import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('maestro_flow_runner', Path(__file__).parents[1] / 'maestro_flow_runner.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class FlowReceiptTests(unittest.TestCase):
    def validate(self, cases, **counts):
        with tempfile.TemporaryDirectory() as folder:
            report = Path(folder) / 'result.xml'
            attributes = ' '.join(f'{key}="{value}"' for key, value in counts.items())
            report.write_text(f'<testsuites><testsuite {attributes}>{cases}</testsuite></testsuites>')
            return runner.validate_flow_receipts(report, ['production_group_send'])

    def test_exact_pass(self):
        self.assertEqual(self.validate('<testcase name="production_group_send"/>', tests=1), ['production_group_send'])

    def test_missing_duplicate_and_foreign_receipts(self):
        for cases in ['', '<testcase name="other"/>', '<testcase name="production_group_send"/><testcase name="production_group_send"/>']:
            with self.subTest(cases=cases), self.assertRaises(ValueError):
                self.validate(cases)

    def test_skipped_and_failed_receipts(self):
        for tag in ['failure', 'error', 'skipped']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                self.validate(f'<testcase name="production_group_send"><{tag}/></testcase>')

    def test_failure_status_without_child_element_is_rejected(self):
        for status in ['ERROR', 'FAILED', 'SKIPPED', 'DISABLED', 'CANCELLED', 'CANCELED']:
            with self.subTest(status=status), self.assertRaises(ValueError):
                self.validate(f'<testcase name="production_group_send" status="{status}"/>')

    def test_suite_incompleteness_is_not_hidden_by_case(self):
        with self.assertRaises(ValueError):
            self.validate('<testcase name="production_group_send"/>', skipped=1)


if __name__ == '__main__':
    unittest.main()
