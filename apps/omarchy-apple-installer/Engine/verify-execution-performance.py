#!/usr/bin/env python3
"""Test a trusted release archive's work budget using tiny in-memory devices.

Runs the archived Python adapter, not the checkout's adapter. The required
SHA-256 binds the measurement to the artifact under review. No real Asahi disk
modules, helper, authorization, or Recovery commands are used.
"""
import argparse
import ast
from contextlib import contextmanager
import hashlib
import importlib.abc
import importlib.util
import inspect
import io
import json
import os
from pathlib import Path
import sys
import tarfile
from types import SimpleNamespace
from unittest.mock import patch
import zipfile


class ArchiveModules(importlib.abc.MetaPathFinder, importlib.abc.Loader):
    def __init__(self, archive):
        self.archive = archive

    def find_spec(self, fullname, path=None, target=None):
        if fullname.startswith('omarchy_'):
            return importlib.util.spec_from_loader(fullname, self)
        return None

    def create_module(self, spec):
        return None

    def exec_module(self, module):
        with tarfile.open(self.archive) as archive:
            source = archive.extractfile('./' + module.__name__ + '.py').read()
        filename = f'{self.archive}!/{module.__name__}.py'
        exec(compile(source, filename, 'exec'), module.__dict__)


def raw_write_hook_is_used(archive):
    """Exercise the archived upstream install method's dispatch, with fake I/O."""
    with tarfile.open(archive) as package:
        tree = ast.parse(package.extractfile('./osinstall.py').read())
    cls = next(node for node in tree.body if isinstance(node, ast.ClassDef)
               and node.name == 'OSInstaller')
    method = next(node for node in cls.body if isinstance(node, ast.FunctionDef)
                  and node.name == 'install')
    calls = []

    def reject_direct_open(*args, **kwargs):
        raise ValueError('raw write bypassed the overridable hook')

    namespace = dict(
        p_progress=lambda *_: None, p_plain=lambda *_: None,
        logging=SimpleNamespace(info=lambda *_: None), os=os,
        m1n1=SimpleNamespace(build=lambda *_: None), open=reject_direct_open,
    )
    exec(compile(ast.Module(body=[method], type_ignores=[]),
                 str(archive) + '!/osinstall.py', 'exec'), namespace)
    fake = SimpleNamespace(
        ucache=None, template={'partitions': [{'image': 'boot.img'}, {'image': 'root.img'}],
                              'boot_object': 'test.bin'},
        part_info=[SimpleNamespace(name='boot'), SimpleNamespace(name='root')],
        install_raw_image=lambda image, info: calls.append((image, info.name)),
        flush_progress=lambda: None, efi_part=None,
        pkg=SimpleNamespace(getinfo=lambda _: SimpleNamespace(file_size=4096),
                            open=lambda _: io.BytesIO(bytes(4096))),
    )
    try:
        namespace['install'](fake, SimpleNamespace(boot_obj_path='unused'))
    except ValueError:
        return False
    return calls == [('boot.img', 'boot'), ('root.img', 'root')]


def measure(archive):
    sys.meta_path.insert(0, ArchiveModules(archive))
    fixture = Path(__file__).parent / 'overlay/tests/test_omarchy_asahi.py'
    spec = importlib.util.spec_from_file_location('fixture', fixture)
    f = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(f)
    case = f.AsahiStage1AdapterTests()
    case.setUp()
    try:
        installer = f.FakeInstaller(f.FakeDiskUtil([[case.free]]))
        installer.dutil.stub_icon_path = str(case.installed_stub_icon)
        installer.dutil.mount_points = {'disk0s5': str(case.installed_esp)}
        reads = {'disk0s6': 0, 'disk0s7': 0}
        writes = {'disk0s6': 0, 'disk0s7': 0}

        class RawReader(io.BytesIO):
            def __init__(self, name):
                super().__init__(case.raw_images[name])
                self.name = name

            def read(self, *args):
                data = super().read(*args)
                reads[self.name] += len(data)
                return data

        @contextmanager
        def writer(name):
            with io.BytesIO() as stream:
                yield stream
                case.raw_images[name] = stream.getvalue()
                writes[name] += len(case.raw_images[name])

        # Older adapters delegate raw writes to OSInstaller; keep that seam
        # in memory too, so the same workload can demonstrate the regression.
        def legacy_write(osinstaller, image, part):
            with osinstaller.pkg.open(image) as source, writer(part.name) as target:
                target.write(source.read())

        f.FakeOSInstaller.install_raw_image = legacy_write
        kwargs = dict(
            installer=installer, metadata_path=str(case.metadata),
            payload_path=str(case.payload), stub_size=2 * f.GIB,
            raw_partition_opener=RawReader, raw_partition_writer=writer,
            image_flush=lambda _: None,
        )
        parameters = inspect.signature(f.AsahiStage1Adapter).parameters
        with patch.dict(os.environ, {'OMARCHY_FULL_READBACK': '0'}):
            adapter = f.AsahiStage1Adapter(**{k: v for k, v in kwargs.items() if k in parameters})
        original_read = zipfile.ZipExtFile.read
        expanded = 0

        def count_read(stream, *args, **kwargs):
            nonlocal expanded
            block = original_read(stream, *args, **kwargs)
            if stream.name in ('boot.img', 'root.img'):
                expanded += len(block)
            return block

        with patch.object(zipfile.ZipExtFile, 'read', count_read):
            adapter.preflight(case.plan)
        adapter.prepare_target(case.plan)
        adapter.install_stub_and_esp(case.plan)
        return {
            'upstream_raw_write_hook': raw_write_hook_is_used(archive),
            'preflight_expanded_image_bytes': expanded,
            'root_readback_bytes': reads['disk0s7'],
            'boot_readback_bytes': reads['disk0s6'],
            'root_written_bytes': writes['disk0s7'],
        }
    finally:
        case.tearDown()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', required=True, type=Path)
    parser.add_argument('--sha256', required=True)
    args = parser.parse_args()
    digest = hashlib.sha256(args.archive.read_bytes()).hexdigest()
    if digest != args.sha256:
        parser.exit(1, 'Archive digest mismatch; no archive code executed\n')
    result = measure(args.archive)
    print(json.dumps(dict(archive=args.archive.name, sha256=digest, **result), sort_keys=True))
    if result != dict(upstream_raw_write_hook=True, preflight_expanded_image_bytes=0, root_readback_bytes=0,
                      boot_readback_bytes=4096, root_written_bytes=4096):
        parser.exit(1, 'Execution engine exceeds the installation work budget\n')


if __name__ == '__main__':
    main()
