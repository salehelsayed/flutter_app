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
//   S14: 1:1 tone-window debounce    (expect audible then SILENT in-place update)
//   S15: group same-chat suppression (expect NO notification, then a control)
//   S16: 1:1 backgrounded-but-connected (expect notification + sound)
//
// Every scenario carries a machine-readable SOUND DISPOSITION (see
// [_dispositionContract]). The disposition — not an either-channel guess — is
// what the OS-capture verdict enforces: an audible scenario whose card lands on
// the silent channel is a failure, and vice versa. `--print-disposition-contract`
// emits that table for the process contract; `--verify-os-capture` runs the same
// pure decision function offline against a canned dumpsys record.
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

/// Documented S14 fallback: if the same-id in-place update's dumpsys record
/// does not surface the SILENT channel on a given API level, the conclusive
/// assertion set degrades to flags `[false, true]` + one record + same id. The
/// flags assertion stays mandatory in this mode.
bool _toneDebounceChannelFallback = false;

/// Android notification channel ids produced by the production channel mapping
/// (`lib/core/notifications/local_notification_support.dart`).
const _audibleChannel = 'mknoon_messages';
const _silentChannel = 'mknoon_messages_silent';

/// How a scenario's posted notification must SOUND.
///
/// * [audibleStrict]  — exactly one OS record on [_audibleChannel] and the
///   production `silent` flag recorded as `false`.
/// * [suppressed]     — zero `showMessageNotification` calls AND zero OS
///   records.
/// * [consistency]    — one record whose channel agrees with the recorded
///   `silent` flag. Used where the tone window legitimately makes the
///   disposition timing-dependent (consecutive same-lane scenarios).
/// * [toneDebounce]   — an audible first message followed by a SILENT in-place
///   update of the same notification id inside the tone window.
enum _SoundDisposition { audibleStrict, suppressed, consistency, toneDebounce }

class _ScenarioDisposition {
  const _ScenarioDisposition({
    required this.disposition,
    required this.lane,
    required this.expectedChannel,
  });

  final _SoundDisposition disposition;

  /// Conversation lane the scenario exercises (`direct` / `group` /
  /// `announcement`). Drives the per-lane stable-card-id assertion.
  final String lane;

  /// Printed contract token. A real channel id for the deterministic
  /// dispositions; `none` for [_SoundDisposition.suppressed] and `silentFlag`
  /// for [_SoundDisposition.consistency], where the expected channel is a
  /// function of the recorded `silent` flag rather than a constant.
  final String expectedChannel;
}

/// The ONE machine-readable scenario -> sound-disposition table.
///
/// Pinned byte-exactly by
/// `scripts/test/notification_sound_disposition_contract_test.sh`. Insertion
/// order IS the printed order, so keep it S1..S16.
const _dispositionContract = <String, _ScenarioDisposition>{
  'S1': _ScenarioDisposition(
    disposition: _SoundDisposition.audibleStrict,
    lane: 'direct',
    expectedChannel: _audibleChannel,
  ),
  'S2': _ScenarioDisposition(
    disposition: _SoundDisposition.audibleStrict,
    lane: 'group',
    expectedChannel: _audibleChannel,
  ),
  'S3': _ScenarioDisposition(
    disposition: _SoundDisposition.audibleStrict,
    lane: 'announcement',
    expectedChannel: _audibleChannel,
  ),
  'S4': _ScenarioDisposition(
    disposition: _SoundDisposition.suppressed,
    lane: 'direct',
    expectedChannel: 'none',
  ),
  'S5': _ScenarioDisposition(
    disposition: _SoundDisposition.consistency,
    lane: 'direct',
    expectedChannel: 'silentFlag',
  ),
  'S6': _ScenarioDisposition(
    disposition: _SoundDisposition.consistency,
    lane: 'direct',
    expectedChannel: 'silentFlag',
  ),
  'S7': _ScenarioDisposition(
    disposition: _SoundDisposition.consistency,
    lane: 'direct',
    expectedChannel: 'silentFlag',
  ),
  'S8': _ScenarioDisposition(
    disposition: _SoundDisposition.consistency,
    lane: 'group',
    expectedChannel: 'silentFlag',
  ),
  'S9': _ScenarioDisposition(
    disposition: _SoundDisposition.consistency,
    lane: 'group',
    expectedChannel: 'silentFlag',
  ),
  'S10': _ScenarioDisposition(
    disposition: _SoundDisposition.consistency,
    lane: 'group',
    expectedChannel: 'silentFlag',
  ),
  'S11': _ScenarioDisposition(
    disposition: _SoundDisposition.consistency,
    lane: 'announcement',
    expectedChannel: 'silentFlag',
  ),
  'S12': _ScenarioDisposition(
    disposition: _SoundDisposition.consistency,
    lane: 'announcement',
    expectedChannel: 'silentFlag',
  ),
  'S13': _ScenarioDisposition(
    disposition: _SoundDisposition.consistency,
    lane: 'announcement',
    expectedChannel: 'silentFlag',
  ),
  'S14': _ScenarioDisposition(
    disposition: _SoundDisposition.toneDebounce,
    lane: 'direct',
    expectedChannel: _silentChannel,
  ),
  'S15': _ScenarioDisposition(
    disposition: _SoundDisposition.suppressed,
    lane: 'group',
    expectedChannel: 'none',
  ),
  'S16': _ScenarioDisposition(
    disposition: _SoundDisposition.audibleStrict,
    lane: 'direct',
    expectedChannel: _audibleChannel,
  ),
};

final _allScenarioIds = _dispositionContract.keys.toSet();

void _printDispositionContract() {
  stdout.writeln('# notification-sound-smoke disposition contract v1');
  stdout.writeln('# scenario|disposition|lane|expectedChannel');
  _dispositionContract.forEach((id, entry) {
    stdout.writeln(
      '$id|${entry.disposition.name}|${entry.lane}|${entry.expectedChannel}',
    );
  });
}

/// Outcome of the pure sound-disposition decision. Shared byte-for-byte between
/// the live device path and the offline `--verify-os-capture` fixtures, so the
/// contract test exercises the SAME predicate the device run enforces.
class _DispositionEvaluation {
  const _DispositionEvaluation({
    required this.pass,
    required this.reason,
    required this.predicates,
  });

  final bool pass;
  final String reason;
  final Map<String, bool> predicates;
}

/// The pure decision function: scenario disposition + parsed OS records +
/// recorded production `silent` flags -> verdict.
///
/// [priorRecordIds] carries the notification ids observed in an earlier phase of
/// the same scenario (S14's audible first message), so the silent in-place
/// update can be asserted as a RELATIONSHIP rather than an independent find.
_DispositionEvaluation _evaluateDisposition({
  required String scenarioId,
  required List<Map<String, dynamic>> records,
  required List<bool> silentFlags,
  List<int> priorRecordIds = const <int>[],
  bool toneDebounceChannelFallback = false,
  _SoundDisposition? dispositionOverride,
}) {
  final disposition =
      dispositionOverride ?? _dispositionContract[scenarioId]?.disposition;
  if (disposition == null) {
    return const _DispositionEvaluation(
      pass: false,
      reason: 'unknown_scenario',
      predicates: <String, bool>{'dispositionRegistered': false},
    );
  }

  String channelOf(Map<String, dynamic> record) =>
      record['channel']?.toString() ?? '';

  var cardCountMatches = true;
  var silentFlagsMatch = true;
  var channelMatches = true;
  var toneDebounceIdStable = true;

  switch (disposition) {
    case _SoundDisposition.audibleStrict:
      cardCountMatches = records.length == 1;
      silentFlagsMatch = silentFlags.length == 1 && !silentFlags.single;
      channelMatches =
          cardCountMatches && channelOf(records.single) == _audibleChannel;
    case _SoundDisposition.suppressed:
      cardCountMatches = records.isEmpty;
      silentFlagsMatch = silentFlags.isEmpty;
    case _SoundDisposition.consistency:
      cardCountMatches = records.length == 1;
      silentFlagsMatch = silentFlags.length == 1;
      channelMatches =
          cardCountMatches &&
          silentFlagsMatch &&
          channelOf(records.single) ==
              (silentFlags.single ? _silentChannel : _audibleChannel);
    case _SoundDisposition.toneDebounce:
      // The flags assertion is the load-bearing exclusion of the
      // "second message was simply suppressed" degenerate pass; it is
      // mandatory in BOTH the primary and the channel-fallback mode.
      silentFlagsMatch =
          silentFlags.length == 2 && !silentFlags[0] && silentFlags[1];
      cardCountMatches = records.length == 1;
      toneDebounceIdStable =
          !cardCountMatches ||
          priorRecordIds.isEmpty ||
          priorRecordIds.contains(records.single['id']);
      channelMatches =
          toneDebounceChannelFallback ||
          (cardCountMatches && channelOf(records.single) == _silentChannel);
  }

  final String reason;
  if (disposition == _SoundDisposition.suppressed &&
      (!cardCountMatches || !silentFlagsMatch)) {
    reason = 'unexpected_notification';
  } else if (disposition == _SoundDisposition.toneDebounce &&
      !silentFlagsMatch) {
    reason = 'tone_debounce_flags_mismatch';
  } else if (!cardCountMatches) {
    reason = 'card_count_mismatch';
  } else if (!silentFlagsMatch) {
    reason = 'silent_flag_contradiction';
  } else if (!toneDebounceIdStable) {
    reason = 'tone_debounce_id_not_stable';
  } else if (!channelMatches) {
    reason = 'channel_contradiction';
  } else {
    reason = 'ok';
  }

  final predicates = <String, bool>{
    'dispositionRegistered': true,
    'cardCountMatchesDisposition': cardCountMatches,
    'silentFlagsMatchDisposition': silentFlagsMatch,
    'channelMatchesDisposition': channelMatches,
    'toneDebounceIdStable': toneDebounceIdStable,
  };
  return _DispositionEvaluation(
    pass: predicates.values.every((value) => value),
    reason: reason,
    predicates: predicates,
  );
}

List<bool> _silentFlagsFromVerdict(Map<String, dynamic> verdict) =>
    (verdict['shownCalls'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((call) => call['silent'] == true)
        .toList(growable: false);

/// Offline `--verify-os-capture <scenarioId> <dumpsys-file> <verdict-json>`.
///
/// Parses a canned `dumpsys notification --noredact` capture with the SAME
/// extractor the live path uses, runs [_evaluateDisposition], and emits exactly
/// one machine-readable reason line. Returns the process exit code.
int _verifyOsCaptureOffline(
  List<String> operands, {
  required bool toneDebounceChannelFallback,
}) {
  final positional = operands
      .where((value) => !value.startsWith('--'))
      .toList(growable: false);
  if (positional.length < 3) {
    stderr.writeln(
      'Usage: --verify-os-capture <scenarioId> <dumpsys-file> <verdict-json>',
    );
    return 64;
  }
  final scenarioId = positional[0].toUpperCase();
  final dumpFile = File(positional[1]);
  final verdictFile = File(positional[2]);
  if (!dumpFile.existsSync()) {
    stderr.writeln('Missing dumpsys fixture: ${dumpFile.path}');
    return 66;
  }
  if (!verdictFile.existsSync()) {
    stderr.writeln('Missing verdict fixture: ${verdictFile.path}');
    return 66;
  }

  _appPackage = resolveAndroidAppPackage();
  final records = _activeAppNotificationRecords(dumpFile.readAsStringSync())
      .map(_sanitizeNotificationRecord)
      .toList(growable: false);
  final Map<String, dynamic> verdict;
  try {
    verdict =
        jsonDecode(verdictFile.readAsStringSync()) as Map<String, dynamic>;
  } on FormatException catch (error) {
    stderr.writeln('Invalid verdict fixture ${verdictFile.path}: $error');
    return 65;
  }

  final evaluation = _evaluateDisposition(
    scenarioId: scenarioId,
    records: records,
    silentFlags: _silentFlagsFromVerdict(verdict),
    priorRecordIds: (verdict['priorRecordIds'] as List<dynamic>? ?? const [])
        .whereType<int>()
        .toList(growable: false),
    toneDebounceChannelFallback: toneDebounceChannelFallback,
  );
  final disposition =
      _dispositionContract[scenarioId]?.disposition.name ?? 'unregistered';
  stdout.writeln(
    'os-capture-verdict scenario=$scenarioId disposition=$disposition '
    'result=${evaluation.pass ? 'pass' : 'fail'} reason=${evaluation.reason} '
    'records=${records.length}',
  );
  return evaluation.pass ? 0 : 1;
}

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
  _promptOperator('Press Enter when ready to run S1..S16: ');
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

/// Light-weight active-record capture: the dumpsys poll ONLY, with no shade
/// expansion, uiautomator dump, or screenshot. Used for S14's phase-1 capture,
/// which must complete well inside the 30s tone window.
Future<List<Map<String, dynamic>>> _captureActiveRecords({
  required int expectedCount,
}) async {
  if (!_bobIsAndroid) return const <Map<String, dynamic>>[];
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
    if (records.length == expectedCount) break;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return records.map(_sanitizeNotificationRecord).toList(growable: false);
}

Future<Map<String, dynamic>> _captureAndroidNotificationState({
  required String scenarioId,
  required Map<String, dynamic> verdict,
  required bool expectSuppressed,
  List<int> priorRecordIds = const <int>[],
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
  // Identity/copy are read from the call that produced the CURRENT card. Every
  // disposition but toneDebounce posts exactly one card from exactly one call;
  // S14 posts an in-place update, so the surviving card carries the SECOND
  // call's copy.
  final expectedCallCount =
      _dispositionContract[scenarioId]?.disposition ==
          _SoundDisposition.toneDebounce
      ? 2
      : 1;
  final expectedCall = shownCalls.length == expectedCallCount
      ? shownCalls.last
      : null;
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

      // A silent MKnoon card can be below a full page of unrelated alerting
      // notifications on a physical test phone. Reopening the shade without
      // scrolling merely captures the same first page on every retry. Scroll
      // progressively instead of clearing unrelated user notifications.
      final scrollCount = attempt - 1;
      for (var scroll = 0; scroll < scrollCount; scroll++) {
        await _adb(const <String>[
          'shell',
          'input',
          'swipe',
          '540',
          '1800',
          '540',
          '650',
          '300',
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

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
            'scrollCount': scrollCount,
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
        'scrollCount': scrollCount,
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

  // The scenario's pinned disposition — NOT an either-channel guess — decides
  // whether the observed channel and the recorded production `silent` flags are
  // acceptable. Same pure function the offline `--verify-os-capture` mode runs.
  final dispositionEvaluation = _evaluateDisposition(
    scenarioId: scenarioId,
    records: sanitized,
    silentFlags: shownCalls
        .map((call) => call['silent'] == true)
        .toList(growable: false),
    priorRecordIds: priorRecordIds,
    toneDebounceChannelFallback: _toneDebounceChannelFallback,
  );
  final channel = observed?['channel']?.toString() ?? '';
  final predicates = <String, bool>{
    'cardCountMatches': expectSuppressed
        ? records.isEmpty
        : records.length == 1,
    'packageMatches': expectSuppressed
        ? true
        : observed?['package'] == _appPackage,
    ...dispositionEvaluation.predicates,
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
    'channelMatchesContract':
        dispositionEvaluation.predicates['channelMatchesDisposition'] ?? false,
    'disposition':
        _dispositionContract[scenarioId]?.disposition.name ?? 'unregistered',
    'dispositionReason': dispositionEvaluation.reason,
    'observedChannel': channel,
    'priorRecordIds': priorRecordIds,
    'toneDebounceChannelFallback': _toneDebounceChannelFallback,
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
  List<int> priorRecordIds = const <int>[],
}) async {
  final contract = _dispositionContract[id];
  if (contract == null) {
    throw StateError('$id has no entry in the sound-disposition contract');
  }
  final contractSuppressed =
      contract.disposition == _SoundDisposition.suppressed;
  if (contractSuppressed != expectSuppressed) {
    throw StateError(
      '$id disposition (${contract.disposition.name}) contradicts '
      'expectSuppressed=$expectSuppressed',
    );
  }
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
    priorRecordIds: priorRecordIds,
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
    // `audibleConfirmed` always means "the operator heard a sound". The silent
    // prompt asks the inverse question, so invert the answer here rather than
    // storing an expectation-shaped boolean the exit rule would misread.
    audibleConfirmed = !answer.startsWith('y');
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

/// S15's in-scenario control leg.
///
/// "Zero cards" is only evidence of SUPPRESSION if the same lane demonstrably
/// notifies once the active-group tracker is cleared — otherwise a dead group
/// notification lane would pass the suppression assertion. Bob clears the
/// tracker before publishing the suppressed verdict; this drives the follow-up
/// message and folds its result into the S15 outcome.
///
/// Deliberately uses the LIGHT record capture: the harness verdict already
/// pins identity/copy/payload for the control message, so the shade dance and
/// screenshot would add minutes of device time for no new evidence.
Future<ScenarioOutcome> _appendGroupSuppressionControl(
  ScenarioOutcome suppressed,
) async {
  _log('ORCH', '─── S15 control: post-clear group message must notify ───');
  _signals.writeSignal('s15_control_go');
  final verdict = await _signals.waitForJson(
    's15_control_bob_verdict',
    timeout: const Duration(minutes: 5),
  );
  final harnessPass = verdict['programmaticPass'] as bool? ?? false;

  if (!suppressed.selected || !_bobIsAndroid) {
    _signals.writeSignal('s15_control_ack');
    if (!harnessPass) {
      throw StateError(
        'S15 control leg did not notify after the group tracker cleared',
      );
    }
    return suppressed;
  }

  final records = await _captureActiveRecords(expectedCount: 1);
  final evaluation = _evaluateDisposition(
    scenarioId: 'S15_control',
    records: records,
    silentFlags: _silentFlagsFromVerdict(verdict),
    dispositionOverride: _SoundDisposition.audibleStrict,
  );
  _signals.writeSignal('s15_control_ack');
  _log(
    'ORCH',
    'S15 control: harness=${harnessPass ? 'PASS' : 'FAIL'} '
        'os=${evaluation.pass ? 'PASS' : 'FAIL'} reason=${evaluation.reason}',
  );

  final controlPass = harnessPass && evaluation.pass;
  final mergedPredicates = <String, dynamic>{
    ...Map<String, dynamic>.from(
      suppressed.osNotification['predicates'] as Map? ??
          const <String, dynamic>{},
    ),
    'controlHarnessProgrammatic': harnessPass,
    for (final entry in evaluation.predicates.entries)
      'control_${entry.key}': entry.value,
  };
  return ScenarioOutcome(
    id: suppressed.id,
    selected: suppressed.selected,
    programmaticPass: suppressed.programmaticPass && controlPass,
    audibleConfirmed: suppressed.audibleConfirmed,
    verdict: suppressed.verdict,
    osNotification: <String, dynamic>{
      ...suppressed.osNotification,
      'pass':
          (suppressed.osNotification['pass'] as bool? ?? false) && controlPass,
      'predicates': mergedPredicates,
      'control': <String, dynamic>{
        'harnessProgrammatic': harnessPass,
        'pass': evaluation.pass,
        'reason': evaluation.reason,
        'records': records,
        'verdict': _redactedVerdict(verdict),
      },
    },
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
  // Deviceless process-contract modes. Both must resolve BEFORE the device-pair
  // requirement below, so `scripts/test/notification_sound_disposition_contract_test.sh`
  // can exercise them without ever attaching (or driving) a real device.
  if (args.contains('--print-disposition-contract')) {
    _printDispositionContract();
    return;
  }
  final verifyIndex = args.indexOf('--verify-os-capture');
  if (verifyIndex >= 0) {
    exit(
      _verifyOsCaptureOffline(
        args.sublist(verifyIndex + 1),
        toneDebounceChannelFallback: args.contains(
          '--tone-debounce-channel-fallback',
        ),
      ),
    );
  }

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
    } else if (args[i] == '--tone-debounce-channel-fallback') {
      _toneDebounceChannelFallback = true;
    }
  }
  if (devices.length != 2) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/run_notification_sound_smoke.dart '
      '-d <alice_udid>,<bob_udid> [--artifact-dir <dir>] '
      '[--rows S6,S7] [--non-interactive] '
      '[--tone-debounce-channel-fallback]\n'
      '       dart run integration_test/scripts/run_notification_sound_smoke.dart '
      '--print-disposition-contract\n'
      '       dart run integration_test/scripts/run_notification_sound_smoke.dart '
      '--verify-os-capture <scenarioId> <dumpsys-file> <verdict-json>',
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
        'S1..S16; invalid=${invalid.toList()..sort()}',
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
  var runCompleted = false;
  Object? runError;
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

    // S5-S13: attachment-only media notifications across the three lanes.
    //
    // These MUST stay literal `_runScenario` blocks. The reliability-simulation
    // discovery gate parses this file with awk
    // (`scripts/check_reliability_simulation_discovery.sh:1019-1039`) and can
    // only see `id: '<Sn>'` / `description: '<text>'` single-line literals — a
    // map loop registers ZERO rows while the gate still exits 0. The
    // descriptions also feed the gate's family filter (`:1005-1015`): they must
    // contain `1:1` for the 1to1 family and `Group` for the group family, and
    // never both.
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S5',
        goSignal: 's5_go',
        bobVerdictSignal: 's5_bob_verdict',
        verdictAckSignal: 's5_verdict_ack',
        description: '1:1 image-only message',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S6',
        goSignal: 's6_go',
        bobVerdictSignal: 's6_bob_verdict',
        verdictAckSignal: 's6_verdict_ack',
        description: '1:1 video-only message',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S7',
        goSignal: 's7_go',
        bobVerdictSignal: 's7_bob_verdict',
        verdictAckSignal: 's7_verdict_ack',
        description: '1:1 voice-only message',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S8',
        goSignal: 's8_go',
        bobVerdictSignal: 's8_bob_verdict',
        verdictAckSignal: 's8_verdict_ack',
        description: 'Group discussion image-only message',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S9',
        goSignal: 's9_go',
        bobVerdictSignal: 's9_bob_verdict',
        verdictAckSignal: 's9_verdict_ack',
        description: 'Group discussion video-only message',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S10',
        goSignal: 's10_go',
        bobVerdictSignal: 's10_bob_verdict',
        verdictAckSignal: 's10_verdict_ack',
        description: 'Group discussion voice-only message',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S11',
        goSignal: 's11_go',
        bobVerdictSignal: 's11_bob_verdict',
        verdictAckSignal: 's11_verdict_ack',
        description: 'Group announcement image-only message',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S12',
        goSignal: 's12_go',
        bobVerdictSignal: 's12_bob_verdict',
        verdictAckSignal: 's12_verdict_ack',
        description: 'Group announcement video-only message',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S13',
        goSignal: 's13_go',
        bobVerdictSignal: 's13_bob_verdict',
        verdictAckSignal: 's13_verdict_ack',
        description: 'Group announcement voice-only message',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );

    // ════════════════════════════════════════════════════════════════
    //  S14: tone-window debounce (1:1). Two texts inside the 30s window:
    //       the first is audible, the second is a SILENT in-place update of
    //       the SAME notification id.
    // ════════════════════════════════════════════════════════════════
    // The window anchors on the last AUDIBLE tone for this conversation key
    // (`notification_tone_tracker.dart:31-43`), so wait it out first —
    // otherwise msg1 inherits an open window and the pair is inconclusive.
    _log('ORCH', 'S14: 31s tone cooldown so msg1 is deterministically audible');
    await Future<void>.delayed(const Duration(seconds: 31));
    _signals.writeSignal('s14_go');
    final s14FirstVerdict = await _signals.waitForJson(
      's14_first_bob_verdict',
      timeout: const Duration(minutes: 5),
    );
    var s14PriorRecordIds = const <int>[];
    if (_isSelectedRow('S14')) {
      if (s14FirstVerdict['programmaticPass'] as bool? ?? false) {
        // LIGHT capture only — the shade/uiautomator dance would burn most of
        // the 30s window before msg2 could be sent.
        final phase1 = await _captureActiveRecords(expectedCount: 1);
        s14PriorRecordIds = phase1
            .map((record) => record['id'])
            .whereType<int>()
            .toList(growable: false);
        _log('ORCH', 'S14 phase-1 audible record ids: $s14PriorRecordIds');
      } else {
        throw StateError('S14 phase-1 audible message failed its harness predicate');
      }
    }
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S14',
        goSignal: 's14_second_go',
        bobVerdictSignal: 's14_bob_verdict',
        verdictAckSignal: 's14_verdict_ack',
        description: '1:1 tone-window debounce (second message updates silently)',
        expectAudible: false,
        expectSuppressed: false,
        priorRecordIds: s14PriorRecordIds,
      ),
    );

    // ════════════════════════════════════════════════════════════════
    //  S15: group same-chat suppression. Bob is resumed WITH the discussion
    //       group marked active, so an incoming group text must not notify.
    //       A post-clear control message in the same scenario proves the
    //       silence came from the suppression gate and not from a dead lane.
    // ════════════════════════════════════════════════════════════════
    _log('ORCH', 'Waiting for Bob to simulate viewing the discussion group...');
    await _signals.waitForSignal(
      'bob_viewing_group',
      timeout: const Duration(minutes: 5),
    );
    final s15Outcome = await _runScenario(
      id: 'S15',
      goSignal: 's15_go',
      bobVerdictSignal: 's15_bob_verdict',
      verdictAckSignal: 's15_verdict_ack',
      description: 'Group discussion same-chat suppression (expect SILENCE)',
      expectAudible: false,
      expectSuppressed: true,
    );
    _recordScenarioOutcome(
      outcomes,
      await _appendGroupSuppressionControl(s15Outcome),
    );

    // ════════════════════════════════════════════════════════════════
    //  S16: backgrounded-but-connected 1:1. Bob's logical lifecycle is
    //       `paused` with no active conversation while the bridge stays live;
    //       delivery must still post one audible OS record.
    // ════════════════════════════════════════════════════════════════
    _log('ORCH', 'S16: 31s tone cooldown before the paused-lifecycle leg');
    await Future<void>.delayed(const Duration(seconds: 31));
    _log('ORCH', 'Waiting for Bob to report a backgrounded lifecycle...');
    await _signals.waitForSignal(
      'bob_backgrounded',
      timeout: const Duration(minutes: 5),
    );
    _recordScenarioOutcome(
      outcomes,
      await _runScenario(
        id: 'S16',
        goSignal: 's16_go',
        bobVerdictSignal: 's16_bob_verdict',
        verdictAckSignal: 's16_verdict_ack',
        description: '1:1 backgrounded-but-connected delivery (expect notification + sound)',
        expectAudible: true,
        expectSuppressed: false,
      ),
    );

    _signals.writeSignal('all_done');
    await _signals.waitForSignal(
      'alice_done',
      timeout: const Duration(seconds: 60),
    );
    await _signals.waitForSignal(
      'bob_done',
      timeout: const Duration(seconds: 60),
    );
    runCompleted = true;
  } on _FocusedRowsComplete {
    runCompleted = true;
    _log('ORCH', 'Focused --rows evidence complete; stopping harnesses');
  } on Object catch (error, stackTrace) {
    // The `finally` below calls exit(), which would otherwise swallow this
    // exception AND its exit code — a harness that dies during setup would be
    // reported as a clean pass with zero scenarios.
    runError = error;
    _log('ORCH', 'Run aborted: $error');
    stderr.writeln(stackTrace);
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
    // Derived from the disposition contract so a new row cannot silently skip
    // the stable-card-id assertion. Suppressed rows are excluded: they post no
    // record, so counting them would make their own lane look unstable.
    String? laneFor(String id) {
      final entry = _dispositionContract[id];
      if (entry == null) return null;
      if (entry.disposition == _SoundDisposition.suppressed) return null;
      return entry.lane;
    }
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

    // A run that never produced its scenarios is a FAILURE, not a pass. Without
    // this, a harness that dies during setup leaves `selectedOutcomes` empty,
    // every lane trivially "stable", and the run exits 0 having proven nothing.
    final expectedScenarioCount =
        _selectedRows?.length ?? _dispositionContract.length;
    final incomplete =
        runError != null ||
        !runCompleted ||
        selectedOutcomes.length < expectedScenarioCount;
    if (incomplete) {
      stdout.writeln(
        '  INCOMPLETE: ${selectedOutcomes.length}/$expectedScenarioCount '
        'scenarios produced evidence'
        '${runError == null ? '' : ' (aborted: $runError)'}',
      );
    }

    // Exit code: non-zero if the run did not complete, OR any programmatic
    // failure, OR an audible-expecting row was NOT heard, OR a row whose
    // conclusive state is silence DID make a sound. `audibleConfirmed` always
    // means "the operator heard a sound", so the polarity follows the pinned
    // disposition. In non-interactive mode it is null and does not count.
    final failed =
        incomplete ||
        !stableConversationCards ||
        selectedOutcomes.any((o) {
          if (!o.programmaticPass) return true;
          if (o.audibleConfirmed == null) return false;
          final disposition = _dispositionContract[o.id]?.disposition;
          if (disposition == _SoundDisposition.suppressed ||
              disposition == _SoundDisposition.toneDebounce) {
            return o.audibleConfirmed == true;
          }
          return o.audibleConfirmed == false;
        });
    exit(failed ? 1 : 0);
  }
}
