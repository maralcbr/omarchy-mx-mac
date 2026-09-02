#!/usr/bin/env python3
"""Emit the unsigned M1 support catalog for local signing.

The document this writes is the exact payload the app verifies: signing is a
separate step (`catalog-signing.swift sign`) that needs the private
catalog-signing key, which this repository deliberately does not contain.

The catalog pins whole-file digests. When the payload was split for release
delivery, the sibling `<payload>.partNN` files are emitted as an additional
`parts` array on `payloadArtifact`; the whole-file digest and size stay
authoritative and the whole-file URL becomes informational.

Usage:
  make-unsigned-catalog.py --base-url URL --assets-dir DIR [--output FILE]
                           [--validity-days N]
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import re
from pathlib import Path

ENGINE_NAME = "installer-v0.9.0-omarchy.7.tar.gz"
METADATA_NAME = "installer_data.json"
PAYLOAD_NAME = "omarchy-2026.09.02-aarch64-apple-silicon-asahi-os-package.zip"

# Every Mac Asahi Linux supports today (M1 and M2 families). The 14-inch M1 Pro
# stays first: it is the qualified reference machine. The Mac Pro (2023) and
# all M3/M4 Macs are still work in progress upstream and are deliberately
# absent, so the app keeps refusing them.
DEVICE_IDENTIFIERS = [
    "apple,j314s",  # MacBook Pro 14" M1 Pro (reference)
    "apple,j314c",  # MacBook Pro 14" M1 Max
    "apple,j316s",  # MacBook Pro 16" M1 Pro
    "apple,j316c",  # MacBook Pro 16" M1 Max
    "apple,j274",   # Mac mini M1
    "apple,j293",   # MacBook Pro 13" M1
    "apple,j313",   # MacBook Air M1
    "apple,j456",   # iMac 24" M1 (4 ports)
    "apple,j457",   # iMac 24" M1 (2 ports)
    "apple,j375c",  # Mac Studio M1 Max
    "apple,j375d",  # Mac Studio M1 Ultra
    "apple,j413",   # MacBook Air 13" M2
    "apple,j415",   # MacBook Air 15" M2
    "apple,j493",   # MacBook Pro 13" M2
    "apple,j473",   # Mac mini M2
    "apple,j474s",  # Mac mini M2 Pro
    "apple,j414s",  # MacBook Pro 14" M2 Pro
    "apple,j414c",  # MacBook Pro 14" M2 Max
    "apple,j416s",  # MacBook Pro 16" M2 Pro
    "apple,j416c",  # MacBook Pro 16" M2 Max
    "apple,j475c",  # Mac Studio M2 Max
    "apple,j475d",  # Mac Studio M2 Ultra
]
DEVICE_IDENTIFIER = DEVICE_IDENTIFIERS[0]
ASAHI_INSTALLER_TAG = "v0.9.0"
ASAHI_INSTALLER_REVISION = "f0469cea0899f3efed8efead604174c7a53c4451"
ASAHI_INSTALLER_DATA_REVISION = "42648e71423eba308d2e3e6228253eff679b068b"
DOWNSTREAM_REVISION = "dff6311446439e1f29f0f2e6c0cf82a9a190e5bc"
ENGINE_VERSION = "v0.9.0-omarchy.7"
EVIDENCE_REVISION = "4.0.2-mac.1.10.090226"

MAXIMUM_PART_COUNT = 16
PART_PATTERN = re.compile(r"\.part(\d{2})$")
READ_BLOCK_BYTES = 8 * 1024 * 1024


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(READ_BLOCK_BYTES):
            value.update(block)
    return value.hexdigest()


def require_regular_file(path: Path) -> Path:
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"unsafe or missing asset: {path}")
    return path


def artifact(path: Path, base_url: str) -> dict:
    return {
        "sourceURL": f"{base_url}/{path.name}",
        "fileName": path.name,
        "sizeBytes": path.stat().st_size,
    }


def discover_parts(payload: Path) -> list[Path]:
    """Return the `<payload>.partNN` siblings in ascending part order."""
    parts = sorted(
        candidate
        for candidate in payload.parent.iterdir()
        if candidate.name.startswith(f"{payload.name}.part")
        and PART_PATTERN.search(candidate.name)
    )
    for index, part in enumerate(parts):
        require_regular_file(part)
        expected = f"{payload.name}.part{index:02d}"
        if part.name != expected:
            raise SystemExit(
                f"payload part sequence is not contiguous: expected {expected}, "
                f"found {part.name}"
            )
    return parts


def part_records(payload: Path, parts: list[Path], base_url: str) -> list[dict]:
    """Digest every part, proving they concatenate back into the payload."""
    if len(parts) == 1:
        raise SystemExit(
            f"a split payload needs at least two parts: found {parts[0].name}"
        )
    if len(parts) > MAXIMUM_PART_COUNT:
        raise SystemExit(
            f"payload is split into {len(parts)} parts; the app accepts at most "
            f"{MAXIMUM_PART_COUNT}"
        )

    whole = hashlib.sha256()
    records = []
    declared_bytes = 0
    for part in parts:
        part_hash = hashlib.sha256()
        with part.open("rb") as stream:
            while block := stream.read(READ_BLOCK_BYTES):
                part_hash.update(block)
                whole.update(block)
        size_bytes = part.stat().st_size
        if size_bytes == 0:
            raise SystemExit(f"payload part is empty: {part.name}")
        declared_bytes += size_bytes
        records.append(
            {
                "sourceURL": f"{base_url}/{part.name}",
                "fileName": part.name,
                "sizeBytes": size_bytes,
                "sha256": f"sha256:{part_hash.hexdigest()}",
            }
        )

    payload_bytes = payload.stat().st_size
    if declared_bytes != payload_bytes:
        raise SystemExit(
            f"payload parts sum to {declared_bytes} bytes but the payload is "
            f"{payload_bytes} bytes"
        )
    payload_digest = digest(payload)
    if whole.hexdigest() != payload_digest:
        raise SystemExit(
            "payload parts do not concatenate into the payload: "
            f"parts hash to sha256:{whole.hexdigest()}, payload is "
            f"sha256:{payload_digest}"
        )
    return records


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Emit the unsigned M1 support catalog."
    )
    parser.add_argument(
        "--base-url",
        required=True,
        help="release download base, without a trailing slash",
    )
    parser.add_argument(
        "--assets-dir",
        required=True,
        type=Path,
        help="directory holding the engine, metadata, and payload assets",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="catalog path to write (default: <assets-dir>/catalog.json)",
    )
    parser.add_argument(
        "--validity-days",
        type=int,
        default=90,
        help="catalog validity window in days (default: 90)",
    )
    arguments = parser.parse_args()

    if not arguments.base_url.startswith("https://"):
        raise SystemExit(f"--base-url must be https: {arguments.base_url}")
    if arguments.base_url.endswith("/"):
        raise SystemExit(
            f"--base-url must not end with a slash: {arguments.base_url}"
        )
    if arguments.validity_days < 1:
        raise SystemExit("--validity-days must be a positive integer")
    if not arguments.assets_dir.is_dir() or arguments.assets_dir.is_symlink():
        raise SystemExit(f"unsafe or missing assets directory: {arguments.assets_dir}")
    if arguments.output is None:
        arguments.output = arguments.assets_dir / "catalog.json"
    return arguments


def main() -> None:
    arguments = parse_arguments()
    assets = arguments.assets_dir
    engine = require_regular_file(assets / ENGINE_NAME)
    metadata = require_regular_file(assets / METADATA_NAME)
    payload = require_regular_file(assets / PAYLOAD_NAME)

    payload_artifact = artifact(payload, arguments.base_url)
    parts = discover_parts(payload)
    if parts:
        payload_artifact["parts"] = part_records(payload, parts, arguments.base_url)

    issued = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    expires = issued + datetime.timedelta(days=arguments.validity_days)

    catalog = {
        "schemaVersion": 2,
        "sequence": int(issued.timestamp()),
        "issuedAt": issued.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "expiresAt": expires.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "models": [
            {
                "deviceIdentifier": device_identifier,
                "status": "enabled",
                "asahiInstallerTag": ASAHI_INSTALLER_TAG,
                "asahiInstallerRevision": ASAHI_INSTALLER_REVISION,
                "asahiInstallerDataRevision": ASAHI_INSTALLER_DATA_REVISION,
                "downstreamRevision": DOWNSTREAM_REVISION,
                "engineVersion": ENGINE_VERSION,
                "engineDigest": f"sha256:{digest(engine)}",
                "metadataDigest": f"sha256:{digest(metadata)}",
                "payloadDigest": f"sha256:{digest(payload)}",
                "evidenceRevision": EVIDENCE_REVISION,
                "engineArtifact": artifact(engine, arguments.base_url),
                "metadataArtifact": artifact(metadata, arguments.base_url),
                "payloadArtifact": payload_artifact,
            }
            for device_identifier in DEVICE_IDENTIFIERS
        ],
    }

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(catalog, indent=2) + "\n")
    print(f"unsigned_catalog={arguments.output}")
    print(f"unsigned_catalog_sha256={digest(arguments.output)}")
    print(f"sequence={catalog['sequence']}")
    print(f"payload_parts={len(parts)}")


if __name__ == "__main__":
    main()
