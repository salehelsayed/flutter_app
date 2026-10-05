import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dart_executable import resolve_dart


def _executable(path, body='#!/bin/sh\nexit 0\n'):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    path.chmod(0o755)
    return path


class ResolveDartTest(unittest.TestCase):
    def test_flutter_symlink_resolves_to_bundled_sdk_dart(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            flutter_dart = _executable(root / 'flutter/bin/dart')
            bundled = _executable(root / 'flutter/bin/cache/dart-sdk/bin/dart')
            link = root / 'bin/dart'
            link.parent.mkdir()
            link.symlink_to(flutter_dart)
            self.assertEqual(resolve_dart({}, which=lambda _: str(link)), bundled)

    def test_version_manager_shim_is_not_resolved_to_the_manager(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manager = _executable(root / 'usr/bin/mise')
            shim = root / 'shims/dart'
            shim.parent.mkdir()
            shim.symlink_to(manager)
            bundled = _executable(root / 'flutter/bin/cache/dart-sdk/bin/dart')
            real = _executable(root / 'flutter/bin/dart')
            resolved = resolve_dart({}, which=lambda _: str(shim),
                                    manager_which=lambda _shim: str(real))
            self.assertEqual(resolved, bundled)
            self.assertNotEqual(resolved.name, 'mise')
            # Without a manager answer the shim itself (argv[0] == dart) is kept.
            self.assertEqual(resolve_dart({}, which=lambda _: str(shim),
                                          manager_which=lambda _shim: None), shim)

    def test_explicit_override_wins(self):
        with tempfile.TemporaryDirectory() as tmp:
            override = _executable(Path(tmp) / 'dart')
            self.assertEqual(
                resolve_dart({'MKNOON_REVIEW_DART': str(override)}, which=lambda _: None),
                override)


if __name__ == '__main__':
    unittest.main()
