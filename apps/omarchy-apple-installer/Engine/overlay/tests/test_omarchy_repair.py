# SPDX-License-Identifier: MIT
import hashlib
import io
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest


sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[1] / "src"),
)

from omarchy_repair import (  # noqa: E402
    AmbiguousRepairState,
    InPlaceRepairError,
    RepairExecutor,
    collect_repair_inventory,
    inspect_filesystem_identity,
    read_filesystem_identity,
    retry_repair_boot_policy_authorization,
    run_repair,
)


class AlignedRawStream(io.BytesIO):
    def seek(self, offset, whence=io.SEEK_SET):
        if whence == io.SEEK_SET and offset % 4096:
            raise OSError(22, "Invalid argument")
        return super().seek(offset, whence)

    def read(self, size=-1):
        if size > 0 and size % 4096:
            raise OSError(22, "Invalid argument")
        return super().read(size)


class InPlaceRepairContractTests(unittest.TestCase):
    def setUp(self):
        self.parts = [
            self._part(
                "disk0s2",
                524_312_576,
                857_223_630_848,
                "1EDFBFBF-3123-4142-BF27-A7215B874733",
                "Apple_APFS",
            ),
            self._part(
                "disk0s3",
                857_747_943_424,
                2_499_805_184,
                "0FB80EDB-92E4-4C26-8B34-227FF4503576",
                "Apple_APFS",
            ),
            self._part(
                "disk0s4",
                860_247_748_608,
                524_288_000,
                "319EF3D8-7176-4D33-9851-6A0144328E1C",
                "EFI",
            ),
            self._part(
                "disk0s5",
                860_772_036_608,
                2_147_483_648,
                "7620A7B4-8548-46FD-8EC5-847AA15C2DA3",
                "Linux Filesystem",
            ),
            self._part(
                "disk0s6",
                862_919_520_256,
                132_267_376_640,
                "76D01F38-70E2-4CB5-81FC-A9B41D2D479A",
                "Linux Filesystem",
            ),
        ]
        self.manifest = self._manifest()

    def test_exact_existing_layout_produces_one_repair_candidate(self):
        inventory = collect_repair_inventory(
            SimpleNamespace(sys_disk="disk0", parts=self.parts),
            self.manifest,
            disk_identity_reader=lambda _: "sha256:" + "5" * 64,
            filesystem_identity_reader=self._filesystem_identity,
        )

        self.assertEqual(inventory["system_store_identifier"], "disk0")
        self.assertEqual(len(inventory["candidates"]), 1)
        candidate = inventory["candidates"][0]
        self.assertEqual(candidate["kind"], "repair")
        self.assertEqual(candidate["source_identifier"], "disk0s2")
        self.assertEqual(candidate["offset_bytes"], 857_747_943_424)
        self.assertEqual(candidate["length_bytes"], 137_438_953_472)
        self.assertRegex(candidate["identity_digest"], r"^sha256:[0-9a-f]{64}$")

    def test_release_and_canary_share_the_concrete_repair_executor_adapter(self):
        plan = SimpleNamespace(plan_digest="a" * 64)
        release_adapter = FakeRepairAdapter()
        canary_adapter = release_adapter

        release_executor = RepairExecutor(release_adapter)
        canary_executor = RepairExecutor(canary_adapter)

        self.assertIs(release_executor.adapter, canary_executor.adapter)
        self.assertEqual(
            release_executor.apply(plan, FakeJournal()),
            "installed",
        )
        self.assertEqual(
            canary_executor.apply(plan, FakeJournal()),
            "installed",
        )

    def test_any_partition_mismatch_fails_before_a_repair_candidate_exists(self):
        self.parts[-1].size -= 4096

        with self.assertRaisesRegex(
            InPlaceRepairError,
            "partition identity changed",
        ):
            collect_repair_inventory(
                SimpleNamespace(sys_disk="disk0", parts=self.parts),
                self.manifest,
                disk_identity_reader=lambda _: "sha256:" + "5" * 64,
                filesystem_identity_reader=self._filesystem_identity,
            )

    def test_disk_identity_mismatch_fails_closed(self):
        with self.assertRaisesRegex(
            InPlaceRepairError,
            "disk identity changed",
        ):
            collect_repair_inventory(
                SimpleNamespace(sys_disk="disk0", parts=self.parts),
                self.manifest,
                disk_identity_reader=lambda _: "sha256:" + "6" * 64,
                filesystem_identity_reader=self._filesystem_identity,
            )

    def test_unsigned_repair_content_semantics_are_rejected(self):
        self.manifest["existing_content"] = {}

        with self.assertRaisesRegex(
            InPlaceRepairError,
            "invalid repair content",
        ):
            collect_repair_inventory(
                SimpleNamespace(sys_disk="disk0", parts=self.parts),
                self.manifest,
                disk_identity_reader=lambda _: "sha256:" + "5" * 64,
                filesystem_identity_reader=self._filesystem_identity,
            )

    def test_ext4_and_btrfs_superblocks_are_read_without_mounting(self):
        ext4 = bytearray(4096)
        ext4[1024 + 0x38 : 1024 + 0x3A] = b"\x53\xef"
        ext4[1024 + 0x68 : 1024 + 0x78] = bytes.fromhex(
            "4f4d5801424f4f548000000000000001"
        )
        ext4[1024 + 0x78 : 1024 + 0x84] = b"OMARCHY_BOOT"

        btrfs = bytearray(0x11000)
        btrfs[0x10000 + 0x20 : 0x10000 + 0x30] = bytes.fromhex(
            "4f4d5801524f4f548000000000000001"
        )
        btrfs[0x10000 + 0x40 : 0x10000 + 0x48] = b"_BHRfS_M"
        btrfs[0x10000 + 0x12B : 0x10000 + 0x137] = b"OMARCHY_ROOT"

        self.assertEqual(
            read_filesystem_identity(io.BytesIO(ext4)),
            {
                "type": "ext4",
                "uuid": "4f4d5801-424f-4f54-8000-000000000001",
                "label": "OMARCHY_BOOT",
            },
        )
        self.assertEqual(
            read_filesystem_identity(io.BytesIO(btrfs)),
            {
                "type": "btrfs",
                "uuid": "4f4d5801-524f-4f54-8000-000000000001",
                "label": "OMARCHY_ROOT",
            },
        )

    def test_raw_filesystem_identity_reads_are_block_aligned(self):
        efi = bytearray(4096)
        efi[510:512] = b"\x55\xaa"
        efi[67:71] = (0x4F4D5801).to_bytes(4, "little")
        efi[71:82] = b"EFI - OMARC"
        self.assertEqual(
            inspect_filesystem_identity(
                SimpleNamespace(
                    name="disk0s4",
                    type="EFI",
                    uuid="319ef3d8-7176-4d33-9851-6a0144328e1c",
                    label=None,
                ),
                raw_partition_opener=lambda _: AlignedRawStream(efi),
            ),
            {"type": "fat32", "uuid": "4f4d-5801", "label": "EFI - OMARC"},
        )

        ext4 = bytearray(4096)
        ext4[1024 + 0x38 : 1024 + 0x3A] = b"\x53\xef"
        ext4[1024 + 0x68 : 1024 + 0x78] = bytes.fromhex(
            "4f4d5801424f4f548000000000000001"
        )
        ext4[1024 + 0x78 : 1024 + 0x84] = b"OMARCHY_BOOT"
        self.assertEqual(
            read_filesystem_identity(AlignedRawStream(ext4)),
            {
                "type": "ext4",
                "uuid": "4f4d5801-424f-4f54-8000-000000000001",
                "label": "OMARCHY_BOOT",
            },
        )

    def test_repair_sequence_never_calls_install_or_partition_primitives(self):
        journal = FakeJournal()
        adapter = FakeRepairAdapter()
        plan = SimpleNamespace(plan_digest="a" * 64)

        outcome = run_repair(plan, journal, adapter)

        self.assertEqual(outcome, "installed")
        self.assertEqual(
            adapter.calls,
            [
                "validate_existing_install",
                "rewrite_existing_content",
                "validate_repaired_content",
                "authorize_existing_boot_policy",
            ],
        )
        self.assertNotIn("resize", adapter.calls)
        self.assertNotIn("partition", adapter.calls)
        self.assertNotIn("install", adapter.calls)

    def test_started_write_without_checkpoint_is_never_replayed(self):
        journal = FakeJournal(events={"repair_content_write_started"})

        with self.assertRaises(AmbiguousRepairState):
            run_repair(
                SimpleNamespace(plan_digest="a" * 64),
                journal,
                FakeRepairAdapter(),
            )

    def test_boot_policy_retry_revalidates_but_never_rewrites_content(self):
        journal = FakeJournal(
            events={
                "existing_install_validation_started",
                "repair_content_write_started",
                "repair_readback_validation_started",
                "repair_boot_policy_authorization_started",
            }
        )
        journal.checkpoints = {
            "existing-install-validated": {},
            "repair-content-written": {},
            "repair-content-validated": {},
        }
        adapter = FakeRepairAdapter()

        outcome = retry_repair_boot_policy_authorization(
            SimpleNamespace(plan_digest="a" * 64),
            journal,
            adapter,
        )

        self.assertEqual(outcome, "installed")
        self.assertEqual(
            adapter.calls,
            [
                "validate_repaired_content",
                "authorize_existing_boot_policy",
            ],
        )
        self.assertNotIn("rewrite_existing_content", adapter.calls)

    def _filesystem_identity(self, part):
        values = {
            "disk0s3": {
                "type": "apfs",
                "uuid": "0fb80edb-92e4-4c26-8b34-227ff4503576",
                "label": "Omarchy",
            },
            "disk0s4": {
                "type": "fat32",
                "uuid": "4f4d-5801",
                "label": "EFI - OMARC",
            },
            "disk0s5": {
                "type": "ext4",
                "uuid": "4f4d5801-424f-4f54-8000-000000000001",
                "label": "OMARCHY_BOOT",
            },
            "disk0s6": {
                "type": "btrfs",
                "uuid": "4f4d5801-524f-4f54-8000-000000000001",
                "label": "OMARCHY_ROOT",
            },
        }
        name = part if isinstance(part, str) else part.name
        return values[name]

    @staticmethod
    def _part(name, offset, size, uuid, part_type):
        return SimpleNamespace(
            name=name,
            offset=offset,
            size=size,
            uuid=uuid,
            type=part_type,
            free=False,
        )

    def _manifest(self):
        return {
            "schema_version": 1,
            "operation": "repair-installed-system",
            "repair_id": "m1-v5-switch-root-branding",
            "device_identifier": "apple,j314s",
            "store_identifier": "disk0",
            "disk_identity": "sha256:" + "5" * 64,
            "approved_extent": {
                "source_identifier": "disk0s2",
                "offset_bytes": 857_747_943_424,
                "length_bytes": 137_438_953_472,
            },
            "partitions": [
                {
                    "role": "stub",
                    "identifier": "disk0s3",
                    "partition_uuid": "0fb80edb-92e4-4c26-8b34-227ff4503576",
                    "offset_bytes": 857_747_943_424,
                    "size_bytes": 2_499_805_184,
                    "partition_type": "Apple_APFS",
                    "filesystem": self._filesystem_identity("disk0s3"),
                },
                {
                    "role": "efi",
                    "identifier": "disk0s4",
                    "partition_uuid": "319ef3d8-7176-4d33-9851-6a0144328e1c",
                    "offset_bytes": 860_247_748_608,
                    "size_bytes": 524_288_000,
                    "partition_type": "EFI",
                    "filesystem": self._filesystem_identity("disk0s4"),
                },
                {
                    "role": "boot",
                    "identifier": "disk0s5",
                    "partition_uuid": "7620a7b4-8548-46fd-8ec5-847aa15c2da3",
                    "offset_bytes": 860_772_036_608,
                    "size_bytes": 2_147_483_648,
                    "partition_type": "Linux Filesystem",
                    "filesystem": self._filesystem_identity("disk0s5"),
                },
                {
                    "role": "root",
                    "identifier": "disk0s6",
                    "partition_uuid": "76d01f38-70e2-4cb5-81fc-a9b41d2d479a",
                    "offset_bytes": 862_919_520_256,
                    "size_bytes": 132_267_376_640,
                    "partition_type": "Linux Filesystem",
                    "filesystem": self._filesystem_identity("disk0s6"),
                },
            ],
            "existing_content": self._content_identities(),
            "replacement_content": {
                role: {
                    **identity,
                    "payload_member": (
                        f"repair/{role}.img"
                        if role in {"boot", "root"}
                        else None
                    ),
                }
                for role, identity in self._content_identities().items()
            },
            "semantic_contract": {
                "partitioning": "forbidden",
                "readback": "exhaustive",
                "boot_policy_retry": "checkpoint-bound",
            },
        }

    @staticmethod
    def _content_identities():
        return {
            role: {
                "size_bytes": 4096,
                "sha256": "sha256:" + digest * 64,
            }
            for role, digest in zip(
                ("stub", "efi", "boot", "root"),
                ("1", "2", "3", "4"),
                strict=True,
            )
        }


class FakeJournal:
    def __init__(self, events=None):
        self.plan_digest = "a" * 64
        self.events = set(events or ())
        self.checkpoints = {}
        self.completion_outcome = None

    def has_event(self, name):
        return name in self.events

    def event(self, name):
        self.events.add(name)

    def checkpoint(self, identifier, phase, evidence):
        self.checkpoints[identifier] = {
            "phase": phase,
            "evidence_digest": "sha256:"
            + hashlib.sha256(evidence).hexdigest(),
        }

    def completion(self, outcome):
        self.completion_outcome = outcome


class FakeRepairAdapter:
    def __init__(self):
        self.calls = []

    def __getattr__(self, name):
        def operation(_):
            self.calls.append(name)
            return name.encode("utf-8")

        return operation


if __name__ == "__main__":
    unittest.main()
