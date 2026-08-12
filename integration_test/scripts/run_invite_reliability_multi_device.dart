#!/usr/bin/env dart
//
// Two-device relay orchestrator for the Review-08 invite-reliability scenario
// (slices C revoke, F decline-ack, D config-pull). Launches the SAME
// `group_multi_device_real_harness.dart` binary as the MD-004 proof (0 new
// build targets) in two roles on two sims:
//   - primary = Alice (admin / inviter)
//   - sibling = Bob   (invitee)
// They exchange real invite / decline-ack / revocation / config envelopes over
// the relay (storeInInbox + drainOfflineInbox) and coordinate via shared files.
// No Go CLI peer is needed — both ends are Dart stacks.
//
// Usage: dart integration_test/scripts/run_invite_reliability_multi_device.dart
//        [-d <primary>,<sibling>]
//        [--scenario invite_reliability]
//        [--scenario invite_send_latency --mode baseline|closure]
//        [--scenario direct_linked_device_addressing -d <accountB,linkedA>]
// Relay: defaults to the prod relay unless MKNOON_RELAY_ADDRESSES is set.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../_support/invite_reliability_runner_contract.dart';
import '_android_app_package.dart';

const _harnessPath = 'integration_test/group_multi_device_real_harness.dart';
const _defaultPrimaryDevice =
    '347FB118-10D0-40C8-A05B-B0C3BD6B8CCD'; // iPhone Air
const _defaultSiblingDevice =
    '5BA69F1C-B112-47BE-B1FF-8C1003728C8F'; // iPhone 17
const _defaultRelayAddresses =
    '/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
    ',/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
const _maximumSignalBytes = 8 * 1024 * 1024;
const _roleTerminationGracePeriod = Duration(seconds: 3);

bool _isIosDeviceId(String? deviceId) {
  if (deviceId == null) return false;
  return RegExp(
    r'^(?:[0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})$',
    caseSensitive: false,
  ).hasMatch(deviceId);
}

String _relayAddresses() {
  final env = Platform.environment['MKNOON_RELAY_ADDRESSES'];
  if (env != null && env.trim().isNotEmpty) return env.trim();
  return _defaultRelayAddresses;
}

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
}

void _pipeOutput(Stream<List<int>> stream, String tag, IOSink sink) {
  stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    _log(tag, line);
    try {
      sink.writeln(line);
    } on StateError {
      // Output may still flush after teardown closes logs.
    }
  });
}

Future<Process> _startRole({
  required String role,
  required String deviceId,
  required String targetSharedDir,
  required String runId,
  required String relayAddresses,
  required InviteReliabilityRunnerArguments options,
}) async {
  final args = <String>[
    if (_isIosDeviceId(deviceId)) ...<String>[
      'drive',
      '--driver=test_driver/integration_test.dart',
      '--target=$_harnessPath',
      '--publish-port',
      '--no-pub',
    ] else ...<String>['test', '--no-pub', _harnessPath],
    '--dart-define=E2E_SHARED_DIR=$targetSharedDir',
    '--dart-define=MD004_ROLE=$role',
    '--dart-define=MD004_RUN_ID=$runId',
    '--dart-define=MD004_SCENARIO=${options.scenario}',
    if (options.mode != null) '--dart-define=MD004_MODE=${options.mode}',
    // 360: the direct linked-device selector is passed to THIS scenario only.
    // `MKNOON_ENABLE_MULTI_DEVICE_SYNC` stays false — that flag gates the group
    // same-user convergence build, which Plan 360 neither implements nor
    // proves, and enabling it here would activate sibling-device admission and
    // group key continuity behind an unrelated proof.
    if (options.scenario == directLinkedDeviceAddressingScenario)
      '--dart-define=MKNOON_ENABLE_DIRECT_LINKED_DEVICES=true',
    // 362: ONLY the aggregate event+blob wave scenario compiles the full
    // linked-media authoring triple (plus device admission). Group
    // multi-device behavior stays off.
    if (options.scenario ==
        directLinkedDeviceEventBlobFanoutScenario) ...const [
      '--dart-define=MKNOON_ENABLE_DIRECT_LINKED_DEVICES=true',
      '--dart-define=MKNOON_ENABLE_DIRECT_LINKED_EVENT_FANOUT=true',
      '--dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true',
      '--dart-define=MKNOON_ENABLE_DIRECT_LINKED_MEDIA_FANOUT=true',
    ],
    '--dart-define=E2E_DB_NAME=${options.scenario}_${runId}_$role.db',
    '--dart-define=MKNOON_RELAY_ADDRESSES=$relayAddresses',
    '-d',
    deviceId,
  ];
  _log('ORCH', 'Launching $role: flutter ${args.join(' ')}');
  return Process.start('flutter', args);
}

Future<void> _terminateRole(Process process, String role) async {
  _log('ORCH', 'Peer failed; terminating surviving $role process');
  final processExit = process.exitCode;
  if (!process.kill()) {
    // The process can settle between the supervisor's observation and this
    // call. In that race there is no survivor left to terminate.
    return;
  }
  try {
    await processExit.timeout(_roleTerminationGracePeriod);
    return;
  } on TimeoutException {
    _log('ORCH', '$role did not stop after SIGTERM; escalating to SIGKILL');
  }

  process.kill(ProcessSignal.sigkill);
  await processExit.timeout(
    _roleTerminationGracePeriod,
    onTimeout: () => throw TimeoutException(
      'Timed out terminating surviving $role process',
      _roleTerminationGracePeriod,
    ),
  );
}

Future<void> _waitForFile(File file, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw TimeoutException('Timed out waiting for ${file.path}');
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run integration_test/scripts/'
    'run_invite_reliability_multi_device.dart '
    '[--scenario invite_reliability] [-d <primary,sibling>]',
  );
  stdout.writeln(
    '       dart run integration_test/scripts/'
    'run_invite_reliability_multi_device.dart '
    '--scenario invite_send_latency --mode baseline|closure '
    '-d <physical-android,android-emulator>',
  );
}

Future<List<InviteReliabilityDeviceTarget>> _discoverFlutterDevices() async {
  final result = await Process.run('flutter', const <String>[
    'devices',
    '--machine',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'flutter devices --machine failed: ${result.stderr.toString().trim()}',
    );
  }
  final decoded = jsonDecode(result.stdout.toString());
  if (decoded is! List) {
    throw const FormatException(
      'flutter devices --machine was not a JSON list',
    );
  }
  return decoded
      .map<InviteReliabilityDeviceTarget>((raw) {
        if (raw is! Map) {
          throw const FormatException('flutter device entry was not an object');
        }
        final device = Map<String, Object?>.from(raw);
        final id = device['id'];
        final targetPlatform = device['targetPlatform'];
        final emulator = device['emulator'];
        if (id is! String || targetPlatform is! String || emulator is! bool) {
          throw const FormatException(
            'flutter device entry lacked id, targetPlatform, or emulator',
          );
        }
        return InviteReliabilityDeviceTarget(
          id: id,
          targetPlatform: targetPlatform,
          isEmulator: emulator,
        );
      })
      .toList(growable: false);
}

Future<Set<String>> _discoverAdbDeviceIds() async {
  final result = await Process.run('adb', const <String>['devices', '-l']);
  if (result.exitCode != 0) {
    throw StateError('adb devices -l failed: ${result.stderr}');
  }
  return result.stdout
      .toString()
      .split('\n')
      .skip(1)
      .map((line) => line.trim().split(RegExp(r'\s+')))
      .where((parts) => parts.length >= 2 && parts[1] == 'device')
      .map((parts) => parts.first)
      .toSet();
}

Future<void> _preflightLatencyTargets(List<String> selectedDeviceIds) async {
  final results = await Future.wait<Object>(<Future<Object>>[
    _discoverFlutterDevices(),
    _discoverAdbDeviceIds(),
  ]);
  final flutterDevices = results[0] as List<InviteReliabilityDeviceTarget>;
  final adbDeviceIds = results[1] as Set<String>;
  final missingFromAdb = selectedDeviceIds
      .where((deviceId) => !adbDeviceIds.contains(deviceId))
      .toList(growable: false);
  if (missingFromAdb.isNotEmpty) {
    throw StateError(
      'N/A (target unavailable by project policy): adb does not report '
      '${missingFromAdb.join(', ')}',
    );
  }
  final topologyError = validateInviteSendLatencyTopology(
    selectedDeviceIds: selectedDeviceIds,
    liveDevices: flutterDevices,
  );
  if (topologyError != null) {
    throw StateError(
      'N/A (target unavailable by project policy): $topologyError',
    );
  }
}

Future<bool> _isLiveAdbDevice(String deviceId) async {
  final result = await Process.run('adb', <String>[
    '-s',
    deviceId,
    'get-state',
  ]);
  return result.exitCode == 0 && result.stdout.toString().trim() == 'device';
}

Future<bool> _usesAndroidSignalTransport(List<String> deviceIds) async {
  if (deviceIds.every(_isIosDeviceId)) return false;
  final states = await Future.wait<bool>(deviceIds.map(_isLiveAdbDevice));
  if (states[0] != states[1]) {
    throw StateError(
      'Mixed Android/non-Android targets cannot share signal files. Select '
      'two Android targets or two iOS targets.',
    );
  }
  return states.every((state) => state);
}

Future<Map<String, Object?>> _readJsonArtifact(File file) async {
  await _waitForFile(file, const Duration(seconds: 15));
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
    throw FormatException('Artifact was not a JSON object: ${file.path}');
  }
  return Map<String, Object?>.from(decoded);
}

Future<String> _gitStdout(List<String> arguments) async {
  final result = await Process.run('git', arguments);
  if (result.exitCode != 0) {
    throw StateError(
      'git ${arguments.join(' ')} failed: ${result.stderr.toString().trim()}',
    );
  }
  final value = result.stdout.toString().trim();
  if (value.isEmpty) {
    throw StateError('git ${arguments.join(' ')} returned no output');
  }
  return value;
}

Future<List<int>> _gitBinaryOutput(List<String> arguments) async {
  final result = await Process.run('git', arguments, stdoutEncoding: null);
  if (result.exitCode != 0 || result.stdout is! List<int>) {
    throw StateError(
      'git ${arguments.join(' ')} failed: ${result.stderr.toString().trim()}',
    );
  }
  return result.stdout as List<int>;
}

Future<String> _sourceFingerprintSha256() async {
  final unstagedDiff = await _gitBinaryOutput(const <String>[
    'diff',
    '--no-ext-diff',
    '--binary',
  ]);
  final stagedDiff = await _gitBinaryOutput(const <String>[
    'diff',
    '--cached',
    '--no-ext-diff',
    '--binary',
  ]);
  final untrackedResult = await Process.run('git', const <String>[
    'ls-files',
    '--others',
    '--exclude-standard',
    '-z',
  ]);
  if (untrackedResult.exitCode != 0) {
    throw StateError('git ls-files for untracked sources failed');
  }
  final untrackedPaths =
      untrackedResult.stdout
          .toString()
          .split('\x00')
          .where((path) => path.isNotEmpty)
          .toList()
        ..sort();
  final fingerprintBytes = <int>[];

  void addEntry(String label, List<int> bytes) {
    fingerprintBytes
      ..addAll(utf8.encode(label))
      ..add(0)
      ..addAll(utf8.encode(bytes.length.toString()))
      ..add(0)
      ..addAll(bytes)
      ..add(0);
  }

  addEntry('unstaged-diff', unstagedDiff);
  addEntry('staged-diff', stagedDiff);
  for (final path in untrackedPaths) {
    final file = File(path);
    if (file.existsSync()) {
      addEntry('untracked:$path', await file.readAsBytes());
    }
  }
  return sha256.convert(fingerprintBytes).toString();
}

Future<InviteSendLatencyProvenance> _captureProvenance(
  String relayAddresses,
) async {
  final appRevision = await _gitStdout(const <String>['rev-parse', 'HEAD']);
  final nativeRevision = await _gitStdout(const <String>[
    '-C',
    'go-mknoon',
    'rev-parse',
    'HEAD',
  ]);
  final status = await Process.run('git', const <String>[
    'status',
    '--porcelain',
  ]);
  if (status.exitCode != 0) {
    throw StateError('git status --porcelain failed: ${status.stderr}');
  }
  final normalizedRelays = relayAddresses
      .split(',')
      .map((address) => address.trim())
      .where((address) => address.isNotEmpty)
      .toList(growable: false);
  return InviteSendLatencyProvenance(
    appGitRevision: appRevision,
    appGitDirty: status.stdout.toString().trim().isNotEmpty,
    appSourceFingerprintSha256: await _sourceFingerprintSha256(),
    nativeGitRevision: nativeRevision,
    relayAddressCount: normalizedRelays.length,
    relayAddressesSha256: sha256
        .convert(utf8.encode(normalizedRelays.join(',')))
        .toString(),
  );
}

void _requireStableProvenance(
  InviteSendLatencyProvenance before,
  InviteSendLatencyProvenance after,
) {
  if (before.appGitRevision != after.appGitRevision ||
      before.appGitDirty != after.appGitDirty ||
      before.appSourceFingerprintSha256 != after.appSourceFingerprintSha256 ||
      before.nativeGitRevision != after.nativeGitRevision ||
      before.relayAddressCount != after.relayAddressCount ||
      before.relayAddressesSha256 != after.relayAddressesSha256) {
    throw StateError(
      'Source or relay provenance changed while the latency harness was '
      'running; discard the artifacts and rerun from a stable worktree.',
    );
  }
}

Future<File> _validateAndWriteLatencySummary({
  required Directory sharedDir,
  required String runId,
  required String mode,
  required String relayAddresses,
  required InviteSendLatencyProvenance preflightProvenance,
}) async {
  final primaryFile = File(
    '${sharedDir.path}/${inviteSendLatencyArtifactFileName(runId, 'primary')}',
  );
  final siblingFile = File(
    '${sharedDir.path}/${inviteSendLatencyArtifactFileName(runId, 'sibling')}',
  );
  final primaryArtifact = await _readJsonArtifact(primaryFile);
  final siblingArtifact = await _readJsonArtifact(siblingFile);
  final validation = validateInviteSendLatencyArtifacts(
    primaryArtifact: primaryArtifact,
    siblingArtifact: siblingArtifact,
    expectedRunId: runId,
    expectedMode: mode,
  );
  if (!validation.ok) {
    throw StateError(
      'invite_send_latency artifacts rejected: ${validation.detail}',
    );
  }
  final primaryArtifactSha256 = sha256
      .convert(await primaryFile.readAsBytes())
      .toString();
  final siblingArtifactSha256 = sha256
      .convert(await siblingFile.readAsBytes())
      .toString();
  final captureReceipt = await _readJsonArtifact(
    File(
      '${sharedDir.path}/'
      '${inviteSendLatencyHostCaptureReceiptFileName(runId)}',
    ),
  );
  for (final entry in <String, String>{
    'primary': primaryArtifactSha256,
    'sibling': siblingArtifactSha256,
  }.entries) {
    final receiptValidation =
        validateInviteSendLatencyHostCaptureReceiptForRole(
          receipt: captureReceipt,
          expectedRunId: runId,
          expectedMode: mode,
          role: entry.key,
          expectedOwnArtifactSha256: entry.value,
        );
    if (!receiptValidation.ok) {
      throw StateError(
        'invite_send_latency host capture receipt rejected for ${entry.key}: '
        '${receiptValidation.detail}',
      );
    }
  }
  final postflightProvenance = await _captureProvenance(relayAddresses);
  _requireStableProvenance(preflightProvenance, postflightProvenance);

  final summary = buildInviteSendLatencyHostSummary(
    primaryArtifact: primaryArtifact,
    siblingArtifact: siblingArtifact,
    expectedRunId: runId,
    expectedMode: mode,
    primaryArtifactPath: primaryFile.absolute.path,
    primaryArtifactSha256: primaryArtifactSha256,
    siblingArtifactPath: siblingFile.absolute.path,
    siblingArtifactSha256: siblingArtifactSha256,
    provenance: preflightProvenance,
  );
  final summaryValidation = validateInviteSendLatencyHostSummary(
    summary: summary,
    expectedRunId: runId,
    expectedMode: mode,
    expectedPrimaryArtifactPath: primaryFile.absolute.path,
    expectedPrimaryArtifactSha256: primaryArtifactSha256,
    expectedSiblingArtifactPath: siblingFile.absolute.path,
    expectedSiblingArtifactSha256: siblingArtifactSha256,
  );
  if (!summaryValidation.ok) {
    throw StateError(
      'invite_send_latency host summary rejected: ${summaryValidation.detail}',
    );
  }
  final summaryFile = File(
    '${sharedDir.path}/${inviteSendLatencyHostSummaryFileName(runId)}',
  );
  final pending = File('${summaryFile.path}.pending');
  await pending.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary),
    flush: true,
  );
  await pending.rename(summaryFile.path);
  final persistedValidation = validateInviteSendLatencyHostSummary(
    summary: jsonDecode(await summaryFile.readAsString()),
    expectedRunId: runId,
    expectedMode: mode,
    expectedPrimaryArtifactPath: primaryFile.absolute.path,
    expectedPrimaryArtifactSha256: primaryArtifactSha256,
    expectedSiblingArtifactPath: siblingFile.absolute.path,
    expectedSiblingArtifactSha256: siblingArtifactSha256,
  );
  if (!persistedValidation.ok) {
    throw StateError(
      'persisted invite_send_latency host summary rejected: '
      '${persistedValidation.detail}',
    );
  }
  return summaryFile;
}

final class _AndroidSignalBroker {
  _AndroidSignalBroker({
    required this.deviceIds,
    required this.hostDir,
    required this.runId,
    required this.appPackage,
    required String? inviteSendLatencyMode,
  }) : remoteDirRelative = 'cache/invite_reliability_$runId',
       remoteDirAbsolute =
           '/data/user/0/$appPackage/cache/invite_reliability_$runId',
       _latencyCaptureBarrier = inviteSendLatencyMode == null
           ? null
           : InviteSendLatencyHostCaptureBarrier(
               runId: runId,
               mode: inviteSendLatencyMode,
             );

  final List<String> deviceIds;
  final Directory hostDir;
  final String runId;
  final String appPackage;
  final String remoteDirRelative;
  final String remoteDirAbsolute;
  final InviteSendLatencyHostCaptureBarrier? _latencyCaptureBarrier;
  bool _stopRequested = false;
  bool _captureReceiptLogged = false;

  void stop() => _stopRequested = true;

  Future<ProcessResult> _adb(
    String deviceId,
    List<String> arguments, {
    Encoding? stdoutEncoding = utf8,
  }) => Process.run('adb', <String>[
    '-s',
    deviceId,
    ...arguments,
  ], stdoutEncoding: stdoutEncoding);

  Future<Set<String>> _listDeviceFiles(String deviceId) async {
    final result = await _adb(deviceId, <String>[
      'shell',
      'run-as',
      appPackage,
      'ls',
      '-1',
      remoteDirRelative,
    ]);
    if (result.exitCode != 0) return <String>{};
    final prefix = 'md004_${runId}_';
    final safeName = RegExp(r'^[A-Za-z0-9_.-]+$');
    return result.stdout
        .toString()
        .split('\n')
        .map((name) => name.trim())
        .where((name) => name.startsWith(prefix) && safeName.hasMatch(name))
        .toSet();
  }

  Future<List<int>?> _readDeviceFile(String deviceId, String name) async {
    final result = await _adb(deviceId, <String>[
      'exec-out',
      'run-as',
      appPackage,
      'cat',
      '$remoteDirRelative/$name',
    ], stdoutEncoding: null);
    if (result.exitCode != 0 || result.stdout is! List<int>) return null;
    final bytes = result.stdout as List<int>;
    if (bytes.length > _maximumSignalBytes) {
      throw StateError('$name exceeds $_maximumSignalBytes bytes');
    }
    return bytes;
  }

  bool _isLatencyRoleArtifact(String name) =>
      name == inviteSendLatencyArtifactFileName(runId, 'primary') ||
      name == inviteSendLatencyArtifactFileName(runId, 'sibling');

  bool _isLatencyHostCaptureReceipt(String name) =>
      name == inviteSendLatencyHostCaptureReceiptFileName(runId);

  String? _ownedLatencyRole(String deviceId, String name) {
    if (_latencyCaptureBarrier == null) return null;
    if (deviceId == deviceIds[0] &&
        name == inviteSendLatencyArtifactFileName(runId, 'primary')) {
      return 'primary';
    }
    if (deviceId == deviceIds[1] &&
        name == inviteSendLatencyArtifactFileName(runId, 'sibling')) {
      return 'sibling';
    }
    return null;
  }

  Future<String?> _pull(
    String deviceId,
    String name, {
    bool requireStableDeviceRead = false,
  }) async {
    final destination = File('${hostDir.path}/$name');
    if (destination.existsSync() && !requireStableDeviceRead) return null;
    final first = await _readDeviceFile(deviceId, name);
    if (first == null) return null;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final second = await _readDeviceFile(deviceId, name);
    if (second == null || base64Encode(first) != base64Encode(second)) {
      return null;
    }
    if (destination.existsSync()) {
      if (base64Encode(await destination.readAsBytes()) !=
          base64Encode(second)) {
        throw StateError('$name conflicts with the host-captured bytes');
      }
    } else {
      final safeDeviceId = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final pending = File('${destination.path}.$safeDeviceId.pending');
      await pending.writeAsBytes(second, flush: true);
      if (destination.existsSync()) {
        await pending.delete();
        if (base64Encode(await destination.readAsBytes()) !=
            base64Encode(second)) {
          throw StateError('$name raced with conflicting host bytes');
        }
      } else {
        await pending.rename(destination.path);
      }
    }
    return sha256.convert(second).toString();
  }

  Future<bool> _push(String deviceId, File source) async {
    final name = source.uri.pathSegments.last;
    final remotePending = '$remoteDirRelative/.$name.host_pending';
    final process = await Process.start('adb', <String>[
      '-s',
      deviceId,
      'shell',
      'run-as',
      appPackage,
      'tee',
      remotePending,
    ]);
    final stdoutDone = process.stdout.drain<void>();
    final stderrDone = process.stderr.drain<void>();
    process.stdin.add(await source.readAsBytes());
    await process.stdin.close();
    final exitCode = await process.exitCode;
    await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
    if (exitCode != 0) return false;
    final promote = await _adb(deviceId, <String>[
      'shell',
      'run-as',
      appPackage,
      'mv',
      remotePending,
      '$remoteDirRelative/$name',
    ]);
    return promote.exitCode == 0;
  }

  Future<bool> _deviceFileMatches(String deviceId, File source) async {
    final name = source.uri.pathSegments.last;
    final deviceBytes = await _readDeviceFile(deviceId, name);
    if (deviceBytes == null) return false;
    return base64Encode(deviceBytes) ==
        base64Encode(await source.readAsBytes());
  }

  Future<void> run() async {
    final prefix = 'md004_${runId}_';
    while (!_stopRequested) {
      try {
        final filesByDevice = <String, Set<String>>{};
        for (final deviceId in deviceIds) {
          final files = await _listDeviceFiles(deviceId);
          filesByDevice[deviceId] = files;
          for (final name in files) {
            if (_latencyCaptureBarrier != null &&
                _isLatencyHostCaptureReceipt(name)) {
              // The receipt has exactly one authority: this host broker.
              // Never import a device-origin file into that namespace.
              continue;
            }
            final ownedRole = _ownedLatencyRole(deviceId, name);
            if (_isLatencyRoleArtifact(name) && ownedRole == null) {
              // Final evidence is sink-only. Never let a peer-side replica be
              // mistaken for capture from the artifact's designated owner.
              continue;
            }
            final digest = await _pull(
              deviceId,
              name,
              requireStableDeviceRead: ownedRole != null,
            );
            if (ownedRole != null && digest != null) {
              _latencyCaptureBarrier!.recordStableRoleArtifact(
                role: ownedRole,
                artifactSha256: digest,
              );
            }
          }
        }

        final captureReceipt = _latencyCaptureBarrier?.receipt;
        if (captureReceipt != null) {
          final receiptFile =
              await persistInviteSendLatencyHostCaptureReceiptAtomically(
                directory: hostDir,
                receipt: captureReceipt,
              );
          if (!_captureReceiptLogged) {
            _captureReceiptLogged = true;
            _log(
              'SYNC',
              'Host stably captured both latency role artifacts; receipt='
                  '${receiptFile.path}',
            );
          }
        }

        final hostFiles = hostDir
            .listSync()
            .whereType<File>()
            .where((file) => file.uri.pathSegments.last.startsWith(prefix))
            .toList(growable: false);
        for (final deviceId in deviceIds) {
          final deviceFiles = filesByDevice[deviceId] ?? <String>{};
          for (final hostFile in hostFiles) {
            final name = hostFile.uri.pathSegments.last;
            if (_latencyCaptureBarrier != null &&
                _isLatencyRoleArtifact(name)) {
              continue;
            }
            final exactReceiptAlreadyPresent =
                _isLatencyHostCaptureReceipt(name) &&
                deviceFiles.contains(name) &&
                await _deviceFileMatches(deviceId, hostFile);
            if ((!deviceFiles.contains(name) ||
                    (_isLatencyHostCaptureReceipt(name) &&
                        !exactReceiptAlreadyPresent)) &&
                await _push(deviceId, hostFile)) {
              deviceFiles.add(name);
            }
          }
        }
      } catch (error) {
        _log('SYNC', 'Android signal synchronization retry: $error');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}

Future<void> main(List<String> args) async {
  late final InviteReliabilityRunnerArguments options;
  try {
    options = InviteReliabilityRunnerArguments.parse(
      args,
      defaultDeviceIds: const <String>[
        _defaultPrimaryDevice,
        _defaultSiblingDevice,
      ],
    );
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    _printUsage();
    exitCode = 64;
    return;
  }
  if (options.helpRequested) {
    _printUsage();
    return;
  }
  final devices = options.deviceIds;
  if (options.isLatencyScenario) {
    await _preflightLatencyTargets(devices);
  }
  final androidPair = await _usesAndroidSignalTransport(devices);
  final primaryDevice = devices[0];
  final siblingDevice = devices[1];
  final runId = DateTime.now().millisecondsSinceEpoch.toString();
  final relayAddresses = _relayAddresses();
  final preflightProvenance = options.isLatencyScenario
      ? await _captureProvenance(relayAddresses)
      : null;
  final sharedDir = await Directory.systemTemp.createTemp(
    'invite_reliability_multi_device_',
  );
  final primaryLog = File(
    '${sharedDir.path}/primary.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);
  final siblingLog = File(
    '${sharedDir.path}/sibling.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);
  final broker = androidPair
      ? _AndroidSignalBroker(
          deviceIds: devices,
          hostDir: sharedDir,
          runId: runId,
          appPackage: resolveAndroidAppPackage(),
          inviteSendLatencyMode: options.isLatencyScenario
              ? options.mode
              : null,
        )
      : null;
  final signalSync = broker?.run();
  final targetSharedDir = broker?.remoteDirAbsolute ?? sharedDir.path;

  _log(
    'ORCH',
    'invite-reliability shared dir: ${sharedDir.path}; '
        'primary=$primaryDevice sibling=$siblingDevice '
        'scenario=${options.scenario} mode=${options.mode ?? 'legacy'}',
  );
  if (broker != null) {
    _log(
      'ORCH',
      'Android target-local signal dir: ${broker.remoteDirAbsolute}; '
          'host-mediated synchronization enabled',
    );
  }
  _log('ORCH', 'Relay: $relayAddresses');

  Process? primary;
  Process? sibling;
  try {
    // Launch primary first; wait until it has built + is running (it writes
    // alice_identity.json once its stack is up) before launching the sibling,
    // so the two flutter builds don't contend on the global startup lock.
    primary = await _startRole(
      role: 'primary',
      deviceId: primaryDevice,
      targetSharedDir: targetSharedDir,
      runId: runId,
      relayAddresses: relayAddresses,
      options: options,
    );
    _pipeOutput(primary.stdout, 'PRIMARY', primaryLog);
    _pipeOutput(primary.stderr, 'PRIMARY-ERR', primaryLog);

    _log('ORCH', 'Waiting for primary to build + come online...');
    final primaryReadyName = options.isLatencyScenario
        ? 'latency_alice_identity.json'
        : 'alice_identity.json';
    final primaryReadyFile = File(
      '${sharedDir.path}/md004_${runId}_$primaryReadyName',
    );
    sibling = await launchInviteReliabilitySiblingWhenPrimaryReady<Process>(
      isPrimaryReady: primaryReadyFile.existsSync,
      primaryExitCode: primary.exitCode,
      timeout: const Duration(minutes: 12),
      pollInterval: const Duration(seconds: 1),
      readinessDescription: primaryReadyFile.path,
      launchSibling: () {
        _log('ORCH', 'Primary online; launching sibling');
        return _startRole(
          role: 'sibling',
          deviceId: siblingDevice,
          targetSharedDir: targetSharedDir,
          runId: runId,
          relayAddresses: relayAddresses,
          options: options,
        );
      },
    );
    _pipeOutput(sibling.stdout, 'SIBLING', siblingLog);
    _pipeOutput(sibling.stderr, 'SIBLING-ERR', siblingLog);

    final roleExits = await superviseInviteReliabilityRoleExits(
      primaryExitCode: primary.exitCode,
      siblingExitCode: sibling.exitCode,
      terminatePrimary: () => _terminateRole(primary!, 'primary'),
      terminateSibling: () => _terminateRole(sibling!, 'sibling'),
    );
    final primaryExit = roleExits.primary;
    final siblingExit = roleExits.sibling;
    _log('ORCH', 'primaryExit=$primaryExit siblingExit=$siblingExit');
    _log('ORCH', 'Primary log: ${sharedDir.path}/primary.log');
    _log('ORCH', 'Sibling log: ${sharedDir.path}/sibling.log');
    if (primaryExit != 0 || siblingExit != 0) {
      throw StateError(
        'invite-reliability harness failure: primary=$primaryExit '
        'sibling=$siblingExit sharedDir=${sharedDir.path}',
      );
    }
    if (options.isLatencyScenario) {
      final summaryFile = await _validateAndWriteLatencySummary(
        sharedDir: sharedDir,
        runId: runId,
        mode: options.mode!,
        relayAddresses: relayAddresses,
        preflightProvenance: preflightProvenance!,
      );
      _log('ORCH', 'Validated latency host summary: ${summaryFile.path}');
    }
    _log('ORCH', 'invite-reliability two-device proof completed successfully');
  } finally {
    try {
      primary?.kill();
    } catch (_) {}
    try {
      sibling?.kill();
    } catch (_) {}
    broker?.stop();
    if (signalSync != null) {
      await signalSync;
    }
    await primaryLog.close();
    await siblingLog.close();
  }
}
