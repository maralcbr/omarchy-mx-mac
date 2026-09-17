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


class UpstreamDeltaTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.checkout = Path(self.temporary.name)
        self.git("init", "-q")
        self.write("asahi_firmware/bluetooth.py", b"old\n")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "base")
        self.base_commit = self.git("rev-parse", "HEAD")
        self.write("asahi_firmware/bluetooth.py", b"new\n")

    def tearDown(self):
        self.temporary.cleanup()

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

    def delta(self, **overrides):
        record = {
            "path": "asahi_firmware/bluetooth.py",
            "base_sha256": digest(b"old\n"),
            "sha256": digest(b"new\n"),
            **overrides,
        }
        return {"base_commit": self.base_commit, "files": [record]}

    def test_exact_python_delta_is_overlaid(self):
        self.commit()
        overlay = REBUILD.upstream_delta(
            self.checkout, self.delta(), archive_with({"asahi_firmware/bluetooth.py": b"old\n"})
        )
        self.assertEqual(overlay, {"asahi_firmware/bluetooth.py": b"new\n"})

    def test_unlisted_upstream_change_is_rejected(self):
        self.write("m1n1/Makefile", b"changed\n")
        self.commit()
        with self.assertRaisesRegex(ValueError, "differ from the source lock"):
            REBUILD.upstream_delta(
                self.checkout, self.delta(), archive_with({"asahi_firmware/bluetooth.py": b"old\n"})
            )

    def test_base_engine_built_from_other_source_is_rejected(self):
        self.commit()
        with self.assertRaisesRegex(ValueError, "base engine differs"):
            REBUILD.upstream_delta(
                self.checkout, self.delta(), archive_with({"asahi_firmware/bluetooth.py": b"other\n"})
            )

    def test_upstream_content_must_match_lock(self):
        self.commit()
        with self.assertRaisesRegex(ValueError, "upstream delta digest mismatch"):
            REBUILD.upstream_delta(
                self.checkout,
                self.delta(sha256=digest(b"unexpected\n")),
                archive_with({"asahi_firmware/bluetooth.py": b"old\n"}),
            )


if __name__ == "__main__":
    unittest.main()
