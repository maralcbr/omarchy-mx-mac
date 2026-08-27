# SPDX-License-Identifier: MIT
"""Resumable sequencing for Asahi-owned stage-1 mutations."""

from dataclasses import dataclass


class Stage1Error(RuntimeError):
    pass


class AmbiguousMutationState(Stage1Error):
    pass


@dataclass(frozen=True)
class Stage:
    event: str
    checkpoint_identifier: str
    checkpoint_phase: str
    adapter_method: str


STAGES = (
    Stage(
        event="apfs_preparation_started",
        checkpoint_identifier="apfs-target-prepared",
        checkpoint_phase="apfs_preparation",
        adapter_method="prepare_target",
    ),
    Stage(
        event="stub_and_esp_started",
        checkpoint_identifier="stub-and-esp-installed",
        checkpoint_phase="stub_and_esp",
        adapter_method="install_stub_and_esp",
    ),
    Stage(
        event="recovery_handoff_started",
        checkpoint_identifier="recovery-handoff-prepared",
        checkpoint_phase="awaiting_recovery",
        adapter_method="prepare_recovery_handoff",
    ),
)


def run_stage1(plan, journal, adapter):
    """Run each mutation once, or return an already completed outcome."""
    completed = validate_stage1_resume(plan, journal)
    if completed is not None:
        return completed

    for stage in STAGES:
        if stage.checkpoint_identifier in journal.checkpoints:
            continue

        journal.event(stage.event)
        operation = getattr(adapter, stage.adapter_method, None)
        if operation is None or not callable(operation):
            raise Stage1Error(
                f"adapter does not implement {stage.adapter_method}"
            )
        evidence = operation(plan)
        if not isinstance(evidence, bytes) or not evidence:
            raise Stage1Error(
                f"{stage.adapter_method} returned invalid evidence"
            )
        journal.checkpoint(
            stage.checkpoint_identifier,
            stage.checkpoint_phase,
            evidence,
        )

    _require_all_checkpoints(journal)
    journal.completion("awaiting_recovery")
    return "awaiting_recovery"


def validate_stage1_resume(plan, journal):
    """Validate resume state before adapter preflight or mutation."""
    if journal.plan_digest != plan.plan_digest:
        raise Stage1Error("journal plan does not match admitted plan")
    if journal.completion_outcome is not None:
        if journal.completion_outcome != "awaiting_recovery":
            raise Stage1Error("unexpected stage-1 completion")
        _require_all_checkpoints(journal)
        return journal.completion_outcome

    for stage in STAGES:
        completed = stage.checkpoint_identifier in journal.checkpoints
        started = journal.has_event(stage.event)
        if completed:
            if not started:
                raise Stage1Error("checkpoint is missing its intent record")
            continue
        if started:
            raise AmbiguousMutationState(
                f"{stage.event} has no completion checkpoint"
            )
    return None


def _require_all_checkpoints(journal):
    missing = [
        stage.checkpoint_identifier
        for stage in STAGES
        if stage.checkpoint_identifier not in journal.checkpoints
    ]
    if missing:
        raise Stage1Error(
            "stage-1 completion is missing checkpoints: "
            + ",".join(missing)
        )
