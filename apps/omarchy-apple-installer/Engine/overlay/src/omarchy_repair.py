# SPDX-License-Identifier: MIT
"""Fail-closed in-place repair of an already partitioned Omarchy target."""

from dataclasses import dataclass
import hashlib
import json
import os
import re
import stat
import subprocess
import uuid


SHA256_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
PARTITION_IDENTIFIER = re.compile(r"^disk[0-9]+s[0-9]+$")
STORE_IDENTIFIER = re.compile(r"^disk[0-9]+$")
REPAIR_OPERATION = "repair-installed-system"
REPAIR_ROLES = ("stub", "efi", "boot", "root")
MAXIMUM_REPAIR_MANIFEST_BYTES = 1_048_576


class InPlaceRepairError(RuntimeError):
    pass


class AmbiguousRepairState(InPlaceRepairError):
    pass


@dataclass(frozen=True)
class RepairStage:
    event: str
    checkpoint_identifier: str
    phase: str
    adapter_method: str
    retryable_before_checkpoint: bool = False


REPAIR_STAGES = (
    RepairStage(
        "existing_install_validation_started",
        "existing-install-validated",
        "preflight",
        "validate_existing_install",
        True,
    ),
    RepairStage(
        "repair_content_write_started",
        "repair-content-written",
        "stub_and_esp",
        "rewrite_existing_content",
    ),
    RepairStage(
        "repair_readback_validation_started",
        "repair-content-validated",
        "awaiting_recovery",
        "validate_repaired_content",
        True,
    ),
    RepairStage(
        "repair_boot_policy_authorization_started",
        "repair-boot-policy-authorized",
        "boot_policy",
        "authorize_existing_boot_policy",
        True,
    ),
)


class RepairExecutor:
    """One concrete repair executor shared by release and canary admission."""

    def __init__(self, adapter):
        self.adapter = adapter

    def apply(self, plan, journal):
        return run_repair(plan, journal, self.adapter)

    def retry_boot_policy(self, plan, journal):
        return retry_repair_boot_policy_authorization(
            plan,
            journal,
            self.adapter,
        )


def collect_repair_inventory(
    installer,
    manifest,
    *,
    disk_identity_reader,
    filesystem_identity_reader,
):
    """Return one repair candidate only after exact live-state admission."""
    _validate_manifest(manifest)
    if installer.sys_disk != manifest["store_identifier"]:
        raise InPlaceRepairError("system store changed")
    observed_disk_identity = disk_identity_reader(installer.sys_disk)
    if observed_disk_identity != manifest["disk_identity"]:
        raise InPlaceRepairError("disk identity changed")

    by_name = {
        part.name: part
        for part in installer.parts
        if not getattr(part, "free", False)
    }
    admitted = []
    for expected in manifest["partitions"]:
        part = by_name.get(expected["identifier"])
        if part is None:
            raise InPlaceRepairError("partition identity changed")
        observed_uuid = _normalized_uuid(getattr(part, "uuid", None))
        expected_uuid = expected["partition_uuid"]
        if (
            part.offset != expected["offset_bytes"]
            or part.size != expected["size_bytes"]
            or getattr(part, "type", None) != expected["partition_type"]
            or observed_uuid != expected_uuid
        ):
            raise InPlaceRepairError("partition identity changed")
        filesystem = filesystem_identity_reader(part)
        if filesystem != expected["filesystem"]:
            raise InPlaceRepairError("filesystem identity changed")
        admitted.append(
            (
                expected["role"],
                part.name,
                observed_uuid,
                str(part.offset),
                str(part.size),
                filesystem["type"],
                filesystem["uuid"],
                filesystem["label"],
            )
        )

    extent = manifest["approved_extent"]
    identity_fields = [
        manifest["device_identifier"],
        manifest["store_identifier"],
        observed_disk_identity,
        extent["source_identifier"],
        str(extent["offset_bytes"]),
        str(extent["length_bytes"]),
    ]
    identity_fields.extend(field for item in admitted for field in item)
    identity_digest = _length_prefixed_digest(identity_fields)
    return {
        "system_store_identifier": installer.sys_disk,
        "candidates": [
            {
                "kind": "repair",
                "source_identifier": extent["source_identifier"],
                "offset_bytes": extent["offset_bytes"],
                "length_bytes": extent["length_bytes"],
                "minimum_install_bytes": extent["length_bytes"],
                "minimum_container_bytes": 0,
                "identity_digest": identity_digest,
            }
        ],
    }


def read_filesystem_identity(stream):
    """Read fixed superblock identity fields without mounting a filesystem."""
    stream.seek(0)
    leading_block = stream.read(4096)
    ext4 = leading_block[1024:2048]
    if len(ext4) >= 0x88 and ext4[0x38:0x3A] == b"\x53\xef":
        return {
            "type": "ext4",
            "uuid": str(uuid.UUID(bytes=ext4[0x68:0x78])),
            "label": _cstring(ext4[0x78:0x88]),
        }

    stream.seek(0x10000)
    btrfs = stream.read(0x1000)
    if len(btrfs) >= 0x22B and btrfs[0x40:0x48] == b"_BHRfS_M":
        return {
            "type": "btrfs",
            "uuid": str(uuid.UUID(bytes=btrfs[0x20:0x30])),
            "label": _cstring(btrfs[0x12B:0x22B]),
        }
    raise InPlaceRepairError("unsupported filesystem identity")


def inspect_filesystem_identity(part, raw_partition_opener=None):
    """Inspect an admitted partition without mounting or changing it."""
    part_type = getattr(part, "type", None)
    part_uuid = _normalized_uuid(getattr(part, "uuid", None))
    label = getattr(part, "label", None) or ""
    if isinstance(part_type, str) and "APFS" in part_type:
        return {"type": "apfs", "uuid": part_uuid, "label": label}
    opener = raw_partition_opener or _open_raw_partition
    with opener(part.name) as stream:
        if part_type == "EFI":
            leading_block = stream.read(4096)
            boot_sector = leading_block[:512]
            if len(leading_block) != 4096 or boot_sector[510:512] != b"\x55\xaa":
                raise InPlaceRepairError("invalid FAT32 filesystem identity")
            volume_id = int.from_bytes(boot_sector[67:71], "little")
            volume_label = _cstring(boot_sector[71:82]).rstrip()
            return {
                "type": "fat32",
                "uuid": f"{volume_id >> 16:04x}-{volume_id & 0xffff:04x}",
                "label": volume_label,
            }
        return read_filesystem_identity(stream)


def read_normalized_disk_identity(store_identifier):
    """Match the retained diskutil-plist/plutil-JSON identity primitive."""
    if STORE_IDENTIFIER.fullmatch(store_identifier or "") is None:
        raise InPlaceRepairError("invalid repair store")
    try:
        diskutil = subprocess.run(
            ["/usr/sbin/diskutil", "list", "-plist", store_identifier],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        normalized = subprocess.run(
            ["/usr/bin/plutil", "-convert", "json", "-o", "-", "-"],
            input=diskutil.stdout,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise InPlaceRepairError("disk identity is unavailable") from error
    if not normalized.stdout:
        raise InPlaceRepairError("disk identity is unavailable")
    return "sha256:" + hashlib.sha256(normalized.stdout).hexdigest()


def load_repair_manifest(path):
    """Load one immutable, canonical, non-symlink repair manifest."""
    if not isinstance(path, str) or not path:
        raise InPlaceRepairError("repair manifest is unavailable")
    flags = os.O_RDONLY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise InPlaceRepairError("repair manifest is unavailable") from error
    try:
        details = os.fstat(descriptor)
        if (
            not stat.S_ISREG(details.st_mode)
            or details.st_mode & 0o022
            or details.st_size <= 0
            or details.st_size > MAXIMUM_REPAIR_MANIFEST_BYTES
        ):
            raise InPlaceRepairError("unsafe repair manifest")
        data = os.read(descriptor, MAXIMUM_REPAIR_MANIFEST_BYTES + 1)
        if len(data) != details.st_size:
            raise InPlaceRepairError("unsafe repair manifest")
    finally:
        os.close(descriptor)
    try:
        manifest = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise InPlaceRepairError("invalid repair manifest") from error
    _validate_manifest(manifest)
    canonical = json.dumps(
        manifest,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    if canonical != data:
        raise InPlaceRepairError("repair manifest is not canonical")
    return manifest


def run_repair(plan, journal, adapter):
    """Run the repair stages once; never replay an ambiguous content write."""
    if journal.plan_digest != plan.plan_digest:
        raise InPlaceRepairError("journal plan does not match admitted plan")
    if journal.completion_outcome is not None:
        if journal.completion_outcome != "installed":
            raise InPlaceRepairError("unexpected repair completion")
        _require_repair_checkpoints(journal)
        return "installed"

    for stage in REPAIR_STAGES:
        completed = stage.checkpoint_identifier in journal.checkpoints
        started = journal.has_event(stage.event)
        if completed:
            if not started:
                raise InPlaceRepairError(
                    "repair checkpoint is missing its intent record"
                )
            continue
        if started and not stage.retryable_before_checkpoint:
            raise AmbiguousRepairState(
                f"{stage.event} has no completion checkpoint"
            )
        if not started:
            journal.event(stage.event)
        operation = getattr(adapter, stage.adapter_method, None)
        if not callable(operation):
            raise InPlaceRepairError(
                f"repair adapter does not implement {stage.adapter_method}"
            )
        evidence = operation(plan)
        if not isinstance(evidence, bytes) or not evidence:
            raise InPlaceRepairError(
                f"{stage.adapter_method} returned invalid evidence"
            )
        journal.checkpoint(
            stage.checkpoint_identifier,
            stage.phase,
            evidence,
        )

    _require_repair_checkpoints(journal)
    journal.completion("installed")
    return "installed"


def retry_repair_boot_policy_authorization(plan, journal, adapter):
    """Revalidate written content, then retry only the existing bless target."""
    if journal.plan_digest != plan.plan_digest:
        raise InPlaceRepairError("journal plan does not match admitted plan")
    completed = {
        "existing-install-validated",
        "repair-content-written",
        "repair-content-validated",
    }
    expected_events = {
        "existing_install_validation_started",
        "repair_content_write_started",
        "repair_readback_validation_started",
        "repair_boot_policy_authorization_started",
    }
    if (
        journal.completion_outcome is not None
        or set(journal.checkpoints) != completed
        or journal.events != expected_events
    ):
        raise InPlaceRepairError(
            "repair authorization retry requires completed read-back"
        )
    validator = getattr(adapter, "validate_repaired_content", None)
    authorizer = getattr(adapter, "authorize_existing_boot_policy", None)
    if not callable(validator) or not callable(authorizer):
        raise InPlaceRepairError("repair adapter does not implement retry")
    validator(plan)
    evidence = authorizer(plan)
    if not isinstance(evidence, bytes) or not evidence:
        raise InPlaceRepairError("invalid repair authorization evidence")
    journal.checkpoint(
        "repair-boot-policy-authorized",
        "boot_policy",
        evidence,
    )
    journal.completion("installed")
    return "installed"


def _validate_manifest(manifest):
    expected_keys = {
        "schema_version",
        "operation",
        "repair_id",
        "device_identifier",
        "store_identifier",
        "disk_identity",
        "approved_extent",
        "partitions",
        "existing_content",
        "replacement_content",
        "semantic_contract",
    }
    if (
        not isinstance(manifest, dict)
        or set(manifest) != expected_keys
        or manifest["schema_version"] != 1
        or manifest["operation"] != REPAIR_OPERATION
        or not isinstance(manifest["repair_id"], str)
        or not manifest["repair_id"]
        or not STORE_IDENTIFIER.fullmatch(manifest["store_identifier"])
        or not SHA256_DIGEST.fullmatch(manifest["disk_identity"])
    ):
        raise InPlaceRepairError("invalid repair manifest")

    extent = manifest["approved_extent"]
    if (
        not isinstance(extent, dict)
        or set(extent)
        != {"source_identifier", "offset_bytes", "length_bytes"}
        or not PARTITION_IDENTIFIER.fullmatch(extent["source_identifier"])
        or not _is_uint64(extent["offset_bytes"])
        or not _is_uint64(extent["length_bytes"])
        or extent["length_bytes"] == 0
        or extent["offset_bytes"] + extent["length_bytes"] >= 2**64
    ):
        raise InPlaceRepairError("invalid repair extent")

    partitions = manifest["partitions"]
    if (
        not isinstance(partitions, list)
        or [item.get("role") for item in partitions] != list(REPAIR_ROLES)
    ):
        raise InPlaceRepairError("invalid repair partitions")
    expected_partition_keys = {
        "role",
        "identifier",
        "partition_uuid",
        "offset_bytes",
        "size_bytes",
        "partition_type",
        "filesystem",
    }
    for item in partitions:
        if (
            not isinstance(item, dict)
            or set(item) != expected_partition_keys
            or not PARTITION_IDENTIFIER.fullmatch(item["identifier"])
            or _normalized_uuid(item["partition_uuid"])
            != item["partition_uuid"]
            or not _is_uint64(item["offset_bytes"])
            or not _is_uint64(item["size_bytes"])
            or item["size_bytes"] == 0
            or not isinstance(item["partition_type"], str)
            or set(item["filesystem"]) != {"type", "uuid", "label"}
        ):
            raise InPlaceRepairError("invalid repair partitions")
    if partitions[0]["offset_bytes"] != extent["offset_bytes"]:
        raise InPlaceRepairError("repair partitions do not match extent")
    for left, right in zip(partitions, partitions[1:]):
        if left["offset_bytes"] + left["size_bytes"] != right["offset_bytes"]:
            raise InPlaceRepairError("repair partitions are not contiguous")
    if (
        partitions[-1]["offset_bytes"] + partitions[-1]["size_bytes"]
        != extent["offset_bytes"] + extent["length_bytes"]
    ):
        raise InPlaceRepairError("repair partitions do not match extent")

    existing = manifest["existing_content"]
    replacement = manifest["replacement_content"]
    if (
        not isinstance(existing, dict)
        or set(existing) != set(REPAIR_ROLES)
        or not isinstance(replacement, dict)
        or set(replacement) != set(REPAIR_ROLES)
    ):
        raise InPlaceRepairError("invalid repair content")
    payload_members = []
    for role in REPAIR_ROLES:
        before = existing[role]
        after = replacement[role]
        if not _valid_content_identity(before) or (
            not isinstance(after, dict)
            or set(after) != {"size_bytes", "sha256", "payload_member"}
            or not _valid_content_identity(
                {key: after[key] for key in ("size_bytes", "sha256")}
            )
        ):
            raise InPlaceRepairError("invalid repair content")
        member = after["payload_member"]
        if member is None:
            if before != {
                key: after[key] for key in ("size_bytes", "sha256")
            }:
                raise InPlaceRepairError("invalid preserved repair content")
            continue
        if (
            not isinstance(member, str)
            or not member
            or member.startswith("/")
            or "\\" in member
            or ".." in member.split("/")
        ):
            raise InPlaceRepairError("invalid repair content member")
        payload_members.append(member)
    if not payload_members or len(payload_members) != len(set(payload_members)):
        raise InPlaceRepairError("invalid repair content members")

    if manifest["semantic_contract"] != {
        "partitioning": "forbidden",
        "readback": "exhaustive",
        "boot_policy_retry": "checkpoint-bound",
    }:
        raise InPlaceRepairError("invalid repair semantic contract")


def _require_repair_checkpoints(journal):
    missing = [
        stage.checkpoint_identifier
        for stage in REPAIR_STAGES
        if stage.checkpoint_identifier not in journal.checkpoints
    ]
    if missing:
        raise InPlaceRepairError(
            "repair completion is missing checkpoints: "
            + ",".join(missing)
        )


def _normalized_uuid(value):
    if not isinstance(value, str):
        return None
    try:
        return str(uuid.UUID(value))
    except ValueError:
        return None


def _cstring(value):
    return value.split(b"\0", 1)[0].decode("utf-8")


def _open_raw_partition(name):
    if PARTITION_IDENTIFIER.fullmatch(name or "") is None:
        raise InPlaceRepairError("invalid raw partition identity")
    return open("/dev/r" + name, "rb", buffering=0)


def _length_prefixed_digest(fields):
    canonical = "|".join(
        f"{len(value.encode('utf-8'))}:{value}" for value in fields
    )
    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _is_uint64(value):
    return (
        isinstance(value, int)
        and not isinstance(value, bool)
        and 0 <= value < 2**64
    )


def _valid_content_identity(value):
    return (
        isinstance(value, dict)
        and set(value) == {"size_bytes", "sha256"}
        and _is_uint64(value["size_bytes"])
        and value["size_bytes"] > 0
        and isinstance(value["sha256"], str)
        and SHA256_DIGEST.fullmatch(value["sha256"]) is not None
    )
