#!/usr/bin/env python3
"""ap.py refuses unfiltered reads while a system photo picker is open (owner picker rule, 11-02 slip)."""
import importlib.util
import os
import unittest

spec = importlib.util.spec_from_file_location("ap", os.path.join(os.path.dirname(os.path.abspath(__file__)), "ap.py"))
ap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ap)

PICKER = '''<XCUIElementTypeButton type="XCUIElementTypeButton" name="Cancel" label="Cancel"/>
<XCUIElementTypeImage type="XCUIElementTypeImage" name="Photo, 02 November, 16:09" label="Photo, 02 November, 16:09"/>
<XCUIElementTypeImage type="XCUIElementTypeImage" name="Screenshot, 03 October, 12:48" label="Screenshot, 03 October, 12:48"/>'''
MKNOON = '''<XCUIElementTypeButton type="XCUIElementTypeButton" name="Open your page" label="Open your page"/>
<XCUIElementTypeStaticText type="XCUIElementTypeStaticText" name="Photo" label="Photo"/>'''


class PickerGuard(unittest.TestCase):
    def test_unfiltered_src_is_refused_while_picker_open(self):
        with self.assertRaises(SystemExit) as e:
            ap.picker_guard("src", [], PICKER)
        self.assertIn("PICKER OPEN", str(e.exception))

    def test_regex_filter_is_refused_while_picker_open(self):
        with self.assertRaises(SystemExit):
            ap.picker_guard("src", ["Photo|Screenshot"], PICKER)

    def test_exact_label_filter_is_allowed_while_picker_open(self):
        self.assertEqual(ap.picker_guard("src", ["Photo, 02 November, 16:09"], PICKER), "Photo, 02 November, 16:09")

    def test_screenshot_is_refused_while_picker_open(self):
        with self.assertRaises(SystemExit):
            ap.picker_guard("shot", ["x"], PICKER)

    def test_find_needs_exact_predicate_while_picker_open(self):
        with self.assertRaises(SystemExit):
            ap.picker_guard("find", ["label CONTAINS 'Photo'"], PICKER)
        self.assertIsNone(ap.picker_guard("tap", ["label == 'Add'"], PICKER))

    def test_mknoon_screen_is_unrestricted(self):
        self.assertFalse(ap.picker_open(MKNOON))
        self.assertIsNone(ap.picker_guard("src", [], MKNOON))
        self.assertIsNone(ap.picker_guard("shot", ["x"], MKNOON))


if __name__ == "__main__":
    unittest.main()
