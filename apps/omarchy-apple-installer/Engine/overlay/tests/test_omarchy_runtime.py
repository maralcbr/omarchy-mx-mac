# SPDX-License-Identifier: MIT
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
import sys
import tempfile
import unittest


sys.modules.setdefault(
    "asahi_firmware",
    SimpleNamespace(core=SimpleNamespace(FWPackage=object)),
)
sys.modules.setdefault("osinstall", SimpleNamespace(OSInstaller=object))
sys.modules.setdefault("stub", SimpleNamespace(StubInstaller=object))
sys.modules.setdefault(
    "util",
    SimpleNamespace(align_down=lambda value, alignment: value),
)

from omarchy_contract import Journal
from omarchy_execution import ExecutionAdmissionError
from omarchy_runtime import EngineRuntime, EngineRuntimeError


class EngineRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.journal_path = self.root / "engine.jsonl"
        self.inventory = {
            "system_store_identifier": "disk0",
            "candidates": [
                {
                    "kind": "free",
                    "source_identifier": "disk0s3",
                    "offset_bytes": 400_000_000_000,
                    "length_bytes": 100_000_000_000,
                    "minimum_install_bytes": 40_000_000_000,
                    "minimum_container_bytes": 0,
                }
            ],
        }
        self.plan = self._build_plan(self.inventory)

    def tearDown(self):
        self.temporary.cleanup()

    def test_no_engine_environment_returns_none(self):
        self.assertIsNone(EngineRuntime.from_environment({}))

        with self.assertRaisesRegex(
            EngineRuntimeError,
            "engine mode is missing",
        ):
            EngineRuntime.from_environment(
                {"OMARCHY_ENGINE_JOURNAL": str(self.journal_path)}
            )

    def test_install_requires_the_complete_helper_environment(self):
        with self.assertRaisesRegex(
            EngineRuntimeError,
            "OMARCHY_ENGINE_BINDING_DIGEST",
        ):
            EngineRuntime.from_environment(
                {
                    "OMARCHY_ENGINE_MODE": "install",
                    "OMARCHY_ENGINE_JOURNAL": str(self.journal_path),
                }
            )

    def test_install_requires_owner_and_recovery_branding(self):
        for key in (
            "OMARCHY_MACHINE_OWNER",
            "DISTRO",
            "DISTRO_DOCS",
        ):
            environment = self._install_environment()
            del environment[key]
            with self.subTest(key=key), self.assertRaisesRegex(
                EngineRuntimeError,
                key,
            ):
                EngineRuntime.from_environment(environment)

    def test_fresh_install_records_admitted_plan_then_runs_adapter(self):
        runtime = EngineRuntime.from_environment(self._install_environment())
        runtime.inspect("j314sap", True)
        adapter = Mock()
        adapter.preflight = Mock()

        with patch(
            "omarchy_runtime.omarchy_planner.collect_inventory",
            return_value=self.inventory,
        ), patch(
            "omarchy_runtime.omarchy_execution.admit_execution",
            return_value=self.plan,
        ), patch(
            "omarchy_runtime.omarchy_asahi.AsahiStage1Adapter",
            return_value=adapter,
        ), patch(
            "omarchy_runtime.omarchy_stage1.run_stage1",
            return_value="awaiting_recovery",
        ) as run_stage1:
            outcome = self._run_layout(runtime)

        self.assertEqual(outcome, "awaiting_recovery")
        self.assertEqual(runtime.journal.plan_digest, self.plan.plan_digest)
        adapter.preflight.assert_called_once_with(self.plan)
        run_stage1.assert_called_once_with(
            self.plan,
            runtime.journal,
            adapter,
        )

    def test_pre_mutation_resume_admits_against_fresh_safety_bounds(self):
        self._seed_plan(self.journal_path, self.inventory, self.plan)
        self._write_execution_inputs()
        runtime = EngineRuntime.from_environment(self._install_environment())
        runtime.inspect("j314sap", True)
        changed = self._copy_inventory()
        changed["candidates"][0]["minimum_install_bytes"] += 1_000_000
        adapter = Mock()
        adapter.preflight = Mock()

        with patch(
            "omarchy_runtime.omarchy_planner.collect_inventory",
            return_value=changed,
        ), patch(
            "omarchy_runtime.omarchy_asahi.AsahiStage1Adapter",
            return_value=adapter,
        ), patch(
            "omarchy_runtime.omarchy_stage1.run_stage1",
            return_value="awaiting_recovery",
        ):
            self._run_layout(runtime)

        self.assertEqual(
            adapter.preflight.call_args.args[0].minimum_install_bytes,
            40_001_000_000,
        )
        adapter.preflight.assert_called_once()

    def test_pre_mutation_resume_rejects_newly_unsafe_bounds(self):
        self._seed_plan(self.journal_path, self.inventory, self.plan)
        self._write_execution_inputs()
        runtime = EngineRuntime.from_environment(self._install_environment())
        runtime.inspect("j314sap", True)
        changed = self._copy_inventory()
        changed["candidates"][0]["minimum_install_bytes"] = 81_000_000_000

        with patch(
            "omarchy_runtime.omarchy_planner.collect_inventory",
            return_value=changed,
        ), patch(
            "omarchy_runtime.omarchy_asahi.AsahiStage1Adapter",
        ) as adapter_type:
            with self.assertRaisesRegex(
                ExecutionAdmissionError,
                "approved extent is too small",
            ):
                self._run_layout(runtime)

        adapter_type.assert_not_called()

    def test_ambiguous_resume_stops_before_adapter_preflight(self):
        journal = self._seed_plan(
            self.journal_path,
            self.inventory,
            self.plan,
        )
        journal.event("apfs_preparation_started")
        runtime = EngineRuntime.from_environment(self._install_environment())
        runtime.inspect("j314sap", True)

        with patch(
            "omarchy_runtime.omarchy_planner.collect_inventory",
            return_value=self.inventory,
        ), patch(
            "omarchy_runtime.omarchy_execution.admit_execution",
            return_value=self.plan,
        ), patch(
            "omarchy_runtime.omarchy_asahi.AsahiStage1Adapter",
        ) as adapter_type:
            with self.assertRaisesRegex(
                Exception,
                "has no completion checkpoint",
            ):
                self._run_layout(runtime)

        adapter_type.assert_not_called()

    def test_completed_resume_skips_adapter_and_mutations(self):
        journal = self._seed_plan(
            self.journal_path,
            self.inventory,
            self.plan,
        )
        for event, identifier, phase in (
            (
                "apfs_preparation_started",
                "apfs-target-prepared",
                "apfs_preparation",
            ),
            (
                "stub_and_esp_started",
                "stub-and-esp-installed",
                "stub_and_esp",
            ),
            (
                "recovery_handoff_started",
                "recovery-handoff-prepared",
                "awaiting_recovery",
            ),
        ):
            journal.event(event)
            journal.checkpoint(identifier, phase, identifier.encode())
        journal.completion("awaiting_recovery")
        runtime = EngineRuntime.from_environment(self._install_environment())
        runtime.inspect("j314sap", True)

        with patch(
            "omarchy_runtime.omarchy_planner.collect_inventory",
            return_value={
                "system_store_identifier": "disk0",
                "candidates": [],
            },
        ), patch(
            "omarchy_runtime.omarchy_execution.admit_execution",
            return_value=self.plan,
        ), patch(
            "omarchy_runtime.omarchy_asahi.AsahiStage1Adapter",
        ) as adapter_type, patch(
            "omarchy_runtime.omarchy_stage1.run_stage1",
        ) as run_stage1:
            outcome = self._run_layout(runtime)

        self.assertEqual(outcome, "awaiting_recovery")
        adapter_type.assert_not_called()
        run_stage1.assert_not_called()

    def test_recovery_retry_uses_strict_bless_only_path(self):
        journal = self._seed_plan(
            self.journal_path,
            self.inventory,
            self.plan,
        )
        journal.event("apfs_preparation_started")
        journal.checkpoint(
            "apfs-target-prepared",
            "apfs_preparation",
            b"target",
        )
        journal.event("stub_and_esp_started")
        journal.checkpoint(
            "stub-and-esp-installed",
            "stub_and_esp",
            b"installed",
        )
        journal.event("recovery_handoff_started")
        environment = self._install_environment()
        environment["OMARCHY_ENGINE_MODE"] = (
            "retry-recovery-authorization"
        )
        runtime = EngineRuntime.from_environment(environment)
        runtime.inspect("j314sap", True)
        adapter = Mock()
        adapter.preflight = Mock()

        with patch(
            "omarchy_runtime.omarchy_planner.collect_inventory",
            return_value={
                "system_store_identifier": "disk0",
                "candidates": [],
            },
        ), patch(
            "omarchy_runtime.omarchy_execution.admit_execution",
            return_value=self.plan,
        ), patch(
            "omarchy_runtime.omarchy_asahi.AsahiStage1Adapter",
            return_value=adapter,
        ), patch(
            "omarchy_runtime.omarchy_stage1.retry_recovery_authorization",
            return_value="awaiting_recovery",
        ) as retry, patch(
            "omarchy_runtime.omarchy_stage1.run_stage1",
        ) as run_stage1:
            outcome = self._run_layout(runtime)

        self.assertEqual(outcome, "awaiting_recovery")
        adapter.preflight.assert_called_once_with(self.plan)
        retry.assert_called_once_with(
            self.plan,
            runtime.journal,
            adapter,
        )
        run_stage1.assert_not_called()

    def test_explicit_repair_uses_only_repair_inventory_and_dispatch(self):
        repair_inventory = {
            "system_store_identifier": "disk0",
            "candidates": [
                {
                    "kind": "repair",
                    "source_identifier": "disk0s2",
                    "offset_bytes": 857_747_943_424,
                    "length_bytes": 137_438_953_472,
                    "minimum_install_bytes": 137_438_953_472,
                    "minimum_container_bytes": 0,
                    "identity_digest": "sha256:" + "9" * 64,
                }
            ],
        }
        plan = self._build_repair_plan(repair_inventory)
        environment = self._install_environment()
        environment["OMARCHY_ENGINE_REPAIR_MANIFEST"] = str(
            self.root / "repair.json"
        )
        environment["OMARCHY_ENGINE_PLAN_DIGEST"] = plan.plan_digest
        runtime = EngineRuntime.from_environment(environment)
        runtime.inspect("j314sap", True)
        adapter = Mock()
        installer = object()

        with patch(
            "omarchy_runtime.omarchy_repair.load_repair_manifest",
            return_value={
                "operation": "repair-installed-system",
                "device_identifier": "apple,j314s",
            },
        ), patch(
            "omarchy_runtime.omarchy_repair.collect_repair_inventory",
            return_value=repair_inventory,
        ) as collect_repair, patch(
            "omarchy_runtime.omarchy_execution.admit_execution",
            return_value=plan,
        ), patch(
            "omarchy_runtime.omarchy_asahi.AsahiInPlaceRepairAdapter",
            return_value=adapter,
        ), patch(
            "omarchy_runtime.omarchy_repair.run_repair",
            return_value="installed",
        ) as run_repair, patch(
            "omarchy_runtime.omarchy_planner.collect_inventory",
        ) as collect_install, patch(
            "omarchy_runtime.omarchy_stage1.run_stage1",
        ) as run_stage1:
            outcome = runtime.run_layout(
                installer=installer,
                free_parts=[],
                resizable_parts=[],
                stub_size=2_500_000_000,
                part_align=1_048_576,
            )

        self.assertEqual(outcome, "installed")
        collect_repair.assert_called_once()
        collect_install.assert_not_called()
        run_repair.assert_called_once_with(plan, runtime.journal, adapter)
        run_stage1.assert_not_called()

    def _install_environment(self):
        return {
            "OMARCHY_ENGINE_MODE": "install",
            "OMARCHY_ENGINE_JOURNAL": str(self.journal_path),
            "OMARCHY_ENGINE_REQUEST": str(self.root / "request.json"),
            "OMARCHY_ENGINE_IDENTITY": str(self.root / "identity.json"),
            "OMARCHY_ENGINE_METADATA": str(self.root / "metadata.json"),
            "OMARCHY_ENGINE_PAYLOAD": str(self.root / "payload.zip"),
            "OMARCHY_ENGINE_BINDING_DIGEST": "sha256:" + "b" * 64,
            "OMARCHY_ENGINE_PLAN_DIGEST": self.plan.plan_digest,
            "OMARCHY_MACHINE_OWNER": "mina",
            "DISTRO": "Omarchy MX Mac",
            "DISTRO_DOCS": "https://omarchy.org/manual/",
        }

    def _run_layout(self, runtime):
        return runtime.run_layout(
            installer=object(),
            free_parts=[],
            resizable_parts=[],
            stub_size=2_500_000_000,
            part_align=1_048_576,
        )

    def _build_plan(self, inventory):
        scratch = self.root / "scratch.jsonl"
        journal = Journal(str(scratch))
        journal.inspection("apple,j314s", "supported")
        journal.inventory(
            inventory["system_store_identifier"],
            inventory["candidates"],
        )
        digest = journal.plan(
            device_identifier="apple,j314s",
            layout_digest=journal.inventory_payload["layout_digest"],
            candidate_kind="free",
            source_identifier="disk0s3",
            requested_length_bytes=80_000_000_000,
            engine_version="v0.9.0-omarchy.2",
            engine_digest="sha256:" + "d" * 64,
            metadata_digest="sha256:" + "e" * 64,
            payload_digest="sha256:" + "f" * 64,
            required_human_steps=[
                "enterOneTrueRecovery",
                "authenticateMachineOwner",
            ],
        )
        payload = journal.plan_payload
        return SimpleNamespace(
            plan_digest=digest,
            device_identifier=payload["device_identifier"],
            store_identifier=payload["store_identifier"],
            layout_digest=payload["layout_digest"],
            candidate_kind=payload["candidate_kind"],
            source_identifier=payload["source_identifier"],
            offset_bytes=payload["offset_bytes"],
            length_bytes=payload["length_bytes"],
            minimum_install_bytes=40_000_000_000,
            minimum_container_bytes=0,
            engine_version=payload["engine_version"],
            engine_digest=payload["engine_digest"],
            metadata_digest=payload["metadata_digest"],
            payload_digest=payload["payload_digest"],
            required_human_steps=tuple(payload["required_human_steps"]),
        )

    def _build_repair_plan(self, inventory):
        scratch = self.root / "repair-scratch.jsonl"
        journal = Journal(str(scratch))
        journal.inspection("apple,j314s", "supported")
        journal.inventory(
            inventory["system_store_identifier"],
            inventory["candidates"],
        )
        digest = journal.plan(
            device_identifier="apple,j314s",
            layout_digest=journal.inventory_payload["layout_digest"],
            candidate_kind="repair",
            source_identifier="disk0s2",
            requested_length_bytes=137_438_953_472,
            engine_version="v0.9.0-omarchy.7",
            engine_digest="sha256:" + "d" * 64,
            metadata_digest="sha256:" + "e" * 64,
            payload_digest="sha256:" + "f" * 64,
            repair_manifest_digest="sha256:" + "7" * 64,
            required_human_steps=["authenticateMachineOwner"],
        )
        payload = journal.plan_payload
        return SimpleNamespace(
            operation="repair-installed-system",
            plan_digest=digest,
            device_identifier=payload["device_identifier"],
            store_identifier=payload["store_identifier"],
            layout_digest=payload["layout_digest"],
            candidate_kind=payload["candidate_kind"],
            source_identifier=payload["source_identifier"],
            offset_bytes=payload["offset_bytes"],
            length_bytes=payload["length_bytes"],
            minimum_install_bytes=137_438_953_472,
            minimum_container_bytes=0,
            candidate_identity_digest="sha256:" + "9" * 64,
            engine_version=payload["engine_version"],
            engine_digest=payload["engine_digest"],
            metadata_digest=payload["metadata_digest"],
            payload_digest=payload["payload_digest"],
            repair_manifest_digest=payload["repair_manifest_digest"],
            required_human_steps=tuple(payload["required_human_steps"]),
        )

    def _copy_inventory(self):
        return {
            "system_store_identifier": self.inventory[
                "system_store_identifier"
            ],
            "candidates": [dict(self.inventory["candidates"][0])],
        }

    def _write_execution_inputs(self):
        request = {
            "format": 1,
            "operation": "install",
            "plan_digest": self.plan.plan_digest,
            "device_identifier": self.plan.device_identifier,
            "store_identifier": self.plan.store_identifier,
            "layout_digest": self.plan.layout_digest,
            "candidate_kind": self.plan.candidate_kind,
            "source_identifier": self.plan.source_identifier,
            "offset_bytes": self.plan.offset_bytes,
            "length_bytes": self.plan.length_bytes,
            "engine_version": self.plan.engine_version,
            "required_human_steps": list(self.plan.required_human_steps),
        }
        identity = {
            "format": 1,
            "binding_digest": "sha256:" + "b" * 64,
            "trust_root_fingerprint": "sha256:" + "a" * 64,
            "catalog_sequence": 41,
            "catalog_payload_digest": "sha256:" + "c" * 64,
            "plan_digest": self.plan.plan_digest,
            "engine_digest": self.plan.engine_digest,
            "metadata_digest": self.plan.metadata_digest,
            "payload_digest": self.plan.payload_digest,
        }
        for path, payload in (
            (self.root / "request.json", request),
            (self.root / "identity.json", identity),
        ):
            path.write_text(
                json.dumps(payload, sort_keys=True, separators=(",", ":")),
                encoding="utf-8",
            )
            path.chmod(0o400)

    def _seed_plan(self, path, inventory, plan):
        journal = Journal(str(path))
        journal.inspection(plan.device_identifier, "supported")
        journal.inventory(
            inventory["system_store_identifier"],
            inventory["candidates"],
        )
        digest = journal.plan(
            device_identifier=plan.device_identifier,
            layout_digest=plan.layout_digest,
            candidate_kind=plan.candidate_kind,
            source_identifier=plan.source_identifier,
            requested_length_bytes=plan.length_bytes,
            engine_version=plan.engine_version,
            engine_digest=plan.engine_digest,
            metadata_digest=plan.metadata_digest,
            payload_digest=plan.payload_digest,
            required_human_steps=list(plan.required_human_steps),
        )
        self.assertEqual(digest, plan.plan_digest)
        return journal


if __name__ == "__main__":
    unittest.main()
