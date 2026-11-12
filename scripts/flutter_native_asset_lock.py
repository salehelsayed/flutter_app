"""Serialize Flutter's native/test asset installation within one checkout.

Flutter 3.47.2 awaits native asset build and manifest copy before package:test's
machine reporter starts. A genuine testStart releases setup ownership; startup
failure or an unrecognized stream keeps ownership until process exit.
"""
import fcntl
import json
import os
import re
from pathlib import Path
import time


def guarded_command(command):
    return (len(command) >= 7 and command[:4] == ['flutter', 'test', '--no-pub', '--machine']
            and re.fullmatch(r'--concurrency=[1-9]\d*', command[4]) and command[5] == '--timeout=2m'
            and all(p.startswith('test/') and p.endswith('_test.dart') for p in command[6:]))


class FlutterNativeAssetLock:
    def __init__(self, root, command, deadline, cancel=None):
        self.enabled = guarded_command(command)
        self.root = Path(root).resolve()
        self.deadline, self.cancel = deadline, cancel
        self.handle = None
        self.ready = not self.enabled
        self.buffer = bytearray()
        self.dropping_line = False

    def __enter__(self):
        if not self.enabled:
            return self
        directory = self.root / '.codex-test-logs'
        directory.mkdir(exist_ok=True)
        if directory.is_symlink():
            raise OSError('Native asset lock directory must not be a symlink')
        fd = os.open(directory / 'flutter-native-assets.lock',
                     os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        self.handle = os.fdopen(fd, 'a+b')
        try:
            while time.monotonic() < self.deadline:
                if self.cancel is not None and self.cancel.is_set():
                    break
                try:
                    fcntl.flock(self.handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    self.ready = True
                    break
                except BlockingIOError:
                    time.sleep(min(.05, max(0, self.deadline - time.monotonic())))
            if not self.ready:
                self.release()
            return self
        except BaseException:
            self.release()
            raise

    def feed_stdout(self, data):
        if self.handle is None:
            return
        for part in data.splitlines(keepends=True):
            ended = part.endswith(b'\n')
            if not self.dropping_line:
                self.buffer.extend(part)
                if len(self.buffer) > 64 * 1024:
                    self.buffer.clear()
                    self.dropping_line = True
            if ended:
                if not self.dropping_line:
                    try:
                        event = json.loads(self.buffer)
                    except (ValueError, UnicodeDecodeError):
                        event = None
                    if isinstance(event, dict) and event.get('type') == 'testStart':
                        test = event.get('test')
                        if (isinstance(test, dict) and type(test.get('id')) is int
                                and type(test.get('suiteID')) is int
                                and isinstance(test.get('name'), str)):
                            self.release()
                            return
                self.buffer.clear()
                self.dropping_line = False

    def release(self):
        if self.handle is not None:
            self.handle.close()
            self.handle = None
        self.buffer.clear()

    def __exit__(self, *_):
        self.release()
