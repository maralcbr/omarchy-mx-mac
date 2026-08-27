# SPDX-License-Identifier: MIT
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest
import zipfile


class FakeOSInstaller:
    def __init__(self, dutil, data, template):
        self.min_recommended_size = template["minimum_size"]
        self.name = template["default_os_name"]
        self.needs_firmware = False
        self.idata_targets = []
        self.efi_part = SimpleNamespace(uuid="ABCDEF")
        self.calls = []

    def partition_disk(self, name, size):
        self.calls.append(("partition_disk", name, size))

    def install(self, installer):
        self.calls.append(("install", installer))


class FakeStubInstaller:
    def __init__(self, sysinfo, dutil, osinfo):
        self.calls = []
        self.osi = SimpleNamespace(
            vgid="vgid-1",
            sys_volume="System",
        )

    def load_ipsw(self, ipsw):
        self.calls.append(("load_ipsw", ipsw))

    def prepare_volume(self, part):
        self.calls.append(("prepare_volume", part.name))

    def check_volume(self):
        self.calls.append(("check_volume",))

    def install_files(self, current_os):
        self.calls.append(("install_files", current_os))

    def prepare_for_step2(self):
        self.calls.append(("prepare_for_step2",))


sys.modules["asahi_firmware"] = SimpleNamespace(
    core=SimpleNamespace(FWPackage=object),
)
sys.modules["osinstall"] = SimpleNamespace(OSInstaller=FakeOSInstaller)
sys.modules["stub"] = SimpleNamespace(StubInstaller=FakeStubInstaller)
sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[1] / "src"),
)

from omarchy_asahi import (  # noqa: E402
    AsahiAdapterError,
    AsahiStage1Adapter,
)


GIB = 1024**3


class AsahiStage1AdapterTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.metadata = self.root / "installer_data.json"
        self.payload = self.root / "payload.zip"
        self._write_metadata()
        with zipfile.ZipFile(self.payload, "w") as archive:
            archive.writestr("manifest", "bound payload")
        self.free = FakePart(
            "disk0s3",
            offset=400 * GIB,
            size=100 * GIB,
            free=True,
            part_type="Free space",
        )
        self.plan = SimpleNamespace(
            plan_digest="a" * 64,
            candidate_kind="free",
            source_identifier="disk0s3",
            offset_bytes=self.free.offset,
            length_bytes=80 * GIB,
            minimum_container_bytes=0,
        )

    def tearDown(self):
        self.temporary.cleanup()

    def test_free_extent_runs_exact_upstream_stage_one_primitives(self):
        dutil = FakeDiskUtil([[self.free]])
        installer = FakeInstaller(dutil)
        adapter = self._adapter(installer)

        adapter.preflight(self.plan)
        target_evidence = json.loads(adapter.prepare_target(self.plan))
        installed_evidence = json.loads(
            adapter.install_stub_and_esp(self.plan)
        )
        recovery_evidence = json.loads(
            adapter.prepare_recovery_handoff(self.plan)
        )

        self.assertEqual(installer.chosen_firmware, None)
        self.assertEqual(
            installer.ins.calls[0],
            ("load_ipsw", "ipsw-image"),
        )
        self.assertEqual(
            dutil.add_calls,
            [("disk0s3", "apfs", "Omarchy", 2 * GIB)],
        )
        self.assertEqual(
            target_evidence["partition_identifier"],
            "disk0s4",
        )
        self.assertEqual(installed_evidence["apfs_vgid"], "vgid-1")
        self.assertEqual(installed_evidence["efi_partition"], "abcdef")
        self.assertEqual(
            recovery_evidence["outcome"],
            "awaiting_recovery",
        )
        self.assertIn(("prepare_for_step2",), installer.ins.calls)

    def test_resize_uses_only_approved_container_and_minimum(self):
        source = FakePart(
            "disk0s2",
            offset=1 * GIB,
            size=500 * GIB,
            free=False,
        )
        resized_free = FakePart(
            "disk0s3",
            offset=421 * GIB,
            size=80 * GIB,
            free=True,
            part_type="Free space",
        )
        plan = SimpleNamespace(
            **{
                **self.plan.__dict__,
                "candidate_kind": "resize",
                "source_identifier": "disk0s2",
                "offset_bytes": resized_free.offset,
                "minimum_container_bytes": 320 * GIB,
            }
        )
        dutil = FakeDiskUtil([[source], [resized_free]])
        adapter = self._adapter(FakeInstaller(dutil))

        adapter.preflight(plan)
        adapter.prepare_target(plan)

        self.assertEqual(
            dutil.resize_calls,
            [("disk0s2", 420 * GIB)],
        )
        self.assertEqual(dutil.add_calls[0][0], "disk0s3")

    def test_changed_free_extent_is_rejected_before_partition_creation(self):
        changed = FakePart(
            "disk0s3",
            offset=self.free.offset + GIB,
            size=self.free.size,
            free=True,
            part_type="Free space",
        )
        dutil = FakeDiskUtil([[changed]])
        adapter = self._adapter(FakeInstaller(dutil))
        adapter.preflight(self.plan)

        with self.assertRaisesRegex(
            AsahiAdapterError,
            "approved free extent changed",
        ):
            adapter.prepare_target(self.plan)

        self.assertEqual(dutil.add_calls, [])

    def test_retry_reconciles_the_exact_prepared_apfs_partition(self):
        prepared = FakePart(
            "disk0s4",
            offset=self.plan.offset_bytes,
            size=2 * GIB,
            free=False,
        )
        adapter = self._adapter(FakeInstaller(FakeDiskUtil([[prepared]])))
        adapter.preflight(self.plan)

        evidence = json.loads(adapter.install_stub_and_esp(self.plan))

        self.assertEqual(evidence["plan_digest"], self.plan.plan_digest)
        self.assertIn(("prepare_volume", "disk0s4"), adapter.installer.ins.calls)

    def test_duplicate_target_metadata_is_rejected(self):
        target = self._target_metadata()
        self._write_metadata([target, dict(target)])
        adapter = self._adapter(FakeInstaller(FakeDiskUtil([[self.free]])))

        with self.assertRaisesRegex(
            AsahiAdapterError,
            "exactly one Omarchy target",
        ):
            adapter.preflight(self.plan)

    def test_metadata_symlink_and_unprepared_adapter_are_rejected(self):
        link = self.root / "metadata-link.json"
        link.symlink_to(self.metadata)
        adapter = AsahiStage1Adapter(
            installer=FakeInstaller(FakeDiskUtil([[self.free]])),
            metadata_path=str(link),
            payload_path=str(self.payload),
            stub_size=2 * GIB,
        )
        with self.assertRaisesRegex(
            AsahiAdapterError,
            "metadata is unavailable",
        ):
            adapter.preflight(self.plan)

        fresh = self._adapter(FakeInstaller(FakeDiskUtil([[self.free]])))
        with self.assertRaisesRegex(
            AsahiAdapterError,
            "preflight is required",
        ):
            fresh.prepare_target(self.plan)

    def _adapter(self, installer):
        return AsahiStage1Adapter(
            installer=installer,
            metadata_path=str(self.metadata),
            payload_path=str(self.payload),
            stub_size=2 * GIB,
        )

    def _target_metadata(self):
        return {
            "omarchy_target": "apple-silicon-uefi",
            "minimum_size": 64 * GIB,
            "name": "Omarchy Apple Silicon installer environment",
            "default_os_name": "Omarchy",
            "supported_fw": None,
        }

    def _write_metadata(self, targets=None):
        if targets is None:
            targets = [self._target_metadata()]
        if self.metadata.exists():
            self.metadata.chmod(0o600)
        self.metadata.write_text(
            json.dumps({"os_list": targets}),
            encoding="utf-8",
        )
        self.metadata.chmod(0o400)


class FakePart:
    def __init__(self, name, *, offset, size, free, part_type="Apple_APFS"):
        self.name = name
        self.offset = offset
        self.size = size
        self.free = free
        self.type = part_type
        self.uuid = "PART-UUID"


class FakeDiskUtil:
    def __init__(self, partition_rounds):
        self.partition_rounds = list(partition_rounds)
        self.round = 0
        self.resize_calls = []
        self.add_calls = []

    def get_info(self):
        return None

    def get_partitions(self, disk):
        index = min(self.round, len(self.partition_rounds) - 1)
        self.round += 1
        return self.partition_rounds[index]

    def resizeContainer(self, name, new_size):
        self.resize_calls.append((name, new_size))

    def addPartition(self, name, part_type, label, size):
        self.add_calls.append((name, part_type, label, size))
        source = self.partition_rounds[-1][0]
        return FakePart(
            "disk0s4",
            offset=source.offset,
            size=size,
            free=False,
        )


class FakeInstaller:
    def __init__(self, dutil):
        self.dutil = dutil
        self.sys_disk = "disk0"
        self.sysinfo = object()
        self.osinfo = object()
        self.cur_os = "current-os"
        self.chosen_firmware = "unset"
        self.check_cur_os_calls = 0

    def choose_ipsw(self, supported_firmware):
        self.chosen_firmware = supported_firmware
        return "ipsw-image"

    def check_cur_os(self):
        self.check_cur_os_calls += 1


if __name__ == "__main__":
    unittest.main()
