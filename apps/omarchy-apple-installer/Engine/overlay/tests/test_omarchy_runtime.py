# SPDX-License-Identifier: MIT
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
import tempfile
import unittest


from omarchy_contract import Journal
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

    def test_planned_resume_admits_against_bound_inventory(self):
        self._seed_plan(self.journal_path, self.inventory, self.plan)
        runtime = EngineRuntime.from_environment(self._install_environment())
        runtime.inspect("j314sap", True)
        changed = {
            "system_store_identifier": "disk0",
            "candidates": [],
        }
        adapter = Mock()

        with patch(
            "omarchy_runtime.omarchy_planner.collect_inventory",
            return_value=changed,
        ), patch(
            "omarchy_runtime.omarchy_execution.admit_execution",
            return_value=self.plan,
        ) as admit, patch(
            "omarchy_runtime.omarchy_asahi.AsahiStage1Adapter",
            return_value=adapter,
        ), patch(
            "omarchy_runtime.omarchy_stage1.run_stage1",
            return_value="awaiting_recovery",
        ):
            self._run_layout(runtime)

        self.assertEqual(
            admit.call_args.kwargs["live_inventory"],
            runtime.journal.inventory_payload,
        )
        adapter.preflight.assert_called_once_with(self.plan)

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
