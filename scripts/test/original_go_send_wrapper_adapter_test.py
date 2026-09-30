from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_original_go_send_wrapper import PACKAGE, verify_completion


class OriginalGoWrapperReceiptTest(unittest.TestCase):
    def test_exact_uncached_completion(self):
        self.assertEqual(verify_completion('TestSendMessage\nTestOther\n',
                         f'ok\t{PACKAGE}\t1.234s\n', 0), ['TestSendMessage'])

    def test_nonzero_child_is_never_hidden_by_success_text(self):
        with self.assertRaises(ValueError):
            verify_completion('TestSendMessage', f'ok\t{PACKAGE}\t1.234s', 27)

    def test_empty_duplicate_or_unrelated_catalog_is_incomplete(self):
        for listing in ['', 'TestOther', 'TestSendMessage\nTestSendMessage']:
            with self.subTest(listing=listing), self.assertRaises(ValueError):
                verify_completion(listing, f'ok\t{PACKAGE}\t1.234s', 0)

    def test_stale_missing_wrong_duplicate_or_failed_receipts_are_incomplete(self):
        valid = f'ok\t{PACKAGE}\t1.234s'
        for output in ['', valid.replace(PACKAGE, 'other/package'),
                       valid + '\n' + valid, valid + ' (cached)',
                       valid + '\nFAIL', valid + ' [no tests to run]',
                       valid + ' [no test files]']:
            with self.subTest(output=output), self.assertRaises(ValueError):
                verify_completion('TestSendMessage', output, 0)


if __name__ == '__main__':
    unittest.main()
