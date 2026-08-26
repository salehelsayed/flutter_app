#!/usr/bin/env python3
"""Static interaction contract for the project evidence dashboard."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class DashboardShellTest(unittest.TestCase):
    def test_behavior_details_use_a_side_panel_instead_of_a_modal(self) -> None:
        html = (ROOT / "dashboard" / "index.html").read_text(encoding="utf-8")
        javascript = (ROOT / "dashboard" / "app.js").read_text(encoding="utf-8")

        self.assertIn('id="behavior-workspace"', html)
        self.assertIn('id="behavior-details"', html)
        self.assertIn('class="behavior-details"', html)
        self.assertNotIn("<dialog", html)
        self.assertIn('classList.add("has-selection")', javascript)
        self.assertNotIn("showModal()", javascript)

    def test_behavior_links_update_and_control_the_side_panel(self) -> None:
        javascript = (ROOT / "dashboard" / "app.js").read_text(encoding="utf-8")

        self.assertIn('button.setAttribute("aria-controls", "behavior-details")', javascript)
        self.assertIn("state.selectedBehaviorId = behavior.id", javascript)
        self.assertIn("syncBehaviorSelection()", javascript)

    def test_side_panel_avoids_table_duplicates_and_labels_proof_types(self) -> None:
        javascript = (ROOT / "dashboard" / "app.js").read_text(encoding="utf-8")

        self.assertNotIn('summaryDetail("Intent"', javascript)
        self.assertNotIn('summaryDetail("Code evidence"', javascript)
        self.assertNotIn('summaryDetail("Proof"', javascript)
        self.assertNotIn('detailCard("What this means"', javascript)
        self.assertNotIn("assessment.prepend", javascript)
        self.assertIn('element("h4", "", "Decision needed")', javascript)
        self.assertIn('"Implementation evidence",', javascript)
        self.assertIn("expandableDetailCard(", javascript)
        self.assertIn('device: "Device / simulator test"', javascript)


if __name__ == "__main__":
    unittest.main()
