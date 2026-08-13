import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String inviteSendLatencyArtifactSchema =
    'mknoon.tc267.invite-send-latency';
const int inviteSendLatencyArtifactSchemaVersion = 2;
const String inviteSendLatencyHostSummarySchema =
    'mknoon.tc267.invite-send-latency-host-summary';
const int inviteSendLatencyHostSummarySchemaVersion = 2;
const String inviteSendLatencyHostCaptureReceiptSchema =
    'mknoon.tc267.invite-send-latency-host-capture-receipt';
const int inviteSendLatencyHostCaptureReceiptSchemaVersion = 1;
const int inviteSendLatencyObservationWindowVersion = 1;
const int inviteSendLatencyObservationWindowMs = 30000;
const String inviteReliabilityScenario = 'invite_reliability';
const String inviteSendLatencyScenario = 'invite_send_latency';

/// 360 / TC-360-04a: the registered Android linked-device addressing scenario.
///
/// Availability-bounded two-target pair. Target B is account A's linked
/// SECONDARY; target A is a different account that already stores A's logical
/// account as a legacy contact fixture. The real primary account-A device does
/// not need to run.
const String directLinkedDeviceAddressingScenario =
    'direct_linked_device_addressing';

/// 362 / TC-362-05b: the aggregate Plan-360/361/362 event+blob wave scenario.
///
/// Two live Androids in PHYSICAL-first, EMULATOR-second order: the physical
/// device runs account A's linked secondary, the emulator runs upgraded
/// account B whose exact persisted targets are live legacy-primary B plus one
/// inert offline linked-B identity fixture. One blob-free event and one tiny
/// image prove outer A-transport != inner A-account, two B target envelopes
/// sharing one blob ID/hash, emulator decrypt/apply/download/ACK, receipt to
/// the physical A transport, and byte-exact offline linked-B siblings.
const String directLinkedDeviceEventBlobFanoutScenario =
    'direct_linked_device_event_blob_fanout';

const String directLinkedDeviceEventBlobFanoutArtifactSchema =
    'mknoon.tc362.direct-linked-device-event-blob-fanout';
const int directLinkedDeviceEventBlobFanoutArtifactSchemaVersion = 1;
const String directLinkedDeviceEventBlobFanoutTargetFixtureSchema =
    'mknoon.tc362.direct-linked-device-event-blob-fanout-targets';
const int directLinkedDeviceEventBlobFanoutTargetFixtureSchemaVersion = 1;
const String directLinkedDeviceEventBlobFanoutHostSummarySchema =
    'mknoon.tc362.direct-linked-device-event-blob-fanout-host-summary';
const int directLinkedDeviceEventBlobFanoutHostSummarySchemaVersion = 1;

String directLinkedDeviceEventBlobFanoutArtifactFileName(
  String runId,
  String role,
) => 'md004_${runId}_direct_linked_device_event_blob_fanout_$role.json';

String directLinkedDeviceEventBlobFanoutTargetFixtureFileName(String runId) =>
    'md004_${runId}_direct_linked_device_event_blob_fanout_targets.json';

String directLinkedDeviceEventBlobFanoutHostSummaryFileName(String runId) =>
    'md004_${runId}_direct_linked_device_event_blob_fanout_host_summary.json';

final class DirectLinkedDeviceEventBlobFanoutValidation {
  DirectLinkedDeviceEventBlobFanoutValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;
  String get detail => ok ? 'accepted' : failures.join('; ');
}

const Set<String> _directFanoutCommonArtifactKeys = <String>{
  'schema',
  'schemaVersion',
  'scenario',
  'runId',
  'role',
  'fixtureIdentitySha256',
  'accountAPeerIdSha256',
  'accountATransportPeerIdSha256',
  'accountBPeerIdSha256',
  'offlineBTransportPeerIdSha256',
  'eventMessageIdSha256',
  'mediaMessageIdSha256',
  'attachmentIdSha256',
  'ciphertextSha256',
};

const Set<String> _directFanoutPrimaryArtifactKeys = <String>{
  ..._directFanoutCommonArtifactKeys,
  'legacyBMlKemPublicKeySha256',
  'offlineBMlKemPublicKeySha256',
  'eventLegacyEnvelopeSha256',
  'eventOfflineEnvelopeSha256',
  'mediaLegacyEnvelopeSha256',
  'mediaOfflineEnvelopeSha256',
  'transportDistinctFromAccount',
  'targetMlKemKeysDistinct',
  'eventTargetCount',
  'mediaTargetCount',
  'oneBlobAcrossTargets',
  'eventEnvelopesDistinct',
  'mediaEnvelopesDistinct',
  'offlineEventSiblingExact',
  'offlineBlobSiblingExact',
};

const Set<String> _directFanoutSiblingArtifactKeys = <String>{
  ..._directFanoutCommonArtifactKeys,
  'outerSenderTransportPeerIdSha256',
  'innerSenderAccountPeerIdSha256',
  'receiptDestinationPeerIdSha256',
  'eventApplied',
  'mediaApplied',
  'blobDownloaded',
  'blobAcked',
  'receiptRoutedToPhysicalTransport',
};

/// Strict cross-role proof validation for the aggregate Plan-362 device leg.
///
/// Role JSON owns only facts that role can observe. Shared identity/message/
/// blob digests must agree, the authoring side proves two distinct envelopes
/// over one blob, and the receiving side proves logical apply plus physical
/// transport receipt routing. Recipient-aware relay counts are supplied by the
/// host's capability-bound Plan-347 probe.
DirectLinkedDeviceEventBlobFanoutValidation
validateDirectLinkedDeviceEventBlobFanoutArtifacts({
  required Object? primaryArtifact,
  required Object? siblingArtifact,
  required String expectedRunId,
  required String expectedFixtureIdentitySha256,
  required int liveProtectedCountAfterAck,
  required int offlineProtectedCountAfterAck,
  required int aggregateProtectedCountAfterAck,
  required int liveEventInboxCountAfterAck,
  required int offlineEventInboxCountAfterAck,
  required String offlineEventEnvelopeSha256,
  required int liveMediaInboxCountAfterAck,
  required int offlineMediaInboxCountAfterAck,
  required String offlineMediaEnvelopeSha256,
}) {
  final failures = <String>[];
  final primary = _asStringMap(primaryArtifact, r'$.primary', failures);
  final sibling = _asStringMap(siblingArtifact, r'$.sibling', failures);
  if (primary == null || sibling == null) {
    return DirectLinkedDeviceEventBlobFanoutValidation(failures);
  }

  _validateDirectFanoutArtifactRoot(
    primary,
    role: 'primary',
    expectedRunId: expectedRunId,
    expectedFixtureIdentitySha256: expectedFixtureIdentitySha256,
    exactKeys: _directFanoutPrimaryArtifactKeys,
    failures: failures,
  );
  _validateDirectFanoutArtifactRoot(
    sibling,
    role: 'sibling',
    expectedRunId: expectedRunId,
    expectedFixtureIdentitySha256: expectedFixtureIdentitySha256,
    exactKeys: _directFanoutSiblingArtifactKeys,
    failures: failures,
  );

  for (final key in const <String>[
    'fixtureIdentitySha256',
    'accountAPeerIdSha256',
    'accountATransportPeerIdSha256',
    'accountBPeerIdSha256',
    'offlineBTransportPeerIdSha256',
    'eventMessageIdSha256',
    'mediaMessageIdSha256',
    'attachmentIdSha256',
    'ciphertextSha256',
  ]) {
    if (primary[key] != sibling[key]) {
      failures.add(r'$.primary.' + key + r' must equal $.sibling.' + key);
    }
  }

  if (primary['accountAPeerIdSha256'] ==
      primary['accountATransportPeerIdSha256']) {
    failures.add('account A transport must differ from account A identity');
  }
  if (primary['accountBPeerIdSha256'] ==
      primary['offlineBTransportPeerIdSha256']) {
    failures.add('offline B transport must differ from live account B');
  }
  if (primary['legacyBMlKemPublicKeySha256'] ==
      primary['offlineBMlKemPublicKeySha256']) {
    failures.add('B target ML-KEM public keys must be distinct');
  }
  if (primary['eventLegacyEnvelopeSha256'] ==
      primary['eventOfflineEnvelopeSha256']) {
    failures.add('event target envelopes must be independently encrypted');
  }
  if (primary['mediaLegacyEnvelopeSha256'] ==
      primary['mediaOfflineEnvelopeSha256']) {
    failures.add('media target envelopes must be independently encrypted');
  }
  for (final entry in const <String, Object>{
    'transportDistinctFromAccount': true,
    'targetMlKemKeysDistinct': true,
    'eventTargetCount': 2,
    'mediaTargetCount': 2,
    'oneBlobAcrossTargets': true,
    'eventEnvelopesDistinct': true,
    'mediaEnvelopesDistinct': true,
    'offlineEventSiblingExact': true,
    'offlineBlobSiblingExact': true,
  }.entries) {
    _expectValue(primary, entry.key, entry.value, r'$.primary', failures);
  }
  _expectValue(
    sibling,
    'outerSenderTransportPeerIdSha256',
    sibling['accountATransportPeerIdSha256']!,
    r'$.sibling',
    failures,
  );
  _expectValue(
    sibling,
    'innerSenderAccountPeerIdSha256',
    sibling['accountAPeerIdSha256']!,
    r'$.sibling',
    failures,
  );
  _expectValue(
    sibling,
    'receiptDestinationPeerIdSha256',
    sibling['accountATransportPeerIdSha256']!,
    r'$.sibling',
    failures,
  );
  for (final key in const <String>[
    'eventApplied',
    'mediaApplied',
    'blobDownloaded',
    'blobAcked',
    'receiptRoutedToPhysicalTransport',
  ]) {
    _expectValue(sibling, key, true, r'$.sibling', failures);
  }

  if (liveProtectedCountAfterAck != 0) {
    failures.add('live B protected blob count after ACK must equal 0');
  }
  if (offlineProtectedCountAfterAck != 1) {
    failures.add('offline B protected blob count after ACK must equal 1');
  }
  if (aggregateProtectedCountAfterAck != 1) {
    failures.add('aggregate protected blob count after ACK must equal 1');
  }
  if (liveEventInboxCountAfterAck != 0) {
    failures.add('live B protected event count after ACK must equal 0');
  }
  if (offlineEventInboxCountAfterAck != 1) {
    failures.add('offline B protected event count after ACK must equal 1');
  }
  if (offlineEventEnvelopeSha256 != primary['eventOfflineEnvelopeSha256']) {
    failures.add('offline B event envelope bytes crossed role/relay evidence');
  }
  if (liveMediaInboxCountAfterAck != 0) {
    failures.add(
      'live B protected media-envelope count after ACK must equal 0',
    );
  }
  if (offlineMediaInboxCountAfterAck != 1) {
    failures.add(
      'offline B protected media-envelope count after ACK must equal 1',
    );
  }
  if (offlineMediaEnvelopeSha256 != primary['mediaOfflineEnvelopeSha256']) {
    failures.add('offline B media envelope bytes crossed role/relay evidence');
  }
  return DirectLinkedDeviceEventBlobFanoutValidation(failures);
}

void _validateDirectFanoutArtifactRoot(
  Map<String, Object?> root, {
  required String role,
  required String expectedRunId,
  required String expectedFixtureIdentitySha256,
  required Set<String> exactKeys,
  required List<String> failures,
}) {
  final path = '\$.$role';
  _expectExactKeys(root, exactKeys, path, failures);
  _expectValue(
    root,
    'schema',
    directLinkedDeviceEventBlobFanoutArtifactSchema,
    path,
    failures,
  );
  _expectValue(
    root,
    'schemaVersion',
    directLinkedDeviceEventBlobFanoutArtifactSchemaVersion,
    path,
    failures,
  );
  _expectValue(
    root,
    'scenario',
    directLinkedDeviceEventBlobFanoutScenario,
    path,
    failures,
  );
  _expectValue(root, 'runId', expectedRunId, path, failures);
  _expectValue(root, 'role', role, path, failures);
  _expectValue(
    root,
    'fixtureIdentitySha256',
    expectedFixtureIdentitySha256,
    path,
    failures,
  );
  for (final key in exactKeys.where((key) => key.endsWith('Sha256'))) {
    _sha256(root, key, path, failures);
  }
}

Map<String, Object?> buildDirectLinkedDeviceEventBlobFanoutHostSummary({
  required String runId,
  required String fixtureIdentitySha256,
  required String primaryArtifactSha256,
  required String siblingArtifactSha256,
  required String liveRecipientPeerIdSha256,
  required String offlineRecipientPeerIdSha256,
  required int liveProtectedCountAfterAck,
  required int offlineProtectedCountAfterAck,
  required int aggregateProtectedCountAfterAck,
  required int liveEventInboxCountAfterAck,
  required int offlineEventInboxCountAfterAck,
  required String offlineEventEnvelopeSha256,
  required int liveMediaInboxCountAfterAck,
  required int offlineMediaInboxCountAfterAck,
  required String offlineMediaEnvelopeSha256,
}) => <String, Object?>{
  'schema': directLinkedDeviceEventBlobFanoutHostSummarySchema,
  'schemaVersion': directLinkedDeviceEventBlobFanoutHostSummarySchemaVersion,
  'scenario': directLinkedDeviceEventBlobFanoutScenario,
  'runId': runId,
  'fixtureIdentitySha256': fixtureIdentitySha256,
  'primaryArtifactSha256': primaryArtifactSha256,
  'siblingArtifactSha256': siblingArtifactSha256,
  'liveRecipientPeerIdSha256': liveRecipientPeerIdSha256,
  'offlineRecipientPeerIdSha256': offlineRecipientPeerIdSha256,
  'recipientAwareProbe': true,
  'liveProtectedCountAfterAck': liveProtectedCountAfterAck,
  'offlineProtectedCountAfterAck': offlineProtectedCountAfterAck,
  'aggregateProtectedCountAfterAck': aggregateProtectedCountAfterAck,
  'liveEventInboxCountAfterAck': liveEventInboxCountAfterAck,
  'offlineEventInboxCountAfterAck': offlineEventInboxCountAfterAck,
  'offlineEventEnvelopeSha256': offlineEventEnvelopeSha256,
  'liveMediaInboxCountAfterAck': liveMediaInboxCountAfterAck,
  'offlineMediaInboxCountAfterAck': offlineMediaInboxCountAfterAck,
  'offlineMediaEnvelopeSha256': offlineMediaEnvelopeSha256,
};

/// The complete set of scenarios this runner may execute.
///
/// Exhaustive on purpose. An unregistered scenario must be a TERMINAL error in
/// both the host parser and the device harness: silently falling through to the
/// legacy `same_user` branch would run a completely different proof and report
/// it as a PASS for the scenario the caller actually asked for.
const Set<String> inviteReliabilityRunnerScenarios = <String>{
  inviteReliabilityScenario,
  inviteSendLatencyScenario,
  directLinkedDeviceAddressingScenario,
  directLinkedDeviceEventBlobFanoutScenario,
};

/// True for an Android emulator/AVD device ID (`emulator-<port>`).
bool isAndroidEmulatorDeviceId(String deviceId) =>
    RegExp(r'^emulator-\d+$').hasMatch(deviceId);

/// True for a plausible LIVE Android device ID this runner may drive: a
/// physical adb serial or an emulator ID — never an iOS simulator UUID, an
/// iOS hardware UDID, or a `flutter devices` desktop/web identifier.
bool isPlausibleAndroidDeviceId(String deviceId) {
  if (isAndroidEmulatorDeviceId(deviceId)) return true;
  final iosSimulatorShape = RegExp(
    r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
    r'[0-9A-Fa-f]{12}$',
  );
  final iosHardwareShape = RegExp(r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$');
  if (iosSimulatorShape.hasMatch(deviceId) ||
      iosHardwareShape.hasMatch(deviceId)) {
    return false;
  }
  return RegExp(r'^[A-Za-z0-9._:-]{4,64}$').hasMatch(deviceId) &&
      !deviceId.contains('macos') &&
      !deviceId.contains('chrome');
}

/// Name of the scenario-specific ready artifact both roles converge on.
String directLinkedDeviceAddressingReadyFileName(String runId, String role) =>
    'md004_${runId}_direct_linked_device_addressing_$role.json';

/// Schema of the [directLinkedDeviceAddressingReadyFileName] artifact.
const String directLinkedDeviceAddressingReadySchema =
    'mknoon.tc360.direct-linked-device-addressing-ready';
const int directLinkedDeviceAddressingReadySchemaVersion = 1;

const Set<String> inviteSendLatencyModes = <String>{'baseline', 'closure'};
const int inviteSendLatencyClosurePreFanoutMedianCeilingMs = 950;
const int inviteSendLatencyClosureCallerMedianCeilingMs = 1300;
const String inviteSendLatencyClosureCell = 'create|online-cold';
const List<String> inviteSendLatencyPhaseNames = <String>[
  'pre_fanout',
  'sign',
  'encrypt',
  'live',
  'inbox',
  'persistence',
  'navigation_settlement',
];

String inviteSendLatencyArtifactFileName(String runId, String role) =>
    'md004_${runId}_invite_send_latency_$role.json';

String inviteSendLatencyHostSummaryFileName(String runId) =>
    'md004_${runId}_invite_send_latency_host_summary.json';

String inviteSendLatencyHostCaptureReceiptFileName(String runId) =>
    'md004_${runId}_invite_send_latency_host_capture_receipt.json';

/// Collects stable, owner-specific role-artifact hashes into one host receipt.
///
/// The Android broker is responsible for calling [recordStableRoleArtifact]
/// only after two identical reads from the role's designated device. No
/// receipt exists until both owners have independently reached that boundary.
final class InviteSendLatencyHostCaptureBarrier {
  InviteSendLatencyHostCaptureBarrier({
    required this.runId,
    required this.mode,
  }) {
    if (runId.trim().isEmpty) {
      throw ArgumentError.value(runId, 'runId', 'Must be non-empty');
    }
    if (!inviteSendLatencyModes.contains(mode)) {
      throw ArgumentError.value(mode, 'mode', 'Must be baseline or closure');
    }
  }

  final String runId;
  final String mode;
  String? _primaryArtifactSha256;
  String? _siblingArtifactSha256;

  Map<String, Object?>? get receipt {
    final primaryArtifactSha256 = _primaryArtifactSha256;
    final siblingArtifactSha256 = _siblingArtifactSha256;
    if (primaryArtifactSha256 == null || siblingArtifactSha256 == null) {
      return null;
    }
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'schema': inviteSendLatencyHostCaptureReceiptSchema,
      'schemaVersion': inviteSendLatencyHostCaptureReceiptSchemaVersion,
      'scenario': inviteSendLatencyScenario,
      'mode': mode,
      'runId': runId,
      'primaryArtifactSha256': primaryArtifactSha256,
      'siblingArtifactSha256': siblingArtifactSha256,
    });
  }

  void recordStableRoleArtifact({
    required String role,
    required String artifactSha256,
  }) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(artifactSha256)) {
      throw ArgumentError.value(
        artifactSha256,
        'artifactSha256',
        'Must be 64 lowercase hex characters',
      );
    }
    switch (role) {
      case 'primary':
        _primaryArtifactSha256 = _recordImmutableDigest(
          role: role,
          previous: _primaryArtifactSha256,
          next: artifactSha256,
        );
      case 'sibling':
        _siblingArtifactSha256 = _recordImmutableDigest(
          role: role,
          previous: _siblingArtifactSha256,
          next: artifactSha256,
        );
      default:
        throw ArgumentError.value(role, 'role', 'Must be primary or sibling');
    }
  }

  String _recordImmutableDigest({
    required String role,
    required String? previous,
    required String next,
  }) {
    if (previous != null && previous != next) {
      throw StateError(
        '$role invite-send-latency artifact changed after stable capture',
      );
    }
    return next;
  }
}

/// Persists the host-generated receipt without ever exposing partial JSON.
///
/// Repeating the same commit is a no-op. A conflicting receipt is rejected
/// instead of overwriting the first host-custody decision.
Future<File> persistInviteSendLatencyHostCaptureReceiptAtomically({
  required Directory directory,
  required Map<String, Object?> receipt,
}) async {
  final runId = receipt['runId'];
  if (runId is! String || runId.trim().isEmpty) {
    throw ArgumentError('receipt.runId must be a non-empty string');
  }
  await directory.create(recursive: true);
  final target = File(
    '${directory.path}/${inviteSendLatencyHostCaptureReceiptFileName(runId)}',
  );
  final encoded = const JsonEncoder.withIndent(' ').convert(receipt);
  if (await target.exists()) {
    if (await target.readAsString() != encoded) {
      throw StateError('Conflicting invite-send-latency host capture receipt');
    }
    return target;
  }

  final pending = File('${target.path}.pending');
  try {
    await pending.writeAsString(encoded, flush: true);
    if (await target.exists()) {
      if (await target.readAsString() != encoded) {
        throw StateError(
          'Conflicting invite-send-latency host capture receipt',
        );
      }
    } else {
      await pending.rename(target.path);
    }
  } finally {
    if (await pending.exists()) {
      await pending.delete();
    }
  }
  if (await target.readAsString() != encoded) {
    throw StateError('Persisted host capture receipt failed exact reread');
  }
  return target;
}

typedef InviteReliabilityRoleTerminator = Future<void> Function();

/// Launches the sibling only after the primary readiness signal wins its race
/// against premature primary process exit.
///
/// Poll and deadline timers are cancelled on every terminal path. This keeps
/// an early process failure from leaving the host runner alive until the full
/// readiness timeout elapses.
Future<T> launchInviteReliabilitySiblingWhenPrimaryReady<T>({
  required bool Function() isPrimaryReady,
  required Future<int> primaryExitCode,
  required Duration timeout,
  required Duration pollInterval,
  required String readinessDescription,
  required Future<T> Function() launchSibling,
}) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
  }
  if (pollInterval <= Duration.zero) {
    throw ArgumentError.value(pollInterval, 'pollInterval', 'Must be positive');
  }

  final readiness = Completer<void>();
  Timer? pollTimer;
  Timer? timeoutTimer;
  var settled = false;

  void cancelTimers() {
    pollTimer?.cancel();
    timeoutTimer?.cancel();
  }

  void succeed() {
    if (settled) return;
    settled = true;
    cancelTimers();
    readiness.complete();
  }

  void fail(Object error, StackTrace stackTrace) {
    if (settled) return;
    settled = true;
    cancelTimers();
    readiness.completeError(error, stackTrace);
  }

  void poll() {
    if (settled) return;
    try {
      if (isPrimaryReady()) {
        succeed();
        return;
      }
    } on Object catch (error, stackTrace) {
      fail(error, stackTrace);
      return;
    }
    pollTimer = Timer(pollInterval, poll);
  }

  primaryExitCode.then<void>(
    (exitCode) => fail(
      StateError(
        'Primary exited before readiness: exitCode=$exitCode '
        'waitingFor=$readinessDescription',
      ),
      StackTrace.current,
    ),
    onError: (Object error, StackTrace stackTrace) => fail(error, stackTrace),
  );
  timeoutTimer = Timer(
    timeout,
    () => fail(
      TimeoutException('Timed out waiting for $readinessDescription', timeout),
      StackTrace.current,
    ),
  );
  poll();

  await readiness.future;
  return launchSibling();
}

/// Waits for both harness roles, but promptly terminates the surviving role
/// when its peer exits unsuccessfully.
///
/// A successful first exit is not a completed proof, so the other role is
/// allowed to finish normally. The terminators are deliberately supplied by
/// the host runner so this ordering contract remains unit-testable without
/// spawning Flutter processes.
Future<({int primary, int sibling})> superviseInviteReliabilityRoleExits({
  required Future<int> primaryExitCode,
  required Future<int> siblingExitCode,
  required InviteReliabilityRoleTerminator terminatePrimary,
  required InviteReliabilityRoleTerminator terminateSibling,
}) async {
  var primarySettled = false;
  var siblingSettled = false;
  final primaryExit = primaryExitCode.then((exitCode) {
    primarySettled = true;
    return _InviteReliabilityRoleExit(
      role: _InviteReliabilityRole.primary,
      exitCode: exitCode,
    );
  });
  final siblingExit = siblingExitCode.then((exitCode) {
    siblingSettled = true;
    return _InviteReliabilityRoleExit(
      role: _InviteReliabilityRole.sibling,
      exitCode: exitCode,
    );
  });

  final firstExit = await Future.any(<Future<_InviteReliabilityRoleExit>>[
    primaryExit,
    siblingExit,
  ]);
  if (firstExit.exitCode != 0) {
    switch (firstExit.role) {
      case _InviteReliabilityRole.primary:
        if (!siblingSettled) await terminateSibling();
      case _InviteReliabilityRole.sibling:
        if (!primarySettled) await terminatePrimary();
    }
  }

  final exits = await Future.wait(<Future<_InviteReliabilityRoleExit>>[
    primaryExit,
    siblingExit,
  ]);
  return (primary: exits[0].exitCode, sibling: exits[1].exitCode);
}

enum _InviteReliabilityRole { primary, sibling }

final class _InviteReliabilityRoleExit {
  const _InviteReliabilityRoleExit({
    required this.role,
    required this.exitCode,
  });

  final _InviteReliabilityRole role;
  final int exitCode;
}

final class InviteReliabilityRunnerArguments {
  const InviteReliabilityRunnerArguments({
    required this.scenario,
    required this.mode,
    required this.deviceIds,
    this.helpRequested = false,
  });

  final String scenario;
  final String? mode;
  final List<String> deviceIds;
  final bool helpRequested;

  bool get isLatencyScenario => scenario == inviteSendLatencyScenario;

  static InviteReliabilityRunnerArguments parse(
    List<String> arguments, {
    required List<String> defaultDeviceIds,
  }) {
    if (arguments.length == 1 &&
        (arguments.single == '--help' || arguments.single == '-h')) {
      return const InviteReliabilityRunnerArguments(
        scenario: inviteReliabilityScenario,
        mode: null,
        deviceIds: <String>[],
        helpRequested: true,
      );
    }

    String? scenarioValue;
    String? modeValue;
    List<String>? parsedDeviceIds;
    final seenOptions = <String>{};

    String takeValue(String option, int index) {
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('-')) {
        throw ArgumentError('Missing value after $option');
      }
      final value = arguments[index + 1].trim();
      if (value.isEmpty) {
        throw ArgumentError('Empty value after $option');
      }
      return value;
    }

    void markSeen(String canonicalOption) {
      if (!seenOptions.add(canonicalOption)) {
        throw ArgumentError('Duplicate option: $canonicalOption');
      }
    }

    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      switch (argument) {
        case '--scenario':
          markSeen('--scenario');
          scenarioValue = takeValue(argument, index);
          index += 1;
        case '--mode':
          markSeen('--mode');
          modeValue = takeValue(argument, index);
          index += 1;
        case '--device':
        case '-d':
          markSeen('--device');
          final rawDevices = takeValue(argument, index);
          index += 1;
          final rawParts = rawDevices.split(',');
          if (rawParts.any((part) => part.trim().isEmpty)) {
            throw ArgumentError(
              'Device list must contain exactly two non-empty IDs',
            );
          }
          parsedDeviceIds = rawParts
              .map((part) => part.trim())
              .toList(growable: false);
        case '--help':
        case '-h':
          throw ArgumentError('$argument must be the only argument');
        default:
          throw ArgumentError('Unknown argument: $argument');
      }
    }

    final scenario = scenarioValue ?? inviteReliabilityScenario;
    if (!inviteReliabilityRunnerScenarios.contains(scenario)) {
      throw ArgumentError('Unsupported scenario: $scenario');
    }

    // 360: the linked-device scenario is mode-free and needs an explicit
    // two-target pair. Inheriting a default device list would let it silently
    // run against whatever happened to be attached, which is not a proof.
    if (scenario == directLinkedDeviceAddressingScenario) {
      if (modeValue != null) {
        throw ArgumentError(
          '--mode is not supported for $directLinkedDeviceAddressingScenario',
        );
      }
      if (parsedDeviceIds == null) {
        throw ArgumentError(
          'Missing explicit two-device IDs for '
          '$directLinkedDeviceAddressingScenario',
        );
      }
      if (parsedDeviceIds.length != 2) {
        throw ArgumentError(
          'Device list must contain exactly two non-empty IDs',
        );
      }
      return InviteReliabilityRunnerArguments(
        scenario: scenario,
        mode: null,
        deviceIds: parsedDeviceIds,
      );
    }

    // 362: the aggregate event+blob wave scenario requires two DISTINCT live
    // Android IDs in physical-first/emulator-second order, refused BEFORE any
    // build: a duplicate, reversed, or non-Android pair is not a proof.
    if (scenario == directLinkedDeviceEventBlobFanoutScenario) {
      if (modeValue != null) {
        throw ArgumentError(
          '--mode is not supported for '
          '$directLinkedDeviceEventBlobFanoutScenario',
        );
      }
      if (parsedDeviceIds == null) {
        throw ArgumentError(
          'Missing explicit two-device IDs for '
          '$directLinkedDeviceEventBlobFanoutScenario',
        );
      }
      if (parsedDeviceIds.length != 2 ||
          parsedDeviceIds[0] == parsedDeviceIds[1]) {
        throw ArgumentError(
          'Device list must contain exactly two distinct non-empty IDs',
        );
      }
      final physical = parsedDeviceIds[0];
      final emulator = parsedDeviceIds[1];
      if (!isPlausibleAndroidDeviceId(physical) ||
          !isPlausibleAndroidDeviceId(emulator)) {
        throw ArgumentError(
          'Both scenario targets must be live Android device IDs',
        );
      }
      if (isAndroidEmulatorDeviceId(physical) ||
          !isAndroidEmulatorDeviceId(emulator)) {
        throw ArgumentError(
          'Device order must be physical-Android first, Android-emulator '
          'second',
        );
      }
      return InviteReliabilityRunnerArguments(
        scenario: scenario,
        mode: null,
        deviceIds: parsedDeviceIds,
      );
    }

    if (scenario == inviteSendLatencyScenario) {
      if (modeValue == null) {
        throw ArgumentError(
          '--mode <baseline|closure> is required for $inviteSendLatencyScenario',
        );
      }
      if (!inviteSendLatencyModes.contains(modeValue)) {
        throw ArgumentError(
          'Unsupported mode for $inviteSendLatencyScenario: $modeValue',
        );
      }
      if (parsedDeviceIds == null) {
        throw ArgumentError(
          '-d <physical-android-id,android-emulator-id> is required for '
          '$inviteSendLatencyScenario',
        );
      }
    } else if (modeValue != null) {
      throw ArgumentError(
        '--mode is only valid with --scenario $inviteSendLatencyScenario',
      );
    }

    final deviceIds = List<String>.unmodifiable(
      parsedDeviceIds ?? defaultDeviceIds,
    );
    if (deviceIds.length != 2) {
      throw ArgumentError(
        'Expected exactly two device IDs via -d <primary,sibling> or defaults',
      );
    }
    if (deviceIds.any((deviceId) => deviceId.trim().isEmpty)) {
      throw ArgumentError('Device IDs must be non-empty');
    }
    if (deviceIds[0] == deviceIds[1]) {
      throw ArgumentError('Primary and sibling device IDs must be distinct');
    }

    return InviteReliabilityRunnerArguments(
      scenario: scenario,
      mode: modeValue,
      deviceIds: deviceIds,
    );
  }
}

final class InviteReliabilityDeviceTarget {
  const InviteReliabilityDeviceTarget({
    required this.id,
    required this.targetPlatform,
    required this.isEmulator,
  });

  final String id;
  final String targetPlatform;
  final bool isEmulator;
}

String? validateInviteSendLatencyTopology({
  required List<String> selectedDeviceIds,
  required List<InviteReliabilityDeviceTarget> liveDevices,
}) {
  if (selectedDeviceIds.length != 2 ||
      selectedDeviceIds[0] == selectedDeviceIds[1]) {
    return 'invite_send_latency requires two distinct device IDs';
  }
  final byId = <String, InviteReliabilityDeviceTarget>{
    for (final device in liveDevices) device.id: device,
  };
  final primary = byId[selectedDeviceIds[0]];
  final sibling = byId[selectedDeviceIds[1]];
  if (primary == null || sibling == null) {
    final missing = selectedDeviceIds.where((id) => !byId.containsKey(id));
    return 'Selected device IDs are not live: ${missing.join(', ')}';
  }
  if (!primary.targetPlatform.toLowerCase().startsWith('android') ||
      !sibling.targetPlatform.toLowerCase().startsWith('android')) {
    return 'invite_send_latency requires two Android targets';
  }
  if (primary.isEmulator || !sibling.isEmulator) {
    return 'invite_send_latency requires primary=physical Android and '
        'sibling=Android emulator';
  }
  return null;
}

/// Plan 363 B1b uses the same availability-bounded Android topology as the
/// latency proof, but keeps a scenario-specific diagnostic so runner failures
/// cannot be mistaken for a latency execution.
String? validateLinkedGroupBootstrapB1bTopology({
  required List<String> selectedDeviceIds,
  required List<InviteReliabilityDeviceTarget> liveDevices,
}) {
  final result = validateInviteSendLatencyTopology(
    selectedDeviceIds: selectedDeviceIds,
    liveDevices: liveDevices,
  );
  return result?.replaceFirst(
    'invite_send_latency',
    'b1b_sibling_device_convergence',
  );
}

final class InviteSendLatencyArtifactValidation {
  InviteSendLatencyArtifactValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;
  String get detail => ok ? 'accepted' : failures.join('; ');
}

InviteSendLatencyArtifactValidation
validateInviteSendLatencyHostCaptureReceiptForRole({
  required Object? receipt,
  required String expectedRunId,
  required String expectedMode,
  required String role,
  required String expectedOwnArtifactSha256,
}) {
  final failures = <String>[];
  const path = r'$.hostCaptureReceipt';
  final root = _asStringMap(receipt, path, failures);
  if (root == null) {
    return InviteSendLatencyArtifactValidation(failures);
  }
  _expectExactKeys(
    root,
    const <String>{
      'schema',
      'schemaVersion',
      'scenario',
      'mode',
      'runId',
      'primaryArtifactSha256',
      'siblingArtifactSha256',
    },
    path,
    failures,
  );
  _expectValue(
    root,
    'schema',
    inviteSendLatencyHostCaptureReceiptSchema,
    path,
    failures,
  );
  _expectValue(
    root,
    'schemaVersion',
    inviteSendLatencyHostCaptureReceiptSchemaVersion,
    path,
    failures,
  );
  _expectValue(root, 'scenario', inviteSendLatencyScenario, path, failures);
  _expectValue(root, 'mode', expectedMode, path, failures);
  _expectValue(root, 'runId', expectedRunId, path, failures);
  final primaryArtifactSha256 = _sha256(
    root,
    'primaryArtifactSha256',
    path,
    failures,
  );
  final siblingArtifactSha256 = _sha256(
    root,
    'siblingArtifactSha256',
    path,
    failures,
  );
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedOwnArtifactSha256)) {
    failures.add(
      'expectedOwnArtifactSha256 must be 64 lowercase hex characters',
    );
  }
  final receiptOwnArtifactSha256 = switch (role) {
    'primary' => primaryArtifactSha256,
    'sibling' => siblingArtifactSha256,
    _ => null,
  };
  if (role != 'primary' && role != 'sibling') {
    failures.add('role must be primary or sibling');
  } else if (receiptOwnArtifactSha256 != null &&
      receiptOwnArtifactSha256 != expectedOwnArtifactSha256) {
    failures.add('$path ${role}ArtifactSha256 does not match local artifact');
  }
  return InviteSendLatencyArtifactValidation(failures);
}

InviteSendLatencyArtifactValidation validateInviteSendLatencyArtifacts({
  required Object? primaryArtifact,
  required Object? siblingArtifact,
  required String expectedRunId,
  required String expectedMode,
}) {
  final failures = <String>[];
  if (!inviteSendLatencyModes.contains(expectedMode)) {
    failures.add('expectedMode must be baseline or closure');
  }

  final primaryRoot = _asStringMap(primaryArtifact, r'$.primary', failures);
  final siblingRoot = _asStringMap(siblingArtifact, r'$.sibling', failures);
  if (primaryRoot == null || siblingRoot == null) {
    return InviteSendLatencyArtifactValidation(failures);
  }

  final primaryIdentity = _validateRoot(
    primaryRoot,
    role: 'primary',
    expectedRunId: expectedRunId,
    expectedMode: expectedMode,
    failures: failures,
  );
  final siblingIdentity = _validateRoot(
    siblingRoot,
    role: 'sibling',
    expectedRunId: expectedRunId,
    expectedMode: expectedMode,
    failures: failures,
  );
  if (primaryIdentity != null &&
      siblingIdentity != null &&
      primaryIdentity.peerId == siblingIdentity.peerId) {
    failures.add('primary and sibling identity.peerId values must differ');
  }

  final primarySamples = _validatePrimarySamples(
    primaryRoot['samples'],
    siblingPeerId: siblingIdentity?.peerId,
    expectedMode: expectedMode,
    failures: failures,
  );
  final siblingSamples = _validateSiblingSamples(
    siblingRoot['samples'],
    siblingPeerId: siblingIdentity?.peerId,
    siblingTransportPeerId: siblingIdentity?.transportPeerId,
    expectedMode: expectedMode,
    failures: failures,
  );

  if (primarySamples.length == 30 && siblingSamples.length == 30) {
    for (final entry in primarySamples.entries) {
      final primary = entry.value;
      final sibling = siblingSamples[entry.key];
      if (sibling == null) {
        failures.add(r'$.sibling.samples is missing operationId ' + entry.key);
        continue;
      }
      if (primary.path != sibling.path ||
          primary.condition != sibling.condition ||
          primary.repetition != sibling.repetition) {
        failures.add('operation ${entry.key} cell identity differs by role');
      }
      if (primary.groupId != sibling.groupId) {
        failures.add('operation ${entry.key} groupId differs by role');
      }
      if (primary.inviteId != sibling.inviteId) {
        failures.add('operation ${entry.key} inviteId differs by role');
      }
      if (primary.recipientPeerId != sibling.recipientPeerId) {
        failures.add('operation ${entry.key} recipientPeerId differs by role');
      }
      if (sibling.pendingInviteId != null &&
          sibling.pendingInviteId != primary.inviteId) {
        failures.add(
          'operation ${entry.key} non-null pendingInviteId must equal inviteId',
        );
      }
    }
    for (final operationId in siblingSamples.keys) {
      if (!primarySamples.containsKey(operationId)) {
        failures.add(
          r'$.sibling.samples has unmatched operationId ' + operationId,
        );
      }
    }
  }

  return InviteSendLatencyArtifactValidation(failures);
}

final class InviteSendLatencyProvenance {
  const InviteSendLatencyProvenance({
    required this.appGitRevision,
    required this.appGitDirty,
    required this.appSourceFingerprintSha256,
    required this.nativeGitRevision,
    required this.relayAddressCount,
    required this.relayAddressesSha256,
  });

  final String appGitRevision;
  final bool appGitDirty;
  final String appSourceFingerprintSha256;
  final String nativeGitRevision;
  final int relayAddressCount;
  final String relayAddressesSha256;
}

Map<String, Object?> buildInviteSendLatencyHostSummary({
  required Object? primaryArtifact,
  required Object? siblingArtifact,
  required String expectedRunId,
  required String expectedMode,
  required String primaryArtifactPath,
  required String primaryArtifactSha256,
  required String siblingArtifactPath,
  required String siblingArtifactSha256,
  required InviteSendLatencyProvenance provenance,
  DateTime? generatedAt,
}) {
  final roleValidation = validateInviteSendLatencyArtifacts(
    primaryArtifact: primaryArtifact,
    siblingArtifact: siblingArtifact,
    expectedRunId: expectedRunId,
    expectedMode: expectedMode,
  );
  if (!roleValidation.ok) {
    throw ArgumentError(
      'Cannot summarize invalid latency artifacts: ${roleValidation.detail}',
    );
  }

  final primary = Map<String, Object?>.from(primaryArtifact! as Map);
  final sibling = Map<String, Object?>.from(siblingArtifact! as Map);
  final rawSamples = List<Object?>.from(primary['samples']! as List);
  final rawSiblingSamples = List<Object?>.from(sibling['samples']! as List);
  final samplesByCell = <String, List<Map<String, Object?>>>{};
  final siblingSamplesByCell = <String, List<Map<String, Object?>>>{};
  for (final rawSample in rawSamples) {
    final sample = Map<String, Object?>.from(rawSample! as Map);
    final key = '${sample['path']}|${sample['condition']}';
    samplesByCell.putIfAbsent(key, () => <Map<String, Object?>>[]).add(sample);
  }
  for (final rawSample in rawSiblingSamples) {
    final sample = Map<String, Object?>.from(rawSample! as Map);
    final key = '${sample['path']}|${sample['condition']}';
    siblingSamplesByCell
        .putIfAbsent(key, () => <Map<String, Object?>>[])
        .add(sample);
  }

  final cells = <Map<String, Object?>>[];
  for (final invitePath in _paths) {
    for (final condition in _conditions) {
      final cellSamples = samplesByCell['$invitePath|$condition']!;
      final siblingCellSamples =
          siblingSamplesByCell['$invitePath|$condition']!;
      final callerDurations = <double>[];
      final recipientEventCounts = siblingCellSamples
          .map((sample) => (sample['eventCount']! as int).toDouble())
          .toList(growable: false);
      final phaseDurations = <String, List<double>>{
        for (final phase in inviteSendLatencyPhaseNames) phase: <double>[],
      };
      final dominantCounts = <String, int>{
        for (final phase in inviteSendLatencyPhaseNames) phase: 0,
      };
      var tiedDominantCount = 0;
      var directConfirmedCount = 0;
      var custodyConfirmedCount = 0;
      var outcomeUnknownCount = 0;

      for (final sample in cellSamples) {
        switch (sample['deliveryKnowledge']) {
          case 'wire_ack_confirmed':
            directConfirmedCount += 1;
            break;
          case 'relay_custody_confirmed':
            custodyConfirmedCount += 1;
            break;
          case 'outcome_unknown':
            outcomeUnknownCount += 1;
            break;
        }
        final caller = Map<String, Object?>.from(sample['caller']! as Map);
        callerDurations.add(
          _durationMs(
            caller['beginAt']! as String,
            caller['settledAt']! as String,
          ),
        );
        final samplePhaseDurations = <String, double>{};
        for (final rawPhase in sample['phases']! as List) {
          final phase = Map<String, Object?>.from(rawPhase! as Map);
          final phaseName = phase['name']! as String;
          final duration = _durationMs(
            phase['beginAt']! as String,
            phase['endAt']! as String,
          );
          phaseDurations[phaseName]!.add(duration);
          samplePhaseDurations[phaseName] = duration;
        }
        final dominantDuration = _maximum(
          samplePhaseDurations.values.toList(growable: false),
        );
        final dominantPhases = samplePhaseDurations.entries
            .where((entry) => entry.value == dominantDuration)
            .map((entry) => entry.key)
            .toList(growable: false);
        if (dominantPhases.length == 1) {
          final dominantPhase = dominantPhases.single;
          dominantCounts[dominantPhase] = dominantCounts[dominantPhase]! + 1;
        } else {
          tiedDominantCount += 1;
        }
      }
      final recipientObservedCount = siblingCellSamples
          .where((sample) => (sample['eventCount']! as int) >= 1)
          .length;
      final recipientLateObservedCount = siblingCellSamples
          .where((sample) => sample['observedLate'] == true)
          .length;

      cells.add(<String, Object?>{
        'path': invitePath,
        'condition': condition,
        'sampleCount': cellSamples.length,
        'callerMedianMs': _median(callerDurations),
        'callerMaxMs': _maximum(callerDurations),
        'recipientEventCountMedian': _median(recipientEventCounts),
        'recipientEventCountMax': _maximum(recipientEventCounts),
        'directConfirmedCount': directConfirmedCount,
        'custodyConfirmedCount': custodyConfirmedCount,
        'outcomeUnknownCount': outcomeUnknownCount,
        'recipientObservedCount': recipientObservedCount,
        'recipientNotObservedCount':
            siblingCellSamples.length - recipientObservedCount,
        'recipientLateObservedCount': recipientLateObservedCount,
        'phaseMedianMs': <String, Object?>{
          for (final phase in inviteSendLatencyPhaseNames)
            phase: _median(phaseDurations[phase]!),
        },
        'phaseMaxMs': <String, Object?>{
          for (final phase in inviteSendLatencyPhaseNames)
            phase: _maximum(phaseDurations[phase]!),
        },
        'dominantPhaseCount': <String, Object?>{
          for (final phase in inviteSendLatencyPhaseNames)
            phase: dominantCounts[phase],
        },
        'tiedDominantCount': tiedDominantCount,
      });
    }
  }

  final disposition = _deriveDisposition(cells, mode: expectedMode);
  return <String, Object?>{
    'schema': inviteSendLatencyHostSummarySchema,
    'schemaVersion': inviteSendLatencyHostSummarySchemaVersion,
    'scenario': inviteSendLatencyScenario,
    'mode': expectedMode,
    'runId': expectedRunId,
    'generatedAt': (generatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'roleArtifacts': <String, Object?>{
      'primary': <String, Object?>{
        'path': primaryArtifactPath,
        'sha256': primaryArtifactSha256,
      },
      'sibling': <String, Object?>{
        'path': siblingArtifactPath,
        'sha256': siblingArtifactSha256,
      },
    },
    'sampleCount': rawSamples.length,
    'cells': cells,
    'disposition': disposition,
    'provenance': <String, Object?>{
      'appGitRevision': provenance.appGitRevision,
      'appGitDirty': provenance.appGitDirty,
      'appSourceFingerprintSha256': provenance.appSourceFingerprintSha256,
      'nativeGitRevision': provenance.nativeGitRevision,
      'relayAddressCount': provenance.relayAddressCount,
      'relayAddressesSha256': provenance.relayAddressesSha256,
    },
  };
}

InviteSendLatencyArtifactValidation validateInviteSendLatencyHostSummary({
  required Object? summary,
  required String expectedRunId,
  required String expectedMode,
  String? expectedPrimaryArtifactPath,
  String? expectedPrimaryArtifactSha256,
  String? expectedSiblingArtifactPath,
  String? expectedSiblingArtifactSha256,
}) {
  final failures = <String>[];
  final root = _asStringMap(summary, r'$.hostSummary', failures);
  if (root == null) return InviteSendLatencyArtifactValidation(failures);
  _expectExactKeys(root, _hostSummaryKeys, r'$.hostSummary', failures);
  _expectValue(
    root,
    'schema',
    inviteSendLatencyHostSummarySchema,
    r'$.hostSummary',
    failures,
  );
  _expectValue(
    root,
    'schemaVersion',
    inviteSendLatencyHostSummarySchemaVersion,
    r'$.hostSummary',
    failures,
  );
  _expectValue(
    root,
    'scenario',
    inviteSendLatencyScenario,
    r'$.hostSummary',
    failures,
  );
  _expectValue(root, 'mode', expectedMode, r'$.hostSummary', failures);
  _expectValue(root, 'runId', expectedRunId, r'$.hostSummary', failures);
  _timestamp(root, 'generatedAt', r'$.hostSummary', failures);
  _expectValue(root, 'sampleCount', 30, r'$.hostSummary', failures);

  final roleArtifacts = _mapField(
    root,
    'roleArtifacts',
    r'$.hostSummary',
    failures,
  );
  if (roleArtifacts != null) {
    _expectExactKeys(
      roleArtifacts,
      const <String>{'primary', 'sibling'},
      r'$.hostSummary.roleArtifacts',
      failures,
    );
    for (final role in const <String>['primary', 'sibling']) {
      final rolePath = '\$.hostSummary.roleArtifacts.$role';
      final artifact = _mapField(
        roleArtifacts,
        role,
        r'$.hostSummary.roleArtifacts',
        failures,
      );
      if (artifact == null) continue;
      _expectExactKeys(
        artifact,
        const <String>{'path', 'sha256'},
        rolePath,
        failures,
      );
      final artifactPath = _requiredString(
        artifact,
        'path',
        rolePath,
        failures,
      );
      final artifactSha256 = _sha256(artifact, 'sha256', rolePath, failures);
      final expectedPath = role == 'primary'
          ? expectedPrimaryArtifactPath
          : expectedSiblingArtifactPath;
      final expectedSha256 = role == 'primary'
          ? expectedPrimaryArtifactSha256
          : expectedSiblingArtifactSha256;
      if (expectedPath != null && artifactPath != expectedPath) {
        failures.add('$rolePath.path must match the validated $role artifact');
      }
      if (expectedSha256 != null && artifactSha256 != expectedSha256) {
        failures.add(
          '$rolePath.sha256 must match the validated $role artifact',
        );
      }
    }
  }

  final cells = _listValue(root['cells'], r'$.hostSummary.cells', failures);
  final seenCells = <String>{};
  final cellMaps = <String, Map<String, Object?>>{};
  if (cells != null) {
    if (cells.length != 6) {
      failures.add(r'$.hostSummary.cells must contain exactly 6 cells');
    }
    for (var index = 0; index < cells.length; index += 1) {
      final path = '\$.hostSummary.cells[$index]';
      final cell = _asStringMap(cells[index], path, failures);
      if (cell == null) continue;
      _expectExactKeys(cell, _hostCellKeys, path, failures);
      final invitePath = _requiredString(cell, 'path', path, failures);
      final condition = _requiredString(cell, 'condition', path, failures);
      if (invitePath != null && !_paths.contains(invitePath)) {
        failures.add('$path.path is unsupported: $invitePath');
      }
      if (condition != null && !_conditions.contains(condition)) {
        failures.add('$path.condition is unsupported: $condition');
      }
      if (invitePath != null && condition != null) {
        final key = '$invitePath|$condition';
        if (!seenCells.add(key)) failures.add('$path duplicates cell $key');
        cellMaps[key] = cell;
      }
      _expectValue(cell, 'sampleCount', 5, path, failures);
      final callerMedian = _nonNegativeNumber(
        cell,
        'callerMedianMs',
        path,
        failures,
      );
      final callerMax = _nonNegativeNumber(cell, 'callerMaxMs', path, failures);
      if (callerMedian != null &&
          callerMax != null &&
          callerMax < callerMedian) {
        failures.add('$path.callerMaxMs must be at least callerMedianMs');
      }
      final eventMedian = _nonNegativeNumber(
        cell,
        'recipientEventCountMedian',
        path,
        failures,
      );
      final eventMax = _nonNegativeNumber(
        cell,
        'recipientEventCountMax',
        path,
        failures,
      );
      if (eventMedian != null && eventMax != null && eventMax < eventMedian) {
        failures.add(
          '$path.recipientEventCountMax must be at least its median',
        );
      }
      if (expectedMode == 'closure' && eventMedian != 1) {
        failures.add(
          '$path.recipientEventCountMedian must equal 1 in closure mode',
        );
      }
      if (expectedMode == 'closure' && eventMax != 1) {
        failures.add(
          '$path.recipientEventCountMax must equal 1 in closure mode',
        );
      }
      final directConfirmedCount = _boundedCellCount(
        cell,
        'directConfirmedCount',
        path,
        failures,
      );
      final custodyConfirmedCount = _boundedCellCount(
        cell,
        'custodyConfirmedCount',
        path,
        failures,
      );
      final outcomeUnknownCount = _boundedCellCount(
        cell,
        'outcomeUnknownCount',
        path,
        failures,
      );
      if (directConfirmedCount != null &&
          custodyConfirmedCount != null &&
          outcomeUnknownCount != null &&
          directConfirmedCount + custodyConfirmedCount + outcomeUnknownCount !=
              5) {
        failures.add('$path delivery-knowledge counts must total 5');
      }
      if (expectedMode == 'closure' && outcomeUnknownCount != 0) {
        failures.add('$path closure mode forbids outcomeUnknownCount');
      }
      final recipientObservedCount = _boundedCellCount(
        cell,
        'recipientObservedCount',
        path,
        failures,
      );
      final recipientNotObservedCount = _boundedCellCount(
        cell,
        'recipientNotObservedCount',
        path,
        failures,
      );
      final recipientLateObservedCount = _boundedCellCount(
        cell,
        'recipientLateObservedCount',
        path,
        failures,
      );
      if (recipientObservedCount != null &&
          recipientNotObservedCount != null &&
          recipientObservedCount + recipientNotObservedCount != 5) {
        failures.add('$path recipient observation counts must total 5');
      }
      if (recipientLateObservedCount != null &&
          recipientObservedCount != null &&
          recipientLateObservedCount > recipientObservedCount) {
        failures.add(
          '$path recipientLateObservedCount cannot exceed observed count',
        );
      }
      if (expectedMode == 'closure' &&
          (recipientObservedCount != 5 ||
              recipientNotObservedCount != 0 ||
              recipientLateObservedCount != 0)) {
        failures.add('$path closure requires five in-window recipient events');
      }
      final phaseMedians = _validatePhaseNumberMap(
        cell,
        'phaseMedianMs',
        path,
        failures,
      );
      final phaseMaxima = _validatePhaseNumberMap(
        cell,
        'phaseMaxMs',
        path,
        failures,
      );
      if (phaseMedians != null && phaseMaxima != null) {
        for (final phase in inviteSendLatencyPhaseNames) {
          if (phaseMaxima[phase]! < phaseMedians[phase]!) {
            failures.add(
              '$path.phaseMaxMs.$phase must be at least phaseMedianMs.$phase',
            );
          }
        }
      }
      final tiedDominantCount = _requiredInt(
        cell,
        'tiedDominantCount',
        path,
        failures,
      );
      if (tiedDominantCount != null &&
          (tiedDominantCount < 0 || tiedDominantCount > 5)) {
        failures.add('$path.tiedDominantCount must be in 0..5');
      }
      final counts = _mapField(cell, 'dominantPhaseCount', path, failures);
      if (counts != null) {
        _expectExactKeys(
          counts,
          inviteSendLatencyPhaseNames.toSet(),
          '$path.dominantPhaseCount',
          failures,
        );
        var total = 0;
        for (final phase in inviteSendLatencyPhaseNames) {
          final count = _requiredInt(
            counts,
            phase,
            '$path.dominantPhaseCount',
            failures,
          );
          if (count != null) {
            if (count < 0 || count > 5) {
              failures.add('$path.dominantPhaseCount.$phase must be in 0..5');
            }
            total += count;
          }
        }
        if (tiedDominantCount != null && total + tiedDominantCount != 5) {
          failures.add(
            '$path exclusive dominant counts plus tiedDominantCount must total 5',
          );
        }
      }
    }
  }
  for (final invitePath in _paths) {
    for (final condition in _conditions) {
      final key = '$invitePath|$condition';
      if (!seenCells.contains(key)) {
        failures.add(r'$.hostSummary.cells is missing cell ' + key);
      }
    }
  }

  if (expectedMode == 'closure') {
    final closureCell = cellMaps[inviteSendLatencyClosureCell];
    if (closureCell != null) {
      final phaseMedians = closureCell['phaseMedianMs'];
      final preFanoutMedian = phaseMedians is Map
          ? phaseMedians['pre_fanout']
          : null;
      if (preFanoutMedian is num &&
          preFanoutMedian.toDouble() >
              inviteSendLatencyClosurePreFanoutMedianCeilingMs) {
        failures.add(
          r'$.hostSummary.cells[create|online-cold].phaseMedianMs.pre_fanout '
          'must be <= '
          '$inviteSendLatencyClosurePreFanoutMedianCeilingMs in closure mode',
        );
      }
      final callerMedian = closureCell['callerMedianMs'];
      if (callerMedian is num &&
          callerMedian.toDouble() >
              inviteSendLatencyClosureCallerMedianCeilingMs) {
        failures.add(
          r'$.hostSummary.cells[create|online-cold].callerMedianMs must be <= '
          '$inviteSendLatencyClosureCallerMedianCeilingMs in closure mode',
        );
      }
    }
  }

  _validateDisposition(root, cellMaps, expectedMode, failures);
  _validateProvenance(root, failures);
  return InviteSendLatencyArtifactValidation(failures);
}

Map<String, Object?> _deriveDisposition(
  List<Map<String, Object?>> cells, {
  required String mode,
}) => mode == 'closure'
    ? _deriveClosureDisposition(cells)
    : _deriveBaselineDisposition(cells);

Map<String, Object?> _deriveClosureDisposition(
  List<Map<String, Object?>> cells,
) {
  final selectedCell = cells.singleWhere(
    (cell) =>
        '${cell['path']}|${cell['condition']}' == inviteSendLatencyClosureCell,
  );
  final phaseMedians = Map<String, Object?>.from(
    selectedCell['phaseMedianMs']! as Map,
  );
  final dominantCounts = Map<String, Object?>.from(
    selectedCell['dominantPhaseCount']! as Map,
  );
  final preFanoutMedian = (phaseMedians['pre_fanout']! as num).toDouble();
  final callerMedian = (selectedCell['callerMedianMs']! as num).toDouble();
  final exactDeliveryEvidence = cells.every(
    (cell) =>
        cell['outcomeUnknownCount'] == 0 &&
        (cell['recipientEventCountMedian']! as num).toDouble() == 1 &&
        (cell['recipientEventCountMax']! as num).toDouble() == 1 &&
        cell['recipientObservedCount'] == 5 &&
        cell['recipientNotObservedCount'] == 0 &&
        cell['recipientLateObservedCount'] == 0,
  );
  final productionAuthorized =
      preFanoutMedian <= inviteSendLatencyClosurePreFanoutMedianCeilingMs &&
      callerMedian <= inviteSendLatencyClosureCallerMedianCeilingMs &&
      exactDeliveryEvidence;

  return <String, Object?>{
    'hypothesis': 'H2',
    'decision': 'candidate_selected',
    'cell': inviteSendLatencyClosureCell,
    'dominantPhase': 'pre_fanout',
    'dominantRepetitions': dominantCounts['pre_fanout'],
    'phaseMedianMs': preFanoutMedian,
    'basis':
        'closure reads create|online-cold phaseMedianMs.pre_fanout='
        '$preFanoutMedian (ceiling '
        '$inviteSendLatencyClosurePreFanoutMedianCeilingMs) and '
        'callerMedianMs=$callerMedian (ceiling '
        '$inviteSendLatencyClosureCallerMedianCeilingMs); '
        'exactDeliveryEvidence=$exactDeliveryEvidence',
    'productionAuthorized': productionAuthorized,
  };
}

Map<String, Object?> _deriveBaselineDisposition(
  List<Map<String, Object?>> cells,
) {
  Map<String, Object?>? selectedCell;
  var selectedPhase = inviteSendLatencyPhaseNames.first;
  var selectedMedian = -1.0;
  var selectedCount = 0;

  for (final cell in cells) {
    final medians = Map<String, Object?>.from(cell['phaseMedianMs']! as Map);
    final counts = Map<String, Object?>.from(
      cell['dominantPhaseCount']! as Map,
    );
    final liveMedian = (medians['live']! as num).toDouble();
    final liveCount = counts['live']! as int;
    if (liveCount >= 4 && liveMedian > 3000) {
      if (selectedCell == null || liveMedian > selectedMedian) {
        selectedCell = cell;
        selectedPhase = 'live';
        selectedMedian = liveMedian;
        selectedCount = liveCount;
      }
    }
  }

  var decision = 'candidate_selected';
  if (selectedCell == null) {
    for (final cell in cells) {
      final medians = Map<String, Object?>.from(cell['phaseMedianMs']! as Map);
      final counts = Map<String, Object?>.from(
        cell['dominantPhaseCount']! as Map,
      );
      for (final phase in inviteSendLatencyPhaseNames) {
        final median = (medians[phase]! as num).toDouble();
        if (median > selectedMedian) {
          selectedCell = cell;
          selectedPhase = phase;
          selectedMedian = median;
          selectedCount = counts[phase]! as int;
        }
      }
    }
    if (selectedPhase == 'live') decision = 'h1_threshold_not_met';
  }

  final hypothesis = switch (selectedPhase) {
    'live' => 'H1',
    'sign' || 'encrypt' => 'H3',
    'inbox' => 'H4',
    _ => 'H2',
  };
  final cellName = '${selectedCell!['path']}|${selectedCell['condition']}';
  final timingBasis = hypothesis == 'H1'
      ? decision == 'candidate_selected'
            ? 'live was exclusive-largest in at least four repetitions and its median exceeded 3000 ms'
            : 'live led the measured medians but did not satisfy the four-of-five and greater-than-3000-ms H1 rule'
      : '$selectedPhase had the largest measured cell median; production remains gated by plan review';
  final unknownCount = selectedCell['outcomeUnknownCount']! as int;
  final basis =
      '$timingBasis; selected cell recorded $unknownCount '
      'outcome-unknown sample(s), which are no-confirmation evidence only; '
      'TC-267-09 remains required';
  return <String, Object?>{
    'hypothesis': hypothesis,
    'decision': decision,
    'cell': cellName,
    'dominantPhase': selectedPhase,
    'dominantRepetitions': selectedCount,
    'phaseMedianMs': selectedMedian,
    'basis': basis,
    'productionAuthorized': false,
  };
}

double _durationMs(String begin, String end) =>
    DateTime.parse(end).difference(DateTime.parse(begin)).inMicroseconds / 1000;

double _median(List<double> values) {
  final sorted = List<double>.from(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

double _maximum(List<double> values) =>
    values.reduce((left, right) => left > right ? left : right);

const Set<String> _rootKeys = <String>{
  'schema',
  'schemaVersion',
  'scenario',
  'mode',
  'runId',
  'role',
  'roleVerdict',
  'identity',
  'admissionCanary',
  'samples',
};
const Set<String> _hostSummaryKeys = <String>{
  'schema',
  'schemaVersion',
  'scenario',
  'mode',
  'runId',
  'generatedAt',
  'roleArtifacts',
  'sampleCount',
  'cells',
  'disposition',
  'provenance',
};
const Set<String> _hostCellKeys = <String>{
  'path',
  'condition',
  'sampleCount',
  'callerMedianMs',
  'callerMaxMs',
  'recipientEventCountMedian',
  'recipientEventCountMax',
  'directConfirmedCount',
  'custodyConfirmedCount',
  'outcomeUnknownCount',
  'recipientObservedCount',
  'recipientNotObservedCount',
  'recipientLateObservedCount',
  'phaseMedianMs',
  'phaseMaxMs',
  'dominantPhaseCount',
  'tiedDominantCount',
};
const Set<String> _dispositionKeys = <String>{
  'hypothesis',
  'decision',
  'cell',
  'dominantPhase',
  'dominantRepetitions',
  'phaseMedianMs',
  'basis',
  'productionAuthorized',
};
const Set<String> _provenanceKeys = <String>{
  'appGitRevision',
  'appGitDirty',
  'appSourceFingerprintSha256',
  'nativeGitRevision',
  'relayAddressCount',
  'relayAddressesSha256',
};
const Set<String> _identityKeys = <String>{'peerId', 'transportPeerId'};
const Set<String> _admissionCanaryKeys = <String>{
  'kind',
  'attemptCount',
  'startedAt',
  'stateObservedAt',
  'storeCompletedAt',
  'drainCompletedAt',
  'completedAt',
  'storeAccepted',
  'drainCompleted',
  'nodeStarted',
  'usabilityReady',
  'relayReady',
  'transportPeerId',
  'status',
};
const Set<String> _primarySampleKeys = <String>{
  'operationId',
  'path',
  'condition',
  'repetition',
  'groupId',
  'inviteId',
  'recipientPeerId',
  'connectionState',
  'envelopeSha256',
  'transport',
  'applicationResult',
  'attemptStatus',
  'attemptLastError',
  'deliveryKnowledge',
  'liveAcknowledged',
  'liveOutcome',
  'inboxAttemptCount',
  'confirmedInboxStoreCount',
  'inboxOutcome',
  'attemptId',
  'caller',
  'phases',
};
const Set<String> _siblingSampleKeys = <String>{
  'operationId',
  'path',
  'condition',
  'repetition',
  'groupId',
  'inviteId',
  'recipientPeerId',
  'pendingInviteId',
  'eventCount',
  'observationStatus',
  'observedLate',
  'observationWindowVersion',
  'observationWindowMs',
  'observationStartedAt',
  'observationDeadlineAt',
  'observationCompletedAt',
  'finalReconciledAt',
  'drainAttemptCount',
  'drainErrorCount',
  'preparedNodeStarted',
  'preparedRelayReady',
  'preparedTransportPeerId',
  'preparedStopCompleted',
  'preparedRestartCompleted',
  'observedAt',
};
const Set<String> _callerKeys = <String>{'beginAt', 'endAt', 'settledAt'};
const Set<String> _phaseKeys = <String>{'name', 'beginAt', 'endAt', 'outcome'};
const Set<String> _paths = <String>{'create', 'add'};
const Set<String> _conditions = <String>{
  'online-warm',
  'online-cold',
  'offline',
};
const Set<String> _transports = <String>{'direct', 'inbox', 'none'};
const Set<String> _applicationResults = <String>{
  'success',
  'queued',
  'send_failed',
};
const Set<String> _attemptStatuses = <String>{'sent', 'queued', 'needs_resend'};
const Set<String> _deliveryKnowledgeValues = <String>{
  'wire_ack_confirmed',
  'relay_custody_confirmed',
  'outcome_unknown',
};
const Set<String> _recipientObservationStatuses = <String>{
  'exact_event_observed',
  'pending_without_event',
  'event_without_pending',
  'not_observed_within_window',
};

_RoleIdentity? _validateRoot(
  Map<String, Object?> root, {
  required String role,
  required String expectedRunId,
  required String expectedMode,
  required List<String> failures,
}) {
  final path = r'$.' + role;
  _expectExactKeys(root, _rootKeys, path, failures);
  _expectValue(root, 'schema', inviteSendLatencyArtifactSchema, path, failures);
  _expectValue(
    root,
    'schemaVersion',
    inviteSendLatencyArtifactSchemaVersion,
    path,
    failures,
  );
  _expectValue(root, 'scenario', inviteSendLatencyScenario, path, failures);
  _expectValue(root, 'mode', expectedMode, path, failures);
  _expectValue(root, 'runId', expectedRunId, path, failures);
  _expectValue(root, 'role', role, path, failures);
  _expectValue(root, 'roleVerdict', 'pass', path, failures);

  final identity = _mapField(root, 'identity', path, failures);
  if (identity == null) return null;
  _expectExactKeys(identity, _identityKeys, '$path.identity', failures);
  final peerId = _requiredString(
    identity,
    'peerId',
    '$path.identity',
    failures,
  );
  final transportPeerId = _requiredString(
    identity,
    'transportPeerId',
    '$path.identity',
    failures,
  );
  if (peerId == null || transportPeerId == null) return null;
  _validateAdmissionCanary(
    root,
    expectedTransportPeerId: transportPeerId,
    path: path,
    failures: failures,
  );
  return _RoleIdentity(peerId, transportPeerId);
}

void _validateAdmissionCanary(
  Map<String, Object?> root, {
  required String expectedTransportPeerId,
  required String path,
  required List<String> failures,
}) {
  final canary = _mapField(root, 'admissionCanary', path, failures);
  if (canary == null) return;
  final canaryPath = '$path.admissionCanary';
  _expectExactKeys(canary, _admissionCanaryKeys, canaryPath, failures);
  _expectValue(canary, 'kind', 'self_inbox_custody', canaryPath, failures);
  _expectValue(canary, 'attemptCount', 1, canaryPath, failures);
  _expectValue(canary, 'storeAccepted', true, canaryPath, failures);
  _expectValue(canary, 'drainCompleted', true, canaryPath, failures);
  _expectValue(canary, 'nodeStarted', true, canaryPath, failures);
  _expectValue(canary, 'usabilityReady', true, canaryPath, failures);
  _expectValue(canary, 'relayReady', true, canaryPath, failures);
  _expectValue(canary, 'status', 'accepted', canaryPath, failures);
  _expectValue(
    canary,
    'transportPeerId',
    expectedTransportPeerId,
    canaryPath,
    failures,
  );
  final timestamps = <DateTime?>[
    _timestamp(canary, 'startedAt', canaryPath, failures),
    _timestamp(canary, 'storeCompletedAt', canaryPath, failures),
    _timestamp(canary, 'drainCompletedAt', canaryPath, failures),
    _timestamp(canary, 'stateObservedAt', canaryPath, failures),
    _timestamp(canary, 'completedAt', canaryPath, failures),
  ];
  for (var index = 1; index < timestamps.length; index += 1) {
    final previous = timestamps[index - 1];
    final current = timestamps[index];
    if (previous != null && current != null && current.isBefore(previous)) {
      failures.add('$canaryPath timestamps must remain ordered');
      break;
    }
  }
}

Map<String, _PrimarySample> _validatePrimarySamples(
  Object? rawSamples, {
  required String? siblingPeerId,
  required String expectedMode,
  required List<String> failures,
}) {
  const rootPath = r'$.primary.samples';
  final samples = _listValue(rawSamples, rootPath, failures);
  if (samples == null) return <String, _PrimarySample>{};
  if (samples.length != 30) {
    failures.add('$rootPath must contain exactly 30 samples');
  }
  final byOperation = <String, _PrimarySample>{};
  final seenCells = <String>{};
  final seenInviteIds = <String>{};

  for (var index = 0; index < samples.length; index += 1) {
    final path = '$rootPath[$index]';
    final sample = _asStringMap(samples[index], path, failures);
    if (sample == null) continue;
    _expectExactKeys(sample, _primarySampleKeys, path, failures);
    final common = _validateCommonSample(sample, path, failures);
    if (common == null) continue;
    if (!seenCells.add(common.cellKey)) {
      failures.add('$path duplicates cell ${common.cellKey}');
    }
    if (byOperation.containsKey(common.operationId)) {
      failures.add('$path reuses operationId ${common.operationId}');
    }
    if (!seenInviteIds.add(common.inviteId)) {
      failures.add('$path reuses inviteId ${common.inviteId}');
    }
    if (siblingPeerId != null && common.recipientPeerId != siblingPeerId) {
      failures.add('$path.recipientPeerId must match sibling identity.peerId');
    }

    final connectionState = _requiredString(
      sample,
      'connectionState',
      path,
      failures,
    );
    if (connectionState != null &&
        !const <String>{
          'connected',
          'not_connected',
          'unknown',
        }.contains(connectionState)) {
      failures.add('$path.connectionState is unsupported: $connectionState');
    }
    final digest = _requiredString(sample, 'envelopeSha256', path, failures);
    if (digest != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      failures.add('$path.envelopeSha256 must be 64 lowercase hex characters');
    }
    final transport = _requiredString(sample, 'transport', path, failures);
    if (transport != null && !_transports.contains(transport)) {
      failures.add('$path.transport is unsupported: $transport');
    }
    final applicationResult = _requiredString(
      sample,
      'applicationResult',
      path,
      failures,
    );
    if (applicationResult != null &&
        !_applicationResults.contains(applicationResult)) {
      failures.add(
        '$path.applicationResult is unsupported: $applicationResult',
      );
    }
    final attemptStatus = _requiredString(
      sample,
      'attemptStatus',
      path,
      failures,
    );
    if (attemptStatus != null && !_attemptStatuses.contains(attemptStatus)) {
      failures.add('$path.attemptStatus is unsupported: $attemptStatus');
    }
    final attemptLastError = _nullableString(
      sample,
      'attemptLastError',
      path,
      failures,
    );
    if ((attemptStatus == 'sent' || attemptStatus == 'queued') &&
        attemptLastError != null) {
      failures.add('$path sent/queued attempt requires attemptLastError=null');
    }
    if (attemptStatus == 'needs_resend' && attemptLastError != 'send_failed') {
      failures.add(
        '$path full-phase needs_resend attempt requires '
        'attemptLastError=send_failed',
      );
    }
    final deliveryKnowledge = _requiredString(
      sample,
      'deliveryKnowledge',
      path,
      failures,
    );
    if (deliveryKnowledge != null &&
        !_deliveryKnowledgeValues.contains(deliveryKnowledge)) {
      failures.add(
        '$path.deliveryKnowledge is unsupported: $deliveryKnowledge',
      );
    }
    final liveAcknowledged = _requiredBool(
      sample,
      'liveAcknowledged',
      path,
      failures,
    );
    final liveOutcome = _requiredString(sample, 'liveOutcome', path, failures);
    if (liveOutcome != null &&
        !const <String>{
          'acknowledged',
          'unacknowledged',
          'error',
        }.contains(liveOutcome)) {
      failures.add('$path.liveOutcome is unsupported: $liveOutcome');
    }
    final inboxAttemptCount = _requiredInt(
      sample,
      'inboxAttemptCount',
      path,
      failures,
    );
    final confirmedInboxStoreCount = _requiredInt(
      sample,
      'confirmedInboxStoreCount',
      path,
      failures,
    );
    for (final entry in <String, int?>{
      'inboxAttemptCount': inboxAttemptCount,
      'confirmedInboxStoreCount': confirmedInboxStoreCount,
    }.entries) {
      if (entry.value != null && (entry.value! < 0 || entry.value! > 1)) {
        failures.add('$path.${entry.key} must be 0 or 1');
      }
    }
    if (inboxAttemptCount != null &&
        confirmedInboxStoreCount != null &&
        confirmedInboxStoreCount > inboxAttemptCount) {
      failures.add(
        '$path.confirmedInboxStoreCount cannot exceed inboxAttemptCount',
      );
    }
    final inboxOutcome = _requiredString(
      sample,
      'inboxOutcome',
      path,
      failures,
    );
    if (inboxOutcome != null &&
        !const <String>{
          'skipped',
          'stored',
          'not_stored',
          'error',
        }.contains(inboxOutcome)) {
      failures.add('$path.inboxOutcome is unsupported: $inboxOutcome');
    }
    final attemptId = _requiredString(sample, 'attemptId', path, failures);
    if (attemptId != null &&
        attemptId != '${common.groupId}:${common.recipientPeerId}') {
      failures.add('$path.attemptId must bind groupId and recipientPeerId');
    }
    final callerEvidence = _validateCallerAndPhases(sample, path, failures);
    if (callerEvidence != null) {
      for (final expected in const <String, String>{
        'pre_fanout': 'ready',
        'sign': 'signed',
        'encrypt': 'encrypted',
        'persistence': 'persisted',
        'navigation_settlement': 'settled',
      }.entries) {
        if (callerEvidence.phaseOutcomes[expected.key] != expected.value) {
          failures.add(
            '$path ${expected.key} phase requires outcome=${expected.value}',
          );
        }
      }
    }
    if (transport == 'direct' &&
        (liveAcknowledged != true ||
            liveOutcome != 'acknowledged' ||
            inboxAttemptCount != 0 ||
            confirmedInboxStoreCount != 0 ||
            inboxOutcome != 'skipped' ||
            applicationResult != 'success' ||
            attemptStatus != 'sent' ||
            attemptLastError != null ||
            deliveryKnowledge != 'wire_ack_confirmed')) {
      failures.add(
        '$path direct transport requires one consistent wire ACK result',
      );
    }
    if (transport == 'inbox' &&
        (liveAcknowledged != false ||
            !const <String>{'unacknowledged', 'error'}.contains(liveOutcome) ||
            inboxAttemptCount != 1 ||
            confirmedInboxStoreCount != 1 ||
            inboxOutcome != 'stored' ||
            applicationResult != 'queued' ||
            attemptStatus != 'queued' ||
            attemptLastError != null ||
            deliveryKnowledge != 'relay_custody_confirmed')) {
      failures.add(
        '$path inbox transport requires one consistent confirmed custody result',
      );
    }
    if (transport == 'none' &&
        (liveAcknowledged != false ||
            liveOutcome == 'acknowledged' ||
            inboxAttemptCount != 1 ||
            confirmedInboxStoreCount != 0 ||
            !const <String>{'not_stored', 'error'}.contains(inboxOutcome) ||
            applicationResult != 'send_failed' ||
            attemptStatus != 'needs_resend' ||
            attemptLastError != 'send_failed' ||
            deliveryKnowledge != 'outcome_unknown')) {
      failures.add(
        '$path transport=none must remain a truthful outcome_unknown sample',
      );
    }
    if (expectedMode == 'closure' && deliveryKnowledge == 'outcome_unknown') {
      failures.add('$path closure mode forbids outcome_unknown');
    }
    if (callerEvidence != null) {
      if (callerEvidence.liveOutcome != liveOutcome) {
        failures.add('$path.liveOutcome must match the live phase outcome');
      }
      if (callerEvidence.inboxOutcome != inboxOutcome) {
        failures.add('$path.inboxOutcome must match the inbox phase outcome');
      }
      if (inboxOutcome == 'skipped' &&
          !callerEvidence.inboxBegin.isAtSameMomentAs(
            callerEvidence.inboxEnd,
          )) {
        failures.add('$path skipped inbox phase must have zero duration');
      }
    }

    if (callerEvidence != null) {
      byOperation[common.operationId] = _PrimarySample(common);
    }
  }
  _validateCompleteGrid(seenCells, rootPath, failures);
  return byOperation;
}

Map<String, _SiblingSample> _validateSiblingSamples(
  Object? rawSamples, {
  required String? siblingPeerId,
  required String? siblingTransportPeerId,
  required String expectedMode,
  required List<String> failures,
}) {
  const rootPath = r'$.sibling.samples';
  final samples = _listValue(rawSamples, rootPath, failures);
  if (samples == null) return <String, _SiblingSample>{};
  if (samples.length != 30) {
    failures.add('$rootPath must contain exactly 30 samples');
  }
  final byOperation = <String, _SiblingSample>{};
  final seenCells = <String>{};

  for (var index = 0; index < samples.length; index += 1) {
    final path = '$rootPath[$index]';
    final sample = _asStringMap(samples[index], path, failures);
    if (sample == null) continue;
    _expectExactKeys(sample, _siblingSampleKeys, path, failures);
    final common = _validateCommonSample(sample, path, failures);
    if (common == null) continue;
    if (!seenCells.add(common.cellKey)) {
      failures.add('$path duplicates cell ${common.cellKey}');
    }
    if (byOperation.containsKey(common.operationId)) {
      failures.add('$path reuses operationId ${common.operationId}');
    }
    if (siblingPeerId != null && common.recipientPeerId != siblingPeerId) {
      failures.add('$path.recipientPeerId must match sibling identity.peerId');
    }
    final pendingInviteId = _nullableString(
      sample,
      'pendingInviteId',
      path,
      failures,
    );
    final eventCount = _requiredInt(sample, 'eventCount', path, failures);
    if (eventCount != null && eventCount < 0) {
      failures.add('$path.eventCount must be non-negative');
    }
    final observationStatus = _requiredString(
      sample,
      'observationStatus',
      path,
      failures,
    );
    if (observationStatus != null &&
        !_recipientObservationStatuses.contains(observationStatus)) {
      failures.add(
        '$path.observationStatus is unsupported: $observationStatus',
      );
    }
    final observedLate = _requiredBool(sample, 'observedLate', path, failures);
    _expectValue(
      sample,
      'observationWindowVersion',
      inviteSendLatencyObservationWindowVersion,
      path,
      failures,
    );
    _expectValue(
      sample,
      'observationWindowMs',
      inviteSendLatencyObservationWindowMs,
      path,
      failures,
    );
    final observationStartedAt = _timestamp(
      sample,
      'observationStartedAt',
      path,
      failures,
    );
    final observationDeadlineAt = _timestamp(
      sample,
      'observationDeadlineAt',
      path,
      failures,
    );
    final observationCompletedAt = _timestamp(
      sample,
      'observationCompletedAt',
      path,
      failures,
    );
    final finalReconciledAt = _timestamp(
      sample,
      'finalReconciledAt',
      path,
      failures,
    );
    if (observationStartedAt != null && observationDeadlineAt != null) {
      final windowMs = observationDeadlineAt
          .difference(observationStartedAt)
          .inMilliseconds;
      if (windowMs != inviteSendLatencyObservationWindowMs) {
        failures.add(
          '$path observation deadline must use the versioned window',
        );
      }
    }
    if (observationStartedAt != null &&
        observationCompletedAt != null &&
        observationCompletedAt.isBefore(observationStartedAt)) {
      failures.add('$path observation cannot complete before it starts');
    }
    if (observationCompletedAt != null &&
        finalReconciledAt != null &&
        finalReconciledAt.isBefore(observationCompletedAt)) {
      failures.add('$path final reconciliation cannot precede observation');
    }
    final drainAttemptCount = _requiredInt(
      sample,
      'drainAttemptCount',
      path,
      failures,
    );
    final drainErrorCount = _requiredInt(
      sample,
      'drainErrorCount',
      path,
      failures,
    );
    if (drainAttemptCount != null && drainAttemptCount < 1) {
      failures.add('$path.drainAttemptCount must be at least 1');
    }
    if (drainErrorCount != null && drainErrorCount < 0) {
      failures.add('$path.drainErrorCount must be non-negative');
    }
    if (drainAttemptCount != null &&
        drainErrorCount != null &&
        drainErrorCount > drainAttemptCount) {
      failures.add('$path.drainErrorCount cannot exceed drainAttemptCount');
    }
    final observedAt = _nullableTimestamp(sample, 'observedAt', path, failures);
    if (observedAt != null &&
        finalReconciledAt != null &&
        observedAt.isAfter(finalReconciledAt)) {
      failures.add(
        '$path first observation cannot follow final reconciliation',
      );
    }
    if (pendingInviteId != null && pendingInviteId != common.inviteId) {
      failures.add('$path.pendingInviteId must be null or equal inviteId');
    }
    if (observedLate != null &&
        observationDeadlineAt != null &&
        observedLate !=
            (observedAt != null && observedAt.isAfter(observationDeadlineAt))) {
      failures.add('$path.observedLate must reflect first observation timing');
    }
    if (eventCount == 0 &&
        observationDeadlineAt != null &&
        observationCompletedAt != null &&
        observationCompletedAt.isBefore(observationDeadlineAt)) {
      failures.add('$path zero-event observation must reach its deadline');
    }
    final observationConsistent = switch (observationStatus) {
      'exact_event_observed' =>
        pendingInviteId == common.inviteId &&
            eventCount != null &&
            eventCount >= 1 &&
            observedAt != null,
      'pending_without_event' =>
        pendingInviteId == common.inviteId &&
            eventCount == 0 &&
            observedAt == null,
      'event_without_pending' =>
        pendingInviteId == null &&
            eventCount != null &&
            eventCount >= 1 &&
            observedAt != null,
      'not_observed_within_window' =>
        pendingInviteId == null && eventCount == 0 && observedAt == null,
      _ => false,
    };
    if (!observationConsistent) {
      failures.add(
        '$path recipient observation fields contradict their status',
      );
    }
    if (expectedMode == 'closure' &&
        (eventCount != 1 ||
            pendingInviteId != common.inviteId ||
            observedAt == null ||
            (observationDeadlineAt != null &&
                observedAt.isAfter(observationDeadlineAt)) ||
            observationStatus != 'exact_event_observed' ||
            observedLate != false)) {
      failures.add(
        '$path closure requires one exact-ID recipient event within its window',
      );
    }
    final preparedNodeStarted = _requiredBool(
      sample,
      'preparedNodeStarted',
      path,
      failures,
    );
    final preparedRelayReady = _requiredBool(
      sample,
      'preparedRelayReady',
      path,
      failures,
    );
    final preparedTransportPeerId = _requiredString(
      sample,
      'preparedTransportPeerId',
      path,
      failures,
    );
    if (siblingTransportPeerId != null &&
        preparedTransportPeerId != siblingTransportPeerId) {
      failures.add(
        '$path.preparedTransportPeerId must match sibling identity.transportPeerId',
      );
    }
    final preparedStopCompleted = _requiredBool(
      sample,
      'preparedStopCompleted',
      path,
      failures,
    );
    final preparedRestartCompleted = _requiredBool(
      sample,
      'preparedRestartCompleted',
      path,
      failures,
    );
    final expectedPreparation = switch (common.condition) {
      'online-warm' => (stop: false, restart: false),
      'online-cold' => (stop: true, restart: true),
      _ => (stop: true, restart: false),
    };
    if (preparedStopCompleted != expectedPreparation.stop ||
        preparedRestartCompleted != expectedPreparation.restart) {
      failures.add(
        '$path condition does not match its stop/restart preparation evidence',
      );
    }
    if (common.condition == 'offline' &&
        (preparedNodeStarted != false || preparedRelayReady != false)) {
      failures.add(
        '$path offline condition requires a stopped, non-ready recipient',
      );
    }
    if (common.condition != 'offline' &&
        (preparedNodeStarted != true || preparedRelayReady != true)) {
      failures.add(
        '$path online condition requires a started, relay-ready recipient',
      );
    }
    byOperation[common.operationId] = _SiblingSample(
      common,
      pendingInviteId: pendingInviteId,
    );
  }
  _validateCompleteGrid(seenCells, rootPath, failures);
  return byOperation;
}

_CommonSample? _validateCommonSample(
  Map<String, Object?> sample,
  String path,
  List<String> failures,
) {
  final operationId = _requiredString(sample, 'operationId', path, failures);
  final invitePath = _requiredString(sample, 'path', path, failures);
  final condition = _requiredString(sample, 'condition', path, failures);
  final repetition = _requiredInt(sample, 'repetition', path, failures);
  final groupId = _requiredString(sample, 'groupId', path, failures);
  final inviteId = _requiredString(sample, 'inviteId', path, failures);
  final recipientPeerId = _requiredString(
    sample,
    'recipientPeerId',
    path,
    failures,
  );
  if (invitePath != null && !_paths.contains(invitePath)) {
    failures.add('$path.path is unsupported: $invitePath');
  }
  if (condition != null && !_conditions.contains(condition)) {
    failures.add('$path.condition is unsupported: $condition');
  }
  if (repetition != null && (repetition < 1 || repetition > 5)) {
    failures.add('$path.repetition must be in 1..5');
  }
  if (operationId == null ||
      invitePath == null ||
      condition == null ||
      repetition == null ||
      groupId == null ||
      inviteId == null ||
      recipientPeerId == null) {
    return null;
  }
  return _CommonSample(
    operationId: operationId,
    path: invitePath,
    condition: condition,
    repetition: repetition,
    groupId: groupId,
    inviteId: inviteId,
    recipientPeerId: recipientPeerId,
  );
}

_CallerEvidence? _validateCallerAndPhases(
  Map<String, Object?> sample,
  String path,
  List<String> failures,
) {
  final caller = _mapField(sample, 'caller', path, failures);
  DateTime? callerBegin;
  DateTime? callerEnd;
  DateTime? callerSettled;
  if (caller != null) {
    _expectExactKeys(caller, _callerKeys, '$path.caller', failures);
    callerBegin = _timestamp(caller, 'beginAt', '$path.caller', failures);
    callerEnd = _timestamp(caller, 'endAt', '$path.caller', failures);
    callerSettled = _timestamp(caller, 'settledAt', '$path.caller', failures);
    if (callerBegin != null &&
        callerEnd != null &&
        callerBegin.isAfter(callerEnd)) {
      failures.add('$path.caller beginAt must not follow endAt');
    }
    if (callerEnd != null &&
        callerSettled != null &&
        callerEnd.isAfter(callerSettled)) {
      failures.add('$path.caller endAt must not follow settledAt');
    }
  }

  final phases = _listValue(sample['phases'], '$path.phases', failures);
  if (phases == null) return null;
  if (phases.length != inviteSendLatencyPhaseNames.length) {
    failures.add(
      '$path.phases must contain exactly '
      '${inviteSendLatencyPhaseNames.length} phase delimiters',
    );
  }
  DateTime? previousEnd;
  DateTime? preFanoutBegin;
  DateTime? persistenceEnd;
  DateTime? navigationEnd;
  DateTime? inboxBegin;
  DateTime? inboxEnd;
  String? liveOutcome;
  String? inboxOutcome;
  final phaseOutcomes = <String, String>{};
  for (var index = 0; index < phases.length; index += 1) {
    final phasePath = '$path.phases[$index]';
    final phase = _asStringMap(phases[index], phasePath, failures);
    if (phase == null) continue;
    _expectExactKeys(phase, _phaseKeys, phasePath, failures);
    if (index < inviteSendLatencyPhaseNames.length) {
      _expectValue(
        phase,
        'name',
        inviteSendLatencyPhaseNames[index],
        phasePath,
        failures,
      );
    }
    final outcome = _requiredString(phase, 'outcome', phasePath, failures);
    if (index < inviteSendLatencyPhaseNames.length && outcome != null) {
      phaseOutcomes[inviteSendLatencyPhaseNames[index]] = outcome;
    }
    final begin = _timestamp(phase, 'beginAt', phasePath, failures);
    final end = _timestamp(phase, 'endAt', phasePath, failures);
    if (begin == null || end == null) continue;
    if (begin.isAfter(end)) {
      failures.add('$phasePath beginAt must not follow endAt');
    }
    if (previousEnd != null && begin.isBefore(previousEnd)) {
      failures.add('$phasePath begins before the prior phase ended');
    }
    if (callerBegin != null && begin.isBefore(callerBegin)) {
      failures.add('$phasePath begins before caller.beginAt');
    }
    if (callerSettled != null && end.isAfter(callerSettled)) {
      failures.add('$phasePath ends after caller.settledAt');
    }
    if (index == 0) preFanoutBegin = begin;
    if (index == inviteSendLatencyPhaseNames.indexOf('inbox')) {
      inboxBegin = begin;
      inboxEnd = end;
      inboxOutcome = outcome;
    }
    if (index == inviteSendLatencyPhaseNames.indexOf('live')) {
      liveOutcome = outcome;
    }
    if (index == inviteSendLatencyPhaseNames.indexOf('persistence')) {
      persistenceEnd = end;
    }
    if (index == inviteSendLatencyPhaseNames.indexOf('navigation_settlement')) {
      navigationEnd = end;
    }
    previousEnd = end;
  }
  if (callerBegin != null &&
      preFanoutBegin != null &&
      !callerBegin.isAtSameMomentAs(preFanoutBegin)) {
    failures.add('$path.caller.beginAt must equal pre_fanout.beginAt');
  }
  if (callerEnd != null &&
      persistenceEnd != null &&
      !callerEnd.isAtSameMomentAs(persistenceEnd)) {
    failures.add('$path.caller.endAt must equal persistence.endAt');
  }
  if (callerSettled != null &&
      navigationEnd != null &&
      !callerSettled.isAtSameMomentAs(navigationEnd)) {
    failures.add(
      '$path.caller.settledAt must equal navigation_settlement.endAt',
    );
  }
  if (callerSettled == null ||
      inboxBegin == null ||
      inboxEnd == null ||
      liveOutcome == null ||
      inboxOutcome == null) {
    return null;
  }
  return _CallerEvidence(
    inboxBegin: inboxBegin,
    inboxEnd: inboxEnd,
    liveOutcome: liveOutcome,
    inboxOutcome: inboxOutcome,
    phaseOutcomes: Map<String, String>.unmodifiable(phaseOutcomes),
  );
}

void _validateCompleteGrid(
  Set<String> seenCells,
  String path,
  List<String> failures,
) {
  for (final invitePath in _paths) {
    for (final condition in _conditions) {
      for (var repetition = 1; repetition <= 5; repetition += 1) {
        final key = '$invitePath|$condition|$repetition';
        if (!seenCells.contains(key)) {
          failures.add('$path is missing cell $key');
        }
      }
    }
  }
}

Map<String, num>? _validatePhaseNumberMap(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) {
  final values = _mapField(owner, key, path, failures);
  if (values == null) return null;
  _expectExactKeys(
    values,
    inviteSendLatencyPhaseNames.toSet(),
    '$path.$key',
    failures,
  );
  final result = <String, num>{};
  for (final phase in inviteSendLatencyPhaseNames) {
    final value = _nonNegativeNumber(values, phase, '$path.$key', failures);
    if (value != null) result[phase] = value;
  }
  return result.length == inviteSendLatencyPhaseNames.length ? result : null;
}

int? _boundedCellCount(
  Map<String, Object?> cell,
  String key,
  String path,
  List<String> failures,
) {
  final count = _requiredInt(cell, key, path, failures);
  if (count != null && (count < 0 || count > 5)) {
    failures.add('$path.$key must be in 0..5');
  }
  return count;
}

void _validateDisposition(
  Map<String, Object?> root,
  Map<String, Map<String, Object?>> cells,
  String expectedMode,
  List<String> failures,
) {
  const path = r'$.hostSummary.disposition';
  final disposition = _mapField(
    root,
    'disposition',
    r'$.hostSummary',
    failures,
  );
  if (disposition == null) return;
  _expectExactKeys(disposition, _dispositionKeys, path, failures);
  final hypothesis = _requiredString(disposition, 'hypothesis', path, failures);
  if (hypothesis != null &&
      !const <String>{'H1', 'H2', 'H3', 'H4'}.contains(hypothesis)) {
    failures.add('$path.hypothesis must be H1, H2, H3, or H4');
  }
  final decision = _requiredString(disposition, 'decision', path, failures);
  if (decision != null &&
      !const <String>{
        'candidate_selected',
        'h1_threshold_not_met',
      }.contains(decision)) {
    failures.add('$path.decision is unsupported: $decision');
  }
  final cell = _requiredString(disposition, 'cell', path, failures);
  if (cell != null &&
      !<String>{
        for (final invitePath in _paths)
          for (final condition in _conditions) '$invitePath|$condition',
      }.contains(cell)) {
    failures.add('$path.cell is unsupported: $cell');
  }
  final phase = _requiredString(disposition, 'dominantPhase', path, failures);
  if (phase != null && !inviteSendLatencyPhaseNames.contains(phase)) {
    failures.add('$path.dominantPhase is unsupported: $phase');
  }
  final repetitions = _requiredInt(
    disposition,
    'dominantRepetitions',
    path,
    failures,
  );
  if (repetitions != null && (repetitions < 0 || repetitions > 5)) {
    failures.add('$path.dominantRepetitions must be in 0..5');
  }
  final phaseMedian = _nonNegativeNumber(
    disposition,
    'phaseMedianMs',
    path,
    failures,
  );
  _requiredString(disposition, 'basis', path, failures);
  _expectValue(
    disposition,
    'productionAuthorized',
    expectedMode == 'closure',
    path,
    failures,
  );
  if (phase != null && hypothesis != null) {
    final expectedHypothesis = switch (phase) {
      'live' => 'H1',
      'sign' || 'encrypt' => 'H3',
      'inbox' => 'H4',
      _ => 'H2',
    };
    if (hypothesis != expectedHypothesis) {
      failures.add('$path.hypothesis does not match dominantPhase');
    }
  }
  if (cell != null && phase != null) {
    final sourceCell = cells[cell];
    if (sourceCell != null) {
      final medians = sourceCell['phaseMedianMs'];
      final counts = sourceCell['dominantPhaseCount'];
      if (medians is Map &&
          phaseMedian != null &&
          medians[phase] != phaseMedian) {
        failures.add('$path.phaseMedianMs must match the selected cell');
      }
      if (counts is Map &&
          repetitions != null &&
          counts[phase] != repetitions) {
        failures.add('$path.dominantRepetitions must match the selected cell');
      }
    }
  }
  if (hypothesis == 'H1') {
    final satisfiesH1 =
        phase == 'live' &&
        repetitions != null &&
        repetitions >= 4 &&
        phaseMedian != null &&
        phaseMedian > 3000;
    final expectedDecision = satisfiesH1
        ? 'candidate_selected'
        : 'h1_threshold_not_met';
    if (decision != expectedDecision) {
      failures.add('$path.decision does not match the quantitative H1 rule');
    }
  } else if (decision != null && decision != 'candidate_selected') {
    failures.add('$path non-H1 disposition must select its measured candidate');
  }
  if (cells.length == 6) {
    final orderedCells = <Map<String, Object?>>[];
    for (final invitePath in _paths) {
      for (final condition in _conditions) {
        final cell = cells['$invitePath|$condition'];
        if (cell != null) orderedCells.add(cell);
      }
    }
    if (orderedCells.length == 6) {
      final expected = _deriveDisposition(orderedCells, mode: expectedMode);
      for (final key in _dispositionKeys) {
        if (disposition[key] != expected[key]) {
          failures.add('$path.$key does not match the measured cell table');
        }
      }
    }
  }
}

void _validateProvenance(Map<String, Object?> root, List<String> failures) {
  const path = r'$.hostSummary.provenance';
  final provenance = _mapField(root, 'provenance', r'$.hostSummary', failures);
  if (provenance == null) return;
  _expectExactKeys(provenance, _provenanceKeys, path, failures);
  for (final key in const <String>['appGitRevision', 'nativeGitRevision']) {
    final revision = _requiredString(provenance, key, path, failures);
    if (revision != null && !RegExp(r'^[0-9a-f]{40,64}$').hasMatch(revision)) {
      failures.add('$path.$key must be a full Git revision');
    }
  }
  _requiredBool(provenance, 'appGitDirty', path, failures);
  _sha256(provenance, 'appSourceFingerprintSha256', path, failures);
  final relayCount = _requiredInt(
    provenance,
    'relayAddressCount',
    path,
    failures,
  );
  if (relayCount != null && relayCount < 1) {
    failures.add('$path.relayAddressCount must be positive');
  }
  _sha256(provenance, 'relayAddressesSha256', path, failures);
}

Map<String, Object?>? _asStringMap(
  Object? value,
  String path,
  List<String> failures,
) {
  if (value is! Map) {
    failures.add('$path must be a JSON object');
    return null;
  }
  if (value.keys.any((key) => key is! String)) {
    failures.add('$path must use string keys');
    return null;
  }
  return Map<String, Object?>.from(value);
}

Map<String, Object?>? _mapField(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) => _asStringMap(owner[key], '$path.$key', failures);

List<Object?>? _listValue(Object? value, String path, List<String> failures) {
  if (value is! List) {
    failures.add('$path must be a JSON array');
    return null;
  }
  return List<Object?>.from(value);
}

void _expectExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String path,
  List<String> failures,
) {
  final actual = value.keys.toSet();
  final missing = expected.difference(actual).toList()..sort();
  final unexpected = actual.difference(expected).toList()..sort();
  if (missing.isNotEmpty) {
    failures.add('$path is missing keys: ${missing.join(', ')}');
  }
  if (unexpected.isNotEmpty) {
    failures.add('$path has unexpected keys: ${unexpected.join(', ')}');
  }
}

void _expectValue(
  Map<String, Object?> owner,
  String key,
  Object expected,
  String path,
  List<String> failures,
) {
  if (owner[key] != expected) {
    failures.add('$path.$key must equal $expected');
  }
}

String? _requiredString(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) {
  final value = owner[key];
  if (value is! String || value.trim().isEmpty) {
    failures.add('$path.$key must be a non-empty string');
    return null;
  }
  return value;
}

String? _nullableString(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) {
  final value = owner[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    failures.add('$path.$key must be null or a non-empty string');
    return null;
  }
  return value;
}

int? _requiredInt(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) {
  final value = owner[key];
  if (value is! int) {
    failures.add('$path.$key must be an integer');
    return null;
  }
  return value;
}

bool? _requiredBool(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) {
  final value = owner[key];
  if (value is! bool) {
    failures.add('$path.$key must be a boolean');
    return null;
  }
  return value;
}

num? _nonNegativeNumber(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) {
  final value = owner[key];
  if (value is! num || !value.isFinite || value < 0) {
    failures.add('$path.$key must be a finite non-negative number');
    return null;
  }
  return value;
}

String? _sha256(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) {
  final digest = _requiredString(owner, key, path, failures);
  if (digest != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    failures.add('$path.$key must be 64 lowercase hex characters');
  }
  return digest;
}

DateTime? _timestamp(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) {
  final raw = _requiredString(owner, key, path, failures);
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || !parsed.isUtc || !raw.endsWith('Z')) {
    failures.add('$path.$key must be an ISO-8601 UTC timestamp');
    return null;
  }
  return parsed;
}

DateTime? _nullableTimestamp(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) {
  final raw = owner[key];
  if (raw == null) return null;
  if (raw is! String || raw.trim().isEmpty) {
    failures.add('$path.$key must be null or an ISO-8601 UTC timestamp');
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || !parsed.isUtc || !raw.endsWith('Z')) {
    failures.add('$path.$key must be null or an ISO-8601 UTC timestamp');
    return null;
  }
  return parsed;
}

final class _RoleIdentity {
  const _RoleIdentity(this.peerId, this.transportPeerId);

  final String peerId;
  final String transportPeerId;
}

final class _CommonSample {
  const _CommonSample({
    required this.operationId,
    required this.path,
    required this.condition,
    required this.repetition,
    required this.groupId,
    required this.inviteId,
    required this.recipientPeerId,
  });

  final String operationId;
  final String path;
  final String condition;
  final int repetition;
  final String groupId;
  final String inviteId;
  final String recipientPeerId;

  String get cellKey => '$path|$condition|$repetition';
}

final class _PrimarySample {
  const _PrimarySample(this.common);

  final _CommonSample common;
  String get path => common.path;
  String get condition => common.condition;
  int get repetition => common.repetition;
  String get groupId => common.groupId;
  String get inviteId => common.inviteId;
  String get recipientPeerId => common.recipientPeerId;
}

final class _SiblingSample {
  const _SiblingSample(this.common, {required this.pendingInviteId});

  final _CommonSample common;
  final String? pendingInviteId;
  String get path => common.path;
  String get condition => common.condition;
  int get repetition => common.repetition;
  String get groupId => common.groupId;
  String get inviteId => common.inviteId;
  String get recipientPeerId => common.recipientPeerId;
}

final class _CallerEvidence {
  const _CallerEvidence({
    required this.inboxBegin,
    required this.inboxEnd,
    required this.liveOutcome,
    required this.inboxOutcome,
    required this.phaseOutcomes,
  });

  final DateTime inboxBegin;
  final DateTime inboxEnd;
  final String liveOutcome;
  final String inboxOutcome;
  final Map<String, String> phaseOutcomes;
}
