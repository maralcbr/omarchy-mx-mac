# SPDX-License-Identifier: MIT
"""Existing-install detection and the replace candidate contract."""

import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest


class FakeOSInstaller:
    def __init__(self, dutil, data, template):
        self.min_recommended_size = template["minimum_size"]
        self.name = template.get("default_os_name", "Omarchy")


sys.modules.setdefault(
    "osinstall", SimpleNamespace(OSInstaller=FakeOSInstaller)
)
sys.modules.setdefault(
    "util",
    SimpleNamespace(
        align_down=lambda value, alignment: value // alignment * alignment
    ),
)
sys.modules.setdefault("stub", SimpleNamespace(StubInstaller=object))
sys.modules.setdefault(
    "asahi_firmware", SimpleNamespace(core=SimpleNamespace(FWPackage=object))
)
sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[1] / "src"),
)

import omarchy_asahi  # noqa: E402
import omarchy_execution  # noqa: E402
import omarchy_stage1  # noqa: E402
from omarchy_contract import ContractError, Journal  # noqa: E402
from omarchy_planner import (  # noqa: E402
    PlanningError,
    collect_existing_installs,
    collect_inventory,
    emit_plan,
    replace_identity_digest,
)


GIB = 1024**3
MIB = 1024**2
STUB_SIZE = 2 * GIB
ALIGN = MIB


def part(name, offset, size, *, type=None, label=None, uuid=None, free=False,
         os=None, container=None):
    return SimpleNamespace(
        name=name,
        offset=offset,
        size=size,
        type=type,
        label=label,
        uuid=uuid,
        free=free,
        os=os,
        container=container,
    )


def stub_os(label="Omarchy", vgid="VGID-1"):
    return SimpleNamespace(stub=True, label=label, vgid=vgid)


def existing_install_parts(start=500 * GIB):
    stub_part = part(
        "disk0s3", start, 5 * MIB * 100,  # 500 MiB stub store
        type="Apple_APFS", uuid="UUID-STUB",
        os=[stub_os()],
        container={"ContainerReference": "disk4"},
    )
    esp = part(
        "disk0s4", stub_part.offset + stub_part.size, 500 * MIB,
        type="Microsoft Basic Data", label="EFI - OMARC", uuid="UUID-ESP",
    )
    boot = part(
        "disk0s5", esp.offset + esp.size, 2 * GIB,
        type="Linux Filesystem", uuid="UUID-BOOT",
    )
    root = part(
        "disk0s6", boot.offset + boot.size, 120 * GIB,
        type="Linux Filesystem", uuid="UUID-ROOT",
    )
    return [stub_part, esp, boot, root]


class FakeInstaller:
    def __init__(self, parts):
        self.data = {
            "os_list": [
                {
                    "omarchy_target": "apple-silicon-full-os",
                    "minimum_size": 64 * GIB,
                    "default_os_name": "Omarchy",
                }
            ]
        }
        self.dutil = object()
        self.sys_disk = "disk0"
        self.parts = parts

    def get_resize_bounds(self, unused):
        return {
            "available_bytes": 0,
            "minimum_size_bytes": 1,
        }


class DetectionTests(unittest.TestCase):
    def test_complete_existing_install_becomes_a_replace_candidate(self):
        members = existing_install_parts()
        installer = FakeInstaller(members)
        inventory = collect_inventory(installer, [], [], STUB_SIZE, ALIGN)
        replace = [
            candidate
            for candidate in inventory["candidates"]
            if candidate["kind"] == "replace"
        ]
        self.assertEqual(len(replace), 1)
        candidate = replace[0]
        span = members[-1].offset + members[-1].size - members[0].offset
        self.assertEqual(candidate["source_identifier"], "disk0s3")
        self.assertEqual(candidate["offset_bytes"], members[0].offset)
        self.assertEqual(candidate["length_bytes"], span // ALIGN * ALIGN)
        self.assertEqual(candidate["minimum_container_bytes"], 0)
        self.assertEqual(
            candidate["minimum_install_bytes"], STUB_SIZE + 64 * GIB
        )
        self.assertEqual(
            candidate["identity_digest"],
            replace_identity_digest(members, "Omarchy", "VGID-1"),
        )

    def test_adjacent_free_rows_are_absorbed_into_the_extent(self):
        members = existing_install_parts()
        leading = part(
            "disk0s2", members[0].offset - 64 * MIB, 64 * MIB, free=True
        )
        trailing = part(
            "disk0s6",
            members[-1].offset + members[-1].size,
            32 * MIB,
            free=True,
        )
        installer = FakeInstaller([leading, *members, trailing])
        candidates = collect_existing_installs(
            installer, "Omarchy", STUB_SIZE, ALIGN
        )
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0]["offset_bytes"], leading.offset)
        self.assertEqual(
            candidates[0]["length_bytes"],
            trailing.offset + trailing.size - leading.offset,
        )

    def test_partial_or_mislabeled_groups_are_never_offered(self):
        members = existing_install_parts()

        wrong_esp = [SimpleNamespace(**vars(item)) for item in members]
        wrong_esp[1].label = "EFI"
        self.assertEqual(
            collect_existing_installs(
                FakeInstaller(wrong_esp), "Omarchy", STUB_SIZE, ALIGN
            ),
            [],
        )

        truncated = members[:3]
        self.assertEqual(
            collect_existing_installs(
                FakeInstaller(truncated), "Omarchy", STUB_SIZE, ALIGN
            ),
            [],
        )

        missing_uuid = [SimpleNamespace(**vars(item)) for item in members]
        missing_uuid[2].uuid = None
        self.assertEqual(
            collect_existing_installs(
                FakeInstaller(missing_uuid), "Omarchy", STUB_SIZE, ALIGN
            ),
            [],
        )

        wrong_label = [SimpleNamespace(**vars(item)) for item in members]
        wrong_label[0].os = [stub_os(label="Asahi Linux")]
        self.assertEqual(
            collect_existing_installs(
                FakeInstaller(wrong_label), "Omarchy", STUB_SIZE, ALIGN
            ),
            [],
        )

        no_name = collect_existing_installs(
            FakeInstaller(members), None, STUB_SIZE, ALIGN
        )
        self.assertEqual(no_name, [])

    def test_two_installs_yield_two_candidates(self):
        first = existing_install_parts(start=500 * GIB)
        second = existing_install_parts(start=700 * GIB)
        for index, item in enumerate(second):
            item.name = f"disk0s{7 + index}"
            item.uuid += "-B"
        installer = FakeInstaller(first + second)
        candidates = collect_existing_installs(
            installer, "Omarchy", STUB_SIZE, ALIGN
        )
        self.assertEqual(
            [candidate["source_identifier"] for candidate in candidates],
            ["disk0s3", "disk0s7"],
        )
        self.assertNotEqual(
            candidates[0]["identity_digest"],
            candidates[1]["identity_digest"],
        )


class ReplacePlanTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.journal = Journal(str(self.root / "engine.jsonl"))
        self.journal.inspection("apple,j314s", "supported")
        self.installer = FakeInstaller(existing_install_parts())
        inventory = collect_inventory(self.installer, [], [], STUB_SIZE, ALIGN)
        self.journal.inventory(
            inventory["system_store_identifier"], inventory["candidates"]
        )
        self.candidate = self.journal.inventory_payload["candidates"][0]

    def tearDown(self):
        self.temporary.cleanup()

    def _write(self, name, value):
        path = self.root / name
        path.write_text(
            json.dumps(value, separators=(",", ":"), sort_keys=True),
            encoding="utf-8",
        )
        path.chmod(0o400)
        return path

    def _plan(self, requested):
        request = self._write(
            f"request-{requested}.json",
            {
                "schema_version": 1,
                "layout_digest": self.journal.inventory_payload[
                    "layout_digest"
                ],
                "candidate_kind": "replace",
                "source_identifier": "disk0s3",
                "requested_length_bytes": requested,
            },
        )
        identity = self._write(
            f"identity-{requested}.json",
            {
                "schema_version": 1,
                "engine_version": "v0.9.0-omarchy.7",
                "engine_digest": "sha256:" + "1" * 64,
                "metadata_digest": "sha256:" + "2" * 64,
                "payload_digest": "sha256:" + "3" * 64,
            },
        )
        return emit_plan(
            self.journal,
            str(request),
            str(identity),
            "apple,j314s",
            ALIGN,
        )

    def test_replace_plan_uses_the_exact_extent_and_full_human_steps(self):
        digest = self._plan(self.candidate["length_bytes"])
        plan = self.journal.plan_payload
        self.assertEqual(plan["plan_digest"], digest)
        self.assertEqual(plan["candidate_kind"], "replace")
        self.assertEqual(plan["offset_bytes"], self.candidate["offset_bytes"])
        self.assertEqual(plan["length_bytes"], self.candidate["length_bytes"])
        self.assertNotIn("repair_manifest_digest", plan)
        self.assertEqual(
            plan["required_human_steps"],
            ["enterOneTrueRecovery", "authenticateMachineOwner"],
        )

    def test_replace_plan_rejects_a_shrunken_extent(self):
        with self.assertRaisesRegex(
            ContractError, "replace requires the exact existing extent"
        ):
            self._plan(self.candidate["length_bytes"] - ALIGN)

    def test_replace_identity_binds_the_layout_digest(self):
        altered = dict(self.candidate)
        altered["identity_digest"] = "sha256:" + "f" * 64
        from omarchy_contract import normalized_inventory

        original = normalized_inventory("disk0", [self.candidate])
        forged = normalized_inventory("disk0", [altered])
        self.assertNotEqual(
            original["layout_digest"], forged["layout_digest"]
        )


class ReplaceAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        installer = FakeInstaller(existing_install_parts())
        inventory = collect_inventory(installer, [], [], STUB_SIZE, ALIGN)
        from omarchy_contract import normalized_inventory

        self.inventory = normalized_inventory(
            inventory["system_store_identifier"], inventory["candidates"]
        )
        self.candidate = self.inventory["candidates"][0]

    def tearDown(self):
        self.temporary.cleanup()

    def _write(self, name, value):
        path = self.root / name
        path.write_text(
            json.dumps(value, separators=(",", ":"), sort_keys=True),
            encoding="utf-8",
        )
        path.chmod(0o400)
        return str(path)

    def _admit(self, *, requested=None, operation="install"):
        requested = (
            self.candidate["length_bytes"] if requested is None else requested
        )
        request = {
            "format": 1,
            "operation": operation,
            "plan_digest": "",
            "device_identifier": "apple,j314s",
            "store_identifier": "disk0",
            "layout_digest": self.inventory["layout_digest"],
            "candidate_kind": "replace",
            "source_identifier": "disk0s3",
            "offset_bytes": self.candidate["offset_bytes"],
            "length_bytes": requested,
            "engine_version": "v0.9.0-omarchy.7",
            "required_human_steps": [
                "enterOneTrueRecovery",
                "authenticateMachineOwner",
            ],
        }
        identity = {
            "format": 1,
            "binding_digest": "sha256:" + "a" * 64,
            "trust_root_fingerprint": "sha256:" + "b" * 64,
            "catalog_sequence": 1_787_910_668,
            "catalog_payload_digest": "sha256:" + "c" * 64,
            "plan_digest": "",
            "engine_digest": "sha256:" + "1" * 64,
            "metadata_digest": "sha256:" + "2" * 64,
            "payload_digest": "sha256:" + "3" * 64,
        }
        if operation == "install":
            digest = omarchy_execution._canonical_plan_digest(
                request, identity
            )
        else:
            digest = "0" * 64
        request["plan_digest"] = digest
        identity["plan_digest"] = digest
        return omarchy_execution.admit_execution(
            request_path=self._write("request.json", request),
            identity_path=self._write("identity.json", identity),
            live_inventory=self.inventory,
            expected_binding_digest=identity["binding_digest"],
            expected_plan_digest=digest,
        )

    def test_replace_admits_under_the_install_operation(self):
        plan = self._admit()
        self.assertEqual(plan.operation, "install")
        self.assertEqual(plan.candidate_kind, "replace")
        self.assertEqual(
            plan.candidate_identity_digest,
            self.candidate["identity_digest"],
        )
        self.assertIsNone(plan.repair_manifest_digest)

    def test_replace_rejects_a_changed_extent(self):
        with self.assertRaisesRegex(
            omarchy_execution.ExecutionAdmissionError,
            "approved extent changed",
        ):
            self._admit(requested=self.candidate["length_bytes"] - ALIGN)

    def test_replace_rejects_the_repair_operation(self):
        with self.assertRaisesRegex(
            omarchy_execution.ExecutionAdmissionError,
            "unexpected identity fields|invalid request",
        ):
            self._admit(operation="repair-installed-system")


class ReplaceStageSequenceTests(unittest.TestCase):
    def _plan(self, kind):
        return SimpleNamespace(candidate_kind=kind, plan_digest="0" * 64)

    def _journal(self):
        journal = SimpleNamespace(
            plan_digest="0" * 64,
            completion_outcome=None,
            events=set(),
            checkpoints={},
            recorded=[],
        )

        def has_event(name):
            return name in journal.events

        def event(name):
            journal.events.add(name)
            journal.recorded.append(("event", name))

        def checkpoint(identifier, phase, evidence):
            journal.checkpoints[identifier] = phase
            journal.recorded.append(("checkpoint", identifier))

        def completion(outcome):
            journal.completion_outcome = outcome
            journal.recorded.append(("completion", outcome))

        journal.has_event = has_event
        journal.event = event
        journal.checkpoint = checkpoint
        journal.completion = completion
        return journal

    def test_replace_runs_removal_before_every_other_stage(self):
        calls = []

        class Adapter:
            def remove_existing_install(self, plan):
                calls.append("remove_existing_install")
                return b"removed"

            def prepare_target(self, plan):
                calls.append("prepare_target")
                return b"prepared"

            def install_stub_and_esp(self, plan):
                calls.append("install_stub_and_esp")
                return b"installed"

            def prepare_recovery_handoff(self, plan):
                calls.append("prepare_recovery_handoff")
                return b"handoff"

        outcome = omarchy_stage1.run_stage1(
            self._plan("replace"), self._journal(), Adapter()
        )
        self.assertEqual(outcome, "awaiting_recovery")
        self.assertEqual(
            calls,
            [
                "remove_existing_install",
                "prepare_target",
                "install_stub_and_esp",
                "prepare_recovery_handoff",
            ],
        )

    def test_free_plans_never_touch_the_removal_stage(self):
        calls = []

        class Adapter:
            def remove_existing_install(self, plan):
                calls.append("remove_existing_install")
                return b"removed"

            def prepare_target(self, plan):
                calls.append("prepare_target")
                return b"prepared"

            def install_stub_and_esp(self, plan):
                calls.append("install_stub_and_esp")
                return b"installed"

            def prepare_recovery_handoff(self, plan):
                calls.append("prepare_recovery_handoff")
                return b"handoff"

        omarchy_stage1.run_stage1(
            self._plan("free"), self._journal(), Adapter()
        )
        self.assertNotIn("remove_existing_install", calls)

    def test_interrupted_removal_is_ambiguous_and_never_replayed(self):
        journal = self._journal()
        journal.events.add("existing_removal_started")
        with self.assertRaises(omarchy_stage1.AmbiguousMutationState):
            omarchy_stage1.validate_stage1_resume(
                self._plan("replace"), journal
            )


class RemoveExistingInstallTests(unittest.TestCase):
    def _adapter_and_plan(self):
        members = existing_install_parts()
        installer = FakeInstaller(members)
        actions = []

        class FakeDutil:
            def action(self, *args, verbose=False):
                actions.append(args)

            def get_info(self):
                pass

            def get_partitions(self, disk):
                span_start = members[0].offset
                span_end = members[-1].offset + members[-1].size
                return [
                    part(
                        "disk0s2",
                        span_start,
                        span_end - span_start,
                        free=True,
                    )
                ]

        installer.dutil = FakeDutil()
        installer.check_cur_os = lambda: None
        adapter = omarchy_asahi.AsahiStage1Adapter(
            installer=installer,
            metadata_path="unused",
            payload_path="unused",
            stub_size=STUB_SIZE,
        )
        adapter.preflight_complete = True
        adapter.template = installer.data["os_list"][0]
        span = members[-1].offset + members[-1].size - members[0].offset
        plan = SimpleNamespace(
            candidate_kind="replace",
            source_identifier="disk0s3",
            offset_bytes=members[0].offset,
            length_bytes=span // ALIGN * ALIGN,
            minimum_install_bytes=STUB_SIZE + 64 * GIB,
            candidate_identity_digest=replace_identity_digest(
                members, "Omarchy", "VGID-1"
            ),
            plan_digest="d" * 64,
        )
        return adapter, plan, actions, members

    def test_removal_erases_by_uuid_and_verifies_the_freed_extent(self):
        adapter, plan, actions, members = self._adapter_and_plan()
        evidence = json.loads(adapter.remove_existing_install(plan))
        self.assertEqual(
            actions[0], ("apfs", "deleteContainer", "disk4")
        )
        erased = [action[3] for action in actions[1:]]
        self.assertEqual(
            erased, ["UUID-STUB", "UUID-ESP", "UUID-BOOT", "UUID-ROOT"]
        )
        self.assertEqual(evidence["plan_digest"], plan.plan_digest)
        self.assertEqual(len(evidence["removed"]), 4)
        self.assertEqual(
            evidence["free_offset_bytes"], members[0].offset
        )

    def test_removal_refuses_a_drifted_identity(self):
        adapter, plan, actions, members = self._adapter_and_plan()
        members[3].uuid = "UUID-ROOT-CHANGED"
        with self.assertRaisesRegex(
            omarchy_asahi.AsahiAdapterError,
            "approved existing install changed",
        ):
            adapter.remove_existing_install(plan)
        self.assertEqual(actions, [])

    def test_removal_refuses_non_replace_plans(self):
        adapter, plan, actions, unused = self._adapter_and_plan()
        plan.candidate_kind = "free"
        with self.assertRaisesRegex(
            omarchy_asahi.AsahiAdapterError,
            "removal requires a replace candidate",
        ):
            adapter.remove_existing_install(plan)
        self.assertEqual(actions, [])


if __name__ == "__main__":
    unittest.main()
