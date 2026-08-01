// TC-317-12 device proof: AndroidAppStateGuard round-trip on the live Pixel 6.
//
// Safety contract (plan 317 v2):
//  - every adb invocation pins -s 21071FDF600CSC; guard devices = [Pixel] only;
//  - the fresh capture dir's path + whole-tar sha + canonical digest are
//    recorded BEFORE restoreAll runs;
//  - the double-cut probe force-stops before each cut, keeps the process
//    stopped between cuts, retries once on inequality, and is EVIDENCE, not a
//    hard gate;
//  - the mknoon-*-state-* set in host tmp is snapshotted before/after and the
//    set-difference must be empty on success;
//  - on failure the retained backup path and the exact recovery invocation
//    are printed;
//  - run only after the 317 host gate ladder is fully green (the success path
//    deletes the backup).
//
// Run FROM THE HOST repo root: dart run docker-ws/state_guard_roundtrip_317.dart

import 'dart:convert';
import 'dart:io';

import '../integration_test/support/android_app_state_guard.dart';

const String _device = '21071FDF600CSC';
const String _package = 'com.mknoon.app';
final File _resultFile = File('docker-ws/state_guard_roundtrip_317_result.txt');
final IOSink _result = _resultFile.openWrite();

void _log(String line) {
  stdout.writeln(line);
  _result.writeln(line);
}

Set<String> _stateGuardTempDirs() => Directory.systemTemp
    .listSync(followLinks: false)
    .map((entity) => entity.path.split(Platform.pathSeparator).last)
    .where((name) => name.startsWith('mknoon-') && name.contains('-state-'))
    .toSet();

Future<File> _streamPrivateTar(List<String> entries, File destination) async {
  final process = await Process.start('adb', <String>[
    '-s',
    _device,
    'exec-out',
    'run-as',
    _package,
    'tar',
    '-cf',
    '-',
    '--',
    ...entries,
  ], runInShell: false);
  final sink = destination.openWrite();
  await sink.addStream(process.stdout);
  await sink.close();
  final code = await process.exitCode;
  if (code != 0 || destination.lengthSync() == 0) {
    throw StateError('probe stream failed (exit $code)');
  }
  return destination;
}

Future<void> _forceStop() async {
  final result = await Process.run('adb', <String>[
    '-s',
    _device,
    'shell',
    'am',
    'force-stop',
    _package,
  ], runInShell: false);
  if (result.exitCode != 0) throw StateError('force-stop failed');
}

Future<void> main() async {
  var exitCodeToUse = 0;
  try {
    _log('=== state_guard_roundtrip_317 ${DateTime.now().toUtc().toIso8601String()} ===');
    final before = _stateGuardTempDirs();
    _log('pre-existing mknoon-*-state-* dirs: ${before.length}');

    _log('--- capture (devices: [$_device]) ---');
    final guard = await AndroidAppStateGuard.capture(
      devices: const <String>[_device],
      packageName: _package,
      backupLabel: 'roundtrip-317',
    );
    final backupPath = guard.backupDirectory.path;
    _log('capture dir: $backupPath');
    final manifest = jsonDecode(
      File('$backupPath/recovery-manifest.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final deviceEntry =
        (manifest['devices'] as List).single as Map<String, Object?>;
    final privateData = deviceEntry['privateData'] as Map<String, Object?>;
    final entries = (privateData['entries'] as List).cast<String>();
    final archive = File('$backupPath/$_device/private-data.tar');
    _log('private-data.tar bytes: ${archive.lengthSync()}');
    _log('whole-tar sha256 (manifest): ${privateData['sha256']}');
    final canonicalOfBackup = await canonicalPrivateArchiveDigest(archive);
    _log('canonical digest (backup): $canonicalOfBackup');
    _log('process at capture: ${jsonEncode(deviceEntry['process'])}');

    _log('--- double-cut probe (evidence, not a gate) ---');
    final probeDir = Directory.systemTemp.createTempSync('roundtrip317-probe-');
    try {
      Future<(String, String)> cut(String name) async {
        await _forceStop();
        final file = await _streamPrivateTar(
          entries,
          File('${probeDir.path}/$name.tar'),
        );
        final canonical = await canonicalPrivateArchiveDigest(file);
        final whole = (await Process.run('shasum', <String>[
          '-a',
          '256',
          file.path,
        ], runInShell: false)).stdout.toString().trim().split(' ').first;
        return (canonical, whole);
      }

      final (canonicalA, wholeA) = await cut('cut-a');
      final (canonicalB, wholeB) = await cut('cut-b');
      _log('cut A: canonical=$canonicalA whole=$wholeA');
      _log('cut B: canonical=$canonicalB whole=$wholeB');
      _log('canonical A==B: ${canonicalA == canonicalB}');
      _log('whole-sha A==B: ${wholeA == wholeB}');
      if (canonicalA != canonicalB) {
        final (canonicalC, wholeC) = await cut('cut-c');
        _log('retry cut C: canonical=$canonicalC whole=$wholeC');
        _log('canonical B==C: ${canonicalB == canonicalC}');
      }
      _log('canonical backup==cutA: ${canonicalOfBackup == canonicalA}');
    } finally {
      probeDir.deleteSync(recursive: true);
    }

    _log('--- restoreAll (in-place reinstall + clear + re-extract + canonical verify) ---');
    final stopwatch = Stopwatch()..start();
    try {
      await guard.restoreAll();
    } on Object catch (error) {
      _log('RESTORE FAILED: $error');
      _log('retained backup: $backupPath');
      _log('recovery invocation: AndroidAppStateGuard.loadRecovery('
          'backupDirectory: Directory(r"$backupPath")) then restoreAll()');
      rethrow;
    }
    stopwatch.stop();
    _log('restoreAll GREEN in ${stopwatch.elapsed.inSeconds}s');
    _log('backup dir deleted: ${!Directory(backupPath).existsSync()}');

    final after = _stateGuardTempDirs();
    final leaked = after.difference(before);
    _log('tmp set-difference after success: ${leaked.isEmpty ? "empty" : leaked.join(", ")}');
    if (leaked.isNotEmpty) {
      throw StateError('roundtrip leaked state dirs: $leaked');
    }
    _log('ROUNDTRIP PASS');
  } on Object catch (error, stackTrace) {
    _log('ROUNDTRIP FAIL: $error');
    _log('$stackTrace');
    exitCodeToUse = 1;
  } finally {
    await _result.close();
  }
  exit(exitCodeToUse);
}
