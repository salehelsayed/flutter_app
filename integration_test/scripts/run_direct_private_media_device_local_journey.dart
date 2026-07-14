#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'direct_private_media_device_local_journey_criteria.dart';

const _artifactMarker = 'P234_DEVICE_ARTIFACT=';
const _maximumEncodedArtifactLength = 16 * 1024;
const _maximumRawOutputLineLength = 32 * 1024;
const _maximumRoleOutputLength = 4 * 1024 * 1024;
const _maximumDiscoveryOutputLength = 512 * 1024;
const _maximumAdbOutputLength = 256 * 1024;
const _maximumPublicationOutputLength = 64 * 1024;
const _forbiddenRawFragments = <String>[
  'never disclose this caption',
  'opaque-kem',
  'opaque-ciphertext',
  'opaque-nonce',
  'private-blob.bin',
];

class _Arguments {
  const _Arguments({
    required this.senderId,
    required this.recipientId,
    required this.artifactDirectory,
  });

  final String senderId;
  final String recipientId;
  final String artifactDirectory;

  static _Arguments parse(List<String> args) {
    String? sender;
    String? recipient;
    String? artifactDirectory;
    for (var index = 0; index < args.length; index += 1) {
      final value = args[index];
      String takeValue() {
        if (index + 1 >= args.length) {
          throw ArgumentError('Missing value after $value');
        }
        index += 1;
        return args[index].trim();
      }

      switch (value) {
        case '--sender':
          sender = takeValue();
        case '--recipient':
          recipient = takeValue();
        case '--artifact-dir':
          artifactDirectory = takeValue();
        case '--help':
        case '-h':
          _printUsage();
          exit(0);
        default:
          throw ArgumentError('Unknown argument: $value');
      }
    }
    if (sender == null || sender.isEmpty) {
      throw ArgumentError('--sender <physical-android-id> is required');
    }
    if (recipient == null || recipient.isEmpty) {
      throw ArgumentError('--recipient <android-emulator-id> is required');
    }
    if (artifactDirectory == null || artifactDirectory.isEmpty) {
      throw ArgumentError('--artifact-dir <directory> is required');
    }
    return _Arguments(
      senderId: sender,
      recipientId: recipient,
      artifactDirectory: artifactDirectory,
    );
  }
}

class _SafeRunnerFailure implements Exception {
  const _SafeRunnerFailure(this.summary);

  final String summary;
}

class _DeviceTarget {
  const _DeviceTarget({
    required this.id,
    required this.platform,
    required this.emulator,
    required this.connectionInterface,
  });

  final String id;
  final String platform;
  final bool emulator;
  final String connectionInterface;

  String get kind => emulator ? 'emulator' : 'physical';
  bool get isAndroid => platform.startsWith('android');
}

class _OutputBudget {
  _OutputBudget(this.maximumBytes, this.onLimitExceeded);

  final int maximumBytes;
  final void Function() onLimitExceeded;
  int observedBytes = 0;
  bool limitExceeded = false;

  bool acceptByte() {
    if (observedBytes <= maximumBytes) {
      observedBytes += 1;
    }
    if (observedBytes > maximumBytes) {
      if (!limitExceeded) {
        limitExceeded = true;
        onLimitExceeded();
      }
      return false;
    }
    return true;
  }
}

class _BoundedCaptureResult {
  const _BoundedCaptureResult(this.bytes);

  final Uint8List bytes;
}

class _BoundedLineDrain {
  _BoundedLineDrain({
    required this.budget,
    required this.maximumLineBytes,
    required this.resourceErrors,
    required this.onLimitExceeded,
    required this.onLine,
  });

  final _OutputBudget budget;
  final int maximumLineBytes;
  final Set<String> resourceErrors;
  final void Function() onLimitExceeded;
  final void Function(String line) onLine;
  final BytesBuilder _line = BytesBuilder(copy: false);
  bool _discardCurrentLine = false;
  bool _hasCurrentLine = false;
  int lineCount = 0;

  Future<void> drain(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      for (final byte in chunk) {
        if (!budget.acceptByte()) {
          if (!_discardCurrentLine) {
            _line.takeBytes();
          }
          _discardCurrentLine = true;
          _hasCurrentLine = true;
          continue;
        }
        if (byte == 0x0a) {
          _finishLine();
          continue;
        }
        _hasCurrentLine = true;
        if (_discardCurrentLine) {
          continue;
        }
        if (_line.length >= maximumLineBytes) {
          resourceErrors.add('line_limit');
          _discardCurrentLine = true;
          _line.takeBytes();
          onLimitExceeded();
          continue;
        }
        _line.addByte(byte);
      }
    }
    if (_hasCurrentLine) {
      _finishLine();
    }
  }

  void _finishLine() {
    if (lineCount < budget.maximumBytes) {
      lineCount += 1;
    }
    final bytes = _line.takeBytes();
    if (!_discardCurrentLine) {
      final end = bytes.isNotEmpty && bytes.last == 0x0d
          ? bytes.length - 1
          : bytes.length;
      try {
        onLine(utf8.decode(bytes.sublist(0, end), allowMalformed: false));
      } on Object {
        resourceErrors.add('invalid_line');
      }
    }
    _discardCurrentLine = false;
    _hasCurrentLine = false;
  }
}

class _AdbObservation {
  int matches = 0;
  int deviceStateMatches = 0;
  int usbClassMatches = 0;
}

class _AdbSnapshot {
  const _AdbSnapshot({
    required this.senderMatches,
    required this.recipientMatches,
    required this.senderDeviceStateMatches,
    required this.recipientDeviceStateMatches,
    required this.senderUsbClassMatches,
  });

  final int senderMatches;
  final int recipientMatches;
  final int senderDeviceStateMatches;
  final int recipientDeviceStateMatches;
  final int senderUsbClassMatches;

  bool sameAs(_AdbSnapshot other) {
    return senderMatches == other.senderMatches &&
        recipientMatches == other.recipientMatches &&
        senderDeviceStateMatches == other.senderDeviceStateMatches &&
        recipientDeviceStateMatches == other.recipientDeviceStateMatches &&
        senderUsbClassMatches == other.senderUsbClassMatches;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run integration_test/scripts/'
    'run_direct_private_media_device_local_journey.dart '
    '--sender <physical-android-id> --recipient <android-emulator-id> '
    '--artifact-dir <directory>',
  );
}

void _log(String phase, String message) {
  stderr.writeln('[P234][$phase] $message');
}

Future<_BoundedCaptureResult> _captureBounded(
  Stream<List<int>> stream, {
  required _OutputBudget budget,
  required bool retain,
}) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    for (final byte in chunk) {
      if (budget.acceptByte() && retain) {
        bytes.addByte(byte);
      }
    }
  }
  return _BoundedCaptureResult(bytes.takeBytes());
}

Future<List<_DeviceTarget>> _loadDevices(Set<String> pinnedIds) async {
  final process = await Process.start('flutter', const <String>[
    'devices',
    '--machine',
    '--device-connection',
    'attached',
  ]);
  var terminationRequested = false;
  void terminateForLimit() {
    if (!terminationRequested) {
      terminationRequested = true;
      process.kill();
    }
  }

  final budget = _OutputBudget(
    _maximumDiscoveryOutputLength,
    terminateForLimit,
  );
  final stdoutCapture = _captureBounded(
    process.stdout,
    budget: budget,
    retain: true,
  );
  final stderrDrain = _captureBounded(
    process.stderr,
    budget: budget,
    retain: false,
  );
  final processExitCode = await process.exitCode;
  final captures = await Future.wait(<Future<_BoundedCaptureResult>>[
    stdoutCapture,
    stderrDrain,
  ]);
  if (budget.limitExceeded || processExitCode != 0) {
    throw StateError('bounded Flutter device discovery failed');
  }

  Object? decoded;
  try {
    decoded = jsonDecode(
      utf8.decode(captures.first.bytes, allowMalformed: false),
    );
  } on Object {
    throw StateError('Flutter device discovery payload was invalid');
  }
  if (decoded is! List) {
    throw StateError('flutter devices --machine returned a non-list payload');
  }
  final targets = <_DeviceTarget>[];
  for (final entry in decoded) {
    if (entry is! Map) {
      throw StateError('flutter devices returned a malformed device row');
    }
    final id = entry['id'];
    if (id is! String || !pinnedIds.contains(id)) {
      continue;
    }
    final connectionInterfaceValue = entry['connectionInterface'];
    // This command explicitly filters to Flutter's attached interface. Older
    // Flutter machine output omits the redundant field; newer output is still
    // retained and verified when present.
    final connectionInterface = connectionInterfaceValue == null
        ? 'attached'
        : connectionInterfaceValue is String
        ? connectionInterfaceValue
        : 'invalid';
    targets.add(
      _DeviceTarget(
        id: id,
        platform: entry['targetPlatform'] as String? ?? '',
        emulator: entry['emulator'] == true,
        connectionInterface: connectionInterface,
      ),
    );
  }
  return targets;
}

_DeviceTarget _requireTarget(
  List<_DeviceTarget> devices,
  String id, {
  required bool emulator,
  required String role,
}) {
  final matches = devices.where((device) => device.id == id).toList();
  if (matches.length != 1) {
    throw StateError('$role target $id is not exactly once in live discovery');
  }
  final target = matches.single;
  if (!target.isAndroid) {
    throw StateError('$role target ${target.id} is not Android');
  }
  if (target.emulator != emulator) {
    throw StateError(
      '$role target ${target.id} must be '
      '${emulator ? 'an emulator' : 'a physical device'}',
    );
  }
  if (target.connectionInterface != 'attached') {
    throw StateError('$role target is not attached');
  }
  return target;
}

void _requireSameTargetSnapshot(
  _DeviceTarget before,
  _DeviceTarget after, {
  required String role,
}) {
  if (after.id != before.id ||
      after.platform != before.platform ||
      after.emulator != before.emulator ||
      after.connectionInterface != before.connectionInterface) {
    throw StateError('$role target changed during the proof run');
  }
}

void _requirePinnedTargetIdShapes(String senderId, String recipientId) {
  final senderIdPattern = RegExp(r'^[A-Za-z0-9._-]{1,128}$');
  final normalizedSenderId = senderId.toLowerCase();
  if (!senderIdPattern.hasMatch(senderId) ||
      normalizedSenderId.contains('adb-tls-connect') ||
      senderId.contains(':') ||
      normalizedSenderId.startsWith('emulator-')) {
    throw ArgumentError('sender must use an attached Android device ID');
  }
  if (!RegExp(r'^emulator-[0-9]{1,10}$').hasMatch(recipientId)) {
    throw ArgumentError('recipient must use an explicit Android emulator ID');
  }
}

void _observeAdbLine(
  String line, {
  required String senderId,
  required String recipientId,
  required _AdbObservation sender,
  required _AdbObservation recipient,
}) {
  final trimmed = line.trim();
  final separator = RegExp(r'\s').firstMatch(trimmed)?.start;
  if (separator == null) {
    return;
  }
  final id = trimmed.substring(0, separator);
  final observation = id == senderId
      ? sender
      : id == recipientId
      ? recipient
      : null;
  if (observation == null) {
    return;
  }
  observation.matches += 1;
  final remainder = trimmed.substring(separator).trimLeft();
  final stateEnd = RegExp(r'\s').firstMatch(remainder)?.start;
  final state = stateEnd == null ? remainder : remainder.substring(0, stateEnd);
  if (state == 'device') {
    observation.deviceStateMatches += 1;
  }
  if (RegExp(r'(^|\s)usb:\S+').hasMatch(remainder)) {
    observation.usbClassMatches += 1;
  }
}

Future<_AdbSnapshot> _loadAdbSnapshot({
  required String senderId,
  required String recipientId,
}) async {
  final process = await Process.start('adb', const <String>['devices', '-l']);
  var terminationRequested = false;
  void terminateForLimit() {
    if (!terminationRequested) {
      terminationRequested = true;
      process.kill();
    }
  }

  final budget = _OutputBudget(_maximumAdbOutputLength, terminateForLimit);
  final resourceErrors = <String>{};
  final sender = _AdbObservation();
  final recipient = _AdbObservation();
  final stdoutDrain = _BoundedLineDrain(
    budget: budget,
    maximumLineBytes: _maximumRawOutputLineLength,
    resourceErrors: resourceErrors,
    onLimitExceeded: terminateForLimit,
    onLine: (line) {
      _observeAdbLine(
        line,
        senderId: senderId,
        recipientId: recipientId,
        sender: sender,
        recipient: recipient,
      );
    },
  ).drain(process.stdout);
  final stderrDrain = _BoundedLineDrain(
    budget: budget,
    maximumLineBytes: _maximumRawOutputLineLength,
    resourceErrors: resourceErrors,
    onLimitExceeded: terminateForLimit,
    onLine: (_) {},
  ).drain(process.stderr);
  final processExitCode = await process.exitCode;
  await Future.wait(<Future<void>>[stdoutDrain, stderrDrain]);
  if (budget.limitExceeded ||
      resourceErrors.isNotEmpty ||
      processExitCode != 0) {
    throw StateError('bounded adb discovery failed');
  }
  if (sender.matches != 1 ||
      sender.deviceStateMatches != 1 ||
      sender.usbClassMatches != 1 ||
      recipient.matches != 1 ||
      recipient.deviceStateMatches != 1) {
    throw StateError('pinned adb topology was not USB/device-ready');
  }
  return _AdbSnapshot(
    senderMatches: sender.matches,
    recipientMatches: recipient.matches,
    senderDeviceStateMatches: sender.deviceStateMatches,
    recipientDeviceStateMatches: recipient.deviceStateMatches,
    senderUsbClassMatches: sender.usbClassMatches,
  );
}

Future<bool> _pathExists(String path) async {
  return await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;
}

Future<void> _refuseExistingPath(File file, {required String label}) async {
  if (await _pathExists(file.path)) {
    throw StateError('refusing existing $label path: ${file.path}');
  }
}

void _scanRawOutput(String text, Set<int> findingCodes) {
  final normalized = text.toLowerCase();
  for (var index = 0; index < _forbiddenRawFragments.length; index += 1) {
    if (normalized.contains(_forbiddenRawFragments[index])) {
      findingCodes.add(index);
    }
  }
}

Future<void> _writeAndFlush(File file, List<int> bytes) async {
  final handle = await file.open(mode: FileMode.writeOnly);
  try {
    await handle.writeFrom(bytes);
    await handle.flush();
  } finally {
    await handle.close();
  }
}

Future<void> _publishArtifactWithoutClobber(
  File output,
  List<int> encodedArtifact,
) async {
  final temporary = File(
    '${output.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
  );
  var temporaryCreated = false;
  try {
    try {
      await temporary.create(exclusive: true);
      temporaryCreated = true;
    } on FileSystemException {
      if (await _pathExists(temporary.path)) {
        throw StateError('refusing existing temporary path: ${temporary.path}');
      }
      rethrow;
    }
    await _writeAndFlush(temporary, encodedArtifact);

    final stagedArtifact = await temporary.readAsBytes();
    if (stagedArtifact.length != encodedArtifact.length ||
        sha256.convert(stagedArtifact) != sha256.convert(encodedArtifact)) {
      throw StateError('temporary artifact verification failed');
    }

    // File.rename removes an existing destination. A same-directory POSIX hard
    // link publishes the fully flushed file atomically and fails if another
    // proof already owns the final path.
    await _refuseExistingPath(output, label: 'artifact');
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw UnsupportedError(
        'no-clobber proof publication requires a POSIX host',
      );
    }
    final linkArguments = <String>['--', temporary.path, output.path];
    final linkProcess = await Process.start('/bin/ln', linkArguments);
    var terminationRequested = false;
    void terminateForLimit() {
      if (!terminationRequested) {
        terminationRequested = true;
        linkProcess.kill();
      }
    }

    final linkBudget = _OutputBudget(
      _maximumPublicationOutputLength,
      terminateForLimit,
    );
    final linkStdoutDrain = _captureBounded(
      linkProcess.stdout,
      budget: linkBudget,
      retain: false,
    );
    final linkStderrDrain = _captureBounded(
      linkProcess.stderr,
      budget: linkBudget,
      retain: false,
    );
    final linkExitCode = await linkProcess.exitCode;
    await Future.wait(<Future<_BoundedCaptureResult>>[
      linkStdoutDrain,
      linkStderrDrain,
    ]);
    if (linkBudget.limitExceeded || linkExitCode != 0) {
      if (await _pathExists(output.path)) {
        throw StateError('refusing existing artifact path: ${output.path}');
      }
      throw StateError('atomic artifact publication failed');
    }

    final publishedArtifact = await output.readAsBytes();
    if (publishedArtifact.length != encodedArtifact.length ||
        sha256.convert(publishedArtifact) != sha256.convert(encodedArtifact)) {
      throw StateError(
        'published artifact verification failed; refusing to replace '
        '${output.path}',
      );
    }
  } finally {
    if (temporaryCreated && await _pathExists(temporary.path)) {
      await temporary.delete();
    }
  }
}

Future<Map<String, Object?>> _runRole(
  _DeviceTarget target, {
  required String role,
}) async {
  _log(
    role.toUpperCase(),
    'running fully automated harness on pinned ${target.kind} target',
  );
  final process = await Process.start('flutter', <String>[
    'test',
    'integration_test/direct_private_media_device_local_journey_harness.dart',
    '-d',
    target.id,
    '--dart-define=P234_ROLE=$role',
    '--dart-define=P234_DEVICE_ID=${target.id}',
  ]);
  var terminationRequested = false;
  void terminateForLimit() {
    if (!terminationRequested) {
      terminationRequested = true;
      process.kill();
    }
  }

  final budget = _OutputBudget(_maximumRoleOutputLength, terminateForLimit);
  final resourceErrors = <String>{};
  final markerErrors = <String>{};
  final rawLeakFindingCodes = <int>{};
  String? marker;
  var markerCount = 0;

  void processLine(String line) {
    final markerIndex = line.indexOf(_artifactMarker);
    if (markerIndex < 0) {
      _scanRawOutput(line, rawLeakFindingCodes);
      return;
    }

    markerCount += 1;
    _scanRawOutput(line.substring(0, markerIndex), rawLeakFindingCodes);
    final afterMarker = line.substring(markerIndex + _artifactMarker.length);
    if (afterMarker.contains(_artifactMarker)) {
      markerCount += 1;
      markerErrors.add('duplicate_marker_line');
      return;
    }
    final payloadStart = RegExp(r'\S').firstMatch(afterMarker)?.start;
    if (payloadStart == null) {
      markerErrors.add('empty_marker');
      return;
    }
    final payloadAndSuffix = afterMarker.substring(payloadStart);
    final suffixStart = RegExp(r'\s').firstMatch(payloadAndSuffix)?.start;
    final encoded = suffixStart == null
        ? payloadAndSuffix
        : payloadAndSuffix.substring(0, suffixStart);
    final suffix = suffixStart == null
        ? ''
        : payloadAndSuffix.substring(suffixStart);
    _scanRawOutput(suffix, rawLeakFindingCodes);
    if (encoded.length > _maximumEncodedArtifactLength) {
      markerErrors.add('marker_limit');
      return;
    }
    if (marker != null) {
      markerErrors.add('duplicate_marker');
      return;
    }
    marker = encoded;
  }

  final stdoutParser = _BoundedLineDrain(
    budget: budget,
    maximumLineBytes: _maximumRawOutputLineLength,
    resourceErrors: resourceErrors,
    onLimitExceeded: terminateForLimit,
    onLine: processLine,
  );
  final stderrParser = _BoundedLineDrain(
    budget: budget,
    maximumLineBytes: _maximumRawOutputLineLength,
    resourceErrors: resourceErrors,
    onLimitExceeded: terminateForLimit,
    onLine: processLine,
  );
  final stdoutDrain = stdoutParser.drain(process.stdout);
  final stderrDrain = stderrParser.drain(process.stderr);
  final processExitCode = await process.exitCode;
  await Future.wait(<Future<void>>[stdoutDrain, stderrDrain]);
  if (budget.limitExceeded || resourceErrors.isNotEmpty) {
    throw _SafeRunnerFailure(
      '$role harness output bounds failed '
      '(bytes=${budget.observedBytes}, '
      'lines=${stdoutParser.lineCount + stderrParser.lineCount}, '
      'errorKinds=${resourceErrors.length + (budget.limitExceeded ? 1 : 0)})',
    );
  }
  if (processExitCode != 0) {
    throw _SafeRunnerFailure(
      '$role harness exited unsuccessfully (code=$processExitCode)',
    );
  }
  if (rawLeakFindingCodes.isNotEmpty) {
    throw _SafeRunnerFailure(
      '$role harness raw-output leak scan failed '
      '(findingKinds=${rawLeakFindingCodes.length})',
    );
  }
  if (markerErrors.isNotEmpty) {
    throw _SafeRunnerFailure(
      '$role harness marker validation failed '
      '(markers=$markerCount, errorKinds=${markerErrors.length})',
    );
  }
  if (markerCount != 1 || marker == null) {
    throw _SafeRunnerFailure(
      '$role harness marker count failed (markers=$markerCount)',
    );
  }

  final encodedMarker = marker!;
  late final Map<String, Object?> artifact;
  try {
    final bytes = base64Url.decode(base64Url.normalize(encodedMarker));
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map) {
      throw const FormatException();
    }
    artifact = Map<String, Object?>.from(decoded);
  } on Object {
    throw _SafeRunnerFailure(
      '$role harness artifact decoding failed '
      '(encodedBytes=${encodedMarker.length})',
    );
  }
  if (artifact['role'] != role || artifact['deviceId'] != target.id) {
    throw _SafeRunnerFailure('$role harness artifact identity check failed');
  }
  if (artifact['observationSource'] != 'instrumented_app') {
    throw _SafeRunnerFailure('$role harness artifact source check failed');
  }
  _log(
    role.toUpperCase(),
    'instrumented artifact accepted '
    '(bytes=${budget.observedBytes}, '
    'lines=${stdoutParser.lineCount + stderrParser.lineCount})',
  );
  return artifact;
}

Future<void> main(List<String> args) async {
  try {
    final parsed = _Arguments.parse(args);
    if (parsed.senderId == parsed.recipientId) {
      throw ArgumentError('sender and recipient IDs must be distinct');
    }
    _requirePinnedTargetIdShapes(parsed.senderId, parsed.recipientId);

    final directory = Directory(parsed.artifactDirectory);
    await directory.create(recursive: true);
    final output = File(
      '${directory.path}${Platform.pathSeparator}'
      'plan234-direct-private-media-device-local-journey.json',
    );
    await _refuseExistingPath(output, label: 'artifact');

    final pinnedIds = <String>{parsed.senderId, parsed.recipientId};
    final devices = await _loadDevices(pinnedIds);
    final sender = _requireTarget(
      devices,
      parsed.senderId,
      emulator: false,
      role: 'sender',
    );
    final recipient = _requireTarget(
      devices,
      parsed.recipientId,
      emulator: true,
      role: 'recipient',
    );
    final adbBefore = await _loadAdbSnapshot(
      senderId: sender.id,
      recipientId: recipient.id,
    );

    final senderArtifact = await _runRole(sender, role: 'sender');
    final recipientArtifact = await _runRole(recipient, role: 'recipient');
    final devicesAfter = await _loadDevices(pinnedIds);
    final senderAfter = _requireTarget(
      devicesAfter,
      parsed.senderId,
      emulator: false,
      role: 'sender',
    );
    final recipientAfter = _requireTarget(
      devicesAfter,
      parsed.recipientId,
      emulator: true,
      role: 'recipient',
    );
    _requireSameTargetSnapshot(sender, senderAfter, role: 'sender');
    _requireSameTargetSnapshot(recipient, recipientAfter, role: 'recipient');
    final adbAfter = await _loadAdbSnapshot(
      senderId: senderAfter.id,
      recipientId: recipientAfter.id,
    );
    if (!adbBefore.sameAs(adbAfter)) {
      throw StateError('pinned adb topology changed during the proof run');
    }
    _log(
      'TOPOLOGY',
      'post-run Flutter and adb discovery retained the pinned USB topology',
    );
    final combined = <String, Object?>{
      'schema': 'plan234.direct-private-media-device-local-journey',
      'version': 1,
      'generatedBy': 'automated_instrumented_harness',
      'topology': <String, Object?>{
        'platform': 'android',
        'automation': 'fully_automated',
        'transportScope': 'device_local_app_layer',
        'senderDeviceId': sender.id,
        'senderDeviceKind': sender.kind,
        'recipientDeviceId': recipient.id,
        'recipientDeviceKind': recipient.kind,
      },
      'claims': <String, Object?>{
        'consumeReceipt': false,
        'accountWideConsumption': false,
        'relayAuthoritativeRevocation': false,
      },
      'sender': senderArtifact,
      'recipient': recipientArtifact,
    };

    final validation = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
      combined,
    );
    if (!validation.ok) {
      throw _SafeRunnerFailure(
        'combined artifact validation failed '
        '(topLevelFields=${combined.length})',
      );
    }

    final encodedArtifact = utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(combined)}\n',
    );
    await _publishArtifactWithoutClobber(output, encodedArtifact);
    final artifactSha256 = sha256.convert(encodedArtifact);
    _log(
      'PASS',
      'validated physical Android + emulator device-local journey; '
          'artifact published; sha256=$artifactSha256',
    );
  } on _SafeRunnerFailure catch (error) {
    _log('FAIL', error.summary);
    exitCode = 1;
  } on Object {
    _log('FAIL', 'runner failed; proof result unavailable');
    exitCode = 1;
  }
}
