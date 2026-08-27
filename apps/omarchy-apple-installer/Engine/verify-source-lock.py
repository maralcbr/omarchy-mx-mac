#!/usr/bin/env python3
"""Verify the pinned Asahi Git graph and every downstream engine input."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


COMMIT = re.compile(r"[0-9a-f]{40}")
SHA256 = re.compile(r"[0-9a-f]{64}")


def run(checkout: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(checkout), *arguments],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.rstrip()


def digest(path: Path) -> str:
    value = hashlib.sha256(path.read_bytes()).hexdigest()
    if not SHA256.fullmatch(value):
        raise ValueError(f"invalid SHA-256 result: {path}")
    return value


def require_digest(engine_root: Path, record: dict, role: str) -> None:
    if set(record) < {"path", "sha256"}:
        raise ValueError(f"invalid {role} lock record")
    path = engine_root / record["path"]
    if not path.is_file() or digest(path) != record["sha256"]:
        raise ValueError(f"{role} digest does not match source lock: {path}")


def verify(engine_root: Path, checkout: Path) -> None:
    lock = json.loads(
        (engine_root / "source-lock.json").read_text(encoding="utf-8")
    )
    if lock.get("schema_version") != 2:
        raise ValueError("unsupported source lock schema")
    if lock.get("source_acquisition") != "verified-git-object-graph":
        raise ValueError("source lock must require verified Git objects")

    upstream = lock["upstream_installer"]
    expected_head = upstream["commit"]
    if (
        not COMMIT.fullmatch(expected_head)
        or run(checkout, "rev-parse", "HEAD") != expected_head
    ):
        raise ValueError("upstream installer commit does not match source lock")
    if run(checkout, "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("upstream installer checkout is not clean")

    expected_submodules = {}
    for item in upstream["submodules"]:
        expected_submodules[item["name"]] = item["commit"]
        for nested in item.get("submodules", []):
            expected_submodules[
                f"{item['name']}/{nested['name']}"
            ] = nested["commit"]
    observed_submodules = {}
    for line in run(
        checkout,
        "submodule",
        "status",
        "--recursive",
    ).splitlines():
        if not line or line[0] != " ":
            raise ValueError(
                "submodule is missing, dirty, or at the wrong commit"
            )
        commit, path, *_ = line[1:].split()
        observed_submodules[path] = commit
    if observed_submodules != expected_submodules:
        raise ValueError("submodule object graph does not match source lock")

    overlay = lock["downstream_overlay"]
    require_digest(engine_root, overlay["patch"], "downstream patch")
    require_digest(engine_root, overlay["metadata"], "downstream metadata")
    for item in overlay["files"]:
        require_digest(engine_root, item, "overlay file")
        destination = item.get("destination")
        if not isinstance(destination, str) or not destination:
            raise ValueError("overlay destination is invalid")
    for item in lock["build_recipe"]:
        require_digest(engine_root, item, "build recipe")

    subprocess.run(
        [
            "git",
            "-C",
            str(checkout),
            "apply",
            "--check",
            str(engine_root / overlay["patch"]["path"]),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("checkout", type=Path)
    args = parser.parse_args()
    verify(Path(__file__).resolve().parent, args.checkout.resolve())
    print("Locked Asahi source graph and downstream overlay verified")


if __name__ == "__main__":
    main()
