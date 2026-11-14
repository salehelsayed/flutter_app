#!/usr/bin/env python3
"""Opt-in real Flutter proof: four lanes in one checkout, three repetitions.

Run only on an otherwise idle host-test queue, in the executor's owned checkout.
Uses the real wrapper scheduler, setup lock, host slots and receipt parser.
"""
import argparse
import json
from pathlib import Path
import sys
import time
import uuid
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mknoon_checks as checks

FIXTURE = r'''
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('BL20 native asset and simultaneous lane __LANE__', () async {
    final db = sqlite3.openInMemory();
    try {
      db.execute('CREATE TABLE proof (value INTEGER)');
      db.execute('INSERT INTO proof VALUES (42)');
      expect(db.select('SELECT value FROM proof').single['value'], 42);
      final barrier = Directory(Platform.environment['BL20_BARRIER_DIR']!);
      final started = DateTime.now().millisecondsSinceEpoch;
      File('${barrier.path}/__LANE__.ready').writeAsStringSync('$started');
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (barrier.listSync().where((f) => f.path.endsWith('.ready')).length < 4) {
        if (DateTime.now().isAfter(deadline)) fail('Four test bodies did not overlap');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      File('${barrier.path}/__LANE__.done').writeAsStringSync(
        '${DateTime.now().millisecondsSinceEpoch}');
    } finally {
      db.dispose();
    }
  });
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    if len(checks.device_preflight.host_slot_names()) != 4:
        raise SystemExit('BLOCKED: proof requires the existing four-slot host policy')
    rules = json.loads((root / checks.RULES).read_text())
    fixture_root = root / 'test' / ('.bl20_native_assets_' + uuid.uuid4().hex)
    fixture_root.mkdir()
    paths = []
    for lane in range(4):
        path = fixture_root / f'lane{lane}_test.dart'
        path.write_text(FIXTURE.replace('__LANE__', str(lane)))
        paths.append(str(path.relative_to(root)))
    (output / 'fixture.dart.txt').write_text(FIXTURE)
    summary = dict(head=checks.resolve_ref(root, 'HEAD'), repeats=[], status='NOT RUN')
    try:
        for repeat in range(3):
            directory = output / f'repeat-{repeat + 1}'
            directory.mkdir()
            barrier = output / f'barrier-{repeat + 1}'
            barrier.mkdir()
            selected = []
            for lane, path in enumerate(paths):
                selected.append(dict(id=f'lane-{lane}', kind='flutter', selected_paths=[path],
                    command=['flutter', 'test', '--no-pub', '--machine', '--concurrency=1', '--timeout=2m', path],
                    timeout_seconds=600, environment={'BL20_BARRIER_DIR': str(barrier)},
                    investigate=['scripts/flutter_native_asset_lock.py'], blocked_prerequisites=[]))
            files = checks.source_files(root)
            plan = dict(mode='change', baseline=summary['head'], candidate_build='BL20 host proof',
                identity=checks.source_identity(root, files, rules), toolchains=checks.toolchain_identity(root),
                selected=selected, not_selected=[], unmapped_changes=[], changes=[])
            run_args = SimpleNamespace(mode='change', evidence=None, candidate_artifact=[], only=None,
                rerun_failed=False, jobs=4, flutter_workers=1, sims_jobs=1)
            code = checks.execute_plan(run_args, root, rules, plan, files, {}, {}, directory, time.monotonic())
            report = json.loads((directory / 'results.json').read_text())
            starts = [int(p.read_text()) for p in barrier.glob('*.ready')]
            ends = [int(p.read_text()) for p in barrier.glob('*.done')]
            overlap = len(starts) == len(ends) == 4 and max(starts) < min(ends)
            passed = (code == 0 and report['status'] == 'PASS' and overlap
                      and report['scheduling']['max_observed_concurrency'] == 4)
            summary['repeats'].append(dict(repeat=repeat + 1, status='PASS' if passed else 'FAIL',
                actual_body_overlap=overlap, result_path=str(directory / 'results.json')))
            summary['status'] = 'PASS' if passed and repeat == 2 else 'FAIL' if not passed else 'IN PROGRESS'
            (output / 'results.json').write_text(json.dumps(summary, indent=2) + '\n')
            if not passed:
                return 1  # Keep the first failure; no automatic retry.
        return 0
    finally:
        for path in paths:
            (root / path).unlink()
        fixture_root.rmdir()


if __name__ == '__main__':
    raise SystemExit(main())
