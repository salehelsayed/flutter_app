"""Additive contracts for Maestro inventory ownership and proof boundaries."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import device_campaign_preflight as preflight
import testing_inventory as inventory


class MaestroMigrationMetadataTest(unittest.TestCase):
    def check(self, **updates):
        return {
            'kind': 'sims',
            'device_roles': ['android_physical', 'android_emulator'],
            'ui_driver': 'maestro',
            'ui_driver_reason': 'Native notification requests need protocol receipts.',
            'maestro_flows': ['integration_test/maestro/production_group_send.yaml'],
            **updates,
        }

    def test_explicit_owner_and_narrow_proof_boundary_are_accepted(self):
        self.assertEqual(preflight.validate_metadata(self.check()), [])

    def test_incomplete_duplicate_or_escaping_flow_paths_are_rejected(self):
        for flows in (None, [], ['integration_test/maestro/a.yaml'] * 2,
                      [None], [{'path': 'a.yaml'}], ['integration_test/legacy.yaml'],
                      ['integration_test/maestro/../legacy.yaml'],
                      ['integration_test/maestro/sub/../../legacy.yaml']):
            with self.subTest(flows=flows):
                self.assertTrue(preflight.validate_metadata(self.check(maestro_flows=flows)))

    def test_maestro_does_not_remove_existing_campaign_justification(self):
        for driver in ('existing_campaign', 'maestro'):
            with self.subTest(driver=driver):
                self.assertTrue(preflight.validate_metadata(
                    self.check(ui_driver=driver, ui_driver_reason='')))

    def test_discovery_recognizes_only_flow_files_in_the_owned_tree(self):
        self.assertEqual(inventory._family('integration_test/maestro/a.yaml'), 'maestro_flow')
        self.assertEqual(inventory._family('integration_test/maestro/sub/a.yml'), 'maestro_flow')
        self.assertIsNone(inventory._family('integration_test/maestro/readme.md'))
        self.assertIsNone(inventory._family('assets/a.yaml'))


if __name__ == '__main__':
    unittest.main()
