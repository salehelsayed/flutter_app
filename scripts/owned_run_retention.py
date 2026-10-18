#!/usr/bin/env python3
"""Retention only for new, explicitly marked Mknoon capture directories."""
import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

LIMIT_BYTES = 2 * 1024 ** 3
SCHEMA = 'mknoon.owned-capture.v1'
MARKER = '.owned-run.json'


class RetentionCapacityError(RuntimeError):
    pass


def check_screenshots(directory, max_count=128, max_bytes=128 * 1024 ** 2,
                      file_limit=20 * 1024 ** 2):
    """Check only this invocation's outputs; never follow screenshot links."""
    count = total = 0
    for current, _, files in os.walk(directory, followlinks=False):
        for name in files:
            path = Path(current) / name
            if path.is_symlink() or path.suffix.lower() not in ('.png', '.jpg', '.jpeg', '.webp'):
                continue
            size = path.stat().st_size
            count += 1
            total += size
            if count > max_count or total > max_bytes or size > file_limit:
                raise RetentionCapacityError('evidence_capacity: screenshot count/bytes exceed run quota')
    return dict(count=count, bytes=total)


class OwnedRuns:
    def __init__(self, repository, limit_bytes=LIMIT_BYTES):
        self.repository = Path(repository).resolve()
        self.root = self.repository / '.codex-test-logs' / 'owned-runs'
        self.limit_bytes = limit_bytes
        # Never adopt a symlinked storage tree or an existing unmarked root.
        for path in (self.root.parent, self.root):
            if path.is_symlink():
                raise ValueError('Owned output root must not be a symlink')
        self.root.mkdir(parents=True, exist_ok=True)
        owner = self.root / '.owner'
        if not owner.exists():
            if any(self.root.iterdir()):
                raise ValueError('Existing output root has no ownership marker')
            owner.write_text(SCHEMA + '\n')
        if owner.is_symlink() or owner.read_text() != SCHEMA + '\n':
            raise ValueError('Unexpected output ownership marker')
        os.chmod(self.root, 0o700)

    @contextlib.contextmanager
    def _locked(self):
        with (self.root / '.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield

    def _load(self, path):
        marker = path / MARKER
        if path.is_symlink() or not path.is_dir() or marker.is_symlink():
            return None
        try:
            data = json.loads(marker.read_text())
            if (data.get('schema') != SCHEMA or data.get('run') != path.name
                    or data.get('state') not in ('active', 'PASS', 'FAIL', 'BLOCKED')
                    or not isinstance(data.get('created_ns'), int)):
                return None
            return data
        except (ValueError, OSError, AttributeError):
            return None

    def _save(self, path, data):
        temporary = path / (MARKER + '.pending')
        temporary.write_text(json.dumps(data, sort_keys=True) + '\n')
        os.chmod(temporary, 0o600)
        temporary.replace(path / MARKER)

    def start(self, kind):
        if kind not in ('checks', 'sims'):
            raise ValueError('Unknown output producer')
        with self._locked():
            self._prune()
            path = self.root / f'{kind}-{time.time_ns()}-{uuid.uuid4().hex[:8]}'
            path.mkdir(mode=0o700)
            self._save(path, dict(schema=SCHEMA, run=path.name, state='active',
                                  created_ns=time.time_ns(), triaged=False))
            return path

    def finish(self, path, status):
        path = Path(path).absolute()
        if path.parent != self.root or status not in ('PASS', 'FAIL', 'BLOCKED'):
            raise ValueError('Not an owned run/status')
        with self._locked():
            data = self._load(path)
            if data is None:
                raise ValueError('Missing exact run ownership marker')
            data['state'] = status
            data['completed_ns'] = time.time_ns()
            self._save(path, data)
            try:
                return self._prune(keep={path.name})
            except RetentionCapacityError:
                data['state'] = 'FAIL'
                self._save(path, data)
                raise

    def _external_reference_texts(self):
        # Only tracked prose and the two canonical state pointers. Never scan
        # ignored private configuration, credentials, or arbitrary JSON files.
        result = subprocess.run(['git', 'ls-files', '-z', '--', '*.md'],
                                cwd=self.repository, capture_output=True)
        names = result.stdout.decode('utf-8', errors='replace').split('\0') if result.returncode == 0 else []
        names += ['build/sims/latest/checkpoint.json', 'build/sims/latest/report.json']
        for name in names:
            path = self.repository / name
            if not name:
                continue
            if path.is_symlink():
                yield str(path.resolve())
                continue
            if not path.is_file():
                continue
            # References in unusually large prose are conservatively handled
            # without materializing the complete document in memory.
            with path.open(errors='replace') as source:
                previous = ''
                while text := source.read(64 * 1024):
                    yield previous + text
                    previous = text[-256:]

    def _prune(self, keep=()):
        runs = {path.name: (path, data) for path in self.root.iterdir()
                if (data := self._load(path)) is not None}
        protected = {name for name, (_, data) in runs.items() if data['state'] == 'active'}
        protected.update(keep)
        good = sorted((name for name in runs if runs[name][1]['state'] == 'PASS'),
                      key=lambda name: runs[name][1].get('completed_ns', runs[name][1]['created_ns']), reverse=True)
        protected.update(good[:2])
        failures = sorted((name for name in runs if runs[name][1]['state'] in ('FAIL', 'BLOCKED')
                           and not runs[name][1].get('triaged', False)),
                          key=lambda name: runs[name][1].get('completed_ns', runs[name][1]['created_ns']))
        protected.update(failures[:1])

        def references(text):
            return {name for name in runs if name in text}

        for text in self._external_reference_texts():
            protected.update(references(text))
        sizes = {}
        references_by_run = {}
        # A symlink anywhere in the managed root pins its target run. Hard
        # linked files pin their own run as well. Neither link is traversed.
        for current, directories, files in os.walk(self.root, followlinks=False):
            for name in directories + files:
                path = Path(current) / name
                if path.is_symlink():
                    try:
                        relative = path.resolve().relative_to(self.root)
                        if relative.parts and relative.parts[0] in runs:
                            protected.add(relative.parts[0])
                    except (ValueError, OSError, RuntimeError):
                        pass
        for name, (path, _) in runs.items():
            size = 0
            refs = set()
            for current, _, files in os.walk(path, followlinks=False):
                for leaf in files:
                    item = Path(current) / leaf
                    if item.is_symlink():
                        continue
                    stat = item.stat()
                    size += stat.st_size
                    if stat.st_nlink > 1:
                        protected.add(name)
                    if leaf in ('plan.json', 'results.json', 'report.json', 'checkpoint.json'):
                        with item.open(errors='replace') as source:
                            previous = ''
                            while text := source.read(64 * 1024):
                                refs.update(references(previous + text))
                                previous = text[-256:]
            sizes[name] = size
            references_by_run[name] = refs
        while True:
            linked = set().union(*(references_by_run.get(name, set()) for name in protected)) if protected else set()
            if linked <= protected:
                break
            protected.update(linked)
        removed = []
        for name, (path, _) in runs.items():
            if name not in protected:
                # _load rejects symlinks and exact ownership is rechecked
                # immediately before rmtree (which does not follow links).
                if self._load(path) is not None:
                    shutil.rmtree(path)
                    removed.append(name)
        retained = sum(size for name, size in sizes.items() if name not in removed)
        receipt = dict(limit_bytes=self.limit_bytes, retained_bytes=retained,
                       protected=sorted(protected), removed=sorted(removed))
        if retained > self.limit_bytes:
            raise RetentionCapacityError('evidence_capacity: protected owned runs exceed retention quota; no protected evidence deleted')
        return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('start', 'finish'))
    parser.add_argument('--repository', type=Path, required=True)
    parser.add_argument('--kind', choices=('checks', 'sims'))
    parser.add_argument('--run', type=Path)
    parser.add_argument('--status', choices=('PASS', 'FAIL', 'BLOCKED'))
    args = parser.parse_args()
    try:
        owned = OwnedRuns(args.repository)
        if args.action == 'start':
            print(owned.start(args.kind))
        else:
            print(json.dumps(owned.finish(args.run, args.status), sort_keys=True))
    except (ValueError, OSError, RetentionCapacityError) as error:
        print(str(error), file=__import__('sys').stderr)
        return 93
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
