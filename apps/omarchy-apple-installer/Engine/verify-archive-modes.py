#!/usr/bin/env python3

import sys
import tarfile
from pathlib import Path


def verify_archive(path: Path) -> int:
    try:
        with tarfile.open(path, "r:*") as archive:
            entry_count = 0
            for member in archive:
                entry_count += 1
                if (member.isfile() or member.isdir()) and member.mode & 0o022:
                    print(
                        "unsafe engine archive mode: "
                        f"{member.mode:04o} {member.name}",
                        file=sys.stderr,
                    )
                    return 1
    except (OSError, tarfile.TarError) as error:
        print(f"unable to verify engine archive modes: {error}", file=sys.stderr)
        return 1

    if entry_count == 0:
        print("engine archive is empty", file=sys.stderr)
        return 1

    print(f"archive_modes=passed entries={entry_count}")
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: verify-archive-modes.py ARCHIVE", file=sys.stderr)
        return 2
    return verify_archive(Path(sys.argv[1]))


if __name__ == "__main__":
    raise SystemExit(main())
