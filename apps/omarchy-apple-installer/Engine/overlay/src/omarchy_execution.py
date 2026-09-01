# SPDX-License-Identifier: MIT
"""Fail-closed admission for a candidate-bound Omarchy install.

The upstream Asahi adapter calls only admit_execution. Schema validation,
artifact binding, live-layout recomputation, plan-digest recomputation, model
gating, and exact candidate selection stay inside this module.
"""

from dataclasses import dataclass
import hashlib
import json
import os
import re
import stat


MAX_INPUT_BYTES = 65_536
DEVICE_IDENTIFIER = re.compile(r"^apple,[a-z0-9]+$")
STORE_IDENTIFIER = re.compile(r"^disk[0-9]+$")
PARTITION_IDENTIFIER = re.compile(r"^disk[0-9]+(?:s[0-9]+)?$")
LOWER_HEX_64 = re.compile(r"^[0-9a-f]{64}$")
SHA256_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
UNSUPPORTED_DEVICES = {"apple,j614s"}
REQUIRED_HUMAN_STEPS = (
    "enterOneTrueRecovery",
    "authenticateMachineOwner",
)

REQUEST_KEYS = {
    "format",
    "operation",
    "plan_digest",
    "device_identifier",
    "store_identifier",
    "layout_digest",
    "candidate_kind",
    "source_identifier",
    "offset_bytes",
    "length_bytes",
    "engine_version",
    "required_human_steps",
}
IDENTITY_KEYS = {
    "format",
    "binding_digest",
    "trust_root_fingerprint",
    "catalog_sequence",
    "catalog_payload_digest",
    "plan_digest",
    "engine_digest",
    "metadata_digest",
    "payload_digest",
}
REPAIR_IDENTITY_KEYS = IDENTITY_KEYS | {"repair_manifest_digest"}
INVENTORY_KEYS = {
    "layout_digest",
    "system_store_identifier",
    "candidates",
}
COMMON_CANDIDATE_KEYS = {
    "kind",
    "source_identifier",
    "offset_bytes",
    "length_bytes",
    "minimum_install_bytes",
    "minimum_container_bytes",
}


class ExecutionAdmissionError(ValueError):
    pass


@dataclass(frozen=True)
class ExecutionPlan:
    binding_digest: str
    operation: str
    plan_digest: str
    device_identifier: str
    store_identifier: str
    layout_digest: str
    candidate_kind: str
    source_identifier: str
    offset_bytes: int
    length_bytes: int
    minimum_install_bytes: int
    minimum_container_bytes: int
    candidate_identity_digest: str | None
    engine_version: str
    engine_digest: str
    metadata_digest: str
    payload_digest: str
    repair_manifest_digest: str | None
    required_human_steps: tuple


def admit_execution(
    *,
    request_path,
    identity_path,
    live_inventory,
    expected_binding_digest,
    expected_plan_digest,
):
    """Return one immutable plan or raise before the first mutation."""
    request = _load_exact_json(request_path, REQUEST_KEYS, "request")
    _validate_request(request)
    identity_keys = (
        REPAIR_IDENTITY_KEYS
        if request["operation"] == "repair-installed-system"
        else IDENTITY_KEYS
    )
    identity = _load_exact_json(identity_path, identity_keys, "identity")
    _validate_identity(identity)
    _validate_environment_binding(
        identity,
        expected_binding_digest,
        expected_plan_digest,
    )
    _validate_request_identity_binding(request, identity)
    inventory = _validate_inventory(live_inventory)

    if request["device_identifier"] in UNSUPPORTED_DEVICES:
        raise ExecutionAdmissionError("device is explicitly unsupported")
    if request["store_identifier"] != inventory["system_store_identifier"]:
        raise ExecutionAdmissionError("system store changed")
    if request["layout_digest"] != inventory["layout_digest"]:
        raise ExecutionAdmissionError("disk layout changed")

    candidate = _select_candidate(request, inventory["candidates"])
    canonical_digest = _canonical_plan_digest(request, identity)
    if canonical_digest != request["plan_digest"]:
        raise ExecutionAdmissionError("plan digest mismatch")

    return ExecutionPlan(
        binding_digest=identity["binding_digest"],
        operation=request["operation"],
        plan_digest=request["plan_digest"],
        device_identifier=request["device_identifier"],
        store_identifier=request["store_identifier"],
        layout_digest=request["layout_digest"],
        candidate_kind=request["candidate_kind"],
        source_identifier=request["source_identifier"],
        offset_bytes=request["offset_bytes"],
        length_bytes=request["length_bytes"],
        minimum_install_bytes=candidate["minimum_install_bytes"],
        minimum_container_bytes=candidate["minimum_container_bytes"],
        candidate_identity_digest=candidate.get("identity_digest"),
        engine_version=request["engine_version"],
        engine_digest=identity["engine_digest"],
        metadata_digest=identity["metadata_digest"],
        payload_digest=identity["payload_digest"],
        repair_manifest_digest=identity.get("repair_manifest_digest"),
        required_human_steps=tuple(request["required_human_steps"]),
    )


def _load_exact_json(path, keys, role):
    if not isinstance(path, str) or not path:
        raise ExecutionAdmissionError(f"{role} path is unavailable")
    flags = os.O_RDONLY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise ExecutionAdmissionError(f"unsafe {role} file") from error
    try:
        details = os.fstat(descriptor)
        if (
            not stat.S_ISREG(details.st_mode)
            or details.st_mode & 0o022
            or details.st_size <= 0
            or details.st_size > MAX_INPUT_BYTES
        ):
            raise ExecutionAdmissionError(f"unsafe {role} file")
        data = os.read(descriptor, MAX_INPUT_BYTES + 1)
        if len(data) != details.st_size:
            raise ExecutionAdmissionError(f"unsafe {role} file")
    finally:
        os.close(descriptor)
    try:
        value = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ExecutionAdmissionError(f"invalid {role}") from error
    if not isinstance(value, dict) or set(value) != keys:
        raise ExecutionAdmissionError(f"unexpected {role} fields")
    return value


def _validate_request(request):
    operation_matches_candidate = (
        request["operation"] == "install"
        and request["candidate_kind"] in ("free", "resize", "replace")
    ) or (
        request["operation"] == "repair-installed-system"
        and request["candidate_kind"] == "repair"
    )
    required_steps = (
        ["authenticateMachineOwner"]
        if request["candidate_kind"] == "repair"
        else list(REQUIRED_HUMAN_STEPS)
    )
    integers = ("offset_bytes", "length_bytes")
    if (
        request["format"] != 1
        or not operation_matches_candidate
        or not LOWER_HEX_64.fullmatch(request["plan_digest"])
        or not DEVICE_IDENTIFIER.fullmatch(request["device_identifier"])
        or not STORE_IDENTIFIER.fullmatch(request["store_identifier"])
        or not SHA256_DIGEST.fullmatch(request["layout_digest"])
        or request["candidate_kind"] not in ("free", "resize", "repair", "replace")
        or not PARTITION_IDENTIFIER.fullmatch(request["source_identifier"])
        or not isinstance(request["engine_version"], str)
        or not request["engine_version"]
        or len(request["engine_version"].encode("utf-8")) > 128
        or request["required_human_steps"] != required_steps
    ):
        raise ExecutionAdmissionError("invalid request")
    if any(not _is_uint64(request[key]) for key in integers):
        raise ExecutionAdmissionError("invalid request extent")
    if request["length_bytes"] == 0:
        raise ExecutionAdmissionError("invalid request extent")
    if request["offset_bytes"] + request["length_bytes"] >= 2**64:
        raise ExecutionAdmissionError("invalid request extent")


def _validate_identity(identity):
    if (
        identity["format"] != 1
        or not SHA256_DIGEST.fullmatch(identity["binding_digest"])
        or not SHA256_DIGEST.fullmatch(identity["trust_root_fingerprint"])
        or not _is_uint64(identity["catalog_sequence"])
        or identity["catalog_sequence"] == 0
        or not SHA256_DIGEST.fullmatch(identity["catalog_payload_digest"])
        or not LOWER_HEX_64.fullmatch(identity["plan_digest"])
        or not SHA256_DIGEST.fullmatch(identity["engine_digest"])
        or not SHA256_DIGEST.fullmatch(identity["metadata_digest"])
        or not SHA256_DIGEST.fullmatch(identity["payload_digest"])
        or (
            "repair_manifest_digest" in identity
            and not SHA256_DIGEST.fullmatch(
                identity["repair_manifest_digest"]
            )
        )
    ):
        raise ExecutionAdmissionError("invalid identity")


def _validate_environment_binding(
    identity,
    expected_binding_digest,
    expected_plan_digest,
):
    if (
        identity["binding_digest"] != expected_binding_digest
        or identity["plan_digest"] != expected_plan_digest
    ):
        raise ExecutionAdmissionError("helper environment binding mismatch")


def _validate_request_identity_binding(request, identity):
    if request["plan_digest"] != identity["plan_digest"]:
        raise ExecutionAdmissionError("request identity mismatch")


def _validate_inventory(inventory):
    if not isinstance(inventory, dict) or set(inventory) != INVENTORY_KEYS:
        raise ExecutionAdmissionError("invalid live inventory")
    if (
        not STORE_IDENTIFIER.fullmatch(inventory["system_store_identifier"])
        or not isinstance(inventory["candidates"], list)
    ):
        raise ExecutionAdmissionError("invalid live inventory")
    identities = set()
    candidates = []
    for candidate in inventory["candidates"]:
        candidate = _validate_candidate(candidate)
        identity = (candidate["kind"], candidate["source_identifier"])
        if identity in identities:
            raise ExecutionAdmissionError("duplicate live candidate")
        identities.add(identity)
        candidates.append(candidate)
    candidates.sort(key=lambda item: (item["offset_bytes"], item["kind"]))
    fields = [inventory["system_store_identifier"]]
    for candidate in candidates:
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
    computed = _length_prefixed_digest(fields, prefix="sha256:")
    if inventory["layout_digest"] != computed:
        raise ExecutionAdmissionError("invalid live layout digest")
    return {
        "layout_digest": computed,
        "system_store_identifier": inventory["system_store_identifier"],
        "candidates": candidates,
    }


def _validate_candidate(candidate):
    keys = set(COMMON_CANDIDATE_KEYS)
    if isinstance(candidate, dict) and candidate.get("kind") in (
        "repair",
        "replace",
    ):
        keys.add("identity_digest")
    if not isinstance(candidate, dict) or set(candidate) != keys:
        raise ExecutionAdmissionError("invalid live candidate")
    if (
        candidate["kind"] not in ("free", "resize", "repair", "replace")
        or not PARTITION_IDENTIFIER.fullmatch(candidate["source_identifier"])
    ):
        raise ExecutionAdmissionError("invalid live candidate")
    for key in (
        "offset_bytes",
        "length_bytes",
        "minimum_install_bytes",
        "minimum_container_bytes",
    ):
        if not _is_uint64(candidate[key]):
            raise ExecutionAdmissionError("invalid live candidate extent")
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
    ):
        raise ExecutionAdmissionError("invalid live candidate extent")
    if candidate["kind"] == "repair" and (
        not SHA256_DIGEST.fullmatch(candidate["identity_digest"])
        or candidate["minimum_container_bytes"] != 0
        or candidate["minimum_install_bytes"] != candidate["length_bytes"]
    ):
        raise ExecutionAdmissionError("invalid live repair identity")
    if candidate["kind"] == "replace" and (
        not SHA256_DIGEST.fullmatch(candidate["identity_digest"])
        or candidate["minimum_container_bytes"] != 0
        or candidate["minimum_install_bytes"] > candidate["length_bytes"]
    ):
        raise ExecutionAdmissionError("invalid live replace identity")
    return dict(candidate)


def _select_candidate(request, candidates):
    matches = [
        candidate
        for candidate in candidates
        if candidate["kind"] == request["candidate_kind"]
        and candidate["source_identifier"] == request["source_identifier"]
    ]
    if len(matches) != 1:
        raise ExecutionAdmissionError("approved candidate is unavailable")
    candidate = matches[0]
    requested = request["length_bytes"]
    if requested < candidate["minimum_install_bytes"]:
        raise ExecutionAdmissionError("approved extent is too small")
    if candidate["kind"] in ("free", "repair", "replace"):
        expected_offset = candidate["offset_bytes"]
        available = candidate["length_bytes"]
    else:
        available = (
            candidate["length_bytes"] - candidate["minimum_container_bytes"]
        )
        expected_offset = (
            candidate["offset_bytes"] + candidate["length_bytes"] - requested
        )
    if (
        requested > available
        or request["offset_bytes"] != expected_offset
        or (
            candidate["kind"] in ("repair", "replace")
            and requested != candidate["length_bytes"]
        )
    ):
        raise ExecutionAdmissionError("approved extent changed")
    return candidate


def _canonical_plan_digest(request, identity):
    fields = [
            request["device_identifier"],
            request["store_identifier"],
            request["layout_digest"],
            request["candidate_kind"],
            request["source_identifier"],
            str(request["offset_bytes"]),
            str(request["length_bytes"]),
            request["engine_version"],
            identity["engine_digest"],
            identity["metadata_digest"],
            identity["payload_digest"],
    ]
    if request["operation"] == "repair-installed-system":
        fields.append(identity["repair_manifest_digest"])
    fields.append(",".join(request["required_human_steps"]))
    return _length_prefixed_digest(fields)


def _length_prefixed_digest(fields, prefix=""):
    canonical = "|".join(
        f"{len(value.encode('utf-8'))}:{value}" for value in fields
    )
    return prefix + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _is_uint64(value):
    return (
        isinstance(value, int)
        and not isinstance(value, bool)
        and 0 <= value < 2**64
    )
