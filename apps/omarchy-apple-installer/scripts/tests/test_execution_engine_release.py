"""Check the engine selected for execution, independently of inspection bundling."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('execution_engine_release', SCRIPTS / 'execution_engine_release.py')


class ExecutionEngineReleaseTests(unittest.TestCase):
    def setUp(self):
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.lock = json.loads((SCRIPTS.parent / 'Engine/source-lock.json').read_text())
        artifact = self.lock['validation_artifact']
        self.model = {
            'status': 'enabled', 'deviceIdentifier': 'apple,j314s',
            'engineVersion': artifact['filename'].removeprefix('installer-').removesuffix('.tar.gz'),
            'engineDigest': 'sha256:' + artifact['sha256'],
            'engineArtifact': {'fileName': artifact['filename'], 'sizeBytes': artifact['size_bytes']},
        }

    def test_qualified_engine_is_accepted(self):
        self.module.verify_catalog({'models': [self.model]}, self.lock)

    def test_each_part_of_the_execution_pin_is_bound(self):
        for field in ('engineVersion', 'engineDigest', 'fileName', 'sizeBytes'):
            with self.subTest(field=field):
                model = copy.deepcopy(self.model)
                target = model if field.startswith('engine') else model['engineArtifact']
                target[field] = 1 if field == 'sizeBytes' else 'old-engine'
                with self.assertRaisesRegex(ValueError, 'qualified execution engine'):
                    self.module.verify_catalog({'models': [model]}, self.lock)

    def test_every_enabled_model_is_checked(self):
        wrong = dict(self.model, engineDigest='sha256:' + '0' * 64)
        with self.assertRaises(ValueError):
            self.module.verify_catalog({'models': [self.model, wrong]}, self.lock)

    def test_both_release_templates_select_the_qualified_engine(self):
        for name in ('release-inputs.template.json', 'release-inputs-aurora.template.json'):
            with self.subTest(name=name):
                inputs = json.loads((SCRIPTS / name).read_text())
                self.assertEqual(inputs['engine_name'], self.model['engineArtifact']['fileName'])
                self.assertEqual(inputs['engine_version'], self.model['engineVersion'])
