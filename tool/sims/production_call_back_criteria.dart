import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import '../../integration_test/support/android_production_audio_call_evidence.dart';
import 'artifact_evidence.dart';

Map<String, Object?> _object(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};
List<Map<String, Object?>> _events(Map<String, Object?> snapshot) =>
    (snapshot['events'] is List ? snapshot['events'] as List : const [])
        .map(_object)
        .toList();
bool _hash(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

/// Raw native policy text is not persisted. A complete, recognized dump and
/// exact UID are required even for the zero-active-client observation.
Map<String, Object?> productionCallbackAudioCaptureSnapshot(
  String dump, {
  required int uid,
}) {
  if (uid < 0 ||
      dump.length > 4 * 1024 * 1024 ||
      !dump.contains('AudioPolicyManager Dump:') ||
      RegExp(
        r'DUMP TIMEOUT|Error dumping service|FAILED BINDER TRANSACTION',
        caseSensitive: false,
      ).hasMatch(dump)) {
    throw const FormatException(
      'Unreadable or over-capacity audio policy evidence.',
    );
  }
  final headers = RegExp(
    r'^ Inputs \((\d+)\):\s*$',
    multiLine: true,
  ).allMatches(dump).toList();
  if (headers.length != 1) {
    throw const FormatException('Exact input inventory missing.');
  }
  final footer = dump.indexOf('\n AllowedCapturePolicies:', headers.single.end);
  if (footer < 0 || !dump.substring(footer).contains('Policy Engine dump:')) {
    throw const FormatException('Complete input inventory footer missing.');
  }
  final section = dump.substring(headers.single.end, footer);
  final inputs = RegExp(
    r'^\s*\d+\. Port ID: \d+;[^\n]*I/O handle: \d+',
    multiLine: true,
  ).allMatches(section).length;
  if (inputs != int.parse(headers.single.group(1)!)) {
    throw const FormatException('Incomplete input descriptor inventory.');
  }
  final expected = RegExp(r'AudioRecord Clients \((\d+)\):')
      .allMatches(section)
      .fold<int>(0, (sum, match) => sum + int.parse(match.group(1)!));
  final clients = RegExp(
    r'Port ID: \d+; Session ID: \d+; uid (\d+); State: (Active|Inactive)\s*\n',
  ).allMatches(section).toList();
  var records = 0;
  var activeOwned = 0;
  for (var i = 0; i < clients.length; i++) {
    final body = section.substring(
      clients[i].end,
      i + 1 < clients.length ? clients[i + 1].start : section.length,
    );
    if (!RegExp(
      r'^(?:[^\n]*\n){1,4}\s*Source: \d+; Flags:',
      multiLine: false,
    ).hasMatch(body)) {
      continue;
    }
    records++;
    if (int.parse(clients[i].group(1)!) == uid &&
        clients[i].group(2) == 'Active') {
      activeOwned++;
    }
  }
  if (records != expected) {
    throw const FormatException('Unrecognized recording-client inventory.');
  }
  return {
    'captureReadSucceeded': true,
    'activeOwnedRecordClients': activeOwned,
    'sourceDumpSha256': sha256.convert(utf8.encode(dump)).toString(),
  };
}

/// Reading a credential-free keyguard is sufficient for the existing native
/// unlocked predicate. A secure or unknown state never authorizes changing it.
bool productionCallbackKeyguardIsUnsecured(String dump) {
  if (dump.length > 4 * 1024 * 1024 ||
      RegExp(
        r'DUMP TIMEOUT|Error dumping service|FAILED BINDER TRANSACTION',
        caseSensitive: false,
      ).hasMatch(dump)) {
    return false;
  }
  final headings = RegExp(
    r'^\s*KeyguardServiceDelegate\s*$',
    multiLine: true,
  ).allMatches(dump).toList();
  if (headings.length != 1) return false;
  final section = dump
      .substring(headings.single.end)
      .split('\n')
      .take(18)
      .join('\n');
  final secure = RegExp(
    r'^\s*secure=(true|false)\s*$',
    multiLine: true,
  ).allMatches(section).toList();
  return secure.length == 1 &&
      secure.single.group(1) == 'false' &&
      RegExp(
        r'^\s*deviceHasKeyguard=true\s*$',
        multiLine: true,
      ).hasMatch(section) &&
      RegExp(r'^\s*systemIsReady=true\s*$', multiLine: true).hasMatch(section);
}

File? _ownedFile(Object? path, Object? attempt) {
  if (path is! String || attempt is! String) return null;
  try {
    final file = File(path);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file ||
        !file.resolveSymbolicLinksSync().startsWith(
          '${Directory(attempt).resolveSymbolicLinksSync()}${Platform.pathSeparator}',
        )) {
      return null;
    }
    return file;
  } on FileSystemException {
    return null;
  }
}

bool _message(Map<String, Object?> proof, String label) {
  final receipt = _object(proof['messageReceipt']);
  final file = _ownedFile(receipt['path'], proof['attemptDirectory']);
  if (file == null ||
      receipt['label'] != label ||
      receipt['packageName'] != 'com.mknoon.sims.productionaudio' ||
      file.lengthSync() > 1024 * 1024 ||
      sha256.convert(file.readAsBytesSync()).toString() != receipt['sha256']) {
    return false;
  }
  try {
    return XmlDocument.parse(file.readAsStringSync()).descendants
            .whereType<XmlElement>()
            .where(
              (node) =>
                  node.getAttribute('package') == receipt['packageName'] &&
                  node.getAttribute('enabled') == 'true' &&
                  node.getAttribute('visible-to-user') != 'false' &&
                  (node.getAttribute('text') == label ||
                      node.getAttribute('content-desc') == label),
            )
            .length ==
        1;
  } on XmlException {
    return false;
  }
}

List<String> validateProductionCallBack(Map<String, Object?> proof) {
  final failures = <String>[];
  void check(bool condition, String failure) {
    if (!condition) failures.add(failure);
  }

  final id = proof['caseId'];
  check(
    {'kx0005', 'kx0006', 'kx0007', 'kx0008'}.contains(id),
    'unregistered callback case',
  );
  final rawPhases = proof['phases'];
  final phases = rawPhases is List
      ? rawPhases.map(_object).toList()
      : <Map<String, Object?>>[];
  Map<String, Object?> phase(String label) => _object(
    phases.where((p) => p['label'] == label).firstOrNull?['snapshot'],
  );
  check(
    phases.map((p) => p['label']).toSet().length == phases.length,
    'duplicate observation phase',
  );
  check(
    phases.isNotEmpty &&
        phases.every(
          (p) =>
              _object(p['snapshot'])['sourceBound'] == true &&
              _object(p['snapshot'])['connectionReadSucceeded'] == true,
        ),
    'canonical source unavailable',
  );
  try {
    final evidence = SimsArtifactEvidence.fromJson(proof['baselineEvidence']);
    final expected = proof['emulatorPair'] == true
        ? 'validateAndroidProductionAudioCallEmulatorArtifact'
        : androidProductionAudioCallArtifactValidatorId;
    final file = _ownedFile(evidence.path, proof['attemptDirectory']);
    check(
      file != null &&
          auditSimsArtifactEvidence(
            evidence: evidence,
            expectedValidatorIds: [expected],
          ).isValid &&
          validateAndroidProductionAudioCallDurableArtifact(
            _object(jsonDecode(file.readAsStringSync())),
            emulatorPair: proof['emulatorPair'] == true,
          ).ok,
      'current authenticated audio control/restoration missing',
    );
  } on Object {
    failures.add('invalid base audio evidence');
  }
  final invocations = proof['invocations'];
  final calls = invocations is List
      ? invocations.map(_object).toList()
      : <Map<String, Object?>>[];
  check(
    calls.isNotEmpty &&
        calls.every(
          (c) =>
              c['scenarioId'] == id &&
              c['role'] == 'alice' &&
              c['profileId'] == 'android.e2e.production_call_local' &&
              c['runId'] == calls.first['runId'],
        ) &&
        calls.map((c) => c['nonce']).toSet().length == calls.length,
    'fresh callback invocation binding missing',
  );
  final active = phase('baseline-active');
  check(
    active['inCall'] == true &&
        active['connectionPresent'] == true &&
        active['localAudioEnabled'] == true &&
        active['inboundAudioRtpObserved'] == true &&
        active['outboundAudioRtpObserved'] == true &&
        _hash(active['callSha256']),
    'positive active-call control missing',
  );
  final seed = _object(proof['seed']);
  final b = _object(seed['b']);
  final bHistory = b['historyCallSha256'];
  check(
    _hash(bHistory) && _hash(b['contactSha256']),
    'exact fixture B binding missing',
  );
  final result = _object(proof['resultSnapshot']);
  final events = _events(result);
  final requests = events
      .where((e) => e['stage'] == 'redialRequested')
      .toList();
  final completions = events.where((e) => e['stage'] == 'completed').toList();
  check(
    requests.length == 1 &&
        requests.single['historyCallSha256'] == bHistory &&
        completions.length == 1 &&
        completions.single['historyCallSha256'] == bHistory,
    'B-only admission/result not observed',
  );
  if (id == 'kx0005' || id == 'kx0006') {
    final aHistory = _object(seed['posted'])['historyCallSha256'];
    final heldA = phase('a-held');
    final heldB = phase('b-held');
    bool held(Map<String, Object?> value) =>
        value['readinessHeld'] == true &&
        _events(value).every((e) => e['stage'] == 'submitted');
    check(
      proof['verifiedOwnedProcessDeath'] == true && calls.length == 2,
      'cold callback boundary missing',
    );
    check(
      _hash(aHistory) &&
          aHistory != bHistory &&
          held(heldA) &&
          held(heldB) &&
          _events(heldA).any((e) => e['historyCallSha256'] == aHistory) &&
          _events(heldA).every((e) => e['historyCallSha256'] != bHistory) &&
          _events(heldB).any((e) => e['historyCallSha256'] == bHistory),
      'actual A then B submissions must precede admission',
    );
    check(
      completions.singleOrNull?['result'] == 'started' &&
          result['inCall'] == true &&
          result['direction'] == 'outgoing' &&
          result['contactSha256'] == b['contactSha256'] &&
          _hash(result['callSha256']) &&
          result['callSha256'] != active['callSha256'] &&
          result['deviceUnlocked'] == true,
      'fresh admitted B call missing',
    );
    if (id == 'kx0006') {
      bool locked(Map<String, Object?> value) =>
          value['deviceUnlocked'] == false &&
          value['readinessHeld'] == false &&
          _events(value).every((e) => e['stage'] == 'submitted');
      check(
        proof['unsecuredEmulatorKeyguard'] == true &&
            proof['keyguardRestored'] == true &&
            locked(phase('released-while-locked')) &&
            locked(phase('still-locked')),
        'real unlock boundary/restoration missing',
      );
    }
  } else if (id == 'kx0007') {
    final after = phase('after-busy');
    check(
      completions.singleOrNull?['result'] == 'unavailable' &&
          after['inCall'] == true &&
          after['callSha256'] == active['callSha256'] &&
          after['connectionPresent'] == true &&
          after['localAudioEnabled'] == true,
      'busy callback changed the original call or its approved result',
    );
    check(
      _message(proof, 'Voice calling is unavailable.'),
      'actual unavailable message missing',
    );
  } else if (id == 'kx0008') {
    final positive = _object(proof['positiveCapture']);
    final negative = _object(proof['negativeCapture']);
    final after = phase('after-microphone-denial');
    check(
      completions.singleOrNull?['result'] == 'microphoneDenied' &&
          after['inCall'] != true &&
          after['connectionPresent'] == false &&
          calls.length == 2,
      'denied callback result or fresh runtime missing',
    );
    check(
      positive['captureReadSucceeded'] == true &&
          positive['activeOwnedRecordClients'] is int &&
          (positive['activeOwnedRecordClients'] as int) > 0 &&
          negative['captureReadSucceeded'] == true &&
          negative['activeOwnedRecordClients'] == 0 &&
          _hash(positive['sourceDumpSha256']) &&
          _hash(negative['sourceDumpSha256']),
      'real positive-to-zero recording control missing',
    );
    check(
      maestroFlowReceiptPassed(
        proof['denialFlowReceipt'],
        proof['attemptDirectory'],
        'production_call_microphone_denial',
      ),
      'actual OS denial and message flow missing',
    );
  }
  return failures;
}
