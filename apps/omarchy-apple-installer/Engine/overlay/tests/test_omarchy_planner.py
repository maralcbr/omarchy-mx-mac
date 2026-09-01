# SPDX-License-Identifier: MIT
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest


class FakeOSInstaller:
    def __init__(self, dutil, data, template):
        self.min_recommended_size = template["minimum_size"]


sys.modules["osinstall"] = SimpleNamespace(OSInstaller=FakeOSInstaller)
sys.modules["util"] = SimpleNamespace(
    align_down=lambda value, alignment: value // alignment * alignment,
)
sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[1] / "src"),
)

from omarchy_contract import Journal  # noqa: E402
from omarchy_planner import (  # noqa: E402
    PlanningError,
    collect_inventory,
    emit_inventory,
    emit_plan,
)


class PlannerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.journal = Journal(str(self.root / "engine.jsonl"))
        self.journal.inspection("apple,j314s", "supported")
        self.installer = FakeInstaller()
        self.free = [
            SimpleNamespace(
                name="disk0s3",
                offset=447_750_000_000,
                size=100 * 1024**3 + 123,
            )
        ]
        self.resize = [
            SimpleNamespace(
                name="disk0s2",
                offset=1_000_000_000,
                size=500 * 1024**3,
            )
        ]

    def tearDown(self):
        self.temporary.cleanup()

    def test_inventory_uses_asahi_minimums_and_resize_bounds(self):
        inventory = collect_inventory(
            self.installer,
            self.free,
            self.resize,
            stub_size=2 * 1024**3,
            part_align=1024**2,
        )

        self.assertEqual(inventory["system_store_identifier"], "disk0")
        self.assertEqual(len(inventory["candidates"]), 2)
        free, resize = inventory["candidates"]
        self.assertEqual(free["kind"], "resize")
        self.assertEqual(
            free["minimum_install_bytes"],
            66 * 1024**3,
        )
        self.assertEqual(
            free["minimum_container_bytes"],
            320 * 1024**3,
        )
        self.assertEqual(resize["kind"], "free")
        self.assertEqual(resize["length_bytes"], 100 * 1024**3)

    def test_emit_inventory_and_plan_share_one_journal_contract(self):
        inventory = emit_inventory(
            self.installer,
            self.journal,
            self.free,
            [],
            stub_size=2 * 1024**3,
            part_align=1024**2,
        )
        planning_request = {
            "schema_version": 1,
            "layout_digest": inventory["layout_digest"],
            "candidate_kind": "free",
            "source_identifier": "disk0s3",
            "requested_length_bytes": 80 * 1024**3,
        }
        identity = {
            "schema_version": 1,
            "engine_version": "v0.9.0-omarchy.2",
            "engine_digest": "sha256:" + "d" * 64,
            "metadata_digest": "sha256:" + "e" * 64,
            "payload_digest": "sha256:" + "f" * 64,
        }
        request_path = self._write("planning-request.json", planning_request)
        identity_path = self._write("planning-identity.json", identity)

        plan_digest = emit_plan(
            self.journal,
            str(request_path),
            str(identity_path),
            "apple,j314s",
            1024**2,
        )

        self.assertEqual(self.journal.sequence, 3)
        self.assertEqual(
            self.journal.plan_payload["plan_digest"],
            plan_digest,
        )
        self.assertEqual(
            self.journal.plan_payload["length_bytes"],
            80 * 1024**3,
        )

    def test_unknown_planning_field_is_rejected(self):
        inventory = emit_inventory(
            self.installer,
            self.journal,
            self.free,
            [],
            stub_size=2 * 1024**3,
            part_align=1024**2,
        )
        request = {
            "schema_version": 1,
            "layout_digest": inventory["layout_digest"],
            "candidate_kind": "free",
            "source_identifier": "disk0s3",
            "requested_length_bytes": 80 * 1024**3,
            "unexpected": True,
        }
        identity = {
            "schema_version": 1,
            "engine_version": "v0.9.0-omarchy.2",
            "engine_digest": "sha256:" + "d" * 64,
            "metadata_digest": "sha256:" + "e" * 64,
            "payload_digest": "sha256:" + "f" * 64,
        }
        request_path = self._write("planning-request.json", request)
        identity_path = self._write("planning-identity.json", identity)

        with self.assertRaisesRegex(
            PlanningError,
            "unexpected planning request fields",
        ):
            emit_plan(
                self.journal,
                str(request_path),
                str(identity_path),
                "apple,j314s",
                1024**2,
            )

    def test_repair_plan_uses_exact_extent_and_no_reinstall_recovery_step(self):
        candidate = {
            "kind": "repair",
            "source_identifier": "disk0s2",
            "offset_bytes": 857_747_943_424,
            "length_bytes": 137_438_953_472,
            "minimum_install_bytes": 137_438_953_472,
            "minimum_container_bytes": 0,
            "identity_digest": "sha256:" + "9" * 64,
        }
        inventory = self.journal.inventory("disk0", [candidate])
        request_path = self._write(
            "repair-request.json",
            {
                "schema_version": 1,
                "layout_digest": inventory,
                "candidate_kind": "repair",
                "source_identifier": "disk0s2",
                "requested_length_bytes": 137_438_953_472,
            },
        )
        identity_path = self._write(
            "repair-identity.json",
            {
                "schema_version": 1,
                "engine_version": "v0.9.0-omarchy.7",
                "engine_digest": "sha256:" + "d" * 64,
                "metadata_digest": "sha256:" + "e" * 64,
                "payload_digest": "sha256:" + "f" * 64,
                "repair_manifest_digest": "sha256:" + "7" * 64,
            },
        )

        emit_plan(
            self.journal,
            str(request_path),
            str(identity_path),
            "apple,j314s",
            1024**2,
        )

        self.assertEqual(
            self.journal.plan_payload["required_human_steps"],
            ["authenticateMachineOwner"],
        )
        self.assertEqual(
            self.journal.plan_payload["offset_bytes"],
            857_747_943_424,
        )
        self.assertEqual(
            self.journal.plan_payload["repair_manifest_digest"],
            "sha256:" + "7" * 64,
        )

    def test_multiple_omarchy_targets_are_rejected(self):
        self.installer.data["os_list"].append(
            dict(self.installer.data["os_list"][0])
        )

        with self.assertRaisesRegex(
            PlanningError,
            "exactly one Omarchy Apple full-OS target",
        ):
            collect_inventory(
                self.installer,
                self.free,
                [],
                stub_size=2 * 1024**3,
                part_align=1024**2,
            )

    def _write(self, name, value):
        path = self.root / name
        path.write_text(
            json.dumps(value, separators=(",", ":"), sort_keys=True),
            encoding="utf-8",
        )
        path.chmod(0o400)
        return path


class FakeInstaller:
    def __init__(self):
        self.data = {
            "os_list": [
                {
                    "omarchy_target": "apple-silicon-full-os",
                    "minimum_size": 64 * 1024**3,
                }
            ]
        }
        self.dutil = object()
        self.sys_disk = "disk0"

    def get_resize_bounds(self, part):
        return {
            "available_bytes": 180 * 1024**3,
            "minimum_size_bytes": 320 * 1024**3,
        }


if __name__ == "__main__":
    unittest.main()
