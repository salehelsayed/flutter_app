#!/usr/bin/env python3
"""Focused host native process-fencing regression; never controls a device."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='mknoon-notification-owner-') as directory:
    executable = str(Path(directory) / 'owner-test')
    subprocess.run(['xcrun', 'swiftc', '-o', executable,
                    str(ROOT / 'ios/NotificationService/IosAppVisibilitySnapshot.swift'),
                    str(ROOT / 'scripts/test/notification_async_owner_native_test.swift')], check=True)
    subprocess.run([executable], check=True, timeout=30)
