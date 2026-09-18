#!/usr/bin/env python3
"""Keep signed execution catalogs aligned with the qualified engine artifact.

The app's bundled read-only inspection engine has a separate lifecycle and is
intentionally not checked here. A new execution engine requires an updated
source lock after qualification, not a version-number-only override.
"""
import argparse
import json
import os
from pathlib import Path

DEFAULT_LOCK = Path(__file__).resolve().parents[1] / 'Engine/source-lock.json'


def verify_catalog(catalog, lock):
    artifact = lock['validation_artifact']
    name = artifact['filename']
    version = name.removeprefix('installer-').removesuffix('.tar.gz')
    expected = (version, 'sha256:' + artifact['sha256'], name, artifact['size_bytes'])
    for model in catalog['models']:
        if model.get('status') != 'enabled':
            continue
        delivery = model.get('engineArtifact', {})
        actual = (model.get('engineVersion'), model.get('engineDigest'),
                  delivery.get('fileName'), delivery.get('sizeBytes'))
        if actual != expected:
            raise ValueError(
                f"{model.get('deviceIdentifier')}: catalog must select qualified execution engine "
                f"{version} ({artifact['sha256']}); selected {model.get('engineVersion')}"
            )


def verify_catalog_file(catalog, lock_path=None):
    path = Path(lock_path or os.environ.get('OMARCHY_ENGINE_SOURCE_LOCK', DEFAULT_LOCK))
    verify_catalog(catalog, json.loads(path.read_text()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', required=True, type=Path)
    parser.add_argument('--source-lock', type=Path)
    args = parser.parse_args()
    try:
        verify_catalog_file(json.loads(args.catalog.read_text()), args.source_lock)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f'execution-engine: {error}\n')
    print('execution_engine=qualified')


if __name__ == '__main__':
    main()
