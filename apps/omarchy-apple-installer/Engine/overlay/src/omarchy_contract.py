# SPDX-License-Identifier: MIT
"""Append-only, resumable transcript shared with the Swift trust core."""

import hashlib
import json
import os
import re
import stat


SCHEMA_VERSION = 1
MAX_RECORD_BYTES = 65_536
MAX_JOURNAL_BYTES = 8_388_608
MAX_CHECKPOINT_EVIDENCE_BYTES = 1_048_576
DEVICE_IDENTIFIER = re.compile(r"^apple,[a-z0-9]+$")
STORE_IDENTIFIER = re.compile(r"^disk[0-9]+$")
PARTITION_IDENTIFIER = re.compile(r"^disk[0-9]+(?:s[0-9]+)?$")
LOWER_HEX_64 = re.compile(r"^[0-9a-f]{64}$")
SHA256_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
CHECKPOINT_IDENTIFIER = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
PHASE_ORDER = {
    "preflight": 0,
    "existing_removal": 1,
    "apfs_preparation": 2,
    "stub_and_esp": 3,
    "awaiting_recovery": 4,
    "boot_policy": 5,
    "media_handoff": 6,
    "omarchy_install": 7,
}
COMPLETION_OUTCOMES = {
    "awaiting_recovery",
    "awaiting_media",
    "installed",
    "manual_recovery_required",
}


class ContractError(ValueError):
    pass


class Journal:
    def __init__(self, path):
        if not isinstance(path, str) or not path:
            raise ContractError("journal path is required")
        self.path = path
        self.records = []
        self.inspection_payload = None
        self.inventory_payload = None
        self.plan_payload = None
        self.events = set()
        self.checkpoints = {}
        self.completion_outcome = None
        self._resume()

    @property
    def sequence(self):
        return len(self.records)

    @property
    def plan_digest(self):
        if self.plan_payload is None:
            return None
        return self.plan_payload["plan_digest"]

    def has_event(self, name):
        return name in self.events

    def has_checkpoint(self, phase):
        return any(
            payload["phase"] == phase
            for payload in self.checkpoints.values()
        )

    def inspection(self, device_identifier, support):
        payload = {
            "device_identifier": device_identifier,
            "support": support,
        }
        _validate_inspection(payload)
        if self.inspection_payload is not None:
            if self.inspection_payload != payload:
                raise ContractError("inspection identity changed")
            return
        if self.sequence != 0:
            raise ContractError("inspection must be first")
        self._append("inspection", payload)
        self.inspection_payload = payload

    def inventory(self, system_store_identifier, candidates):
        payload = _inventory_payload(system_store_identifier, candidates)
        if self.inventory_payload is not None:
            if self.inventory_payload == payload:
                return payload["layout_digest"]
            if (
                self.plan_payload is not None
                or self.inventory_payload["layout_digest"]
                != payload["layout_digest"]
            ):
                raise ContractError("inventory changed during resume")
            merged = []
            for recorded, current in zip(
                self.inventory_payload["candidates"],
                payload["candidates"],
                strict=True,
            ):
                geometry_keys = (
                    "kind",
                    "source_identifier",
                    "offset_bytes",
                    "length_bytes",
                )
                if any(
                    recorded[key] != current[key]
                    for key in geometry_keys
                ):
                    raise ContractError("inventory changed during resume")
                candidate = dict(current)
                candidate["minimum_install_bytes"] = max(
                    recorded["minimum_install_bytes"],
                    current["minimum_install_bytes"],
                )
                candidate["minimum_container_bytes"] = max(
                    recorded["minimum_container_bytes"],
                    current["minimum_container_bytes"],
                )
                merged.append(candidate)
            self.inventory_payload = _inventory_payload(
                system_store_identifier,
                merged,
            )
            return self.inventory_payload["layout_digest"]
        if self.sequence != 1 or self.inspection_payload is None:
            raise ContractError("inventory must follow inspection")
        self._append("inventory", payload)
        self.inventory_payload = payload
        return payload["layout_digest"]

    def plan(
        self,
        *,
        device_identifier,
        layout_digest,
        candidate_kind,
        source_identifier,
        requested_length_bytes,
        engine_version,
        engine_digest,
        metadata_digest,
        payload_digest,
        required_human_steps,
        repair_manifest_digest=None,
    ):
        payload = _plan_payload(
            inventory=self.inventory_payload,
            device_identifier=device_identifier,
            layout_digest=layout_digest,
            candidate_kind=candidate_kind,
            source_identifier=source_identifier,
            requested_length_bytes=requested_length_bytes,
            engine_version=engine_version,
            engine_digest=engine_digest,
            metadata_digest=metadata_digest,
            payload_digest=payload_digest,
            repair_manifest_digest=repair_manifest_digest,
            required_human_steps=required_human_steps,
        )
        if self.plan_payload is not None:
            if self.plan_payload != payload:
                raise ContractError("plan changed during resume")
            return payload["plan_digest"]
        if self.sequence != 2:
            raise ContractError("plan must follow inventory")
        self._append("plan", payload)
        self.plan_payload = payload
        return payload["plan_digest"]

    def event(self, name):
        if not isinstance(name, str) or not name:
            raise ContractError("event name is required")
        if name in self.events:
            return
        self._require_open_plan()
        payload = {
            "plan_digest": self.plan_digest,
            "name": name,
        }
        self._append("event", payload)
        self.events.add(name)

    def checkpoint(self, identifier, phase, evidence):
        if (
            not isinstance(identifier, str)
            or CHECKPOINT_IDENTIFIER.fullmatch(identifier) is None
            or phase not in PHASE_ORDER
            or not isinstance(evidence, bytes)
            or not evidence
        ):
            raise ContractError("invalid checkpoint")
        payload = {
            "plan_digest": self.plan_digest,
            "identifier": identifier,
            "phase": phase,
            "evidence_digest": sha256_digest(evidence),
        }
        existing = self.checkpoints.get(identifier)
        if existing is not None:
            if existing != payload:
                raise ContractError("checkpoint changed during resume")
            self._store_checkpoint_evidence(identifier, evidence)
            return
        self._require_open_plan()
        highest = max(
            (
                PHASE_ORDER[item["phase"]]
                for item in self.checkpoints.values()
            ),
            default=-1,
        )
        if PHASE_ORDER[phase] < highest:
            raise ContractError("checkpoint phase regressed")
        self._store_checkpoint_evidence(identifier, evidence)
        self._append("checkpoint", payload)
        self.checkpoints[identifier] = payload

    def checkpoint_evidence(self, identifier):
        checkpoint = self.checkpoints.get(identifier)
        if checkpoint is None:
            raise ContractError("checkpoint evidence is unavailable")
        evidence = self._read_checkpoint_evidence(identifier)
        if sha256_digest(evidence) != checkpoint["evidence_digest"]:
            raise ContractError("checkpoint evidence changed")
        return evidence

    def _store_checkpoint_evidence(self, identifier, evidence):
        path = self._checkpoint_evidence_path(identifier)
        try:
            descriptor = os.open(
                path,
                os.O_WRONLY
                | os.O_CREAT
                | os.O_EXCL
                | os.O_CLOEXEC
                | os.O_NOFOLLOW,
                0o600,
            )
        except FileExistsError:
            if self._read_checkpoint_evidence(identifier) != evidence:
                raise ContractError("checkpoint evidence changed")
            return
        try:
            written = 0
            while written < len(evidence):
                count = os.write(descriptor, evidence[written:])
                if count <= 0:
                    raise ContractError("short checkpoint evidence write")
                written += count
            os.fsync(descriptor)
        finally:
            os.close(descriptor)

    def _read_checkpoint_evidence(self, identifier):
        descriptor = os.open(
            self._checkpoint_evidence_path(identifier),
            os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW,
        )
        try:
            details = os.fstat(descriptor)
            if (
                not stat.S_ISREG(details.st_mode)
                or details.st_mode & 0o077
                or details.st_uid != os.geteuid()
                or details.st_size <= 0
                or details.st_size > MAX_CHECKPOINT_EVIDENCE_BYTES
            ):
                raise ContractError("unsafe checkpoint evidence")
            evidence = os.read(
                descriptor,
                MAX_CHECKPOINT_EVIDENCE_BYTES + 1,
            )
            if len(evidence) != details.st_size:
                raise ContractError("short checkpoint evidence read")
            return evidence
        finally:
            os.close(descriptor)

    def _checkpoint_evidence_path(self, identifier):
        if CHECKPOINT_IDENTIFIER.fullmatch(identifier) is None:
            raise ContractError("invalid checkpoint identifier")
        return f"{self.path}.{identifier}.evidence"

    def completion(self, outcome):
        if self.plan_payload is None:
            raise ContractError("plan is required")
        if outcome not in COMPLETION_OUTCOMES:
            raise ContractError("invalid completion")
        if self.completion_outcome is not None:
            if self.completion_outcome != outcome:
                raise ContractError("completion changed during resume")
            return
        payload = {
            "plan_digest": self.plan_digest,
            "outcome": outcome,
        }
        self._append("completion", payload)
        self.completion_outcome = outcome

    def _require_open_plan(self):
        if self.plan_payload is None:
            raise ContractError("plan is required")
        if self.completion_outcome is not None:
            raise ContractError("journal is complete")

    def _resume(self):
        try:
            descriptor = _open_journal(self.path, os.O_RDONLY)
        except FileNotFoundError:
            return
        try:
            details = os.fstat(descriptor)
            if details.st_size > MAX_JOURNAL_BYTES:
                raise ContractError("journal is too large")
            data = os.read(descriptor, MAX_JOURNAL_BYTES + 1)
            if len(data) != details.st_size:
                raise ContractError("short journal read")
        finally:
            os.close(descriptor)
        if data and not data.endswith(b"\n"):
            raise ContractError("truncated journal")
        for line_number, encoded in enumerate(data.splitlines(), 1):
            if len(encoded) > MAX_RECORD_BYTES:
                raise ContractError(f"record {line_number} is too large")
            try:
                record = json.loads(encoded)
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise ContractError(
                    f"invalid record {line_number}"
                ) from error
            self._accept_resumed_record(record, line_number)

    def _accept_resumed_record(self, record, line_number):
        if (
            not isinstance(record, dict)
            or set(record) != {
                "schema_version",
                "sequence",
                "type",
                "payload",
            }
            or record["schema_version"] != SCHEMA_VERSION
            or record["sequence"] != line_number
            or not isinstance(record["payload"], dict)
        ):
            raise ContractError(f"invalid record {line_number}")
        if self.completion_outcome is not None:
            raise ContractError("message after completion")

        record_type = record["type"]
        payload = record["payload"]
        if record_type == "inspection":
            if line_number != 1 or self.inspection_payload is not None:
                raise ContractError("invalid inspection sequence")
            _validate_inspection(payload)
            self.inspection_payload = payload
        elif record_type == "inventory":
            if line_number != 2 or self.inventory_payload is not None:
                raise ContractError("invalid inventory sequence")
            validated = _inventory_payload(
                payload.get("system_store_identifier"),
                payload.get("candidates"),
            )
            if payload != validated:
                raise ContractError("invalid inventory")
            self.inventory_payload = payload
        elif record_type == "plan":
            if line_number != 3 or self.plan_payload is not None:
                raise ContractError("invalid plan sequence")
            validated = _plan_payload_from_record(
                payload,
                self.inventory_payload,
            )
            if payload != validated:
                raise ContractError("invalid plan")
            self.plan_payload = payload
        elif record_type == "event":
            _require_exact_keys(payload, {"plan_digest", "name"})
            self._require_resumed_plan_digest(payload)
            if not isinstance(payload["name"], str) or not payload["name"]:
                raise ContractError("invalid event")
            if payload["name"] in self.events:
                raise ContractError("duplicate event")
            self.events.add(payload["name"])
        elif record_type == "checkpoint":
            _require_exact_keys(
                payload,
                {
                    "plan_digest",
                    "identifier",
                    "phase",
                    "evidence_digest",
                },
            )
            self._require_resumed_plan_digest(payload)
            if (
                not isinstance(payload["identifier"], str)
                or CHECKPOINT_IDENTIFIER.fullmatch(
                    payload["identifier"]
                )
                is None
                or payload["identifier"] in self.checkpoints
                or payload["phase"] not in PHASE_ORDER
                or not SHA256_DIGEST.fullmatch(payload["evidence_digest"])
            ):
                raise ContractError("invalid checkpoint")
            highest = max(
                (
                    PHASE_ORDER[item["phase"]]
                    for item in self.checkpoints.values()
                ),
                default=-1,
            )
            if PHASE_ORDER[payload["phase"]] < highest:
                raise ContractError("checkpoint phase regressed")
            self.checkpoints[payload["identifier"]] = payload
        elif record_type == "completion":
            _require_exact_keys(payload, {"plan_digest", "outcome"})
            self._require_resumed_plan_digest(payload)
            if payload["outcome"] not in COMPLETION_OUTCOMES:
                raise ContractError("invalid completion")
            self.completion_outcome = payload["outcome"]
        else:
            raise ContractError("unknown journal record")
        self.records.append(record)

    def _require_resumed_plan_digest(self, payload):
        if (
            self.plan_payload is None
            or payload["plan_digest"] != self.plan_digest
        ):
            raise ContractError("stale plan digest")

    def _append(self, record_type, payload):
        record = {
            "schema_version": SCHEMA_VERSION,
            "sequence": self.sequence + 1,
            "type": record_type,
            "payload": payload,
        }
        encoded = (
            json.dumps(
                record,
                separators=(",", ":"),
                sort_keys=True,
            ).encode("utf-8")
            + b"\n"
        )
        if len(encoded) > MAX_RECORD_BYTES:
            raise ContractError("record is too large")
        descriptor = _open_journal(
            self.path,
            os.O_WRONLY | os.O_CREAT | os.O_APPEND,
            mode=0o600,
        )
        try:
            if os.write(descriptor, encoded) != len(encoded):
                raise ContractError("short journal write")
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        self.records.append(record)


def normalize_device_identifier(device_class):
    if not isinstance(device_class, str):
        raise ContractError("invalid device identifier")
    value = device_class.lower()
    if value.endswith("ap"):
        value = value[:-2]
    identifier = f"apple,{value}"
    if not DEVICE_IDENTIFIER.fullmatch(identifier):
        raise ContractError("invalid device identifier")
    return identifier


def sha256_digest(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def _open_journal(path, flags, mode=0):
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, mode)
    details = os.fstat(descriptor)
    if (
        not stat.S_ISREG(details.st_mode)
        or details.st_mode & 0o077
    ):
        os.close(descriptor)
        raise ContractError("unsafe journal")
    return descriptor


def _validate_inspection(payload):
    _require_exact_keys(payload, {"device_identifier", "support"})
    if (
        not DEVICE_IDENTIFIER.fullmatch(payload["device_identifier"])
        or payload["support"] not in ("supported", "unsupported")
    ):
        raise ContractError("invalid inspection")


def normalized_inventory(system_store_identifier, candidates):
    return _inventory_payload(system_store_identifier, candidates)


def _inventory_payload(system_store_identifier, candidates):
    if (
        not STORE_IDENTIFIER.fullmatch(system_store_identifier or "")
        or not isinstance(candidates, list)
    ):
        raise ContractError("invalid inventory")
    identities = set()
    normalized = []
    for candidate in candidates:
        candidate = _validate_candidate(candidate)
        identity = (candidate["kind"], candidate["source_identifier"])
        if identity in identities:
            raise ContractError("duplicate candidate identity")
        identities.add(identity)
        normalized.append(candidate)
    normalized.sort(key=lambda item: (item["offset_bytes"], item["kind"]))
    fields = [system_store_identifier]
    for candidate in normalized:
        fields.extend(
            (
                candidate["kind"],
                candidate["source_identifier"],
                str(candidate["offset_bytes"]),
                str(candidate["length_bytes"]),
            )
        )
        if candidate["kind"] in ("repair", "replace"):
            fields.append(candidate["identity_digest"])
    return {
        "layout_digest": _length_prefixed_digest(
            fields,
            prefix="sha256:",
        ),
        "system_store_identifier": system_store_identifier,
        "candidates": normalized,
    }


def _validate_candidate(candidate):
    common_keys = {
        "kind",
        "source_identifier",
        "offset_bytes",
        "length_bytes",
        "minimum_install_bytes",
        "minimum_container_bytes",
    }
    keys = set(common_keys)
    if isinstance(candidate, dict) and candidate.get("kind") in (
        "repair",
        "replace",
    ):
        keys.add("identity_digest")
    _require_exact_keys(candidate, keys)
    if (
        candidate["kind"] not in ("free", "resize", "repair", "replace")
        or not PARTITION_IDENTIFIER.fullmatch(
            candidate["source_identifier"]
        )
    ):
        raise ContractError("invalid candidate")
    for key in common_keys - {"kind", "source_identifier"}:
        if not _is_uint64(candidate[key]):
            raise ContractError("invalid candidate extent")
    if candidate["kind"] in ("repair", "replace") and not SHA256_DIGEST.fullmatch(
        candidate["identity_digest"]
    ):
        raise ContractError("invalid repair identity")
    if (
        candidate["length_bytes"] == 0
        or candidate["minimum_install_bytes"] == 0
        or candidate["offset_bytes"] + candidate["length_bytes"] >= 2**64
        or (
            candidate["kind"] == "free"
            and candidate["minimum_container_bytes"] != 0
        )
        or (
            candidate["kind"] == "resize"
            and candidate["minimum_container_bytes"] == 0
        )
        or (
            candidate["kind"] == "repair"
            and (
                candidate["minimum_container_bytes"] != 0
                or candidate["minimum_install_bytes"]
                != candidate["length_bytes"]
            )
        )
        or (
            candidate["kind"] == "replace"
            and (
                candidate["minimum_container_bytes"] != 0
                or candidate["minimum_install_bytes"]
                > candidate["length_bytes"]
            )
        )
    ):
        raise ContractError("invalid candidate extent")
    return dict(candidate)


def _plan_payload(
    *,
    inventory,
    device_identifier,
    layout_digest,
    candidate_kind,
    source_identifier,
    requested_length_bytes,
    engine_version,
    engine_digest,
    metadata_digest,
    payload_digest,
    repair_manifest_digest,
    required_human_steps,
):
    if inventory is None:
        raise ContractError("inventory is required")
    matches = [
        candidate
        for candidate in inventory["candidates"]
        if candidate["kind"] == candidate_kind
        and candidate["source_identifier"] == source_identifier
    ]
    if (
        not DEVICE_IDENTIFIER.fullmatch(device_identifier or "")
        or layout_digest != inventory["layout_digest"]
        or len(matches) != 1
        or not _is_uint64(requested_length_bytes)
        or requested_length_bytes == 0
        or not isinstance(engine_version, str)
        or not engine_version
        or not isinstance(required_human_steps, list)
        or not required_human_steps
        or any(
            not isinstance(item, str) or not item
            for item in required_human_steps
        )
        or (
            candidate_kind == "repair"
            and not SHA256_DIGEST.fullmatch(
                repair_manifest_digest or ""
            )
        )
        or (
            candidate_kind != "repair"
            and repair_manifest_digest is not None
        )
        or any(
            not SHA256_DIGEST.fullmatch(value or "")
            for value in (
                engine_digest,
                metadata_digest,
                payload_digest,
            )
        )
    ):
        raise ContractError("invalid plan")
    candidate = matches[0]
    if requested_length_bytes < candidate["minimum_install_bytes"]:
        raise ContractError("requested extent is too small")
    if candidate_kind in ("free", "repair", "replace"):
        available = candidate["length_bytes"]
        offset = candidate["offset_bytes"]
    else:
        available = (
            candidate["length_bytes"] - candidate["minimum_container_bytes"]
        )
        offset = (
            candidate["offset_bytes"]
            + candidate["length_bytes"]
            - requested_length_bytes
        )
    if requested_length_bytes > available:
        raise ContractError("requested extent exceeds candidate")
    if (
        candidate_kind == "replace"
        and requested_length_bytes != candidate["length_bytes"]
    ):
        raise ContractError("replace requires the exact existing extent")
    payload = {
        "plan_digest": "",
        "device_identifier": device_identifier,
        "store_identifier": inventory["system_store_identifier"],
        "layout_digest": layout_digest,
        "candidate_kind": candidate_kind,
        "source_identifier": source_identifier,
        "offset_bytes": offset,
        "length_bytes": requested_length_bytes,
        "engine_version": engine_version,
        "engine_digest": engine_digest,
        "metadata_digest": metadata_digest,
        "payload_digest": payload_digest,
        "required_human_steps": list(required_human_steps),
    }
    if candidate_kind == "repair":
        payload["repair_manifest_digest"] = repair_manifest_digest
    payload["plan_digest"] = _canonical_plan_digest(payload)
    return payload


def _plan_payload_from_record(payload, inventory):
    keys = {
        "plan_digest",
        "device_identifier",
        "store_identifier",
        "layout_digest",
        "candidate_kind",
        "source_identifier",
        "offset_bytes",
        "length_bytes",
        "engine_version",
        "engine_digest",
        "metadata_digest",
        "payload_digest",
        "required_human_steps",
    }
    if isinstance(payload, dict) and payload.get("candidate_kind") == "repair":
        keys.add("repair_manifest_digest")
    _require_exact_keys(payload, keys)
    validated = _plan_payload(
        inventory=inventory,
        device_identifier=payload["device_identifier"],
        layout_digest=payload["layout_digest"],
        candidate_kind=payload["candidate_kind"],
        source_identifier=payload["source_identifier"],
        requested_length_bytes=payload["length_bytes"],
        engine_version=payload["engine_version"],
        engine_digest=payload["engine_digest"],
        metadata_digest=payload["metadata_digest"],
        payload_digest=payload["payload_digest"],
        repair_manifest_digest=payload.get("repair_manifest_digest"),
        required_human_steps=payload["required_human_steps"],
    )
    if payload["store_identifier"] != validated["store_identifier"]:
        raise ContractError("invalid plan store")
    return validated


def _canonical_plan_digest(plan):
    fields = [
            plan["device_identifier"],
            plan["store_identifier"],
            plan["layout_digest"],
            plan["candidate_kind"],
            plan["source_identifier"],
            str(plan["offset_bytes"]),
            str(plan["length_bytes"]),
            plan["engine_version"],
            plan["engine_digest"],
            plan["metadata_digest"],
            plan["payload_digest"],
    ]
    if plan["candidate_kind"] == "repair":
        fields.append(plan["repair_manifest_digest"])
    fields.append(",".join(plan["required_human_steps"]))
    return _length_prefixed_digest(fields)


def _length_prefixed_digest(fields, prefix=""):
    canonical = "|".join(
        f"{len(value.encode('utf-8'))}:{value}" for value in fields
    )
    return prefix + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _require_exact_keys(value, keys):
    if not isinstance(value, dict) or set(value) != keys:
        raise ContractError("unexpected fields")


def _is_uint64(value):
    return (
        isinstance(value, int)
        and not isinstance(value, bool)
        and 0 <= value < 2**64
    )
