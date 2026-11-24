#!/usr/bin/env python3
"""Check the glossary's source paths and feature folder coverage."""

from pathlib import Path
import re


GLOSSARY = Path("docs/GLOSSARY.md")
FEATURES = Path("lib/features")
COLUMNS = ["Term", "Code names", "Where", "Means", "Not to confuse with"]
WHERE_PATHS = re.compile(r"`([^`]+)`(?:,\s*`([^`]+)`)?")


def check_glossary(root: Path) -> list[str]:
    root = root.resolve()
    glossary = root / GLOSSARY
    if not glossary.is_file():
        return [f"Missing glossary: {GLOSSARY}"]

    errors = []
    covered = set()
    in_table = False
    for number, raw in enumerate(glossary.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line.startswith("|"):
            in_table = False
            continue
        cells = [cell.strip() for cell in line[1:].removesuffix("|").split("|")]
        if cells == COLUMNS:
            in_table = True
            continue
        if not in_table:
            continue
        if all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells):
            continue
        match = WHERE_PATHS.fullmatch(cells[2]) if len(cells) == len(COLUMNS) else None
        if not match:
            errors.append(f"{GLOSSARY}:{number}: use one or two backticked paths in Where")
            continue
        for value in filter(None, match.groups()):
            path = Path(value)
            target = root / path
            if path.is_absolute() or ".." in path.parts or not target.resolve().is_relative_to(root):
                errors.append(f"{GLOSSARY}:{number}: Where path must be relative to the repository: {value}")
            elif not target.exists():
                errors.append(f"{GLOSSARY}:{number}: missing Where path: {value}")
            elif path.parts[:2] == FEATURES.parts and len(path.parts) > 2:
                covered.add(path.parts[2])

    for folder in sorted((root / FEATURES).glob("*")):
        if folder.is_dir() and folder.name not in covered:
            errors.append(f"{GLOSSARY}: add a row for {FEATURES / folder.name}")
    return errors


if __name__ == "__main__":
    problems = check_glossary(Path(__file__).resolve().parents[1])
    for problem in problems:
        print(problem)
    raise SystemExit(int(bool(problems)))
