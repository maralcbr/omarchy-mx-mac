# SPDX-License-Identifier: MIT
import json
from pathlib import Path
import sys
import tempfile
import unittest


sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[1] / "src"),
)

from omarchy_contract import (  # noqa: E402
    ContractError,
    Journal,
    normalize_device_identifier,
)


class ResumableJournalTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.path = self.root / "engine.jsonl"
        self.candidate = {
            "kind": "free",
            "source_identifier": "disk0s3",
            "offset_bytes": 447_750_000_000,
            "length_bytes": 100 * 1024**3,
            "minimum_install_bytes": 64 * 1024**3,
            "minimum_container_bytes": 0,
        }
        self.digests = (
            "sha256:" + "d" * 64,
            "sha256:" + "e" * 64,
            "sha256:" + "f" * 64,
        )

    def tearDown(self):
        self.temporary.cleanup()

    def test_complete_journal_resumes_without_duplicate_records(self):
        journal = self._planned_journal()
        journal.event("apfs_preparation_started")
        journal.checkpoint(
            "apfs-created",
            "apfs_preparation",
            b"disk0s4",
        )
        journal.event("stub_and_esp_started")
        journal.checkpoint(
            "stub-installed",
            "stub_and_esp",
            b"disk0s4|disk0s5",
        )
        journal.checkpoint(
            "recovery-prepared",
            "awaiting_recovery",
            b"vgid",
        )
        journal.completion("awaiting_recovery")
        original = self.path.read_bytes()

        resumed = Journal(str(self.path))
        self._repeat_plan(resumed)
        resumed.event("apfs_preparation_started")
        resumed.checkpoint(
            "apfs-created",
            "apfs_preparation",
            b"disk0s4",
        )
        resumed.completion("awaiting_recovery")

        self.assertEqual(self.path.read_bytes(), original)
        self.assertEqual(resumed.completion_outcome, "awaiting_recovery")
        self.assertTrue(resumed.has_event("stub_and_esp_started"))
        self.assertTrue(resumed.has_checkpoint("awaiting_recovery"))

    def test_changed_plan_is_rejected_during_resume(self):
        journal = self._planned_journal()
        resumed = Journal(str(self.path))
        resumed.inspection("apple,j314s", "supported")
        layout = resumed.inventory("disk0", [self.candidate])

        with self.assertRaisesRegex(
            ContractError,
            "plan changed during resume",
        ):
            resumed.plan(
                device_identifier="apple,j314s",
                layout_digest=layout,
                candidate_kind="free",
                source_identifier="disk0s3",
                requested_length_bytes=81 * 1024**3,
                engine_version="v0.9.0-omarchy.2",
                engine_digest=self.digests[0],
                metadata_digest=self.digests[1],
                payload_digest=self.digests[2],
                required_human_steps=[
                    "enterOneTrueRecovery",
                    "authenticateMachineOwner",
                ],
            )
        self.assertEqual(journal.sequence, 3)

    def test_layout_identity_ignores_dynamic_safety_bound_drift(self):
        first = Journal(str(self.root / "first.jsonl"))
        second = Journal(str(self.root / "second.jsonl"))
        first_candidate = dict(self.candidate)
        first_candidate["kind"] = "resize"
        first_candidate["source_identifier"] = "disk0s2"
        first_candidate["minimum_container_bytes"] = 320 * 1024**3
        second_candidate = dict(first_candidate)
        second_candidate["minimum_install_bytes"] += 1024**2
        second_candidate["minimum_container_bytes"] += 1024**2

        first.inspection("apple,j314s", "supported")
        second.inspection("apple,j314s", "supported")
        first_layout = first.inventory("disk0", [first_candidate])
        second_layout = second.inventory("disk0", [second_candidate])

        self.assertEqual(first_layout, second_layout)

    def test_repair_layout_binds_the_exact_existing_partition_identity(self):
        candidate = {
            "kind": "repair",
            "source_identifier": "disk0s2",
            "offset_bytes": 857_747_943_424,
            "length_bytes": 137_438_953_472,
            "minimum_install_bytes": 137_438_953_472,
            "minimum_container_bytes": 0,
            "identity_digest": "sha256:" + "a" * 64,
        }
        first = Journal(str(self.root / "repair-first.jsonl"))
        second = Journal(str(self.root / "repair-second.jsonl"))
        first.inspection("apple,j314s", "supported")
        second.inspection("apple,j314s", "supported")

        first_layout = first.inventory("disk0", [candidate])
        candidate["identity_digest"] = "sha256:" + "b" * 64
        second_layout = second.inventory("disk0", [candidate])

        self.assertNotEqual(first_layout, second_layout)

    def test_unplanned_resume_uses_conservative_drifted_bounds(self):
        journal = Journal(str(self.path))
        journal.inspection("apple,j314s", "supported")
        candidate = dict(self.candidate)
        candidate["kind"] = "resize"
        candidate["source_identifier"] = "disk0s2"
        candidate["minimum_container_bytes"] = 320 * 1024**3
        layout = journal.inventory("disk0", [candidate])

        resumed = Journal(str(self.path))
        drifted = dict(candidate)
        drifted["minimum_install_bytes"] -= 1024**2
        drifted["minimum_container_bytes"] += 1024**2

        self.assertEqual(resumed.inventory("disk0", [drifted]), layout)
        refreshed = resumed.inventory_payload["candidates"][0]
        self.assertEqual(
            refreshed["minimum_install_bytes"],
            candidate["minimum_install_bytes"],
        )
        self.assertEqual(
            refreshed["minimum_container_bytes"],
            drifted["minimum_container_bytes"],
        )

    def test_checkpoint_phase_regression_is_rejected(self):
        journal = self._planned_journal()
        journal.checkpoint(
            "stub-installed",
            "stub_and_esp",
            b"stub",
        )

        with self.assertRaisesRegex(
            ContractError,
            "checkpoint phase regressed",
        ):
            journal.checkpoint(
                "late-apfs",
                "apfs_preparation",
                b"apfs",
            )

    def test_checkpoint_evidence_round_trips_and_tampering_fails_closed(self):
        journal = self._planned_journal()
        evidence = b'{"partition_identifier":"disk0s4"}'
        journal.checkpoint(
            "apfs-created",
            "apfs_preparation",
            evidence,
        )

        resumed = Journal(str(self.path))
        self.assertEqual(
            resumed.checkpoint_evidence("apfs-created"),
            evidence,
        )
        evidence_path = self.root / "engine.jsonl.apfs-created.evidence"
        evidence_path.chmod(0o600)
        evidence_path.write_bytes(b"changed")
        evidence_path.chmod(0o600)

        with self.assertRaisesRegex(
            ContractError,
            "checkpoint evidence changed",
        ):
            resumed.checkpoint_evidence("apfs-created")

    def test_truncated_journal_is_rejected(self):
        journal = self._planned_journal()
        self.path.write_bytes(self.path.read_bytes()[:-1])

        with self.assertRaisesRegex(ContractError, "truncated journal"):
            Journal(str(self.path))
        self.assertEqual(journal.sequence, 3)

    def test_symlinked_journal_is_rejected(self):
        target = self.root / "target.jsonl"
        target.write_bytes(b"")
        target.chmod(0o600)
        self.path.symlink_to(target)

        with self.assertRaises(OSError):
            Journal(str(self.path))

    def test_unknown_resumed_payload_field_is_rejected(self):
        self._planned_journal()
        records = [
            json.loads(line)
            for line in self.path.read_text(encoding="utf-8").splitlines()
        ]
        records[0]["payload"]["unexpected"] = True
        self.path.write_text(
            "".join(
                json.dumps(record, separators=(",", ":")) + "\n"
                for record in records
            ),
            encoding="utf-8",
        )
        self.path.chmod(0o600)

        with self.assertRaisesRegex(ContractError, "unexpected fields"):
            Journal(str(self.path))

    def test_device_class_normalization_matches_swift_identity(self):
        self.assertEqual(
            normalize_device_identifier("J314sAP"),
            "apple,j314s",
        )
        with self.assertRaisesRegex(
            ContractError,
            "invalid device identifier",
        ):
            normalize_device_identifier("../j314s")

    def _planned_journal(self):
        journal = Journal(str(self.path))
        self._repeat_plan(journal)
        return journal

    def _repeat_plan(self, journal):
        journal.inspection("apple,j314s", "supported")
        layout = journal.inventory("disk0", [self.candidate])
        return journal.plan(
            device_identifier="apple,j314s",
            layout_digest=layout,
            candidate_kind="free",
            source_identifier="disk0s3",
            requested_length_bytes=80 * 1024**3,
            engine_version="v0.9.0-omarchy.2",
            engine_digest=self.digests[0],
            metadata_digest=self.digests[1],
            payload_digest=self.digests[2],
            required_human_steps=[
                "enterOneTrueRecovery",
                "authenticateMachineOwner",
            ],
        )


if __name__ == "__main__":
    unittest.main()
