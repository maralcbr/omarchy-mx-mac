#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Repack the authenticated deployed engine with a Python-only overlay."""
import argparse
import difflib
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile

BASE_SHA256 = '9e9277384b6c9e8b269cc79b1b24df7bfcdcbb898a596a677b74d1d18050aebe'
BASE_COMMIT = 'f0469cea0899f3efed8efead604174c7a53c4451'
VERSION = 'v0.9.2-omarchy.17'

_SPEC = importlib.util.spec_from_file_location(
    'verify_source_lock', Path(__file__).resolve().parent / 'verify-source-lock.py')
VERIFY = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(VERIFY)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def git(directory, *arguments):
    return subprocess.run(['git', '-C', str(directory), *arguments],
                          check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def archive_name(path):
    # build.sh flattens src/ into the package root; other Python packages keep their directory.
    return path.removeprefix('src/')


def apply_downstream_patch(patch, path, content):
    with tempfile.TemporaryDirectory() as scratch:
        target = Path(scratch) / path
        target.parent.mkdir(parents=True)
        target.write_bytes(content)
        git(scratch, 'init', '-q')
        try:
            git(scratch, 'apply', '--whitespace=nowarn', '--include=' + path, str(patch.resolve()))
        except subprocess.CalledProcessError as error:
            raise ValueError('downstream patch does not apply: ' + path) from error
        return target.read_bytes()


def upstream_delta(checkout, delta, archive, patch):
    # The base keeps its native runtime and m1n1, so upstream may only have changed the listed Python files.
    VERIFY.require_upstream_delta(delta, patch.read_text())
    changed = git(checkout, 'diff', '--name-only', delta['base_commit'], 'HEAD').decode().splitlines()
    if sorted(changed) != sorted(item['path'] for item in delta['files']):
        raise ValueError('upstream changes since the base differ from the source lock')
    overlay = {}
    for item in delta['files']:
        path = item['path']
        base = git(checkout, 'show', delta['base_commit'] + ':' + path)
        new = git(checkout, 'show', 'HEAD:' + path)
        if sha256(base) != item['upstream_base_sha256'] or sha256(new) != item['upstream_sha256']:
            raise ValueError('upstream delta digest mismatch: ' + path)
        if item['downstream_patched']:
            base = apply_downstream_patch(patch, path, base)
            new = apply_downstream_patch(patch, path, new)
            if sha256(base) != item['base_sha256'] or sha256(new) != item['sha256']:
                raise ValueError('patched upstream delta digest mismatch: ' + path)
        name = archive_name(path)
        try:
            shipped = archive.extractfile('./' + name).read()
        except KeyError as error:
            raise ValueError('base engine does not ship upstream file: ' + path) from error
        if sha256(shipped) != item['base_sha256']:
            raise ValueError('base engine differs from the upstream base: ' + path)
        overlay[name] = new
    return overlay


def require_base(data, lock):
    if sha256(data) != BASE_SHA256:
        raise ValueError('base must be the exact deployed omarchy.14 engine')
    # The archive digest alone does not say which upstream it was built from; the delta must start there too.
    build = lock['incremental_build']
    if build['base_sha256'] != BASE_SHA256 or build['upstream_delta']['base_commit'] != BASE_COMMIT:
        raise ValueError('source lock names a different base than the deployed omarchy.14 engine')


def rebuild(checkout, base, output):
    root = Path(__file__).resolve().parent
    data = base.read_bytes()
    lock = json.loads((root / 'source-lock.json').read_text())
    require_base(data, lock)
    VERIFY.verify_upstream(root, lock, checkout)
    records = lock['downstream_overlay']['files']
    expected = {item['path'] for item in records if item['destination'].startswith('src/')}
    actual = {str(p.relative_to(root)) for p in (root / 'overlay/src').glob('*.py')}
    if expected != actual:
        raise ValueError('Python overlay inventory differs from source lock')
    for item in records + lock['build_recipe'] + [lock['downstream_overlay']['patch']]:
        if sha256((root / item['path']).read_bytes()) != item['sha256']:
            raise ValueError('source lock digest mismatch: ' + item['path'])
    overlay = {Path(name).name: (root / name).read_bytes() for name in sorted(expected)}
    overlay['version.tag'] = (VERSION + '\n').encode()
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        # The engine carries its own installer metadata; the per-payload copy in the repository is a different file.
        if sha256(archive.extractfile('./installer_data.json').read()) != lock['validation_artifact']['metadata_sha256']:
            raise ValueError('base engine metadata differs from the source lock')
        delta = upstream_delta(checkout, lock['incremental_build']['upstream_delta'], archive,
                               root / lock['downstream_overlay']['patch']['path'])
        # The hook below rewrites the base archive's osinstall.py, so an upstream osinstall.py change would be lost.
        if delta.keys() & (overlay.keys() | {'osinstall.py'}):
            raise ValueError('upstream delta overlaps the downstream overlay or osinstall hook')
        overlay.update(delta)
        old = archive.extractfile('./osinstall.py').read().decode()
        block = '''                zinfo = self.pkg.getinfo(image)
                if zinfo.file_size % (4 * 1024) != 0:
                    raise Exception("The size of the rootfs image file must be a multiple of 4KiB.")
                with self.pkg.open(image) as sfd, \\
                    open(f"/dev/r{info.name}", "r+b") as dfd:
                    self.fdcopy(sfd, dfd, zinfo.file_size)
'''
        if old.count(block) != 1:
            raise ValueError('upstream image hook changed')
        new = old.replace(block, '                self.install_raw_image(image, info)\n')
        hook = '''    def install_raw_image(self, image, info):
        zinfo = self.pkg.getinfo(image)
        if zinfo.file_size % (4 * 1024) != 0:
            raise Exception("The size of the rootfs image file must be a multiple of 4KiB.")
        with self.pkg.open(image) as source, open(f"/dev/r{info.name}", "r+b") as target:
            self.fdcopy(source, target, zinfo.file_size)

'''
        new = new.replace('    def install(self, stub_ins):', hook + '    def install(self, stub_ins):')
        expected_patch = ''.join(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                             fromfile='a/src/osinstall.py', tofile='b/src/osinstall.py'))
        if expected_patch not in (root / 'patches/0001-omarchy-engine-runtime.patch').read_text():
            raise ValueError('incremental hook differs from source patch')
        overlay['osinstall.py'] = new.encode()
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open('xb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as gz:
            with tarfile.open(fileobj=gz, mode='w|', format=tarfile.PAX_FORMAT) as result:
                for member in archive.getmembers():
                    name = member.name.removeprefix('./')
                    if name in overlay or (name.startswith('._') and name[2:] in overlay):
                        continue
                    if '__pycache__' in name and any(Path(p).stem in name for p in overlay):
                        continue
                    result.addfile(member, archive.extractfile(member) if member.isfile() else None)
                for name, content in sorted(overlay.items()):
                    member = tarfile.TarInfo('./' + name)
                    member.mode = 0o644
                    member.mtime = 1786436181
                    member.size = len(content)
                    result.addfile(member, io.BytesIO(content))
    artifact = output.read_bytes()
    print(json.dumps({'file': str(output), 'size': len(artifact),
                      'sha256': sha256(artifact),
                      'base_sha256': BASE_SHA256}, sort_keys=True))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout', type=Path, help='asahi-installer checkout at the locked commit')
    parser.add_argument('base', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    rebuild(args.checkout.resolve(), args.base, args.output)
