# SPDX-License-Identifier: MIT
"""Concrete stage-1 adapter over pinned upstream Asahi primitives."""

import json
import os
import stat
import shutil
import zipfile

import asahi_firmware
import osinstall
import stub


TARGET = "apple-silicon-uefi"


class AsahiAdapterError(RuntimeError):
    pass


class AsahiStage1Adapter:
    def __init__(
        self,
        *,
        installer,
        metadata_path,
        payload_path,
        stub_size,
    ):
        self.installer = installer
        self.metadata_path = metadata_path
        self.payload_path = payload_path
        self.stub_size = stub_size
        self.template = None
        self.osins = None
        self.target_part = None
        self.preflight_complete = False

    def preflight(self, plan):
        if self.preflight_complete:
            return
        metadata = self._load_metadata()
        templates = [
            template
            for template in metadata["os_list"]
            if template.get("omarchy_target") == TARGET
        ]
        if len(templates) != 1:
            raise AsahiAdapterError(
                "metadata must contain exactly one Omarchy target"
            )
        self.installer.data = metadata
        self.template = templates[0]
        self.osins = osinstall.OSInstaller(
            self.installer.dutil,
            metadata,
            self.template,
        )
        if (
            plan.length_bytes
            < self.stub_size + self.osins.min_recommended_size
        ):
            raise AsahiAdapterError(
                "approved extent is smaller than Asahi minimum"
            )
        try:
            self.osins.pkg = zipfile.ZipFile(self.payload_path)
            invalid_member = self.osins.pkg.testzip()
        except (OSError, zipfile.BadZipFile) as error:
            raise AsahiAdapterError("invalid Omarchy payload") from error
        if invalid_member is not None:
            raise AsahiAdapterError(
                f"invalid Omarchy payload member: {invalid_member}"
            )
        ipsw = self.installer.choose_ipsw(
            self.template.get("supported_fw"),
        )
        self.installer.ins = stub.StubInstaller(
            self.installer.sysinfo,
            self.installer.dutil,
            self.installer.osinfo,
        )
        self.installer.ins.load_ipsw(ipsw)
        self.installer.osins = self.osins
        self.preflight_complete = True

    def prepare_target(self, plan):
        self._require_preflight()
        self.installer.check_cur_os()
        self._refresh_parts()
        if plan.candidate_kind == "resize":
            source = self._find_partition(
                name=plan.source_identifier,
                free=False,
            )
            new_size = source.size - plan.length_bytes
            if new_size < plan.minimum_container_bytes:
                raise AsahiAdapterError(
                    "resize would cross the approved minimum"
                )
            self.installer.dutil.resizeContainer(source.name, new_size)
            self._refresh_parts()
        free = self._find_free_extent(plan)
        self.target_part = self.installer.dutil.addPartition(
            free.name,
            "apfs",
            self.osins.name,
            self.stub_size,
        )
        self.installer.part = self.target_part
        return self._target_evidence(plan)

    def install_stub_and_esp(self, plan):
        self._require_preflight()
        if self.target_part is None:
            self._refresh_parts()
            self.target_part = self._find_prepared_target(plan)
            self.installer.part = self.target_part

        self.installer.ins.prepare_volume(self.target_part)
        self.installer.ins.check_volume()
        self.installer.ins.install_files(self.installer.cur_os)
        os_size = plan.length_bytes - self.stub_size
        self.osins.partition_disk(self.target_part.name, os_size)

        firmware_package = None
        if self.osins.needs_firmware:
            os.makedirs("vendorfw", exist_ok=True)
            firmware_package = asahi_firmware.core.FWPackage(
                "vendorfw"
            )
            self.installer.ins.collect_firmware(firmware_package)
            firmware_package.close()
            self.osins.firmware_package = firmware_package

        self.osins.install(self.installer.ins)
        for target in self.osins.idata_targets:
            self.installer.ins.collect_installer_data(target)
            shutil.copy(
                "installer.log",
                os.path.join(target, "installer.log"),
            )
        self.installer.ins.prepare_for_step2()
        return self._installed_evidence(plan)

    def prepare_recovery_handoff(self, plan):
        self._require_preflight()
        return json.dumps(
            {
                "plan_digest": plan.plan_digest,
                "outcome": "awaiting_recovery",
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")

    def _load_metadata(self):
        flags = os.O_RDONLY
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            descriptor = os.open(self.metadata_path, flags)
        except OSError as error:
            raise AsahiAdapterError("metadata is unavailable") from error
        try:
            status = os.fstat(descriptor)
            if (
                not stat.S_ISREG(status.st_mode)
                or status.st_mode & (stat.S_IWGRP | stat.S_IWOTH)
                or status.st_size < 1
                or status.st_size > 65_536
            ):
                raise AsahiAdapterError("metadata is invalid")
            data = os.read(descriptor, status.st_size + 1)
        finally:
            os.close(descriptor)
        if not data or len(data) > 65_536:
            raise AsahiAdapterError("metadata is invalid")
        try:
            metadata = json.loads(data)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise AsahiAdapterError("metadata is invalid") from error
        if (
            not isinstance(metadata, dict)
            or set(metadata) != {"os_list"}
            or not isinstance(metadata["os_list"], list)
        ):
            raise AsahiAdapterError("metadata is invalid")
        return metadata

    def _refresh_parts(self):
        self.installer.dutil.get_info()
        self.installer.parts = self.installer.dutil.get_partitions(
            self.installer.sys_disk
        )

    def _find_partition(self, *, name, free):
        matches = [
            part
            for part in self.installer.parts
            if part.name == name and part.free is free
        ]
        if len(matches) != 1:
            raise AsahiAdapterError("approved source partition changed")
        return matches[0]

    def _find_free_extent(self, plan):
        matches = [
            part
            for part in self.installer.parts
            if part.free
            and part.offset == plan.offset_bytes
            and part.size >= plan.length_bytes
        ]
        if len(matches) != 1:
            raise AsahiAdapterError("approved free extent changed")
        return matches[0]

    def _find_prepared_target(self, plan):
        minimum = int(self.stub_size * 0.95)
        maximum = int(self.stub_size * 1.05)
        matches = [
            part
            for part in self.installer.parts
            if not part.free
            and part.offset == plan.offset_bytes
            and minimum <= part.size <= maximum
            and isinstance(part.type, str)
            and "APFS" in part.type
        ]
        if len(matches) != 1:
            raise AsahiAdapterError(
                "prepared APFS target cannot be reconciled"
            )
        return matches[0]

    def _target_evidence(self, plan):
        return json.dumps(
            {
                "plan_digest": plan.plan_digest,
                "partition_identifier": self.target_part.name,
                "offset_bytes": self.target_part.offset,
                "size_bytes": self.target_part.size,
                "uuid": self.target_part.uuid,
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")

    def _installed_evidence(self, plan):
        osi = self.installer.ins.osi
        return json.dumps(
            {
                "plan_digest": plan.plan_digest,
                "apfs_vgid": osi.vgid,
                "system_volume": osi.sys_volume,
                "efi_partition": (
                    self.osins.efi_part.uuid.lower()
                    if self.osins.efi_part is not None
                    else None
                ),
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")

    def _require_preflight(self):
        if not self.preflight_complete:
            raise AsahiAdapterError("adapter preflight is required")
