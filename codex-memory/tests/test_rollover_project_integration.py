from __future__ import annotations

import json
import tomllib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class RolloverProjectIntegrationTests(unittest.TestCase):
    def test_project_uses_native_compaction_without_token_budget_checkpointing(
        self,
    ) -> None:
        with (ROOT / ".codex" / "config.toml").open("rb") as handle:
            config = tomllib.load(handle)

        budget = config["features"]["token_budget"]
        self.assertEqual(budget, {"enabled": False})

        raw = (ROOT / ".codex" / "config.toml").read_text("utf-8")
        self.assertNotIn("context_rollover.py", raw)
        self.assertNotIn("functions.new_context", raw)
        self.assertNotIn("reminder_message_template", raw)
        self.assertNotIn("auto_compact_fallback_prompt", raw)

    def test_checkpoint_lifecycle_hooks_are_absent_without_replacing_other_hooks(
        self,
    ) -> None:
        raw = (ROOT / ".codex" / "hooks.json").read_text("utf-8")
        hooks = json.loads(raw)["hooks"]

        self.assertIn("PreToolUse", hooks)
        self.assertIn("PostToolUse", hooks)
        for event in ("PreCompact", "PostCompact", "SessionStart", "Stop"):
            self.assertNotIn(event, hooks)
        self.assertNotIn("context_rollover.py", raw)

    def test_readme_describes_native_compaction_and_dormant_tooling(self) -> None:
        readme = (ROOT / "codex-memory" / "README.md").read_text("utf-8")
        normalized = " ".join(readme.split())

        self.assertIn("Native context compaction (checkpoint rollover disabled)", readme)
        self.assertIn("does not run `context_rollover.py prepare`", normalized)
        self.assertIn("dormant in ordinary project sessions", normalized)
        self.assertIn("start a new session", normalized)


if __name__ == "__main__":
    unittest.main()
