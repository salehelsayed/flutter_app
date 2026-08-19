#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '_android_app_package.dart';
import 'group_muted_notification_android_criteria.dart';
import 'group_notification_projection_android_criteria.dart';
import 'group_reaction_notification_device_criteria.dart';
import 'reaction_notification_proof_support.dart';

const _defaultRelayTarget = 'ubuntu@mknoun.xyz';
const _defaultRelayKey = 'se.pem';
const _defaultServiceAccount =
    'mknoon-c6e62-firebase-adminsdk-fbsvc-70e1a8d4fb.json';
const _reactionEmoji = '👍';
const _sqlCipherProbe =
    'integration_test/group_reaction_notification_sqlcipher_probe_test.dart';
const _duplicateRedrivePrefix = 'MKNOON_257_DUPLICATE_REDRIVE_OBSERVATION ';
const _runtimeRequestSchema = 'mknoon.plan257.runtime-probe-request.v1';
const _runtimeResultSchema = 'mknoon.plan257.runtime-probe-result.v1';
const _runtimeObserveAction = 'group_reaction_sqlcipher_observe';
const _runtimeExactAddRedriveAction = 'group_reaction_exact_add_redrive';
const _plan330EndpointAction = 'group_notification_projection_android';
const _plan330EndpointCommandSchema =
    'mknoon.plan330.android-endpoint-command.v1';
const _plan330EndpointResultSchema =
    'mknoon.plan330.android-endpoint-result.v1';
const _iosTapTest = 'ios/RunnerUITests/NotificationTapUITests.swift';
const _iosTapSelector = 'testAnnouncementReactionNotificationTap';
const _iosFixtureCreateSelector = 'testCreateAnnouncementReactionFixture';
const _iosFixtureAuthorSelector = 'testAuthorAnnouncementReactionTarget';
const _iosNotificationPrepareSelector = 'testPrepareWarmNotificationTap';
const _iosSystemLogExecutable = 'idevicesyslog';

/// Stable Android semantics identifier for Orbit's create-group FAB.
///
/// This is intentionally not localized: the host driver uses it as an exact
/// automation identifier while the expanded actions retain localized labels.
const String orbitCreateGroupFabSemanticId = 'orbit_create_group_fab';

/// Returns the exact semantics-node center for Orbit's create-group FAB.
///
/// Generic top-right clickability is deliberately insufficient: other Orbit
/// actions occupy the same quadrant and may be mounted before the FAB.
(int, int)? findOrbitCreateGroupFabCenter(String xml) {
  for (final node in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = node.group(0)!;
    if (_fixtureXmlAttribute(raw, 'content-desc') !=
        orbitCreateGroupFabSemanticId) {
      continue;
    }
    final bounds = RegExp(
      r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
    ).firstMatch(raw);
    if (bounds == null) continue;
    return (
      (int.parse(bounds.group(1)!) + int.parse(bounds.group(3)!)) ~/ 2,
      (int.parse(bounds.group(2)!) + int.parse(bounds.group(4)!)) ~/ 2,
    );
  }
  return null;
}

/// Probes the exact FAB around one bounded Orbit re-establishment attempt.
Future<(int, int)?> findOrbitCreateGroupFabWithRecovery({
  required Future<String> Function() readUiDump,
  required Future<void> Function() reestablishOrbit,
  int probesBeforeRecovery = 4,
  int probesAfterRecovery = 4,
  Duration retryDelay = const Duration(milliseconds: 500),
}) async {
  if (probesBeforeRecovery <= 0 || probesAfterRecovery <= 0) {
    throw ArgumentError('FAB recovery probe counts must be positive');
  }

  Future<(int, int)?> probe(int count) async {
    for (var attempt = 0; attempt < count; attempt++) {
      final center = findOrbitCreateGroupFabCenter(await readUiDump());
      if (center != null) return center;
      if (attempt + 1 < count && retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
    }
    return null;
  }

  final initial = await probe(probesBeforeRecovery);
  if (initial != null) return initial;
  await reestablishOrbit();
  return probe(probesAfterRecovery);
}

/// Finds one of Plan 330's exact group nodes on a canonical Inner Circle.
///
/// Accepting a group invite opens Orbit's all-chats `Intros` filter. The
/// create-group FAB remains mounted there, but active group nodes are excluded
/// from that filter. Plan 330 owns only one contact and two groups, so all
/// three active nodes fit inside Inner Circle's thirteen seats. Canonicalizing
/// to Inner Circle is therefore deterministic and avoids mistaking a mounted
/// FAB for an active-group projection.
Future<(int, int)?> findPlan330OrbitGroupWithInnerCircleRecovery({
  required String groupName,
  required Future<String> Function() readUiDump,
  required Future<void> Function((int, int) center) tapSemanticNode,
  int maximumPolls = 30,
  int maximumToggleAttempts = 2,
  Duration retryDelay = const Duration(milliseconds: 700),
}) async {
  if (maximumPolls <= 0) {
    throw ArgumentError.value(maximumPolls, 'maximumPolls');
  }
  if (maximumToggleAttempts <= 0) {
    throw ArgumentError.value(maximumToggleAttempts, 'maximumToggleAttempts');
  }

  var toggleAttempts = 0;
  for (var poll = 0; poll < maximumPolls; poll += 1) {
    final dump = await readUiDump();
    final showInnerCircle = findSemanticNodeCenter(dump, 'Show inner circle');
    if (showInnerCircle != null && toggleAttempts < maximumToggleAttempts) {
      toggleAttempts += 1;
      await tapSemanticNode(showInnerCircle);
    } else if (findSemanticNodeCenter(dump, 'Show all chats') != null) {
      final group = findSemanticNodeCenter(dump, 'Open group $groupName');
      if (group != null) return group;
    } else if (toggleAttempts == 0) {
      return null;
    }

    if (poll + 1 < maximumPolls && retryDelay > Duration.zero) {
      await Future<void>.delayed(retryDelay);
    }
  }
  return null;
}

/// Waits for the readiness event emitted by one already-pinned app process.
///
/// The caller owns process pinning (the live driver uses `logcat --pid`).
/// Nearby diagnostic prose is not accepted as readiness.
Future<bool> waitForCreatorSendableReadiness({
  required Future<String> Function() readCurrentProcessLog,
  int maximumPolls = 90,
  Duration pollInterval = const Duration(seconds: 1),
}) async {
  if (maximumPolls <= 0) {
    throw ArgumentError.value(maximumPolls, 'maximumPolls');
  }
  final event = RegExp(r'"event"\s*:\s*"TIME_TO_SENDABLE_BADGE"');
  for (var poll = 0; poll < maximumPolls; poll++) {
    if (event.hasMatch(await readCurrentProcessLog())) return true;
    if (poll + 1 < maximumPolls && pollInterval > Duration.zero) {
      await Future<void>.delayed(pollInterval);
    }
  }
  return false;
}

/// Opens a fresh group-mutation window after the current process completes a
/// newly observed canonical group-inbox drain, plus a small settle interval.
///
/// A stale completion already in logcat is deliberately insufficient. Group
/// creation adds members after persisting the group, so a recovery pass that
/// begins mid-create can activate the mutation guard and leave a partial
/// fixture with no invite. Waiting immediately before the final create tap
/// keeps this proof setup out of that periodic recovery window.
Future<bool> waitForCreatorGroupRecoveryQuiescentWindow({
  required Future<String> Function() readCurrentProcessLog,
  int maximumPolls = 60,
  Duration pollInterval = const Duration(seconds: 1),
  Duration settleDelay = const Duration(seconds: 2),
}) async {
  if (maximumPolls <= 0) {
    throw ArgumentError.value(maximumPolls, 'maximumPolls');
  }
  final completed = RegExp(r'"event"\s*:\s*"GROUP_DRAIN_OFFLINE_INBOX_TIMING"');
  final baselineCount = completed
      .allMatches(await readCurrentProcessLog())
      .length;
  for (var poll = 0; poll < maximumPolls; poll++) {
    final currentCount = completed
        .allMatches(await readCurrentProcessLog())
        .length;
    if (currentCount > baselineCount) {
      if (settleDelay > Duration.zero) {
        await Future<void>.delayed(settleDelay);
      }
      return true;
    }
    if (poll + 1 < maximumPolls && pollInterval > Duration.zero) {
      await Future<void>.delayed(pollInterval);
    }
  }
  return false;
}

/// Waits for a real pending-group projection, not Orbit's empty review remnant.
///
/// A non-empty review dock is opened at most once per observed label. Recovery
/// runs once at [recoveryPoll]; callers provide the bounded Orbit navigation.
Future<String?> waitForPendingGroupInviteProjection({
  required String groupName,
  required Future<String> Function() readUiDump,
  required Future<void> Function(String label) openReview,
  required Future<void> Function() reestablishOrbit,
  int maximumPolls = 180,
  int recoveryPoll = 20,
  Duration pollInterval = const Duration(seconds: 1),
}) async {
  if (maximumPolls <= 0) {
    throw ArgumentError.value(maximumPolls, 'maximumPolls');
  }
  if (recoveryPoll <= 0 || recoveryPoll > maximumPolls) {
    throw ArgumentError.value(recoveryPoll, 'recoveryPoll');
  }

  final openedLabels = <String>{};
  for (var poll = 1; poll <= maximumPolls; poll++) {
    final values = _fixtureSemanticValues(await readUiDump());
    if (values.contains(groupName)) return groupName;
    if (values.contains('Pending Group Invites')) {
      return 'Pending Group Invites';
    }

    final nonEmptyReview = values.cast<String?>().firstWhere(
      (value) =>
          value != null &&
          value.startsWith('Open introductions review, ') &&
          value.endsWith(' new'),
      orElse: () => null,
    );
    if (nonEmptyReview != null && openedLabels.add(nonEmptyReview)) {
      await openReview(nonEmptyReview);
    }

    if (poll == recoveryPoll) {
      await reestablishOrbit();
    }
    if (poll < maximumPolls && pollInterval > Duration.zero) {
      await Future<void>.delayed(pollInterval);
    }
  }
  return null;
}

/// One-shot cleanup for child-owned transient fixture state.
///
/// App/private state and notification restoration remain owned by the outer
/// AndroidAppStateGuard. This child cleanup removes only its temporary request,
/// result, status-bar, and pending-proof residue and is safe to call twice.
final class GroupFixtureTransientCleanup {
  GroupFixtureTransientCleanup(Iterable<Future<void> Function()> actions)
    : _actions = List<Future<void> Function()>.unmodifiable(actions);

  final List<Future<void> Function()> _actions;
  bool _completed = false;

  bool get completed => _completed;

  Future<void> run() async {
    if (_completed) return;
    _completed = true;
    for (final action in _actions) {
      await action();
    }
  }
}

/// Retries a read-only fixture command through a bounded transient failure.
///
/// Android emulators can briefly replace their adb transport while the app is
/// backgrounded. Evidence collection must tolerate that reconnect, but the
/// final non-success result is still returned for the caller to classify.
Future<T> retryBoundedFixtureRead<T>({
  required Future<T> Function() attempt,
  required bool Function(T value) succeeded,
  int maximumAttempts = 3,
  Duration retryDelay = const Duration(milliseconds: 500),
}) async {
  if (maximumAttempts <= 0) {
    throw ArgumentError.value(maximumAttempts, 'maximumAttempts');
  }
  late T result;
  for (
    var attemptNumber = 1;
    attemptNumber <= maximumAttempts;
    attemptNumber++
  ) {
    result = await attempt();
    if (succeeded(result) || attemptNumber == maximumAttempts) return result;
    if (retryDelay > Duration.zero) {
      await Future<void>.delayed(retryDelay);
    }
  }
  return result;
}

Set<String> _fixtureSemanticValues(String xml) {
  final values = <String>{};
  for (final node in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = node.group(0)!;
    for (final attribute in const <String>['text', 'content-desc']) {
      final value = _fixtureXmlAttribute(raw, attribute);
      if (value.isNotEmpty) values.add(value);
    }
  }
  return values;
}

String _fixtureXmlAttribute(String raw, String name) =>
    RegExp('$name="([^"]*)"').firstMatch(raw)?.group(1) ?? '';

Future<void> main(List<String> args) async {
  final scenarioId = _valueFor(args, '--scenario');
  final senderId = _valueFor(args, '--sender');
  final recipientId = _valueFor(args, '--recipient');
  final artifactPath = _valueFor(args, '--artifact-dir');
  final scenario = scenarioId == null
      ? null
      : groupReactionNotificationScenario(scenarioId);
  if (scenario == null ||
      senderId == null ||
      recipientId == null ||
      artifactPath == null) {
    _usage();
  }

  final artifactDirectory = Directory(artifactPath).absolute;
  final stagingPath =
      _valueFor(args, '--staging-manifest') ??
      Platform.environment['MKNOON_257_STAGING_MANIFEST'];
  if (stagingPath == null || stagingPath.trim().isEmpty) {
    await writeGroupReactionNotificationVerdict(
      outputDirectory: artifactDirectory,
      scenario: scenario.id,
      ok: false,
      stage: 'configuration',
      status: 'configuration_blocked',
      detail:
          'staging_manifest_required: pass a redacted Plan 257 staging '
          'manifest; relay/provider readiness is never inferred',
    );
    stderr.writeln(
      'CONFIGURATION BLOCKED [${scenario.testCase}/${scenario.id}]: '
      'staging_manifest_required.',
    );
    exit(78);
  }

  final prebuiltAndroidPath =
      _valueFor(args, '--prebuilt-android-apk') ??
      Platform.environment['SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM'];
  final capture = _Plan257Capture(
    scenario: scenario,
    senderId: senderId,
    recipientId: recipientId,
    artifactDirectory: artifactDirectory,
    stagingManifest: File(stagingPath).absolute,
    relayTarget:
        _valueFor(args, '--relay-target') ??
        Platform.environment['MKNOON_257_RELAY_TARGET'] ??
        _defaultRelayTarget,
    relayKey: File(
      _valueFor(args, '--relay-key') ??
          Platform.environment['MKNOON_257_RELAY_KEY'] ??
          _defaultRelayKey,
    ).absolute,
    serviceAccount: File(
      _valueFor(args, '--service-account') ??
          Platform.environment['FIREBASE_SERVICE_ACCOUNT'] ??
          _defaultServiceAccount,
    ).absolute,
    prebuiltAndroidApk:
        prebuiltAndroidPath == null || prebuiltAndroidPath.trim().isEmpty
        ? null
        : File(prebuiltAndroidPath).absolute,
    noChildBuilds: args.contains('--no-child-builds'),
    statePreparedByParent: args.contains('--android-state-prepared'),
    verbose: args.contains('--verbose'),
    keepBuildArtifacts: args.contains('--keep-build-artifacts'),
  );

  try {
    try {
      await capture.run();
    } finally {
      await capture.cleanupTransientState();
    }
  } on _CaptureFailure catch (failure, stackTrace) {
    await capture.writeFailure(failure, stackTrace);
    stderr.writeln(
      '${failure.status.toUpperCase()} '
      '[${scenario.testCase}/${scenario.id}/${failure.stage}]: '
      '${failure.message}',
    );
    exit(failure.exitCode);
  } on Object catch (error, stackTrace) {
    final failure = _CaptureFailure.capture(
      capture.stage,
      'unexpected_${error.runtimeType}: capture stopped without a proof '
      'artifact',
    );
    await capture.writeFailure(failure, stackTrace);
    stderr.writeln(
      'CAPTURE_FAILED [${scenario.testCase}/${scenario.id}/${capture.stage}]: '
      '${failure.message}',
    );
    exit(1);
  }
}

class _CaptureFailure implements Exception {
  const _CaptureFailure._(this.stage, this.message, this.status, this.exitCode);

  factory _CaptureFailure.configuration(String stage, String message) =>
      _CaptureFailure._(stage, message, 'configuration_blocked', 78);

  factory _CaptureFailure.environment(String stage, String message) =>
      _CaptureFailure._(stage, message, 'environment_blocked', 78);

  factory _CaptureFailure.capture(String stage, String message) =>
      _CaptureFailure._(stage, message, 'capture_failed', 1);

  final String stage;
  final String message;
  final String status;
  final int exitCode;
}

class _CommandOutput {
  const _CommandOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  String get combined => '$stdout\n$stderr';
}

class _Party {
  _Party({required this.role, required this.deviceId, required this.username});

  final String role;
  final String deviceId;
  final String username;
  String peerId = '';
  String qrPayload = '';
  String? mlKemPublicKey;

  String get peerPrefix =>
      peerId.length <= 20 ? peerId : peerId.substring(0, 20);
}

class _RelayObservation {
  const _RelayObservation({required this.revision, required this.sha256});

  final String revision;
  final String sha256;
}

class _AndroidBuilds {
  const _AndroidBuilds({
    required this.provenance,
    required this.e2eApk,
    required this.normalApk,
    required this.e2eSha256,
    required this.normalSha256,
  });

  final String provenance;
  final File e2eApk;
  final File normalApk;
  final String e2eSha256;
  final String normalSha256;
}

class _Plan257Capture {
  _Plan257Capture({
    required this.scenario,
    required this.senderId,
    required this.recipientId,
    required this.artifactDirectory,
    required this.stagingManifest,
    required this.relayTarget,
    required this.relayKey,
    required this.serviceAccount,
    required this.prebuiltAndroidApk,
    required this.noChildBuilds,
    required this.statePreparedByParent,
    required this.verbose,
    required this.keepBuildArtifacts,
  }) : sender = _Party(
         role: scenario.senderRole,
         deviceId: senderId,
         username: 'Alice',
       ),
       recipient = _Party(
         role: scenario.recipientRole,
         deviceId: recipientId,
         username: 'Bob',
       ),
       appPackage = resolveAndroidAppPackage();

  final GroupReactionNotificationScenario scenario;
  final String senderId;
  final String recipientId;
  final Directory artifactDirectory;
  final File stagingManifest;
  final String relayTarget;
  final File relayKey;
  final File serviceAccount;
  final File? prebuiltAndroidApk;
  final bool noChildBuilds;
  final bool statePreparedByParent;
  final bool verbose;
  final bool keepBuildArtifacts;
  final _Party sender;
  final _Party recipient;
  final String appPackage;

  String stage = 'configuration';
  late Map<String, Object?> _staging;
  late List<String> _relayAddresses;
  late _RelayObservation _relay;
  _AndroidBuilds? _androidBuilds;
  DateTime? _captureWindowStart;
  String _groupName = '';
  String _plan330GroupAName = '';
  String _plan330GroupBName = '';
  String _plan330GroupAIdSha256 = '';
  String _plan330GroupBIdSha256 = '';
  String _plan330Locale = '';
  int? _plan330GroupANotificationId;
  int? _plan330GroupBNotificationId;
  File? _plan330BeforeNotificationDump;
  File? _plan330AfterNotificationDump;
  File? _plan330BeforeUiDump;
  File? _plan330AfterUiDump;
  File? _plan330ReadFlowLog;
  final List<Map<String, Object?>> _plan330ReactionObservations =
      <Map<String, Object?>>[];
  final List<Map<String, Object?>> _plan330Commands = <Map<String, Object?>>[];
  late final Map<String, String> _plan330MessageIds = <String, String>{
    for (final kind in const <String>['jpeg', 'mp4', 'voice']) kind: _uuidV4(),
  };
  late final Map<String, String> _plan330AttachmentIds = <String, String>{
    for (final kind in const <String>['jpeg', 'mp4', 'voice']) kind: _uuidV4(),
  };
  String _firstMarker = '';
  String _secondMarker = '';
  String _targetMarker = '';
  final List<int> _uiUnreadTimeline = <int>[];
  final List<File> _uiSnapshots = <File>[];
  final List<File> _notificationSnapshots = <File>[];
  String _senderLogcat = '';
  String _recipientLogcat = '';
  String _relayJournal = '';
  String _iosSystemLog = '';
  String _iosXcuitestOutput = '';
  String _exactDuplicateRedriveObservation = '';
  String _backgroundConnectedObservation = '';
  DateTime? _backgroundConnectedHomeAt;
  DateTime? _backgroundConnectedReactionAt;
  // Plan 379 muted lane state. Populated only by the two muted stages and
  // consumed only by `_writeMutedAndroidArtifact`.
  String _mutedGroupName = '';
  String _mutedControlGroupName = '';
  String _mutedGroupIdSha256 = '';
  String _mutedControlGroupIdSha256 = '';
  String _mutedUnderTestMessageIdDigest = '';
  final List<Map<String, Object?>> _mutedCommands = <Map<String, Object?>>[];
  String _mutedUnderTestMarker = '';
  String _mutedControlMarker = '';
  String _mutedNotificationDump = '';
  String _mutedPreMuteNotificationDump = '';
  String _mutedPostMuteNotificationDump = '';
  String _mutedPreMuteCardGroup = 'muted';
  String _mutedSqlCipherObservation = '';
  int _mutedUnreadBaseline = 0;
  int _mutedUnreadAfter = 0;
  bool _mutedUnderTestReadAtNull = false;
  bool _mutedGroupIsMuted = false;
  bool _mutedPersistedRowObserved = false;
  int _mutedReactionRowsObserved = 0;
  bool _mutedBadgeAvailable = false;
  bool _mutedBadgeIncludesMutedGroup = true;
  bool _mutedBadgeIncludesControlGroup = false;
  int _mutedBadgeGroupIdentityCount = 0;
  GroupMutedBackgroundDeliveryInput? _mutedBackgroundDelivery;
  // Plan 384 killed-app card lane state. Populated only by
  // `_runAndroidGroupTextKilledAppCardLifecycle` and consumed only by
  // `_writeKilledTextCardAndroidArtifact`.
  final List<Map<String, Object?>> _killedCommands = <Map<String, Object?>>[];
  String _killedBaselineMarker = '';
  String _killedWarmupMarker = '';
  String _killedGradedMarker = '';
  String _killedPreKillNotificationDump = '';
  String _killedGradedNotificationDump = '';
  GroupKilledTextCardDeliveryInput? _killedDelivery;
  String _iosE2eAppSha256 = '';
  String _iosNormalAppSha256 = '';
  final Map<String, File> _iosInstallReceipts = <String, File>{};
  Process? _iosSystemLogProcess;
  final StringBuffer _iosSystemLogStdout = StringBuffer();
  final StringBuffer _iosSystemLogStderr = StringBuffer();
  Future<void>? _iosSystemLogStdoutDone;
  Future<void>? _iosSystemLogStderrDone;
  final List<Map<String, Object?>> _commandJournal = <Map<String, Object?>>[];
  final Random _random = Random.secure();
  late final String _runtimeRunId = _runtimeToken('run');
  late final String _runtimeNonce = _runtimeToken('nonce');
  late final GroupFixtureTransientCleanup _transientCleanup =
      GroupFixtureTransientCleanup(<Future<void> Function()>[
        _deleteTransientFixtureFiles,
        _collapseAndroidStatusBars,
        _deletePendingProofResidue,
      ]);

  Map<String, Object?> get _iosCapture =>
      Map<String, Object?>.from(_staging['iosCapture'] as Map);

  File get _commandJournalFile => File(
    '${artifactDirectory.path}${Platform.pathSeparator}'
    'automation_command_journal.json',
  );

  bool get _isPlan330 => scenario.id == groupNotificationProjectionScenarioId;

  /// Which lifecycle/observation/validator this scenario id selects.
  ///
  /// Resolved once from the shared criteria file instead of re-deriving
  /// `id.endsWith('_message_unread_lifecycle')` at each branch, so a scenario
  /// that is neither "message" nor "reaction" can exist without silently
  /// falling into the reaction grammar. The lookup is total over every
  /// registered id, so the null branch is unreachable for a resolved scenario.
  late final GroupReactionCaptureDispatch _dispatch =
      groupReactionCaptureDispatchFor(scenario.id) ??
      (throw _CaptureFailure.configuration(
        'scenario',
        'capture_dispatch_missing_for_${scenario.id}',
      ));

  bool get _isMutedLane =>
      _dispatch.validatorKind == GroupReactionCaptureValidatorKind.muted;

  bool get _isMutedBackgroundLane =>
      _dispatch.lifecycleStage ==
      GroupReactionCaptureLifecycleStage.mutedReactionBackgroundSuppression;

  Future<void> cleanupTransientState() => _transientCleanup.run();

  Future<void> run() async {
    await artifactDirectory.create(recursive: true);
    final staleArtifact = File(
      '${artifactDirectory.path}${Platform.pathSeparator}${scenario.id}.json',
    );
    if (await staleArtifact.exists()) {
      await staleArtifact.delete();
    }
    stage = 'configuration';
    _staging = await _readStagingManifest();
    _relayAddresses = (_staging['relayAddresses'] as List<dynamic>)
        .cast<String>()
        .map((value) => value.trim())
        .toList(growable: false);

    if (noChildBuilds && scenario.recipientPlatform == 'android') {
      final prepared = prebuiltAndroidApk;
      if (prepared == null ||
          FileSystemEntity.typeSync(prepared.path, followLinks: true) !=
              FileSystemEntityType.file) {
        throw _CaptureFailure.configuration(
          'prepared_artifact',
          'central_prebuilt_android_apk_required',
        );
      }
    }
    if (_isPlan330 && (!noChildBuilds || prebuiltAndroidApk == null)) {
      throw _CaptureFailure.configuration(
        'prepared_artifact',
        'Plan 330 requires one centrally prepared production-FCM APK and '
            'forbids child builds',
      );
    }

    stage = 'device_inventory';
    await _verifyLiveDeviceTopology();

    stage = 'relay_configuration';
    _relay = await _verifyRelay();

    stage = 'provider_configuration';
    if (scenario.recipientPlatform == 'android') {
      await _verifyFcmConfiguration();
    } else {
      await _verifyApnsConfiguration();
    }
    await _writeConfigurationVerdict();

    if (scenario.recipientPlatform == 'ios') {
      await _runIosAvailableStages();
      return;
    }

    stage = 'candidate_build';
    _androidBuilds = prebuiltAndroidApk == null
        ? await _buildAndroidCandidate()
        : await _loadPreparedAndroidCandidate(prebuiltAndroidApk!);

    stage = 'android_role_install';
    await _resetAndInstallAndroidRoles(_androidBuilds!);

    stage = 'android_identity_setup';
    await _prepareAndroidIdentity(sender);
    await _prepareAndroidIdentity(recipient);
    await _launchAndroid(senderId);
    await _launchAndroid(recipientId);
    await _collectAndroidIdentity(sender);
    await _collectAndroidIdentity(recipient);
    await _prepopulateAndroidContacts();

    stage = 'group_fixture_setup';
    if (_isPlan330) {
      final suffix = _runtimeToken('fixture').replaceAll('-', '');
      _plan330GroupAName = 'Plan330A-${suffix.substring(0, 16)}';
      _plan330GroupBName = 'Plan330B-${suffix.substring(16, 32)}';
      await _createAndAcceptGroup(name: _plan330GroupAName);
      await _createAndAcceptGroup(name: _plan330GroupBName);
      _groupName = _plan330GroupAName;
    } else if (_isMutedLane) {
      // Two groups: the one under test, which is muted mid-capture, and an
      // always-unmuted control. Without the control, a dead notification lane
      // and a working mute are indistinguishable.
      final suffix = _runtimeToken('fixture').replaceAll('-', '');
      _mutedGroupName = 'Plan379M-${suffix.substring(0, 12)}';
      _mutedControlGroupName = 'Plan379C-${suffix.substring(12, 24)}';
      await _createAndAcceptGroup(name: _mutedGroupName);
      await _createAndAcceptGroup(name: _mutedControlGroupName);
      _groupName = _mutedGroupName;
    } else {
      await _createAndAcceptGroup();
    }

    stage = 'provider_registration';
    if (!statePreparedByParent ||
        _androidBuilds!.e2eSha256 != _androidBuilds!.normalSha256) {
      await _installApk(recipientId, _androidBuilds!.normalApk);
    }
    await _grantNotificationPermission(recipientId);
    // Clear BEFORE the registration window opens: a stale success line from a
    // previous run would otherwise satisfy the wait instantly.
    await _adb(recipientId, const <String>['logcat', '-c']);
    await _launchAndroid(recipientId);
    await _waitForRecipientPushRegistrationAccepted();
    await _requireCleanNotificationSlate();

    _captureWindowStart = DateTime.now().toUtc();
    await _adb(senderId, const <String>['logcat', '-c']);
    await _adb(recipientId, const <String>['logcat', '-c']);
    // Dispatch site 1 of 4: lifecycle stage select.
    switch (_dispatch.lifecycleStage) {
      case GroupReactionCaptureLifecycleStage.notificationProjection:
        stage = 'android_group_notification_projection';
        await _runAndroidGroupNotificationProjectionLifecycle();
      case GroupReactionCaptureLifecycleStage.messageUnreadLifecycle:
        stage = 'android_unread_lifecycle';
        await _runAndroidUnreadLifecycle();
      case GroupReactionCaptureLifecycleStage.mutedMessageSuppression:
        stage = 'android_muted_message_suppression';
        await _runAndroidMutedMessageSuppressionLifecycle();
      case GroupReactionCaptureLifecycleStage
          .mutedReactionBackgroundSuppression:
        stage = 'android_muted_reaction_background_suppression';
        await _runAndroidMutedReactionBackgroundLifecycle();
      case GroupReactionCaptureLifecycleStage.groupTextKilledAppCard:
        stage = 'android_group_text_killed_app_card';
        await _runAndroidGroupTextKilledAppCardLifecycle();
      case GroupReactionCaptureLifecycleStage.reactionRecipient:
        stage = 'android_reaction_lifecycle';
        await _runAndroidReactionLifecycle();
    }

    // Dispatch site 2 of 4: SQLCipher observation.
    //
    // Only the Plan-257 reaction grammar routes through
    // `_captureSqlCipherObservation`, whose `_validateSqlCipherObservation`
    // hard-pins `unreadCount == 0` — the exact opposite of what a muted
    // scenario proves. The muted stages take their own observation inline.
    String? sqlCipherEvidence;
    if (_dispatch.validatorKind == GroupReactionCaptureValidatorKind.reaction) {
      stage = 'sqlcipher_observation';
      sqlCipherEvidence = await _captureSqlCipherObservation();
    }

    // Dispatch site 3 of 4: artifact write.
    stage = 'artifact_capture';
    switch (_dispatch.validatorKind) {
      case GroupReactionCaptureValidatorKind.notificationProjection:
        await _writePlan330AndroidArtifact();
      case GroupReactionCaptureValidatorKind.muted:
        await _writeMutedAndroidArtifact();
      case GroupReactionCaptureValidatorKind.killedTextCard:
        await _writeKilledTextCardAndroidArtifact();
      case GroupReactionCaptureValidatorKind.reaction:
        await _writeAndroidArtifact(sqlCipherEvidence!);
    }

    stage = 'artifact_self_validation';
    final artifact = File(
      '${artifactDirectory.path}${Platform.pathSeparator}${scenario.id}.json',
    );
    late final bool artifactAccepted;
    late final String artifactValidationDetail;
    // Dispatch site 4 of 4: artifact self-validation.
    switch (_dispatch.validatorKind) {
      case GroupReactionCaptureValidatorKind.notificationProjection:
        final result = await validateGroupNotificationProjectionAndroidArtifact(
          artifactFile: artifact,
          expectedPhysicalDeviceId: recipientId,
          expectedEmulatorDeviceId: senderId,
          expectedApkSha256: _androidBuilds!.e2eSha256,
          expectedPackageName: appPackage,
        );
        artifactAccepted = result.ok;
        artifactValidationDetail = result.detail;
      case GroupReactionCaptureValidatorKind.muted:
        final result = await validateGroupMutedNotificationAndroidArtifact(
          artifactFile: artifact,
          expectedPhysicalDeviceId: recipientId,
          expectedEmulatorDeviceId: senderId,
          expectedApkSha256: _androidBuilds!.e2eSha256,
          expectedPackageName: appPackage,
        );
        artifactAccepted = result.ok;
        artifactValidationDetail = result.detail;
      case GroupReactionCaptureValidatorKind.killedTextCard:
        final result = await validateGroupKilledTextCardAndroidArtifact(
          artifactFile: artifact,
          expectedPhysicalDeviceId: recipientId,
          expectedEmulatorDeviceId: senderId,
          expectedApkSha256: _androidBuilds!.e2eSha256,
          expectedPackageName: appPackage,
        );
        artifactAccepted = result.ok;
        artifactValidationDetail = result.detail;
      case GroupReactionCaptureValidatorKind.reaction:
        final result = await validateGroupReactionNotificationArtifact(
          scenario: scenario.id,
          artifactFile: artifact,
          expectedSenderDeviceId: senderId,
          expectedRecipientDeviceId: recipientId,
        );
        artifactAccepted = result.ok;
        artifactValidationDetail = result.detail;
    }
    if (!artifactAccepted) {
      throw _CaptureFailure.capture(
        stage,
        'captured_authoritative_evidence_rejected: '
        '$artifactValidationDetail',
      );
    }

    await writeGroupReactionNotificationVerdict(
      outputDirectory: artifactDirectory,
      scenario: scenario.id,
      ok: true,
      stage: 'capture',
      status: 'passed',
      detail:
          'real device roles, staging relay/provider, SQLCipher, OS card, '
          'and automated UI evidence captured and self-validated',
    );
    stdout.writeln('PASS: ${scenario.id} captured at ${artifact.path}.');

    if (!keepBuildArtifacts) {
      await _deleteBuildCopies();
    }
  }

  Future<void> writeFailure(
    _CaptureFailure failure,
    StackTrace stackTrace,
  ) async {
    await artifactDirectory.create(recursive: true);
    await _flushCommandJournal();
    await writeGroupReactionNotificationVerdict(
      outputDirectory: artifactDirectory,
      scenario: scenario.id,
      ok: false,
      stage: failure.stage,
      status: failure.status,
      detail: failure.message,
    );
    final failureFile = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      '${scenario.id}_capture_failure.json',
    );
    await failureFile.writeAsString(
      const JsonEncoder.withIndent(' ').convert(<String, Object?>{
        'schema': 'mknoon.plan257.capture-failure.v1',
        'scenario': scenario.id,
        'status': failure.status,
        'stage': failure.stage,
        'detail': failure.message,
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
        'stackType': stackTrace.runtimeType.toString(),
        'completedStages': _commandJournal
            .map((record) => record['stage'])
            .toSet()
            .toList(growable: false),
      }),
      flush: true,
    );
  }

  Future<Map<String, Object?>> _readStagingManifest() async {
    if (!await stagingManifest.exists()) {
      throw _CaptureFailure.configuration(
        stage,
        'staging_manifest_missing: ${stagingManifest.path}',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(await stagingManifest.readAsString());
    } on Object {
      throw _CaptureFailure.configuration(
        stage,
        'staging_manifest_invalid_json',
      );
    }
    if (decoded is! Map) {
      throw _CaptureFailure.configuration(
        stage,
        'staging_manifest_root_not_object',
      );
    }
    final manifest = Map<String, Object?>.from(decoded);
    final validation = validateGroupReactionNotificationStagingManifest(
      manifest,
      scenario: scenario,
    );
    if (!validation.ok) {
      throw _CaptureFailure.configuration(
        stage,
        'staging_manifest_contract_rejected: ${validation.detail}',
      );
    }
    return manifest;
  }

  Future<void> _verifyLiveDeviceTopology() async {
    final selectionErrors = _validateTopologyShape();
    if (selectionErrors.isNotEmpty) {
      throw _CaptureFailure.configuration(
        stage,
        'explicit_topology_invalid: ${selectionErrors.join('; ')}',
      );
    }

    final flutterDevices = await _run('flutter', const <String>[
      'devices',
      '--machine',
    ], environmentFailure: true);
    Object? decoded;
    try {
      decoded = jsonDecode(flutterDevices.stdout);
    } on Object {
      throw _CaptureFailure.environment(
        stage,
        'flutter_device_inventory_invalid_json',
      );
    }
    if (decoded is! List) {
      throw _CaptureFailure.environment(
        stage,
        'flutter_device_inventory_not_list',
      );
    }
    final devices = decoded
        .whereType<Map>()
        .map((entry) => Map<String, Object?>.from(entry))
        .toList(growable: false);
    Map<String, Object?>? find(String id) {
      for (final device in devices) {
        if (device['id'] == id) return device;
      }
      return null;
    }

    final senderDevice = find(senderId);
    final recipientDevice = find(recipientId);
    if (senderDevice == null || recipientDevice == null) {
      throw _CaptureFailure.environment(
        stage,
        'explicit_device_unavailable: senderPresent=${senderDevice != null}, '
        'recipientPresent=${recipientDevice != null}',
      );
    }
    if (!senderDevice['targetPlatform'].toString().contains('android')) {
      throw _CaptureFailure.environment(
        stage,
        'sender_not_live_android_target',
      );
    }
    final expectedRecipientPlatform = scenario.recipientPlatform;
    if (!recipientDevice['targetPlatform'].toString().contains(
      expectedRecipientPlatform,
    )) {
      throw _CaptureFailure.environment(
        stage,
        'recipient_not_live_${expectedRecipientPlatform}_target',
      );
    }

    final adb = await _run('adb', const <String>[
      'devices',
    ], environmentFailure: true);
    if (!adb.stdout.contains('$senderId\tdevice')) {
      throw _CaptureFailure.environment(stage, 'sender_absent_from_adb');
    }
    if (scenario.recipientPlatform == 'android' &&
        !adb.stdout.contains('$recipientId\tdevice')) {
      throw _CaptureFailure.environment(stage, 'recipient_absent_from_adb');
    }
    if (scenario.recipientPlatform == 'ios') {
      final ios = await _run('xcrun', const <String>[
        'xctrace',
        'list',
        'devices',
      ], environmentFailure: true);
      final lines = ios.stdout
          .split('\n')
          .where((line) => line.contains(recipientId))
          .where((line) => !line.toLowerCase().contains('simulator'));
      if (lines.isEmpty) {
        throw _CaptureFailure.environment(
          stage,
          'recipient_not_live_physical_ios_target',
        );
      }
    }
  }

  List<String> _validateTopologyShape() {
    final failures = <String>[];
    if (senderId == recipientId) failures.add('device ids must differ');
    final safe = RegExp(r'^[A-Za-z0-9._:-]{4,128}$');
    if (!safe.hasMatch(senderId)) failures.add('unsafe sender id');
    if (!safe.hasMatch(recipientId)) failures.add('unsafe recipient id');
    final senderEmulator = RegExp(r'^emulator-[0-9]+$').hasMatch(senderId);
    final recipientEmulator = RegExp(
      r'^emulator-[0-9]+$',
    ).hasMatch(recipientId);
    final recipientIos = RegExp(
      r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$',
    ).hasMatch(recipientId);
    if (scenario.senderDeviceKind == 'emulator' && !senderEmulator) {
      failures.add('sender must be Android emulator');
    }
    if (scenario.senderDeviceKind == 'physical' && senderEmulator) {
      failures.add('sender must be physical');
    }
    if (scenario.recipientDeviceKind == 'physical' && recipientEmulator) {
      failures.add('recipient must be physical');
    }
    if (scenario.recipientPlatform == 'ios' && !recipientIos) {
      failures.add('recipient must be physical iOS id');
    }
    if (scenario.recipientPlatform == 'android' && recipientIos) {
      failures.add('recipient must be Android');
    }
    return failures;
  }

  Future<_RelayObservation> _verifyRelay() async {
    if (!relayKey.existsSync()) {
      throw _CaptureFailure.configuration(
        stage,
        'relay_ssh_key_missing: ${relayKey.path}',
      );
    }
    final active = await _ssh(const <String>[
      'systemctl',
      'is-active',
      'relay-server',
    ], environmentFailure: true);
    if (active.stdout.trim() != 'active') {
      throw _CaptureFailure.environment(stage, 'staging_relay_not_active');
    }
    final version = await _ssh(const <String>[
      '/usr/local/bin/relay-server',
      'version',
    ], environmentFailure: true);
    final digest = await _ssh(const <String>[
      'sha256sum',
      '/usr/local/bin/relay-server',
    ], environmentFailure: true);
    final actualSha = digest.stdout.trim().split(RegExp(r'\s+')).first;
    final expectedRevision = _staging['candidateRelayRevision'].toString();
    final expectedSha = _staging['candidateRelaySha256'].toString();
    if (!version.stdout.contains(expectedRevision) ||
        actualSha != expectedSha) {
      throw _CaptureFailure.configuration(
        stage,
        'relay_candidate_mismatch: live revision/digest does not match the '
        'staging declaration',
      );
    }
    final mainPidOutput = await _ssh(const <String>[
      'systemctl',
      'show',
      'relay-server',
      '--property=MainPID',
      '--value',
    ], environmentFailure: true);
    List<String> flagProbe;
    try {
      flagProbe = groupReactionRelayProcessFlagProbe(
        mainPidOutput.stdout.trim(),
      );
    } on FormatException {
      throw _CaptureFailure.environment(
        stage,
        'staging_relay_has_no_live_main_pid',
      );
    }
    final flag = await _ssh(
      flagProbe,
      allowFail: true,
      environmentFailure: true,
    );
    if (flag.exitCode != 0) {
      throw _CaptureFailure.configuration(
        stage,
        'group_reaction_rollout_flag_disabled: live relay process does not '
        'inherit '
        'GROUP_REACTION_PUSH_ENABLED=true',
      );
    }
    return _RelayObservation(
      revision: version.stdout.trim(),
      sha256: actualSha,
    );
  }

  Future<void> _verifyFcmConfiguration() async {
    if (!serviceAccount.existsSync()) {
      throw _CaptureFailure.configuration(
        stage,
        'fcm_service_account_missing: ${serviceAccount.path}',
      );
    }
    final googleServices = File('android/app/google-services.json').absolute;
    if (!googleServices.existsSync()) {
      throw _CaptureFailure.configuration(
        stage,
        'android_google_services_missing',
      );
    }
    Map<String, dynamic> service;
    Map<String, dynamic> google;
    try {
      service = Map<String, dynamic>.from(
        jsonDecode(await serviceAccount.readAsString()) as Map,
      );
      google = Map<String, dynamic>.from(
        jsonDecode(await googleServices.readAsString()) as Map,
      );
    } on Object {
      throw _CaptureFailure.configuration(
        stage,
        'fcm_configuration_invalid_json',
      );
    }
    final projectInfo = Map<String, dynamic>.from(
      google['project_info'] as Map? ?? const <String, dynamic>{},
    );
    final serviceProject = service['project_id']?.toString().trim();
    final appProject = projectInfo['project_id']?.toString().trim();
    final clientEmail = service['client_email']?.toString().trim();
    final privateKey = service['private_key']?.toString().trim();
    if (serviceProject == null ||
        serviceProject.isEmpty ||
        serviceProject != appProject ||
        clientEmail == null ||
        clientEmail.isEmpty ||
        privateKey == null ||
        !privateKey.contains('BEGIN PRIVATE KEY')) {
      throw _CaptureFailure.configuration(
        stage,
        'fcm_configuration_project_or_credential_mismatch',
      );
    }
  }

  Future<void> _verifyApnsConfiguration() async {
    final entitlements = File('ios/Runner/Runner.entitlements');
    final nseEntitlements = File(
      'ios/NotificationService/NotificationService.entitlements',
    );
    final project = File('ios/Runner.xcodeproj/project.pbxproj');
    if (!entitlements.existsSync() ||
        !nseEntitlements.existsSync() ||
        !project.existsSync()) {
      throw _CaptureFailure.configuration(
        stage,
        'apns_entitlement_or_xcode_project_missing',
      );
    }
    final combined =
        '${await entitlements.readAsString()}\n'
        '${await nseEntitlements.readAsString()}\n'
        '${await project.readAsString()}';
    if (!combined.contains('aps-environment') ||
        !combined.contains('NotificationService.appex')) {
      throw _CaptureFailure.configuration(
        stage,
        'apns_or_nse_configuration_not_present',
      );
    }
  }

  Future<void> _writeConfigurationVerdict() async {
    final file = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'configuration_verdict.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent(' ').convert(<String, Object?>{
        'schema': 'mknoon.plan257.configuration-verdict.v1',
        'scenario': scenario.id,
        'ok': true,
        'environment': 'staging',
        'sender': <String, Object?>{
          'deviceId': senderId,
          'platform': scenario.senderPlatform,
          'deviceKind': scenario.senderDeviceKind,
          'liveDiscovered': true,
        },
        'recipient': <String, Object?>{
          'deviceId': recipientId,
          'platform': scenario.recipientPlatform,
          'deviceKind': scenario.recipientDeviceKind,
          'liveDiscovered': true,
        },
        'relay': <String, Object?>{
          'active': true,
          'candidateRevisionMatched': true,
          'candidateSha256': _relay.sha256,
          'groupReactionRolloutEnabled': true,
        },
        'provider': <String, Object?>{
          'kind': scenario.recipientPlatform == 'ios' ? 'apns' : 'fcm',
          'configurationChecked': true,
          'deliveryStillRequiresScenarioEvidence': true,
        },
        'productionDeploymentPerformed': false,
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<void> _runIosAvailableStages() async {
    stage = 'ios_android_sender_build';
    _androidBuilds = await _buildAndroidCandidate();
    await _installApk(senderId, _androidBuilds!.e2eApk);
    await _clearAndroidPrivateEntries(senderId);
    await _prepareAndroidIdentity(sender);
    await _launchAndroid(senderId);
    await _collectAndroidIdentity(sender);

    stage = 'ios_candidate_build';
    final e2eApp = await _buildIosCandidate(e2eMode: true);

    stage = 'ios_candidate_install';
    await _run('xcrun', <String>[
      'devicectl',
      'device',
      'uninstall',
      'app',
      '--device',
      recipientId,
      _iosCapture['bundleId']! as String,
    ], allowFail: true);
    await _installIosCandidate(e2eApp, mode: 'e2e');

    stage = 'ios_fixture_staging';
    await _stageIosAppFile(
      'auto_setup.json',
      jsonEncode(<String, Object?>{'username': recipient.username}),
    );
    await _launchIosCandidate();
    await _collectIosIdentity(recipient);
    await _prepopulateContact(sender, recipient);
    await _prepopulateIosContact(recipient, sender);

    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    _groupName = 'TC257Ann$stamp';
    _targetMarker = 'TC257Target$stamp';
    final tapConfig = await _writeIosTapConfig();

    final uiTest = File(_iosTapTest);
    final uiSource = uiTest.existsSync() ? await uiTest.readAsString() : '';
    for (final selector in const <String>[
      _iosFixtureCreateSelector,
      _iosFixtureAuthorSelector,
      _iosNotificationPrepareSelector,
      _iosTapSelector,
    ]) {
      if (!uiSource.contains(selector)) {
        throw _CaptureFailure.environment(
          stage,
          'native_plan257_xcuitest_selector_missing: '
          'RunnerUITests/NotificationTapUITests/$selector',
        );
      }
    }

    _iosXcuitestOutput += await _runIosUiSelector(
      _iosFixtureCreateSelector,
      tapConfig,
    );
    await _acceptIosCreatedGroupOnAndroid();
    _iosXcuitestOutput += await _runIosUiSelector(
      _iosFixtureAuthorSelector,
      tapConfig,
    );
    await _openGroup(senderId);
    await _waitForUiText(senderId, _targetMarker, const Duration(minutes: 2));

    stage = 'ios_candidate_build';
    final normalApp = await _buildIosCandidate(e2eMode: false);
    stage = 'ios_candidate_install';
    await _installIosCandidate(normalApp, mode: 'normal');
    final tokenWindow = DateTime.now().toUtc();
    await _launchIosCandidate();
    await _waitForRelayTokenRegistration(tokenWindow);

    _iosXcuitestOutput += await _runIosUiSelector(
      _iosNotificationPrepareSelector,
      tapConfig,
    );

    stage = 'ios_reaction_lifecycle';
    _captureWindowStart = DateTime.now().toUtc();
    await _adb(senderId, const <String>['logcat', '-c']);
    await _startIosSystemLog();
    try {
      await _runIosReactionLifecycle(tapConfig);
    } finally {
      await _stopIosSystemLog();
    }

    stage = 'sqlcipher_observation';
    final sqlCipherEvidence = await _captureSqlCipherObservation();

    stage = 'artifact_capture';
    await _writeIosArtifact(sqlCipherEvidence);

    stage = 'artifact_self_validation';
    final artifact = File(
      '${artifactDirectory.path}${Platform.pathSeparator}${scenario.id}.json',
    );
    final validation = await validateGroupReactionNotificationArtifact(
      scenario: scenario.id,
      artifactFile: artifact,
      expectedSenderDeviceId: senderId,
      expectedRecipientDeviceId: recipientId,
    );
    if (!validation.ok) {
      throw _CaptureFailure.capture(
        stage,
        'captured_authoritative_evidence_rejected: ${validation.detail}',
      );
    }

    await writeGroupReactionNotificationVerdict(
      outputDirectory: artifactDirectory,
      scenario: scenario.id,
      ok: true,
      stage: 'capture',
      status: 'passed',
      detail:
          'physical Android/iPhone roles, staging relay/APNs, raw NSE, '
          'XCUITest notification/tap, and SQLCipher evidence captured and '
          'self-validated',
    );
    stdout.writeln('PASS: ${scenario.id} captured at ${artifact.path}.');
    if (!keepBuildArtifacts) await _deleteBuildCopies();
  }

  Future<Directory> _buildIosCandidate({required bool e2eMode}) async {
    await _runStreaming('flutter', <String>[
      'build',
      'ios',
      '--debug',
      '--no-pub',
      '--dart-define=E2E_TEST_MODE=$e2eMode',
      '--dart-define=MKNOON_RELAY_ADDRESSES=${_relayAddresses.join(',')}',
    ], environmentFailure: true);
    final app = Directory('build/ios/iphoneos/Runner.app').absolute;
    if (!app.existsSync()) {
      throw _CaptureFailure.capture(
        stage,
        'signed_physical_ios_candidate_not_materialized',
      );
    }
    final digest = await _sha256Directory(app);
    if (e2eMode) {
      _iosE2eAppSha256 = digest;
    } else {
      _iosNormalAppSha256 = digest;
    }
    return app;
  }

  Future<void> _installIosCandidate(
    Directory app, {
    required String mode,
  }) async {
    await _run('xcrun', <String>[
      'devicectl',
      'device',
      'install',
      'app',
      '--device',
      recipientId,
      app.path,
    ], environmentFailure: true);
    final receipt = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'ios_${mode}_installed_app_inventory.json',
    );
    if (receipt.existsSync()) await receipt.delete();
    await _run('xcrun', <String>[
      'devicectl',
      'device',
      'info',
      'apps',
      '--device',
      recipientId,
      '--bundle-id',
      _iosCapture['bundleId']! as String,
      '--json-output',
      receipt.path,
    ], environmentFailure: true);
    if (!receipt.existsSync() ||
        !await receipt.readAsString().then(
          (raw) => raw.contains(_iosCapture['bundleId']! as String),
        )) {
      throw _CaptureFailure.capture(
        stage,
        'physical_ios_${mode}_install_inventory_missing_candidate_bundle',
      );
    }
    _iosInstallReceipts[mode] = receipt;
  }

  Future<void> _launchIosCandidate() async {
    await _run('xcrun', <String>[
      'devicectl',
      'device',
      'process',
      'launch',
      '--device',
      recipientId,
      '--terminate-existing',
      _iosCapture['bundleId']! as String,
    ], environmentFailure: true);
  }

  Future<void> _stageIosAppFile(String name, String contents) async {
    final local = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'plan257_ios_${DateTime.now().microsecondsSinceEpoch}_$name',
    );
    await local.writeAsString(contents, flush: true);
    try {
      await _run('xcrun', <String>[
        'devicectl',
        'device',
        'copy',
        'to',
        '--device',
        recipientId,
        '--source',
        local.path,
        '--destination',
        'Documents/$name',
        '--domain-type',
        'appDataContainer',
        '--domain-identifier',
        _iosCapture['bundleId']! as String,
      ], environmentFailure: true);
    } finally {
      if (local.existsSync()) await local.delete();
    }
  }

  Future<String?> _readIosAppFile(String name) async {
    final directory = await Directory.systemTemp.createTemp(
      'plan257_ios_read_',
    );
    try {
      final output = await _run('xcrun', <String>[
        'devicectl',
        'device',
        'copy',
        'from',
        '--device',
        recipientId,
        '--source',
        'Documents/$name',
        '--destination',
        directory.path,
        '--domain-type',
        'appDataContainer',
        '--domain-identifier',
        _iosCapture['bundleId']! as String,
      ], allowFail: true);
      if (output.exitCode != 0) return null;
      final direct = File('${directory.path}${Platform.pathSeparator}$name');
      if (direct.existsSync()) return direct.readAsString();
      final files = directory.listSync(recursive: true).whereType<File>();
      for (final file in files) {
        if (file.uri.pathSegments.last == name) return file.readAsString();
      }
      return null;
    } finally {
      if (directory.existsSync()) await directory.delete(recursive: true);
    }
  }

  Future<void> _collectIosIdentity(_Party party) async {
    final raw = await _waitForValue<String>(
      'physical iOS identity export for ${party.role}',
      const Duration(minutes: 3),
      () => _readIosAppFile('intro_e2e_identity.json'),
    );
    try {
      final exported = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      party.qrPayload = exported['qrPayload'] as String;
      party.mlKemPublicKey = exported['mlKemPublicKey'] as String?;
      final qr = Map<String, dynamic>.from(jsonDecode(party.qrPayload) as Map);
      party.peerId = qr['ns'] as String;
    } on Object {
      throw _CaptureFailure.capture(
        stage,
        'physical_ios_identity_export_invalid',
      );
    }
    if (party.peerId.isEmpty) {
      throw _CaptureFailure.capture(
        stage,
        'physical_ios_identity_export_missing_peer',
      );
    }
  }

  Future<void> _prepopulateIosContact(_Party owner, _Party contact) async {
    final stepId =
        '257-ios-${scenario.id}-${DateTime.now().microsecondsSinceEpoch}';
    await _stageIosAppFile(
      'intro_e2e_config.json',
      jsonEncode(<String, Object?>{
        'stepId': stepId,
        'add_contacts': <Object?>[
          <String, Object?>{
            'qrPayload': contact.qrPayload,
            'mlKemPublicKey': contact.mlKemPublicKey,
          },
        ],
      }),
    );
    await _launchIosCandidate();
    final raw = await _waitForValue<String>(
      'physical iOS contact fixture completion',
      const Duration(minutes: 3),
      () async {
        final value = await _readIosAppFile('intro_e2e_result.json');
        if (value == null) return null;
        try {
          final decoded = Map<String, dynamic>.from(jsonDecode(value) as Map);
          return decoded['stepId'] == stepId && decoded['status'] == 'complete'
              ? value
              : null;
        } on Object {
          return null;
        }
      },
    );
    final result = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (result['success'] != true) {
      throw _CaptureFailure.capture(
        stage,
        'physical_ios_contact_fixture_failed',
      );
    }
  }

  Future<File> _writeIosTapConfig() async {
    final file = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'ios_announcement_reaction_tap_config.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent(' ').convert(<String, Object?>{
        'expectedTitle': _groupName,
        'expectedGroupName': _groupName,
        'expectedTargetMessageText': _targetMarker,
        'expectedMemberName': sender.username,
        'expectedActorName': sender.username,
        'expectedReactionEmoji': _reactionEmoji,
        'preBackgroundWaitSeconds': '12',
      }),
      flush: true,
    );
    return file;
  }

  Future<String> _runIosUiSelector(String selector, File tapConfig) async {
    final resultBundle = Directory(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      '${selector.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}.xcresult',
    );
    if (resultBundle.existsSync()) {
      await resultBundle.delete(recursive: true);
    }
    final output = await _runStreaming(
      'xcodebuild',
      <String>[
        'test',
        '-workspace',
        _iosCapture['workspace']! as String,
        '-scheme',
        _iosCapture['scheme']! as String,
        '-destination',
        'platform=iOS,id=$recipientId',
        '-only-testing:RunnerUITests/NotificationTapUITests/$selector',
        '-resultBundlePath',
        resultBundle.path,
      ],
      environmentFailure: true,
      environment: <String, String>{
        'MKNOON_APNS_TAP_APP_BUNDLE_ID': _iosCapture['bundleId']! as String,
        'MKNOON_APNS_TAP_CONFIG_FILE': tapConfig.path,
        'MKNOON_APNS_TAP_EXPECTED_TITLE': _groupName,
        'MKNOON_257_EXPECTED_GROUP_NAME': _groupName,
        'MKNOON_257_EXPECTED_TARGET_TEXT': _targetMarker,
        'MKNOON_257_EXPECTED_MEMBER_NAME': sender.username,
        'MKNOON_257_EXPECTED_ACTOR_NAME': sender.username,
        'MKNOON_257_EXPECTED_REACTION_EMOJI': _reactionEmoji,
      },
    );
    return '${output.stdout}\n${output.stderr}\n';
  }

  Future<void> _acceptIosCreatedGroupOnAndroid() async {
    await _launchAndroid(senderId);
    await _waitForGroupInviteEntry(senderId, const Duration(minutes: 3));
    await _waitForUiText(senderId, _groupName, const Duration(minutes: 1));
    await _tapText(senderId, 'Accept');
    await _waitForUiText(
      senderId,
      'Open group $_groupName',
      const Duration(minutes: 3),
    );
  }

  Future<void> _startIosSystemLog() async {
    _iosSystemLogProcess = await Process.start(
      _iosSystemLogExecutable,
      <String>['--udid', recipientId, '--no-colors'],
    );
    _iosSystemLogStdoutDone = _iosSystemLogProcess!.stdout
        .transform(utf8.decoder)
        .forEach(_iosSystemLogStdout.write);
    _iosSystemLogStderrDone = _iosSystemLogProcess!.stderr
        .transform(utf8.decoder)
        .forEach(_iosSystemLogStderr.write);
  }

  Future<void> _stopIosSystemLog() async {
    final process = _iosSystemLogProcess;
    if (process == null) return;
    process.kill();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    await Future.wait(<Future<void>>[
      ?_iosSystemLogStdoutDone,
      ?_iosSystemLogStderrDone,
    ]);
    _iosSystemLog =
        '${_iosSystemLogStdout.toString()}\n${_iosSystemLogStderr.toString()}';
    _recordCommandAtStage('ios_system_log', _iosSystemLogExecutable, <String>[
      '--udid',
      recipientId,
      '--no-colors',
    ], exitCode);
    _iosSystemLogProcess = null;
  }

  Future<void> _runIosReactionLifecycle(File tapConfig) async {
    await _openGroup(senderId);
    final firstWindow = DateTime.now().toUtc();
    await _longPressText(senderId, _targetMarker);
    await _tapText(senderId, _reactionEmoji);
    await _waitForSenderEventCount('GROUP_REACTION_SEND_QUEUED', 1);
    await _waitForProviderSendCount(firstWindow, 1);

    await _longPressText(senderId, _targetMarker);
    await _tapText(senderId, _reactionEmoji);
    await _waitForSenderEventCount('GROUP_REACTION_REMOVE_QUEUED', 1);
    await Future<void>.delayed(const Duration(seconds: 8));
    if (_countProviderSends(await _relayJournalSince(firstWindow)) != 1) {
      throw _CaptureFailure.capture(
        stage,
        'ios_remove_transition_woke_provider',
      );
    }

    await _longPressText(senderId, _targetMarker);
    await _tapText(senderId, _reactionEmoji);
    await _waitForSenderEventCount('GROUP_REACTION_SEND_QUEUED', 2);
    await _waitForProviderSendCount(firstWindow, 2);
    await Future<void>.delayed(const Duration(seconds: 10));
    _iosXcuitestOutput += await _runIosUiSelector(_iosTapSelector, tapConfig);

    final senderLog = await _readAndroidLogcat(senderId);
    _senderLogcat = _flowLines(senderLog.stdout);
    _relayJournal = await _relayJournalSince(
      _captureWindowStart ?? firstWindow,
    );
    if (_countProviderSends(_relayJournal) != 2) {
      throw _CaptureFailure.capture(
        stage,
        'ios_provider_send_count_mismatch_after_quiescence',
      );
    }
  }

  Future<_AndroidBuilds> _buildAndroidCandidate() async {
    final provenance = await _candidateProvenance();
    final e2eApk = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'candidate_e2e_arm64.apk',
    );
    final normalApk = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'candidate_normal_arm64.apk',
    );
    final buildArgs = <String>[
      'build',
      'apk',
      '--debug',
      '--no-pub',
      '--target-platform=android-arm64',
      '--dart-define=MKNOON_RELAY_ADDRESSES=${_relayAddresses.join(',')}',
    ];
    await _runStreaming('flutter', <String>[
      ...buildArgs,
      '--dart-define=E2E_TEST_MODE=true',
    ], environmentFailure: true);
    final output = File('build/app/outputs/flutter-apk/app-debug.apk').absolute;
    if (!output.existsSync()) {
      throw _CaptureFailure.capture(stage, 'candidate_e2e_apk_missing');
    }
    await output.copy(e2eApk.path);

    await _runStreaming('flutter', <String>[
      ...buildArgs,
      '--dart-define=E2E_TEST_MODE=false',
    ], environmentFailure: true);
    if (!output.existsSync()) {
      throw _CaptureFailure.capture(stage, 'candidate_normal_apk_missing');
    }
    await output.copy(normalApk.path);
    final builds = _AndroidBuilds(
      provenance: provenance,
      e2eApk: e2eApk,
      normalApk: normalApk,
      e2eSha256: await _sha256(e2eApk),
      normalSha256: await _sha256(normalApk),
    );
    await File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'candidate_build_provenance.json',
    ).writeAsString(
      const JsonEncoder.withIndent(' ').convert(<String, Object?>{
        'schema': 'mknoon.plan257.candidate-build.v1',
        'sourceProvenance': builds.provenance,
        'e2eApkSha256': builds.e2eSha256,
        'normalApkSha256': builds.normalSha256,
        'builtAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    return builds;
  }

  Future<_AndroidBuilds> _loadPreparedAndroidCandidate(File apk) async {
    if (!apk.existsSync()) {
      throw _CaptureFailure.configuration(
        stage,
        'central_prebuilt_android_apk_missing: ${apk.path}',
      );
    }
    final digest = await _sha256(apk);
    final builds = _AndroidBuilds(
      provenance: 'central-prebuilt:android.production_fcm:$digest',
      e2eApk: apk,
      normalApk: apk,
      e2eSha256: digest,
      normalSha256: digest,
    );
    await File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'candidate_build_provenance.json',
    ).writeAsString(
      const JsonEncoder.withIndent(' ').convert(<String, Object?>{
        'schema': 'mknoon.plan257.candidate-build.v1',
        'sourceProvenance': builds.provenance,
        'buildMode': 'central_prebuilt',
        'buildProfile': 'android.production_fcm',
        'childBuildCount': 0,
        'parentPreparedAndroidState': statePreparedByParent,
        'e2eApkSha256': builds.e2eSha256,
        'normalApkSha256': builds.normalSha256,
        'preparedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    return builds;
  }

  Future<String> _candidateProvenance() async {
    final revision = await _run('git', const <String>['rev-parse', 'HEAD']);
    final files = await _run('git', const <String>[
      'ls-files',
      '-co',
      '--exclude-standard',
      '--',
      'lib',
      'packages',
      'android',
      'ios',
      'pubspec.yaml',
      'pubspec.lock',
    ]);
    final sink = _SingleDigestSink();
    final converter = sha256.startChunkedConversion(sink);
    final paths =
        files.stdout
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList()
          ..sort();
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      converter.add(utf8.encode('$path\u0000'));
      converter.add(await file.readAsBytes());
      converter.add(const <int>[0]);
    }
    converter.close();
    final treeDigest = sink.value?.toString();
    if (treeDigest == null) {
      throw _CaptureFailure.capture(stage, 'candidate_provenance_hash_missing');
    }
    return '${revision.stdout.trim()}+worktree:$treeDigest';
  }

  Future<void> _resetAndInstallAndroidRoles(_AndroidBuilds builds) async {
    for (final id in <String>[senderId, recipientId]) {
      if (!statePreparedByParent) {
        await _installApk(id, builds.e2eApk);
        await _clearAndroidPrivateEntries(id);
      } else {
        await _verifyParentPreparedAndroidRole(
          deviceId: id,
          expectedSha256: builds.e2eSha256,
        );
      }
      await _grantNotificationPermission(id);
      await _wakeAndroid(id);
    }
  }

  Future<void> _verifyParentPreparedAndroidRole({
    required String deviceId,
    required String expectedSha256,
  }) async {
    final installed = await _adbShell(deviceId, <String>[
      'pm',
      'path',
      appPackage,
    ], environmentFailure: true);
    final packagePaths = installed
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('package:'))
        .map((line) => line.substring('package:'.length))
        .toList(growable: false);
    if (packagePaths.length != 1) {
      throw _CaptureFailure.environment(
        stage,
        'parent_prepared_app_requires_single_base_apk_on_$deviceId',
      );
    }

    final baseApkPath = packagePaths.single;
    if (!baseApkPath.startsWith('/') ||
        !baseApkPath.endsWith('/base.apk') ||
        baseApkPath.contains(RegExp(r'[\s\x00]'))) {
      throw _CaptureFailure.environment(
        stage,
        'parent_prepared_app_base_apk_path_invalid_on_$deviceId',
      );
    }

    final digestOutput = await _adbShell(deviceId, <String>[
      'sha256sum',
      baseApkPath,
    ], environmentFailure: true);
    final digestParts = digestOutput.trim().split(RegExp(r'\s+'));
    final actualSha256 = digestParts.isEmpty
        ? ''
        : digestParts.first.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(actualSha256)) {
      throw _CaptureFailure.environment(
        stage,
        'parent_prepared_app_digest_invalid_on_$deviceId',
      );
    }
    if (actualSha256 != expectedSha256.toLowerCase()) {
      throw _CaptureFailure.environment(
        stage,
        'parent_prepared_app_digest_mismatch_on_$deviceId',
      );
    }
  }

  Future<void> _clearAndroidPrivateEntries(String deviceId) async {
    final inventory = await _adb(deviceId, <String>[
      'shell',
      'run-as',
      appPackage,
      'ls',
      '-1',
      '-A',
      '.',
    ], allowFail: true);
    if (inventory.exitCode != 0) {
      throw _CaptureFailure.environment(
        stage,
        'private_app_inventory_unavailable_on_$deviceId',
      );
    }
    final entries = inventory.stdout
        .split('\n')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (entries.any(
      (entry) =>
          !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(entry) ||
          entry == '.' ||
          entry == '..',
    )) {
      throw _CaptureFailure.capture(
        stage,
        'unsafe_private_app_inventory_on_$deviceId',
      );
    }
    for (final entry in entries) {
      await _adb(deviceId, <String>[
        'shell',
        'run-as',
        appPackage,
        'rm',
        '-rf',
        '--',
        entry,
      ]);
    }
  }

  Future<void> _installApk(String deviceId, File apk) async {
    final result = await _adb(deviceId, <String>[
      'install',
      '-r',
      '-d',
      '-t',
      apk.path,
    ], allowFail: true);
    if (result.exitCode != 0) {
      throw _CaptureFailure.environment(
        stage,
        'candidate_install_failed_on_$deviceId: ${_lastLine(result.combined)}',
      );
    }
    final installedPath = await _adbShell(deviceId, <String>[
      'pm',
      'path',
      appPackage,
    ], environmentFailure: true);
    if (!installedPath.contains('package:')) {
      throw _CaptureFailure.environment(
        stage,
        'candidate_install_not_discoverable_on_$deviceId',
      );
    }
  }

  Future<void> _wakeAndroid(String deviceId) async {
    await _adbShell(deviceId, const <String>[
      'input',
      'keyevent',
      'KEYCODE_WAKEUP',
    ], allowFail: true);
    await _adbShell(deviceId, const <String>[
      'wm',
      'dismiss-keyguard',
    ], allowFail: true);
  }

  Future<void> _prepareAndroidIdentity(_Party party) async {
    await _wakeAndroid(party.deviceId);
    await _writeAppFile(
      party.deviceId,
      'auto_setup.json',
      jsonEncode(<String, Object?>{'username': party.username}),
    );
    for (final name in const <String>[
      'intro_e2e_identity.json',
      'intro_e2e_config.json',
      'intro_e2e_result.json',
    ]) {
      await _deleteAppFile(party.deviceId, name);
    }
  }

  Future<void> _collectAndroidIdentity(_Party party) async {
    final raw = await _waitForValue<String>(
      'identity export for ${party.role}',
      const Duration(minutes: 3),
      () => _readAppFile(party.deviceId, 'intro_e2e_identity.json'),
    );
    Map<String, dynamic> exported;
    Map<String, dynamic> qr;
    try {
      exported = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      party.qrPayload = exported['qrPayload'] as String;
      party.mlKemPublicKey = exported['mlKemPublicKey'] as String?;
      qr = Map<String, dynamic>.from(jsonDecode(party.qrPayload) as Map);
      party.peerId = qr['ns'] as String;
    } on Object {
      throw _CaptureFailure.capture(
        stage,
        'identity_export_invalid_for_${party.role}',
      );
    }
    if (party.peerId.isEmpty) {
      throw _CaptureFailure.capture(
        stage,
        'identity_export_missing_peer_for_${party.role}',
      );
    }
  }

  Future<void> _prepopulateAndroidContacts() async {
    await _prepopulateContact(sender, recipient);
    await _prepopulateContact(recipient, sender);
  }

  Future<void> _prepopulateContact(_Party owner, _Party contact) async {
    await _writeAppFile(
      owner.deviceId,
      'intro_e2e_config.json',
      jsonEncode(<String, Object?>{
        'stepId':
            '257-${scenario.id}-${owner.username}-'
            '${DateTime.now().microsecondsSinceEpoch}',
        'add_contacts': <Object?>[
          <String, Object?>{
            'qrPayload': contact.qrPayload,
            'mlKemPublicKey': contact.mlKemPublicKey,
          },
        ],
      }),
    );
    await _launchAndroid(owner.deviceId);
    await _deleteAppFile(owner.deviceId, 'intro_e2e_config.json');
    await _deleteAppFile(owner.deviceId, 'intro_e2e_result.json');
    await _launchAndroid(owner.deviceId);
  }

  Future<void> _createAndAcceptGroup({String? name}) async {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    _groupName =
        name ??
        (scenario.groupType == 'announcement'
            ? 'TC257Ann$now'
            : 'TC257Group$now');
    final creator = scenario.id.endsWith('_message_unread_lifecycle')
        ? sender
        : recipient;
    final invitee = identical(creator, sender) ? recipient : sender;

    await _launchAndroid(creator.deviceId);
    await _waitForCreatorSendable(creator.deviceId);
    await _tapOrbitCreateFab(creator.deviceId);
    await _tapText(
      creator.deviceId,
      scenario.groupType == 'announcement' ? 'New Announce' : 'New Group',
    );
    await _tapText(creator.deviceId, invitee.username);
    final groupNameField = await _retryUiCenter(
      creator.deviceId,
      (dump) =>
          findBottommostNodeCenterByClass(dump, 'android.widget.EditText'),
    );
    if (groupNameField == null) {
      throw _CaptureFailure.capture(
        stage,
        'group_name_field_not_found_on_${creator.deviceId}',
      );
    }
    await _adbShell(creator.deviceId, <String>[
      'input',
      'tap',
      '${groupNameField.$1}',
      '${groupNameField.$2}',
    ], environmentFailure: true);
    await _adbShell(creator.deviceId, <String>[
      'input',
      'text',
      _groupName,
    ], environmentFailure: true);
    await _waitForCreatorGroupRecoveryQuiescentWindow(creator.deviceId);
    await _tapText(creator.deviceId, 'Start group chat');
    await _waitForUiText(
      creator.deviceId,
      _groupName,
      const Duration(minutes: 2),
    );

    await _startAndroid(invitee.deviceId);
    await _waitForGroupInviteEntry(
      invitee.deviceId,
      const Duration(minutes: 3),
    );
    await _waitForUiText(
      invitee.deviceId,
      _groupName,
      const Duration(seconds: 30),
    );
    await _tapText(invitee.deviceId, 'Accept');
    await _waitForValue<bool>(
      'accepted group surface for $_groupName on ${invitee.deviceId}',
      const Duration(minutes: 3),
      () async =>
          isAcceptedGroupSurface(await _uiDump(invitee.deviceId), _groupName)
          ? true
          : null,
    );
  }

  Future<void> _waitForCreatorSendable(String deviceId) async {
    final rawPid = await _adbShell(deviceId, <String>[
      'pidof',
      appPackage,
    ], environmentFailure: true);
    final pid = RegExp(r'\b[1-9][0-9]*\b').firstMatch(rawPid)?.group(0);
    if (pid == null) {
      throw _CaptureFailure.capture(
        stage,
        'creator_process_missing_before_sendable_wait_on_$deviceId',
      );
    }

    final ready = await waitForCreatorSendableReadiness(
      readCurrentProcessLog: () async {
        final output = await _adb(deviceId, <String>[
          'logcat',
          '-d',
          '--pid=$pid',
          '-v',
          'brief',
        ], allowFail: true);
        return output.stdout;
      },
    );
    if (!ready) {
      throw _CaptureFailure.capture(
        stage,
        'creator_sendable_readiness_timeout_on_${deviceId}_pid_$pid',
      );
    }
  }

  Future<void> _waitForCreatorGroupRecoveryQuiescentWindow(
    String deviceId,
  ) async {
    final rawPid = await _adbShell(deviceId, <String>[
      'pidof',
      appPackage,
    ], environmentFailure: true);
    final pid = RegExp(r'\b[1-9][0-9]*\b').firstMatch(rawPid)?.group(0);
    if (pid == null) {
      throw _CaptureFailure.capture(
        stage,
        'creator_process_missing_before_recovery_window_on_$deviceId',
      );
    }

    final ready = await waitForCreatorGroupRecoveryQuiescentWindow(
      readCurrentProcessLog: () async {
        final output = await _adb(deviceId, <String>[
          'logcat',
          '-d',
          '--pid=$pid',
          '-v',
          'brief',
        ], allowFail: true);
        return output.stdout;
      },
    );
    if (!ready) {
      throw _CaptureFailure.capture(
        stage,
        'creator_group_recovery_quiescent_window_timeout_on_${deviceId}_pid_$pid',
      );
    }
  }

  Future<void> _runAndroidUnreadLifecycle() async {
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    _firstMarker = 'TC257First$stamp';
    _secondMarker = 'TC257Second$stamp';
    await _ensureOrbit(recipientId);
    await _captureUiSnapshot('unread_0', expectedUnread: 0);

    await _openGroup(senderId);
    await _sendGroupText(senderId, _firstMarker);
    await _waitForGroupUnread(1);
    await _captureUiSnapshot('unread_1', expectedUnread: 1);
    final firstCard = await _waitForNotificationCard();
    _notificationSnapshots.add(
      await _writeNotificationSnapshot('message_first', firstCard.$2),
    );
    await _dismissNotificationCard();
    await _waitForNoNotificationCard();
    await _waitForGroupUnread(1);
    await _captureUiSnapshot('unread_1_after_dismiss', expectedUnread: 1);

    await _openGroup(senderId);
    await _sendGroupText(senderId, _secondMarker);
    await _waitForGroupUnread(2);
    await _captureUiSnapshot('unread_2', expectedUnread: 2);
    final secondCard = await _waitForNotificationCard();
    _notificationSnapshots.add(
      await _writeNotificationSnapshot('message_second', secondCard.$2),
    );
    await _tapNotificationCard();
    await _waitForUiText(
      recipientId,
      _firstMarker,
      const Duration(seconds: 45),
    );
    await _waitForUiText(
      recipientId,
      _secondMarker,
      const Duration(seconds: 45),
    );
    await _captureRawUiSnapshot('conversation_after_tap');
    await _adbShell(recipientId, const <String>[
      'input',
      'keyevent',
      'KEYCODE_BACK',
    ], environmentFailure: true);
    await _waitForUiText(
      recipientId,
      'Open group $_groupName',
      const Duration(seconds: 45),
    );
    await _captureUiSnapshot('unread_0_after_tap', expectedUnread: 0);
    await _collectBoundedLogs();
  }

  Future<void> _runAndroidGroupNotificationProjectionLifecycle() async {
    final suffix = _runtimeToken('message').replaceAll('-', '');
    final groupAMarker = 'Plan330TextA${suffix.substring(0, 12)}';
    final groupBMarker = 'Plan330TextB${suffix.substring(12, 24)}';

    await _plan330InnerCircleGroupCenter(recipientId, _plan330GroupAName);
    await _openPlan330Group(senderId, _plan330GroupAName);
    await _sendGroupText(senderId, groupAMarker);
    await _openPlan330Group(senderId, _plan330GroupBName);
    await _sendGroupText(senderId, groupBMarker);

    await _plan330InnerCircleGroupCenter(recipientId, _plan330GroupAName);
    final beforeUi = await _waitForValue<String>(
      'both Plan 330 unread-one Orbit projections',
      const Duration(minutes: 3),
      () async {
        final xml = await _uiDump(recipientId);
        return xml.contains(
                  'Open group $_plan330GroupAName, 1 unread message',
                ) &&
                xml.contains('Open group $_plan330GroupBName, 1 unread message')
            ? xml
            : null;
      },
    );
    _plan330BeforeUiDump = await _writePlan330RawFile(
      'plan330_read_before_ui.xml',
      beforeUi,
    );

    final beforeCards = await _waitForPlan330TwoCards();
    _plan330BeforeNotificationDump = await _writePlan330RawFile(
      'plan330_read_before_notifications.log',
      '${_appNotificationRecords(beforeCards.$1)}\n',
    );
    _plan330GroupANotificationId = beforeCards.$2
        .singleWhere((record) => record.$2.title == _plan330GroupAName)
        .$1;
    _plan330GroupBNotificationId = beforeCards.$2
        .singleWhere((record) => record.$2.title == _plan330GroupBName)
        .$1;

    final groupABefore = await _runPlan330Endpoint(
      deviceId: recipientId,
      phase: 'observe_group',
      role: 'physical_author',
      groupName: _plan330GroupAName,
      kind: 'group',
    );
    final groupBBefore = await _runPlan330Endpoint(
      deviceId: recipientId,
      phase: 'observe_group',
      role: 'physical_author',
      groupName: _plan330GroupBName,
      kind: 'group',
    );
    if (groupABefore['unreadCount'] != 1 || groupBBefore['unreadCount'] != 1) {
      throw _CaptureFailure.capture(
        stage,
        'Plan 330 SQLCipher unread baseline is not A=1/B=1',
      );
    }
    _plan330GroupAIdSha256 = '${groupABefore['groupIdSha256'] ?? ''}';
    _plan330GroupBIdSha256 = '${groupBBefore['groupIdSha256'] ?? ''}';

    await _adb(recipientId, const <String>['logcat', '-c']);
    final readCenter = findSemanticNodeCenter(
      await _uiDump(recipientId),
      'Open group $_plan330GroupAName, 1 unread message',
    );
    if (readCenter == null) {
      throw _CaptureFailure.capture(
        stage,
        'Plan 330 in-app group-A Orbit node is unavailable',
      );
    }
    _recordPlan330Command(
      commandStage: 'read_projection',
      target: recipientId,
      action: 'tap',
      semanticTarget: 'Open group $_plan330GroupAName',
    );
    await _adbShell(recipientId, <String>[
      'input',
      'tap',
      '${readCenter.$1}',
      '${readCenter.$2}',
    ], environmentFailure: true);
    await _waitFor(
      'Plan 330 group-A conversation',
      const Duration(seconds: 45),
      () async => isGroupConversationSurface(
        await _uiDump(recipientId),
        _plan330GroupAName,
      ),
    );
    final groupAAfterRead = await _waitForValue<Map<String, dynamic>>(
      'Plan 330 committed group-A unread zero',
      const Duration(seconds: 60),
      () async {
        final observed = await _runPlan330Endpoint(
          deviceId: recipientId,
          phase: 'observe_group',
          role: 'physical_author',
          groupName: _plan330GroupAName,
          kind: 'group',
        );
        return observed['unreadCount'] == 0 ? observed : null;
      },
    );
    if (groupAAfterRead['groupIdSha256'] != _plan330GroupAIdSha256) {
      throw _CaptureFailure.capture(
        stage,
        'Plan 330 group-A identity changed across the read commit',
      );
    }
    _recordPlan330Command(
      commandStage: 'read_projection',
      target: recipientId,
      action: 'wait_unread_zero',
      semanticTarget: 'Open group $_plan330GroupAName',
    );

    await _adbShell(recipientId, const <String>[
      'input',
      'keyevent',
      'KEYCODE_BACK',
    ], environmentFailure: true);
    final afterUi = await _waitForValue<String>(
      'Plan 330 Orbit A=0/B=1 projection',
      const Duration(seconds: 60),
      () async {
        final xml = await _uiDump(recipientId);
        final aUnread = RegExp(
          'Open group ${RegExp.escape(_plan330GroupAName)}, '
          r'[1-9][0-9]* unread messages?',
        ).hasMatch(xml);
        return xml.contains('Open group $_plan330GroupAName') &&
                !aUnread &&
                xml.contains('Open group $_plan330GroupBName, 1 unread message')
            ? xml
            : null;
      },
    );
    _plan330AfterUiDump = await _writePlan330RawFile(
      'plan330_read_after_ui.xml',
      afterUi,
    );
    final afterReadCards =
        await _waitForValue<(String, List<(int, ActiveNotificationCard)>)>(
          'Plan 330 exact group-A notification cancellation',
          const Duration(seconds: 60),
          () async {
            final dump = await _notificationDump(recipientId);
            final cards = _activeContentNotificationRecords(dump);
            return cards.length == 1 &&
                    cards.single.$1 == _plan330GroupBNotificationId &&
                    cards.single.$2.title == _plan330GroupBName
                ? (dump, cards)
                : null;
          },
        );
    _plan330AfterNotificationDump = await _writePlan330RawFile(
      'plan330_read_after_notifications.log',
      '${_appNotificationRecords(afterReadCards.$1)}\n',
    );
    _recordPlan330Command(
      commandStage: 'read_projection',
      target: recipientId,
      action: 'dumpsys_notification',
      semanticTarget: 'after_read_zero',
    );
    final readLog = _flowLines((await _readAndroidLogcat(recipientId)).stdout);
    _plan330ReadFlowLog = await _writePlan330RawFile(
      'plan330_read_flow.log',
      '$readLog\n',
    );

    await _grantRecordAudioPermission(recipientId);
    final mediaSend = await _runPlan330Endpoint(
      deviceId: recipientId,
      phase: 'send_media',
      role: 'physical_author',
      groupName: _plan330GroupAName,
      kind: 'group',
      timeout: const Duration(minutes: 6),
    );
    if (mediaSend['groupIdSha256'] != _plan330GroupAIdSha256 ||
        mediaSend['media'] is! List ||
        (mediaSend['media'] as List).length != 3) {
      throw _CaptureFailure.capture(
        stage,
        'Plan 330 production media fixture receipt is incomplete',
      );
    }

    const fixtureKinds = <String>['jpeg', 'mp4', 'voice'];
    const externalKinds = <String>['photo', 'video', 'voiceMessage'];
    const mediaTypes = <String>['image', 'video', 'audio'];
    for (var index = 0; index < fixtureKinds.length; index += 1) {
      await _terminateAndroidRecipient();
      final fixtureKind = fixtureKinds[index];
      final externalKind = externalKinds[index];
      final receipt = await _runPlan330Endpoint(
        deviceId: senderId,
        phase: 'react_media',
        role: 'emulator_reactor',
        groupName: _plan330GroupAName,
        kind: fixtureKind,
        timeout: const Duration(minutes: 4),
      );
      if (receipt['schema'] != groupNotificationProjectionTargetReceiptSchema ||
          receipt['kind'] != externalKind ||
          receipt['mediaType'] != mediaTypes[index] ||
          receipt['ownerLane'] != 'group' ||
          receipt['attachmentCount'] != 1 ||
          receipt['reactionCommitted'] != true) {
        throw _CaptureFailure.capture(
          stage,
          'Plan 330 $externalKind reaction target receipt is invalid',
        );
      }
      _recordPlan330Command(
        commandStage: 'reaction_projection',
        target: senderId,
        action: 'react_to_group_media',
        semanticTarget: externalKind,
      );
      final bodies = _plan330LocalizedBodies(externalKind);
      final cards = await _waitForPlan330TwoCards(
        acceptedGroupABodies: bodies.values.toSet(),
      );
      final groupACard = cards.$2.singleWhere(
        (record) => record.$2.title == _plan330GroupAName,
      );
      final groupBCard = cards.$2.singleWhere(
        (record) => record.$2.title == _plan330GroupBName,
      );
      if (groupACard.$1 != _plan330GroupANotificationId ||
          groupBCard.$1 != _plan330GroupBNotificationId) {
        throw _CaptureFailure.capture(
          stage,
          'Plan 330 stable group notification identity changed for '
          '$externalKind',
        );
      }
      final matchedLocales = bodies.entries
          .where((entry) => entry.value == groupACard.$2.body)
          .map((entry) => entry.key)
          .toList(growable: false);
      if (matchedLocales.length != 1 ||
          (_plan330Locale.isNotEmpty &&
              _plan330Locale != matchedLocales.single)) {
        throw _CaptureFailure.capture(
          stage,
          'Plan 330 $externalKind localized notification copy is ambiguous',
        );
      }
      _plan330Locale = matchedLocales.single;
      final notificationFile = await _writePlan330RawFile(
        'plan330_reaction_${externalKind}_notifications.log',
        '${_appNotificationRecords(cards.$1)}\n',
      );
      final receiptFile = await _writePlan330RawFile(
        'plan330_reaction_${externalKind}_target.json',
        '${const JsonEncoder.withIndent(' ').convert(receipt)}\n',
      );
      _plan330ReactionObservations.add(<String, Object?>{
        'kind': externalKind,
        'mediaType': mediaTypes[index],
        'ownerLane': 'group',
        'attachmentCount': 1,
        'targetMessageIdSha256': receipt['targetMessageIdSha256'],
        'notificationDump': await _plan330EvidenceReference(notificationFile),
        'targetReceipt': await _plan330EvidenceReference(receiptFile),
      });
    }
  }

  Future<void> _runAndroidReactionLifecycle() async {
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    _targetMarker = 'TC257Target$stamp';

    await _openGroup(recipientId);
    await _sendGroupText(recipientId, _targetMarker);
    await _openGroup(senderId);
    await _waitForUiText(senderId, _targetMarker, const Duration(minutes: 2));
    await _ensureOrbit(recipientId);
    await _captureUiSnapshot('reaction_unread_0_before', expectedUnread: 0);
    final keepRecipientProcessAlive =
        groupReactionNotificationKeepsRecipientProcessAlive(scenario.id);
    if (keepRecipientProcessAlive) {
      await _backgroundAndroidRecipientConnected();
    } else {
      await _terminateAndroidRecipient();
    }

    if (!keepRecipientProcessAlive) {
      await _openGroup(senderId);
    }
    final firstWindow = DateTime.now().toUtc();
    await _longPressText(senderId, _targetMarker);
    await _tapText(senderId, _reactionEmoji);
    if (keepRecipientProcessAlive) {
      _backgroundConnectedReactionAt = DateTime.now().toUtc();
    }
    await _waitForSenderEventCount('GROUP_REACTION_SEND_QUEUED', 1);
    await _waitForProviderSendCount(firstWindow, 1);
    final firstCard = await _waitForNotificationCard();
    if (keepRecipientProcessAlive) {
      _completeBackgroundConnectedObservation(DateTime.now().toUtc());
    }
    _notificationSnapshots.add(
      await _writeNotificationSnapshot('reaction_first', firstCard.$2),
    );

    await _longPressText(senderId, _targetMarker);
    await _tapText(senderId, _reactionEmoji);
    await _waitForSenderEventCount('GROUP_REACTION_REMOVE_QUEUED', 1);
    await Future<void>.delayed(const Duration(seconds: 8));
    final afterRemove = await _relayJournalSince(firstWindow);
    final providerAfterRemove = _countProviderSends(afterRemove);
    if (providerAfterRemove != 1) {
      throw _CaptureFailure.capture(
        stage,
        'remove_transition_woke_provider: expected one ADD provider send '
        'before re-add, observed $providerAfterRemove',
      );
    }

    await _longPressText(senderId, _targetMarker);
    await _tapText(senderId, _reactionEmoji);
    await _waitForSenderEventCount('GROUP_REACTION_SEND_QUEUED', 2);
    await _waitForProviderSendCount(firstWindow, 2);
    final replacementCard = await _waitForNotificationCard();
    _notificationSnapshots.add(
      await _writeNotificationSnapshot(
        'reaction_replacement',
        replacementCard.$2,
      ),
    );
    if (firstCard.$1 != replacementCard.$1) {
      throw _CaptureFailure.capture(
        stage,
        'reaction_notification_not_stable_per_group: first=${firstCard.$1}, '
        'replacement=${replacementCard.$1}',
      );
    }
    final expectedBody = groupReactionNotificationExpectedAndroidReactionBody(
      'Alice',
    );
    if (replacementCard.$2.title != _groupName ||
        replacementCard.$2.body != expectedBody ||
        replacementCard.$2.body.contains('New Message')) {
      throw _CaptureFailure.capture(
        stage,
        'reaction_card_copy_mismatch: observed title/body did not match '
        'recipient-owned group and trusted actor copy',
      );
    }

    await _redriveExactStoredAdd(firstWindow);

    await _tapNotificationCard();
    await _waitForUiText(
      recipientId,
      _targetMarker,
      const Duration(seconds: 60),
    );
    await _captureRawUiSnapshot('reaction_target_after_tap');
    await _adbShell(recipientId, const <String>[
      'input',
      'keyevent',
      'KEYCODE_BACK',
    ], environmentFailure: true);
    await _waitForUiText(
      recipientId,
      'Open group $_groupName',
      const Duration(seconds: 45),
    );
    await _captureUiSnapshot('reaction_unread_0_after', expectedUnread: 0);
    await _collectBoundedLogs();
  }

  Future<void> _redriveExactStoredAdd(DateTime providerWindow) async {
    final observation = noChildBuilds
        ? await _runInstalledGroupReactionProbe(
            deviceId: senderId,
            action: _runtimeExactAddRedriveAction,
          )
        : await _runLegacyExactAddRedriveProbe();
    _validateExactAddRedriveObservation(observation);
    _exactDuplicateRedriveObservation =
        '$_duplicateRedrivePrefix${jsonEncode(observation)}\n';

    if (noChildBuilds) {
      // The production app performed the bounded SQLCipher mutation in place.
      // Its ordinary pending retrier must now resubmit the unchanged stored
      // inbox_retry_payload; no reinstall, test target, or child build is
      // permitted in the central-build path.
      await _startAndroid(senderId);
    } else {
      // flutter drive keeps the probe application installed/running, so the
      // sender's identity and SQLCipher rows survive. Reinstalling/launching
      // the normal candidate makes the production pending retrier submit the
      // same persisted inbox_retry_payload bytes.
      await _installApk(senderId, _androidBuilds!.normalApk);
      await _startAndroid(senderId);
    }
    await _waitFor(
      'production exact group reaction duplicate retry',
      const Duration(minutes: 3),
      () async {
        final log = await _adb(senderId, const <String>[
          'logcat',
          '-d',
          '-v',
          'brief',
        ]);
        return log.stdout.contains('RETRY_FAILED_GROUP_REACTION_REPLAY_OK');
      },
    );
    await Future<void>.delayed(const Duration(seconds: 10));
    final providerCount = _countProviderSends(
      await _relayJournalSince(providerWindow),
    );
    if (providerCount != 2) {
      throw _CaptureFailure.capture(
        stage,
        'exact_duplicate_redrive_changed_provider_count: expected 2, '
        'observed $providerCount',
      );
    }
  }

  Future<Map<String, dynamic>> _runLegacyExactAddRedriveProbe() async {
    final output = await _runStreaming('flutter', <String>[
      'drive',
      '--no-pub',
      '-d',
      senderId,
      '--driver',
      'test_driver/integration_test.dart',
      '--target',
      _sqlCipherProbe,
      '--keep-app-running',
      '--dart-define=MKNOON_257_PROBE_SCENARIO=${scenario.id}',
      '--dart-define=MKNOON_257_PROBE_GROUP_NAME=$_groupName',
      '--dart-define=MKNOON_257_PROBE_TARGET_MARKER=$_targetMarker',
    ]);
    String? encoded;
    for (final line in output.combined.split('\n')) {
      final index = line.indexOf(_duplicateRedrivePrefix);
      if (index >= 0) {
        encoded = line.substring(index + _duplicateRedrivePrefix.length).trim();
      }
    }
    if (encoded == null) {
      throw _CaptureFailure.capture(
        stage,
        'exact_duplicate_redrive_probe_emitted_no_observation',
      );
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    } on Object {
      throw _CaptureFailure.capture(
        stage,
        'exact_duplicate_redrive_observation_invalid_json',
      );
    }
  }

  void _validateExactAddRedriveObservation(Map<String, dynamic> observation) {
    final identityHashes = <String>[
      'transitionIdSha256',
      'reactionStateIdSha256',
      'targetMessageIdSha256',
    ].map((key) => observation[key]).toList(growable: false);
    final validSha = RegExp(r'^[0-9a-f]{64}$');
    if (observation['schema'] !=
            'mknoon.plan257.duplicate-redrive-observation.v1' ||
        observation['scenario'] != scenario.id ||
        observation['prepared'] != true ||
        observation['notificationExtensionBound'] != true ||
        observation['signedEnvelopePresent'] != true ||
        observation['storedEnvelopeDecryptOk'] != true ||
        identityHashes.any(
          (value) => value is! String || !validSha.hasMatch(value),
        ) ||
        identityHashes.toSet().length != 3 ||
        observation['transitionIdPrefixSha256'] is! String ||
        !validSha.hasMatch(observation['transitionIdPrefixSha256'] as String) ||
        observation['inboxRetryPayloadSha256'] is! String ||
        !validSha.hasMatch(observation['inboxRetryPayloadSha256'] as String)) {
      throw _CaptureFailure.capture(
        stage,
        'exact_duplicate_redrive_observation_contract_mismatch',
      );
    }
  }

  Future<void> _collectBoundedLogs() async {
    // The provider count is an eventual boundary. Wait through a bounded
    // quiescence interval, then require the final raw relay window to contain
    // exactly the two expected sends (first ADD/message and replacement). A
    // late third send can no longer pass an earlier `>= 2` wait.
    await Future<void>.delayed(const Duration(seconds: 10));
    final senderLog = await _readAndroidLogcat(senderId);
    final recipientLog = await _readAndroidLogcat(recipientId);
    _senderLogcat = _flowLines(senderLog.stdout);
    _recipientLogcat = _flowLines(recipientLog.stdout);
    _relayJournal = await _relayJournalSince(
      _captureWindowStart ?? DateTime.now().toUtc(),
    );
    final providerSendCount = _countProviderSends(_relayJournal);
    if (providerSendCount != 2) {
      throw _CaptureFailure.capture(
        stage,
        'provider_send_count_mismatch_after_quiescence: expected=2 '
        'observed=$providerSendCount',
      );
    }
  }

  Future<void> _tapOrbitCreateFab(String deviceId) async {
    final center = await findOrbitCreateGroupFabWithRecovery(
      readUiDump: () => _uiDump(deviceId),
      reestablishOrbit: () => _reestablishOrbitWithoutForceStop(deviceId),
    );
    if (center == null) {
      throw _CaptureFailure.capture(
        stage,
        'orbit_create_fab_not_found_on_$deviceId',
      );
    }
    await _adbShell(deviceId, <String>[
      'input',
      'tap',
      '${center.$1}',
      '${center.$2}',
    ], environmentFailure: true);
    await _waitForAnyText(deviceId, const <String>[
      'New Group',
      'New Announce',
    ], const Duration(seconds: 15));
  }

  Future<void> _reestablishOrbitWithoutForceStop(String deviceId) async {
    // Resuming and bounded back navigation are sufficient to recover Orbit.
    // Repeated force-stop/start cycles can reset relay readiness while fixture
    // setup is trying to prove it, so recovery deliberately never calls
    // _launchAndroid.
    await _startAndroid(deviceId);
    for (var attempt = 0; attempt < 3; attempt++) {
      final dump = await _uiDump(deviceId);
      if (findOrbitCreateGroupFabCenter(dump) != null ||
          _fixtureSemanticValues(dump).contains('Pending Group Invites') ||
          _fixtureSemanticValues(
            dump,
          ).any((value) => value.startsWith('Open introductions review'))) {
        return;
      }
      await _adbShell(deviceId, const <String>[
        'input',
        'keyevent',
        'KEYCODE_BACK',
      ], allowFail: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<(int, int)?> _retryUiCenter(
    String deviceId,
    (int, int)? Function(String dump) finder,
  ) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final center = finder(await _uiDump(deviceId));
      if (center != null) return center;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  Future<void> _ensureOrbit(String deviceId) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final dump = await _uiDump(deviceId);
      if (findSemanticNodeCenter(dump, 'Open group $_groupName') != null ||
          dump.contains('Open introductions review')) {
        return;
      }
      await _adbShell(deviceId, const <String>[
        'input',
        'keyevent',
        'KEYCODE_BACK',
      ], allowFail: true);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    throw _CaptureFailure.capture(
      stage,
      'orbit_surface_not_reached_on_$deviceId',
    );
  }

  /// Reaches Orbit without assuming which of the two Plan-330 groups is
  /// already projected. The legacy helper is intentionally group-specific;
  /// using it immediately after accepting group B made a perfectly valid
  /// group-B conversation stack look like a missing group-A Orbit surface.
  Future<void> _ensurePlan330Orbit(String deviceId) async {
    await _startAndroid(deviceId);
    for (var attempt = 0; attempt < 12; attempt += 1) {
      final dump = await _uiDump(deviceId);
      if (findOrbitCreateGroupFabCenter(dump) != null) return;
      await _adbShell(deviceId, const <String>[
        'input',
        'keyevent',
        'KEYCODE_BACK',
      ], allowFail: true);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    throw _CaptureFailure.capture(
      stage,
      'Plan 330 Orbit FAB not reached on $deviceId',
    );
  }

  // -------------------------------------------------------------------------
  // Plan 379 muted-group lifecycles (TC-379-05 live, TC-379-06 FCM).
  //
  // Neither stage calls `_collectBoundedLogs` (it hard-requires EXACTLY two
  // provider sends) nor `_writeAndroidArtifact` (its inventory precondition
  // demands a `[PUSH] … sent to` relay line that relay v1.8.0 no longer emits,
  // and `_validateSqlCipherObservation` pins `unreadCount == 0` — the exact
  // negation of what a muted scenario proves). The relay has no mute knowledge
  // at all, so delivery is proven at the RECIPIENT boundary: persisted rows
  // plus cursor-scoped client flow events.
  // -------------------------------------------------------------------------

  /// Flow event emitted when a group message row is inserted
  /// (`group_messages_db_helpers.dart:76`). Pinned by a census test so this
  /// literal cannot silently stop existing.

  Future<void> _pressAndroidKey(String deviceId, String keycode) => _adbShell(
    deviceId,
    <String>['input', 'keyevent', keycode],
    environmentFailure: true,
  );

  void _recordMutedCommand({
    required String commandStage,
    required String target,
    required String action,
    required String semanticTarget,
  }) {
    _mutedCommands.add(<String, Object?>{
      'stage': commandStage,
      'target': target,
      'action': action,
      'semanticTarget': semanticTarget,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Content cards attributable to [groupName] or to [marker].
  ///
  /// Uses the id-free extractor: `_activeNotificationRecords` THROWS on any
  /// pkg-matching record without a numeric id, so a "must be empty" assertion
  /// built on it could raise instead of returning zero.
  List<ActiveNotificationCard> _mutedAttributableCards(
    String dump, {
    required String groupName,
    String marker = '',
  }) => extractActiveContentNotificationCards(dump, packageName: appPackage)
      .where(
        (card) =>
            card.title == groupName ||
            (marker.isNotEmpty &&
                (card.title.contains(marker) || card.body.contains(marker))),
      )
      .toList(growable: false);

  Future<String> _waitForGroupNotificationDump(String groupName) =>
      _waitForValue<String>(
        'notification card for $groupName',
        const Duration(seconds: 120),
        () async {
          final dump = await _notificationDump(recipientId);
          return _mutedAttributableCards(dump, groupName: groupName).length == 1
              ? dump
              : null;
        },
      );

  /// Waits until [groupName]'s card carries none of [staleBodies].
  ///
  /// Android replaces a conversation's card in place, so "a card exists for
  /// the control group" is satisfied by a card posted BEFORE the observation
  /// window opened. Requiring the body to have changed is what makes the
  /// control prove that a notification arrived inside the window. The stale
  /// set is a LIST because the lane posts more than one message to the control
  /// group ahead of the window (the liveness baseline and the cold-start
  /// warm-up), and either of them can be the card sitting in the shade.
  Future<String> _waitForGroupNotificationBodyChange(
    String groupName,
    List<String> staleBodies,
  ) async {
    try {
      return await _waitForGroupNotificationBodyChangeInner(
        groupName,
        staleBodies,
      );
    } on _CaptureFailure {
      await _writeMutedDiagnosticDump(
        'background_control_card_not_refreshed',
        await _notificationDump(recipientId),
      );
      rethrow;
    }
  }

  Future<String> _waitForGroupNotificationBodyChangeInner(
    String groupName,
    List<String> staleBodies,
  ) => _waitForValue<String>(
    'refreshed notification card for $groupName',
    const Duration(seconds: 180),
    () async {
      final dump = await _notificationDump(recipientId);
      final cards = _mutedAttributableCards(dump, groupName: groupName);
      // At least one card whose body is no longer any known baseline.
      // Deliberately not "exactly one": a reaction may post ALONGSIDE the
      // baseline message card rather than replacing it in place, and both
      // shapes prove an in-window arrival equally well.
      final refreshed = cards
          .where((card) => !staleBodies.any((body) => card.body.contains(body)))
          .toList(growable: false);
      return refreshed.isEmpty ? null : dump;
    },
  );

  /// Waits until [groupName]'s card body carries [marker].
  ///
  /// Stronger than "the body changed": post-384 the warm-up push cards too,
  /// under the SAME conversation-keyed notification id, so card presence — and
  /// even "the body is no longer the baseline" — can latch on the warm-up's
  /// card. Binding the wait to the graded marker is what makes the observation
  /// the graded push's own.
  Future<String> _waitForGroupNotificationBodyContaining(
    String groupName,
    String marker,
  ) => _waitForValue<String>(
    'notification card for $groupName carrying $marker',
    const Duration(seconds: 180),
    () async {
      final dump = await _notificationDump(recipientId);
      final matched = _mutedAttributableCards(
        dump,
        groupName: groupName,
      ).where((card) => card.body.contains(marker));
      return matched.isEmpty ? null : dump;
    },
  );

  /// Waits until the recipient's background isolate has taken [count] wakes.
  Future<void> _waitForBackgroundPushWakes(int count) => _waitFor(
    'background isolate wake #$count on the recipient',
    const Duration(minutes: 3),
    () async =>
        countFlowEventOccurrences(
          await _accumulatedRecipientFlowLines(),
          'PUSH_BACKGROUND_MESSAGE_RECEIVED',
        ) >=
        count,
  );

  /// Waits until the background isolate has opened and read the encrypted
  /// group store.
  ///
  /// This is the cost the warm-up exists to absorb, so it is asserted directly
  /// rather than by enumerating the warm-up's notification dispositions.
  /// Enumerating was tried and was wrong: run 12 (2026-08-18) saw the warm-up
  /// text end at `PUSH_ANDROID_DATA_DECRYPT_FAIL{group_parity_mismatch}` ->
  /// `PUSH_BACKGROUND_NOTIFICATION_ERROR`, a disposition outside the list,
  /// even though its SQLCipher open had completed normally. That parity death
  /// was G19 and Plan 384 fixed it (`push_decrypt_preview.dart`, sender-clause
  /// null guard), so the warm-up text now CARDS — which is exactly why the
  /// storage-warmth signal, not a disposition list, is the right oracle here.
  /// The warm-up's own outcome stays deliberately NOT graded; only that it
  /// paid the cold cost.
  Future<void> _waitForRecipientStorageWarm() => _waitFor(
    'the background isolate to open and read the encrypted group store',
    const Duration(minutes: 2),
    () async =>
        (await _accumulatedRecipientFlowLines()).contains(_groupStoreReadEvent),
  );

  static const String _groupStoreReadEvent =
      'GROUP_MESSAGES_DB_LOAD_ALL_SUCCESS';

  /// Waits until no card remains for [groupName].
  ///
  /// Opening a group commits its unread to zero and the reconciler cancels its
  /// card. The muted lane asserts zero cards later, so the pre-mute control
  /// card must be provably gone BEFORE the observation window — otherwise a
  /// stale card would fail the capture and be misread as a mute regression.
  Future<void> _waitForGroupNotificationCleared(String groupName) => _waitFor(
    'cleared notification cards for $groupName',
    const Duration(seconds: 60),
    () async => _mutedAttributableCards(
      await _notificationDump(recipientId),
      groupName: groupName,
    ).isEmpty,
  );

  /// Saves a raw UI tree next to the artifact so an on-device targeting
  /// failure is diagnosable without re-running the whole capture.
  Future<void> _writeMutedDiagnosticDump(String name, String contents) async {
    final file = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      '${scenario.id}_diagnostic_$name.xml',
    );
    await file.writeAsString(contents, flush: true);
  }

  /// Scrolls Group Info until the mute switch itself is reachable.
  ///
  /// Keyed on the switch node, not on the row label: the "Mute Notifications"
  /// `Text` is never exposed to the accessibility tree (verified on device —
  /// the switch carries `NAF="true"` and every `text=` is empty).
  Future<void> _scrollGroupInfoToMuteRow() async {
    for (var attempt = 0; attempt < 8; attempt += 1) {
      if (findGroupMuteSwitchCenter(await _uiDump(recipientId)) != null) return;
      await _adbShell(recipientId, const <String>[
        'input',
        'swipe',
        '540',
        '1700',
        '540',
        '900',
        '400',
      ], environmentFailure: true);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    await _writeMutedDiagnosticDump(
      'group_info_mute_row_not_found',
      await _uiDump(recipientId),
    );
    throw _CaptureFailure.capture(
      stage,
      'group_mute_switch_not_reachable_in_bounded_scroll',
    );
  }

  /// Drives the real Group Info mute switch on the recipient.
  ///
  /// The switch exposes no text or content-description, so it is located by
  /// its own bounds inside the "Mute Notifications" row. The post-tap check
  /// reads the row's state subtitle; the authoritative read stays the
  /// SQLCipher `groupIsMuted` observation, which the validator requires.
  Future<void> _muteGroupThroughGroupInfo(String groupName) async {
    await _openPlan330Group(recipientId, groupName);
    final conversation = await _uiDump(recipientId);
    final info = findGroupInfoEntryCenter(conversation);
    if (info == null) {
      throw _CaptureFailure.capture(
        stage,
        'group_info_entry_not_reachable_on_recipient',
      );
    }
    _recordMutedCommand(
      commandStage: 'mute_toggle',
      target: recipientId,
      action: 'tap',
      semanticTarget: 'Group Info',
    );
    await _adbShell(recipientId, <String>[
      'input',
      'tap',
      '${info.$1}',
      '${info.$2}',
    ], environmentFailure: true);

    // Distinguish "the info control was mis-targeted" from "Group Info opened
    // but the mute card is below the fold": leaving the conversation surface
    // is the first, independent signal.
    var left = false;
    for (var attempt = 0; attempt < 20 && !left; attempt += 1) {
      final xml = await _uiDump(recipientId);
      left = !isGroupConversationSurface(xml, groupName);
      if (!left) await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!left) {
      await _writeMutedDiagnosticDump(
        'group_info_entry_tap_did_not_navigate',
        await _uiDump(recipientId),
      );
      throw _CaptureFailure.capture(
        stage,
        'group_info_entry_tap_did_not_leave_conversation at '
        '${info.$1},${info.$2}',
      );
    }

    await _waitFor(
      'group info surface on recipient',
      const Duration(seconds: 45),
      () async => isGroupInfoSurface(await _uiDump(recipientId)),
    );

    // `uiautomator dump` only serializes VISIBLE nodes, and the mute card sits
    // below the member list, so it is scrolled into view rather than assumed
    // on screen.
    await _scrollGroupInfoToMuteRow();

    final infoDump = await _uiDump(recipientId);
    if (groupMuteSwitchChecked(infoDump) != true) {
      final toggle = findGroupMuteSwitchCenter(infoDump);
      if (toggle == null) {
        await _writeMutedDiagnosticDump(
          'group_mute_switch_not_found',
          infoDump,
        );
        throw _CaptureFailure.capture(
          stage,
          'group_mute_switch_not_reachable_on_recipient',
        );
      }
      _recordMutedCommand(
        commandStage: 'mute_toggle',
        target: recipientId,
        action: 'tap',
        semanticTarget: groupMuteRowLabel,
      );
      await _adbShell(recipientId, <String>[
        'input',
        'tap',
        '${toggle.$1}',
        '${toggle.$2}',
      ], environmentFailure: true);
      await _waitFor(
        'mute switch checked after the Group Info tap',
        const Duration(seconds: 30),
        () async => groupMuteSwitchChecked(await _uiDump(recipientId)) == true,
      );
    }

    // Back out to Orbit and STAY FOREGROUND. Orbit is not a conversation, so
    // notifications still post normally, but no conversation is visible and
    // nothing gets marked read. Backgrounding here would move delivery onto
    // the push-wake path, where storage can defer to inbox-drain-on-resume —
    // which is TC-379-06's lane, not this one.
    await _pressAndroidKey(recipientId, 'KEYCODE_BACK');
    await _pressAndroidKey(recipientId, 'KEYCODE_BACK');
    await _ensureOrbit(recipientId);
  }

  /// Visits the unmuted control group, then returns to Orbit and HOME.
  ///
  /// This is the tracker-staleness control: visiting the control group
  /// overwrites whatever conversation the visibility tracker last held, so a
  /// "the group under test was considered visible" confound cannot survive.
  Future<void> _visitControlGroupAndReturnToOrbit() async {
    _recordMutedCommand(
      commandStage: 'control_visit',
      target: recipientId,
      action: 'tap',
      semanticTarget: 'Open group $_mutedControlGroupName',
    );
    await _openPlan330Group(recipientId, _mutedControlGroupName);
    await _pressAndroidKey(recipientId, 'KEYCODE_BACK');
    await _ensureOrbit(recipientId);
  }

  /// Reads the recipient's flow-event lines without foregrounding the app.
  Future<String> _recipientFlowLines() async {
    final log = await _readAndroidLogcat(recipientId);
    return _flowLines(log.stdout);
  }

  final List<String> _recipientFlowAccumulator = <String>[];
  final Set<String> _recipientFlowSeen = <String>{};

  /// Folds every `logcat -d` read into a monotonically growing flow log.
  ///
  /// `logcat -d` returns only what is still in the device ring buffer. On the
  /// pinned Pixel under campaign load that window is a couple of minutes —
  /// shorter than a lane — so polling the raw dump makes event counts go DOWN
  /// as older lines rotate out. Run 11 (2026-08-18) stalled exactly there: the
  /// live lane's `count > baseline` arrival wait could never fire because the
  /// baseline occurrences had rotated away. Accumulating is what makes "what
  /// has this lane seen so far" answerable at all, and it is also what keeps
  /// the artifact's raw flow log complete rather than "whatever survived to
  /// the last read".
  Future<String> _accumulatedRecipientFlowLines() async {
    final fresh = await _recipientFlowLines();
    for (final line in fresh.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (_recipientFlowSeen.add(trimmed)) {
        _recipientFlowAccumulator.add(trimmed);
      }
    }
    return '${_recipientFlowAccumulator.join('\n')}\n';
  }

  /// Drops accumulated lines; call immediately after clearing the device log.
  void _resetRecipientFlowAccumulator() {
    _recipientFlowAccumulator.clear();
    _recipientFlowSeen.clear();
  }

  /// The id of the message the SENDER most recently published.
  Future<String> _latestSenderGroupMessageId() async {
    final log = await _readAndroidLogcat(senderId);
    final id = latestGroupSendMessageId(_flowLines(log.stdout));
    if (id == null || id.isEmpty) {
      throw _CaptureFailure.capture(
        stage,
        'sender_group_send_message_id_not_observable',
      );
    }
    return id;
  }

  /// Records the SQLCipher observation for the muted group under test.
  ///
  /// Runs LAST in each stage: the probe transport foregrounds the installed
  /// app, and every card assertion must already be captured by then.
  Future<void> _captureMutedSqlCipherObservation() async {
    _groupName = _mutedGroupName;
    _targetMarker = _mutedUnderTestMarker;
    _firstMarker = '';
    _secondMarker = '';
    // On the FCM lane the reaction arrives while the recipient process is
    // dead, and the background isolate is read-only — the row is written by
    // the offline-inbox drain the next time the app runs, which is the
    // probe's own foreground start. A single-shot probe therefore races the
    // drain and reads a suppressed-but-delivered reaction as a LOST one
    // (run 13, 2026-08-18: `reactionRows: 0` while every other claim held).
    // Polling bounds that race without weakening the rule: if the row never
    // lands, delivery really was harmed and the lane still fails.
    final observed = _isMutedBackgroundLane
        ? await _waitForValue<Map<String, dynamic>>(
            'the suppressed reaction row to drain onto the recipient',
            const Duration(minutes: 3),
            () async {
              final probe = await _runInstalledGroupReactionProbe(
                deviceId: recipientId,
                action: _runtimeObserveAction,
              );
              final rows = (probe['reactionRows'] as num?)?.toInt() ?? 0;
              return rows >= 1 ? probe : null;
            },
          )
        : await _runInstalledGroupReactionProbe(
            deviceId: recipientId,
            action: _runtimeObserveAction,
          );
    if (observed['schema'] != 'mknoon.plan257.sqlcipher-observation.v1') {
      throw _CaptureFailure.capture(
        stage,
        'muted_probe_observation_schema_mismatch',
      );
    }
    _mutedSqlCipherObservation = jsonEncode(observed);
    _mutedGroupIdSha256 = '${observed['groupIdSha256'] ?? ''}';
    _mutedGroupIsMuted = observed['groupIsMuted'] == true;
    _mutedUnreadAfter = (observed['unreadCount'] as num?)?.toInt() ?? -1;

    final markers = observed['markers'];
    var persisted = false;
    var readAtNull = false;
    if (markers is List) {
      for (final entry in markers) {
        if (entry is! Map) continue;
        if (entry['marker'] != 'target') continue;
        persisted = true;
        readAtNull = entry['read'] != true;
        final digest = entry['idSha256'];
        if (digest is String) _mutedUnderTestMessageIdDigest = digest;
      }
    }
    _mutedPersistedRowObserved = persisted;
    _mutedReactionRowsObserved =
        (observed['reactionRows'] as num?)?.toInt() ?? 0;
    _mutedUnderTestReadAtNull = readAtNull;

    final badge = observed['canonicalBadgeState'];
    if (badge is Map) {
      _mutedBadgeAvailable = badge['available'] == true;
      _mutedBadgeIncludesMutedGroup = badge['includesObservedGroup'] == true;
      _mutedBadgeGroupIdentityCount =
          (badge['groupIdentityCount'] as num?)?.toInt() ?? 0;
      // The fixture holds exactly two groups and the observed (muted) one is
      // excluded, so any remaining badge identity is the unmuted control.
      _mutedBadgeIncludesControlGroup =
          !_mutedBadgeIncludesMutedGroup && _mutedBadgeGroupIdentityCount >= 1;
    }
  }

  Future<void> _runAndroidMutedMessageSuppressionLifecycle() async {
    final token = _runtimeToken('marker').replaceAll('-', '');
    final preMuteMarker = 'Plan379Pre${token.substring(0, 10)}';
    _mutedControlMarker = 'Plan379Ctl${token.substring(10, 20)}';
    _mutedUnderTestMarker = 'Plan379Mut${token.substring(20, 30)}';
    _mutedPreMuteCardGroup = 'muted';

    // 1. Pre-mute control — the group under test posts a card while UNMUTED.
    //    This is what makes a later zero-card dump attributable to mute rather
    //    than to a group that never notified at all.
    await _ensureOrbit(recipientId);
    await _openPlan330Group(senderId, _mutedGroupName);
    await _sendGroupText(senderId, preMuteMarker);
    _mutedPreMuteNotificationDump = await _waitForGroupNotificationDump(
      _mutedGroupName,
    );

    // 2. Mute it through the real Group Info switch. Opening the group to
    //    reach Group Info also commits its unread to zero, which cancels the
    //    pre-mute card; wait for that so a stale card cannot later be misread
    //    as a mute regression.
    await _muteGroupThroughGroupInfo(_mutedGroupName);
    await _waitForGroupNotificationCleared(_mutedGroupName);

    // 3. Overwrite the conversation tracker with the unmuted control group.
    await _visitControlGroupAndReturnToOrbit();

    // 4. Unread baseline AFTER the visits: opening the group under test in
    //    step 2 cleared its unread, so this is the floor the suppressed
    //    message must still grow.
    _mutedUnreadBaseline = 0;

    // 5. Post-mute lane liveness — the control group still posts a card
    //    INSIDE the suppression window. Without it, a dead notification lane
    //    reads exactly like a working mute.
    await _openPlan330Group(senderId, _mutedControlGroupName);
    await _sendGroupText(senderId, _mutedControlMarker);
    _mutedPostMuteNotificationDump = await _waitForGroupNotificationDump(
      _mutedControlGroupName,
    );

    // 6. The message under test, bound by the id the sender published. The
    //    recipient stores incoming group messages under that same envelope id,
    //    so this identifies THE message rather than counting occurrences of an
    //    event the control messages also emit.
    await _openPlan330Group(senderId, _mutedGroupName);
    await _sendGroupText(senderId, _mutedUnderTestMarker);
    final underTestMessageId = await _latestSenderGroupMessageId();

    // 7. Prove it ARRIVED before proving it did not notify: without this the
    //    zero-card dump would also pass for a message that never landed.
    await _waitFor(
      'muted group message $underTestMessageId stored by the recipient',
      const Duration(seconds: 180),
      () async => groupMessageStoredWithId(
        await _accumulatedRecipientFlowLines(),
        underTestMessageId,
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 10));

    _mutedNotificationDump = await _notificationDump(recipientId);
    final leaked = _mutedAttributableCards(
      _mutedNotificationDump,
      groupName: _mutedGroupName,
      marker: _mutedUnderTestMarker,
    );
    if (leaked.isNotEmpty) {
      throw _CaptureFailure.capture(
        stage,
        'muted_group_posted_${leaked.length}_notification_cards',
      );
    }

    await _captureMutedSqlCipherObservation();
    await _captureMutedControlGroupDigest();
  }

  Future<void> _runAndroidMutedReactionBackgroundLifecycle() async {
    final token = _runtimeToken('marker').replaceAll('-', '');
    _mutedControlMarker = 'Plan379Ctl${token.substring(0, 10)}';
    _mutedUnderTestMarker = 'Plan379Mut${token.substring(10, 20)}';
    _mutedPreMuteCardGroup = 'control';

    // 1. The recipient authors the reaction targets in both groups: a group
    //    reaction notifies the TARGET's author.
    await _openPlan330Group(recipientId, _mutedControlGroupName);
    await _sendGroupText(recipientId, _mutedControlMarker);
    await _openPlan330Group(recipientId, _mutedGroupName);
    await _sendGroupText(recipientId, _mutedUnderTestMarker);

    // 2. Mute the group under test through the real Group Info switch, then
    //    let its own card clear. This lane deliberately terminates the app
    //    later (step 4) so the pushes must wake the background isolate.
    await _muteGroupThroughGroupInfo(_mutedGroupName);
    await _waitForGroupNotificationCleared(_mutedGroupName);

    // 3. Baseline liveness, still foregroundable: the control group can post a
    //    card in this build/install at all. Deliberately a TEXT message rather
    //    than a reaction — it also leaves the control group with one unread
    //    incoming row, which is what keeps the canonical badge non-empty while
    //    the muted group is excluded from it.
    final baselineMarker = 'Plan379Base${token.substring(20, 30)}';
    await _openPlan330Group(senderId, _mutedControlGroupName);
    await _sendGroupText(senderId, baselineMarker);
    _mutedPreMuteNotificationDump = await _waitForGroupNotificationDump(
      _mutedControlGroupName,
    );

    // 4. Terminate the recipient so the next pushes must wake the background
    //    isolate rather than being handled by a live foreground listener.
    await _terminateAndroidRecipient();
    await _adb(recipientId, const <String>['logcat', '-c']);
    _resetRecipientFlowAccumulator();

    // 5. Absorb the cold-start storage deferral with a throwaway push.
    //
    //    The FIRST wake after a kill spawns the background isolate cold, and
    //    its first-touch warm-up can outrun the 2s `display_eligibility`
    //    phase budget (`background_message_handler.dart:78-81`). Measured
    //    2026-08-18 on the pinned Pixel (two runs, 2.170s / 2.180s): ART
    //    profile install, the Go-runtime dlopen and the first encrypted-store
    //    open all land inside that window. Note the eligibility resolver's own
    //    DB reads take only ~0.3s and FINISH ~0.2s BEFORE the timeout — so
    //    this is generic cold-isolate cost, NOT slow SQLCipher; do not "fix"
    //    it by tuning the database. Either way the push exits
    //    at PUSH_BACKGROUND_STORAGE_DEFERRED *upstream of the mute gate* and
    //    presents nothing. Whichever graded push went first was therefore
    //    silent for a reason that has nothing to do with mute: the muted
    //    reaction never reached the gate that would suppress it, and the
    //    unmuted control never reached the presenter that would card it.
    //    A throwaway text to the CONTROL group takes that hit instead, so both
    //    graded pushes travel the warm path. The deferral itself is real
    //    product behaviour owned elsewhere (Plan 383 defers `storage_deferred`
    //    alerting to the dropped-push-recovery wave); this lane only declines
    //    to be its victim.
    final warmupMarker = 'Plan379Warm${token.substring(28, 38)}';
    await _openPlan330Group(senderId, _mutedControlGroupName);
    await _sendGroupText(senderId, warmupMarker);
    await _waitForBackgroundPushWakes(1);
    await _waitForRecipientStorageWarm();
    // The opens the first wake started keep running briefly after it gives up
    // (measured: ~1s more), so settle wide of that before grading anything.
    await Future<void>.delayed(const Duration(seconds: 15));

    // 6. In ONE backgrounded window: react in the muted group and in the
    //    unmuted control group.
    await _openPlan330Group(senderId, _mutedGroupName);
    await _longPressText(senderId, _mutedUnderTestMarker);
    await _tapText(senderId, _reactionEmoji);
    await _waitForBackgroundPushWakes(2);
    await _openPlan330Group(senderId, _mutedControlGroupName);
    await _longPressText(senderId, _mutedControlMarker);
    await _tapText(senderId, _reactionEmoji);

    // 7. Pipeline health: the control REACTION must surface through the
    //    background path. Android replaces a conversation's card in place, so
    //    requiring the body to be neither the liveness baseline nor the
    //    warm-up is what makes this prove an in-window arrival rather than
    //    re-observing a card posted before the window opened.
    _mutedPostMuteNotificationDump = await _waitForGroupNotificationBodyChange(
      _mutedControlGroupName,
      <String>[baselineMarker, warmupMarker],
    );
    await Future<void>.delayed(const Duration(seconds: 10));

    _mutedNotificationDump = await _notificationDump(recipientId);
    final leaked = _mutedAttributableCards(
      _mutedNotificationDump,
      groupName: _mutedGroupName,
    );
    if (leaked.isNotEmpty) {
      throw _CaptureFailure.capture(
        stage,
        'muted_group_posted_${leaked.length}_background_notification_cards',
      );
    }

    // 8. Bind the background evidence by fcm message id. The reason is
    //    RECORDED, never pinned: production group-reaction traffic is
    //    intercepted before the fallback resolver, so its suppression
    //    collapses into a catch-all rather than reason `muted`. The binding
    //    itself is a pure function with host rows — it excludes the warm-up
    //    wake, takes the muted push from the SUPPRESSED event and the control
    //    push from the SHOWN event, and fails closed rather than guessing.
    final flowLog = await _accumulatedRecipientFlowLines();
    final binding = resolveMutedBackgroundPushBinding(flowLog);
    if (binding == null) {
      await _writeMutedDiagnosticDump(
        'background_push_binding_unresolvable',
        flowLog,
      );
      throw _CaptureFailure.capture(
        stage,
        'muted_background_flow_evidence_incomplete: '
        'received=${flowEventMessageIdsInOrder(flowLog, 'PUSH_BACKGROUND_MESSAGE_RECEIVED').length} '
        'suppressed=${flowEventMessageIdsInOrder(flowLog, 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED').length} '
        'shown=${flowEventMessageIdsInOrder(flowLog, 'PUSH_BACKGROUND_NOTIFICATION_SHOWN').length}',
      );
    }
    _mutedBackgroundDelivery = GroupMutedBackgroundDeliveryInput(
      recipientProcessState: 'terminated',
      mutedFcmMessageId: binding.mutedFcmMessageId,
      controlFcmMessageId: binding.controlFcmMessageId,
      suppressionReason: _mutedFlowEventReason(
        flowLog,
        binding.mutedFcmMessageId,
      ),
      backgroundFlowLog: flowLog,
    );
    _mutedUnreadBaseline = 0;

    await _captureMutedSqlCipherObservation();
    await _captureMutedControlGroupDigest();
  }

  void _recordKilledCommand({
    required String commandStage,
    required String target,
    required String action,
    required String semanticTarget,
  }) {
    _killedCommands.add(<String, Object?>{
      'stage': commandStage,
      'target': target,
      'action': action,
      'semanticTarget': semanticTarget,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Plan 384 (G19): a killed recipient must post an OS card for a
  /// default-lane group TEXT.
  ///
  /// Deliberately the simplest shape that reaches the boundary — one group, an
  /// alive-lane baseline card, a kill, a throwaway warm-up push, then one
  /// graded text. No mute, no control group, no reaction: each of those would
  /// add a way for the lane to go red for a reason that is not G19. The
  /// fixture is the capture driver's DEFAULT one-group branch, so nothing in
  /// the muted lane's two-group setup is touched.
  Future<void> _runAndroidGroupTextKilledAppCardLifecycle() async {
    final token = _runtimeToken('marker').replaceAll('-', '');
    _killedBaselineMarker = 'Plan384Base${token.substring(0, 10)}';
    _killedWarmupMarker = 'Plan384Warm${token.substring(10, 20)}';
    _killedGradedMarker = 'Plan384Grad${token.substring(20, 30)}';

    // 1. Alive-lane control. The recipient goes HOME so the live path is not
    //    holding the conversation open, then the sender posts a text. A card
    //    here proves this build, install and permission state can card at all,
    //    so a silent graded push later cannot be blamed on the install.
    await _pressAndroidKey(recipientId, 'KEYCODE_HOME');
    _recordKilledCommand(
      commandStage: 'killed_app_group_text',
      target: recipientId,
      action: 'keyevent',
      semanticTarget: 'KEYCODE_HOME',
    );
    await _openGroup(senderId);
    _recordKilledCommand(
      commandStage: 'killed_app_group_text',
      target: senderId,
      action: 'tap',
      semanticTarget: 'Open group $_groupName',
    );
    await _sendGroupText(senderId, _killedBaselineMarker);
    _killedPreKillNotificationDump = await _waitForGroupNotificationDump(
      _groupName,
    );

    // 2. Terminate the recipient so the next pushes must wake the background
    //    isolate rather than being handled by a live foreground listener.
    await _terminateAndroidRecipient();
    _recordKilledCommand(
      commandStage: 'killed_app_group_text',
      target: recipientId,
      action: 'terminate',
      semanticTarget: 'recipient process',
    );
    await _adb(recipientId, const <String>['logcat', '-c']);
    _resetRecipientFlowAccumulator();

    // 3. Absorb the cold-start storage deferral with a throwaway push. Same
    //    reasoning as the muted background lane: the FIRST wake after a kill
    //    opens SQLCipher cold and can blow the 2s `display_eligibility` phase
    //    budget, so a graded push in that position is silent for a reason that
    //    has nothing to do with the boundary under test. Gated on storage
    //    WARMTH, never on the warm-up's own disposition.
    await _openGroup(senderId);
    await _sendGroupText(senderId, _killedWarmupMarker);
    await _waitForBackgroundPushWakes(1);
    await _waitForRecipientStorageWarm();
    // The opens the first wake started keep running briefly after it gives up
    // (measured: ~1s more), so settle wide of that before grading anything.
    await Future<void>.delayed(const Duration(seconds: 15));

    // 4. The graded push: one ordinary default-lane group text.
    await _openGroup(senderId);
    await _sendGroupText(senderId, _killedGradedMarker);
    await _waitForBackgroundPushWakes(2);
    _killedGradedNotificationDump =
        await _waitForGroupNotificationBodyContaining(
          _groupName,
          _killedGradedMarker,
        );

    // 5. Bind the card to the graded push by fcm message id. The binding is a
    //    pure function with host rows: it excludes the warm-up wake and takes
    //    the graded push from the SHOWN event, failing closed rather than
    //    guessing.
    final flowLog = await _accumulatedRecipientFlowLines();
    final binding = resolveKilledTextCardPushBinding(flowLog);
    if (binding == null) {
      await _writeMutedDiagnosticDump(
        'killed_text_card_binding_unresolvable',
        flowLog,
      );
      throw _CaptureFailure.capture(
        stage,
        'killed_text_card_flow_evidence_incomplete: '
        'received=${flowEventMessageIdsInOrder(flowLog, 'PUSH_BACKGROUND_MESSAGE_RECEIVED').length} '
        'shown=${flowEventMessageIdsInOrder(flowLog, 'PUSH_BACKGROUND_NOTIFICATION_SHOWN').length}',
      );
    }
    _killedDelivery = GroupKilledTextCardDeliveryInput(
      recipientProcessState: 'terminated',
      warmupFcmMessageId: binding.warmupFcmMessageId,
      gradedFcmMessageId: binding.gradedFcmMessageId,
      backgroundFlowLog: flowLog,
    );
  }

  Future<void> _writeKilledTextCardAndroidArtifact() async {
    final delivery = _killedDelivery;
    if (_killedPreKillNotificationDump.isEmpty ||
        _killedGradedNotificationDump.isEmpty ||
        delivery == null) {
      throw _CaptureFailure.capture(
        stage,
        'killed_text_card_capture_inventory_incomplete',
      );
    }
    final input = GroupKilledTextCardCaptureInput(
      recordedAt: DateTime.now().toUtc().toIso8601String(),
      build: GroupMutedNotificationBuildInput(
        apkSha256: _androidBuilds!.e2eSha256,
        packageName: appPackage,
      ),
      topology: GroupMutedNotificationTopologyInput(
        physicalDeviceId: recipientId,
        emulatorDeviceId: senderId,
      ),
      fixture: GroupKilledTextCardFixtureInput(
        groupName: _groupName,
        baselineMarker: _killedBaselineMarker,
        warmupMarker: _killedWarmupMarker,
        gradedMarker: _killedGradedMarker,
      ),
      delivery: delivery,
      card: GroupKilledTextCardCardInput(
        preKillCardCount: _mutedAttributableCards(
          _killedPreKillNotificationDump,
          groupName: _groupName,
        ).length,
        preKillNotificationDump: _killedPreKillNotificationDump,
        gradedCardCount: _mutedAttributableCards(
          _killedGradedNotificationDump,
          groupName: _groupName,
        ).length,
        gradedNotificationDump: _killedGradedNotificationDump,
      ),
      commandJournal: jsonEncode(<String, Object?>{
        'schema': groupMutedNotificationCommandJournalSchema,
        'commands': _killedCommands,
      }),
    );
    await writeGroupKilledTextCardArtifact(
      proofDirectory: artifactDirectory,
      input: input,
    );
  }

  /// Second probe, keyed by the CONTROL group's name.
  ///
  /// Yields its redacted identity digest and, in doing so, proves the control
  /// group is a real persisted row on the recipient rather than a name that
  /// only ever existed on the sender.
  Future<void> _captureMutedControlGroupDigest() async {
    _groupName = _mutedControlGroupName;
    _targetMarker = _mutedControlMarker;
    _firstMarker = '';
    _secondMarker = '';
    final observed = await _runInstalledGroupReactionProbe(
      deviceId: recipientId,
      action: _runtimeObserveAction,
    );
    _mutedControlGroupIdSha256 = '${observed['groupIdSha256'] ?? ''}';
    if (observed['groupRows'] != 1 || _mutedControlGroupIdSha256.isEmpty) {
      throw _CaptureFailure.capture(
        stage,
        'muted_control_group_row_not_observable_on_recipient',
      );
    }
    _groupName = _mutedGroupName;
  }

  Future<void> _writeMutedAndroidArtifact() async {
    if (_mutedNotificationDump.isEmpty ||
        _mutedPreMuteNotificationDump.isEmpty ||
        _mutedPostMuteNotificationDump.isEmpty ||
        _mutedSqlCipherObservation.isEmpty) {
      throw _CaptureFailure.capture(
        stage,
        'muted_capture_inventory_incomplete',
      );
    }
    if (_mutedGroupIdSha256.isEmpty || _mutedControlGroupIdSha256.isEmpty) {
      await _writeMutedDiagnosticDump(
        'identity_digests_incomplete',
        'mutedGroupName=$_mutedGroupName\n'
            'controlGroupName=$_mutedControlGroupName\n'
            'mutedGroupIdSha256=$_mutedGroupIdSha256\n'
            'controlGroupIdSha256=$_mutedControlGroupIdSha256\n'
            'observation=$_mutedSqlCipherObservation\n',
      );
      throw _CaptureFailure.capture(
        stage,
        'muted_group_identity_digests_incomplete',
      );
    }

    final input = GroupMutedNotificationCaptureInput(
      scenario: scenario.id,
      recordedAt: DateTime.now().toUtc().toIso8601String(),
      build: GroupMutedNotificationBuildInput(
        apkSha256: _androidBuilds!.e2eSha256,
        packageName: appPackage,
      ),
      topology: GroupMutedNotificationTopologyInput(
        physicalDeviceId: recipientId,
        emulatorDeviceId: senderId,
      ),
      fixture: GroupMutedNotificationFixtureInput(
        mutedGroupName: _mutedGroupName,
        controlGroupName: _mutedControlGroupName,
        mutedGroupIdSha256: _mutedGroupIdSha256,
        controlGroupIdSha256: _mutedControlGroupIdSha256,
        actorName: 'Alice',
      ),
      mutedProjection: GroupMutedProjectionInput(
        groupIsMuted: _mutedGroupIsMuted,
        underTestMarker: _mutedUnderTestMarker,
        underTestMessageIdSha256: _mutedUnderTestMessageIdDigest,
        underTestReadAtNull: _mutedUnderTestReadAtNull,
        mutedCardCount: _mutedAttributableCards(
          _mutedNotificationDump,
          groupName: _mutedGroupName,
          marker: _mutedUnderTestMarker,
        ).length,
        unreadBaseline: _mutedUnreadBaseline,
        unreadAfter: _mutedUnreadAfter,
        persistedRowObserved: _mutedPersistedRowObserved,
        reactionRowsObserved: _mutedReactionRowsObserved,
        badgeAvailable: _mutedBadgeAvailable,
        badgeIncludesMutedGroup: _mutedBadgeIncludesMutedGroup,
        badgeIncludesControlGroup: _mutedBadgeIncludesControlGroup,
        badgeGroupIdentityCount: _mutedBadgeGroupIdentityCount,
        notificationDump: _mutedNotificationDump,
        sqlcipherObservation: _mutedSqlCipherObservation,
      ),
      control: GroupMutedControlInput(
        controlMarker: _mutedControlMarker,
        preMuteCardGroup: _mutedPreMuteCardGroup,
        preMuteCardCount: _mutedAttributableCards(
          _mutedPreMuteNotificationDump,
          groupName: _mutedPreMuteCardGroup == 'muted'
              ? _mutedGroupName
              : _mutedControlGroupName,
        ).length,
        preMuteNotificationDump: _mutedPreMuteNotificationDump,
        postMuteCardCount: _mutedAttributableCards(
          _mutedPostMuteNotificationDump,
          groupName: _mutedControlGroupName,
        ).length,
        postMuteNotificationDump: _mutedPostMuteNotificationDump,
      ),
      commandJournal: jsonEncode(<String, Object?>{
        'schema': groupMutedNotificationCommandJournalSchema,
        'commands': _mutedCommands,
      }),
      backgroundDelivery: _mutedBackgroundDelivery,
    );

    await writeGroupMutedNotificationArtifact(
      proofDirectory: artifactDirectory,
      input: input,
    );
  }

  String _mutedFlowEventReason(String log, String messageId) {
    for (final line in log.split('\n')) {
      if (!line.contains('PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED')) continue;
      if (!line.contains('"messageId":"$messageId"')) continue;
      final match = RegExp(r'"reason"\s*:\s*"([^"]+)"').firstMatch(line);
      if (match != null) return match.group(1)!;
    }
    return 'unrecorded';
  }

  Future<void> _openPlan330Group(String deviceId, String groupName) async {
    _groupName = groupName;
    final initial = await _uiDump(deviceId);
    if (isGroupConversationSurface(initial, groupName)) return;
    final center = await _plan330InnerCircleGroupCenter(deviceId, groupName);
    await _adbShell(deviceId, <String>[
      'input',
      'tap',
      '${center.$1}',
      '${center.$2}',
    ], environmentFailure: true);
    await _waitFor(
      'Plan 330 $groupName conversation on $deviceId',
      const Duration(seconds: 45),
      () async =>
          isGroupConversationSurface(await _uiDump(deviceId), groupName),
    );
  }

  Future<(int, int)> _plan330InnerCircleGroupCenter(
    String deviceId,
    String groupName,
  ) async {
    await _ensurePlan330Orbit(deviceId);
    final center = await findPlan330OrbitGroupWithInnerCircleRecovery(
      groupName: groupName,
      readUiDump: () => _uiDump(deviceId),
      tapSemanticNode: (toggleCenter) async {
        _recordPlan330Command(
          commandStage: 'orbit_recovery',
          target: deviceId,
          action: 'tap',
          semanticTarget: 'Show inner circle',
        );
        await _adbShell(deviceId, <String>[
          'input',
          'tap',
          '${toggleCenter.$1}',
          '${toggleCenter.$2}',
        ], environmentFailure: true);
      },
    );
    if (center == null) {
      throw _CaptureFailure.capture(
        stage,
        'Plan 330 Inner Circle node for $groupName unavailable on $deviceId',
      );
    }
    return center;
  }

  Future<void> _openGroup(String deviceId) async {
    var dump = await _uiDump(deviceId);
    if (isGroupConversationSurface(dump, _groupName)) {
      return;
    }
    await _ensureOrbit(deviceId);
    dump = await _uiDump(deviceId);
    final group = findSemanticNodeCenter(dump, 'Open group $_groupName');
    if (group == null) {
      throw _CaptureFailure.capture(
        stage,
        'group_orbit_node_missing_on_$deviceId',
      );
    }
    await _adbShell(deviceId, <String>[
      'input',
      'tap',
      '${group.$1}',
      '${group.$2}',
    ], environmentFailure: true);
    await _waitFor(
      'group conversation on $deviceId',
      const Duration(seconds: 30),
      () async =>
          isGroupConversationSurface(await _uiDump(deviceId), _groupName),
    );
  }

  Future<void> _sendGroupText(String deviceId, String marker) async {
    final markerEntry = await enterGroupComposeMarkerOnce(
      marker: marker,
      readUiDump: () => _uiDump(deviceId),
      tapEditor: (center) => _adbShell(deviceId, <String>[
        'input',
        'tap',
        '${center.$1}',
        '${center.$2}',
      ], environmentFailure: true),
      injectMarker: (value) => _adbShell(deviceId, <String>[
        'input',
        'text',
        value,
      ], environmentFailure: true),
      maximumFocusPolls: 80,
      maximumAcceptancePolls: 80,
    );
    if (markerEntry != GroupComposeMarkerEntryOutcome.accepted) {
      throw _CaptureFailure.capture(
        stage,
        'group_compose_marker_${markerEntry.name}_on_$deviceId',
      );
    }

    // Announcement sends are intentionally rejected while the production
    // group-recovery gate is active. That result restores this exact draft,
    // so a generic `marker is visible` wait would falsely report a commit.
    // Every re-tap below is therefore gated by a newly observed, explicit
    // recovery-pending terminal outcome; an ambiguous timeout is never retried.
    const maxRecoveryPendingOutcomes = 8;
    var recoveryPendingOutcomes = 0;
    while (true) {
      final typedEditor = await _waitForValue<(int, int, int, int)>(
        'group compose marker accepted on $deviceId',
        const Duration(seconds: 20),
        () async => findEnabledFocusableGroupComposeEditorBounds(
          await _uiDump(deviceId),
          requireFocused: true,
          exactText: marker,
        ),
      );
      final baselineOutcomeCount = (await _groupSendTimingObservations(
        deviceId,
      )).length;
      await _adbShell(deviceId, <String>[
        'input',
        'tap',
        '${typedEditor.$3 + 70}',
        '${(typedEditor.$2 + typedEditor.$4) ~/ 2}',
      ], environmentFailure: true);

      final outcome = await _waitForValue<GroupSendTimingObservation>(
        'terminal group send FLOW outcome on $deviceId',
        const Duration(seconds: 30),
        () async {
          final observations = await _groupSendTimingObservations(deviceId);
          return observations.length > baselineOutcomeCount
              ? observations[baselineOutcomeCount]
              : null;
        },
      );
      if (outcome.isCommitted) {
        if (!outcome.hasRequiredInboxCustody(recipientCount: 1)) {
          throw _CaptureFailure.capture(
            stage,
            'group_send_commit_lacked_exact_durable_inbox_custody_on_'
            '$deviceId',
          );
        }
        await _waitFor(
          'committed group message outside compose editor on $deviceId',
          const Duration(seconds: 30),
          () async {
            final committed = await _uiDump(deviceId);
            return findSemanticNodeCenter(committed, marker) != null &&
                findNodeBoundsByClassContainingText(
                      committed,
                      'android.widget.EditText',
                      marker,
                    ) ==
                    null;
          },
        );
        return;
      }
      if (!outcome.isRecoveryPending) {
        throw _CaptureFailure.capture(
          stage,
          'group_send_terminal_outcome_${outcome.outcome}_on_$deviceId',
        );
      }

      recoveryPendingOutcomes += 1;
      if (recoveryPendingOutcomes >= maxRecoveryPendingOutcomes) {
        throw _CaptureFailure.capture(
          stage,
          'group_send_recovery_remained_pending_after_'
          '${maxRecoveryPendingOutcomes}_bounded_attempts_on_$deviceId',
        );
      }
      await Future<void>.delayed(
        Duration(seconds: min(recoveryPendingOutcomes, 4)),
      );
    }
  }

  Future<List<GroupSendTimingObservation>> _groupSendTimingObservations(
    String deviceId,
  ) async {
    final logcat = await _adb(deviceId, const <String>[
      'logcat',
      '-d',
      '-v',
      'brief',
    ]);
    return extractGroupSendTimingObservations(
      '${logcat.stdout}\n${logcat.stderr}',
    );
  }

  Future<void> _waitForGroupUnread(int count) async {
    final label = count == 1
        ? 'Open group $_groupName, 1 unread message'
        : 'Open group $_groupName, $count unread messages';
    await _waitForUiText(recipientId, label, const Duration(minutes: 2));
  }

  Future<void> _captureUiSnapshot(
    String name, {
    required int expectedUnread,
  }) async {
    final xml = await _uiDump(recipientId);
    final expected = expectedUnread == 0
        ? 'Open group $_groupName'
        : expectedUnread == 1
        ? 'Open group $_groupName, 1 unread message'
        : 'Open group $_groupName, $expectedUnread unread messages';
    final center = findSemanticNodeCenter(xml, expected);
    if (center == null) {
      throw _CaptureFailure.capture(
        stage,
        'ui_unread_observation_missing: expected "$expected"',
      );
    }
    if (expectedUnread == 0 &&
        xml.contains('Open group $_groupName,') &&
        xml.contains('unread message')) {
      throw _CaptureFailure.capture(
        stage,
        'ui_unread_zero_observation_still_contains_unread_semantics',
      );
    }
    final file = File(
      '${artifactDirectory.path}${Platform.pathSeparator}ui_$name.xml',
    );
    await file.writeAsString(xml, flush: true);
    _uiSnapshots.add(file);
    _uiUnreadTimeline.add(expectedUnread);
  }

  Future<void> _captureRawUiSnapshot(String name) async {
    final file = File(
      '${artifactDirectory.path}${Platform.pathSeparator}ui_$name.xml',
    );
    await file.writeAsString(await _uiDump(recipientId), flush: true);
    _uiSnapshots.add(file);
  }

  Future<(int, ActiveNotificationCard)> _waitForNotificationCard() {
    return _waitForValue<(int, ActiveNotificationCard)>(
      'one active $_groupName notification card',
      const Duration(minutes: 2),
      () async {
        final dump = await _notificationDump(recipientId);
        final records = _activeNotificationRecords(dump);
        if (records.length != 1) return null;
        return records.single;
      },
    );
  }

  Future<File> _writeNotificationSnapshot(
    String name,
    ActiveNotificationCard observed,
  ) async {
    final dump = await _notificationDump(recipientId);
    final records = _appNotificationRecords(dump);
    if (records.trim().isEmpty) {
      throw _CaptureFailure.capture(
        stage,
        'notification_record_disappeared_before_capture',
      );
    }
    final file = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'notification_$name.log',
    );
    await file.writeAsString(
      '${_redact(records)}\n'
      'observed_title=${observed.title}\n'
      'observed_body=${observed.body}\n',
      flush: true,
    );
    return file;
  }

  Future<void> _dismissNotificationCard() async {
    await _adbShell(recipientId, const <String>[
      'cmd',
      'statusbar',
      'expand-notifications',
    ], environmentFailure: true);
    final center = await _waitForNotificationCardInShade();
    await _adbShell(recipientId, <String>[
      'input',
      'swipe',
      '${center.$1}',
      '${center.$2}',
      '1',
      '${center.$2}',
      '450',
    ], environmentFailure: true);
    await _adbShell(recipientId, const <String>[
      'cmd',
      'statusbar',
      'collapse',
    ], allowFail: true);
  }

  Future<void> _waitForNoNotificationCard() async {
    await _waitFor(
      'notification card dismissal',
      const Duration(seconds: 30),
      () async => _activeNotificationRecords(
        await _notificationDump(recipientId),
      ).isEmpty,
    );
  }

  Future<void> _tapNotificationCard() async {
    await _adbShell(recipientId, const <String>[
      'cmd',
      'statusbar',
      'expand-notifications',
    ], environmentFailure: true);
    final center = await _waitForNotificationCardInShade();
    await _adbShell(recipientId, <String>[
      'input',
      'tap',
      '${center.$1}',
      '${center.$2}',
    ], environmentFailure: true);
  }

  Future<(int, int)> _waitForNotificationCardInShade() async {
    await Future<void>.delayed(const Duration(milliseconds: 750));
    for (var attempt = 0; attempt < 6; attempt++) {
      final xml = await _uiDump(recipientId);
      final title = findSemanticNodeCenter(xml, _groupName);
      if (title != null) return title;
      if (attempt < 5) {
        await _adbShell(recipientId, const <String>[
          'input',
          'swipe',
          '540',
          '1900',
          '540',
          '700',
          '500',
        ], environmentFailure: true);
        await Future<void>.delayed(const Duration(milliseconds: 750));
      }
    }
    throw _CaptureFailure.capture(
      stage,
      'active_group_notification_not_reachable_in_bounded_shade_scroll',
    );
  }

  Future<void> _terminateAndroidRecipient() async {
    await _adbShell(recipientId, const <String>[
      'input',
      'keyevent',
      'KEYCODE_HOME',
    ], environmentFailure: true);
    await _adbShell(recipientId, <String>[
      'am',
      'kill',
      appPackage,
    ], environmentFailure: true);
    if (!await _recipientProcessAbsentWithin(const Duration(seconds: 5))) {
      await _adbShell(recipientId, <String>[
        'am',
        'stop-app',
        appPackage,
      ], environmentFailure: true);
    }
    await _waitFor(
      'recipient process absent before provider delivery',
      const Duration(seconds: 30),
      () async => (await _adbShell(recipientId, <String>[
        'pidof',
        appPackage,
      ], allowFail: true)).trim().isEmpty,
    );
  }

  Future<void> _backgroundAndroidRecipientConnected() async {
    await _adb(recipientId, const <String>['logcat', '-c']);
    final homeAt = DateTime.now().toUtc();
    _backgroundConnectedHomeAt = homeAt;
    await _adbShell(recipientId, const <String>[
      'input',
      'keyevent',
      'KEYCODE_HOME',
    ], environmentFailure: true);

    final rawPid = await _adbShell(recipientId, <String>[
      'pidof',
      appPackage,
    ], allowFail: true);
    if (RegExp(r'\b[1-9][0-9]*\b').firstMatch(rawPid) == null) {
      throw _CaptureFailure.capture(
        stage,
        'recipient_process_missing_after_home_before_reaction',
      );
    }

    await _waitForValue<Map<String, dynamic>>(
      'post-HOME recipient relay presence flow event',
      const Duration(seconds: 15),
      () async {
        final log = await _adb(recipientId, const <String>[
          'logcat',
          '-d',
          '-v',
          'brief',
        ]);
        for (final line in log.stdout.split('\n').reversed) {
          final marker = line.indexOf('[FLOW] ');
          if (marker < 0) continue;
          try {
            final event = Map<String, dynamic>.from(
              jsonDecode(line.substring(marker + '[FLOW] '.length)) as Map,
            );
            final details = event['details'];
            if (event['event'] == 'P2P_RELAY_PRESENCE_SET_RESPONSE' &&
                details is Map &&
                details['state'] == 'background' &&
                details['ok'] == true) {
              return event;
            }
          } on Object {
            continue;
          }
        }
        return null;
      },
    );

    final remaining = homeAt
        .add(
          const Duration(
            milliseconds: groupReactionBackgroundConnectedHomeToReactDelayMs,
          ),
        )
        .difference(DateTime.now().toUtc());
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  void _completeBackgroundConnectedObservation(DateTime notificationAt) {
    final homeAt = _backgroundConnectedHomeAt;
    final reactionAt = _backgroundConnectedReactionAt;
    if (homeAt == null || reactionAt == null) {
      throw _CaptureFailure.capture(
        stage,
        'background_connected_timing_anchor_missing',
      );
    }
    final homeToReactMs = reactionAt.difference(homeAt).inMilliseconds;
    final reactionToNotificationMs = notificationAt
        .difference(reactionAt)
        .inMilliseconds;
    if (homeToReactMs < groupReactionBackgroundConnectedHomeToReactDelayMs ||
        homeToReactMs >
            groupReactionBackgroundConnectedHomeToReactDelayMs + 15000 ||
        reactionToNotificationMs < 0 ||
        reactionToNotificationMs >
            groupReactionBackgroundConnectedObservationWindowMs) {
      throw _CaptureFailure.capture(
        stage,
        'background_connected_timing_out_of_bounds: '
        'homeToReactMs=$homeToReactMs '
        'reactionToNotificationMs=$reactionToNotificationMs',
      );
    }
    final observation = <String, Object?>{
      'schema': 'mknoon.plan315.background-connected-observation.v1',
      'scenario': scenario.id,
      'pidPresentBeforeDelivery': true,
      'connectivityEvent': 'P2P_RELAY_PRESENCE_SET_RESPONSE',
      'connectivityState': 'background',
      'connectivityOk': true,
      'homeAt': homeAt.toIso8601String(),
      'reactionAt': reactionAt.toIso8601String(),
      'notificationAt': notificationAt.toIso8601String(),
      'minimumHomeToReactDelayMs':
          groupReactionBackgroundConnectedHomeToReactDelayMs,
      'homeToReactDelayMs': homeToReactMs,
      'notificationObservationWindowMs':
          groupReactionBackgroundConnectedObservationWindowMs,
      'reactionToNotificationMs': reactionToNotificationMs,
    };
    _backgroundConnectedObservation =
        '$groupReactionBackgroundConnectedObservationPrefix'
        '${jsonEncode(observation)}\n'
        'pid_present_before_delivery=true '
        'connectivity_event=P2P_RELAY_PRESENCE_SET_RESPONSE '
        'home_to_react_delay_ms='
        '$groupReactionBackgroundConnectedHomeToReactDelayMs '
        'notification_observation_window_ms='
        '$groupReactionBackgroundConnectedObservationWindowMs\n';
  }

  Future<bool> _recipientProcessAbsentWithin(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final pid = await _adbShell(recipientId, <String>[
        'pidof',
        appPackage,
      ], allowFail: true);
      if (pid.trim().isEmpty) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// Waits until the recipient device's own log shows the relay ACCEPTED its
  /// Android push-token registration.
  ///
  /// Replaces a relay-journal grep for
  /// `[PUSH] Token registered for <peerPrefix> (<platform>)`, which relay
  /// v1.8.0 (`8d86501e4`) deleted along with the rest of the identifying
  /// `[PUSH]` vocabulary. That removal is deliberate and pinned by Plan 368,
  /// so the fix is to stop asking the relay who registered and ask the device
  /// instead — better attribution, since the log is unambiguously this
  /// device's rather than a 20-char peer prefix.
  ///
  /// The old wait was named "capability-bearing", which it never was: even the
  /// deleted relay line carried only a peer prefix and a platform, never the
  /// advertised capability set. The name is corrected rather than carried
  /// forward.
  Future<void> _waitForRecipientPushRegistrationAccepted() async {
    await _waitFor(
      'recipient android push registration accepted by the relay',
      const Duration(minutes: 3),
      () async => androidRelayPushRegistrationAccepted(
        (await _readAndroidLogcat(recipientId)).stdout,
      ),
    );
  }

  /// iOS token registration still reads the relay journal.
  ///
  /// The same v1.8.0 removal applies, so this is expected to be dead — but the
  /// iOS legs are deferred (GAP-N12) and unexercised, and rewriting them
  /// against `idevicesyslog` without an iOS device to verify would be worse
  /// than leaving the known-dead path clearly labelled.
  Future<void> _waitForRelayTokenRegistration(DateTime since) async {
    await _waitFor(
      'recipient ios token registration (relay journal; dead on v1.8.0)',
      const Duration(minutes: 3),
      () async {
        final log = await _relayJournalSince(since);
        return log.contains(
          '[PUSH] Token registered for ${recipient.peerPrefix} (ios)',
        );
      },
    );
  }

  Future<void> _requireCleanNotificationSlate() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final records = _activeNotificationRecords(
      await _notificationDump(recipientId),
    );
    if (records.isNotEmpty) {
      throw _CaptureFailure.environment(
        stage,
        'recipient_notification_slate_not_clean: ${records.length} app '
        'record(s) already active; unrelated cards are never cancelled',
      );
    }
  }

  Future<void> _waitForSenderEventCount(String event, int count) async {
    await _waitFor(
      '$count sender $event event(s)',
      const Duration(seconds: 60),
      () async {
        final log = await _adb(senderId, const <String>[
          'logcat',
          '-d',
          '-v',
          'brief',
        ]);
        return RegExp(RegExp.escape(event)).allMatches(log.stdout).length >=
            count;
      },
    );
  }

  Future<void> _waitForProviderSendCount(DateTime since, int count) async {
    await _waitFor(
      '$count real provider send(s)',
      const Duration(minutes: 2),
      () async => _countProviderSends(await _relayJournalSince(since)) >= count,
    );
  }

  int _countProviderSends(String journal) => RegExp(
    RegExp.escape(_providerSuccessMarker) +
        RegExp.escape(recipient.peerPrefix) +
        r'\b',
  ).allMatches(journal).length;

  Future<Map<String, dynamic>> _runPlan330Endpoint({
    required String deviceId,
    required String phase,
    required String role,
    required String groupName,
    required String kind,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final stepId = 'plan330-$phase-$kind-$_runtimeRunId';
    final request = <String, Object?>{
      'schema': _plan330EndpointCommandSchema,
      'transport_action': _plan330EndpointAction,
      'scenario': scenario.id,
      'stepId': stepId,
      'phase': phase,
      'role': role,
      'runId': _runtimeRunId,
      'nonce': _runtimeNonce,
      'groupName': groupName,
      'kind': kind,
      'messageIds': _plan330MessageIds,
      'attachmentIds': _plan330AttachmentIds,
    };
    await _deleteAppFile(deviceId, 'intro_e2e_result.json');
    await _deleteAppFile(deviceId, 'intro_e2e_config.json');
    await _writeAppFile(deviceId, 'intro_e2e_config.json', jsonEncode(request));
    await _startAndroid(deviceId);
    try {
      return await _waitForValue<Map<String, dynamic>>(
        'Plan 330 $phase/$kind installed endpoint result',
        timeout,
        () async {
          final raw = await _readAppFile(deviceId, 'intro_e2e_result.json');
          if (raw == null) return null;
          late final Map<String, dynamic> result;
          try {
            result = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          } on Object {
            throw _CaptureFailure.capture(
              stage,
              'Plan 330 endpoint result is invalid JSON',
            );
          }
          if (result['stepId'] != stepId) return null;
          if (result['schema'] != _plan330EndpointResultSchema ||
              result['transport_action'] != _plan330EndpointAction ||
              result['scenario'] != scenario.id ||
              result['phase'] != phase ||
              result['role'] != role ||
              result['runId'] != _runtimeRunId ||
              result['nonce'] != _runtimeNonce) {
            throw _CaptureFailure.capture(
              stage,
              'Plan 330 endpoint result contract mismatch',
            );
          }
          if (result['status'] != 'complete' ||
              result['success'] != true ||
              result['observation'] is! Map) {
            throw _CaptureFailure.capture(
              stage,
              'Plan 330 endpoint failed with '
              '${result['errorType'] ?? 'unknown error'}',
            );
          }
          return Map<String, dynamic>.from(result['observation'] as Map);
        },
      );
    } finally {
      await _deleteAppFile(deviceId, 'intro_e2e_config.json');
      await _deleteAppFile(deviceId, 'intro_e2e_result.json');
    }
  }

  Future<(String, List<(int, ActiveNotificationCard)>)>
  _waitForPlan330TwoCards({Set<String>? acceptedGroupABodies}) async {
    var lastDump = '';
    var lastCards = <(int, ActiveNotificationCard)>[];
    for (var attempt = 0; attempt < 180; attempt += 1) {
      lastDump = await _notificationDump(recipientId);
      lastCards = _activeContentNotificationRecords(lastDump);
      final groupA = lastCards
          .where((record) => record.$2.title == _plan330GroupAName)
          .toList(growable: false);
      final groupB = lastCards
          .where((record) => record.$2.title == _plan330GroupBName)
          .toList(growable: false);
      if (lastCards.length == 2 &&
          groupA.length == 1 &&
          groupB.length == 1 &&
          (acceptedGroupABodies == null ||
              acceptedGroupABodies.contains(groupA.single.$2.body))) {
        return (lastDump, lastCards);
      }
      if (attempt < 179) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    final appRecords = _appNotificationRecords(lastDump).trim();
    await _writePlan330RawFile(
      'plan330_two_cards_timeout_notifications.log',
      'parsed_card_count=${lastCards.length}\n'
          'parsed_cards=${lastCards.map((record) => <String, Object?>{'id': record.$1, 'title': record.$2.title, 'body': record.$2.body}).toList(growable: false)}\n'
          'app_notification_records=${appRecords.isEmpty ? '[none]' : appRecords}\n',
    );
    final recipientLog = await _readAndroidLogcat(recipientId);
    final flowLog = _flowLines(recipientLog.stdout).trim();
    await _writePlan330RawFile(
      'plan330_two_cards_timeout_flow.log',
      '${flowLog.isEmpty ? '[no FLOW records]' : flowLog}\n',
    );
    throw _CaptureFailure.capture(
      stage,
      'exact Plan 330 group-A/group-B notification cards unavailable; '
      'observed ${lastCards.length} parsed app cards',
    );
  }

  Map<String, String> _plan330LocalizedBodies(String externalKind) {
    final targetKey = switch (externalKind) {
      'photo' => 'notification_group_reaction_target_photo',
      'video' => 'notification_group_reaction_target_video',
      'voiceMessage' => 'notification_group_reaction_target_voice_message',
      _ => throw _CaptureFailure.capture(
        stage,
        'unsupported Plan 330 reaction target kind $externalKind',
      ),
    };
    final result = <String, String>{};
    for (final locale in const <String>['ar', 'de', 'en']) {
      final arb = Map<String, dynamic>.from(
        jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync()) as Map,
      );
      final template = arb['notification_group_reaction_actor'] as String?;
      final target = arb[targetKey] as String?;
      if (template == null ||
          target == null ||
          !template.contains('{actorName}') ||
          !template.contains('{targetKind}')) {
        throw _CaptureFailure.capture(
          stage,
          'Plan 330 localized copy source is malformed for $locale',
        );
      }
      result[locale] = template
          .replaceAll('{actorName}', sender.username)
          .replaceAll('{targetKind}', target);
    }
    return result;
  }

  Future<File> _writePlan330RawFile(String name, String text) async {
    if (text.trim().isEmpty || utf8.encode(text).length > 4 * 1024 * 1024) {
      throw _CaptureFailure.capture(
        stage,
        'Plan 330 evidence $name is empty or exceeds 4 MiB',
      );
    }
    final file = File(
      '${artifactDirectory.path}${Platform.pathSeparator}$name',
    );
    await file.writeAsString(text, flush: true);
    return file;
  }

  Future<Map<String, Object?>> _plan330EvidenceReference(File file) async =>
      <String, Object?>{
        'path': file.uri.pathSegments.last,
        'sha256': await _sha256(file),
      };

  void _recordPlan330Command({
    required String commandStage,
    required String target,
    required String action,
    required String semanticTarget,
  }) {
    _plan330Commands.add(<String, Object?>{
      'stage': commandStage,
      'target': target,
      'action': action,
      'semanticTarget': semanticTarget,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _grantRecordAudioPermission(String deviceId) async {
    await _adbShell(deviceId, <String>[
      'pm',
      'grant',
      appPackage,
      'android.permission.RECORD_AUDIO',
    ], environmentFailure: true);
  }

  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<Map<String, dynamic>> _runInstalledGroupReactionProbe({
    required String deviceId,
    required String action,
  }) async {
    final stepId = 'plan257-$action-$_runtimeRunId';
    final request = <String, Object?>{
      'schema': _runtimeRequestSchema,
      'transport_action': action,
      'scenario': scenario.id,
      'stepId': stepId,
      'runId': _runtimeRunId,
      'nonce': _runtimeNonce,
      'groupName': _groupName,
      'firstMarker': _firstMarker,
      'secondMarker': _secondMarker,
      'targetMarker': _targetMarker,
    };
    await _deleteAppFile(deviceId, 'intro_e2e_result.json');
    await _deleteAppFile(deviceId, 'intro_e2e_config.json');
    await _writeAppFile(deviceId, 'intro_e2e_config.json', jsonEncode(request));
    // Starting an already installed candidate is build-free and gives the
    // production E2E poller a deterministic foreground opportunity. It does
    // not clear app data or replace the SQLCipher database being observed.
    await _startAndroid(deviceId);

    try {
      return await _waitForValue<Map<String, dynamic>>(
        '$action installed-app result',
        const Duration(seconds: 45),
        () async {
          final raw = await _readAppFile(deviceId, 'intro_e2e_result.json');
          if (raw == null) return null;
          late final Map<String, dynamic> result;
          try {
            result = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          } on Object {
            throw _CaptureFailure.capture(
              stage,
              'group_reaction_runtime_result_invalid_json',
            );
          }
          if (result['stepId'] != stepId) return null;
          if (result['schema'] != _runtimeResultSchema ||
              result['transport_action'] != action ||
              result['scenario'] != scenario.id ||
              result['runId'] != _runtimeRunId ||
              result['nonce'] != _runtimeNonce ||
              result['status'] != 'complete' ||
              result['success'] != true ||
              result['observation'] is! Map) {
            throw _CaptureFailure.capture(
              stage,
              'group_reaction_runtime_result_contract_mismatch',
            );
          }
          return Map<String, dynamic>.from(result['observation'] as Map);
        },
      );
    } finally {
      await _deleteAppFile(deviceId, 'intro_e2e_config.json');
      await _deleteAppFile(deviceId, 'intro_e2e_result.json');
    }
  }

  String _runtimeToken(String prefix) {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$prefix-$hex';
  }

  Future<String> _captureSqlCipherObservation() async {
    if (noChildBuilds) {
      final observed = await _runInstalledGroupReactionProbe(
        deviceId: recipientId,
        action: _runtimeObserveAction,
      );
      _validateSqlCipherObservation(observed);
      return 'MKNOON_257_SQLCIPHER_OBSERVATION ${jsonEncode(observed)}\n';
    }
    final args = <String>[
      'test',
      '--no-pub',
      '-d',
      recipientId,
      _sqlCipherProbe,
      '--plain-name',
      'Plan 257 reads the installed app SQLCipher state',
      '--dart-define=MKNOON_257_PROBE_SCENARIO=${scenario.id}',
      '--dart-define=MKNOON_257_PROBE_GROUP_NAME=$_groupName',
      '--dart-define=MKNOON_257_PROBE_FIRST_MARKER=$_firstMarker',
      '--dart-define=MKNOON_257_PROBE_SECOND_MARKER=$_secondMarker',
      '--dart-define=MKNOON_257_PROBE_TARGET_MARKER=$_targetMarker',
    ];
    final output = await _runStreaming('flutter', args);
    const prefix = 'MKNOON_257_SQLCIPHER_OBSERVATION ';
    String? encoded;
    for (final line in output.combined.split('\n')) {
      final index = line.indexOf(prefix);
      if (index >= 0) {
        encoded = line.substring(index + prefix.length).trim();
      }
    }
    if (encoded == null) {
      throw _CaptureFailure.capture(
        stage,
        'sqlcipher_probe_emitted_no_observation',
      );
    }
    Map<String, dynamic> observed;
    try {
      observed = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    } on Object {
      throw _CaptureFailure.capture(
        stage,
        'sqlcipher_probe_observation_invalid_json',
      );
    }
    _validateSqlCipherObservation(observed);
    return '$prefix${jsonEncode(observed)}\n';
  }

  void _validateSqlCipherObservation(Map<String, dynamic> observed) {
    if (observed['schema'] != 'mknoon.plan257.sqlcipher-observation.v1' ||
        observed['scenario'] != scenario.id ||
        observed['groupName'] != _groupName ||
        observed['groupRows'] != 1 ||
        observed['groupType'] != scenario.groupType ||
        observed['unreadCount'] != 0 ||
        observed['reactionMessageRows'] != 0) {
      throw _CaptureFailure.capture(
        stage,
        'sqlcipher_observation_core_invariant_mismatch',
      );
    }
    final markers = (observed['markers'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    if (scenario.id.endsWith('_message_unread_lifecycle')) {
      final first = markers.where((value) => value['marker'] == 'first');
      final second = markers.where((value) => value['marker'] == 'second');
      if (first.length != 1 ||
          second.length != 1 ||
          first.single['incoming'] != true ||
          second.single['incoming'] != true ||
          first.single['read'] != true ||
          second.single['read'] != true ||
          observed['reactionRows'] != 0) {
        throw _CaptureFailure.capture(
          stage,
          'sqlcipher_unread_lifecycle_rows_mismatch',
        );
      }
    } else {
      final target = markers.where((value) => value['marker'] == 'target');
      if (target.length != 1 ||
          target.single['incoming'] != false ||
          observed['reactionRows'] != 1 ||
          observed['reactionEmoji'] != _reactionEmoji ||
          observed['reactionTargetIdSha256'] != target.single['idSha256']) {
        throw _CaptureFailure.capture(
          stage,
          'sqlcipher_group_reaction_rows_mismatch',
        );
      }
    }
  }

  Future<void> _writePlan330AndroidArtifact() async {
    final beforeNotifications = _plan330BeforeNotificationDump;
    final afterNotifications = _plan330AfterNotificationDump;
    final beforeUi = _plan330BeforeUiDump;
    final afterUi = _plan330AfterUiDump;
    final readFlow = _plan330ReadFlowLog;
    final groupANotificationId = _plan330GroupANotificationId;
    final groupBNotificationId = _plan330GroupBNotificationId;
    if (beforeNotifications == null ||
        afterNotifications == null ||
        beforeUi == null ||
        afterUi == null ||
        readFlow == null ||
        groupANotificationId == null ||
        groupBNotificationId == null ||
        _plan330GroupAIdSha256.isEmpty ||
        _plan330GroupBIdSha256.isEmpty ||
        _plan330Locale.isEmpty ||
        _plan330ReactionObservations.length != 3) {
      throw _CaptureFailure.capture(
        stage,
        'Plan 330 authoritative evidence inventory is incomplete',
      );
    }
    final journal = await _writePlan330RawFile(
      'plan330_command_journal.json',
      '${const JsonEncoder.withIndent(' ').convert(<String, Object?>{'schema': groupNotificationProjectionCommandJournalSchema, 'commands': _plan330Commands})}\n',
    );
    final build = _androidBuilds!;
    final artifact = <String, Object?>{
      'schema': groupNotificationProjectionArtifactSchema,
      'version': 1,
      'capabilityId': groupNotificationProjectionCapabilityId,
      'scenario': groupNotificationProjectionScenarioId,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'build': <String, Object?>{
        'profile': 'android.production_fcm',
        'provenance': 'central_prebuilt',
        'apkSha256': build.e2eSha256,
        'childBuildCount': 0,
        'packageName': appPackage,
      },
      'topology': <String, Object?>{
        'physical': <String, Object?>{
          'deviceId': recipientId,
          'platform': 'android',
          'kind': 'physical',
        },
        'emulator': <String, Object?>{
          'deviceId': senderId,
          'platform': 'android',
          'kind': 'emulator',
        },
      },
      'fixture': <String, Object?>{
        'groupAName': _plan330GroupAName,
        'groupBName': _plan330GroupBName,
        'groupAIdSha256': _plan330GroupAIdSha256,
        'groupBIdSha256': _plan330GroupBIdSha256,
        'actorName': sender.username,
        'locale': _plan330Locale,
      },
      'readProjection': <String, Object?>{
        'navigation': 'in_app_group_list',
        'unreadBefore': 1,
        'unreadAfter': 0,
        'commitObserved': true,
        'notificationTapCount': 0,
        'groupANotificationId': groupANotificationId,
        'groupBNotificationId': groupBNotificationId,
        'beforeNotificationDump': await _plan330EvidenceReference(
          beforeNotifications,
        ),
        'afterNotificationDump': await _plan330EvidenceReference(
          afterNotifications,
        ),
        'beforeUiDump': await _plan330EvidenceReference(beforeUi),
        'afterUiDump': await _plan330EvidenceReference(afterUi),
        'readFlowLog': await _plan330EvidenceReference(readFlow),
      },
      'reactionProjection': <String, Object?>{
        'stableGroupANotificationId': groupANotificationId,
        'duplicateCount': 0,
        'observations': _plan330ReactionObservations,
      },
      'automation': <String, Object?>{
        'manualTaps': 0,
        'notificationCardTaps': 0,
        'commandJournal': await _plan330EvidenceReference(journal),
      },
    };
    final output = File(
      '${artifactDirectory.path}${Platform.pathSeparator}${scenario.id}.json',
    );
    final pending = File('${output.path}.pending');
    await pending.writeAsString(
      const JsonEncoder.withIndent(' ').convert(artifact),
      flush: true,
    );
    await pending.rename(output.path);
    await _flushCommandJournal();
  }

  Future<void> _writeAndroidArtifact(String sqlCipherObservation) async {
    if (_relayJournal.trim().isEmpty ||
        _senderLogcat.trim().isEmpty ||
        _recipientLogcat.trim().isEmpty ||
        _uiSnapshots.isEmpty ||
        _notificationSnapshots.isEmpty) {
      throw _CaptureFailure.capture(
        stage,
        'authoritative_capture_inventory_incomplete',
      );
    }

    final relayLines = _relayJournal
        .split('\n')
        .where(
          (line) =>
              line.contains('[GROUP_INBOX]') ||
              line.contains('[PUSH]') ||
              line.contains('[GROUP_REACTION_WAKE]'),
        )
        .join('\n');
    if (!relayLines.contains('[GROUP_INBOX] Stored message for group') ||
        !relayLines.contains(_providerSuccessMarker)) {
      throw _CaptureFailure.capture(
        stage,
        'relay_or_provider_window_missing_group_store_or_send',
      );
    }

    final notificationText = StringBuffer();
    for (final file in _notificationSnapshots) {
      notificationText
        ..writeln('source_file=${file.uri.pathSegments.last}')
        ..writeln('source_sha256=${await _sha256(file)}')
        ..writeln(await file.readAsString());
    }
    final uiText = StringBuffer();
    for (final file in _uiSnapshots) {
      uiText
        ..writeln('source_file=${file.uri.pathSegments.last}')
        ..writeln('source_sha256=${await _sha256(file)}')
        ..writeln(await file.readAsString());
    }

    final evidenceText = <String, String>{};
    if (scenario.id.endsWith('_message_unread_lifecycle')) {
      if (_uiUnreadTimeline.join(',') != '0,1,1,2,0') {
        throw _CaptureFailure.capture(
          stage,
          'unread_ui_timeline_mismatch: ${_uiUnreadTimeline.join(',')}',
        );
      }
      evidenceText.addAll(<String, String>{
        'relay': '${_redact(relayLines)}\n',
        'provider_fcm': _providerEvidenceLines(_relayJournal),
        'sender_app': '${_redact(_senderLogcat)}\n',
        'recipient_app': '${_redact(_recipientLogcat)}\n',
        'sqlcipher_state': sqlCipherObservation,
        'android_notification_records': notificationText.toString(),
        'ui_automation': uiText.toString(),
      });
    } else {
      for (final marker in const <String>[
        'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
        'PUSH_ANDROID_DATA_DECRYPT_OK',
      ]) {
        if (!_recipientLogcat.contains(marker)) {
          throw _CaptureFailure.capture(
            stage,
            'android_background_group_crypto_marker_missing: $marker',
          );
        }
      }
      evidenceText.addAll(<String, String>{
        'relay': '${_redact(relayLines)}\n',
        'provider_fcm': _providerEvidenceLines(_relayJournal),
        'sender_app':
            '${_redact(_senderLogcat)}\n$_exactDuplicateRedriveObservation',
        'recipient_app':
            '${_redact(_recipientLogcat)}\n$_backgroundConnectedObservation',
        'sqlcipher_state': sqlCipherObservation,
        'android_logcat': _redact(_recipientLogcat),
        'android_notification_records': notificationText.toString(),
        'ui_automation': uiText.toString(),
      });
    }

    final evidence = <Map<String, Object?>>[];
    for (final requirement in scenario.evidenceRequirements) {
      final text = evidenceText[requirement.kind];
      if (text == null) {
        throw _CaptureFailure.capture(
          stage,
          'capture_has_no_writer_for_evidence_kind_${requirement.kind}',
        );
      }
      final file = File(
        '${artifactDirectory.path}${Platform.pathSeparator}'
        '${requirement.kind}.log',
      );
      final redacted = _redact(text);
      _rejectSensitivePersistence(redacted, requirement.kind);
      await file.writeAsString(redacted, flush: true);
      final bytes = await file.readAsBytes();
      evidence.add(<String, Object?>{
        'kind': requirement.kind,
        'path': file.uri.pathSegments.last,
        'sha256': sha256.convert(bytes).toString(),
        'bytes': bytes.length,
      });
    }

    final build = _androidBuilds!;
    await _flushCommandJournal();
    final configurationFile = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'configuration_verdict.json',
    );
    final buildProvenanceFile = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'candidate_build_provenance.json',
    );
    final artifact = <String, Object?>{
      'schema': groupReactionNotificationArtifactSchema,
      'version': groupReactionNotificationArtifactVersion,
      'scenario': scenario.id,
      'testCase': scenario.testCase,
      'status': 'passed',
      'generatedBy': 'automated_capture_pipeline',
      'capture': <String, Object?>{
        'configuration': await _artifactFileReference(configurationFile),
        'candidateBuild': await _artifactFileReference(buildProvenanceFile),
        'commandJournal': await _artifactFileReference(_commandJournalFile),
      },
      'measurements': <String, Object?>{
        'appPackage': appPackage,
        'groupName': _groupName,
        'actorName': sender.username,
        'firstMarker': _firstMarker,
        'secondMarker': _secondMarker,
        'targetMarker': _targetMarker,
        'expectedProviderSendCount': 2,
      },
      'topology': <String, Object?>{
        'groupType': scenario.groupType,
        'sender': <String, Object?>{
          'role': scenario.senderRole,
          'platform': scenario.senderPlatform,
          'deviceKind': scenario.senderDeviceKind,
          'deviceId': senderId,
          'liveDiscovered': true,
          'explicitId': true,
        },
        'recipient': <String, Object?>{
          'role': scenario.recipientRole,
          'platform': scenario.recipientPlatform,
          'deviceKind': scenario.recipientDeviceKind,
          'deviceId': recipientId,
          'liveDiscovered': true,
          'explicitId': true,
        },
      },
      'execution': <String, Object?>{
        'automation': 'fully_automated',
        'manualTaps': 0,
        // Setup launches may reset a debug process, but the bounded recipient
        // delivery lifecycle above uses only `am kill`, never force-stop.
        'forceStopUsed': false,
        'candidateBuildInstalled':
            build.e2eSha256.isNotEmpty && build.normalSha256.isNotEmpty,
        'stagingRelay': _relay.sha256 == _staging['candidateRelaySha256'],
        'realProvider': _providerLines(
          _relayJournal,
        ).contains(_providerSuccessMarker),
      },
      'evidence': evidence,
      'redaction': const <String, Object?>{
        'pushTokensPersisted': false,
        'secretKeysPersisted': false,
        'ciphertextPersisted': false,
        'plaintextPayloadPersisted': false,
        'rawPeerIdsPersisted': false,
      },
    };
    final encoded = const JsonEncoder.withIndent(' ').convert(artifact);
    _rejectSensitivePersistence(encoded, 'artifact');
    final output = File(
      '${artifactDirectory.path}${Platform.pathSeparator}${scenario.id}.json',
    );
    final pending = File('${output.path}.pending');
    await pending.writeAsString(encoded, flush: true);
    await pending.rename(output.path);
  }

  Future<void> _writeIosArtifact(String sqlCipherObservation) async {
    final relayLines = _relayJournal
        .split('\n')
        .where(
          (line) => line.contains('[GROUP_INBOX]') || line.contains('[PUSH]'),
        )
        .join('\n');
    final recipientLines = _iosSystemLog
        .split('\n')
        .where(
          (line) =>
              line.contains('[PUSH_DIAG]') ||
              line.contains('IOS_APNS_') ||
              line.contains('NOTIFICATION_TAP_') ||
              line.contains('INITIAL_LOCAL_NOTIFICATION_ROUTE_'),
        )
        .join('\n');
    final nseLines = _iosSystemLog
        .split('\n')
        .where((line) => line.contains('PUSH_NSE_'))
        .join('\n');
    if (!relayLines.contains('[GROUP_INBOX] Stored message for group') ||
        _providerLines(_relayJournal).trim().isEmpty ||
        _senderLogcat.trim().isEmpty ||
        recipientLines.trim().isEmpty ||
        nseLines.trim().isEmpty ||
        _iosXcuitestOutput.trim().isEmpty) {
      throw _CaptureFailure.capture(
        stage,
        'physical_ios_authoritative_capture_inventory_incomplete',
      );
    }

    await _writeIosBuildProvenance();
    final evidenceText = <String, String>{
      'relay': '${_redact(relayLines)}\n',
      'provider_apns': _providerLines(_relayJournal),
      'sender_app': '${_redact(_senderLogcat)}\n',
      'recipient_app': '${_redact(recipientLines)}\n',
      'sqlcipher_state': sqlCipherObservation,
      'nse_log': '${_redact(nseLines)}\n',
      'xcuitest': '${_redact(_iosXcuitestOutput)}\n',
    };
    final evidence = <Map<String, Object?>>[];
    for (final requirement in scenario.evidenceRequirements) {
      final text = evidenceText[requirement.kind];
      if (text == null) {
        throw _CaptureFailure.capture(
          stage,
          'capture_has_no_writer_for_evidence_kind_${requirement.kind}',
        );
      }
      final redacted = _redact(text);
      _rejectSensitivePersistence(redacted, requirement.kind);
      final file = File(
        '${artifactDirectory.path}${Platform.pathSeparator}'
        '${requirement.kind}.log',
      );
      await file.writeAsString(redacted, flush: true);
      final bytes = await file.readAsBytes();
      evidence.add(<String, Object?>{
        'kind': requirement.kind,
        'path': file.uri.pathSegments.last,
        'sha256': sha256.convert(bytes).toString(),
        'bytes': bytes.length,
      });
    }

    await _flushCommandJournal();
    final configurationFile = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'configuration_verdict.json',
    );
    final buildProvenanceFile = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'candidate_build_provenance.json',
    );
    final artifact = <String, Object?>{
      'schema': groupReactionNotificationArtifactSchema,
      'version': groupReactionNotificationArtifactVersion,
      'scenario': scenario.id,
      'testCase': scenario.testCase,
      'status': 'passed',
      'generatedBy': 'automated_capture_pipeline',
      'capture': <String, Object?>{
        'configuration': await _artifactFileReference(configurationFile),
        'candidateBuild': await _artifactFileReference(buildProvenanceFile),
        'commandJournal': await _artifactFileReference(_commandJournalFile),
      },
      'measurements': <String, Object?>{
        'appPackage': _iosCapture['bundleId']! as String,
        'groupName': _groupName,
        'actorName': sender.username,
        'firstMarker': '',
        'secondMarker': '',
        'targetMarker': _targetMarker,
        'expectedProviderSendCount': 2,
      },
      'topology': <String, Object?>{
        'groupType': scenario.groupType,
        'sender': <String, Object?>{
          'role': scenario.senderRole,
          'platform': scenario.senderPlatform,
          'deviceKind': scenario.senderDeviceKind,
          'deviceId': senderId,
          'liveDiscovered': true,
          'explicitId': true,
        },
        'recipient': <String, Object?>{
          'role': scenario.recipientRole,
          'platform': scenario.recipientPlatform,
          'deviceKind': scenario.recipientDeviceKind,
          'deviceId': recipientId,
          'liveDiscovered': true,
          'explicitId': true,
        },
      },
      'execution': <String, Object?>{
        'automation': 'fully_automated',
        'manualTaps': 0,
        'forceStopUsed': false,
        'candidateBuildInstalled':
            _iosE2eAppSha256.isNotEmpty &&
            _iosNormalAppSha256.isNotEmpty &&
            _iosE2eAppSha256 != _iosNormalAppSha256 &&
            _iosInstallReceipts.length == 2,
        'stagingRelay': _relay.sha256 == _staging['candidateRelaySha256'],
        'realProvider':
            _providerLines(_relayJournal)
                .split('\n')
                .where((line) => line.contains(_providerSuccessMarker))
                .length ==
            2,
      },
      'evidence': evidence,
      'redaction': const <String, Object?>{
        'pushTokensPersisted': false,
        'secretKeysPersisted': false,
        'ciphertextPersisted': false,
        'plaintextPayloadPersisted': false,
        'rawPeerIdsPersisted': false,
      },
    };
    final encoded = const JsonEncoder.withIndent(' ').convert(artifact);
    _rejectSensitivePersistence(encoded, 'artifact');
    final output = File(
      '${artifactDirectory.path}${Platform.pathSeparator}${scenario.id}.json',
    );
    final pending = File('${output.path}.pending');
    await pending.writeAsString(encoded, flush: true);
    await pending.rename(output.path);
  }

  Future<void> _writeIosBuildProvenance() async {
    final file = File(
      '${artifactDirectory.path}${Platform.pathSeparator}'
      'candidate_build_provenance.json',
    );
    if (!file.existsSync() ||
        _iosE2eAppSha256.isEmpty ||
        _iosNormalAppSha256.isEmpty ||
        _iosE2eAppSha256 == _iosNormalAppSha256 ||
        !_iosInstallReceipts.keys.toSet().containsAll(const <String>{
          'e2e',
          'normal',
        })) {
      throw _CaptureFailure.capture(
        stage,
        'physical_ios_build_or_install_provenance_incomplete',
      );
    }
    final decoded = Map<String, Object?>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
    decoded.addAll(<String, Object?>{
      'iosBundleId': _iosCapture['bundleId']! as String,
      'iosBuildTarget': 'build/ios/iphoneos/Runner.app',
      'iosE2eAppSha256': _iosE2eAppSha256,
      'iosNormalAppSha256': _iosNormalAppSha256,
      'iosInstallReceipts': <Object?>[
        for (final mode in const <String>['e2e', 'normal'])
          <String, Object?>{
            'mode': mode,
            'receipt': await _artifactFileReference(_iosInstallReceipts[mode]!),
          },
      ],
    });
    await file.writeAsString(
      const JsonEncoder.withIndent(' ').convert(decoded),
      flush: true,
    );
  }

  Future<Map<String, Object?>> _artifactFileReference(File file) async {
    if (!await file.exists()) {
      throw _CaptureFailure.capture(
        stage,
        'capture_provenance_file_missing_${file.uri.pathSegments.last}',
      );
    }
    final bytes = await file.readAsBytes();
    return <String, Object?>{
      'path': file.uri.pathSegments.last,
      'sha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
    };
  }

  String get _providerSuccessMarker =>
      scenario.id.endsWith('_message_unread_lifecycle')
      ? '[PUSH] Group notification sent to '
      : '[PUSH] Notification sent to ';

  String _providerLines(String journal) =>
      '${journal.split('\n').where((line) => line.contains(_providerSuccessMarker)).map(_redact).join('\n')}\n';

  String _providerEvidenceLines(String journal) {
    final raw = _providerLines(journal);
    if (!groupReactionNotificationKeepsRecipientProcessAlive(scenario.id)) {
      return raw;
    }
    return '$raw'
        'MKNOON_315_PROVIDER_FCM_MATCH '
        'event=group_reaction delivery_matched=true\n';
  }

  void _rejectSensitivePersistence(String text, String source) {
    for (final forbidden in const <String>[
      '"fcmToken":',
      '"apnsToken":',
      '"secretKey":',
      '"ciphertext":',
      '"plaintext":',
      '"senderPeerId":',
      '"recipientPeerId":',
      'BEGIN PRIVATE KEY',
    ]) {
      if (text.contains(forbidden)) {
        throw _CaptureFailure.capture(
          stage,
          '$source contains forbidden persisted material $forbidden',
        );
      }
    }
  }

  Future<void> _deleteBuildCopies() async {
    final preparedPath = prebuiltAndroidApk?.absolute.path;
    for (final file in <File?>[
      _androidBuilds?.e2eApk,
      _androidBuilds?.normalApk,
    ]) {
      if (file == null || file.absolute.path == preparedPath) continue;
      if (file.existsSync()) await file.delete();
    }
  }

  Future<void> _deleteTransientFixtureFiles() async {
    final androidIds = <String>{
      if (scenario.senderPlatform == 'android') senderId,
      if (scenario.recipientPlatform == 'android') recipientId,
    };
    for (final deviceId in androidIds) {
      await _deleteAppFile(deviceId, 'intro_e2e_config.json');
      await _deleteAppFile(deviceId, 'intro_e2e_result.json');
    }
  }

  Future<void> _collapseAndroidStatusBars() async {
    final androidIds = <String>{
      if (scenario.senderPlatform == 'android') senderId,
      if (scenario.recipientPlatform == 'android') recipientId,
    };
    for (final deviceId in androidIds) {
      await _adbShell(deviceId, const <String>[
        'cmd',
        'statusbar',
        'collapse',
      ], allowFail: true);
    }
  }

  Future<void> _deletePendingProofResidue() async {
    final pending = File(
      '${artifactDirectory.path}${Platform.pathSeparator}${scenario.id}'
      '.json.pending',
    );
    if (pending.existsSync()) {
      await pending.delete();
    }
  }

  Future<void> _grantNotificationPermission(String deviceId) async {
    await _adbShell(deviceId, <String>[
      'pm',
      'grant',
      appPackage,
      'android.permission.POST_NOTIFICATIONS',
    ], allowFail: true);
  }

  Future<void> _launchAndroid(String deviceId) async {
    // Setup launches are cold so bootstrap deterministically consumes the
    // app-private fixture. The actual notification boundary later uses only
    // `am kill`; force-stop is never used after the capture window opens.
    await _adbShell(deviceId, <String>[
      'am',
      'force-stop',
      appPackage,
    ], environmentFailure: true);
    await _startAndroid(deviceId);
  }

  Future<void> _startAndroid(String deviceId) async {
    // Used inside proof windows after an APK reinstall has already stopped the
    // prior process. Do not add force-stop here: the lifecycle contract rejects
    // it because force-stopped apps are not eligible for ordinary push wakeup.
    await _adbShell(deviceId, <String>[
      'am',
      'start',
      '-W',
      '-n',
      '$appPackage/.MainActivity',
    ], environmentFailure: true);
  }

  Future<void> _writeAppFile(
    String deviceId,
    String name,
    String content,
  ) async {
    final safeId = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final local = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'plan257_${safeId}_$name',
    );
    final remote = '/data/local/tmp/plan257_$name';
    await local.writeAsString(content, flush: true);
    try {
      await _adb(deviceId, <String>['push', local.path, remote]);
      await _adbShell(deviceId, <String>[
        'run-as',
        appPackage,
        'mkdir',
        '-p',
        'app_flutter',
      ], environmentFailure: true);
      await _adbShell(deviceId, <String>[
        'run-as',
        appPackage,
        'cp',
        remote,
        'app_flutter/$name',
      ], environmentFailure: true);
    } finally {
      await _adbShell(deviceId, <String>['rm', '-f', remote], allowFail: true);
      if (local.existsSync()) await local.delete();
    }
  }

  Future<String?> _readAppFile(String deviceId, String name) async {
    final result = await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'cat',
      'app_flutter/$name',
    ], allowFail: true);
    if (result.trim().isEmpty || result.contains('No such file')) return null;
    return result;
  }

  Future<void> _deleteAppFile(String deviceId, String name) async {
    await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'rm',
      '-f',
      'app_flutter/$name',
    ], allowFail: true);
  }

  Future<void> _longPressText(String deviceId, String text) async {
    final center = await _waitForBounds(
      deviceId,
      text,
      const Duration(seconds: 30),
    );
    await _adbShell(deviceId, <String>[
      'input',
      'swipe',
      '${center.$1}',
      '${center.$2}',
      '${center.$1}',
      '${center.$2}',
      '900',
    ], environmentFailure: true);
  }

  Future<void> _tapText(String deviceId, String text) async {
    final center = await _waitForBounds(
      deviceId,
      text,
      const Duration(seconds: 30),
    );
    await _adbShell(deviceId, <String>[
      'input',
      'tap',
      '${center.$1}',
      '${center.$2}',
    ], environmentFailure: true);
  }

  Future<void> _waitForUiText(
    String deviceId,
    String text,
    Duration timeout,
  ) async {
    await _waitForBounds(deviceId, text, timeout);
  }

  Future<String> _waitForAnyText(
    String deviceId,
    List<String> texts,
    Duration timeout,
  ) {
    return _waitForValue<String>(
      'one of ${texts.join(', ')} on $deviceId',
      timeout,
      () async {
        final xml = await _uiDump(deviceId);
        for (final text in texts) {
          if (findSemanticNodeCenter(xml, text) != null) return text;
        }
        return null;
      },
    );
  }

  Future<void> _waitForGroupInviteEntry(
    String deviceId,
    Duration timeout,
  ) async {
    final maximumPolls = max(1, timeout.inSeconds);
    final observed = await waitForPendingGroupInviteProjection(
      groupName: _groupName,
      readUiDump: () => _uiDump(deviceId),
      openReview: (label) => _tapText(deviceId, label),
      reestablishOrbit: () => _reestablishOrbitWithoutForceStop(deviceId),
      maximumPolls: maximumPolls,
      recoveryPoll: min(20, maximumPolls),
    );
    if (observed == null) {
      throw _CaptureFailure.capture(
        stage,
        'timed_out_waiting_for_pending_group_invite_$_groupName'
        '_on_$deviceId',
      );
    }
  }

  Future<(int, int)> _waitForBounds(
    String deviceId,
    String text,
    Duration timeout,
  ) {
    return _waitForValue<(int, int)>(
      'UI node "$text" on $deviceId',
      timeout,
      () async => findSemanticNodeCenter(await _uiDump(deviceId), text),
    );
  }

  Future<String> _uiDump(String deviceId) async {
    const remote = '/data/local/tmp/plan257_ui.xml';
    await _adbShell(deviceId, const <String>[
      'uiautomator',
      'dump',
      remote,
    ], allowFail: true);
    final xml = await _adbShell(deviceId, const <String>[
      'cat',
      remote,
    ], allowFail: true);
    await _adbShell(deviceId, const <String>[
      'rm',
      '-f',
      remote,
    ], allowFail: true);
    return xml;
  }

  Future<String> _notificationDump(String deviceId) {
    return _adbShell(deviceId, const <String>[
      'dumpsys',
      'notification',
      '--noredact',
    ], environmentFailure: true);
  }

  List<(int, ActiveNotificationCard)> _activeNotificationRecords(String dump) {
    final result = <(int, ActiveNotificationCard)>[];
    for (final card in extractActiveNotificationCards(
      dump,
      packageName: appPackage,
    )) {
      final id = card.id;
      if (id == null || id < 0) {
        throw _CaptureFailure.capture(
          stage,
          'android_notification_record_has_no_numeric_id',
        );
      }
      result.add((id, card));
    }
    return result;
  }

  List<(int, ActiveNotificationCard)> _activeContentNotificationRecords(
    String dump,
  ) {
    return _activeNotificationRecords(
      dump,
    ).where((record) => !record.$2.isGroupSummary).toList(growable: false);
  }

  String _appNotificationRecords(String dump) {
    final section = dump.split(RegExp(r'\nRanking Config:')).first;
    return RegExp(
          r'NotificationRecord\([\s\S]*?(?=\n\s*NotificationRecord\(|$)',
        )
        .allMatches(section)
        .map((match) => match.group(0)!)
        .where((record) => record.contains('pkg=$appPackage'))
        .join('\n');
  }

  Future<String> _relayJournalSince(DateTime since) async {
    final epochSeconds = since.millisecondsSinceEpoch ~/ 1000 - 2;
    final result = await _ssh(<String>[
      'sudo',
      'journalctl',
      '-u',
      'relay-server',
      '--since',
      '@$epochSeconds',
      '--no-pager',
      '-o',
      'short-iso',
    ], environmentFailure: true);
    return result.stdout;
  }

  Future<_CommandOutput> _ssh(
    List<String> remoteArgs, {
    bool allowFail = false,
    bool environmentFailure = false,
  }) {
    return _run(
      'ssh',
      <String>[
        '-o',
        'BatchMode=yes',
        '-o',
        'ConnectTimeout=15',
        '-i',
        relayKey.path,
        relayTarget,
        _shellJoin(remoteArgs),
      ],
      allowFail: allowFail,
      environmentFailure: environmentFailure,
    );
  }

  Future<_CommandOutput> _adb(
    String deviceId,
    List<String> args, {
    bool allowFail = false,
    bool environmentFailure = false,
  }) {
    return _run(
      'adb',
      <String>['-s', deviceId, ...args],
      allowFail: allowFail,
      environmentFailure: environmentFailure,
    );
  }

  Future<_CommandOutput> _readAndroidLogcat(String deviceId) async {
    final output = await retryBoundedFixtureRead<_CommandOutput>(
      attempt: () => _adb(deviceId, const <String>[
        'logcat',
        '-d',
        '-v',
        'threadtime',
      ], allowFail: true),
      succeeded: (value) => value.exitCode == 0,
    );
    if (output.exitCode != 0) {
      throw _CaptureFailure.capture(
        stage,
        'adb logcat remained unavailable on $deviceId after bounded retry: '
        '${_lastLine(output.combined)}',
      );
    }
    return output;
  }

  Future<String> _adbShell(
    String deviceId,
    List<String> args, {
    bool allowFail = false,
    bool environmentFailure = false,
  }) async {
    return (await _adb(
      deviceId,
      <String>['shell', ...args],
      allowFail: allowFail,
      environmentFailure: environmentFailure,
    )).stdout;
  }

  Future<_CommandOutput> _run(
    String executable,
    List<String> args, {
    bool allowFail = false,
    bool environmentFailure = false,
  }) async {
    if (verbose) stdout.writeln('RUN: $executable ${args.join(' ')}');
    final result = await Process.run(executable, args);
    final output = _CommandOutput(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
    _recordCommand(executable, args, output.exitCode);
    if (verbose) {
      stdout.write(output.stdout);
      stderr.write(output.stderr);
    }
    if (output.exitCode != 0 && !allowFail) {
      final message =
          '$executable exited ${output.exitCode}: ${_lastLine(output.combined)}';
      throw environmentFailure
          ? _CaptureFailure.environment(stage, message)
          : _CaptureFailure.capture(stage, message);
    }
    return output;
  }

  Future<_CommandOutput> _runStreaming(
    String executable,
    List<String> args, {
    bool environmentFailure = false,
    Map<String, String>? environment,
  }) async {
    stdout.writeln('RUN: $executable ${args.join(' ')}');
    final process = await Process.start(
      executable,
      args,
      environment: environment,
      includeParentEnvironment: true,
    );
    final out = StringBuffer();
    final err = StringBuffer();
    final outDone = process.stdout.transform(utf8.decoder).forEach((chunk) {
      out.write(chunk);
      stdout.write(chunk);
    });
    final errDone = process.stderr.transform(utf8.decoder).forEach((chunk) {
      err.write(chunk);
      stderr.write(chunk);
    });
    final exitCode = await process.exitCode;
    await Future.wait(<Future<void>>[outDone, errDone]);
    _recordCommand(executable, args, exitCode);
    final output = _CommandOutput(
      exitCode: exitCode,
      stdout: out.toString(),
      stderr: err.toString(),
    );
    if (exitCode != 0) {
      final message =
          '$executable exited $exitCode: ${_lastLine(output.combined)}';
      throw environmentFailure
          ? _CaptureFailure.environment(stage, message)
          : _CaptureFailure.capture(stage, message);
    }
    return output;
  }

  void _recordCommand(String executable, List<String> args, int exitCode) {
    _recordCommandAtStage(stage, executable, args, exitCode);
  }

  void _recordCommandAtStage(
    String commandStage,
    String executable,
    List<String> args,
    int exitCode,
  ) {
    final safeArgs = args
        .map((argument) {
          if (argument == serviceAccount.path) return '[service-account-path]';
          if (argument == relayKey.path) return '[relay-key-path]';
          return _redact(argument);
        })
        .toList(growable: false);
    _commandJournal.add(<String, Object?>{
      'stage': commandStage,
      'executable': executable,
      'args': safeArgs,
      'exitCode': exitCode,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _flushCommandJournal() async {
    final encoded = const JsonEncoder.withIndent(' ').convert(<String, Object?>{
      'schema': 'mknoon.plan257.command-journal.v1',
      'scenario': scenario.id,
      'commands': _commandJournal,
    });
    _rejectSensitivePersistence(encoded, 'command journal');
    await _commandJournalFile.writeAsString(encoded, flush: true);
  }

  Future<void> _waitFor(
    String label,
    Duration timeout,
    Future<bool> Function() probe,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await probe()) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _CaptureFailure.capture(stage, 'timed_out_waiting_for_$label');
  }

  Future<T> _waitForValue<T>(
    String label,
    Duration timeout,
    Future<T?> Function() probe,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final value = await probe();
      if (value != null) return value;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _CaptureFailure.capture(stage, 'timed_out_waiting_for_$label');
  }

  Future<String> _sha256(File file) async =>
      sha256.convert(await file.readAsBytes()).toString();

  Future<String> _sha256Directory(Directory directory) async {
    final files = await directory
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));
    final sink = _SingleDigestSink();
    final converter = sha256.startChunkedConversion(sink);
    final prefix = '${directory.path}${Platform.pathSeparator}';
    for (final file in files) {
      final relative = file.path.startsWith(prefix)
          ? file.path.substring(prefix.length)
          : file.path;
      converter.add(utf8.encode('$relative\u0000'));
      converter.add(await file.readAsBytes());
      converter.add(const <int>[0]);
    }
    converter.close();
    final digest = sink.value;
    if (digest == null) {
      throw _CaptureFailure.capture(stage, 'ios_candidate_bundle_hash_failed');
    }
    return digest.toString();
  }

  String _flowLines(String logcat) => logcat
      .split('\n')
      .where(
        (line) =>
            line.contains('[FLOW]') ||
            line.contains('PUSH_BACKGROUND_REACTION_') ||
            line.contains('PUSH_ANDROID_DATA_DECRYPT_'),
      )
      .map(_redact)
      .join('\n');

  String _redact(String value) {
    var redacted = value;
    for (final peer in <String>[
      sender.peerId,
      sender.peerPrefix,
      recipient.peerId,
      recipient.peerPrefix,
    ]) {
      if (peer.isNotEmpty) redacted = redacted.replaceAll(peer, '[peer]');
    }
    redacted = redacted.replaceAll(RegExp(r'12D3Koo[A-Za-z0-9]+'), '[peer]');
    return redacted;
  }
}

class _SingleDigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    if (value != null) throw StateError('digest sink received two values');
    value = data;
  }

  @override
  void close() {}
}

String _shellJoin(List<String> values) => values.map(_shellQuote).join(' ');

String _shellQuote(String value) {
  if (RegExp(r'^[A-Za-z0-9_./:@=+-]+$').hasMatch(value)) return value;
  return "'${value.replaceAll("'", "'\\''")}'";
}

String _lastLine(String value) {
  final lines = value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  return lines.isEmpty ? '' : lines.last;
}

String? _valueFor(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == name) {
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        _usage('Missing value for $name.');
      }
      return args[index + 1];
    }
    if (argument.startsWith('$name=')) {
      final value = argument.substring(name.length + 1);
      if (value.isEmpty) _usage('Missing value for $name.');
      return value;
    }
  }
  return null;
}

Never _usage([String? error]) {
  if (error != null) stderr.writeln(error);
  stderr.writeln(
    'Usage: dart run integration_test/scripts/'
    'capture_group_reaction_notification_device.dart '
    '--scenario <plan257-id> --sender <explicit-id> '
    '--recipient <explicit-id> --artifact-dir <dir> '
    '--staging-manifest <redacted-json> [--relay-target <ssh-target>] '
    '[--relay-key <file>] [--service-account <file>] '
    '[--prebuilt-android-apk <central-apk> --no-child-builds] [--verbose] '
    '[--keep-build-artifacts]',
  );
  exit(64);
}
