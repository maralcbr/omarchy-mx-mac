# SPDX-License-Identifier: MIT
"""Asahi-native inventory and candidate-bound planning."""

import json
import os
import stat

import osinstall
from util import align_down


TARGET = "apple-silicon-uefi"
MAX_INPUT_BYTES = 65_536
PLAN_REQUEST_KEYS = {
    "schema_version",
    "layout_digest",
    "candidate_kind",
    "source_identifier",
    "requested_length_bytes",
}
ENGINE_IDENTITY_KEYS = {
    "schema_version",
    "engine_version",
    "engine_digest",
    "metadata_digest",
    "payload_digest",
}
REQUIRED_HUMAN_STEPS = [
    "enterOneTrueRecovery",
    "authenticateMachineOwner",
]


class PlanningError(ValueError):
    pass


def collect_inventory(
    installer,
    free_parts,
    resizable_parts,
    stub_size,
    part_align,
):
    templates = [
        template
        for template in installer.data["os_list"]
        if template.get("omarchy_target") == TARGET
    ]
    if len(templates) != 1:
        raise PlanningError(
            "metadata must contain exactly one Omarchy Apple UEFI target"
        )

    os_installer = osinstall.OSInstaller(
        installer.dutil,
        installer.data,
        templates[0],
    )
    minimum_install = stub_size + os_installer.min_recommended_size
    candidates = []
    for part in free_parts:
        length = align_down(part.size, part_align)
        if length >= minimum_install:
            candidates.append(
                {
                    "kind": "free",
                    "source_identifier": part.name,
                    "offset_bytes": part.offset,
                    "length_bytes": length,
                    "minimum_install_bytes": minimum_install,
                    "minimum_container_bytes": 0,
                }
            )
    for part in resizable_parts:
        bounds = installer.get_resize_bounds(part)
        if bounds["available_bytes"] >= minimum_install:
            candidates.append(
                {
                    "kind": "resize",
                    "source_identifier": part.name,
                    "offset_bytes": part.offset,
                    "length_bytes": part.size,
                    "minimum_install_bytes": minimum_install,
                    "minimum_container_bytes": bounds[
                        "minimum_size_bytes"
                    ],
                }
            )
    candidates.sort(
        key=lambda candidate: (
            candidate["offset_bytes"],
            candidate["kind"],
        )
    )
    return {
        "system_store_identifier": installer.sys_disk,
        "candidates": candidates,
    }


def emit_inventory(
    installer,
    journal,
    free_parts,
    resizable_parts,
    stub_size,
    part_align,
):
    inventory = collect_inventory(
        installer,
        free_parts,
        resizable_parts,
        stub_size,
        part_align,
    )
    journal.inventory(
        inventory["system_store_identifier"],
        inventory["candidates"],
    )
    return journal.inventory_payload


def emit_plan(
    journal,
    request_path,
    identity_path,
    device_identifier,
    part_align,
):
    request = _load_exact_json(
        request_path,
        PLAN_REQUEST_KEYS,
        "planning request",
    )
    identity = _load_exact_json(
        identity_path,
        ENGINE_IDENTITY_KEYS,
        "planning identity",
    )
    requested = request["requested_length_bytes"]
    if (
        not isinstance(requested, int)
        or isinstance(requested, bool)
        or requested <= 0
        or requested % part_align != 0
    ):
        raise PlanningError(
            "requested length must be a positive aligned integer"
        )
    return journal.plan(
        device_identifier=device_identifier,
        layout_digest=request["layout_digest"],
        candidate_kind=request["candidate_kind"],
        source_identifier=request["source_identifier"],
        requested_length_bytes=requested,
        engine_version=identity["engine_version"],
        engine_digest=identity["engine_digest"],
        metadata_digest=identity["metadata_digest"],
        payload_digest=identity["payload_digest"],
        required_human_steps=REQUIRED_HUMAN_STEPS,
    )


def _load_exact_json(path, keys, role):
    flags = os.O_RDONLY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise PlanningError(f"unsafe {role}") from error
    try:
        details = os.fstat(descriptor)
        if (
            not stat.S_ISREG(details.st_mode)
            or details.st_mode & 0o022
            or details.st_size <= 0
            or details.st_size > MAX_INPUT_BYTES
        ):
            raise PlanningError(f"unsafe {role}")
        data = os.read(descriptor, MAX_INPUT_BYTES + 1)
        if len(data) != details.st_size:
            raise PlanningError(f"unsafe {role}")
    finally:
        os.close(descriptor)
    try:
        value = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PlanningError(f"invalid {role}") from error
    if (
        not isinstance(value, dict)
        or set(value) != keys
        or value["schema_version"] != 1
    ):
        raise PlanningError(f"unexpected {role} fields")
    return value
