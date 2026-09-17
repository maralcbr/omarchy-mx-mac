import hashlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


MODULE_PATH = Path(__file__).resolve().parents[1] / "rebuild-python-overlay.py"
SPEC = importlib.util.spec_from_file_location("rebuild_python_overlay", MODULE_PATH)
REBUILD = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(REBUILD)

GIT_ENV = {
    **os.environ,
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "test",
    "GIT_AUTHOR_EMAIL": "test@example.com",
    "GIT_COMMITTER_NAME": "test",
    "GIT_COMMITTER_EMAIL": "test@example.com",
}

MAIN_BASE = b'import os\n\nDEVICES = {\n    "j433ap": Device("14.8.3", True),\n}\n'
MAIN_NEW = b'import os\n\nDEVICES = {\n    "j433ap": Device("14.8.3", False),\n}\n'
MAIN_BASE_PATCHED = MAIN_BASE.replace(b"import os\n", b"import os\nimport omarchy_runtime\n")
MAIN_NEW_PATCHED = MAIN_NEW.replace(b"import os\n", b"import os\nimport omarchy_runtime\n")
PATCH = """diff --git a/build.sh b/build.sh
--- a/build.sh
+++ b/build.sh
@@ -1 +1 @@
-echo upstream
+echo omarchy
diff --git a/src/main.py b/src/main.py
--- a/src/main.py
+++ b/src/main.py
@@ -1,3 +1,4 @@
 import os
+import omarchy_runtime

 DEVICES = {
"""


def digest(data):
    return hashlib.sha256(data).hexdigest()


def archive_with(files):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as archive:
        for name, content in files.items():
            member = tarfile.TarInfo("./" + name)
            member.size = len(content)
            archive.addfile(member, io.BytesIO(content))
    buffer.seek(0)
    return tarfile.open(fileobj=buffer, mode="r")


def record(path, base, new, patched=None):
    patched_base, patched_new = patched or (base, new)
    return {
        "path": path,
        "downstream_patched": patched is not None,
        "upstream_base_sha256": digest(base),
        "upstream_sha256": digest(new),
        "base_sha256": digest(patched_base),
        "sha256": digest(patched_new),
    }


BLUETOOTH = record("asahi_firmware/bluetooth.py", b"old\n", b"new\n")
MAIN = record("src/main.py", MAIN_BASE, MAIN_NEW, (MAIN_BASE_PATCHED, MAIN_NEW_PATCHED))


class UpstreamDeltaTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.checkout = root / "checkout"
        self.checkout.mkdir()
        self.patch = root / "0001-omarchy-engine-runtime.patch"
        self.patch.write_text(PATCH)
        self.git("init", "-q")
        self.write("asahi_firmware/bluetooth.py", b"old\n")
        self.write("src/main.py", MAIN_BASE)
        self.write("src/util.py", b"base\n")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "base")
        self.base_commit = self.git("rev-parse", "HEAD")
        self.write("asahi_firmware/bluetooth.py", b"new\n")

    def git(self, *arguments):
        return subprocess.run(
            ["git", "-C", str(self.checkout), *arguments],
            check=True, text=True, stdout=subprocess.PIPE, env=GIT_ENV,
        ).stdout.strip()

    def write(self, path, content):
        target = self.checkout / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-q", "-m", "upstream")

    def delta(self, *records):
        return {"base_commit": self.base_commit, "files": list(records or [BLUETOOTH])}

    def rebuild(self, delta, archive_files):
        return REBUILD.upstream_delta(self.checkout, delta, archive_with(archive_files), self.patch)

    def test_exact_python_delta_is_overlaid(self):
        self.commit()
        overlay = self.rebuild(self.delta(), {"asahi_firmware/bluetooth.py": b"old\n"})
        self.assertEqual(overlay, {"asahi_firmware/bluetooth.py": b"new\n"})

    def test_patched_delta_is_rebuilt_from_base_and_new_with_the_patch(self):
        self.write("src/main.py", MAIN_NEW)
        self.commit()
        overlay = self.rebuild(
            self.delta(BLUETOOTH, MAIN),
            {"asahi_firmware/bluetooth.py": b"old\n", "main.py": MAIN_BASE_PATCHED},
        )
        self.assertEqual(
            overlay, {"asahi_firmware/bluetooth.py": b"new\n", "main.py": MAIN_NEW_PATCHED}
        )
        self.assertEqual((self.checkout / "src/main.py").read_bytes(), MAIN_NEW)
        self.assertEqual(self.git("status", "--porcelain", "--untracked-files=all"), "")

    def test_src_files_map_to_the_archive_root(self):
        self.write("src/util.py", b"new\n")
        self.commit()
        overlay = self.rebuild(
            self.delta(BLUETOOTH, record("src/util.py", b"base\n", b"new\n")),
            {"asahi_firmware/bluetooth.py": b"old\n", "util.py": b"base\n"},
        )
        self.assertEqual(overlay["util.py"], b"new\n")
        self.assertNotIn("src/util.py", overlay)

    def test_archive_without_the_mapped_file_is_rejected(self):
        self.write("src/util.py", b"new\n")
        self.commit()
        with self.assertRaisesRegex(ValueError, "does not ship upstream file: src/util.py"):
            self.rebuild(
                self.delta(BLUETOOTH, record("src/util.py", b"base\n", b"new\n")),
                {"asahi_firmware/bluetooth.py": b"old\n", "src/util.py": b"base\n"},
            )

    def test_base_engine_without_the_downstream_patch_is_rejected(self):
        self.write("src/main.py", MAIN_NEW)
        self.commit()
        with self.assertRaisesRegex(ValueError, "base engine differs.*src/main.py"):
            self.rebuild(
                self.delta(BLUETOOTH, MAIN),
                {"asahi_firmware/bluetooth.py": b"old\n", "main.py": MAIN_BASE},
            )

    def test_patched_content_must_match_lock(self):
        self.write("src/main.py", MAIN_NEW)
        self.commit()
        with self.assertRaisesRegex(ValueError, "patched upstream delta digest mismatch"):
            self.rebuild(
                self.delta(BLUETOOTH, {**MAIN, "sha256": digest(MAIN_NEW)}),
                {"asahi_firmware/bluetooth.py": b"old\n", "main.py": MAIN_BASE_PATCHED},
            )

    def test_patch_that_no_longer_applies_is_rejected(self):
        moved = MAIN_NEW.replace(b"import os\n", b"import sys\n")
        self.write("src/main.py", moved)
        self.commit()
        with self.assertRaisesRegex(ValueError, "downstream patch does not apply"):
            self.rebuild(
                self.delta(BLUETOOTH, record("src/main.py", MAIN_BASE, moved,
                                             (MAIN_BASE_PATCHED, MAIN_NEW_PATCHED))),
                {"asahi_firmware/bluetooth.py": b"old\n", "main.py": MAIN_BASE_PATCHED},
            )

    def test_patch_coverage_must_match_lock(self):
        self.write("src/main.py", MAIN_NEW)
        self.commit()
        with self.assertRaisesRegex(ValueError, "patch coverage differs"):
            self.rebuild(
                self.delta(BLUETOOTH, record("src/main.py", MAIN_BASE, MAIN_NEW)),
                {"asahi_firmware/bluetooth.py": b"old\n", "main.py": MAIN_BASE},
            )

    def test_non_python_delta_is_rejected(self):
        self.write("m1n1/Makefile", b"changed\n")
        self.commit()
        with self.assertRaisesRegex(ValueError, "Python only: m1n1/Makefile"):
            self.rebuild(
                self.delta(BLUETOOTH, record("m1n1/Makefile", b"", b"changed\n")),
                {"asahi_firmware/bluetooth.py": b"old\n"},
            )

    def test_unlisted_upstream_change_is_rejected(self):
        self.write("m1n1/Makefile", b"changed\n")
        self.commit()
        with self.assertRaisesRegex(ValueError, "differ from the source lock"):
            self.rebuild(self.delta(), {"asahi_firmware/bluetooth.py": b"old\n"})

    def test_listed_but_unchanged_file_is_rejected(self):
        self.commit()
        with self.assertRaisesRegex(ValueError, "differ from the source lock"):
            self.rebuild(
                self.delta(BLUETOOTH, MAIN),
                {"asahi_firmware/bluetooth.py": b"old\n", "main.py": MAIN_BASE_PATCHED},
            )

    def test_base_engine_built_from_other_source_is_rejected(self):
        self.commit()
        with self.assertRaisesRegex(ValueError, "base engine differs"):
            self.rebuild(self.delta(), {"asahi_firmware/bluetooth.py": b"other\n"})

    def test_upstream_content_must_match_lock(self):
        self.commit()
        with self.assertRaisesRegex(ValueError, "upstream delta digest mismatch"):
            self.rebuild(
                self.delta({**BLUETOOTH, "upstream_sha256": digest(b"unexpected\n"),
                            "sha256": digest(b"unexpected\n")}),
                {"asahi_firmware/bluetooth.py": b"old\n"},
            )

class BaseIdentityTest(unittest.TestCase):
    def lock(self, base_sha256=None, base_commit=None):
        return {"incremental_build": {
            "base_sha256": base_sha256 or REBUILD.BASE_SHA256,
            "upstream_delta": {"base_commit": base_commit or REBUILD.BASE_COMMIT, "files": []},
        }}

    def setUp(self):
        self.data = b"deployed base engine"
        self.saved = REBUILD.BASE_SHA256
        REBUILD.BASE_SHA256 = digest(self.data)

    def tearDown(self):
        REBUILD.BASE_SHA256 = self.saved

    def test_pinned_base_and_commit_are_accepted(self):
        REBUILD.require_base(self.data, self.lock())

    def test_other_base_archive_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "exact deployed omarchy.14 engine"):
            REBUILD.require_base(b"another engine", self.lock())

    def test_delta_from_another_upstream_commit_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "different base"):
            REBUILD.require_base(self.data, self.lock(base_commit="99dff2e968dafcabc2a940865b051e91ffcfafd3"))

    def test_lock_naming_another_base_archive_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "different base"):
            REBUILD.require_base(self.data, self.lock(base_sha256="0" * 64))


if __name__ == "__main__":
    unittest.main()
