from __future__ import annotations

import json
import tempfile
import tomllib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class RolloverProjectIntegrationTests(unittest.TestCase):
    def assert_native_compaction(self, root: Path) -> None:
        # These machine-local files are deliberately untracked. A fresh CI
        # checkout has no project overrides; validate overrides when present.
        path = root / ".codex" / "config.toml"
        raw = path.read_text("utf-8") if path.exists() else ""
        config = tomllib.loads(raw)
        budget = config.get("features", {}).get("token_budget", {"enabled": False})
        self.assertEqual(budget, {"enabled": False})
        self.assertNotIn("context_rollover.py", raw)
        self.assertNotIn("functions.new_context", raw)
        self.assertNotIn("reminder_message_template", raw)
        self.assertNotIn("auto_compact_fallback_prompt", raw)

    def assert_no_checkpoint_hooks(self, root: Path) -> None:
        path = root / ".codex" / "hooks.json"
        raw = path.read_text("utf-8") if path.exists() else ""
        hooks = json.loads(raw)["hooks"] if path.exists() else {}
        if path.exists():
            self.assertIn("PreToolUse", hooks)
            self.assertIn("PostToolUse", hooks)
        for event in ("PreCompact", "PostCompact", "SessionStart", "Stop"):
            self.assertNotIn(event, hooks)
        self.assertNotIn("context_rollover.py", raw)

    def test_project_uses_native_compaction_without_token_budget_checkpointing(
        self,
    ) -> None:
        self.assert_native_compaction(ROOT)

    def test_checkpoint_lifecycle_hooks_are_absent_without_replacing_other_hooks(
        self,
    ) -> None:
        self.assert_no_checkpoint_hooks(ROOT)

    def test_fresh_checkout_needs_no_private_editor_configuration(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assert_native_compaction(root)
            self.assert_no_checkpoint_hooks(root)

    def test_present_local_overrides_still_reject_checkpointing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".codex").mkdir()
            config = root / ".codex" / "config.toml"
            config.write_text("[features.token_budget]\nenabled = false\n", "utf-8")
            self.assert_native_compaction(root)
            config.write_text("[features.token_budget]\nenabled = true\n", "utf-8")
            with self.assertRaises(AssertionError):
                self.assert_native_compaction(root)
            hooks = root / ".codex" / "hooks.json"
            preserved = {"PreToolUse": [], "PostToolUse": []}
            hooks.write_text(json.dumps({"hooks": preserved}), "utf-8")
            self.assert_no_checkpoint_hooks(root)
            for event in ("PreCompact", "PostCompact", "SessionStart", "Stop"):
                with self.subTest(event=event):
                    hooks.write_text(json.dumps({"hooks": {**preserved, event: []}}), "utf-8")
                    with self.assertRaises(AssertionError):
                        self.assert_no_checkpoint_hooks(root)

    def test_readme_describes_native_compaction_and_dormant_tooling(self) -> None:
        readme = (ROOT / "codex-memory" / "README.md").read_text("utf-8")
        normalized = " ".join(readme.split())

        self.assertIn("Native context compaction (checkpoint rollover disabled)", readme)
        self.assertIn("does not run `context_rollover.py prepare`", normalized)
        self.assertIn("dormant in ordinary project sessions", normalized)
        self.assertIn("start a new session", normalized)


if __name__ == "__main__":
    unittest.main()
