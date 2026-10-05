"""Locate the Dart executable for host contract tests.

A Flutter SDK `dart` (often symlinked onto PATH) resolves to the SDK's bundled
`cache/dart-sdk/bin/dart`. A version-manager shim (mise, asdf) is a symlink to
the manager binary, which dispatches on the invoked name; resolving it would
run the manager itself, so the real tool is asked of the manager instead.
"""
import os
from pathlib import Path
import shutil
import subprocess


def _mise_which(shim):
    mise = shutil.which('mise')
    if not mise:
        return None
    try:
        run = subprocess.run([mise, 'which', 'dart'], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    found = run.stdout.strip()
    return found if run.returncode == 0 and found else None


def resolve_dart(environ=os.environ, which=shutil.which, manager_which=_mise_which):
    found = Path(environ.get('MKNOON_REVIEW_DART') or which('dart') or '/unavailable/dart')
    resolved = found.resolve()
    if resolved.name != 'dart':
        real = manager_which(found)
        if real is None:
            return found
        resolved = Path(real).resolve()
    bundled = resolved.parent / 'cache/dart-sdk/bin/dart'
    return bundled if bundled.is_file() else resolved
