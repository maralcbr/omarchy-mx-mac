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

BASE_SHA256 = '9e9277384b6c9e8b269cc79b1b24df7bfcdcbb898a596a677b74d1d18050aebe'
VERSION = 'v0.9.1-omarchy.16'


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def verify_checkout(root, lock, checkout):
    spec = importlib.util.spec_from_file_location('verify_source_lock', root / 'verify-source-lock.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.verify_upstream(root, lock, checkout)


def upstream_delta(checkout, delta, archive):
    # The base keeps its native runtime and m1n1, so upstream may only have changed the listed Python files.
    changed = subprocess.run(
        ['git', '-C', str(checkout), 'diff', '--name-only', delta['base_commit'], 'HEAD'],
        check=True, text=True, stdout=subprocess.PIPE,
    ).stdout.splitlines()
    if sorted(changed) != sorted(item['path'] for item in delta['files']):
        raise ValueError('upstream changes since the base differ from the source lock')
    overlay = {}
    for item in delta['files']:
        path = item['path']
        if not path.endswith('.py'):
            raise ValueError('upstream delta must be Python only: ' + path)
        if sha256(archive.extractfile('./' + path).read()) != item['base_sha256']:
            raise ValueError('base engine differs from the upstream base: ' + path)
        content = (checkout / path).read_bytes()
        if sha256(content) != item['sha256']:
            raise ValueError('upstream delta digest mismatch: ' + path)
        overlay[path] = content
    return overlay


def rebuild(checkout, base, output):
    root = Path(__file__).resolve().parent
    data = base.read_bytes()
    if sha256(data) != BASE_SHA256:
        raise ValueError('base must be the exact deployed omarchy.14 engine')
    lock = json.loads((root / 'source-lock.json').read_text())
    verify_checkout(root, lock, checkout)
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
        overlay.update(upstream_delta(checkout, lock['incremental_build']['upstream_delta'], archive))
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
