#!/usr/bin/env dart
// Notification Sound Smoke — Two-Simulator Orchestrator
//
// Drives text, suppression, and media-notification scenarios across two mobile
// targets:
//   S1: 1:1 direct chat              (expect notification + sound)
//   S2: Group discussion (chat)      (expect notification + sound)
//   S3: Group announcement           (expect notification + sound)
//   S4: Suppression control          (expect NO notification — gate works)
//   S5-S13: image/video/voice across all three conversation lanes
//
// For each scenario the orchestrator asks the operator "did you hear sound?"
// so the final report combines programmatic FLOW-event verdicts with audible
// confirmation. Programmatic results alone prove the code path fires; the
// human confirmation proves the OS delivers audio at the speaker.
//
// Usage:
//   dart run integration_test/scripts/run_notification_sound_smoke.dart \
//       -d <alice_udid>,<bob_udid>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../_support/signal_files.dart';
import '_android_app_package.dart';

// Single role-dispatched harness; the SMOKE_ROLE dart-define selects the
// alice (sender) or bob (receiver) path inside the merged file.
const _mergedHarness = 'integration_test/notification_sound_smoke_harness.dart';

bool _isIosDeviceId(String? id) {
  if (id == null) return false;
  return RegExp(
    r'^(?:[0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})$',
    caseSensitive: false,
  ).hasMatch(id);
}

List<String> _relayDartDefines() {
  final relay = Platform.environment['MKNOON_RELAY_ADDRESSES'];
  if (relay == null || relay.trim().isEmpty) return const [];
  return ['--dart-define=MKNOON_RELAY_ADDRESSES=${relay.trim()}'];
}

List<String> _notificationDartDefines() {
  if (!_nonInteractive) return const [];
  return const ['--dart-define=NOTIFICATION_SOUND_NON_INTERACTIVE=true'];
}

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
}

late Directory _sharedDir;
late String _runId;

/// Canonical signal-file coordinator for the `nsmoke_` family. Reproduces the
/// inline `'${_sharedDir.path}/nsmoke_${_runId}_$name'` path byte-for-byte
/// (prefix `'nsmoke_'`, runId baked with the trailing `'_'`). Assigned in
/// [main] once `_sharedDir` / `_runId` are known.
late SignalDir _signals;
Directory? _artifactDirectory;
late String _bobDevice;
late String _appPackage;
bool _bobIsAndroid = false;
bool _androidPair = false;
late String _remoteSharedDir;
late String _remoteSharedDirRelative;
bool _stopSignalSync = false;
Set<String>? _selectedRows;

const _allScenarioIds = <String>{
  'S1',
  'S2',
  'S3',
  'S4',
  'S5',
  'S6',
  'S7',
  'S8',
  'S9',
  'S10',
  'S11',
  'S12',
  'S13',
};

bool _isSelectedRow(String id) =>
    _selectedRows == null || _selectedRows!.contains(id);

void _pipeOutput(Stream<List<int>> stream, String tag, IOSink sink) {
  stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    _log(tag, line);
    try {
      sink.writeln(line);
    } catch (_) {
      // Sink may be closed during teardown; swallow to avoid killing the
      // orchestrator with a cosmetic StreamSink exception.
    }
  });
}

Future<Process> _launchHarness({
  required String harness,
  required String role,
  required String deviceId,
  required String dbName,
}) async {
  final sharedDir = _androidPair ? _remoteSharedDir : _sharedDir.path;
  final args = <String>[
    if (_isIosDeviceId(deviceId)) ...[
      'drive',
      '--driver=test_driver/integration_test.dart',
      '--target=$harness',
      '--publish-port',
      '--no-pub',
    ] else ...[
      'test',
      '--no-pub',
      harness,
    ],
    '--dart-define=E2E_SHARED_DIR=$sharedDir',
    '--dart-define=SMOKE_ROLE=$role',
    '--dart-define=SMOKE_RUN_ID=$_runId',
    '--dart-define=E2E_DB_NAME=$dbName',
    ..._relayDartDefines(),
    ..._notificationDartDefines(),
    '-d',
    deviceId,
  ];
  _log('ORCH', 'Launching $role: flutter ${args.join(' ')}');
  return Process.start('flutter', args);
}

bool _nonInteractive = false;

String _promptOperator(String prompt) {
  stdout.write(prompt);
  if (_nonInteractive) {
    stdout.writeln('[non-interactive: skipped]');
    return '';
  }
  final line = stdin.readLineSync(encoding: utf8);
  return (line ?? '').trim().toLowerCase();
}

void _printChecklist() {
  stdout.writeln('\n${'═' * 70}');
  stdout.writeln('  NOTIFICATION SOUND SMOKE — MANUAL AUDIO CHECKLIST');
  stdout.writeln('═' * 70);
  stdout.writeln('Before starting, confirm on Bob\'s simulator:');
  stdout.writeln(
    '  [ ] Simulator menu > I/O > Audio Output > your Mac\'s speakers',
  );
  stdout.writeln('  [ ] macOS host volume > 50% and NOT muted');
  stdout.writeln('  [ ] Simulator Settings > Focus / Do Not Disturb = OFF');
  stdout.writeln(
    '  [ ] Settings > <app> > Notifications > Allow Notifications = ON',
  );
  stdout.writeln('  [ ] Settings > <app> > Notifications > Sounds = ON');
  stdout.writeln('${'═' * 70}\n');
  _promptOperator('Press Enter when ready to run S1..S13: ');
}

Future<bool> _isLiveAdbDevice(String deviceId) async {
  final result = await Process.run('adb', <String>[
    '-s',
    deviceId,
    'get-state',
  ]);
  return result.exitCode == 0 && result.stdout.toString().trim() == 'device';
}

Future<ProcessResult> _adbOn(
  String deviceId,
  List<String> args, {
  Encoding? stdoutEncoding = utf8,
}) {
  return Process.run('adb', <String>[
    '-s',
    deviceId,
    ...args,
  ], stdoutEncoding: stdoutEncoding);
}

Future<ProcessResult> _adb(
  List<String> args, {
  Encoding? stdoutEncoding = utf8,
}) => _adbOn(_bobDevice, args, stdoutEncoding: stdoutEncoding);

Future<Set<String>> _listDeviceSignalFiles(String deviceId) async {
  final result = await _adbOn(deviceId, <String>[
    'shell',
    'run-as',
    _appPackage,
    'ls',
    '-1',
    _remoteSharedDirRelative,
  ]);
  if (result.exitCode != 0) return <String>{};
  final prefix = 'nsmoke_${_runId}_';
  final safeName = RegExp(r'^[A-Za-z0-9_.-]+$');
  return result.stdout
      .toString()
      .split('\n')
      .map((value) => value.trim())
      .where((value) => value.startsWith(prefix) && safeName.hasMatch(value))
      .toSet();
}

Future<void> _pullDeviceSignal(String deviceId, String name) async {
  final destination = File('${_sharedDir.path}/$name');
  if (destination.existsSync()) return;
  Future<ProcessResult> read() => _adbOn(deviceId, <String>[
    'exec-out',
    'run-as',
    _appPackage,
    'cat',
    '$_remoteSharedDirRelative/$name',
  ], stdoutEncoding: null);
  final first = await read();
  if (first.exitCode != 0 || first.stdout is! List<int>) return;
  await Future<void>.delayed(const Duration(milliseconds: 40));
  final second = await read();
  if (second.exitCode != 0 || second.stdout is! List<int>) return;
  final firstBytes = first.stdout as List<int>;
  final secondBytes = second.stdout as List<int>;
  if (base64Encode(firstBytes) != base64Encode(secondBytes)) return;
  final pending = File('${destination.path}.$deviceId.pending');
  await pending.writeAsBytes(secondBytes, flush: true);
  if (destination.existsSync()) {
    await pending.delete();
  } else {
    await pending.rename(destination.path);
  }
}

Future<bool> _pushHostSignal(String deviceId, File source) async {
  final name = source.uri.pathSegments.last;
  final process = await Process.start('adb', <String>[
    '-s',
    deviceId,
    'shell',
    'run-as',
    _appPackage,
    'tee',
    '$_remoteSharedDirRelative/$name',
  ]);
  final stdoutDone = process.stdout.drain<void>();
  final stderrDone = process.stderr.drain<void>();
  process.stdin.add(await source.readAsBytes());
  await process.stdin.close();
  final exitCode = await process.exitCode;
  await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
  return exitCode == 0;
}

Future<void> _syncAndroidSignalFiles(List<String> deviceIds) async {
  final prefix = 'nsmoke_${_runId}_';
  while (!_stopSignalSync) {
    final filesByDevice = <String, Set<String>>{};
    for (final deviceId in deviceIds) {
      final files = await _listDeviceSignalFiles(deviceId);
      filesByDevice[deviceId] = files;
      for (final name in files) {
        await _pullDeviceSignal(deviceId, name);
      }
    }

    final hostSignals = _sharedDir
        .listSync()
        .whereType<File>()
        .where((file) => file.uri.pathSegments.last.startsWith(prefix))
        .toList(growable: false);
    for (final deviceId in deviceIds) {
      final deviceFiles = filesByDevice[deviceId] ?? <String>{};
      for (final signal in hostSignals) {
        final name = signal.uri.pathSegments.last;
        if (!deviceFiles.contains(name)) {
          if (await _pushHostSignal(deviceId, signal)) {
            deviceFiles.add(name);
          }
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

Future<void> _grantAndroidNotificationPermission() async {
  if (!_bobIsAndroid) return;
  final result = await _adb(<String>[
    'shell',
    'pm',
    'grant',
    _appPackage,
    'android.permission.POST_NOTIFICATIONS',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Unable to grant Android notification permission on $_bobDevice.',
    );
  }
}

List<String> _activeAppNotificationRecords(String dump) {
  final activeSection = dump.split(RegExp(r'\nRanking Config:')).first;
  final packagePattern = RegExp(r'\bpkg=' + RegExp.escape(_appPackage) + r'\b');
  return RegExp(r'NotificationRecord\([\s\S]*?(?=\n\s*NotificationRecord\(|$)')
      .allMatches(activeSection)
      .map((match) => match.group(0)!)
      .where(packagePattern.hasMatch)
      .toList(growable: false);
}

String _notificationValue(String record, String key) {
  final match = RegExp(
    '^\\s*${RegExp.escape(key)}=(.+)\$',
    multiLine: true,
  ).firstMatch(record);
  if (match == null) return '';
  final value = match.group(1)!.trim();
  final wrapped = RegExp(r'^[A-Za-z]*String \((.*)\)$').firstMatch(value);
  return wrapped?.group(1) ?? (value == 'null' ? '' : value);
}

Map<String, dynamic> _sanitizeNotificationRecord(String record) {
  String match(String pattern) =>
      RegExp(pattern, multiLine: true).firstMatch(record)?.group(1) ?? '';
  return <String, dynamic>{
    'package': match(r'\bpkg=([^\s]+)'),
    'id': int.tryParse(match(r'\bid=(\d+)\b')),
    'channel': match(r'Notification\(channel=([^\s\)]+)'),
    'category': match(r'\bcategory=([^\s\)]+)'),
    'groupKey': match(r'^\s*groupKey=(.+)$'),
    'title': _notificationValue(record, 'android.title'),
    'body': _notificationValue(record, 'android.text'),
  };
}

Future<Map<String, dynamic>> _captureAndroidNotificationState({
  required String scenarioId,
  required Map<String, dynamic> verdict,
  required bool expectSuppressed,
}) async {
  if (!_bobIsAndroid) {
    return const <String, dynamic>{
      'applicable': false,
      'pass': true,
      'reason': 'recipient_is_not_android',
    };
  }

  List<String> records = const <String>[];
  for (var attempt = 0; attempt < 20; attempt++) {
    final dump = await _adb(const <String>[
      'shell',
      'dumpsys',
      'notification',
      '--noredact',
    ]);
    if (dump.exitCode != 0) {
      throw StateError('dumpsys notification failed on $_bobDevice.');
    }
    records = _activeAppNotificationRecords(dump.stdout.toString());
    if ((expectSuppressed && records.isEmpty) ||
        (!expectSuppressed && records.length == 1)) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  final sanitized = records
      .map(_sanitizeNotificationRecord)
      .toList(growable: false);
  final shownCalls = (verdict['shownCalls'] as List<dynamic>? ?? const [])
      .whereType<Map>()
      .map((value) => Map<String, dynamic>.from(value))
      .toList(growable: false);
  final expectedCall = shownCalls.length == 1 ? shownCalls.single : null;
  final expectedTitle = expectedCall?['senderUsername']?.toString() ?? '';
  final expectedBody = expectedCall?['messageText']?.toString() ?? '';
  final observed = sanitized.length == 1 ? sanitized.single : null;

  final packageState = await _adb(<String>[
    'shell',
    'dumpsys',
    'package',
    _appPackage,
  ]);
  final permissionGranted = packageState.stdout.toString().contains(
    'android.permission.POST_NOTIFICATIONS: granted=true',
  );

  var shadeTitleVisible = expectSuppressed;
  var shadeBodyVisible = expectSuppressed;
  final uiHierarchyAttempts = <Map<String, dynamic>>[];
  String? screenshotPath;
  if (!expectSuppressed && observed != null) {
    for (var attempt = 1; attempt <= 3; attempt++) {
      await _adb(const <String>['shell', 'cmd', 'statusbar', 'collapse']);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _adb(const <String>[
        'shell',
        'cmd',
        'statusbar',
        'expand-notifications',
      ]);
      await Future<void>.delayed(Duration(milliseconds: 650 + (attempt * 250)));

      final remoteDump =
          '/data/local/tmp/nsmoke_notification_${scenarioId.toLowerCase()}_'
          '$attempt.xml';
      final dumpResult = await _adb(<String>[
        'shell',
        'uiautomator',
        'dump',
        remoteDump,
      ]);
      final ui = dumpResult.exitCode == 0
          ? await _adb(<String>['shell', 'cat', remoteDump])
          : null;
      final xml = ui?.stdout.toString() ?? '';
      final attemptTitleVisible =
          expectedTitle.isNotEmpty && xml.contains(expectedTitle);
      final attemptBodyVisible =
          expectedBody.isNotEmpty && xml.contains(expectedBody);
      shadeTitleVisible = shadeTitleVisible || attemptTitleVisible;
      shadeBodyVisible = shadeBodyVisible || attemptBodyVisible;

      String? sanitizedArtifactPath;
      final artifactDirectory = _artifactDirectory;
      if (artifactDirectory != null) {
        final artifact = File(
          '${artifactDirectory.path}/'
          '${scenarioId.toLowerCase()}_ui_hierarchy_attempt_$attempt.json',
        );
        await artifact.writeAsString(
          const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
            'scenarioId': scenarioId,
            'attempt': attempt,
            'dumpExitCode': dumpResult.exitCode,
            'readExitCode': ui?.exitCode,
            'titleVisible': attemptTitleVisible,
            'bodyVisible': attemptBodyVisible,
          }),
          flush: true,
        );
        sanitizedArtifactPath = artifact.path;
      }
      uiHierarchyAttempts.add(<String, dynamic>{
        'attempt': attempt,
        'dumpExitCode': dumpResult.exitCode,
        'readExitCode': ui?.exitCode,
        'titleVisible': attemptTitleVisible,
        'bodyVisible': attemptBodyVisible,
        'sanitizedArtifact': sanitizedArtifactPath,
      });
      await _adb(<String>['shell', 'rm', '-f', remoteDump]);
      if (shadeTitleVisible && shadeBodyVisible) break;
    }

    final artifactDirectory = _artifactDirectory;
    if (artifactDirectory != null) {
      final screenshot = await _adb(const <String>[
        'exec-out',
        'screencap',
        '-p',
      ], stdoutEncoding: null);
      if (screenshot.exitCode == 0 && screenshot.stdout is List<int>) {
        final file = File(
          '${artifactDirectory.path}/'
          '${scenarioId.toLowerCase()}_notification.png',
        );
        await file.writeAsBytes(screenshot.stdout as List<int>, flush: true);
        screenshotPath = file.path;
      }
    }
    await _adb(const <String>['shell', 'cmd', 'statusbar', 'collapse']);
  }

  final channel = observed?['channel']?.toString() ?? '';
  final channelMatches =
      channel == 'mknoon_messages' || channel == 'mknoon_messages_silent';
  final predicates = <String, bool>{
    'cardCountMatches': expectSuppressed
        ? records.isEmpty
        : records.length == 1,
    'packageMatches': expectSuppressed
        ? true
        : observed?['package'] == _appPackage,
    'channelMatches': expectSuppressed ? true : channelMatches,
    'notificationIdPresent': expectSuppressed ? true : observed?['id'] is int,
    'titleMatches': expectSuppressed
        ? true
        : observed?['title'] == expectedTitle,
    'bodyMatches': expectSuppressed ? true : observed?['body'] == expectedBody,
    'payloadMatches': verdict['payloadMatches'] as bool? ?? expectSuppressed,
    'categoryMatches': expectSuppressed ? true : observed?['category'] == 'msg',
    'permissionGranted': permissionGranted,
    'uiHierarchyTitleVisible': expectSuppressed ? true : shadeTitleVisible,
    'uiHierarchyBodyVisible': expectSuppressed ? true : shadeBodyVisible,
    'screenshotCaptured':
        expectSuppressed ||
        _artifactDirectory == null ||
        screenshotPath != null,
    'suppressionStateMatches': expectSuppressed
        ? verdict['notificationSuppressed'] == true && records.isEmpty
        : verdict['notificationSuppressed'] != true &&
              verdict['notificationShown'] == true,
  };
  final osPass = predicates.values.every((value) => value);
  return <String, dynamic>{
    'applicable': true,
    'pass': osPass,
    'predicates': predicates,
    'activeCount': records.length,
    'duplicateCount': records.length > 1 ? records.length - 1 : 0,
    'permissionGranted': permissionGranted,
    'expectedTitle': expectedTitle,
    'expectedBody': expectedBody,
    'shadeTitleVisible': shadeTitleVisible,
    'shadeBodyVisible': shadeBodyVisible,
    'uiHierarchyAttempts': uiHierarchyAttempts,
    'channelMatchesContract': channelMatches,
    'records': sanitized,
    'screenshot': screenshotPath,
  };
}

Map<String, dynamic> _redactedVerdict(Map<String, dynamic> verdict) {
  final redacted = <String, dynamic>{...verdict};
  for (final key in const <String>[
    'expectedContactPeerId',
    'expectedPayload',
    'expectedPayloadPrefix',
  ]) {
    if (redacted[key] != null) redacted[key] = '[redacted-route]';
  }
  redacted['shownCalls'] =
      (verdict['shownCalls'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((value) {
            final call = Map<String, dynamic>.from(value);
            if (call['contactPeerId'] != null) {
              call['contactPeerId'] = '[redacted-conversation]';
            }
            if (call['payload'] != null) call['payload'] = '[redacted-route]';
            return call;
          })
          .toList(growable: false);
  return redacted;
}

class ScenarioOutcome {
  final String id;
  final bool selected;
  final bool programmaticPass;
  final bool? audibleConfirmed;
  final Map<String, dynamic> verdict;
  final Map<String, dynamic> osNotification;
  ScenarioOutcome({
    required this.id,
    required this.selected,
    required this.programmaticPass,
    required this.audibleConfirmed,
    required this.verdict,
    required this.osNotification,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'selected': selected,
    'programmaticPass': programmaticPass,
    'audibleConfirmed': audibleConfirmed,
    'verdict': _redactedVerdict(verdict),
    'osNotification': osNotification,
  };
}

Future<ScenarioOutcome> _runScenario({
  required String id,
  required String goSignal,
  required String bobVerdictSignal,
  required String verdictAckSignal,
  required String description,
  required bool expectAudible,
  required bool expectSuppressed,
}) async {
  _log('ORCH', '─── $id: $description ───');
  _signals.writeSignal(goSignal);
  final verdict = await _signals.waitForJson(
    bobVerdictSignal,
    timeout: const Duration(minutes: 5),
  );
  final harnessPass = verdict['programmaticPass'] as bool? ?? false;
  final selected = _isSelectedRow(id);
  if (!selected) {
    _log(
      'ORCH',
      '$id prerequisite: ${harnessPass ? 'PASS' : 'FAIL'} '
          '(OS evidence skipped by --rows)',
    );
    _signals.writeSignal(verdictAckSignal);
    if (!harnessPass) {
      throw StateError('$id prerequisite harness predicate failed');
    }
    return ScenarioOutcome(
      id: id,
      selected: false,
      programmaticPass: true,
      audibleConfirmed: null,
      verdict: verdict,
      osNotification: const <String, dynamic>{
        'applicable': false,
        'pass': true,
        'reason': 'row_filter_prerequisite',
      },
    );
  }
  final osNotification = await _captureAndroidNotificationState(
    scenarioId: id,
    verdict: verdict,
    expectSuppressed: expectSuppressed,
  );
  final osPass = osNotification['pass'] as bool? ?? false;
  final programmaticPass = harnessPass && osPass;
  final predicateVector = <String, dynamic>{
    'harnessProgrammatic': harnessPass,
    ...Map<String, dynamic>.from(
      osNotification['predicates'] as Map? ?? const <String, dynamic>{},
    ),
  };
  _log('ORCH', '$id predicates: ${jsonEncode(predicateVector)}');
  _log(
    'ORCH',
    '$id programmatic: ${programmaticPass ? 'PASS' : 'FAIL'} '
        '(shown=${verdict['notificationShown']}, '
        'suppressed=${verdict['notificationSuppressed']}, '
        'osCount=${osNotification['activeCount']})',
  );

  bool? audibleConfirmed;
  if (_nonInteractive) {
    audibleConfirmed = null;
  } else if (expectAudible) {
    final answer = _promptOperator(
      '$id — did you hear a notification SOUND on Bob\'s simulator? (y/n): ',
    );
    audibleConfirmed = answer.startsWith('y');
  } else {
    final answer = _promptOperator(
      '$id — confirm Bob\'s simulator stayed SILENT (no sound)? (y/n): ',
    );
    audibleConfirmed = answer.startsWith('y');
  }

  _signals.writeSignal(verdictAckSignal);
  return ScenarioOutcome(
    id: id,
    selected: true,
    programmaticPass: programmaticPass,
    audibleConfirmed: audibleConfirmed,
    verdict: verdict,
    osNotification: osNotification,
  );
}

class _FocusedRowsComplete implements Exception {
  const _FocusedRowsComplete();
}

void _recordScenarioOutcome(
  List<ScenarioOutcome> outcomes,
  ScenarioOutcome outcome,
) {
  outcomes.add(outcome);
  if (!outcome.selected) return;
  if (!outcome.programmaticPass) {
    final predicates = <String, dynamic>{
      'harnessProgrammatic':
          outcome.verdict['programmaticPass'] as bool? ?? false,
      ...Map<String, dynamic>.from(
        outcome.osNotification['predicates'] as Map? ??
            const <String, dynamic>{},
      ),
    };
    final failed = predicates.entries
        .where((entry) => entry.value != true)
        .map((entry) => entry.key)
        .toList(growable: false);
    throw StateError('${outcome.id} failed predicates: ${failed.join(', ')}');
  }
  final selectedRows = _selectedRows;
  if (selectedRows != null &&
      selectedRows.every(
        (id) => outcomes.any(
          (candidate) => candidate.selected && candidate.id == id,
        ),
      )) {
    throw const _FocusedRowsComplete();
  }
}

Future<void> main(List<String> args) async {
  final devices = <String>[];
  String? artifactPath;
  String? rowFilter;
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      devices.addAll(
        args[i + 1].split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
      );
      i++;
    } else if (args[i] == '--artifact-dir' && i + 1 < args.length) {
      artifactPath = args[i + 1].trim();
      i++;
    } else if (args[i] == '--rows' && i + 1 < args.length) {
      rowFilter = args[i + 1].trim();
      i++;
    } else if (args[i] == '--non-interactive') {
      _nonInteractive = true;
    }
  }
  if (devices.length != 2) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/run_notification_sound_smoke.dart '
      '-d <alice_udid>,<bob_udid> [--artifact-dir <dir>] '
      '[--rows S6,S7] [--non-interactive]',
    );
    exit(1);
  }
  if (rowFilter != null) {
    final parsed = rowFilter
        .split(',')
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    final invalid = parsed.difference(_allScenarioIds);
    if (parsed.isEmpty || invalid.isNotEmpty) {
      stderr.writeln(
        'Invalid --rows value. Expected a comma-separated subset of '
        'S1..S13; invalid=${invalid.toList()..sort()}',
      );
      exit(64);
    }
    _selectedRows = parsed;
  }
  final aliceDevice = devices[0];
  final bobDevice = devices[1];
  final aliceIsAndroid = await _isLiveAdbDevice(aliceDevice);
  _bobDevice = bobDevice;
  _bobIsAndroid = await _isLiveAdbDevice(bobDevice);
  if (aliceIsAndroid != _bobIsAndroid) {
    stderr.writeln(
      'Mixed Android/non-Android topology is not supported by this '
      'two-peer signal transport.',
    );
    exit(64);
  }
  _androidPair = aliceIsAndroid && _bobIsAndroid;
  _appPackage = resolveAndroidAppPackage();
  if (artifactPath != null && artifactPath.isNotEmpty) {
    _artifactDirectory = Directory(artifactPath).absolute
      ..createSync(recursive: true);
  }

  _runId = DateTime.now().millisecondsSinceEpoch.toString();
  _sharedDir = await Directory.systemTemp.createTemp('notif_sound_smoke_');
  // Byte-identical to the old inline `'$_sharedDir/nsmoke_${_runId}_$name'`:
  // prefix 'nsmoke_', runId carries the trailing '_'.
  _signals = SignalDir(
    dir: _sharedDir.path,
    prefix: 'nsmoke_',
    runId: '${_runId}_',
    role: 'Orchestrator',
  );
  if (_androidPair) {
    _remoteSharedDirRelative = 'cache/notif_sound_smoke_$_runId';
    _remoteSharedDir = '/data/user/0/$_appPackage/$_remoteSharedDirRelative';
  }

  final aliceLog = File(
    '${_sharedDir.path}/alice.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);
  final bobLog = File(
    '${_sharedDir.path}/bob.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);

  _log('ORCH', 'Shared dir: ${_sharedDir.path}');
  _log('ORCH', 'Alice=$aliceDevice  Bob=$bobDevice  runId=$_runId');

  Process? alice;
  Process? bob;
  final outcomes = <ScenarioOutcome>[];
  final signalSync = _androidPair
      ? _syncAndroidSignalFiles(<String>[aliceDevice, bobDevice])
      : null;

  try {
    alice = await _launchHarness(
      harness: _mergedHarness,
      role: 'alice',
      deviceId: aliceDevice,
      dbName: 'notif_sound_smoke_${_runId}_alice.db',
    );
    _pipeOutput(alice.stdout, 'ALICE', aliceLog);
    _pipeOutput(alice.stderr, 'ALICE-ERR', aliceLog);

    _log('ORCH', 'Waiting for alice_ready...');
    await _signals.waitForSignal(
      'alice_ready',
      timeout: const Duration(minutes: 5),
    );
    _log('ORCH', 'Alice ready — launching Bob');

    bob = await _launchHarness(
      harness: _mergedHarness,
      role: 'bob',
      deviceId: bobDevice,
      dbName: 'notif_sound_smoke_${_runId}_bob.db',
    );
    _pipeOutput(bob.stdout, 'BOB', bobLog);
    _pipeOutput(bob.stderr, 'BOB-ERR', bobLog);

    _log('ORCH', 'Waiting for bob_ready...');
    await _signals.waitForSignal(
      'bob_ready',
      timeout: const Duration(minutes: 5),
    );
    await _grantAndroidNotificationPermission();
    _log('ORCH', 'Both harnesses ready');

    // Human checklist + audio-setup confirmation.
    _printChecklist();

    // S1: 1:1 direct
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S1',
        goSignal: 's1_go',
        bobVerdictSignal: 's1_bob_verdict',
        verdictAckSignal: 's1_verdict_ack',
        description: '1:1 direct chat (expect notification + sound)',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );

    // S2: Group discussion (GroupType.chat). Group creation + join runs
    // inside the harnesses; orchestrator just triggers the send.
    _log('ORCH', 'Waiting for Bob to join chat group...');
    await _signals.waitForSignal(
      'bob_group_chat_joined',
      timeout: const Duration(minutes: 5),
    );
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S2',
        goSignal: 's2_go',
        bobVerdictSignal: 's2_bob_verdict',
        verdictAckSignal: 's2_verdict_ack',
        description: 'Group discussion (expect notification + sound)',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );

    // S3: Group announcement
    _log('ORCH', 'Waiting for Bob to join announcement group...');
    await _signals.waitForSignal(
      'bob_group_announcement_joined',
      timeout: const Duration(minutes: 5),
    );
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S3',
        goSignal: 's3_go',
        bobVerdictSignal: 's3_bob_verdict',
        verdictAckSignal: 's3_verdict_ack',
        description: 'Group announcement (expect notification + sound)',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );

    // S4: Suppression control — Bob simulates viewing Alice's 1:1 conversation.
    _log('ORCH', 'Waiting for Bob to simulate viewing conversation...');
    await _signals.waitForSignal(
      'bob_viewing_conversation',
      timeout: const Duration(minutes: 5),
    );
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S4',
        goSignal: 's4_go',
        bobVerdictSignal: 's4_bob_verdict',
        verdictAckSignal: 's4_verdict_ack',
        description: 'Suppression control (expect SILENCE)',
        expectAudible: false,
        expectSuppressed: true,
      ),
    );

    const mediaDescriptions = <String, String>{
      'S5': '1:1 image-only message',
      'S6': '1:1 video-only message',
      'S7': '1:1 voice-only message',
      'S8': 'group discussion image-only message',
      'S9': 'group discussion video-only message',
      'S10': 'group discussion voice-only message',
      'S11': 'announcement image-only message',
      'S12': 'announcement video-only message',
      'S13': 'announcement voice-only message',
    };
    for (final entry in mediaDescriptions.entries) {
      final signal = entry.key.toLowerCase();
      _recordScenarioOutcome(
        outcomes,
        await _runScenario(
          id: entry.key,
          goSignal: '${signal}_go',
          bobVerdictSignal: '${signal}_bob_verdict',
          verdictAckSignal: '${signal}_verdict_ack',
          description: entry.value,
          expectAudible: true,
          expectSuppressed: false,
        ),
      );
    }

    _signals.writeSignal('all_done');
    await _signals.waitForSignal(
      'alice_done',
      timeout: const Duration(seconds: 60),
    );
    await _signals.waitForSignal(
      'bob_done',
      timeout: const Duration(seconds: 60),
    );
  } on _FocusedRowsComplete {
    _log('ORCH', 'Focused --rows evidence complete; stopping harnesses');
  } finally {
    _log('ORCH', 'Cleaning up...');
    alice?.kill();
    bob?.kill();
    _stopSignalSync = true;
    if (signalSync != null) {
      await signalSync.timeout(const Duration(seconds: 5));
    }
    await aliceLog.flush();
    await aliceLog.close();
    await bobLog.flush();
    await bobLog.close();

    final selectedOutcomes = outcomes
        .where((outcome) => outcome.selected)
        .toList(growable: false);
    final laneIds = <String, Set<int>>{
      'direct': <int>{},
      'group': <int>{},
      'announcement': <int>{},
    };
    final laneObservationCounts = <String, int>{
      'direct': 0,
      'group': 0,
      'announcement': 0,
    };
    String? laneFor(String id) => switch (id) {
      'S1' || 'S5' || 'S6' || 'S7' => 'direct',
      'S2' || 'S8' || 'S9' || 'S10' => 'group',
      'S3' || 'S11' || 'S12' || 'S13' => 'announcement',
      _ => null,
    };
    final expectedLaneObservationCounts = <String, int>{
      'direct': 0,
      'group': 0,
      'announcement': 0,
    };
    for (final outcome in selectedOutcomes) {
      final lane = laneFor(outcome.id);
      if (lane == null) continue;
      expectedLaneObservationCounts[lane] =
          expectedLaneObservationCounts[lane]! + 1;
      final records =
          outcome.osNotification['records'] as List<dynamic>? ?? const [];
      if (records.length != 1 || records.single is! Map) continue;
      final id = (records.single as Map)['id'];
      if (id is int) {
        laneIds[lane]!.add(id);
        laneObservationCounts[lane] = laneObservationCounts[lane]! + 1;
      }
    }
    final conversationCardIdentity = <String, dynamic>{
      for (final lane in laneIds.keys)
        lane: <String, dynamic>{
          'applicable': expectedLaneObservationCounts[lane]! > 0,
          'stable':
              expectedLaneObservationCounts[lane] == 0 ||
              (laneIds[lane]!.length == 1 &&
                  laneObservationCounts[lane] ==
                      expectedLaneObservationCounts[lane]),
          'observations': laneObservationCounts[lane],
          'expectedObservations': expectedLaneObservationCounts[lane],
          'distinctIds': laneIds[lane]!.length,
          'id': laneIds[lane]!.length == 1 ? laneIds[lane]!.single : null,
        },
    };
    final stableConversationCards =
        !_bobIsAndroid ||
        conversationCardIdentity.values.every(
          (value) => (value as Map<String, dynamic>)['stable'] == true,
        );

    // Summary
    final rowFilterSummary = _selectedRows == null
        ? null
        : (_selectedRows!.toList()..sort());
    final summary = <String, dynamic>{
      'runId': _runId,
      'sharedDir': _sharedDir.path,
      'rowFilter': rowFilterSummary,
      'androidRecipient': _bobIsAndroid,
      'stableConversationCards': stableConversationCards,
      'conversationCardIdentity': conversationCardIdentity,
      'prerequisiteRows': outcomes
          .where((outcome) => !outcome.selected)
          .map((outcome) => outcome.id)
          .toList(growable: false),
      'scenarios': selectedOutcomes.map((o) => o.toJson()).toList(),
    };
    final summaryDirectory = _artifactDirectory ?? Directory.systemTemp;
    final summaryPath = _artifactDirectory == null
        ? '${summaryDirectory.path}/notification_sound_smoke_summary_$_runId.json'
        : '${summaryDirectory.path}/notification_sound_smoke_summary.json';
    File(
      summaryPath,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));

    stdout.writeln('\n${'═' * 70}');
    stdout.writeln('  NOTIFICATION SOUND SMOKE — RESULTS');
    stdout.writeln('═' * 70);
    for (final o in selectedOutcomes) {
      final audioMark = o.audibleConfirmed == null
          ? 'skip'
          : (o.audibleConfirmed! ? 'YES' : 'NO');
      final progMark = o.programmaticPass ? 'PASS' : 'FAIL';
      stdout.writeln('  ${o.id}: programmatic=$progMark  audible=$audioMark');
    }
    stdout.writeln(
      '  stable per-conversation Android card IDs: '
      '${stableConversationCards ? 'PASS' : 'FAIL'}',
    );
    stdout.writeln('\n  Summary JSON: $summaryPath');
    stdout.writeln('${'═' * 70}\n');

    // Exit code: non-zero if any programmatic failure, OR any S1/S2/S3 was
    // NOT audibly confirmed, OR S4 was audible (suppression failure).
    // In non-interactive mode, audibleConfirmed is null and does not count.
    final failed =
        !stableConversationCards ||
        selectedOutcomes.any((o) {
          if (!o.programmaticPass) return true;
          if (o.audibleConfirmed == null) return false;
          if (o.id == 'S4') return o.audibleConfirmed == true;
          return o.audibleConfirmed == false;
        });
    exit(failed ? 1 : 0);
  }
}
