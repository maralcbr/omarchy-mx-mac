import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).resolve().parents[1] / "verify-source-lock.py"
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


if __name__ == "__main__":
    unittest.main()
