# SPDX-License-Identifier: MIT
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest


sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[1] / "src"),
)

from omarchy_execution import (  # noqa: E402
    ExecutionAdmissionError,
    admit_execution,
)


class ExecutionAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.engine_digest = self._sha256(b"engine")
        self.metadata_digest = self._sha256(b"metadata")
        self.payload_digest = self._sha256(b"payload")
        self.binding_digest = self._sha256(b"binding")
        self.inventory = self._inventory()
        self.request = self._request()
        self.identity = self._identity()
        self.request_path = self.root / "request.json"
        self.identity_path = self.root / "identity.json"
        self._write_inputs()

    def tearDown(self):
        self.temporary.cleanup()

    def test_valid_free_candidate_returns_immutable_bound_plan(self):
        plan = self._admit()

        self.assertEqual(plan.binding_digest, self.binding_digest)
        self.assertEqual(plan.plan_digest, self.request["plan_digest"])
        self.assertEqual(plan.device_identifier, "apple,j314s")
        self.assertEqual(plan.candidate_kind, "free")
        self.assertEqual(plan.source_identifier, "disk0s3")
        self.assertEqual(plan.offset_bytes, 447_750_000_000)
        self.assertEqual(plan.length_bytes, 80 * 1024**3)
        self.assertEqual(
            plan.required_human_steps,
            (
                "enterOneTrueRecovery",
                "authenticateMachineOwner",
            ),
        )
        with self.assertRaises(AttributeError):
            plan.length_bytes = 1

    def test_valid_resize_candidate_uses_end_aligned_extent(self):
        self.inventory = self._inventory(kind="resize")
        candidate = self.inventory["candidates"][0]
        requested = 80 * 1024**3
        self.request = self._request(
            kind="resize",
            source_identifier="disk0s2",
            offset_bytes=(
                candidate["offset_bytes"]
                + candidate["length_bytes"]
                - requested
            ),
            length_bytes=requested,
        )
        self.identity = self._identity()
        self._write_inputs()

        plan = self._admit()

        self.assertEqual(plan.candidate_kind, "resize")
        self.assertEqual(
            plan.minimum_container_bytes,
            320 * 1024**3,
        )

    def test_valid_repair_requires_exact_identity_extent_and_operation(self):
        self.inventory = self._inventory(kind="repair")
        self.request = self._request(
            kind="repair",
            source_identifier="disk0s2",
            offset_bytes=857_747_943_424,
            length_bytes=137_438_953_472,
            operation="repair-installed-system",
        )
        self.identity = self._identity()
        self._write_inputs()

        plan = self._admit()

        self.assertEqual(plan.candidate_kind, "repair")
        self.assertEqual(
            plan.candidate_identity_digest,
            "sha256:" + "9" * 64,
        )
        self.assertEqual(
            plan.repair_manifest_digest,
            self.identity["repair_manifest_digest"],
        )

        self.request["operation"] = "install"
        self._write_inputs()
        self._assert_rejected("invalid request")

    def test_repair_manifest_substitution_is_rejected_by_plan_digest(self):
        self.inventory = self._inventory(kind="repair")
        self.request = self._request(
            kind="repair",
            source_identifier="disk0s2",
            offset_bytes=857_747_943_424,
            length_bytes=137_438_953_472,
            operation="repair-installed-system",
        )
        self.identity = self._identity()
        self.identity["repair_manifest_digest"] = self._sha256(b"changed")
        self._write_inputs()

        self._assert_rejected("plan digest mismatch")

    def test_resize_admission_accepts_safe_dynamic_bound_drift(self):
        self.inventory = self._inventory(kind="resize")
        candidate = self.inventory["candidates"][0]
        requested = 80 * 1024**3
        self.request = self._request(
            kind="resize",
            source_identifier="disk0s2",
            offset_bytes=(
                candidate["offset_bytes"]
                + candidate["length_bytes"]
                - requested
            ),
            length_bytes=requested,
        )
        self.identity = self._identity()
        self._write_inputs()
        candidate["minimum_install_bytes"] += 1024**2
        candidate["minimum_container_bytes"] += 1024**2

        plan = self._admit()

        self.assertEqual(
            plan.minimum_container_bytes,
            320 * 1024**3 + 1024**2,
        )

    def test_resize_admission_rejects_bound_drift_that_removes_space(self):
        self.inventory = self._inventory(kind="resize")
        candidate = self.inventory["candidates"][0]
        requested = 80 * 1024**3
        self.request = self._request(
            kind="resize",
            source_identifier="disk0s2",
            offset_bytes=(
                candidate["offset_bytes"]
                + candidate["length_bytes"]
                - requested
            ),
            length_bytes=requested,
        )
        self.identity = self._identity()
        self._write_inputs()
        candidate["minimum_container_bytes"] = 421 * 1024**3

        self._assert_rejected("approved extent changed")

    def test_m4_is_rejected_even_with_otherwise_valid_binding(self):
        self.request = self._request(device_identifier="apple,j614s")
        self.identity = self._identity()
        self._write_inputs()

        self._assert_rejected("device is explicitly unsupported")

    def test_changed_extent_is_rejected_by_plan_digest(self):
        self.request["length_bytes"] -= 1024**2
        self._write_inputs()

        self._assert_rejected("plan digest mismatch")

    def test_changed_live_layout_is_rejected(self):
        self.inventory["candidates"][0]["length_bytes"] -= 1024**2
        self.inventory["layout_digest"] = self._layout_digest(
            self.inventory["system_store_identifier"],
            self.inventory["candidates"],
        )

        self._assert_rejected("disk layout changed")

    def test_forged_inventory_digest_is_rejected(self):
        self.inventory["candidates"][0]["length_bytes"] -= 1024**2

        self._assert_rejected("invalid live layout digest")

    def test_helper_binding_substitution_is_rejected(self):
        with self.assertRaisesRegex(
            ExecutionAdmissionError,
            "helper environment binding mismatch",
        ):
            admit_execution(
                request_path=str(self.request_path),
                identity_path=str(self.identity_path),
                live_inventory=self.inventory,
                expected_binding_digest=self._sha256(b"other"),
                expected_plan_digest=self.request["plan_digest"],
            )

    def test_unknown_request_field_is_rejected(self):
        self.request["unexpected"] = True
        self._write_inputs()

        self._assert_rejected("unexpected request fields")

    def test_symlinked_request_is_rejected(self):
        target = self.root / "request-target.json"
        self.request_path.rename(target)
        self.request_path.symlink_to(target)

        self._assert_rejected("unsafe request file")

    def test_duplicate_candidate_identity_is_rejected(self):
        self.inventory["candidates"].append(
            dict(self.inventory["candidates"][0])
        )
        self.inventory["layout_digest"] = self._layout_digest(
            self.inventory["system_store_identifier"],
            self.inventory["candidates"],
        )

        self._assert_rejected("duplicate live candidate")

    def _admit(self):
        return admit_execution(
            request_path=str(self.request_path),
            identity_path=str(self.identity_path),
            live_inventory=self.inventory,
            expected_binding_digest=self.binding_digest,
            expected_plan_digest=self.request["plan_digest"],
        )

    def _assert_rejected(self, message):
        with self.assertRaisesRegex(ExecutionAdmissionError, message):
            self._admit()

    def _write_inputs(self):
        for path, value in (
            (self.request_path, self.request),
            (self.identity_path, self.identity),
        ):
            path.unlink(missing_ok=True)
            path.write_text(
                json.dumps(
                    value,
                    sort_keys=True,
                    separators=(",", ":"),
                ),
                encoding="utf-8",
            )
            path.chmod(0o400)

    def _inventory(self, kind="free"):
        if kind == "free":
            candidates = [
                {
                    "kind": "free",
                    "source_identifier": "disk0s3",
                    "offset_bytes": 447_750_000_000,
                    "length_bytes": 100 * 1024**3,
                    "minimum_install_bytes": 64 * 1024**3,
                    "minimum_container_bytes": 0,
                }
            ]
        elif kind == "resize":
            candidates = [
                {
                    "kind": "resize",
                    "source_identifier": "disk0s2",
                    "offset_bytes": 1_000_000_000,
                    "length_bytes": 500 * 1024**3,
                    "minimum_install_bytes": 64 * 1024**3,
                    "minimum_container_bytes": 320 * 1024**3,
                }
            ]
        else:
            candidates = [
                {
                    "kind": "repair",
                    "source_identifier": "disk0s2",
                    "offset_bytes": 857_747_943_424,
                    "length_bytes": 137_438_953_472,
                    "minimum_install_bytes": 137_438_953_472,
                    "minimum_container_bytes": 0,
                    "identity_digest": "sha256:" + "9" * 64,
                }
            ]
        return {
            "system_store_identifier": "disk0",
            "candidates": candidates,
            "layout_digest": self._layout_digest("disk0", candidates),
        }

    def _request(
        self,
        *,
        device_identifier="apple,j314s",
        kind="free",
        source_identifier="disk0s3",
        offset_bytes=447_750_000_000,
        length_bytes=80 * 1024**3,
        operation="install",
    ):
        request = {
            "format": 1,
            "operation": operation,
            "plan_digest": "",
            "device_identifier": device_identifier,
            "store_identifier": "disk0",
            "layout_digest": self.inventory["layout_digest"],
            "candidate_kind": kind,
            "source_identifier": source_identifier,
            "offset_bytes": offset_bytes,
            "length_bytes": length_bytes,
            "engine_version": "v0.9.0-omarchy.2",
            "required_human_steps": (
                ["authenticateMachineOwner"]
                if operation == "repair-installed-system"
                else [
                    "enterOneTrueRecovery",
                    "authenticateMachineOwner",
                ]
            ),
        }
        request["plan_digest"] = self._plan_digest(request)
        return request

    def _identity(self):
        identity = {
            "format": 1,
            "binding_digest": self.binding_digest,
            "trust_root_fingerprint": self._sha256(b"root"),
            "catalog_sequence": 41,
            "catalog_payload_digest": self._sha256(b"catalog"),
            "plan_digest": self.request["plan_digest"],
            "engine_digest": self.engine_digest,
            "metadata_digest": self.metadata_digest,
            "payload_digest": self.payload_digest,
        }
        if self.request["operation"] == "repair-installed-system":
            identity["repair_manifest_digest"] = self._sha256(
                b"repair-manifest"
            )
        return identity

    def _plan_digest(self, request):
        fields = [
                request["device_identifier"],
                request["store_identifier"],
                request["layout_digest"],
                request["candidate_kind"],
                request["source_identifier"],
                str(request["offset_bytes"]),
                str(request["length_bytes"]),
                request["engine_version"],
                self.engine_digest,
                self.metadata_digest,
                self.payload_digest,
        ]
        if request["operation"] == "repair-installed-system":
            fields.append(self._sha256(b"repair-manifest"))
        fields.append(",".join(request["required_human_steps"]))
        return self._length_prefixed(fields)

    def _layout_digest(self, store, candidates):
        fields = [store]
        for candidate in sorted(
            candidates,
            key=lambda item: (item["offset_bytes"], item["kind"]),
        ):
            fields.extend(
                (
                    candidate["kind"],
                    candidate["source_identifier"],
                    str(candidate["offset_bytes"]),
                    str(candidate["length_bytes"]),
                )
            )
            if candidate["kind"] == "repair":
                fields.append(candidate["identity_digest"])
        return self._length_prefixed(fields, prefix="sha256:")

    def _length_prefixed(self, fields, prefix=""):
        canonical = "|".join(
            f"{len(value.encode('utf-8'))}:{value}" for value in fields
        )
        return prefix + hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    def _sha256(self, data):
        return "sha256:" + hashlib.sha256(data).hexdigest()


if __name__ == "__main__":
    unittest.main()
