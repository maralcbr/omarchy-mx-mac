import importlib.util
import json
from pathlib import Path
import unittest


ENGINE_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ENGINE_ROOT / "verify-source-lock.py"
SPEC = importlib.util.spec_from_file_location("verify_source_lock", MODULE_PATH)
VERIFY_SOURCE_LOCK = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(VERIFY_SOURCE_LOCK)


class ValidationArtifactLockTests(unittest.TestCase):
    def test_complete_validation_artifact_is_accepted(self):
        VERIFY_SOURCE_LOCK.require_validation_artifact(
            {
                "filename": "installer-v0.9.0-omarchy.7.tar.gz",
                "size_bytes": 22071040,
                "sha256": "3e86e003c65f5dc2f90e78b656d1cc959f3d9ff7865c6c76d494d335c6867a66",
                "reproducibility_scope": (
                    "two-clean-builds-same-host-pinned-toolchain"
                ),
                "signature": "absent",
            }
        )

    def test_missing_size_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "validation artifact"):
            VERIFY_SOURCE_LOCK.require_validation_artifact(
                {
                    "filename": "installer-v0.9.0-omarchy.7.tar.gz",
                    "sha256": "3e86e003c65f5dc2f90e78b656d1cc959f3d9ff7865c6c76d494d335c6867a66",
                    "reproducibility_scope": (
                        "two-clean-builds-same-host-pinned-toolchain"
                    ),
                    "signature": "absent",
                }
            )

    def test_empty_digest_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "validation artifact"):
            VERIFY_SOURCE_LOCK.require_validation_artifact(
                {
                    "filename": "installer-v0.9.0-omarchy.7.tar.gz",
                    "size_bytes": 22071040,
                    "sha256": "",
                    "reproducibility_scope": (
                        "two-clean-builds-same-host-pinned-toolchain"
                    ),
                    "signature": "absent",
                }
            )


class M1N1BrandingOverlayLockTests(unittest.TestCase):
    def test_exact_authoritative_bootlogo_overlay_is_accepted(self):
        VERIFY_SOURCE_LOCK.require_m1n1_branding_overlay(
            [
                {
                    "path": "overlay/m1n1/data/bootlogo_48.bin",
                    "destination": "m1n1/data/bootlogo_48.bin",
                    "sha256": "6668050653645711ad7523fe2abeb4cbe85a92c875f3eec754b6db23cea2191c",
                },
                {
                    "path": "overlay/m1n1/data/bootlogo_128.bin",
                    "destination": "m1n1/data/bootlogo_128.bin",
                    "sha256": "b19cb017645c7a9068ea0be9b6bb394131d7ca11b28093cf6caa1ffca74b0a4e",
                },
                {
                    "path": "overlay/m1n1/data/bootlogo_256.bin",
                    "destination": "m1n1/data/bootlogo_256.bin",
                    "sha256": "9c659b392aacfa31c62c638003d2257abfdbe17919b5c90cde4c4e62f87addab",
                },
            ]
        )

    def test_missing_stage_one_bootlogo_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "m1n1 branding overlay"):
            VERIFY_SOURCE_LOCK.require_m1n1_branding_overlay([])

    def test_wrong_stage_one_bootlogo_digest_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "m1n1 branding overlay"):
            VERIFY_SOURCE_LOCK.require_m1n1_branding_overlay(
                [
                    {
                        "path": "overlay/m1n1/data/bootlogo_48.bin",
                        "destination": "m1n1/data/bootlogo_48.bin",
                        "sha256": "0" * 64,
                    }
                ]
            )


PATCH = """diff --git a/build.sh b/build.sh
--- a/build.sh
+++ b/build.sh
diff --git a/src/main.py b/src/main.py
--- a/src/main.py
+++ b/src/main.py
"""


def delta_record(path, patched, **overrides):
    return {
        "path": path,
        "downstream_patched": patched,
        "upstream_base_sha256": "1" * 64,
        "upstream_sha256": "2" * 64,
        "base_sha256": ("3" if patched else "1") * 64,
        "sha256": ("4" if patched else "2") * 64,
        **overrides,
    }


def delta(*records):
    return {
        "base_commit": "f0469cea0899f3efed8efead604174c7a53c4451",
        "files": list(records),
    }


class UpstreamDeltaLockTests(unittest.TestCase):
    def test_patched_and_unpatched_files_are_accepted(self):
        VERIFY_SOURCE_LOCK.require_upstream_delta(
            delta(
                delta_record("asahi_firmware/bluetooth.py", False),
                delta_record("src/main.py", True),
            ),
            PATCH,
        )

    def test_repository_lock_matches_the_downstream_patch(self):
        lock = json.loads((ENGINE_ROOT / "source-lock.json").read_text())
        patch = ENGINE_ROOT / lock["downstream_overlay"]["patch"]["path"]
        VERIFY_SOURCE_LOCK.require_upstream_delta(
            lock["incremental_build"]["upstream_delta"], patch.read_text()
        )

    def test_patch_paths_are_read_from_git_headers(self):
        self.assertEqual(
            VERIFY_SOURCE_LOCK.patched_paths(PATCH), {"build.sh", "src/main.py"}
        )

    def test_patched_file_declared_unpatched_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "patch coverage"):
            VERIFY_SOURCE_LOCK.require_upstream_delta(
                delta(delta_record("src/main.py", False)), PATCH
            )

    def test_unpatched_file_declared_patched_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "patch coverage"):
            VERIFY_SOURCE_LOCK.require_upstream_delta(
                delta(delta_record("asahi_firmware/bluetooth.py", True)), PATCH
            )

    def test_unpatched_file_with_distinct_shipped_digest_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "unpatched upstream delta digests"):
            VERIFY_SOURCE_LOCK.require_upstream_delta(
                delta(
                    delta_record(
                        "asahi_firmware/bluetooth.py", False, sha256="5" * 64
                    )
                ),
                PATCH,
            )

    def test_non_python_file_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Python only"):
            VERIFY_SOURCE_LOCK.require_upstream_delta(
                delta(delta_record("build.sh", True)), PATCH
            )

    def test_record_without_upstream_digests_is_rejected(self):
        record = delta_record("asahi_firmware/bluetooth.py", False)
        del record["upstream_sha256"]
        with self.assertRaisesRegex(ValueError, "file record"):
            VERIFY_SOURCE_LOCK.require_upstream_delta(delta(record), PATCH)

    def test_duplicate_or_escaping_paths_are_rejected(self):
        record = delta_record("asahi_firmware/bluetooth.py", False)
        for records in (
            [record, record],
            [delta_record("../main.py", False)],
        ):
            with self.assertRaisesRegex(ValueError, "upstream delta path"):
                VERIFY_SOURCE_LOCK.require_upstream_delta(delta(*records), PATCH)

    def test_empty_delta_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "upstream delta lock record"):
            VERIFY_SOURCE_LOCK.require_upstream_delta(delta(), PATCH)


if __name__ == "__main__":
    unittest.main()
