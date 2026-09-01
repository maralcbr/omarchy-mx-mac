import io
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path


class VerifyArchiveModesTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)
        self.archive = Path(self.root.name) / "engine.tar.gz"
        self.verifier = (
            Path(__file__).resolve().parents[1] / "verify-archive-modes.py"
        )

    def test_safe_regular_directory_and_symlink_entries_pass(self):
        self._write_archive(
            [
                ("bundle", tarfile.DIRTYPE, 0o755),
                ("bundle/main.py", tarfile.REGTYPE, 0o644),
                ("bundle/current", tarfile.SYMTYPE, 0o777),
            ]
        )

        result = self._verify()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("archive_modes=passed", result.stdout)

    def test_group_writable_regular_entry_is_rejected(self):
        self._write_archive(
            [("bundle/main.py", tarfile.REGTYPE, 0o664)]
        )

        result = self._verify()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("bundle/main.py", result.stderr)
        self.assertIn("0664", result.stderr)

    def test_group_writable_directory_entry_is_rejected(self):
        self._write_archive([("bundle", tarfile.DIRTYPE, 0o775)])

        result = self._verify()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("bundle", result.stderr)
        self.assertIn("0775", result.stderr)

    def _verify(self):
        return subprocess.run(
            [sys.executable, str(self.verifier), str(self.archive)],
            check=False,
            capture_output=True,
            text=True,
        )

    def _write_archive(self, entries):
        with tarfile.open(self.archive, "w:gz", format=tarfile.PAX_FORMAT) as archive:
            for name, entry_type, mode in entries:
                info = tarfile.TarInfo(name)
                info.type = entry_type
                info.mode = mode
                info.mtime = 0
                if entry_type == tarfile.REGTYPE:
                    payload = b"fixture\n"
                    info.size = len(payload)
                    archive.addfile(info, io.BytesIO(payload))
                elif entry_type == tarfile.SYMTYPE:
                    info.linkname = "main.py"
                    archive.addfile(info)
                else:
                    archive.addfile(info)


if __name__ == "__main__":
    unittest.main()
