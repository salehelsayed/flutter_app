"""Glossary checks discovered by the Linux metadata workflow."""

from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_glossary import check_glossary


class GlossaryChecksTest(unittest.TestCase):
    def test_glossary_tracks_paths_and_feature_folders(self):
        errors = check_glossary(Path(__file__).resolve().parents[2])
        self.assertFalse(errors, "\n".join(errors))

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            feature = root / "lib/features/example"
            feature.mkdir(parents=True)
            (feature / "example.dart").touch()
            docs = root / "docs"
            docs.mkdir()
            note = docs / "example.md"
            note.touch()
            (docs / "GLOSSARY.md").write_text(
                "| Term | Code names | Where | Means | Not to confuse with |\n"
                "| --- | --- | --- | --- | --- |\n"
                "| Example | Example | `lib/features/example/example.dart`, `docs/example.md` "
                "| Example. | |\n",
                encoding="utf-8",
            )
            self.assertEqual([], check_glossary(root))

            note.unlink()
            (feature.parent / "new_feature").mkdir()
            self.assertEqual(
                [
                    "docs/GLOSSARY.md:3: missing Where path: docs/example.md",
                    "docs/GLOSSARY.md: add a row for lib/features/new_feature",
                ],
                check_glossary(root),
            )
