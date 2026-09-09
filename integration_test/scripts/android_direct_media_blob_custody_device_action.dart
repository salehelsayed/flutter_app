import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_app/core/debug/android_direct_media_blob_custody_e2e_protocol.dart';

import '../support/android_app_state_guard.dart';
import '../support/android_direct_media_blob_custody_campaign_contract.dart';
import '_android_app_package.dart';

const String _configFile = 'intro_e2e_config.json';
const String _resultFile = 'intro_e2e_result.json';
const String _identityFile = 'intro_e2e_identity.json';

/// Runs the concrete two-Android action using the same private app-file/ADB
/// boundary as the existing one-to-one campaigns. It never builds an APK and
/// never supplies media bytes from the host.
Future<Map<String, Object?>> runAndroidDirectMediaBlobCustodyAdbDeviceAction(
  AndroidDirectMediaBlobCustodyCampaignContext context,
) async {
  final host = _AndroidDirectMediaBlobCustodyHost(
    context: context,
    packageName: resolveAndroidAppPackage(),
  );
  await host.verifyPrerequisites();
  return host.run();
}

final class _AndroidDirectMediaBlobCustodyHost {
  _AndroidDirectMediaBlobCustodyHost({
    required this.context,
    required this.packageName,
  });

  final AndroidDirectMediaBlobCustodyCampaignContext context;
  final String packageName;
  final Random _random = Random.secure();
  bool _mutated = false;

  Future<void> verifyPrerequisites() async {
    await _process(
      'adb',
      const <String>['version'],
      mutate: false,
      missingToolBlocker: 'missingDriver',
    );
    final devices = await _process('adb', const <String>[
      'devices',
      '-l',
    ], mutate: false);
    final states = <String, String>{};
    for (final line in '${devices.stdout}'.split('\n')) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length >= 2) states[fields.first] = fields[1];
    }
    for (final device in <String>[
      context.physicalDeviceId,
      context.emulatorDeviceId,
    ]) {
      if (states[device] != 'device') {
        throw AndroidDirectMediaBlobCustodyCampaignBlocked(
          'targetUnavailable',
          'Android target "$device" is not attached in device state.',
        );
      }
    }
    final physicalQemu = (await _adbShell(
      context.physicalDeviceId,
      const <String>['getprop', 'ro.kernel.qemu'],
      mutate: false,
    )).trim();
    final emulatorQemu = (await _adbShell(
      context.emulatorDeviceId,
      const <String>['getprop', 'ro.kernel.qemu'],
      mutate: false,
    )).trim();
    if (physicalQemu == '1' || emulatorQemu != '1') {
      throw AndroidDirectMediaBlobCustodyCampaignBlocked(
        'targetUnavailable',
        'Target ordering is invalid: ${context.physicalDeviceId} must be '
            'physical and ${context.emulatorDeviceId} must be an emulator.',
      );
    }
  }

  Future<Map<String, Object?>> run() async {
    final sender = _Party(
      role: androidDirectMediaBlobCustodySenderRole,
      deviceId: context.physicalDeviceId,
      username: 'SimsCustodySender',
    );
    final receiver = _Party(
      role: androidDirectMediaBlobCustodyReceiverRole,
      deviceId: context.emulatorDeviceId,
      username: 'SimsCustodyReceiver',
    );
    final runId = _token('custody');
    final messageId = _token('message');
    final attachmentId = _token('attachment');
    final senderNonce = _token('sender');
    final receiverNonce = _token('receiver');

    late final AndroidAppStateGuard stateGuard;
    try {
      stateGuard = await AndroidAppStateGuard.capture(
        devices: <String>[sender.deviceId, receiver.deviceId],
        packageName: packageName,
        backupLabel: 'direct-media-custody',
      );
    } on AndroidAppStateBlocked catch (error) {
      throw AndroidDirectMediaBlobCustodyCampaignBlocked(
        'environment',
        error.detail,
      );
    } on AndroidAppStateFailure catch (error) {
      throw StateError(error.detail);
    }

    try {
      await _installAndReset(sender, stateGuard);
      await _installAndReset(receiver, stateGuard);
      await _grantRecordAudio(sender);
      await _bootstrapIdentity(sender);
      await _bootstrapIdentity(receiver);
      await _exchangeContacts(sender, receiver);

      await _stageAction(
        receiver,
        _actionConfig(
          party: receiver,
          phase: androidDirectMediaBlobCustodyReceiverArmPhase,
          contactPeerId: sender.peerId!,
          runId: runId,
          nonce: receiverNonce,
          messageId: messageId,
          attachmentId: attachmentId,
        ),
      );
      await _launch(receiver);
      final receiverArmed = await _waitForEndpoint(
        receiver,
        phase: androidDirectMediaBlobCustodyReceiverArmPhase,
        status: 'armed',
        runId: runId,
        nonce: receiverNonce,
      );
      _requireIds(receiverArmed, messageId, attachmentId);
      final receiverPidWhileArmed = await _requiredPid(receiver);
      await _forceStop(receiver);
      await _waitForProcessAbsent(receiver);

      await _stageAction(
        sender,
        _actionConfig(
          party: sender,
          phase: androidDirectMediaBlobCustodySenderPreparePhase,
          contactPeerId: receiver.peerId!,
          runId: runId,
          nonce: senderNonce,
          messageId: messageId,
          attachmentId: attachmentId,
        ),
      );
      await _launch(sender);
      final senderStored = await _waitForEndpoint(
        sender,
        phase: androidDirectMediaBlobCustodySenderPreparePhase,
        status: 'blob_stored',
        runId: runId,
        nonce: senderNonce,
      );
      _requireIds(senderStored, messageId, attachmentId);
      final preparedHash = _requiredSha256(senderStored, 'ciphertextSha256');
      final senderPidBeforeRestart = await _requiredPid(sender);

      await _forceStop(sender);
      await _waitForProcessAbsent(sender);
      await _stageAction(
        sender,
        _actionConfig(
          party: sender,
          phase: androidDirectMediaBlobCustodySenderResumePhase,
          contactPeerId: receiver.peerId!,
          runId: runId,
          nonce: senderNonce,
          messageId: messageId,
          attachmentId: attachmentId,
          expectedCiphertextSha256: preparedHash,
        ),
      );
      await _start(sender);
      final senderPidAfterRestart = await _waitForNewPid(
        sender,
        previousPid: senderPidBeforeRestart,
      );
      final senderRestartObserved =
          senderPidAfterRestart != senderPidBeforeRestart;
      if (!senderRestartObserved) {
        throw StateError('sender process identity did not change');
      }
      final senderComplete = await _waitForEndpoint(
        sender,
        phase: androidDirectMediaBlobCustodySenderResumePhase,
        status: 'complete',
        runId: runId,
        nonce: senderNonce,
      );
      _requireIds(senderComplete, messageId, attachmentId);
      final protectedBeforeAck = await _fixtureProtectedCount(attachmentId);
      if (protectedBeforeAck != 1) {
        throw StateError(
          'fixture did not observe the exact protected blob before receiver ACK',
        );
      }

      // Keep the receiver offline until the restarted sender has committed the
      // expiry-bounded v108 envelope. Relaunching the still-staged arm request
      // then exercises production inbox drain and strict blob recovery.
      await _start(receiver);
      await _waitForNewPid(receiver, previousPid: receiverPidWhileArmed);
      final receiverComplete = await _waitForEndpoint(
        receiver,
        phase: androidDirectMediaBlobCustodyReceiverArmPhase,
        status: 'complete',
        runId: runId,
        nonce: receiverNonce,
      );
      _requireIds(receiverComplete, messageId, attachmentId);
      final protectedAfterAck = await _waitForFixtureProtectedCount(
        attachmentId,
        expected: 0,
      );
      final protectedAfterAckObservedAtMs = DateTime.now()
          .toUtc()
          .millisecondsSinceEpoch;

      final receiverPidBeforeRestart = await _requiredPid(receiver);
      await _forceStop(receiver);
      await _waitForProcessAbsent(receiver);
      await _stageAction(
        receiver,
        _actionConfig(
          party: receiver,
          phase: androidDirectMediaBlobCustodyReceiverReopenPhase,
          contactPeerId: sender.peerId!,
          runId: runId,
          nonce: receiverNonce,
          messageId: messageId,
          attachmentId: attachmentId,
          expectedCiphertextSha256: preparedHash,
        ),
      );
      await _start(receiver);
      final receiverPidAfterRestart = await _waitForNewPid(
        receiver,
        previousPid: receiverPidBeforeRestart,
      );
      if (receiverPidAfterRestart == receiverPidBeforeRestart) {
        throw StateError('receiver process identity did not change');
      }
      final receiverReopen = await _waitForEndpoint(
        receiver,
        phase: androidDirectMediaBlobCustodyReceiverReopenPhase,
        status: 'complete',
        runId: runId,
        nonce: receiverNonce,
      );
      _requireIds(receiverReopen, messageId, attachmentId);

      return _aggregate(
        senderStored: senderStored,
        senderComplete: senderComplete,
        receiverComplete: receiverComplete,
        receiverReopen: receiverReopen,
        protectedBeforeAck: protectedBeforeAck,
        protectedAfterAck: protectedAfterAck,
        protectedAfterAckObservedAtMs: protectedAfterAckObservedAtMs,
        senderRestartObserved: senderRestartObserved,
      );
    } on AndroidAppStateFailure catch (error) {
      throw StateError(error.detail);
    } finally {
      try {
        await stateGuard.restoreAll();
      } on AndroidAppStateFailure catch (error) {
        throw StateError(
          'Android app-state restoration failed: ${error.detail}',
        );
      }
    }
  }

  Map<String, Object?> _aggregate({
    required Map<String, Object?> senderStored,
    required Map<String, Object?> senderComplete,
    required Map<String, Object?> receiverComplete,
    required Map<String, Object?> receiverReopen,
    required int protectedBeforeAck,
    required int protectedAfterAck,
    required int protectedAfterAckObservedAtMs,
    required bool senderRestartObserved,
  }) {
    final preparedHash = _requiredSha256(senderStored, 'ciphertextSha256');
    final reopenedHash = _requiredSha256(senderComplete, 'ciphertextSha256');
    final receiverHash = _requiredSha256(receiverComplete, 'ciphertextSha256');
    final receiverReopenHash = _requiredSha256(
      receiverReopen,
      'ciphertextSha256',
    );
    final receiverPlaintextHash = _requiredSha256(
      receiverComplete,
      'plaintextSha256',
    );
    final receiverReopenPlaintextHash = _requiredSha256(
      receiverReopen,
      'plaintextSha256',
    );
    if (<String>{
          preparedHash,
          reopenedHash,
          receiverHash,
          receiverReopenHash,
        }.length !=
        1) {
      throw const FormatException(
        'Android endpoint ciphertext identities do not match',
      );
    }
    final attachmentCount = senderStored['attachmentCount'];
    final blobExpiry = senderComplete['blobExpiresAtMs'];
    final envelopeExpiry = senderComplete['envelopeExpiresAtMs'];
    final strictCommitmentVerified =
        senderStored['strictCommitmentVerified'] == true &&
        senderComplete['strictCommitmentVerified'] == true;
    final envelopeExpiryWithinBlobBound =
        blobExpiry is int &&
        blobExpiry > 0 &&
        envelopeExpiry is int &&
        envelopeExpiry > 0 &&
        envelopeExpiry <= blobExpiry;
    final receiverAckOwnerObserved =
        receiverComplete['ackSourcePinned'] == true;
    final receiverStrictLifecycleCompletionObserved =
        receiverComplete['strictLifecycleCompletionObserved'] == true;
    final relayProtectedAuthorityRetired =
        protectedBeforeAck == 1 && protectedAfterAck == 0;
    // The production bootstrap recovery owner can win the process-wide strict
    // single-flight before the debug action installs its callback. Attribute
    // source-pinned ACK only from the combined durable-local lifecycle receipt
    // and the fixture's exact protected 1 -> 0 observation while the sender's
    // persisted blob proof is still live. Expiry convergence cannot satisfy
    // this bound.
    final ackSourcePinned =
        (receiverAckOwnerObserved ||
            receiverStrictLifecycleCompletionObserved) &&
        relayProtectedAuthorityRetired &&
        blobExpiry is int &&
        blobExpiry > 0 &&
        protectedAfterAckObservedAtMs > 0 &&
        protectedAfterAckObservedAtMs < blobExpiry;
    final relayProtectedAbsentAfterAck = ackSourcePinned;
    final durableLocalCommit =
        receiverComplete['durableLocalCommit'] == true &&
        receiverReopen['durableLocalCommit'] == true &&
        receiverPlaintextHash == receiverReopenPlaintextHash;
    if (attachmentCount is! int ||
        attachmentCount <= 0 ||
        !senderRestartObserved ||
        !strictCommitmentVerified ||
        !envelopeExpiryWithinBlobBound ||
        !ackSourcePinned ||
        !relayProtectedAbsentAfterAck ||
        !durableLocalCommit) {
      throw const FormatException(
        'Android endpoint custody assertions are incomplete',
      );
    }
    return <String, Object?>{
      'schemaVersion': 1,
      'scenarioId': androidDirectMediaBlobCustodyE2EScenario,
      'senderRestartObserved': senderRestartObserved,
      'attachmentCount': attachmentCount,
      'preparedCiphertextSha256': preparedHash,
      'reopenedCiphertextSha256': reopenedHash,
      'receiverCiphertextSha256': receiverHash,
      'receiverReopenSha256': receiverReopenHash,
      'receiverPlaintextSha256': receiverPlaintextHash,
      'receiverReopenPlaintextSha256': receiverReopenPlaintextHash,
      'strictCommitmentVerified': strictCommitmentVerified,
      'envelopeExpiryWithinBlobBound': envelopeExpiryWithinBlobBound,
      'ackSourcePinned': ackSourcePinned,
      'relayProtectedAbsentAfterAck': relayProtectedAbsentAfterAck,
      'fixtureIdentitySha256': context.fixtureIdentitySha256,
    };
  }

  Future<int> _waitForFixtureProtectedCount(
    String attachmentId, {
    required int expected,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    var last = -1;
    while (DateTime.now().isBefore(deadline)) {
      last = await _fixtureProtectedCount(attachmentId);
      if (last == expected) return last;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(
      'fixture protected count remained $last; expected $expected',
    );
  }

  Future<int> _fixtureProtectedCount(String attachmentId) async {
    final base = Uri.parse(context.fixtureProbeUrl);
    final uri = base.replace(
      queryParameters: <String, String>{'attachmentId': attachmentId},
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          'fixture protected-state probe returned ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(body);
      final count = decoded is Map<String, dynamic>
          ? decoded['protectedMediaCountForId']
          : null;
      if (decoded is! Map<String, dynamic> ||
          decoded['schema'] != 'mknoon.plan347.direct-media-probe.v1' ||
          count is! int ||
          count < 0 ||
          count > 1) {
        throw const FormatException(
          'fixture protected-state probe returned an invalid payload',
        );
      }
      return count;
    } finally {
      client.close(force: true);
    }
  }

  Map<String, Object?> _actionConfig({
    required _Party party,
    required String phase,
    required String contactPeerId,
    required String runId,
    required String nonce,
    required String messageId,
    required String attachmentId,
    String? expectedCiphertextSha256,
  }) => <String, Object?>{
    'schema': androidDirectMediaBlobCustodyE2ERequestSchema,
    'transport_action': androidDirectMediaBlobCustodyE2EAction,
    'scenario': androidDirectMediaBlobCustodyE2EScenario,
    'buildProfile': androidDirectMediaBlobCustodyE2EBuildProfile,
    'role': party.role,
    'phase': phase,
    'stepId': androidDirectMediaBlobCustodyStepId(
      role: party.role,
      phase: phase,
      runId: runId,
    ),
    'runId': runId,
    'nonce': nonce,
    'contactPeerId': contactPeerId,
    'messageId': messageId,
    'attachmentId': attachmentId,
    'fixtureIdentitySha256': context.fixtureIdentitySha256,
    'timeoutMs': 220000,
    'expectedCiphertextSha256': ?expectedCiphertextSha256,
  };

  Future<void> _installAndReset(
    _Party party,
    AndroidAppStateGuard stateGuard,
  ) async {
    await stateGuard.prepareFreshInstall(
      device: party.deviceId,
      artifact: context.artifact,
    );
    await _writeAppFile(
      party,
      'auto_setup.json',
      jsonEncode(<String, Object?>{'username': party.username}),
    );
  }

  Future<void> _bootstrapIdentity(_Party party) async {
    await _launch(party);
    final raw = await _waitForAppFile(
      party,
      _identityFile,
      const Duration(minutes: 3),
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Identity export is not an object');
    }
    final qrPayload = decoded['qrPayload'];
    final mlKemPublicKey = decoded['mlKemPublicKey'];
    if (qrPayload is! String ||
        qrPayload.isEmpty ||
        mlKemPublicKey is! String ||
        mlKemPublicKey.isEmpty) {
      throw const FormatException(
        'Identity export lacks signed QR/ML-KEM material',
      );
    }
    final qr = jsonDecode(qrPayload);
    if (qr is! Map || qr['ns'] is! String) {
      throw const FormatException('Identity QR payload is invalid');
    }
    party
      ..qrPayload = qrPayload
      ..mlKemPublicKey = mlKemPublicKey
      ..peerId = qr['ns']! as String;
  }

  Future<void> _exchangeContacts(_Party sender, _Party receiver) async {
    await _stageContact(sender, receiver);
    await _stageContact(receiver, sender);
    await _launch(sender);
    await _launch(receiver);
    await Future.wait(<Future<void>>[
      _waitForGenericStep(sender, 'custody-contact-${sender.role}'),
      _waitForGenericStep(receiver, 'custody-contact-${receiver.role}'),
    ]);
  }

  Future<void> _stageContact(_Party owner, _Party contact) async {
    await _deleteAppFile(owner, _resultFile);
    await _writeAppFile(
      owner,
      _configFile,
      jsonEncode(<String, Object?>{
        'stepId': 'custody-contact-${owner.role}',
        'add_contacts': <Object?>[
          <String, Object?>{
            'qrPayload': contact.qrPayload,
            'mlKemPublicKey': contact.mlKemPublicKey,
          },
        ],
      }),
    );
  }

  Future<void> _waitForGenericStep(_Party party, String stepId) async {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      final raw = await _readAppFile(party, _resultFile);
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map && decoded['stepId'] == stepId) {
            if (decoded['status'] == 'failed' || decoded['success'] == false) {
              throw StateError('Contact bootstrap failed on ${party.deviceId}');
            }
            if (decoded['status'] == 'complete' && decoded['success'] == true) {
              return;
            }
          }
        } on FormatException {
          // Atomic file replacement may be between observations.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('Contact bootstrap timed out on ${party.deviceId}');
  }

  Future<void> _stageAction(_Party party, Map<String, Object?> config) async {
    await _deleteAppFile(party, _resultFile);
    await _writeAppFile(party, _configFile, jsonEncode(config));
  }

  Future<Map<String, Object?>> _waitForEndpoint(
    _Party party, {
    required String phase,
    required String status,
    required String runId,
    required String nonce,
  }) async {
    final deadline = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(deadline)) {
      final raw = await _readAppFile(party, _resultFile);
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final value = decoded.map<String, Object?>(
              (key, item) => MapEntry('$key', item),
            );
            final bound =
                value['schema'] ==
                    androidDirectMediaBlobCustodyE2EEndpointResultSchema &&
                value['scenario'] == androidDirectMediaBlobCustodyE2EScenario &&
                value['buildProfile'] ==
                    androidDirectMediaBlobCustodyE2EBuildProfile &&
                value['role'] == party.role &&
                value['phase'] == phase &&
                value['stepId'] ==
                    androidDirectMediaBlobCustodyStepId(
                      role: party.role,
                      phase: phase,
                      runId: runId,
                    ) &&
                value['runId'] == runId &&
                value['nonce'] == nonce &&
                value['fixtureIdentitySha256'] == context.fixtureIdentitySha256;
            if (bound &&
                (value['status'] == 'failed' || value['success'] == false)) {
              throw StateError(
                'Custody endpoint ${party.role}/$phase failed '
                '(${value['errorCode'] ?? 'unknown'}; '
                '${value['errorType'] ?? 'unknown'}).',
              );
            }
            if (bound &&
                value['status'] == status &&
                value['success'] == true) {
              return value;
            }
          }
        } on FormatException {
          // Atomic file replacement may be between observations.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw TimeoutException(
      'Custody endpoint ${party.role}/$phase did not reach $status on '
      '${party.deviceId}.',
    );
  }

  Future<void> _grantRecordAudio(_Party sender) => _adbShell(
    sender.deviceId,
    <String>['pm', 'grant', packageName, 'android.permission.RECORD_AUDIO'],
    mutate: true,
  ).then<void>((_) {});

  Future<void> _launch(_Party party) async {
    await _forceStop(party);
    await _start(party);
  }

  Future<void> _forceStop(_Party party) => _adbShell(party.deviceId, <String>[
    'am',
    'force-stop',
    packageName,
  ], mutate: true).then<void>((_) {});

  Future<void> _start(_Party party) => _adbShell(party.deviceId, <String>[
    'am',
    'start',
    '-W',
    '-n',
    '$packageName/com.mknoon.app.MainActivity',
  ], mutate: true).then<void>((_) {});

  Future<int> _requiredPid(_Party party) async {
    final value = await _pidOf(party);
    if (value == null) {
      throw StateError('No running app process on ${party.deviceId}');
    }
    return value;
  }

  Future<int?> _pidOf(_Party party) async {
    final result = await _process(
      'adb',
      <String>['-s', party.deviceId, 'shell', 'pidof', packageName],
      allowFailure: true,
      mutate: false,
    );
    if (result.exitCode != 0) return null;
    final first = '${result.stdout}'.trim().split(RegExp(r'\s+')).firstOrNull;
    return int.tryParse(first ?? '');
  }

  Future<void> _waitForProcessAbsent(_Party party) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      if (await _pidOf(party) == null) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('App process did not stop on ${party.deviceId}');
  }

  Future<int> _waitForNewPid(_Party party, {required int previousPid}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final current = await _pidOf(party);
      if (current != null && current != previousPid) return current;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(
      'A replacement app process did not start on ${party.deviceId}',
    );
  }

  Future<String> _waitForAppFile(
    _Party party,
    String name,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final value = await _readAppFile(party, name);
      if (value != null && value.trim().isNotEmpty) return value;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('$name timed out on ${party.deviceId}');
  }

  Future<String?> _readAppFile(_Party party, String name) async {
    final result = await _process(
      'adb',
      <String>[
        '-s',
        party.deviceId,
        'shell',
        'run-as',
        packageName,
        'cat',
        'app_flutter/$name',
      ],
      allowFailure: true,
      mutate: false,
    );
    if (result.exitCode != 0 || '${result.stdout}'.trim().isEmpty) return null;
    return '${result.stdout}';
  }

  Future<void> _deleteAppFile(_Party party, String name) async {
    await _process(
      'adb',
      <String>[
        '-s',
        party.deviceId,
        'shell',
        'run-as',
        packageName,
        'rm',
        '-f',
        'app_flutter/$name',
      ],
      allowFailure: true,
      mutate: true,
    );
  }

  Future<void> _writeAppFile(_Party party, String name, String content) async {
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final safeDevice = party.deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final temp = File(
      '${Directory.systemTemp.path}/sims-custody-$safeDevice-$safeName-$pid-'
      '${_random.nextInt(1 << 32)}',
    );
    final remote = '/data/local/tmp/sims-custody-$safeName-${_token('cfg')}';
    try {
      await temp.writeAsString(content, flush: true);
      await _process('adb', <String>[
        '-s',
        party.deviceId,
        'push',
        temp.path,
        remote,
      ], mutate: true);
      await _adbShell(party.deviceId, <String>[
        'run-as',
        packageName,
        'mkdir',
        '-p',
        'app_flutter',
      ], mutate: true);
      await _adbShell(party.deviceId, <String>[
        'run-as',
        packageName,
        'cp',
        remote,
        'app_flutter/$name',
      ], mutate: true);
    } finally {
      await _process(
        'adb',
        <String>['-s', party.deviceId, 'shell', 'rm', '-f', remote],
        allowFailure: true,
        mutate: true,
      );
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<String> _adbShell(
    String deviceId,
    List<String> command, {
    required bool mutate,
  }) async {
    final result = await _process('adb', <String>[
      '-s',
      deviceId,
      'shell',
      ...command,
    ], mutate: mutate);
    return '${result.stdout}';
  }

  Future<ProcessResult> _process(
    String executable,
    List<String> arguments, {
    bool allowFailure = false,
    required bool mutate,
    String missingToolBlocker = 'missingDriver',
  }) async {
    if (mutate) _mutated = true;
    late final ProcessResult result;
    try {
      result = await Process.run(executable, arguments, runInShell: false);
    } on ProcessException catch (error) {
      if (!_mutated) {
        throw AndroidDirectMediaBlobCustodyCampaignBlocked(
          missingToolBlocker,
          '$executable is unavailable: ${error.message}',
        );
      }
      throw StateError('$executable could not start: ${error.message}');
    }
    if (!allowFailure && result.exitCode != 0) {
      if (!_mutated) {
        throw AndroidDirectMediaBlobCustodyCampaignBlocked(
          'environment',
          '$executable ${arguments.take(3).join(' ')} failed.',
        );
      }
      throw StateError(
        '$executable ${arguments.take(3).join(' ')} failed after mutation.',
      );
    }
    return result;
  }

  String _token(String prefix) {
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    final suffix = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-$suffix';
  }
}

final class _Party {
  _Party({required this.role, required this.deviceId, required this.username});

  final String role;
  final String deviceId;
  final String username;
  String? peerId;
  String? qrPayload;
  String? mlKemPublicKey;
}

void _requireIds(
  Map<String, Object?> receipt,
  String messageId,
  String attachmentId,
) {
  if (receipt['messageId'] != messageId ||
      receipt['attachmentId'] != attachmentId) {
    throw const FormatException('Endpoint receipt tuple does not match');
  }
}

String _requiredSha256(Map<String, Object?> receipt, String key) {
  final value = receipt[key];
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('Endpoint receipt has invalid $key');
  }
  return value;
}
