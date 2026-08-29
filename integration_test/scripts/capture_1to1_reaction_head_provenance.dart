#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '_android_app_package.dart';
import 'android_notification_recovery_completion_criteria.dart'
    show parseAndroidCanonicalRecoveryJobIds;
import 'reaction_notification_proof_support.dart';

const _defaultRelayTarget = 'ubuntu@mknoun.xyz';
const _defaultRelayKey = 'se.pem';
const _reactionEmoji = '👍';
const _androidBuildProfile = 'debug-android-arm64-split-v1';
const _firstWakeProfileAotBuildProfile =
    'profile-android-arm64-split-plan393-g21-v1';
const _fixedWakeRecoveryBuildProfile = 'android.production_fcm.fixed_wake';
const _fixedWakeRecoveryScenario =
    'android_fixed_wake_direct_reaction_recovery';
const _relaySelectedRouteCounter = 'relay_push_route_selected_total';
const _g21FrozenProductionReserveMs = 2000;
const _providerObservationDelay = Duration(seconds: 10);

const List<Map<String, String>> _plan393RecoveryAssertionDisposition =
    <Map<String, String>>[
      <String, String>{
        'assertion': 'notifications.headless_direct_group_recovery',
        'disposition': 'retained_host_native',
        'owner': 'plan374_tc374_02_tc374_08',
      },
      <String, String>{
        'assertion': 'notifications.foreground_handoff_new_generation',
        'disposition': 'retained_host_concurrency',
        'owner': 'plan374_tc374_06_and_plan393_distinct_generations',
      },
      <String, String>{
        'assertion': 'notifications.direct_custody_recovery',
        'disposition': 'specialized',
        'owner': 'plan393_authenticated_direct_reaction',
      },
      <String, String>{
        'assertion': 'notifications.synthetic_outer_id_recovery',
        'disposition': 'retired_obsolete_unsafe',
        'owner': 'plan375_tc375_04_identity_free_wake',
      },
      <String, String>{
        'assertion': 'notifications.history_count_projection',
        'disposition': 'retained_outside_recovery_matrix',
        'owner': 'conversation_snapshot_and_projection_tests',
      },
      <String, String>{
        'assertion': 'notifications.registration_health_live_recovery',
        'disposition': 'split_existing_owners',
        'owner': 'plan375_tc375_07_and_registration_health_tests',
      },
      <String, String>{
        'assertion': 'notifications.recovery_copy_locales',
        'disposition': 'retained_native_host',
        'owner': 'android_recovery_string_resources_tests',
      },
      <String, String>{
        'assertion': 'notifications.zero_taps_zero_child_builds',
        'disposition': 'retained_narrowed_capability',
        'owner': 'plan393_tc393_12_tc393_13',
      },
    ];

Future<void> main(List<String> args) async {
  final sender = _valueFor(args, '--sender');
  final recipient = _valueFor(args, '--recipient');
  final artifactPath = _valueFor(args, '--artifact-dir');
  final directTextOnly = args.contains('--direct-text-only');
  final firstWakeProfileAot = args.contains('--first-wake-profile-aot');
  final fixedWakeRecovery = args.contains('--fixed-wake-recovery');
  final measurementOnly = args.contains('--measurement-only');
  final requireAlert = args.contains('--require-alert');
  final prebuiltAndroidApkPath = _valueFor(args, '--prebuilt-android-apk');
  final noChildBuilds = args.contains('--no-child-builds');
  final statePreparedByParent = args.contains('--android-state-prepared');
  final gateAArtifactPath = _valueFor(args, '--gate-a-artifact');
  final gateAArtifactSha256 = _valueFor(args, '--gate-a-artifact-sha256');
  if (sender == null || recipient == null || artifactPath == null) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/'
      'capture_1to1_reaction_head_provenance.dart '
      '--sender <android-id> --recipient <android-id> '
      '--artifact-dir <dir> [--relay-target <ssh-target>] '
      '[--relay-key <key>] [--head-source-root <path>] '
      '[--live-typed-smoke] [--durable-background-connected] '
      '[--prebuilt-android-apk <central-apk> --no-child-builds '
      '--android-state-prepared] '
      '[--direct-text-only '
      '--gate-a-artifact <gate-a-pass.json> '
      '--gate-a-artifact-sha256 <sha256>] '
      '[--first-wake-profile-aot '
      '(--measurement-only | --require-alert) '
      '--service-account <fcm-service-account.json> '
      '--staging-manifest <staging-manifest.json>] '
      '[--fixed-wake-recovery --service-account <json> '
      '--staging-manifest <json> --prebuilt-android-apk <central-apk> '
      '--no-child-builds --android-state-prepared] '
      '[--reuse-working-tree-apks] [--verbose]',
    );
    exit(64);
  }
  if (<bool>[
        firstWakeProfileAot,
        directTextOnly,
        fixedWakeRecovery,
      ].where((value) => value).length >
      1) {
    stderr.writeln(
      '--first-wake-profile-aot, --direct-text-only, and '
      '--fixed-wake-recovery are mutually exclusive.',
    );
    exit(64);
  }
  if (firstWakeProfileAot && measurementOnly == requireAlert) {
    stderr.writeln(
      '--first-wake-profile-aot requires exactly one of --measurement-only '
      'or --require-alert.',
    );
    exit(64);
  }
  if (!firstWakeProfileAot && (measurementOnly || requireAlert)) {
    stderr.writeln(
      '--measurement-only/--require-alert require --first-wake-profile-aot.',
    );
    exit(64);
  }
  final serviceAccountPath = _valueFor(args, '--service-account');
  final stagingManifestPath = _valueFor(args, '--staging-manifest');
  final relayFixtureProbeRaw = _valueFor(args, '--relay-fixture-probe');
  final relayFixtureProbe = _parseRelayFixtureProbe(relayFixtureProbeRaw);
  if (relayFixtureProbeRaw != null && relayFixtureProbe == null) {
    stderr.writeln(
      '--relay-fixture-probe is not an exact local capability URL.',
    );
    exit(64);
  }
  if (relayFixtureProbe != null && !fixedWakeRecovery) {
    stderr.writeln(
      '--relay-fixture-probe is reserved for fixed-wake recovery.',
    );
    exit(64);
  }
  if ((firstWakeProfileAot || fixedWakeRecovery) &&
      (serviceAccountPath == null || stagingManifestPath == null)) {
    stderr.writeln(
      'The profile-AOT/fixed-wake mode requires --service-account and '
      '--staging-manifest.',
    );
    exit(64);
  }
  if (directTextOnly &&
      (gateAArtifactPath == null ||
          gateAArtifactSha256 == null ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(gateAArtifactSha256))) {
    stderr.writeln(
      '--direct-text-only requires --gate-a-artifact <json> and its exact '
      '--gate-a-artifact-sha256 <sha256>.',
    );
    exit(64);
  }
  final preparedFlags = <bool>[
    prebuiltAndroidApkPath != null,
    noChildBuilds,
    statePreparedByParent,
  ];
  if (preparedFlags.any((value) => value) &&
      (!preparedFlags.every((value) => value) ||
          (!args.contains('--live-typed-smoke') && !fixedWakeRecovery))) {
    stderr.writeln(
      '--prebuilt-android-apk, --no-child-builds, and '
      '--android-state-prepared are an atomic central-capture contract.',
    );
    exit(64);
  }
  if (fixedWakeRecovery && !preparedFlags.every((value) => value)) {
    stderr.writeln(
      '--fixed-wake-recovery requires the atomic central prepared-APK flags.',
    );
    exit(64);
  }

  File? gateAArtifact;
  List<int>? gateAArtifactBytes;
  Map<String, Object?>? gateAAuthorization;
  if (directTextOnly) {
    gateAArtifact = File(gateAArtifactPath!).absolute;
    try {
      final stat = gateAArtifact.statSync();
      if (stat.type != FileSystemEntityType.file ||
          stat.size <= 0 ||
          stat.size > 64 * 1024) {
        throw const FormatException('Gate A artifact size rejected');
      }
      gateAArtifactBytes = List<int>.unmodifiable(
        gateAArtifact.readAsBytesSync(),
      );
      gateAAuthorization = parseDirectTextGateAAuthorization(
        gateAArtifactBytes,
        now: DateTime.now().toUtc(),
        expectedArtifactSha256: gateAArtifactSha256!,
      );
      if (gateAAuthorization['authorizationKind'] !=
          backgroundCryptoCurrentTokenAuthorizationKind) {
        throw const FormatException(
          'Gate A v2 current-token authorization is required',
        );
      }
    } on Object {
      stderr.writeln('Gate A PASS artifact contract rejected.');
      exit(64);
    }
  }

  final artifactDir = Directory(artifactPath)..createSync(recursive: true);
  final campaign = _HeadProvenanceCampaign(
    senderId: sender,
    recipientId: recipient,
    artifactDir: artifactDir,
    sourceRoot: Directory(
      _valueFor(args, '--head-source-root') ?? Directory.current.path,
    ).absolute,
    relayTarget: _valueFor(args, '--relay-target') ?? _defaultRelayTarget,
    relayKey: File(_valueFor(args, '--relay-key') ?? _defaultRelayKey).absolute,
    relayFixtureProbe: relayFixtureProbe,
    verbose: args.contains('--verbose'),
    keepBuildArtifacts: args.contains('--keep-build-artifacts'),
    liveTypedSmoke: args.contains('--live-typed-smoke'),
    durableBackgroundConnected: args.contains('--durable-background-connected'),
    reuseWorkingTreeApks: args.contains('--reuse-working-tree-apks'),
    directTextOnly: directTextOnly,
    firstWakeProfileAot: firstWakeProfileAot,
    fixedWakeRecovery: fixedWakeRecovery,
    measurementOnly: measurementOnly,
    serviceAccount: serviceAccountPath == null
        ? null
        : File(serviceAccountPath).absolute,
    stagingManifest: stagingManifestPath == null
        ? null
        : File(stagingManifestPath).absolute,
    gateAArtifact: gateAArtifact,
    gateAArtifactBytes: gateAArtifactBytes,
    gateAAuthorization: gateAAuthorization,
    prebuiltAndroidApk: prebuiltAndroidApkPath == null
        ? null
        : File(prebuiltAndroidApkPath).absolute,
    noChildBuilds: noChildBuilds,
    statePreparedByParent: statePreparedByParent,
  );

  try {
    await campaign.run();
  } on _CampaignFailure catch (failure, stackTrace) {
    campaign.writeFailure(failure, stackTrace);
    stderr.writeln(
      'TC-00 CAPTURE FAILED [${failure.stage}]: ${failure.message}',
    );
    exit(failure.environmentBlocked ? 78 : 1);
  }
}

class _CampaignFailure implements Exception {
  _CampaignFailure(
    this.stage,
    this.message, {
    this.environmentBlocked = false,
    this.cleanupFailure,
  });

  final String stage;
  final String message;
  final bool environmentBlocked;
  final _CampaignFailure? cleanupFailure;
}

class _Party {
  _Party({required this.role, required this.deviceId});

  final String role;
  final String deviceId;
  String peerId = '';
  String username = '';
  String qrPayload = '';
  String? mlKemPublicKey;

  String get peerPrefix =>
      peerId.length <= 20 ? peerId : peerId.substring(0, 20);
}

class _BuildArtifacts {
  const _BuildArtifacts({
    required this.revision,
    required this.e2eApk,
    required this.normalApk,
    required this.e2eApkSha256,
    required this.normalApkSha256,
    required this.buildMode,
    required this.buildProfile,
    required this.childBuildCount,
  });

  final String revision;
  final File e2eApk;
  final File normalApk;
  final String e2eApkSha256;
  final String normalApkSha256;
  final String buildMode;
  final String buildProfile;
  final int childBuildCount;
}

class _RelayInfo {
  const _RelayInfo({
    required this.version,
    required this.sha256,
    this.executionBoundary = 'external_staging',
    this.backend = 'redis',
    this.pushTokenState = 'unspecified',
    this.wakeOutcomeLedger = 'redis',
    this.provider = 'fcm',
  });

  final String version;
  final String sha256;
  final String executionBoundary;
  final String backend;
  final String pushTokenState;
  final String wakeOutcomeLedger;
  final String provider;
}

class _InitialAndroidPackageState {
  _InitialAndroidPackageState({required this.installed});

  final bool installed;
  final List<File> apkBackups = <File>[];
  final List<String> apkSha256 = <String>[];
  int? androidSdk;
  String? versionCode;
  String? versionName;
  bool? notificationPermissionGranted;
  String? baselineNotificationSha256;
  String? privateBackupDirectory;
  String? privateBackupSha256;
  int? privateBackupSizeBytes;
  String? privateBackupOwner;
  List<String> privateTopLevelEntries = <String>[];
  Map<String, String> privateTopLevelMetadata = <String, String>{};
  bool privateDataRestored = false;
  bool packageStateRestored = false;
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
}

class _DirectTextRelaySendEvidence {
  const _DirectTextRelaySendEvidence({
    required this.marker,
    required this.messageId,
    required this.windowStart,
    required this.relayEvidencePath,
  });

  final String marker;
  final String messageId;
  final DateTime windowStart;
  final String relayEvidencePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'markerSha256': sha256.convert(utf8.encode(marker)).toString(),
    'messageIdSha256': sha256.convert(utf8.encode(messageId)).toString(),
    'windowStart': windowStart.toIso8601String(),
    'relayStoreMatched': true,
    'providerSendMatched': true,
    'providerFailureRejected': true,
    'relayEvidencePath': relayEvidencePath,
  };
}

class _RelayRouteSnapshot {
  const _RelayRouteSnapshot({
    required this.opaque,
    required this.rich,
    required this.evidence,
  });

  final int opaque;
  final int rich;
  final File evidence;
}

class _FixedWakeWindow {
  const _FixedWakeWindow({
    required this.reactionId,
    required this.generation,
    required this.firstWorkerPid,
    required this.routeAfter,
    required this.ingress,
    required this.notificationSnapshots,
    required this.runtimeLog,
    required this.relayJournal,
  });

  final String reactionId;
  final int generation;
  final int? firstWorkerPid;
  final _RelayRouteSnapshot routeAfter;
  final Map<String, Object?> ingress;
  final File notificationSnapshots;
  final File runtimeLog;
  final File relayJournal;
}

class _FixedWakeCompletion {
  const _FixedWakeCompletion({
    required this.canonicalCard,
    required this.acknowledgement,
    required this.directShow,
    required this.settlement,
    required this.workerCompletion,
    required this.workerEngineCompletion,
    required this.runtimeLog,
    required this.notificationSnapshots,
    required this.jobSchedulerAudit,
  });

  final ActiveNotificationCard canonicalCard;
  final Map<String, Object?> acknowledgement;
  final Map<String, Object?> directShow;
  final Map<String, Object?> settlement;
  final Map<String, Object?>? workerCompletion;
  final Map<String, Object?>? workerEngineCompletion;
  final File runtimeLog;
  final File notificationSnapshots;
  final File? jobSchedulerAudit;
}

class _HeadProvenanceCampaign {
  _HeadProvenanceCampaign({
    required this.senderId,
    required this.recipientId,
    required this.artifactDir,
    required this.sourceRoot,
    required this.relayTarget,
    required this.relayKey,
    required this.relayFixtureProbe,
    required this.verbose,
    required this.keepBuildArtifacts,
    required this.liveTypedSmoke,
    required this.durableBackgroundConnected,
    required this.reuseWorkingTreeApks,
    required this.directTextOnly,
    required this.firstWakeProfileAot,
    required this.fixedWakeRecovery,
    required this.measurementOnly,
    required this.serviceAccount,
    required this.stagingManifest,
    required this.gateAArtifact,
    required this.gateAArtifactBytes,
    required this.gateAAuthorization,
    required this.prebuiltAndroidApk,
    required this.noChildBuilds,
    required this.statePreparedByParent,
  }) : sender = _Party(role: 'A', deviceId: senderId),
       recipient = _Party(role: 'B', deviceId: recipientId),
       appPackage = resolveAndroidAppPackage();

  final String senderId;
  final String recipientId;
  final Directory artifactDir;
  final Directory sourceRoot;
  final String relayTarget;
  final File relayKey;
  final Uri? relayFixtureProbe;
  final bool verbose;
  final bool keepBuildArtifacts;
  final bool liveTypedSmoke;
  final bool durableBackgroundConnected;
  final bool reuseWorkingTreeApks;
  final bool directTextOnly;
  final bool firstWakeProfileAot;
  final bool fixedWakeRecovery;
  final bool measurementOnly;
  final File? serviceAccount;
  final File? stagingManifest;
  final File? gateAArtifact;
  final List<int>? gateAArtifactBytes;
  Map<String, Object?>? gateAAuthorization;
  final File? prebuiltAndroidApk;
  final bool noChildBuilds;
  final bool statePreparedByParent;
  final _Party sender;
  final _Party recipient;
  final String appPackage;

  Directory? _cleanWorktree;
  Directory? _stateBackupDirectory;
  final Map<String, _InitialAndroidPackageState> _initialPackageStates =
      <String, _InitialAndroidPackageState>{};
  final List<_DirectTextRelaySendEvidence> _directTextRelaySends =
      <_DirectTextRelaySendEvidence>[];
  String? _directTextTokenCommandId;
  String? _directTextTokenCommandSha256;
  String? _relayTokenRegistrationEvidencePath;
  Map<String, Object?>? _directTextTokenReceipt;
  AndroidColdLocalNotificationOpenEvidence?
  _directTextColdLocalNotificationOpenEvidence;
  _BuildArtifacts? _build;
  bool _initialStateCaptureComplete = false;
  bool _deviceMutationStarted = false;
  bool _exactRestorationComplete = false;
  String _stage = 'preflight';

  String get _artifactStem => directTextOnly
      ? 'android_direct_text_public_relay'
      : firstWakeProfileAot
      ? 'android_first_wake_profile_aot'
      : fixedWakeRecovery
      ? _fixedWakeRecoveryScenario
      : liveTypedSmoke
      ? 'android_typed_reaction_smoke'
      : durableBackgroundConnected
      ? 'android_durable_reaction_background_connected'
      : 'head_provenance';

  String get _scenario => directTextOnly
      ? 'android_direct_text_public_relay'
      : firstWakeProfileAot
      ? 'android_first_wake_profile_aot'
      : fixedWakeRecovery
      ? _fixedWakeRecoveryScenario
      : liveTypedSmoke
      ? 'android_typed_reaction_smoke'
      : durableBackgroundConnected
      ? 'android_durable_reaction_background_connected'
      : 'head_provenance';

  String get _testCase => directTextOnly
      ? 'TC-DIRECT-TEXT-PUBLIC-RELAY'
      : firstWakeProfileAot
      ? 'TC-393-06'
      : fixedWakeRecovery
      ? 'TC-393-13'
      : liveTypedSmoke
      ? 'TC-13-core-smoke'
      : durableBackgroundConnected
      ? 'TC-DURABLE-DIRECT-REACTION'
      : 'TC-00';

  /// Every variant except TC-00 grades the WORKING TREE. TC-00 alone builds
  /// clean HEAD, which is what its `cleanCurrentBuild` claim means.
  bool get _workingTreeBuild =>
      liveTypedSmoke ||
      directTextOnly ||
      durableBackgroundConnected ||
      firstWakeProfileAot ||
      fixedWakeRecovery;

  /// The variants whose card must carry the typed reaction copy rather than the
  /// generic "New Message" fallback.
  bool get _typedCopyRequired =>
      liveTypedSmoke || durableBackgroundConnected || fixedWakeRecovery;

  Future<void> run() async {
    _CampaignFailure? primaryFailure;
    StackTrace? primaryStackTrace;
    _CampaignFailure? cleanupFailure;
    try {
      _stage = 'preflight';
      await _verifyEnvironment();
      final relayInfo = await _readRelayInfo();
      if (directTextOnly || firstWakeProfileAot) {
        await _captureInitialDeviceState();
      }

      _stage = _workingTreeBuild ? 'working_tree_build' : 'clean_head_build';
      if (noChildBuilds) {
        _build = await _useCentralPrebuiltAndroidApk();
      } else {
        _build = _workingTreeBuild
            ? reuseWorkingTreeApks
                  ? await _reuseWorkingTreeApks()
                  : await _buildWorkingTreeApks()
            : await _buildCleanHeadApks();
      }

      _stage = 'e2e_setup';
      if (directTextOnly || firstWakeProfileAot) {
        if (!_initialStateCaptureComplete) {
          throw _CampaignFailure(
            _stage,
            'Exact initial state capture did not complete.',
          );
        }
        _deviceMutationStarted = true;
      }
      await _installApk(senderId, _build!.e2eApk);
      await _installApk(recipientId, _build!.e2eApk);
      // Fresh Android 13+ installs can surface the runtime notification prompt
      // over Orbit as soon as the debug harness requests notifications. Grant
      // both fixture apps before their first launch; the enclosing state guard
      // still restores the exact package/permission baseline.
      await _grantNotificationPermission(senderId);
      await _grantNotificationPermission(recipientId);
      await _prepareE2EParty(sender, 'TC256-A');
      await _prepareE2EParty(recipient, 'TC256-B');
      await _launch(senderId);
      await _launch(recipientId);
      await _collectIdentity(sender);
      await _collectIdentity(recipient);
      await _prepopulateContacts();
      String? messageMarker;
      String? messageId;
      String? secondMessageMarker;
      String? secondMessageId;
      if (!directTextOnly && !firstWakeProfileAot) {
        messageMarker =
            '${fixedWakeRecovery ? 'TC393RA' : 'TC256'}-'
            '${DateTime.now().toUtc().microsecondsSinceEpoch}';
        messageId = await _seedIncomingMessage(messageMarker);
        if (fixedWakeRecovery) {
          secondMessageMarker =
              'TC393RB-${DateTime.now().toUtc().microsecondsSinceEpoch}';
          secondMessageId = await _seedIncomingMessage(secondMessageMarker);
          if (messageId == secondMessageId ||
              messageMarker == secondMessageMarker) {
            throw _CampaignFailure(
              _stage,
              'The fixed-wake transitions did not receive distinct targets.',
            );
          }
        }
      }

      _stage = 'recipient_push_registration';
      final tokenWindowStart = DateTime.now().toUtc();
      await _installApk(recipientId, _build!.normalApk);
      await _grantNotificationPermission(recipientId);
      if (directTextOnly) {
        await _stageDirectTextTokenProofCommand();
      }
      await _launch(recipientId);
      if (directTextOnly) {
        await _waitForDirectTextTokenProofReceipt();
        // The direct-text artifact claims a PUBLIC RELAY observation, so its
        // wait stays on the relay journal even though the line it greps is
        // gone. Known dead, owned by that lane, deliberately unchanged here.
        await _waitForRelayTokenRegistration(tokenWindowStart);
      } else {
        await _waitForRecipientPushRegistrationAccepted();
      }
      await _requireCleanNotificationSlate();
      // The durable arm resolves an EXACT direct_notification_display_outbox
      // row, and only the live runtime writes those, so this variant
      // BACKGROUNDS the recipient instead of killing it. Every other variant
      // kills it: the killed path is the premise they grade.
      if (durableBackgroundConnected || fixedWakeRecovery) {
        await _backgroundRecipient();
      } else {
        await _terminateRecipient();
      }

      if (firstWakeProfileAot) {
        _stage = 'first_wake_profile_aot';
        final evidence = await _captureFirstWakeProfileAot();
        _stage = 'restoration';
        await _restoreExactInitialDeviceState();
        _stage = 'artifact';
        _writeFirstWakeProfileAotArtifact(
          relayInfo: relayInfo,
          evidence: evidence,
        );
        stdout.writeln(
          'PASS: $_testCase $_scenario captured at '
          '${artifactDir.path}/$_artifactStem.json',
        );
      }

      if (directTextOnly) {
        _stage = 'direct_text_public_relay';
        final unreadLifecycle = await _captureUnreadLifecycle(
          publicRelayProof: true,
        );
        _stage = 'restoration';
        await _restoreExactInitialDeviceState();
        _stage = 'artifact';
        await _revalidateGateAAuthorization('authorization_before_pass');
        _writeDirectTextPassedArtifact(
          relayInfo: relayInfo,
          unreadLifecycle: unreadLifecycle,
        );
        stdout.writeln(
          'PASS: $_testCase $_scenario captured at '
          '${artifactDir.path}/$_artifactStem.json',
        );
      }

      if (fixedWakeRecovery) {
        _stage = 'fixed_wake_recovery';
        await _captureFixedWakeRecovery(
          relayInfo: relayInfo,
          firstMarker: messageMarker!,
          firstMessageId: messageId!,
          secondMarker: secondMessageMarker!,
          secondMessageId: secondMessageId!,
        );
        stdout.writeln(
          'PASS: $_testCase $_scenario captured at '
          '${artifactDir.path}/$_artifactStem.json',
        );
      }

      if (!directTextOnly && !firstWakeProfileAot && !fixedWakeRecovery) {
        _stage = 'reaction_capture';
        await _adb(senderId, ['logcat', '-c']);
        // Bound the RECIPIENT's window too. The provider send is attributed on
        // that device's own log now, so a marker left by an earlier run must
        // not be able to satisfy this capture.
        await _adb(recipientId, ['logcat', '-c']);
        // The killed-path premise, measured rather than assumed. Absence at
        // kill time is already established by _terminateRecipient; this is
        // absence at the moment the reaction is driven. Non-throwing on
        // purpose: this stage is shared with TC-00, whose contract must not
        // gain a new failure mode.
        final recipientAbsentBeforeReaction =
            await _recipientProcessAndActivityAbsentWithin(
              const Duration(seconds: 5),
            );
        // The alive-connected premise, measured the same way and in the same
        // window: process alive with no resumed activity at the moment the
        // reaction is driven. Only the durable variant claims it, so only the
        // durable variant pays for the measurement.
        final recipientAliveBeforeReaction = durableBackgroundConnected
            ? await _recipientProcessAliveAndBackgroundedWithin(
                const Duration(seconds: 5),
              )
            : false;
        if (durableBackgroundConnected && !recipientAliveBeforeReaction) {
          throw _CampaignFailure(
            _stage,
            'The recipient was not alive-and-backgrounded when the reaction '
            'was driven; this is not an alive-connected proof.',
          );
        }
        final reactionWindowStart = DateTime.now().toUtc();
        await _longPressText(senderId, messageMarker!);
        await _tapText(senderId, _reactionEmoji);
        final senderLogcat = await _waitForReactionSuccess();
        final reactionId = extractReactionSuccessId(senderLogcat);
        if (reactionId == null) {
          throw _CampaignFailure(
            _stage,
            'REACTION_SEND_SUCCESS did not contain a usable event id.',
          );
        }

        await _waitForRelayStore(reactionWindowStart);
        await Future<void>.delayed(_providerObservationDelay);
        // Refetch after the full observation window. Classifying the first
        // journal snapshot that contains the store line could miss a provider
        // send/failure logged a moment later.
        final relayJournal = await _relayJournalSince(reactionWindowStart);
        final relayCapture = classifyRelayCapture(
          log: relayJournal,
          senderPrefix: sender.peerPrefix,
          recipientPrefix: recipient.peerPrefix,
        );
        if (!relayCapture.relayMatchedEvent) {
          throw _CampaignFailure(
            _stage,
            'No relay store matched the bounded sender/recipient reaction window.',
          );
        }
        if (relayCapture.providerFailureMatched) {
          throw _CampaignFailure(
            _stage,
            'The provider attempted the bounded recipient push but reported a failure.',
          );
        }

        // The provider send is attributed on the RECIPIENT device. The relay
        // can no longer say who it pushed to: `[PUSH] Notification sent to
        // <peerPrefix>` is gone and what survives carries no peer at all. The
        // relay-journal match is kept as an accepted source in case it ever
        // returns, but nothing depends on it.
        final recipientPushLog = await _recipientDirectReactionPushWithin(
          const Duration(seconds: 20),
        );
        final recipientBackgroundPushObserved = recipientPushLog != null;
        final providerSendObserved =
            relayCapture.providerMatchedEvent ||
            recipientBackgroundPushObserved;
        final providerEvidenceSource = recipientBackgroundPushObserved
            ? 'recipient_background_push'
            : relayCapture.providerMatchedEvent
            ? 'relay_journal'
            : 'none';

        final notificationDump = await _notificationDump(recipientId);
        final cards = extractActiveNotificationCards(
          notificationDump,
          packageName: appPackage,
        );
        if (providerSendObserved && cards.length != 1) {
          throw _CampaignFailure(
            _stage,
            'A provider send was observed, but ${cards.length} active app cards '
            'were observed; attribution is ambiguous.',
          );
        }
        if (!providerSendObserved && cards.isNotEmpty) {
          throw _CampaignFailure(
            _stage,
            'An app card appeared without an observed provider send; the card '
            'is unrelated or locally produced and TC-00 rejects it.',
          );
        }
        if (_typedCopyRequired && !providerSendObserved) {
          throw _CampaignFailure(
            _stage,
            'The live typed smoke requires one observed provider send.',
          );
        }
        if (_typedCopyRequired) {
          final typedCopyErrors = validateDirectReactionNotificationCard(
            cards.single,
            expectedTitle: sender.username,
            emoji: _reactionEmoji,
          );
          if (typedCopyErrors.isNotEmpty) {
            throw _CampaignFailure(_stage, typedCopyErrors.join('; '));
          }
        }

        // The whole point of this variant. The card alone does not say which
        // arm produced it: the non-durable fallback posts an identical-looking
        // card, which is exactly what the killed-path leg observed.
        final durableShow = durableBackgroundConnected
            ? await _recipientDurableDirectReactionShowWithin(
                const Duration(seconds: 30),
              )
            : null;
        if (durableShow != null && !durableShow.durableArmExecuted) {
          throw _CampaignFailure(
            _stage,
            'The durable direct-reaction arm did not execute: '
            'durableShown=${durableShow.durableShown} '
            'disposition=${durableShow.disposition ?? 'none'} '
            'fallbackShown=${durableShow.fallbackShown} '
            'deferrals=[${durableShow.deferralReasons.join(', ')}].',
          );
        }

        var tapRoute = 'not_applicable';
        if (cards.isNotEmpty) {
          tapRoute = await _tapAndClassifyRoute(cards.single);
        }
        final unreadLifecycle = liveTypedSmoke
            ? await _captureUnreadLifecycle()
            : null;

        _stage = 'artifact';
        final relayEvidence = _writeRelayEvidence(
          relayJournal,
          reactionWindowStart,
        );
        final senderEvidence = File(
          '${artifactDir.path}/sender_reaction_flow.log',
        )..writeAsStringSync(_reactionFlowLines(senderLogcat));
        final notificationEvidence = File(
          '${artifactDir.path}/recipient_notification_record.txt',
        )..writeAsStringSync(_appNotificationRecords(notificationDump));
        final providerEvidence = File(
          '${artifactDir.path}/recipient_background_push.log',
        )..writeAsStringSync(_backgroundPushFlowLines(recipientPushLog ?? ''));
        final durableEvidence =
            File(
              '${artifactDir.path}/recipient_durable_effect.log',
            )..writeAsStringSync(
              'durableShown=${durableShow?.durableShown ?? false}\n'
              'disposition=${durableShow?.disposition ?? 'not_observed'}\n'
              'silent=${durableShow?.silent}\n'
              'fallbackShown=${durableShow?.fallbackShown ?? false}\n'
              'deferralReasons=${durableShow?.deferralReasons.join(',') ?? ''}\n',
            );
        _writePassedArtifact(
          relayInfo: relayInfo,
          reactionId: reactionId,
          messageId: messageId!,
          card: cards.isEmpty ? null : cards.single,
          tapRoute: tapRoute,
          recipientAbsentBeforeReaction: recipientAbsentBeforeReaction,
          recipientAliveBeforeReaction: recipientAliveBeforeReaction,
          durableShow: durableShow,
          durableEvidence: durableEvidence,
          providerSendObserved: providerSendObserved,
          recipientBackgroundPushObserved: recipientBackgroundPushObserved,
          providerEvidenceSource: providerEvidenceSource,
          providerEvidence: providerEvidence,
          relayCapture: relayCapture,
          relayEvidence: relayEvidence,
          senderEvidence: senderEvidence,
          notificationEvidence: notificationEvidence,
          unreadLifecycle: unreadLifecycle,
        );
        stdout.writeln(
          'PASS: $_testCase $_scenario captured at '
          '${artifactDir.path}/$_artifactStem.json',
        );
      }
    } on _CampaignFailure catch (failure, stackTrace) {
      primaryFailure = failure;
      primaryStackTrace = stackTrace;
    } on Object catch (_, stackTrace) {
      primaryFailure = _CampaignFailure(_stage, 'Unexpected campaign failure.');
      primaryStackTrace = stackTrace;
    }
    try {
      if ((directTextOnly || firstWakeProfileAot) &&
          !_exactRestorationComplete) {
        await _restoreExactInitialDeviceState();
      } else {
        if (!directTextOnly && !firstWakeProfileAot && !statePreparedByParent) {
          await _restoreNormalBuilds();
        }
      }
      await _removeCleanWorktree();
    } on _CampaignFailure catch (failure) {
      cleanupFailure = failure;
    } on Object {
      cleanupFailure = _CampaignFailure(
        'restoration',
        'Unexpected restoration failure.',
      );
    }
    final primary = primaryFailure;
    final cleanup = cleanupFailure;
    if (primary != null) {
      final composed = cleanup == null
          ? primary
          : _CampaignFailure(
              primary.stage,
              primary.message,
              environmentBlocked: primary.environmentBlocked,
              cleanupFailure: cleanup,
            );
      Error.throwWithStackTrace(
        composed,
        primaryStackTrace ?? StackTrace.current,
      );
    }
    if (cleanup != null) {
      throw cleanup;
    }
  }

  void writeFailure(_CampaignFailure failure, StackTrace stackTrace) {
    String sanitize(String value) =>
        value.replaceAll(RegExp(r'12D3Koo\S+'), '[peer]');
    File('${artifactDir.path}/${_artifactStem}_failure.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'testCase': _testCase,
        'scenario': _scenario,
        'status': 'failed',
        'stage': failure.stage,
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'error': sanitize(failure.message),
        'cleanupFailure': failure.cleanupFailure == null
            ? null
            : <String, Object?>{
                'stage': failure.cleanupFailure!.stage,
                'error': sanitize(failure.cleanupFailure!.message),
              },
        'stackType': stackTrace.runtimeType.toString(),
      }),
    );
  }

  Future<void> _verifyEnvironment() async {
    final devices = await _run('adb', ['devices']);
    for (final id in [senderId, recipientId]) {
      if (!devices.stdout.contains('$id\tdevice')) {
        throw _CampaignFailure(
          _stage,
          'Android target $id is not a live adb device.',
          environmentBlocked: true,
        );
      }
    }
    if (relayFixtureProbe == null && !relayKey.existsSync()) {
      throw _CampaignFailure(
        _stage,
        'Relay SSH key is unavailable at ${relayKey.path}.',
        environmentBlocked: true,
      );
    }
    if (firstWakeProfileAot || fixedWakeRecovery) {
      for (final requiredFile in <File?>[serviceAccount, stagingManifest]) {
        if (requiredFile == null ||
            !requiredFile.existsSync() ||
            requiredFile.lengthSync() <= 0) {
          throw _CampaignFailure(
            _stage,
            'The profile-AOT/fixed-wake credential or manifest is missing.',
            environmentBlocked: true,
          );
        }
      }
      try {
        final manifest = jsonDecode(stagingManifest!.readAsStringSync());
        if (manifest is! Map<String, dynamic> || manifest.isEmpty) {
          throw const FormatException('empty staging manifest');
        }
        final credential = jsonDecode(serviceAccount!.readAsStringSync());
        if (credential is! Map<String, dynamic> ||
            credential['type'] != 'service_account') {
          throw const FormatException('not a service account');
        }
      } on Object {
        throw _CampaignFailure(
          _stage,
          'The profile-AOT/fixed-wake manifest or FCM account is invalid.',
          environmentBlocked: true,
        );
      }
    }
    if (relayFixtureProbe == null) {
      final ssh = await _ssh(['systemctl', 'is-active', 'relay-server']);
      if (ssh.stdout.trim() != 'active') {
        throw _CampaignFailure(
          _stage,
          'Relay service is not active on the configured capture target.',
          environmentBlocked: true,
        );
      }
    } else {
      await _relayFixtureSnapshot(DateTime.fromMillisecondsSinceEpoch(0));
    }
  }

  Future<_RelayInfo> _readRelayInfo() async {
    if (relayFixtureProbe != null) {
      final snapshot = await _relayFixtureSnapshot(
        DateTime.fromMillisecondsSinceEpoch(0),
      );
      return _RelayInfo(
        version: snapshot['relayVersion']! as String,
        sha256: snapshot['relayBinarySha256']! as String,
        executionBoundary: 'ephemeral_production_redis_fixture',
        backend: snapshot['backend']! as String,
        pushTokenState: snapshot['pushTokenState']! as String,
        wakeOutcomeLedger: 'redis',
        provider: 'fcm',
      );
    }
    final version = await _ssh(['/usr/local/bin/relay-server', 'version']);
    final sha = await _ssh(['sha256sum', '/usr/local/bin/relay-server']);
    return _RelayInfo(
      version: version.stdout.trim(),
      sha256: sha.stdout.trim().split(RegExp(r'\s+')).first,
    );
  }

  Future<_BuildArtifacts> _buildCleanHeadApks() async {
    final revision = (await _run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: sourceRoot.path)).stdout.trim();
    final cachedE2E = File('${artifactDir.path}/clean_head_e2e.apk');
    final cachedNormal = File('${artifactDir.path}/clean_head_normal.apk');
    final cacheMetadata = File('${artifactDir.path}/clean_head_build.json');
    if (cachedE2E.existsSync() &&
        cachedNormal.existsSync() &&
        cacheMetadata.existsSync()) {
      try {
        final metadata =
            jsonDecode(cacheMetadata.readAsStringSync())
                as Map<String, dynamic>;
        if (metadata['revision'] == revision &&
            metadata['buildProfile'] == _androidBuildProfile) {
          final e2eSha = await _sha256(cachedE2E);
          final normalSha = await _sha256(cachedNormal);
          if (metadata['e2eApkSha256'] == e2eSha &&
              metadata['normalApkSha256'] == normalSha) {
            stdout.writeln(
              'Reusing verified clean-HEAD APK cache for $revision.',
            );
            return _BuildArtifacts(
              revision: revision,
              e2eApk: cachedE2E,
              normalApk: cachedNormal,
              e2eApkSha256: e2eSha,
              normalApkSha256: normalSha,
              buildMode: 'standalone_cached',
              buildProfile: _androidBuildProfile,
              childBuildCount: 0,
            );
          }
        }
      } on FormatException {
        // Rebuild below; malformed cache metadata is never trusted.
      }
    }
    final temp = await Directory.systemTemp.createTemp('mknoon_256_head_');
    await temp.delete();
    _cleanWorktree = temp;
    await _runStreaming('git', [
      'worktree',
      'add',
      '--detach',
      temp.path,
      revision,
    ], workingDirectory: sourceRoot.path);

    final googleServices = File(
      '${sourceRoot.path}/android/app/google-services.json',
    );
    if (!googleServices.existsSync()) {
      throw _CampaignFailure(
        _stage,
        'android/app/google-services.json is required for real FCM capture.',
        environmentBlocked: true,
      );
    }
    final cleanGoogleServices = File(
      '${temp.path}/android/app/google-services.json',
    );
    await googleServices.copy(cleanGoogleServices.path);

    final trackedDiff = await _run('git', [
      'status',
      '--porcelain',
      '--untracked-files=no',
    ], workingDirectory: temp.path);
    if (trackedDiff.stdout.trim().isNotEmpty) {
      throw _CampaignFailure(
        _stage,
        'The isolated HEAD worktree has tracked modifications before build.',
      );
    }

    await _runStreaming('flutter', [
      'build',
      'apk',
      '--debug',
      '--target-platform=android-arm64',
      '--split-per-abi',
      '--dart-define=E2E_TEST_MODE=true',
    ], workingDirectory: temp.path);
    final builtApk = File(
      '${temp.path}/build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk',
    );
    if (!builtApk.existsSync()) {
      throw _CampaignFailure(
        _stage,
        'Clean E2E debug APK did not materialize.',
      );
    }
    final e2eApk = await builtApk.copy(cachedE2E.path);

    await _runStreaming('flutter', [
      'build',
      'apk',
      '--debug',
      '--target-platform=android-arm64',
      '--split-per-abi',
      '--dart-define=E2E_TEST_MODE=false',
    ], workingDirectory: temp.path);
    if (!builtApk.existsSync()) {
      throw _CampaignFailure(
        _stage,
        'Clean normal debug APK did not materialize.',
      );
    }
    final normalApk = await builtApk.copy(cachedNormal.path);

    final result = _BuildArtifacts(
      revision: revision,
      e2eApk: e2eApk,
      normalApk: normalApk,
      e2eApkSha256: await _sha256(e2eApk),
      normalApkSha256: await _sha256(normalApk),
      buildMode: 'standalone_child_builds',
      buildProfile: _androidBuildProfile,
      childBuildCount: 2,
    );
    cacheMetadata.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'revision': revision,
        'buildProfile': _androidBuildProfile,
        'e2eApkSha256': result.e2eApkSha256,
        'normalApkSha256': result.normalApkSha256,
      }),
    );
    return result;
  }

  Future<_BuildArtifacts> _useCentralPrebuiltAndroidApk() async {
    final prepared = prebuiltAndroidApk;
    if (!noChildBuilds ||
        !statePreparedByParent ||
        prepared == null ||
        FileSystemEntity.typeSync(prepared.path, followLinks: true) !=
            FileSystemEntityType.file ||
        prepared.lengthSync() <= 0) {
      throw _CampaignFailure(
        _stage,
        'The central-prebuilt contract is incomplete; child builds remain '
        'forbidden.',
        environmentBlocked: true,
      );
    }
    final profile = Platform.environment['SIMS_ARTIFACT_PROFILE_ID']?.trim();
    final expectedProfile = fixedWakeRecovery
        ? _fixedWakeRecoveryBuildProfile
        : 'android.production_fcm';
    if (profile != null && profile.isNotEmpty && profile != expectedProfile) {
      throw _CampaignFailure(
        _stage,
        'Prepared build profile $profile is not $expectedProfile.',
        environmentBlocked: true,
      );
    }
    final head = (await _run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: sourceRoot.path)).stdout.trim();
    final status = await _run('git', [
      'status',
      '--porcelain',
    ], workingDirectory: sourceRoot.path);
    final revision = status.stdout.trim().isEmpty ? head : '$head+working-tree';
    final preparedSha = await _sha256(prepared);
    final result = _BuildArtifacts(
      revision: revision,
      e2eApk: prepared,
      normalApk: prepared,
      e2eApkSha256: preparedSha,
      normalApkSha256: preparedSha,
      buildMode: 'central_prebuilt',
      buildProfile: expectedProfile,
      childBuildCount: 0,
    );
    File(
      '${artifactDir.path}/candidate_build_provenance.json',
    ).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schema': 'mknoon.plan257.candidate-build.v1',
        'revision': revision,
        'buildMode': result.buildMode,
        'buildProfile': result.buildProfile,
        'childBuildCount': result.childBuildCount,
        'preparedArtifactPath': prepared.resolveSymbolicLinksSync(),
        'preparedArtifactSha256': preparedSha,
        'e2eApkSha256': preparedSha,
        'normalApkSha256': preparedSha,
        'senderApkSha256': preparedSha,
        'recipientApkSha256': preparedSha,
      }),
    );
    return result;
  }

  Future<_BuildArtifacts> _buildWorkingTreeApks() async {
    final head = (await _run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: sourceRoot.path)).stdout.trim();
    final status = await _run('git', [
      'status',
      '--porcelain',
    ], workingDirectory: sourceRoot.path);
    final revision = status.stdout.trim().isEmpty ? head : '$head+working-tree';
    final e2eTarget = File('${artifactDir.path}/working_tree_e2e.apk');
    final normalTarget = File('${artifactDir.path}/working_tree_normal.apk');

    final googleServices = File(
      '${sourceRoot.path}/android/app/google-services.json',
    );
    if (!googleServices.existsSync()) {
      throw _CampaignFailure(
        _stage,
        'android/app/google-services.json is required for real FCM capture.',
        environmentBlocked: true,
      );
    }

    await _runStreaming('flutter', [
      'build',
      'apk',
      '--debug',
      '--target-platform=android-arm64',
      '--split-per-abi',
      '--dart-define=E2E_TEST_MODE=true',
      '--dart-define=MKNOON_EMIT_WAKE_TOKEN=true',
      if (firstWakeProfileAot) '--dart-define=PRODUCTION_FCM=true',
    ], workingDirectory: sourceRoot.path);
    final builtApk = File(
      '${sourceRoot.path}/build/app/outputs/flutter-apk/'
      'app-arm64-v8a-debug.apk',
    );
    if (!builtApk.existsSync()) {
      throw _CampaignFailure(
        _stage,
        'Working-tree E2E APK did not materialize.',
      );
    }
    final e2eApk = await builtApk.copy(e2eTarget.path);

    if (firstWakeProfileAot) {
      await _runStreaming('flutter', [
        'build',
        'apk',
        '--profile',
        '--target-platform=android-arm64',
        '--split-per-abi',
        '--dart-define=E2E_TEST_MODE=true',
        '--dart-define=PRODUCTION_FCM=true',
        '--dart-define=MKNOON_EMIT_WAKE_TOKEN=true',
        if (measurementOnly)
          '--dart-define=MKNOON_NOTIFICATION_G21_MEASUREMENT=true',
      ], workingDirectory: sourceRoot.path);
    } else {
      await _runStreaming('flutter', [
        'build',
        'apk',
        '--debug',
        '--target-platform=android-arm64',
        '--split-per-abi',
        '--dart-define=E2E_TEST_MODE=false',
        '--dart-define=MKNOON_EMIT_WAKE_TOKEN=true',
        if (directTextOnly)
          '--dart-define=MKNOON_DIRECT_TEXT_RELAY_TOKEN_PROOF=true',
      ], workingDirectory: sourceRoot.path);
    }
    final recipientBuiltApk = firstWakeProfileAot
        ? File(
            '${sourceRoot.path}/build/app/outputs/flutter-apk/'
            'app-arm64-v8a-profile.apk',
          )
        : builtApk;
    if (!recipientBuiltApk.existsSync()) {
      throw _CampaignFailure(
        _stage,
        'Working-tree recipient APK did not materialize.',
      );
    }
    final normalApk = await recipientBuiltApk.copy(normalTarget.path);
    final result = _BuildArtifacts(
      revision: revision,
      e2eApk: e2eApk,
      normalApk: normalApk,
      e2eApkSha256: await _sha256(e2eApk),
      normalApkSha256: await _sha256(normalApk),
      buildMode: 'standalone_child_builds',
      buildProfile: firstWakeProfileAot
          ? _firstWakeProfileAotBuildProfile
          : _androidBuildProfile,
      childBuildCount: 2,
    );
    File('${artifactDir.path}/working_tree_build.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'revision': revision,
        'buildProfile': result.buildProfile,
        'dirtyAtBuild': status.stdout.trim().isNotEmpty,
        'directTextRelayTokenProof': directTextOnly,
        'firstWakeProfileAot': firstWakeProfileAot,
        'measurementOnly': firstWakeProfileAot ? measurementOnly : null,
        'e2eApkSha256': result.e2eApkSha256,
        'normalApkSha256': result.normalApkSha256,
      }),
    );
    return result;
  }

  Future<_BuildArtifacts> _reuseWorkingTreeApks() async {
    if (!liveTypedSmoke && !directTextOnly) {
      throw _CampaignFailure(
        _stage,
        '--reuse-working-tree-apks requires a working-tree proof mode.',
      );
    }
    final metadataFile = File('${artifactDir.path}/working_tree_build.json');
    final e2eApk = File('${artifactDir.path}/working_tree_e2e.apk');
    final normalApk = File('${artifactDir.path}/working_tree_normal.apk');
    if (!metadataFile.existsSync() ||
        !e2eApk.existsSync() ||
        !normalApk.existsSync()) {
      throw _CampaignFailure(
        _stage,
        'Reusable working-tree APKs and their build metadata are required.',
      );
    }

    final metadata = jsonDecode(metadataFile.readAsStringSync());
    if (metadata is! Map<String, dynamic> ||
        metadata['buildProfile'] != _androidBuildProfile ||
        metadata['directTextRelayTokenProof'] != directTextOnly) {
      throw _CampaignFailure(
        _stage,
        'Reusable APK metadata has the wrong build profile.',
      );
    }
    final revision = metadata['revision'];
    final expectedE2E = metadata['e2eApkSha256'];
    final expectedNormal = metadata['normalApkSha256'];
    if (revision is! String ||
        expectedE2E is! String ||
        expectedNormal is! String) {
      throw _CampaignFailure(_stage, 'Reusable APK metadata is incomplete.');
    }
    final head = (await _run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: sourceRoot.path)).stdout.trim();
    if (revision != head && revision != '$head+working-tree') {
      throw _CampaignFailure(
        _stage,
        'Reusable APK revision $revision does not match current HEAD $head.',
      );
    }
    final actualE2E = await _sha256(e2eApk);
    final actualNormal = await _sha256(normalApk);
    if (actualE2E != expectedE2E || actualNormal != expectedNormal) {
      throw _CampaignFailure(
        _stage,
        'Reusable APK hash does not match its persisted build metadata.',
      );
    }
    return _BuildArtifacts(
      revision: revision,
      e2eApk: e2eApk,
      normalApk: normalApk,
      e2eApkSha256: actualE2E,
      normalApkSha256: actualNormal,
      buildMode: 'standalone_cached',
      buildProfile: _androidBuildProfile,
      childBuildCount: 0,
    );
  }

  Future<void> _prepareE2EParty(_Party party, String username) async {
    await _adbShell(party.deviceId, ['input', 'keyevent', 'KEYCODE_WAKEUP']);
    await _adbShell(party.deviceId, [
      'wm',
      'dismiss-keyguard',
    ], allowFail: true);
    await _adbShell(party.deviceId, [
      'cmd',
      'statusbar',
      'collapse',
    ], allowFail: true);
    await _writeAppFile(
      party.deviceId,
      'auto_setup.json',
      jsonEncode({'username': username}),
    );
    for (final name in const [
      'intro_e2e_identity.json',
      'intro_e2e_config.json',
      'intro_e2e_result.json',
    ]) {
      await _adbShell(party.deviceId, [
        'run-as',
        appPackage,
        'rm',
        '-f',
        'app_flutter/$name',
      ], allowFail: true);
    }
  }

  Future<void> _collectIdentity(_Party party) async {
    final raw = await _waitForValue(
      'identity export for ${party.role}',
      const Duration(minutes: 3),
      () => _readAppFile(party.deviceId, 'intro_e2e_identity.json'),
    );
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    party.qrPayload = decoded['qrPayload'] as String;
    party.mlKemPublicKey = decoded['mlKemPublicKey'] as String?;
    final qr = jsonDecode(party.qrPayload) as Map<String, dynamic>;
    party.peerId = qr['ns'] as String;
    party.username = (qr['un'] as String?) ?? party.role;
  }

  Future<void> _prepopulateContacts() async {
    await _prepopulateContactAtStartup(sender, recipient);
    await _prepopulateContactAtStartup(recipient, sender);
    await _exchangeWakeToken(sender, recipient);
    await _exchangeWakeToken(recipient, sender);
    await _openConversation(sender, recipient.username);
  }

  Future<String> _seedIncomingMessage(String marker) async {
    await _openConversation(recipient, sender.username);
    await _adb(recipientId, ['logcat', '-c']);
    final markerEntry = await enterGroupComposeMarkerOnce(
      marker: marker,
      readUiDump: () => _uiDump(recipientId),
      tapEditor: (center) async {
        await _adbShell(recipientId, [
          'input',
          'tap',
          '${center.$1}',
          '${center.$2}',
        ]);
      },
      injectMarker: (value) async {
        await _adbShell(recipientId, ['input', 'text', value]);
      },
      maximumFocusPolls: 40,
      maximumAcceptancePolls: 40,
    );
    if (markerEntry != GroupComposeMarkerEntryOutcome.accepted) {
      throw _CampaignFailure(
        _stage,
        'The recipient compose marker was not accepted: ${markerEntry.name}.',
      );
    }

    final typedDump = await _uiDump(recipientId);
    final typedEditor = findEnabledFocusableGroupComposeEditorBounds(
      typedDump,
      requireFocused: true,
      exactText: marker,
    );
    if (typedEditor == null) {
      throw _CampaignFailure(
        _stage,
        'The compose editor disappeared before the UI-seeded send.',
      );
    }
    await _adbShell(recipientId, [
      'input',
      'tap',
      '${typedEditor.$3 + 75}',
      '${(typedEditor.$2 + typedEditor.$4) ~/ 2}',
    ]);

    final messageId = await _waitForValue(
      'UI-seeded chat send success on B',
      const Duration(seconds: 90),
      () async {
        final logcat = await _adb(recipientId, ['logcat', '-d']);
        return extractChatSendSuccessId(logcat.stdout + logcat.stderr);
      },
    );
    await _waitForUiText(senderId, marker, const Duration(seconds: 60));
    return messageId;
  }

  Future<void> _prepopulateContactAtStartup(
    _Party owner,
    _Party contact,
  ) async {
    final stepId =
        '256-head-${owner.role.toLowerCase()}-fixture-'
        '${DateTime.now().microsecondsSinceEpoch}';
    await _deleteAppFile(owner.deviceId, 'intro_e2e_result.json');
    await _writeAppFile(
      owner.deviceId,
      'intro_e2e_config.json',
      jsonEncode({
        'stepId': stepId,
        'add_contacts': [_contactEntry(contact)],
      }),
    );
    // Android's activity-level wait does not prove that Flutter consumed this
    // startup file. Keep it in place until the app publishes the matching
    // completed receipt and its snapshot contains the expected contact.
    await _launch(owner.deviceId);
    await _waitForIntroE2EStepCompletion(
      owner: owner,
      stepId: stepId,
      expectedContactPeerId: contact.peerId,
    );
    await _deleteAppFile(owner.deviceId, 'intro_e2e_config.json');
    await _deleteAppFile(owner.deviceId, 'intro_e2e_result.json');
    await _launch(owner.deviceId);
  }

  Future<Map<String, dynamic>> _waitForIntroE2EStepCompletion({
    required _Party owner,
    required String stepId,
    required String expectedContactPeerId,
  }) => _waitForValue<Map<String, dynamic>>(
    'completed contact bootstrap on ${owner.role}',
    const Duration(minutes: 3),
    () async {
      final raw = await _readAppFile(owner.deviceId, 'intro_e2e_result.json');
      if (raw == null) return null;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return null;
        final result = Map<String, dynamic>.from(decoded);
        if (result['stepId'] != stepId) return null;
        if (result['status'] == 'failed' || result['success'] == false) {
          throw _CampaignFailure(
            _stage,
            'Contact bootstrap failed on ${owner.role}.',
          );
        }
        if (result['status'] != 'complete' || result['success'] != true) {
          return null;
        }
        final snapshot = result['snapshot'];
        final contacts = snapshot is Map ? snapshot['contacts'] : null;
        final expectedContactPresent =
            contacts is List &&
            contacts.whereType<Map>().any(
              (contact) => contact['peerId'] == expectedContactPeerId,
            );
        if (!expectedContactPresent) {
          throw _CampaignFailure(
            _stage,
            'Contact bootstrap receipt on ${owner.role} omitted the expected contact.',
          );
        }
        return result;
      } on FormatException {
        return null;
      }
    },
  );

  Future<void> _exchangeWakeToken(_Party owner, _Party contact) async {
    final stepId =
        '256-wake-${owner.role.toLowerCase()}-'
        '${DateTime.now().microsecondsSinceEpoch}';
    await _adb(contact.deviceId, ['logcat', '-c']);
    await _deleteAppFile(owner.deviceId, 'intro_e2e_result.json');
    await _writeAppFile(
      owner.deviceId,
      'intro_e2e_config.json',
      jsonEncode({
        'stepId': stepId,
        'add_contacts': [_contactEntry(contact)],
        'send_contact_requests_for_added_contacts': true,
      }),
    );
    await _launch(owner.deviceId);
    final raw = await _waitForValue(
      'recipient-issued wake authorization exchange for ${owner.role}',
      const Duration(minutes: 3),
      () async {
        final value = await _readAppFile(
          owner.deviceId,
          'intro_e2e_result.json',
        );
        if (value == null) return null;
        try {
          final decoded = jsonDecode(value) as Map<String, dynamic>;
          if (decoded['stepId'] != stepId) return null;
          if (decoded['status'] == 'failed') {
            throw _CampaignFailure(
              _stage,
              'Wake authorization exchange failed for ${owner.role}.',
            );
          }
          return decoded['status'] == 'complete' ? value : null;
        } on FormatException {
          return null;
        }
      },
    );
    final result = jsonDecode(raw) as Map<String, dynamic>;
    if (result['success'] != true) {
      throw _CampaignFailure(
        _stage,
        'Wake authorization exchange did not complete for ${owner.role}.',
      );
    }
    await _waitFor(
      'wake authorization persistence on ${contact.role}',
      const Duration(seconds: 60),
      () async {
        final logcat = await _adb(contact.deviceId, [
          'logcat',
          '-d',
          '-v',
          'brief',
        ]);
        return logcat.stdout.contains('WAKE_TOKEN_RECEIVED_STORED');
      },
    );
    await _deleteAppFile(owner.deviceId, 'intro_e2e_config.json');
    await _deleteAppFile(owner.deviceId, 'intro_e2e_result.json');
    await _launch(owner.deviceId);
  }

  Future<void> _openConversation(_Party owner, String contactUsername) async {
    var dump = await _uiDump(owner.deviceId);
    if (findNodeBoundsByClass(dump, 'android.widget.EditText') != null) {
      if (findSemanticNodeCenter(dump, contactUsername) != null) return;
      await _adbShell(owner.deviceId, ['input', 'keyevent', 'KEYCODE_BACK']);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      dump = await _uiDump(owner.deviceId);
    }

    // `am start -W` proves only that Android resumed MainActivity; the first
    // Flutter frame can still be pending. Sampling once here made clean,
    // prebuilt runs fail before the campaign whenever Orbit rendered a moment
    // after the activity-level wait completed.
    var lastDump = dump;
    try {
      dump = await _waitForValue<String>(
        'direct chat or chat-list entry point on ${owner.role}',
        const Duration(seconds: 20),
        () async {
          final candidate = await _uiDump(owner.deviceId);
          lastDump = candidate;
          final directReady = findSemanticNodeCenter(
            candidate,
            'Open chat with $contactUsername',
          );
          final chatListReady = findSemanticNodeCenter(
            candidate,
            'Show all chats',
          );
          final alreadyInChatList = findSemanticNodeCenter(
            candidate,
            'Show inner circle',
          );
          final listContactReady = findSemanticNodeCenter(
            candidate,
            contactUsername,
          );
          return directReady != null ||
                  chatListReady != null ||
                  alreadyInChatList != null ||
                  listContactReady != null
              ? candidate
              : null;
        },
      );
    } on _CampaignFailure {
      await _captureConversationEntryDiagnostic(
        owner: owner,
        contactUsername: contactUsername,
        uiDump: lastDump,
      );
      rethrow;
    }

    final direct = findSemanticNodeCenter(
      dump,
      'Open chat with $contactUsername',
    );
    if (direct != null) {
      await _adbShell(owner.deviceId, [
        'input',
        'tap',
        '${direct.$1}',
        '${direct.$2}',
      ]);
    } else {
      var contact = findSemanticNodeCenter(dump, contactUsername);
      final allChats = findSemanticNodeCenter(dump, 'Show all chats');
      final alreadyInChatList = findSemanticNodeCenter(
        dump,
        'Show inner circle',
      );
      if (contact == null && allChats == null && alreadyInChatList == null) {
        throw _CampaignFailure(
          _stage,
          'Could not find the direct chat or chat-list entry point on ${owner.role}.',
        );
      }
      if (contact == null && allChats != null) {
        await _adbShell(owner.deviceId, [
          'input',
          'tap',
          '${allChats.$1}',
          '${allChats.$2}',
        ]);
      }
      contact ??= await _waitForBounds(
        owner.deviceId,
        contactUsername,
        const Duration(seconds: 20),
      );
      await _adbShell(owner.deviceId, [
        'input',
        'tap',
        '${contact.$1}',
        '${contact.$2}',
      ]);
    }

    await _waitForValue(
      'conversation compose editor on ${owner.role}',
      const Duration(seconds: 20),
      () async => findNodeBoundsByClass(
        await _uiDump(owner.deviceId),
        'android.widget.EditText',
      ),
    );
  }

  Future<void> _captureConversationEntryDiagnostic({
    required _Party owner,
    required String contactUsername,
    required String uiDump,
  }) async {
    try {
      artifactDir.createSync(recursive: true);
      final stem = '${_artifactStem}_${owner.role.toLowerCase()}_conversation';
      final packages =
          RegExp(r'package="([^"]+)"')
              .allMatches(uiDump)
              .map((match) => match.group(1)!)
              .toSet()
              .toList(growable: false)
            ..sort();
      final screenshot = File('${artifactDir.path}/${stem}_failure.png');
      final capture = await Process.run('adb', <String>[
        '-s',
        owner.deviceId,
        'exec-out',
        'screencap',
        '-p',
      ], stdoutEncoding: null);
      final screenshotCaptured =
          capture.exitCode == 0 && capture.stdout is List<int>;
      if (screenshotCaptured) {
        await screenshot.writeAsBytes(capture.stdout as List<int>, flush: true);
      }
      await File('${artifactDir.path}/${stem}_failure.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'role': owner.role,
          'uiSha256': sha256.convert(utf8.encode(uiDump)).toString(),
          'nodeCount': RegExp(r'<node\b').allMatches(uiDump).length,
          'packages': packages,
          'appPackageVisible': packages.contains(appPackage),
          'systemUiVisible': packages.contains('com.android.systemui'),
          'composeEditorVisible':
              findNodeBoundsByClass(uiDump, 'android.widget.EditText') != null,
          'directContactVisible':
              findSemanticNodeCenter(
                uiDump,
                'Open chat with $contactUsername',
              ) !=
              null,
          'listContactVisible':
              findSemanticNodeCenter(uiDump, contactUsername) != null,
          'showAllChatsVisible':
              findSemanticNodeCenter(uiDump, 'Show all chats') != null,
          'showInnerCircleVisible':
              findSemanticNodeCenter(uiDump, 'Show inner circle') != null,
          'screenshotCaptured': screenshotCaptured,
          'screenshot': screenshotCaptured ? screenshot.path : null,
          'containsSecrets': false,
        }),
        flush: true,
      );
    } on Object {
      // Diagnostics must never replace the original causal failure.
    }
  }

  Map<String, dynamic> _contactEntry(_Party party) => {
    'qrPayload': party.qrPayload,
    'mlKemPublicKey': party.mlKemPublicKey,
  };

  /// Waits until the RECIPIENT device's own log shows the relay accepted its
  /// Android push-token registration.
  ///
  /// Replaces a relay-journal grep for
  /// `[PUSH] Token registered for <peerPrefix> (android)`, which relay v1.8.0
  /// (`8d86501e4`) deleted along with the rest of the identifying `[PUSH]`
  /// vocabulary. That removal is deliberate and pinned by Plan 368, so the fix
  /// is to stop asking the relay who registered and ask the device instead —
  /// better attribution too, since the log is unambiguously this device's
  /// rather than a 20-char peer prefix. Measured 2026-08-20: the recipient
  /// logged `relay_push_registration_success` at 07:49:06Z and the old wait
  /// still failed at 07:51:12Z, which had been blocking every Android capture
  /// on this lane. `capture_group_reaction_notification_device.dart` already
  /// made the same move.
  /// Polls the RECIPIENT's own log for the direct-reaction background push and
  /// returns the log that carries it, or null if the window closes first.
  ///
  /// Non-throwing: absence of a push is a legitimate TC-00 outcome
  /// (`providerConfirmedNoSend`), and only the typed smoke requires one.
  Future<String?> _recipientDirectReactionPushWithin(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final log = (await _adb(recipientId, [
        'logcat',
        '-d',
        '-v',
        'brief',
      ])).stdout;
      if (androidDirectReactionBackgroundPushObserved(log)) return log;
      if (!DateTime.now().isBefore(deadline)) return null;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _waitForRecipientPushRegistrationAccepted() async {
    await _waitFor(
      'recipient android push registration accepted by the relay',
      const Duration(minutes: 3),
      () async => androidRelayPushRegistrationAccepted(
        (await _adb(recipientId, [
          'logcat',
          '-d',
          '-v',
          'brief',
        ], allowFail: true)).stdout,
      ),
    );
  }

  Future<void> _waitForRelayTokenRegistration(DateTime since) async {
    final prefix = recipient.peerPrefix;
    final journal = await _waitForValue(
      'recipient FCM token registration',
      const Duration(minutes: 2),
      () async {
        final log = await _relayJournalSince(since);
        return log.contains('[PUSH] Token registered for $prefix (android)')
            ? log
            : null;
      },
    );
    if (directTextOnly) {
      final evidence =
          File(
            '${artifactDir.path}/direct_text_token_registration.log',
          )..writeAsStringSync(
            'windowStart=${since.toIso8601String()}\n'
            '${journal.split('\n').where((line) => line.contains('[PUSH] Token registered for $prefix (android)')).join('\n')}\n',
          );
      _relayTokenRegistrationEvidencePath = evidence.path;
    }
  }

  Future<Map<String, Object?>> _revalidateGateAAuthorization(
    String boundary,
  ) async {
    final bytes = gateAArtifactBytes;
    final original = gateAAuthorization;
    if (bytes == null || original == null) {
      throw _CampaignFailure(
        _stage,
        'Gate A authorization is unavailable at $boundary.',
      );
    }
    Map<String, Object?> current;
    try {
      current = revalidateDirectTextGateAAuthorization(
        bytes,
        now: DateTime.now().toUtc(),
        expectedArtifactSha256: original['gateAArtifactSha256']! as String,
        expectedAuthorization: original,
      );
    } on Object {
      throw _CampaignFailure(
        _stage,
        'Gate A authorization expired or changed at $boundary.',
      );
    }
    final file = gateAArtifact;
    if (file == null ||
        !file.existsSync() ||
        sha256.convert(file.readAsBytesSync()).toString() !=
            current['gateAArtifactSha256']) {
      throw _CampaignFailure(
        _stage,
        'Gate A artifact bytes changed at $boundary.',
      );
    }
    gateAAuthorization = current;
    return current;
  }

  Future<void> _stageDirectTextTokenProofCommand() async {
    await _removeAndVerifyDirectTextTokenProofFiles();
    final authorization = await _revalidateGateAAuthorization(
      'command_staging',
    );
    final recipientIdentitySha256 = sha256
        .convert(utf8.encode(recipient.peerId))
        .toString();
    if (authorization['accountIdentitySha256'] != recipientIdentitySha256 ||
        authorization['transportIdentitySha256'] != recipientIdentitySha256) {
      throw _CampaignFailure(
        _stage,
        'Gate A account/transport identity does not match the recipient.',
      );
    }
    final now = DateTime.now().toUtc();
    final commandId =
        'direct-text-relay-${now.microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(0x7fffffff)}';
    final bytes = utf8.encode(
      jsonEncode(<String, Object?>{
        'schema': directTextRelayTokenProofCommandSchemaV2,
        'commandId': commandId,
        'issuedAt': now.toIso8601String(),
        'maxAgeSeconds': 300,
        'tokenSha256': authorization['tokenSha256'],
        'authorizationKind': authorization['authorizationKind'],
        'authorizationArtifactSha256':
            authorization['authorizationArtifactSha256'],
        'gateACommandGenerationId': authorization['gateACommandGenerationId'],
        'gateAArtifactSha256': authorization['gateAArtifactSha256'],
        'accountIdentitySha256': authorization['accountIdentitySha256'],
        'transportIdentitySha256': authorization['transportIdentitySha256'],
      }),
    );
    final staged = await copyBackgroundCryptoCommandBytesToAppPrivateFile(
      bytes: bytes,
      run: _runDirectTextPrivateFileTransport,
      appPrivatePath: directTextRelayTokenProofCommandPath,
    );
    await _adbShell(recipientId, <String>[
      'run-as',
      appPackage,
      'chmod',
      '0600',
      directTextRelayTokenProofCommandPath,
    ]);
    await _requireRunAsFileMode(
      recipientId,
      directTextRelayTokenProofCommandPath,
      '600',
    );
    _directTextTokenCommandId = commandId;
    _directTextTokenCommandSha256 = staged.sha256;
  }

  Future<void> _waitForDirectTextTokenProofReceipt() async {
    final commandId = _directTextTokenCommandId;
    final commandSha256 = _directTextTokenCommandSha256;
    if (commandId == null || commandSha256 == null) {
      throw _CampaignFailure(_stage, 'Token proof command was not staged.');
    }
    await _revalidateGateAAuthorization('receipt_wait_start');
    final raw = await _waitForValue(
      'current Firebase token SHA-256 receipt',
      const Duration(minutes: 2),
      () => _readAppFile(recipientId, 'intro_e2e_result.json'),
    );
    await _requireRunAsFileMode(
      recipientId,
      directTextRelayTokenProofReceiptPath,
      '600',
    );
    // The wait above is intentionally bounded but can still consume most of
    // Gate A v2's validity window. Re-parse the same immutable bytes at the
    // acceptance boundary so an artifact that expired during the wait can
    // never authorize the downstream proof.
    final authorization = await _revalidateGateAAuthorization(
      'receipt_acceptance',
    );
    try {
      _directTextTokenReceipt = parseDirectTextRelayTokenProofReceiptV2(
        utf8.encode(raw),
        now: DateTime.now().toUtc(),
        commandId: commandId,
        commandSha256: commandSha256,
        tokenSha256: authorization['tokenSha256']! as String,
        authorizationKind: authorization['authorizationKind']! as String,
        authorizationArtifactSha256:
            authorization['authorizationArtifactSha256']! as String,
        gateACommandGenerationId:
            authorization['gateACommandGenerationId']! as String,
        gateAArtifactSha256: authorization['gateAArtifactSha256']! as String,
        accountIdentitySha256:
            authorization['accountIdentitySha256']! as String,
        transportIdentitySha256:
            authorization['transportIdentitySha256']! as String,
      );
    } on Object {
      throw _CampaignFailure(_stage, 'Current Firebase token proof rejected.');
    }
    await _adbShell(recipientId, <String>[
      'run-as',
      appPackage,
      'test',
      '!',
      '-e',
      directTextRelayTokenProofCommandPath,
    ]);
    await _removeAndVerifyDirectTextTokenProofFiles();
  }

  Future<BackgroundCryptoTransportResult> _runDirectTextPrivateFileTransport(
    BackgroundCryptoTransportInvocation invocation,
  ) async {
    final _CommandOutput output = switch (invocation.channel) {
      BackgroundCryptoTransportChannel.adb => await _adb(
        recipientId,
        invocation.arguments,
        allowFail: true,
      ),
      BackgroundCryptoTransportChannel.shell => await _adb(
        recipientId,
        <String>['shell', ...invocation.arguments],
        allowFail: true,
      ),
      BackgroundCryptoTransportChannel.runAs => await _adb(
        recipientId,
        <String>['shell', 'run-as', appPackage, ...invocation.arguments],
        allowFail: true,
      ),
    };
    return BackgroundCryptoTransportResult(
      exitCode: output.exitCode,
      stdout: output.stdout,
      stderr: output.stderr,
    );
  }

  Future<void> _requireRunAsFileMode(
    String deviceId,
    String path,
    String expected,
  ) async {
    final result = await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'stat',
      '-c',
      '%a',
      path,
    ]);
    if (result.trim() != expected) {
      throw _CampaignFailure(_stage, 'App-private proof file mode rejected.');
    }
  }

  Future<void> _removeAndVerifyDirectTextTokenProofFiles() async {
    for (final path in const <String>[
      directTextRelayTokenProofCommandPath,
      directTextRelayTokenProofReceiptPath,
      directTextRelayTokenProofReceiptTempPath,
    ]) {
      await _adbShell(recipientId, <String>[
        'run-as',
        appPackage,
        'rm',
        '-f',
        path,
      ]);
      await _adbShell(recipientId, <String>[
        'run-as',
        appPackage,
        'test',
        '!',
        '-e',
        path,
      ]);
    }
  }

  Future<void> _requireCleanNotificationSlate() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final dump = await _notificationDump(recipientId);
    final cards = extractActiveNotificationCards(dump, packageName: appPackage);
    if (cards.isNotEmpty) {
      throw _CampaignFailure(
        _stage,
        'Recipient starts with ${cards.length} active app notification(s); '
        'TC-00 requires a clean slate and will not cancel unrelated cards.',
      );
    }
  }

  /// Stops the just-unregistered recipient before Android background work can
  /// restart the process and register a fresh push route. Unlike force-stop,
  /// `stop-app` preserves normal push eligibility, so the following relay
  /// metric probe still detects any route that was actually left behind.
  Future<void> _stopRecipientAfterRouteUnregister() async {
    await _adbShell(recipientId, ['input', 'keyevent', 'KEYCODE_HOME']);
    await _adbShell(recipientId, [
      'cmd',
      'activity',
      'stop-app',
      appPackage,
    ]);
    await _waitForProcessAndActivityAbsent(recipientId);
  }

  Future<void> _terminateRecipient() async {
    await _adbShell(recipientId, ['input', 'keyevent', 'KEYCODE_HOME']);
    await Future<void>.delayed(const Duration(seconds: 1));
    await _adbShell(recipientId, ['am', 'kill', appPackage]);
    if (!await _recipientProcessAndActivityAbsentWithin(
      const Duration(seconds: 5),
    )) {
      await _adbShell(recipientId, ['cmd', 'activity', 'stop-app', appPackage]);
    }
    await _waitForProcessAndActivityAbsent(recipientId);
  }

  /// Sends the recipient to the background WITHOUT killing it, then proves the
  /// process survived. A recipient that died here would silently turn this leg
  /// back into the killed-path leg, whose durable arm cannot resolve at all.
  Future<void> _backgroundRecipient() async {
    await _adbShell(recipientId, ['input', 'keyevent', 'KEYCODE_HOME']);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!await _recipientProcessAliveAndBackgroundedWithin(
      const Duration(seconds: 15),
    )) {
      throw _CampaignFailure(
        _stage,
        'The recipient app is not alive-and-backgrounded after HOME; the '
        'durable arm requires a live runtime that has projected the event.',
      );
    }
  }

  Future<bool> _recipientProcessAliveAndBackgroundedWithin(
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final pid = (await _adbShell(recipientId, <String>[
        'pidof',
        appPackage,
      ], allowFail: true)).trim();
      final activities = await _adbShell(recipientId, <String>[
        'dumpsys',
        'activity',
        'activities',
      ]);
      if (isAndroidAppProcessAliveAndBackgrounded(
        pidOutput: pid,
        dumpsysActivities: activities,
        packageName: appPackage,
      )) {
        return true;
      }
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Polls the recipient's own log for the DURABLE direct-reaction show, and
  /// returns whatever it last observed when the window closes so the failure
  /// can name the deferral reason instead of just timing out.
  Future<AndroidDurableDirectReactionShow>
  _recipientDurableDirectReactionShowWithin(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    var observed = AndroidDurableDirectReactionShow.nothingObserved;
    while (true) {
      // Accumulated, not snapshotted: a live recipient fills the ring fast
      // enough that a single late read can miss what an earlier poll saw.
      observed = observed.mergedWith(
        androidDurableDirectReactionShow(
          (await _adb(recipientId, ['logcat', '-d', '-v', 'brief'])).stdout,
        ),
      );
      if (observed.durableArmExecuted) return observed;
      if (!DateTime.now().isBefore(deadline)) return observed;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<bool> _recipientProcessAndActivityAbsentWithin(
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        await _requireProcessAndActivityAbsent(recipientId);
        return true;
      } on _CampaignFailure {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    return false;
  }

  Future<String> _waitForReactionSuccess() async {
    return _waitForValue(
      'REACTION_SEND_SUCCESS flow event',
      const Duration(seconds: 45),
      () async {
        final log = await _adb(senderId, ['logcat', '-d', '-v', 'brief']);
        return extractReactionSuccessId(log.stdout) == null ? null : log.stdout;
      },
    );
  }

  Future<String> _waitForRelayStore(DateTime since) async {
    return _waitForValue(
      'matched relay reaction store',
      const Duration(seconds: 60),
      () async {
        final log = await _relayJournalSince(since);
        final capture = classifyRelayCapture(
          log: log,
          senderPrefix: sender.peerPrefix,
          recipientPrefix: recipient.peerPrefix,
        );
        return capture.relayMatchedEvent ? log : null;
      },
    );
  }

  Future<void> _captureFixedWakeRecovery({
    required _RelayInfo relayInfo,
    required String firstMarker,
    required String firstMessageId,
    required String secondMarker,
    required String secondMessageId,
  }) async {
    final build = _build;
    if (!fixedWakeRecovery ||
        build == null ||
        build.buildProfile != _fixedWakeRecoveryBuildProfile ||
        build.childBuildCount != 0 ||
        !statePreparedByParent) {
      throw _CampaignFailure(
        _stage,
        'Fixed-wake recovery requires the central fixed cohort and zero child builds.',
      );
    }
    if (!await _recipientProcessAliveAndBackgroundedWithin(
      const Duration(seconds: 5),
    )) {
      throw _CampaignFailure(
        _stage,
        'Transition A did not start with an alive/backgrounded receiver.',
      );
    }

    final routeBeforeA = await _fixedRouteSnapshot('route-before-a');
    final windowA = await _captureFixedWakeWindow(
      stem: 'transition-a',
      marker: firstMarker,
      routeBefore: routeBeforeA,
      requireBarrier: false,
    );
    final completionA = await _waitForFixedWakeCompletion(
      stem: 'transition-a',
      generation: windowA.generation,
      requireHeadlessWorker: false,
    );
    await _launch(recipientId);
    await _openConversation(recipient, sender.username);
    await _waitForZeroAppCards('transition A exact-chat retirement');
    final transitionAActivation =
        File(
          '${artifactDir.path}/transition-a-exact-chat-retirement.json',
        )..writeAsStringSync(
          '${jsonEncode(<String, Object?>{'programmaticExactChatActivation': true, 'notificationCardTapCount': 0, 'canonicalNotificationId': completionA.canonicalCard.id, 'genericCardId': 329, 'postActivationAppCardCount': 0, 'generation': windowA.generation})}\n',
          flush: true,
        );

    // Transition B must start only after A has fully converged and cleared.
    await _backgroundRecipient();
    await _waitForZeroAppCards('transition A convergence before B');
    final baselineRecoveryJobs = await _registeredRecoveryJobIds();
    final jobBaselineEvidence = File(
      '${artifactDir.path}/transition-b-jobscheduler-baseline.txt',
    )..writeAsStringSync('${await _jobschedulerDump()}\n', flush: true);
    final barrierReceipt = await _armFixedWakeBarrier();
    await _terminateRecipient();
    final processAbsentBeforeB = await _recipientProcessAndActivityAbsentWithin(
      const Duration(seconds: 5),
    );
    if (!processAbsentBeforeB) {
      throw _CampaignFailure(
        _stage,
        'Transition B receiver was not process/activity absent before send.',
      );
    }

    final routeBeforeB = await _fixedRouteSnapshot('route-before-b');
    final windowB = await _captureFixedWakeWindow(
      stem: 'transition-b',
      marker: secondMarker,
      routeBefore: routeBeforeB,
      requireBarrier: true,
    );
    final firstWorkerPid = windowB.firstWorkerPid;
    if (firstWorkerPid == null) {
      throw _CampaignFailure(
        _stage,
        'Transition B did not bind the first barrier-held worker PID.',
      );
    }
    await _killBarrierHeldWorker(firstWorkerPid);
    final completionB = await _waitForFixedWakeCompletion(
      stem: 'transition-b',
      generation: windowB.generation,
      requireHeadlessWorker: true,
      firstWorkerPid: firstWorkerPid,
      baselineRecoveryJobs: baselineRecoveryJobs,
    );

    if (windowA.reactionId == windowB.reactionId ||
        windowA.generation == windowB.generation ||
        firstMessageId == secondMessageId) {
      throw _CampaignFailure(
        _stage,
        'Transition B reused transition A reaction, generation, or target.',
      );
    }

    // Clear the final exact card without tapping it, then authenticate removal
    // of the fresh recipient route while that identity is still active.
    await _launch(recipientId);
    await _openConversation(recipient, sender.username);
    await _waitForZeroAppCards('transition B exact-chat retirement');
    final unregisterReceipt = await _runNotificationPayloadAction(
      'notification_unregister_push',
    );
    if (unregisterReceipt['unregistered'] != true ||
        unregisterReceipt['success'] != true) {
      throw _CampaignFailure(
        _stage,
        'Authenticated ephemeral push-route unregister was not acknowledged.',
      );
    }
    final unregisterEvidence =
        File(
          '${artifactDir.path}/recipient-route-unregister.json',
        )..writeAsStringSync(
          '${jsonEncode(<String, Object?>{'schema': unregisterReceipt['schema'], 'transport_action': unregisterReceipt['transport_action'], 'scenario': unregisterReceipt['scenario'], 'status': unregisterReceipt['status'], 'success': unregisterReceipt['success'], 'unregistered': unregisterReceipt['unregistered'], 'authenticatedMainAppAction': true})}\n',
          flush: true,
        );
    await _stopRecipientAfterRouteUnregister();
    // Both transition targets already carry the same reaction used by this
    // campaign. Reusing either one would toggle that reaction off and emit
    // REACTION_REMOVE_SUCCESS, which cannot prove a fresh post-unregister
    // relay store. Seed a third, unreacted target while the recipient and its
    // authenticated push route are absent, then react to that exact target.
    final routeAbsenceMarker =
        'TC393RX-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    await _sendUiMessageFromSender(routeAbsenceMarker);
    final routeAbsence = await _captureRouteAbsenceProbe(routeAbsenceMarker);
    await _waitForZeroAppCards('post-unregister campaign baseline');

    final artifact = <String, Object?>{
      'schema': 'mknoon.plan393.android-fixed-wake-recovery-raw.v1',
      'version': 1,
      'scenario': _fixedWakeRecoveryScenario,
      'status': 'passed',
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'buildProfile': _fixedWakeRecoveryBuildProfile,
      'buildCapability': 'build.android.production_fcm.fixed_wake',
      'preparedArtifactSha256': build.normalApkSha256,
      'appPackage': appPackage,
      'topology': <String, Object?>{
        'sender': <String, Object?>{
          'deviceId': senderId,
          'kind': 'physical',
          'role': 'sender',
        },
        'receiver': <String, Object?>{
          'deviceId': recipientId,
          'kind': 'emulator',
          'role': 'receiver',
        },
      },
      'relay': <String, Object?>{
        'revision': relayInfo.version,
        'sha256': relayInfo.sha256,
        'selectedRouteCounter': _relaySelectedRouteCounter,
        'executionBoundary': relayInfo.executionBoundary,
        'backend': relayInfo.backend,
        'pushTokenState': relayInfo.pushTokenState,
        'wakeOutcomeLedger': relayInfo.wakeOutcomeLedger,
        'provider': relayInfo.provider,
      },
      'transitionA': _fixedTransitionJson(
        lifecycle: 'alive_backgrounded',
        marker: firstMarker,
        messageId: firstMessageId,
        window: windowA,
        completion: completionA,
        routeBefore: routeBeforeA,
        exactChatActivation: _evidenceReference(transitionAActivation),
      ),
      'transitionB': <String, Object?>{
        ..._fixedTransitionJson(
          lifecycle: 'killed',
          marker: secondMarker,
          messageId: secondMessageId,
          window: windowB,
          completion: completionB,
          routeBefore: routeBeforeB,
        ),
        'processAbsentBeforeSend': processAbsentBeforeB,
        'barrierArmReceipt': barrierReceipt,
        'firstWorkerPid': firstWorkerPid,
        'resumedWorkerPid': completionB.workerCompletion!['pid'],
        'runAttemptCount': completionB.workerCompletion!['runAttemptCount'],
        'terminalOutcome': completionB.workerCompletion!['outcome'],
        'jobSchedulerBaseline': _evidenceReference(jobBaselineEvidence),
        'jobSchedulerAudit': _evidenceReference(completionB.jobSchedulerAudit!),
      },
      'cleanup': <String, Object?>{
        'authenticatedRouteUnregister': true,
        'unregisterReceipt': _evidenceReference(unregisterEvidence),
        'routeAbsentReadback': true,
        'absenceProbeReactionIdSha256': routeAbsence['reactionIdSha256'],
        'absenceProbeRouteBefore': routeAbsence['routeBefore'],
        'absenceProbeRouteAfter': routeAbsence['routeAfter'],
        'absenceProbeRelayJournal': routeAbsence['relayJournal'],
        'postCampaignAppCardCount': 0,
        'localStateRestorationOwnedByParent': true,
      },
      'automation': <String, Object?>{
        'manualUserTaps': 0,
        'notificationCardTaps': 0,
        'childBuildCount': 0,
        'mainActivityLaunchesDuringKilledRecovery': 0,
        'productionIngressInjectionCount': 0,
        'statePreparedByParent': true,
      },
      'assertions': const <String>[
        'notifications.fixed_wake_live_route_selected',
        'notifications.direct_reaction_canonical_recovery',
        'notifications.generic_recovery_card_retired',
        'notifications.no_duplicate_or_second_tone',
        'notifications.state_and_route_restored',
        'notifications.zero_taps_zero_child_builds',
      ],
      'oldAssertionDisposition': _plan393RecoveryAssertionDisposition,
      'redaction': const <String, Object?>{
        'providerTokensPersisted': false,
        'privateKeysPersisted': false,
        'rawPeerIdsPersisted': false,
        'messagePlaintextPersisted': false,
      },
    };
    File('${artifactDir.path}/$_artifactStem.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(artifact)}\n',
      flush: true,
    );
  }

  Map<String, Object?> _fixedTransitionJson({
    required String lifecycle,
    required String marker,
    required String messageId,
    required _FixedWakeWindow window,
    required _FixedWakeCompletion completion,
    required _RelayRouteSnapshot routeBefore,
    Map<String, Object?>? exactChatActivation,
  }) => <String, Object?>{
    'lifecycle': lifecycle,
    'targetMarkerSha256': sha256.convert(utf8.encode(marker)).toString(),
    'targetMessageIdSha256': sha256.convert(utf8.encode(messageId)).toString(),
    'reactionIdSha256': sha256
        .convert(utf8.encode(window.reactionId))
        .toString(),
    'recoveryGeneration': window.generation,
    'routeBefore': _routeJson(routeBefore),
    'routeAfter': _routeJson(window.routeAfter),
    'opaqueRouteDelta': window.routeAfter.opaque - routeBefore.opaque,
    'richRouteDelta': window.routeAfter.rich - routeBefore.rich,
    'productionFixedWakeIngress': window.ingress,
    'genericCard': const <String, Object?>{
      'tag': 'mknoon_dropped_push_recovery',
      'id': 329,
      'observed': true,
      'requestedSilent': true,
    },
    'canonicalCard': <String, Object?>{
      'id': completion.canonicalCard.id,
      'titleSha256': sha256
          .convert(utf8.encode(completion.canonicalCard.title))
          .toString(),
      'bodySha256': sha256
          .convert(utf8.encode(completion.canonicalCard.body))
          .toString(),
      'producer': 'direct_reaction',
      'sourceCustody': 'SQL_READY',
      'presentationOwner': 'INBOX_RECONCILER',
      'effectPhase': 'SETTLED',
      'settlement': completion.settlement,
      'requestedSilent': completion.directShow['silent'],
    },
    'genericCardRetiredAfterCanonical': true,
    'exactMarkerAcknowledgement': completion.acknowledgement,
    'duplicateCanonicalShowCount': 0,
    'requestedToneCount': 1,
    'richFlutterFireCallbackCount': 0,
    'notificationSnapshots': <Map<String, Object?>>[
      _evidenceReference(window.notificationSnapshots),
      _evidenceReference(completion.notificationSnapshots),
    ],
    'runtimeEvidence': <Map<String, Object?>>[
      _evidenceReference(window.runtimeLog),
      _evidenceReference(completion.runtimeLog),
    ],
    'relayJournal': _evidenceReference(window.relayJournal),
    'exactChatActivation': ?exactChatActivation,
  };

  Future<_FixedWakeWindow> _captureFixedWakeWindow({
    required String stem,
    required String marker,
    required _RelayRouteSnapshot routeBefore,
    required bool requireBarrier,
  }) async {
    await _adb(senderId, const <String>['logcat', '-c']);
    await _adb(recipientId, const <String>['logcat', '-c']);
    await _longPressText(senderId, marker);
    final windowStart = DateTime.now().toUtc();
    await _tapText(senderId, _reactionEmoji);

    String? reactionId;
    String relayJournal = '';
    var relayMatched = false;
    var genericObserved = false;
    int? generation;
    int? firstWorkerPid;
    Map<String, Object?>? ingress;
    var routeAfter = routeBefore;
    var iteration = 0;
    final snapshots = <Map<String, Object?>>[];
    String runtimeLog = '';
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      final senderLog = await _adb(senderId, const <String>[
        'logcat',
        '-d',
        '-v',
        'brief',
      ]);
      reactionId ??= extractReactionSuccessId(senderLog.stdout);
      final recipientLog = await _adb(recipientId, const <String>[
        'logcat',
        '-d',
        '-v',
        'brief',
      ]);
      runtimeLog = recipientLog.stdout;
      final dump = await _notificationDump(recipientId);
      final summary = _notificationSnapshot(dump);
      snapshots.add(<String, Object?>{
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        ...summary,
      });
      genericObserved =
          genericObserved || summary['genericCardPresent'] == true;

      final ingressEvents = _runtimeEvents(runtimeLog)
          .where((event) => event['event'] == 'plan393_fixed_wake_ingress')
          .toList(growable: false);
      if (ingressEvents.length > 1) {
        throw _CampaignFailure(
          _stage,
          '$stem observed more than one production fixed-wake ingress.',
        );
      }
      if (ingressEvents.length == 1) {
        final candidate = ingressEvents.single;
        final candidateGeneration = candidate['generation'];
        if (candidateGeneration is int && candidateGeneration > 0) {
          generation = candidateGeneration;
          ingress = candidate;
        }
      }
      if (requireBarrier && generation != null) {
        final held = _runtimeEvents(runtimeLog).where(
          (event) =>
              event['event'] == 'plan374_headless_worker' &&
              event['phase'] == 'process_death_barrier_consumed' &&
              event['generation'] == generation,
        );
        if (held.isNotEmpty && held.first['pid'] is int) {
          firstWorkerPid = held.first['pid']! as int;
        }
      }

      if (iteration % 4 == 0) {
        relayJournal = await _relayJournalSince(windowStart);
        relayMatched = classifyRelayCapture(
          log: relayJournal,
          senderPrefix: sender.peerPrefix,
          recipientPrefix: recipient.peerPrefix,
        ).relayMatchedEvent;
        routeAfter = await _fixedRouteSnapshot('$stem-route-after');
        final opaqueDelta = routeAfter.opaque - routeBefore.opaque;
        final richDelta = routeAfter.rich - routeBefore.rich;
        if (opaqueDelta > 1 || richDelta != 0) {
          throw _CampaignFailure(
            _stage,
            '$stem selected-route counter escaped the exact opaque +1/rich +0 window.',
          );
        }
      }

      final ingressExact =
          ingress != null &&
          ingress['triggerKind'] == 'FIXED_WAKE' &&
          ingress['genericMayHaveAlerted'] == false &&
          ingress['genericCardTag'] == 'mknoon_dropped_push_recovery' &&
          ingress['genericCardId'] == 329 &&
          ingress['genericCardRequestedSilent'] == true &&
          ingress['richFlutterFireDelegated'] == false &&
          ingress['productionIngressInvoked'] == true;
      final routeExact =
          routeAfter.opaque - routeBefore.opaque == 1 &&
          routeAfter.rich == routeBefore.rich;
      final barrierExact = !requireBarrier || firstWorkerPid != null;
      if (reactionId != null &&
          relayMatched &&
          routeExact &&
          genericObserved &&
          ingressExact &&
          barrierExact) {
        if (_containsRichFlutterFireCallback(runtimeLog)) {
          throw _CampaignFailure(
            _stage,
            '$stem substituted a rich FlutterFire callback for fixed ingress.',
          );
        }
        final runtimeEvidence = _writeRuntimeEvidence(
          '$stem-runtime-ingress.jsonl',
          runtimeLog,
        );
        final snapshotEvidence = _writeJsonEvidence(
          '$stem-notification-snapshots.json',
          <String, Object?>{'snapshots': snapshots},
        );
        final relayEvidence = _writeRelayEvidence(
          relayJournal,
          windowStart,
          filename: '$stem-relay-window.log',
        );
        return _FixedWakeWindow(
          reactionId: reactionId,
          generation: generation!,
          firstWorkerPid: firstWorkerPid,
          routeAfter: routeAfter,
          ingress: Map<String, Object?>.unmodifiable(ingress),
          notificationSnapshots: snapshotEvidence,
          runtimeLog: runtimeEvidence,
          relayJournal: relayEvidence,
        );
      }
      iteration += 1;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final timeoutIngressExact =
        ingress != null &&
        ingress['triggerKind'] == 'FIXED_WAKE' &&
        ingress['genericMayHaveAlerted'] == false &&
        ingress['genericCardTag'] == 'mknoon_dropped_push_recovery' &&
        ingress['genericCardId'] == 329 &&
        ingress['genericCardRequestedSilent'] == true &&
        ingress['richFlutterFireDelegated'] == false &&
        ingress['productionIngressInvoked'] == true;
    _writeRuntimeEvidence('$stem-timeout-runtime.jsonl', runtimeLog);
    _writeJsonEvidence('$stem-timeout-notification-snapshots.json', {
      'snapshots': snapshots,
    });
    _writeJsonEvidence('$stem-timeout-diagnostics.json', {
      'schema': 'mknoon.plan393.fixed-wake-timeout.v1',
      'reactionSuccessObserved': reactionId != null,
      'relayStoreObserved': relayMatched,
      'opaqueRouteDelta': routeAfter.opaque - routeBefore.opaque,
      'richRouteDelta': routeAfter.rich - routeBefore.rich,
      'genericCardObserved': genericObserved,
      'fixedIngressObserved': ingress != null,
      'fixedIngressExact': timeoutIngressExact,
      'barrierSatisfied': !requireBarrier || firstWorkerPid != null,
      'richFlutterFireObserved': _containsRichFlutterFireCallback(runtimeLog),
      'notificationSnapshotCount': snapshots.length,
    });
    throw _CampaignFailure(
      _stage,
      '$stem did not converge through reaction/store/opaque ingress/generic card.',
    );
  }

  Future<_FixedWakeCompletion> _waitForFixedWakeCompletion({
    required String stem,
    required int generation,
    required bool requireHeadlessWorker,
    int? firstWorkerPid,
    Set<int> baselineRecoveryJobs = const <int>{},
  }) async {
    final snapshots = <Map<String, Object?>>[];
    String runtimeLog = '';
    final forcedKeys = <String>{};
    final deferredForceKeys = <String>{};
    final retryObservedAt = <int, DateTime>{};
    final forceAudit = StringBuffer();
    var latestRetryAttempt = -1;
    final deadline = DateTime.now().add(
      requireHeadlessWorker
          ? const Duration(minutes: 5)
          : const Duration(minutes: 2),
    );
    while (DateTime.now().isBefore(deadline)) {
      runtimeLog = (await _adb(recipientId, const <String>[
        'logcat',
        '-d',
        '-v',
        'brief',
      ])).stdout;
      if (_containsRichFlutterFireCallback(runtimeLog)) {
        throw _CampaignFailure(
          _stage,
          '$stem entered the forbidden rich FlutterFire callback.',
        );
      }
      final events = _runtimeEvents(runtimeLog);
      final acknowledgements = events
          .where(
            (event) =>
                event['event'] == 'plan393_recovery_generation_acknowledged' &&
                event['generation'] == generation &&
                event['genericCardId'] == 329 &&
                event['genericCardRetired'] == true,
          )
          .toList(growable: false);
      final directShows = events
          .where((event) {
            if (event['event'] != 'NOTIFICATION_SHOWN') return false;
            final details = event['details'];
            return details is Map &&
                details['durable'] == true &&
                details['producer'] == 'direct_reaction' &&
                details['disposition'] == 'osPosted';
          })
          .toList(growable: false);
      final settlements = events
          .where((event) {
            if (event['event'] != 'DIRECT_NOTIFICATION_DURABLE_SETTLED') {
              return false;
            }
            final details = event['details'];
            return details is Map &&
                details['sourceCustody'] == 'SQL_READY' &&
                details['presentationOwner'] == 'INBOX_RECONCILER' &&
                details['effectPhase'] == 'SETTLED' &&
                details['presentationState'] == 'OS_POSTED';
          })
          .toList(growable: false);
      if (acknowledgements.length > 1 || directShows.length > 1) {
        throw _CampaignFailure(
          _stage,
          '$stem observed duplicate marker ACK or canonical notification show.',
        );
      }
      final workerCompletions = events
          .where(
            (event) =>
                event['event'] == 'plan374_headless_worker' &&
                event['phase'] == 'completion' &&
                event['generation'] == generation,
          )
          .toList(growable: false);
      for (final event in workerCompletions) {
        if (event['outcome'] == 'RETRY' && event['runAttemptCount'] is int) {
          final attempt = event['runAttemptCount']! as int;
          retryObservedAt.putIfAbsent(attempt, DateTime.now);
          latestRetryAttempt = max(latestRetryAttempt, attempt);
        }
      }
      final successfulWorkers = workerCompletions
          .where(
            (event) =>
                event['outcome'] == 'SUCCESS' &&
                event['pid'] is int &&
                event['runAttemptCount'] is int &&
                (event['runAttemptCount']! as int) >= 1 &&
                event['pid'] != firstWorkerPid,
          )
          .toList(growable: false);
      if (successfulWorkers.length > 1) {
        throw _CampaignFailure(
          _stage,
          '$stem observed multiple resumed WorkManager SUCCESS completions.',
        );
      }
      final worker = successfulWorkers.isEmpty
          ? null
          : successfulWorkers.single;
      final workerPid = worker?['pid'];
      final engineCompletions = events
          .where(
            (event) =>
                event['event'] == 'plan374_headless_engine' &&
                event['phase'] == 'dart_completion' &&
                event['pid'] == workerPid &&
                event['disposition'] == 'SUCCEEDED' &&
                event['databaseClosed'] == true &&
                event['leaseReleased'] == true,
          )
          .toList(growable: false);

      final dump = await _notificationDump(recipientId);
      final summary = _notificationSnapshot(dump);
      snapshots.add(<String, Object?>{
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        ...summary,
      });
      final contentCards = extractActiveContentNotificationCards(
        dump,
        packageName: appPackage,
      ).where((card) => card.id != 329 && card.id != 330).toList();
      ActiveNotificationCard? canonical;
      if (contentCards.length == 1) {
        final errors = validateDirectReactionNotificationCard(
          contentCards.single,
          expectedTitle: sender.username,
          emoji: _reactionEmoji,
        );
        if (errors.isEmpty) canonical = contentCards.single;
      } else if (contentCards.length > 1) {
        final diagnostic = File(
          '${artifactDir.path}/$stem-unexpected-content-notifications.txt',
        )..writeAsStringSync(dump, flush: true);
        final ids = contentCards
            .map((card) => card.id?.toString() ?? 'null')
            .join(',');
        throw _CampaignFailure(
          _stage,
          '$stem has ${contentCards.length} canonical content cards '
          '(ids=$ids; diagnostic=${diagnostic.path}).',
        );
      }

      final ack = acknowledgements.isEmpty ? null : acknowledgements.single;
      final show = directShows.isEmpty ? null : directShows.single;
      final showDetails = show?['details'];
      final exactShow = showDetails is Map && showDetails['silent'] == false;
      // SQL-B recovery may idempotently replay the durable ledger settlement
      // after the one OS post. That replay is not a duplicate notification;
      // the one-show and one-ACK checks above remain the alerting boundary.
      final exactSettlement = settlements.isNotEmpty;
      final exactAck =
          ack != null &&
          (!requireHeadlessWorker ||
              (ack['owner'] == 'headless' && ack['pid'] == workerPid));
      final workerExact =
          !requireHeadlessWorker ||
          (worker != null && engineCompletions.length == 1);
      final cardExact =
          canonical != null &&
          summary['genericCardPresent'] == false &&
          summary['workerCardPresent'] == false;
      if (exactShow &&
          exactSettlement &&
          exactAck &&
          workerExact &&
          cardExact) {
        final runtimeEvidence = _writeRuntimeEvidence(
          '$stem-runtime-completion.jsonl',
          runtimeLog,
        );
        final snapshotEvidence = _writeJsonEvidence(
          '$stem-notification-completion.json',
          <String, Object?>{'snapshots': snapshots},
        );
        final jobAudit = requireHeadlessWorker
            ? (File('${artifactDir.path}/$stem-jobscheduler-resume.log')
                ..writeAsStringSync(forceAudit.toString(), flush: true))
            : null;
        return _FixedWakeCompletion(
          canonicalCard: canonical,
          acknowledgement: Map<String, Object?>.unmodifiable(ack),
          directShow: Map<String, Object?>.unmodifiable(
            showDetails.map<String, Object?>(
              (key, value) => MapEntry('$key', value),
            ),
          ),
          settlement: Map<String, Object?>.unmodifiable(
            (settlements.first['details']! as Map).map<String, Object?>(
              (key, value) => MapEntry('$key', value),
            ),
          ),
          workerCompletion: worker == null
              ? null
              : Map<String, Object?>.unmodifiable(worker),
          workerEngineCompletion: engineCompletions.isEmpty
              ? null
              : Map<String, Object?>.unmodifiable(engineCompletions.single),
          runtimeLog: runtimeEvidence,
          notificationSnapshots: snapshotEvidence,
          jobSchedulerAudit: jobAudit,
        );
      }

      if (requireHeadlessWorker && worker == null) {
        final currentJobs = await _registeredRecoveryJobIds();
        final incumbent = currentJobs.difference(baselineRecoveryJobs);
        if (incumbent.length > 1) {
          throw _CampaignFailure(
            _stage,
            'Multiple non-baseline recovery jobs make forcing ambiguous.',
          );
        }
        if (incumbent.length == 1) {
          final jobId = incumbent.single;
          final forceKey = '$latestRetryAttempt';
          if (!forcedKeys.contains(forceKey)) {
            final retryAge = latestRetryAttempt < 0
                ? const Duration(days: 1)
                : DateTime.now().difference(
                    retryObservedAt[latestRetryAttempt] ?? DateTime.now(),
                  );
            if (retryAge < const Duration(seconds: 31)) {
              if (deferredForceKeys.add(forceKey)) {
                forceAudit.writeln(
                  'jobId=$jobId retry=$latestRetryAttempt '
                  'result=awaiting_workmanager_backoff',
                );
              }
              await Future<void>.delayed(const Duration(milliseconds: 500));
              continue;
            }
            final state = await _adbShell(recipientId, <String>[
              'cmd',
              'jobscheduler',
              'get-job-state',
              '-n',
              'androidx.work.systemjobscheduler',
              appPackage,
              '$jobId',
            ], allowFail: true);
            final unsafe = <String>[
              'active',
              'user-stopped',
              'backing-up',
              'no-component',
            ].any(state.contains);
            var forceResult = 'not_forced';
            if (!unsafe) {
              // Spend this attempt only when Android will receive a force-run.
              // An active predecessor can become runnable after its PID dies.
              forcedKeys.add(forceKey);
              final result = await _adb(recipientId, <String>[
                'shell',
                'cmd',
                'jobscheduler',
                'run',
                '-f',
                '-n',
                'androidx.work.systemjobscheduler',
                appPackage,
                '$jobId',
              ], allowFail: true);
              forceResult = result.exitCode == 0 ? 'forced' : 'force_race';
            }
            forceAudit.writeln(
              'jobId=$jobId retry=$latestRetryAttempt state=${state.trim()} result=$forceResult',
            );
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw _CampaignFailure(
      _stage,
      '$stem did not reach canonical show, exact marker ACK, card retirement, and worker success.',
    );
  }

  Future<void> _killBarrierHeldWorker(int firstPid) async {
    final result = await _adb(recipientId, <String>[
      'shell',
      'run-as',
      appPackage,
      'kill',
      '-9',
      '$firstPid',
    ], allowFail: true);
    if (result.exitCode != 0) {
      throw _CampaignFailure(
        _stage,
        'The pinned package-UID process-death cut failed.',
      );
    }
    await _waitFor(
      'barrier-held worker PID termination',
      const Duration(seconds: 10),
      () async {
        final pids = (await _adbShell(recipientId, <String>[
          'pidof',
          appPackage,
        ], allowFail: true)).split(RegExp(r'\s+'));
        return !pids.contains('$firstPid');
      },
    );
  }

  Future<Map<String, Object?>> _armFixedWakeBarrier() async {
    final nonce =
        'plan393-${DateTime.now().toUtc().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(0x7fffffff)}';
    final result = await _adb(recipientId, <String>[
      'shell',
      'am',
      'broadcast',
      '-W',
      '--receiver-foreground',
      '-a',
      'com.mknoon.app.debug.CANONICAL_RUNTIME_H0_PROBE',
      '-n',
      '$appPackage/com.mknoon.app.CanonicalRuntimeH0ProbeReceiver',
      '--es',
      'plan374Phase',
      'arm-fixed-wake',
      '--es',
      'runNonce',
      nonce,
    ], allowFail: true);
    if (result.exitCode != 0) {
      throw _CampaignFailure(
        _stage,
        'The arm-only fixed-wake broadcast failed.',
      );
    }
    final raw = await _waitForValue<String>(
      'arm-only fixed-wake receipt',
      const Duration(seconds: 20),
      () async {
        final output = await _adb(recipientId, <String>[
          'shell',
          'run-as',
          appPackage,
          'cat',
          'files/plan374-headless-recovery/arm-fixed-wake-latest.json',
        ], allowFail: true);
        return output.exitCode == 0 && output.stdout.trim().isNotEmpty
            ? output.stdout.trim()
            : null;
      },
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['status'] != 'PASS' ||
        decoded['phase'] != 'arm-fixed-wake' ||
        decoded['runNonce'] != nonce ||
        decoded['processDeathBarrierArmed'] != true ||
        decoded['productionIngressInvoked'] != false ||
        decoded['pendingGenerationBefore'] != null ||
        decoded['pendingGenerationAfter'] != null ||
        decoded['mainActivityLaunchCount'] != 0) {
      throw _CampaignFailure(
        _stage,
        'The arm-only receipt could inject ingress or carried stale recovery.',
      );
    }
    return <String, Object?>{
      'status': 'PASS',
      'phase': 'arm-fixed-wake',
      'processDeathBarrierArmed': true,
      'productionIngressInvoked': false,
      'pendingGenerationBefore': null,
      'pendingGenerationAfter': null,
      'mainActivityLaunchCount': 0,
      'receiptSha256': sha256.convert(utf8.encode(raw)).toString(),
    };
  }

  Future<Map<String, Object?>> _runNotificationPayloadAction(
    String action,
  ) async {
    final runId =
        'plan393-${DateTime.now().toUtc().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(0x7fffffff)}';
    final stepId = 'notification-$action-$runId';
    await _deleteAppFile(recipientId, 'intro_e2e_result.json');
    await _writeAppFile(
      recipientId,
      'intro_e2e_config.json',
      jsonEncode(<String, Object?>{
        'schema': 'mknoon.plan258.android-notification-request.v1',
        'scenario': 'notifications.android_payload_campaign',
        'transport_action': action,
        'runId': runId,
        'stepId': stepId,
        'nonce':
            'n-${DateTime.now().toUtc().microsecondsSinceEpoch}-'
            '${Random.secure().nextInt(0x7fffffff)}',
        'timeoutMs': 120000,
      }),
    );
    await _launch(recipientId);
    final raw = await _waitForValue<String>(
      'authenticated notification action $action',
      const Duration(minutes: 2),
      () async {
        final candidate = await _readAppFile(
          recipientId,
          'intro_e2e_result.json',
        );
        if (candidate == null) return null;
        try {
          final decoded = jsonDecode(candidate);
          return decoded is Map &&
                  decoded['stepId'] == stepId &&
                  (decoded['status'] == 'complete' ||
                      decoded['status'] == 'failed')
              ? candidate
              : null;
        } on FormatException {
          return null;
        }
      },
    );
    await _deleteAppFile(recipientId, 'intro_e2e_config.json');
    await _deleteAppFile(recipientId, 'intro_e2e_result.json');
    final receipt = (jsonDecode(raw) as Map).map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    if (receipt['status'] != 'complete') {
      throw _CampaignFailure(
        _stage,
        'Authenticated notification action $action reported '
        '${receipt['errorType'] ?? 'failure'}.',
      );
    }
    return receipt;
  }

  Future<Map<String, Object?>> _captureRouteAbsenceProbe(String marker) async {
    if (!await _recipientProcessAndActivityAbsentWithin(
      const Duration(seconds: 5),
    )) {
      throw _CampaignFailure(
        _stage,
        'Recipient was not absent for route-absence readback.',
      );
    }
    await _adb(senderId, const <String>['logcat', '-c']);
    await _adb(recipientId, const <String>['logcat', '-c']);
    final before = await _fixedRouteSnapshot('route-absence-before');
    await _longPressText(senderId, marker);
    final windowStart = DateTime.now().toUtc();
    await _tapText(senderId, _reactionEmoji);
    final senderLog = await _waitForReactionSuccess();
    final reactionId = extractReactionSuccessId(senderLog);
    if (reactionId == null) {
      throw _CampaignFailure(_stage, 'Route-absence reaction has no event id.');
    }
    final journal = await _waitForRelayStore(windowStart);
    await Future<void>.delayed(const Duration(seconds: 15));
    final after = await _fixedRouteSnapshot('route-absence-after');
    if (after.opaque != before.opaque || after.rich != before.rich) {
      throw _CampaignFailure(
        _stage,
        'Authenticated unregister left a selected push route.',
      );
    }
    final recipientLog = (await _adb(recipientId, const <String>[
      'logcat',
      '-d',
      '-v',
      'brief',
    ])).stdout;
    if (recipientLog.contains('plan393_fixed_wake_ingress') ||
        (await _appCardCount()) != 0) {
      throw _CampaignFailure(
        _stage,
        'Route-absence probe still reached fixed ingress or posted a card.',
      );
    }
    final relayEvidence = _writeRelayEvidence(
      journal,
      windowStart,
      filename: 'route-absence-relay-window.log',
    );
    return <String, Object?>{
      'reactionIdSha256': sha256.convert(utf8.encode(reactionId)).toString(),
      'routeBefore': _routeJson(before),
      'routeAfter': _routeJson(after),
      'relayJournal': _evidenceReference(relayEvidence),
    };
  }

  Future<_RelayRouteSnapshot> _fixedRouteSnapshot(String stem) async {
    if (relayFixtureProbe != null) {
      final snapshot = await _relayFixtureSnapshot(
        DateTime.fromMillisecondsSinceEpoch(0),
      );
      final routes = snapshot['selectedRoutes']! as Map<String, Object?>;
      final opaque = routes['opaque']! as int;
      final rich = routes['rich']! as int;
      final processStart = snapshot['processStartTimeSeconds']! as num;
      final kept =
          '$_relaySelectedRouteCounter{route="opaque"} $opaque\n'
          '$_relaySelectedRouteCounter{route="rich"} $rich\n'
          'process_start_time_seconds $processStart';
      final evidence = File('${artifactDir.path}/$stem.metrics')
        ..writeAsStringSync('$kept\n', flush: true);
      return _RelayRouteSnapshot(
        opaque: opaque,
        rich: rich,
        evidence: evidence,
      );
    }
    final result = await _ssh(<String>[
      'curl',
      '-sS',
      '--max-time',
      '15',
      'http://127.0.0.1:2112/metrics',
    ]);
    if (result.exitCode != 0 ||
        !result.stdout.contains('process_start_time_seconds')) {
      throw _CampaignFailure(
        _stage,
        'The staging relay metrics endpoint is unreadable.',
        environmentBlocked: true,
      );
    }
    final kept = result.stdout
        .split('\n')
        .where(
          (line) =>
              line.startsWith(_relaySelectedRouteCounter) ||
              line.startsWith('process_start_time_seconds'),
        )
        .join('\n');
    final evidence = File('${artifactDir.path}/$stem.metrics')
      ..writeAsStringSync('$kept\n', flush: true);
    int value(String route) {
      final match = RegExp(
        '^${RegExp.escape(_relaySelectedRouteCounter)}\\{route="$route"\\}\\s+([^\\s]+)\\s*\$',
        multiLine: true,
      ).firstMatch(kept);
      if (match == null) return 0;
      final parsed = double.tryParse(match.group(1)!);
      if (parsed == null ||
          !parsed.isFinite ||
          parsed < 0 ||
          parsed != parsed.roundToDouble()) {
        throw _CampaignFailure(_stage, 'Selected-route counter is invalid.');
      }
      return parsed.toInt();
    }

    return _RelayRouteSnapshot(
      opaque: value('opaque'),
      rich: value('rich'),
      evidence: evidence,
    );
  }

  Map<String, Object?> _routeJson(_RelayRouteSnapshot value) =>
      <String, Object?>{
        'opaque': value.opaque,
        'rich': value.rich,
        'evidence': _evidenceReference(value.evidence),
      };

  Future<String> _jobschedulerDump() async =>
      _adbShell(recipientId, <String>['dumpsys', 'jobscheduler', appPackage]);

  Future<Set<int>> _registeredRecoveryJobIds() async {
    try {
      return parseAndroidCanonicalRecoveryJobIds(
        dump: await _jobschedulerDump(),
        appPackage: appPackage,
      );
    } on FormatException catch (error) {
      throw _CampaignFailure(_stage, error.message);
    }
  }

  Map<String, Object?> _notificationSnapshot(String dump) {
    final cards = extractActiveContentNotificationCards(
      dump,
      packageName: appPackage,
    );
    final records = _appNotificationRecords(dump);
    return <String, Object?>{
      'contentCardCount': cards.length,
      'ids': cards.map((card) => card.id).toList(growable: false),
      'cardDigests': cards
          .map(
            (card) => <String, Object?>{
              'id': card.id,
              'titleSha256': sha256.convert(utf8.encode(card.title)).toString(),
              'bodySha256': sha256.convert(utf8.encode(card.body)).toString(),
            },
          )
          .toList(growable: false),
      'genericCardPresent':
          RegExp(r'\bid=329\b').hasMatch(records) &&
          RegExp(r'\btag=mknoon_dropped_push_recovery\b').hasMatch(records),
      'workerCardPresent': RegExp(r'\bid=330\b').hasMatch(records),
    };
  }

  Future<int> _appCardCount() async => extractActiveContentNotificationCards(
    await _notificationDump(recipientId),
    packageName: appPackage,
  ).length;

  Future<void> _waitForZeroAppCards(String label) => _waitFor(
    label,
    const Duration(seconds: 45),
    () async => await _appCardCount() == 0,
  );

  List<Map<String, Object?>> _runtimeEvents(String logcat) {
    final result = <Map<String, Object?>>[];
    for (final line in logcat.split('\n')) {
      final open = line.indexOf('{');
      if (open < 0) continue;
      try {
        final decoded = jsonDecode(line.substring(open).trim());
        if (decoded is Map) {
          result.add(
            decoded.map<String, Object?>(
              (key, value) => MapEntry('$key', value),
            ),
          );
        }
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  bool _containsRichFlutterFireCallback(String logcat) => <String>[
    'PUSH_BACKGROUND_MESSAGE_RECEIVED',
    'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
    'PUSH_ANDROID_DATA_DECRYPT_OK',
  ].any(logcat.contains);

  File _writeRuntimeEvidence(String filename, String logcat) {
    final safe = _runtimeEvents(logcat)
        .where((event) {
          final name = event['event'];
          return name == 'plan393_fixed_wake_ingress' ||
              name == 'plan393_recovery_generation_acknowledged' ||
              name == 'plan374_headless_worker' ||
              name == 'plan374_headless_engine' ||
              name == 'NOTIFICATION_SHOWN' ||
              name == 'DIRECT_NOTIFICATION_DURABLE_SETTLED';
        })
        .map((event) {
          final name = event['event'];
          if (name == 'NOTIFICATION_SHOWN') {
            final details = event['details'];
            final values = details is Map
                ? details
                : const <Object?, Object?>{};
            return <String, Object?>{
              'event': name,
              'details': <String, Object?>{
                'durable': values['durable'],
                'producer': values['producer'],
                'disposition': values['disposition'],
                'nativeEntry': values['nativeEntry'],
                'silent': values['silent'],
              },
            };
          }
          return event;
        })
        .toList(growable: false);
    return File('${artifactDir.path}/$filename')
      ..writeAsStringSync("${safe.map(jsonEncode).join('\n')}\n", flush: true);
  }

  File _writeJsonEvidence(String filename, Map<String, Object?> value) =>
      File('${artifactDir.path}/$filename')
        ..writeAsStringSync('${jsonEncode(value)}\n', flush: true);

  Map<String, Object?> _evidenceReference(File file) {
    final bytes = file.readAsBytesSync();
    return <String, Object?>{
      'path': file.uri.pathSegments.last,
      'sha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
    };
  }

  Future<Map<String, Object?>> _captureFirstWakeProfileAot() async {
    if (!firstWakeProfileAot || _build == null) {
      throw _CampaignFailure(_stage, 'Profile-AOT capture was not prepared.');
    }
    final installedSha = await _installedApkSha256(recipientId);
    if (installedSha != _build!.normalApkSha256) {
      throw _CampaignFailure(
        _stage,
        'Installed profile receiver does not match the captured APK SHA-256.',
      );
    }
    final before = await _g21MeasurementInventory();
    if (!await _recipientProcessAndActivityAbsentWithin(
      const Duration(seconds: 5),
    )) {
      throw _CampaignFailure(
        _stage,
        'The warmed profile receiver was not killed before the direct send.',
      );
    }
    await _adb(recipientId, <String>['logcat', '-c']);
    final marker = 'TC393G21${DateTime.now().toUtc().microsecondsSinceEpoch}';
    await _sendUiMessageFromSender(marker);
    final captured = await _waitForSingleOrdinaryMessageCard(marker);
    final card = captured.$1;

    Set<String> after = before;
    if (measurementOnly) {
      after = await _waitForValue<Set<String>>(
        'one fresh G21 measurement receipt',
        const Duration(seconds: 20),
        () async {
          final inventory = await _g21MeasurementInventory();
          return inventory.difference(before).length == 1 ? inventory : null;
        },
      );
    } else {
      await Future<void>.delayed(const Duration(seconds: 2));
      after = await _g21MeasurementInventory();
      if (after.difference(before).isNotEmpty) {
        throw _CampaignFailure(
          _stage,
          'Production acceptance emitted a measurement-only receipt.',
        );
      }
    }

    Map<String, Object?>? receipt;
    String? receiptPath;
    String? receiptSha256;
    var selectedReserveMs = _g21FrozenProductionReserveMs;
    if (measurementOnly) {
      final name = after.difference(before).single;
      receipt = await _readG21MeasurementReceipt(name);
      final localReceipt = File(
        '${artifactDir.path}/android_first_wake_profile_aot_receipt.json',
      )..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(receipt));
      receiptPath = localReceipt.path;
      receiptSha256 = await _sha256(localReceipt);
      final remaining = _positiveReceiptInt(
        receipt,
        'remainingAtEligibilityStartMs',
      );
      final eligibility = _nonNegativeReceiptInt(
        receipt,
        'eligibilityElapsedMs',
      );
      final nativeTail = _nonNegativeReceiptInt(receipt, 'nativeEntryTailMs');
      selectedReserveMs = max(2000, nativeTail + 500);
      if (selectedReserveMs != _g21FrozenProductionReserveMs) {
        throw _CampaignFailure(
          _stage,
          'Measured reserve does not match the frozen production constant.',
        );
      }
      if (eligibility > remaining - selectedReserveMs) {
        throw _CampaignFailure(
          _stage,
          'Measured eligibility does not fit the remaining aggregate after '
          'the required downstream reserve.',
        );
      }
    }

    _writeSanitizedCardEvidence(
      'android_first_wake_profile_aot_card.txt',
      card,
    );
    await _dismissSingleNotification(card.title);
    await _requireCleanNotificationSlate();
    return <String, Object?>{
      'mode': measurementOnly ? 'measurement_only' : 'require_alert',
      'profileReceiverWarmed': true,
      'recipientProcessAbsentBeforeSend': true,
      'notificationCount': 1,
      'cardTitleSha256': sha256.convert(utf8.encode(card.title)).toString(),
      'cardBodySha256': sha256.convert(utf8.encode(card.body)).toString(),
      'cardId': card.id,
      'receiptInventoryBefore': before.toList()..sort(),
      'receiptInventoryAfter': after.toList()..sort(),
      'freshReceiptCount': after.difference(before).length,
      'receipt': receipt,
      'receiptPath': receiptPath,
      'receiptSha256': receiptSha256,
      'selectedProductionReserveMs': selectedReserveMs,
      'measurementFlagEnabled': measurementOnly,
      'measurementFlagAbsentInAcceptance': !measurementOnly,
      'cardStateClearedBeforeRestore': true,
    };
  }

  Future<Set<String>> _g21MeasurementInventory() async {
    const directory = 'files/BackgroundStorageLiveness';
    final listed = await _adbShell(recipientId, <String>[
      'run-as',
      appPackage,
      'ls',
      '-1',
      directory,
    ], allowFail: true);
    return listed
        .split('\n')
        .map((value) => value.trim())
        .where(
          (value) => RegExp(
            r'^g21-measurement-v1-[0-9]+-[0-9a-f]{8}-[0-9a-f]{8}-[0-9]+\.json$',
          ).hasMatch(value),
        )
        .toSet();
  }

  Future<Map<String, Object?>> _readG21MeasurementReceipt(String name) async {
    if (!RegExp(
      r'^g21-measurement-v1-[0-9]+-[0-9a-f]{8}-[0-9a-f]{8}-[0-9]+\.json$',
    ).hasMatch(name)) {
      throw _CampaignFailure(_stage, 'G21 receipt name is unsafe.');
    }
    final output = await _adb(recipientId, <String>[
      'exec-out',
      'run-as',
      appPackage,
      'cat',
      'files/BackgroundStorageLiveness/$name',
    ]);
    final decoded = jsonDecode(output.stdout);
    if (decoded is! Map<String, dynamic>) {
      throw _CampaignFailure(_stage, 'G21 receipt is not a JSON object.');
    }
    final receipt = Map<String, Object?>.from(decoded);
    const exactKeys = <String>{
      'schema',
      'kind',
      'measurementMode',
      'aggregateElapsedAtEligibilityStartMs',
      'remainingAtEligibilityStartMs',
      'eligibilityElapsedMs',
      'nativeEntryTailMs',
      'terminalOutcome',
      'buildMode',
      'engineRole',
    };
    if (receipt.keys.toSet().difference(exactKeys).isNotEmpty ||
        exactKeys.difference(receipt.keys.toSet()).isNotEmpty ||
        receipt['schema'] != 'mknoon.plan393.g21-measurement.v1' ||
        receipt['kind'] != 'direct_message' ||
        receipt['measurementMode'] != 'raw_aggregate_remainder' ||
        receipt['terminalOutcome'] != 'shown' ||
        receipt['buildMode'] != 'profile' ||
        receipt['engineRole'] != 'flutterfire_background') {
      throw _CampaignFailure(
        _stage,
        'G21 receipt fixed-domain contract was rejected.',
      );
    }
    _nonNegativeReceiptInt(receipt, 'aggregateElapsedAtEligibilityStartMs');
    _positiveReceiptInt(receipt, 'remainingAtEligibilityStartMs');
    _nonNegativeReceiptInt(receipt, 'eligibilityElapsedMs');
    _nonNegativeReceiptInt(receipt, 'nativeEntryTailMs');
    return receipt;
  }

  int _nonNegativeReceiptInt(Map<String, Object?> receipt, String key) {
    final value = int.tryParse(receipt[key]?.toString() ?? '');
    if (value == null || value < 0 || value > 8000) {
      throw _CampaignFailure(_stage, 'G21 receipt timing $key was rejected.');
    }
    return value;
  }

  int _positiveReceiptInt(Map<String, Object?> receipt, String key) {
    final value = _nonNegativeReceiptInt(receipt, key);
    if (value <= 0) {
      throw _CampaignFailure(_stage, 'G21 receipt timing $key was zero.');
    }
    return value;
  }

  Future<Map<String, Object?>> _captureUnreadLifecycle({
    bool publicRelayProof = false,
  }) async {
    _stage = 'unread_lifecycle';
    await _reopenRecipientAtOrbit();
    await _waitForOrbitUnread(0);
    await _requireCleanNotificationSlate();

    final markerBase = DateTime.now().toUtc().microsecondsSinceEpoch;
    final firstMarker = 'TC256-unread-1-$markerBase';
    final secondMarker = 'TC256-unread-2-$markerBase';

    if (publicRelayProof) await _terminateRecipient();
    await _sendUiMessageFromSender(
      firstMarker,
      publicRelayProof: publicRelayProof,
    );
    final firstCapture = await _waitForSingleOrdinaryMessageCard(firstMarker);
    final firstCard = firstCapture.$1;
    if (publicRelayProof) await _reopenRecipientAtOrbit();
    await _waitForOrbitUnread(1);
    _writeSanitizedCardEvidence(
      'recipient_unread_first_notification.txt',
      firstCard,
    );
    await _dismissSingleNotification(firstCard.title);
    await _waitForOrbitUnread(1);

    if (publicRelayProof) await _terminateRecipient();
    await _sendUiMessageFromSender(
      secondMarker,
      publicRelayProof: publicRelayProof,
    );
    final secondCapture = await _waitForSingleOrdinaryMessageCard(secondMarker);
    final secondCard = secondCapture.$1;
    if (publicRelayProof) await _reopenRecipientAtOrbit();
    await _waitForOrbitUnread(2);
    _writeSanitizedCardEvidence(
      'recipient_unread_second_notification.txt',
      secondCard,
    );
    if (firstCard.id == null || secondCard.id != firstCard.id) {
      throw _CampaignFailure(
        _stage,
        'Ordinary message replacement must reuse one deterministic notification id; '
        'observed ${firstCard.id} then ${secondCard.id}.',
      );
    }
    if (publicRelayProof) await _terminateRecipient();

    final messageTapRoute = await _tapAndClassifyRoute(
      secondCard,
      evidenceName: 'recipient_message_notification_tap_flow.log',
      expectedPeerId: publicRelayProof ? sender.peerId : null,
      requireColdLocalProof: publicRelayProof,
    );
    final coldLocalOpenEvidence = _directTextColdLocalNotificationOpenEvidence;
    if (publicRelayProof && coldLocalOpenEvidence?.isComplete != true) {
      throw _CampaignFailure(
        _stage,
        'Cold local notification open did not produce complete causal proof.',
      );
    }
    await _waitForUiText(recipientId, firstMarker, const Duration(seconds: 45));
    await _waitForUiText(
      recipientId,
      secondMarker,
      const Duration(seconds: 45),
    );
    await _reopenRecipientAtOrbit();
    await _waitForOrbitUnread(0);

    return <String, Object?>{
      'status': 'passed',
      'initialUnreadAtZero': true,
      if (!publicRelayProof) 'reactionLeftUnreadAtZero': true,
      'unreadCounts': const <int>[0, 1, 1, 2, 0],
      'dismissalPreservedUnread': true,
      'firstNotificationId': firstCard.id,
      'secondNotificationId': secondCard.id,
      if (!publicRelayProof) 'replacementObserved': true,
      if (publicRelayProof)
        'stableConversationNotificationIdAcrossDismissAndResurface': true,
      if (publicRelayProof)
        'notificationLifecycle':
            'first_posted_dismissed_second_resurfaced_same_id_then_tapped',
      'firstTitle': firstCard.title,
      'firstBody': firstCard.body,
      'secondTitle': secondCard.title,
      'secondBody': secondCard.body,
      'genericNewMessageRejected': true,
      'tapRoute': messageTapRoute,
      if (publicRelayProof)
        'coldLocalNotificationOpen': coldLocalOpenEvidence!.toJson(),
      'bothMessagesVisibleAfterTap': true,
      'orbitClearedAfterReadAndReturn': true,
      'recipientKilledBeforeEachSend': publicRelayProof,
      'recipientKilledBeforeNotificationTap': publicRelayProof,
      'publicRelayStoreAndProviderSendPerMessage': publicRelayProof,
      'orbitObservationNavigation': 'launcher_resume_walk_back_no_force_stop',
      'firstEvidencePath':
          '${artifactDir.path}/recipient_unread_first_notification.txt',
      'secondEvidencePath':
          '${artifactDir.path}/recipient_unread_second_notification.txt',
    };
  }

  Future<void> _reopenRecipientAtOrbit() async {
    // RESUME the existing task; never clear it. FLAG_ACTIVITY_CLEAR_TASK
    // (0x8000) destroys the activity while the process keeps living, so a
    // SECOND Flutter engine starts in a process whose FIRST engine still owns
    // the canonical Go runtime and the SQLCipher handle. Measured on device
    // 2026-08-20: the relaunched engine logged GO_BRIDGE_PLATFORM_ERROR
    // 'This Flutter engine does not own the active Go runtime' and
    // DatabaseException(database_closed), and rendered a BLACK screen whose
    // whole UI dump was one node with an empty content-desc — so the unread
    // wait could never observe anything and timed out. A clean single-engine
    // launch of the same build renders Orbit with the contact row intact.
    // The process is still never terminated and no persisted message state
    // changes: the two prohibitions this method has always carried are the
    // reason it resumes rather than restarts.
    Future<void> resumeLauncherRoot() => _adbShell(recipientId, [
      'am',
      'start',
      '-W',
      '-a',
      'android.intent.action.MAIN',
      '-c',
      'android.intent.category.LAUNCHER',
      '-f',
      '0x10000000',
      '-n',
      '$appPackage/.MainActivity',
    ]);

    await resumeLauncherRoot();
    // A notification cold start leaves the conversation on top. Walk back the
    // way a user does and stop as soon as an Orbit row is on screen. The
    // alternating resume covers the other case, where Back pops past the app
    // root instead of revealing Orbit beneath the conversation.
    for (var attempt = 0; attempt < 6; attempt++) {
      if (extractOrbitUnreadCount(
            await _uiDump(recipientId),
            sender.username,
          ) !=
          null) {
        return;
      }
      if (attempt.isOdd) {
        await resumeLauncherRoot();
      } else {
        await _adbShell(recipientId, ['input', 'keyevent', 'KEYCODE_BACK']);
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _sendUiMessageFromSender(
    String marker, {
    bool publicRelayProof = false,
  }) async {
    await _openConversation(sender, recipient.username);
    await _adb(senderId, ['logcat', '-c']);
    final initialDump = await _uiDump(senderId);
    final initialEditor = findNodeBoundsByClass(
      initialDump,
      'android.widget.EditText',
    );
    if (initialEditor == null) {
      throw _CampaignFailure(
        _stage,
        'The sender conversation did not expose its compose editor.',
      );
    }
    await _adbShell(senderId, [
      'input',
      'tap',
      '${(initialEditor.$1 + initialEditor.$3) ~/ 2}',
      '${(initialEditor.$2 + initialEditor.$4) ~/ 2}',
    ]);
    await _adbShell(senderId, ['input', 'text', marker]);
    await _waitForUiText(senderId, marker, const Duration(seconds: 10));

    final typedDump = await _uiDump(senderId);
    final typedEditor = findNodeBoundsByClass(
      typedDump,
      'android.widget.EditText',
    );
    if (typedEditor == null) {
      throw _CampaignFailure(
        _stage,
        'The sender compose editor disappeared before send.',
      );
    }
    DateTime? relayWindowStart;
    if (publicRelayProof) {
      await _revalidateGateAAuthorization(
        'message_${_directTextRelaySends.length + 1}_send',
      );
      relayWindowStart = DateTime.now().toUtc();
    }
    await _adbShell(senderId, [
      'input',
      'tap',
      '${typedEditor.$3 + 75}',
      '${(typedEditor.$2 + typedEditor.$4) ~/ 2}',
    ]);
    final messageId = await _waitForValue(
      'ordinary message send success for $marker',
      const Duration(seconds: 90),
      () async {
        final logcat = await _adb(senderId, ['logcat', '-d']);
        return extractChatSendSuccessId(logcat.stdout + logcat.stderr);
      },
    );
    if (publicRelayProof) {
      final since = relayWindowStart!;
      await _waitForRelayStore(since);
      await Future<void>.delayed(_providerObservationDelay);
      final journal = await _relayJournalSince(since);
      final capture = classifyRelayCapture(
        log: journal,
        senderPrefix: sender.peerPrefix,
        recipientPrefix: recipient.peerPrefix,
      );
      if (!capture.relayMatchedEvent ||
          !capture.providerMatchedEvent ||
          capture.providerFailureMatched) {
        throw _CampaignFailure(
          _stage,
          'The bounded direct-text window did not contain one successful '
          'public relay store/provider path.',
        );
      }
      final storeMarker =
          '[INBOX] Stored message for ${recipient.peerPrefix} from '
          '${sender.peerPrefix}';
      final pushMarker = '[PUSH] Notification sent to ${recipient.peerPrefix}';
      final storeIndex = journal.indexOf(storeMarker);
      final pushIndex = journal.indexOf(pushMarker, storeIndex + 1);
      if (storeIndex < 0 || pushIndex <= storeIndex) {
        throw _CampaignFailure(
          _stage,
          'The bounded direct-text relay/provider markers were out of order.',
        );
      }
      final evidence = _writeRelayEvidence(
        journal,
        since,
        filename:
            'direct_text_relay_provider_${_directTextRelaySends.length + 1}.log',
      );
      _directTextRelaySends.add(
        _DirectTextRelaySendEvidence(
          marker: marker,
          messageId: messageId,
          windowStart: since,
          relayEvidencePath: evidence.path,
        ),
      );
    }
  }

  Future<void> _waitForOrbitUnread(int expected) async {
    await _waitFor(
      'Orbit unread count $expected for ${sender.username}',
      const Duration(seconds: 60),
      () async {
        final xml = await _uiDump(recipientId);
        return extractOrbitUnreadCount(xml, sender.username) == expected;
      },
    );
  }

  Future<(ActiveNotificationCard, String)> _waitForSingleOrdinaryMessageCard(
    String expectedBody,
  ) {
    return _waitForValue(
      'one ordinary message notification for $expectedBody',
      const Duration(seconds: 60),
      () async {
        final dump = await _notificationDump(recipientId);
        final cards = extractActiveNotificationCards(
          dump,
          packageName: appPackage,
        );
        if (cards.isEmpty) return null;
        if (cards.length != 1) {
          throw _CampaignFailure(
            _stage,
            'Expected one ordinary message card, observed ${cards.length}.',
          );
        }
        final errors = validateOrdinaryMessageNotificationCard(
          cards.single,
          expectedTitle: sender.username,
          expectedBody: expectedBody,
        );
        if (errors.isNotEmpty) {
          throw _CampaignFailure(_stage, errors.join('; '));
        }
        return (cards.single, dump);
      },
    );
  }

  Future<void> _dismissSingleNotification(String title) async {
    await _adbShell(recipientId, ['cmd', 'statusbar', 'expand-notifications']);
    final bounds = await _waitForBounds(
      recipientId,
      title,
      const Duration(seconds: 15),
    );
    await _adbShell(recipientId, [
      'input',
      'swipe',
      '${bounds.$1}',
      '${bounds.$2}',
      '1040',
      '${bounds.$2}',
      '500',
    ]);
    await _waitFor(
      'ordinary message notification dismissal',
      const Duration(seconds: 20),
      () async => extractActiveNotificationCards(
        await _notificationDump(recipientId),
        packageName: appPackage,
      ).isEmpty,
    );
    await _adbShell(recipientId, [
      'cmd',
      'statusbar',
      'collapse',
    ], allowFail: true);
  }

  void _writeSanitizedCardEvidence(
    String filename,
    ActiveNotificationCard card,
  ) {
    File('${artifactDir.path}/$filename').writeAsStringSync(
      'id=${card.id}\n'
      'title=${card.title}\n'
      'body=${card.body}\n',
    );
  }

  Future<String> _tapAndClassifyRoute(
    ActiveNotificationCard card, {
    String evidenceName = 'recipient_notification_tap_flow.log',
    String? expectedPeerId,
    bool requireColdLocalProof = false,
  }) async {
    if (requireColdLocalProof &&
        (expectedPeerId == null || expectedPeerId.trim().isEmpty)) {
      throw _CampaignFailure(
        _stage,
        'Cold local notification proof requires the exact target peer.',
      );
    }
    await _adb(recipientId, ['logcat', '-c']);
    await _adbShell(recipientId, ['cmd', 'statusbar', 'expand-notifications']);
    final cardCenter = await _waitForNotificationCardInShade(card);
    await _adbShell(recipientId, [
      'input',
      'tap',
      '${cardCenter.$1}',
      '${cardCenter.$2}',
    ]);
    final log = await _waitForValue(
      requireColdLocalProof
          ? 'cold local notification exact route/timing/drain markers'
          : 'notification route marker',
      requireColdLocalProof
          ? const Duration(seconds: 90)
          : const Duration(seconds: 45),
      () async {
        final output = await _adb(recipientId, ['logcat', '-d', '-v', 'brief']);
        if (requireColdLocalProof) {
          final evidence = parseAndroidColdLocalNotificationOpenEvidence(
            output.stdout,
            expectedPeerId: expectedPeerId!,
            tappedRoutePayload: card.routePayload,
          );
          if (evidence.hasTerminalFailure) {
            throw _CampaignFailure(
              _stage,
              evidence.routeTargetMismatch
                  ? 'Cold local notification opened the wrong conversation.'
                  : 'Cold local notification open emitted a route/load/drain error.',
            );
          }
          if (evidence.isComplete) {
            _directTextColdLocalNotificationOpenEvidence = evidence;
            return output.stdout;
          }
          return null;
        }
        if (output.stdout.contains('NOTIFICATION_TAP_TO_MESSAGE_TIMING') ||
            output.stdout.contains(
              'CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE',
            )) {
          return output.stdout;
        }
        if (output.stdout.contains('NOTIFICATION_TAP_NAV_ERROR') ||
            output.stdout.contains('INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR')) {
          throw _CampaignFailure(
            _stage,
            'Notification tap emitted a route error.',
          );
        }
        return null;
      },
    );
    File(
      '${artifactDir.path}/$evidenceName',
    ).writeAsStringSync(_notificationRouteLines(log));
    return 'conversation';
  }

  Future<(int, int)> _waitForNotificationCardInShade(
    ActiveNotificationCard card,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 750));
    for (var attempt = 0; attempt < 6; attempt++) {
      final xml = await _uiDump(recipientId);
      final target = findAndroidNotificationCardTapTarget(
        xml,
        title: card.title,
        body: card.body,
      );
      if (target != null) {
        final expand = target.collapsedGroupExpandCenter;
        if (expand == null) return target.cardCenter;
        await _adbShell(recipientId, [
          'input',
          'tap',
          '${expand.$1}',
          '${expand.$2}',
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 750));
        continue;
      }
      if (attempt < 5) {
        await _adbShell(recipientId, [
          'input',
          'swipe',
          '540',
          '1900',
          '540',
          '700',
          '500',
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 750));
      }
    }
    throw _CampaignFailure(
      _stage,
      'The validated notification card was active but not reachable in the '
      'bounded notification-shade scroll window.',
    );
  }

  File _writeRelayEvidence(
    String journal,
    DateTime since, {
    String filename = 'relay_provider_window.log',
  }) {
    final lines = journal
        .split('\n')
        .where((line) {
          final relevantPeer =
              line.contains(sender.peerPrefix) ||
              line.contains(recipient.peerPrefix);
          return relevantPeer &&
              (line.contains('[INBOX]') || line.contains('[PUSH]'));
        })
        .join('\n');
    return File('${artifactDir.path}/$filename')..writeAsStringSync(
      'windowStart=${since.toIso8601String()}\n'
      'senderPrefix=${sender.peerPrefix}\n'
      'recipientPrefix=${recipient.peerPrefix}\n'
      '$lines\n',
    );
  }

  void _writePassedArtifact({
    required _RelayInfo relayInfo,
    required String reactionId,
    required String messageId,
    required ActiveNotificationCard? card,
    required String tapRoute,
    required bool recipientAbsentBeforeReaction,
    required bool recipientAliveBeforeReaction,
    required AndroidDurableDirectReactionShow? durableShow,
    required File durableEvidence,
    required bool providerSendObserved,
    required bool recipientBackgroundPushObserved,
    required String providerEvidenceSource,
    required File providerEvidence,
    required RelayCaptureClassification relayCapture,
    required File relayEvidence,
    required File senderEvidence,
    required File notificationEvidence,
    required Map<String, Object?>? unreadLifecycle,
  }) {
    final staleFailure = File(
      '${artifactDir.path}/${_artifactStem}_failure.json',
    );
    if (staleFailure.existsSync()) staleFailure.deleteSync();
    final build = _build!;
    final artifact = <String, Object?>{
      'testCase': _testCase,
      'scenario': _scenario,
      'status': 'passed',
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'app': {
        'revision': build.revision,
        'cleanCurrentBuild': !_workingTreeBuild,
        'workingTreeCandidate': _workingTreeBuild,
        'reusedPrebuiltCandidate': noChildBuilds || reuseWorkingTreeApks,
        'buildMode': build.buildMode,
        'buildProfile': build.buildProfile,
        'childBuildCount': build.childBuildCount,
        'apkSha256': build.normalApkSha256,
        'senderHarnessApkSha256': build.e2eApkSha256,
        'senderApkSha256': build.e2eApkSha256,
        'recipientApkSha256': build.normalApkSha256,
        'senderDevice': senderId,
        'recipientDevice': recipientId,
      },
      'relay': {
        'revision': '${relayInfo.version}+sha256:${relayInfo.sha256}',
        'evidencePath': relayEvidence.path,
        'adminAccessReadOnly': true,
        'testTrafficWritesExpected': true,
      },
      'reaction': {
        'eventId': reactionId,
        'remoteType': 'message_reaction',
        'messageIdPrefix': messageId.length <= 8
            ? messageId
            : messageId.substring(0, 8),
        'emoji': _reactionEmoji,
        'senderEvidencePath': senderEvidence.path,
      },
      'observation': {
        'cardPresent': card != null,
        'recipientProcessAbsentBeforeReaction': recipientAbsentBeforeReaction,
        'unrelatedCardsRejected': true,
        'matchedReactionEventId': true,
        'producer': card == null ? 'none' : 'relay_fcm',
        'lifecycle': card == null ? 'not_emitted' : 'posted_and_tapped',
        'tapRoute': tapRoute,
        'title': card?.title ?? '',
        'body': card?.body ?? '',
        'typedCopyRequired': _typedCopyRequired,
        'genericNewMessageRejected': _typedCopyRequired,
        'notificationEvidencePath': notificationEvidence.path,
        'recipientProcessAliveBeforeReaction': recipientAliveBeforeReaction,
        'durableEffectRequired': durableBackgroundConnected,
        'durableEffectObserved': durableShow?.durableShown ?? false,
        'durableEffectDisposition': durableShow?.disposition ?? 'not_observed',
        'durableEffectFallbackShown': durableShow?.fallbackShown ?? false,
        'durableEffectDeferralReasons':
            durableShow?.deferralReasons ?? const <String>[],
        'durableEffectEvidencePath': durableEvidence.path,
      },
      'sourceAttribution': {
        'relayMatchedEvent': relayCapture.relayMatchedEvent,
        'providerEvidenceCaptured': true,
        'providerObservationWindowSeconds': _providerObservationDelay.inSeconds,
        'providerMatchedEvent': providerSendObserved,
        'providerConfirmedNoSend':
            relayCapture.relayMatchedEvent &&
            !providerSendObserved &&
            !relayCapture.providerFailureMatched,
        'providerEvidenceSource': providerEvidenceSource,
        'recipientBackgroundPushObserved': recipientBackgroundPushObserved,
        'providerEvidencePath': providerEvidence.path,
      },
      'unreadLifecycle': ?unreadLifecycle,
    };
    File(
      '${artifactDir.path}/$_artifactStem.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(artifact));
  }

  Future<void> _captureInitialDeviceState() async {
    _stage = 'initial_state_capture';
    final backup = await Directory.systemTemp.createTemp(
      'mknoon-direct-text-state-',
    );
    _stateBackupDirectory = backup;
    for (final deviceId in <String>[senderId, recipientId]) {
      await _requireProcessAndActivityAbsent(
        deviceId,
        environmentBlocked: true,
      );
      final paths = await _installedPackagePaths(deviceId);
      final state = _InitialAndroidPackageState(installed: paths.isNotEmpty);
      final initialCards = extractActiveNotificationCards(
        await _notificationDump(deviceId),
        packageName: appPackage,
      );
      if (initialCards.isNotEmpty) {
        throw _CampaignFailure(
          _stage,
          'Initial app notification state on $deviceId is not empty.',
          environmentBlocked: true,
        );
      }
      state.baselineNotificationSha256 = _notificationCardsSha256(initialCards);
      _initialPackageStates[deviceId] = state;
      if (!state.installed) continue;

      state.androidSdk = int.tryParse(
        (await _adbShell(deviceId, <String>[
          'getprop',
          'ro.build.version.sdk',
        ])).trim(),
      );
      if (state.androidSdk == null || state.androidSdk! <= 0) {
        throw _CampaignFailure(_stage, 'Android SDK state is unavailable.');
      }
      final packageDump = await _adbShell(deviceId, <String>[
        'dumpsys',
        'package',
        appPackage,
      ]);
      final versionCode = RegExp(
        r'\bversionCode=(\d+)\b',
      ).firstMatch(packageDump)?.group(1);
      final versionName = RegExp(
        r'\bversionName=([^\s]+)',
      ).firstMatch(packageDump)?.group(1);
      if (versionCode == null || versionName == null) {
        throw _CampaignFailure(_stage, 'Package version state is unavailable.');
      }
      state.versionCode = versionCode;
      state.versionName = versionName;
      state.notificationPermissionGranted = state.androidSdk! < 33
          ? true
          : await _isNotificationPermissionGranted(deviceId);

      final deviceBackup = Directory(
        '${backup.path}/${deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}',
      )..createSync();
      for (var index = 0; index < paths.length; index++) {
        final apk = File('${deviceBackup.path}/installed-$index.apk');
        await _adb(deviceId, <String>['pull', paths[index], apk.path]);
        if (!apk.existsSync() || apk.lengthSync() <= 0) {
          throw _CampaignFailure(_stage, 'Installed APK backup failed.');
        }
        final hostSha = await _sha256(apk);
        final deviceSha = await _deviceFileSha256(deviceId, paths[index]);
        if (hostSha != deviceSha) {
          throw _CampaignFailure(_stage, 'Installed APK backup hash drifted.');
        }
        state.apkBackups.add(apk);
        state.apkSha256.add(hostSha);
      }
      await _capturePrivateAppData(deviceId, state);
    }
    _initialStateCaptureComplete = true;
  }

  Future<void> _capturePrivateAppData(
    String deviceId,
    _InitialAndroidPackageState state,
  ) async {
    final listed = await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'ls',
      '-1',
      '-A',
      '.',
    ]);
    final entries = listed
        .split('\n')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (entries.isEmpty ||
        entries.any((entry) => !_isSafePrivateEntry(entry))) {
      throw _CampaignFailure(
        _stage,
        'App-private top-level inventory is empty or unsafe.',
      );
    }
    final size = await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'du',
      '-sk',
      '.',
    ]);
    final sizeKb = int.tryParse(size.trim().split(RegExp(r'\s+')).first);
    if (sizeKb == null || sizeKb < 0 || sizeKb > 256 * 1024) {
      throw _CampaignFailure(
        _stage,
        'App-private backup exceeds the bounded 256 MiB policy.',
      );
    }
    final backupName =
        '.mknoon_direct_text_backup_'
        '${DateTime.now().toUtc().microsecondsSinceEpoch}_'
        '${Random.secure().nextInt(0x7fffffff)}';
    if (entries.contains(backupName)) {
      throw _CampaignFailure(_stage, 'Private backup name collision.');
    }
    state.privateBackupDirectory = backupName;
    state.privateTopLevelEntries = List<String>.unmodifiable(entries);
    await _requireProcessAndActivityAbsent(deviceId, environmentBlocked: true);
    await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'mkdir',
      '-m',
      '0700',
      backupName,
    ]);
    final archive = '$backupName/original.tar';
    await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'tar',
      '-cf',
      archive,
      '--',
      ...entries,
    ]);
    await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'chmod',
      '0600',
      archive,
    ]);
    await _requireProcessAndActivityAbsent(deviceId, environmentBlocked: true);
    state.privateBackupSha256 = await _runAsFileSha256(deviceId, archive);
    final appOwner = (await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'stat',
      '-c',
      '%u:%g',
      '.',
    ])).trim();
    final topLevelMetadata = <String, String>{};
    for (final entry in entries) {
      final value = (await _adbShell(deviceId, <String>[
        'run-as',
        appPackage,
        'stat',
        '-c',
        '%a:%u:%g',
        entry,
      ])).trim();
      if (!RegExp(r'^\d{3,4}:\d+:\d+$').hasMatch(value)) {
        throw _CampaignFailure(
          _stage,
          'Private top-level metadata was rejected.',
        );
      }
      topLevelMetadata[entry] = value;
    }
    final metadata = (await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'stat',
      '-c',
      '%a:%u:%g:%s',
      archive,
    ])).trim();
    final fields = metadata.split(':');
    final archiveSize = fields.length == 4 ? int.tryParse(fields[3]) : null;
    final archiveOwner = fields.length == 4 ? '${fields[1]}:${fields[2]}' : '';
    if (fields.length != 4 ||
        fields[0] != '600' ||
        !RegExp(r'^\d+:\d+$').hasMatch(appOwner) ||
        archiveOwner != appOwner ||
        archiveSize == null ||
        archiveSize <= 0 ||
        archiveSize > 256 * 1024 * 1024) {
      throw _CampaignFailure(_stage, 'Private backup metadata was rejected.');
    }
    state.privateBackupSizeBytes = archiveSize;
    state.privateBackupOwner = archiveOwner;
    state.privateTopLevelMetadata = Map<String, String>.unmodifiable(
      topLevelMetadata,
    );
  }

  Future<void> _restoreExactInitialDeviceState() async {
    if (_exactRestorationComplete) return;
    _stage = 'restoration';
    final failures = <String>[];
    for (final deviceId in <String>[senderId, recipientId]) {
      final state = _initialPackageStates[deviceId];
      if (state == null) continue;
      try {
        if (_deviceMutationStarted) {
          await _restoreOneDeviceState(deviceId, state);
        } else {
          final backupName = state.privateBackupDirectory;
          if (state.installed && backupName != null) {
            await _adbShell(deviceId, <String>[
              'run-as',
              appPackage,
              'rm',
              '-rf',
              '--',
              backupName,
            ]);
          }
          state.privateDataRestored = true;
          state.packageStateRestored = true;
        }
      } on Object {
        failures.add(
          'device_${deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}',
        );
      }
    }
    if (failures.isEmpty) {
      try {
        await _finishHostRestoration();
      } on Object {
        failures.add('host_cleanup');
      }
    } else {
      try {
        await _cleanupGeneratedBuildArtifacts();
      } on Object {
        failures.add('host_build_cleanup');
      }
    }
    if (failures.isNotEmpty) {
      throw _CampaignFailure(
        _stage,
        'Exact restoration failed at ${failures.join(',')}; recovery backups retained.',
      );
    }
    _exactRestorationComplete = true;
  }

  Future<void> _restoreOneDeviceState(
    String deviceId,
    _InitialAndroidPackageState state,
  ) async {
    final failures = <String>[];
    var safeToRestore = false;
    try {
      await _adbShell(deviceId, <String>['am', 'force-stop', appPackage]);
      await _waitForProcessAndActivityAbsent(deviceId);
      safeToRestore = true;
    } on Object {
      failures.add('force_stop');
    }
    if (safeToRestore && !state.installed) {
      try {
        if ((await _installedPackagePaths(deviceId)).isNotEmpty) {
          await _adb(deviceId, <String>[
            'uninstall',
            appPackage,
          ], allowFail: true);
        }
        if ((await _installedPackagePaths(deviceId)).isNotEmpty) {
          throw _CampaignFailure(
            _stage,
            'Initially absent package survived restoration on $deviceId.',
          );
        }
        state.privateDataRestored = true;
        state.packageStateRestored = true;
      } on Object {
        failures.add('absent_package');
      }
    } else if (safeToRestore) {
      try {
        await _restoreOriginalApks(deviceId, state);
      } on Object {
        failures.add('apk');
      }
      try {
        await _restorePrivateAppData(deviceId, state);
      } on Object {
        failures.add('private_data');
      }
      try {
        await _restoreNotificationPermission(deviceId, state);
        state.packageStateRestored = true;
      } on Object {
        failures.add('permission');
      }
    }
    try {
      await _adbShell(deviceId, <String>['am', 'force-stop', appPackage]);
      await _waitForProcessAndActivityAbsent(deviceId);
      final finalCards = extractActiveNotificationCards(
        await _notificationDump(deviceId),
        packageName: appPackage,
      );
      if (_notificationCardsSha256(finalCards) !=
          state.baselineNotificationSha256) {
        throw _CampaignFailure(
          _stage,
          'Notification state was not restored exactly on $deviceId.',
        );
      }
    } on Object {
      failures.add('idle_or_notification');
    }
    if (failures.isNotEmpty) {
      throw _CampaignFailure(
        _stage,
        'Device restoration failed at ${failures.join(',')}.',
      );
    }
  }

  Future<void> _finishHostRestoration() async {
    final failures = <String>[];
    try {
      await _cleanupGeneratedBuildArtifacts();
    } on Object {
      failures.add('generated_builds');
    }
    final backup = _stateBackupDirectory;
    if (failures.isEmpty && backup != null) {
      try {
        if (backup.existsSync()) await backup.delete(recursive: true);
        if (backup.existsSync()) {
          throw _CampaignFailure(
            _stage,
            'Host state backup survived restoration.',
          );
        }
      } on Object {
        failures.add('recovery_backup');
      }
    }
    if (failures.isNotEmpty) {
      throw _CampaignFailure(
        _stage,
        'Host restoration cleanup failed at ${failures.join(',')}; recovery backup retained.',
      );
    }
  }

  Future<void> _cleanupGeneratedBuildArtifacts() async {
    if (keepBuildArtifacts) return;
    final failures = <String>[];
    final files = <String, File?>{
      'e2e_apk': _build?.e2eApk,
      'normal_apk': _build?.normalApk,
      'metadata': File('${artifactDir.path}/working_tree_build.json'),
    };
    for (final entry in files.entries) {
      final file = entry.value;
      if (file == null) continue;
      try {
        if (file.existsSync()) await file.delete();
        if (file.existsSync()) failures.add(entry.key);
      } on Object {
        failures.add(entry.key);
      }
    }
    if (failures.isNotEmpty) {
      throw _CampaignFailure(
        _stage,
        'Generated build cleanup failed at ${failures.join(',')}.',
      );
    }
  }

  Future<void> _restoreOriginalApks(
    String deviceId,
    _InitialAndroidPackageState state,
  ) async {
    if (state.apkBackups.isEmpty) {
      throw _CampaignFailure(_stage, 'Original APK backup is unavailable.');
    }
    await _adb(
      deviceId,
      state.apkBackups.length == 1
          ? <String>['install', '-r', '-d', '-t', state.apkBackups.single.path]
          : <String>[
              'install-multiple',
              '-r',
              '-d',
              '-t',
              ...state.apkBackups.map((apk) => apk.path),
            ],
    );
    final paths = await _installedPackagePaths(deviceId);
    final actual = <String>[];
    for (final path in paths) {
      actual.add(await _deviceFileSha256(deviceId, path));
    }
    final expected = List<String>.from(state.apkSha256)..sort();
    actual.sort();
    if (jsonEncode(expected) != jsonEncode(actual)) {
      throw _CampaignFailure(_stage, 'Original APK bytes were not restored.');
    }
  }

  Future<void> _restorePrivateAppData(
    String deviceId,
    _InitialAndroidPackageState state,
  ) async {
    final backupName = state.privateBackupDirectory;
    final originalSha = state.privateBackupSha256;
    if (backupName == null || originalSha == null) {
      throw _CampaignFailure(_stage, 'Private app-data backup is unavailable.');
    }
    await _waitForProcessAndActivityAbsent(deviceId);
    await _verifyPrivateBackupBeforeRestore(deviceId, state);
    final current =
        (await _adbShell(deviceId, <String>[
              'run-as',
              appPackage,
              'ls',
              '-1',
              '-A',
              '.',
            ]))
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
    if (!current.contains(backupName) ||
        current.any((entry) => !_isSafePrivateEntry(entry))) {
      throw _CampaignFailure(_stage, 'Private backup inventory was corrupted.');
    }
    for (final entry in current.where((entry) => entry != backupName)) {
      await _adbShell(deviceId, <String>[
        'run-as',
        appPackage,
        'rm',
        '-rf',
        '--',
        entry,
      ]);
    }
    await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'tar',
      '-xf',
      '$backupName/original.tar',
      '-C',
      '.',
    ]);
    await _repairPackageMetadataAfterPrivateRestore(deviceId, state);
    final restoredEntries = List<String>.from(state.privateTopLevelEntries);
    await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'tar',
      '-cf',
      '$backupName/restored.tar',
      '--',
      ...restoredEntries,
    ]);
    final restoredSha = await _runAsFileSha256(
      deviceId,
      '$backupName/restored.tar',
    );
    if (restoredSha != originalSha) {
      throw _CampaignFailure(_stage, 'Private app-data hash did not restore.');
    }
    await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'rm',
      '-rf',
      '--',
      backupName,
    ]);
    final finalEntries =
        (await _adbShell(deviceId, <String>[
              'run-as',
              appPackage,
              'ls',
              '-1',
              '-A',
              '.',
            ]))
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
          ..sort();
    final expectedEntries = List<String>.from(state.privateTopLevelEntries)
      ..sort();
    if (jsonEncode(finalEntries) != jsonEncode(expectedEntries)) {
      throw _CampaignFailure(_stage, 'Private app-data inventory drifted.');
    }
    state.privateDataRestored = true;
  }

  Future<void> _repairPackageMetadataAfterPrivateRestore(
    String deviceId,
    _InitialAndroidPackageState state,
  ) async {
    // Reinstalling the exact retained APK asks installd to repair package-owned
    // cache roots (including their per-app cache gid/setgid metadata) without
    // clearing data, launching the app, or changing package bytes.
    await _restoreOriginalApks(deviceId, state);
    await _waitForProcessAndActivityAbsent(deviceId);
    await _restoreNotificationPermission(deviceId, state);

    final packageDump = await _adbShell(deviceId, <String>[
      'dumpsys',
      'package',
      appPackage,
    ]);
    if (!RegExp(
          '\\bversionCode=${RegExp.escape(state.versionCode!)}\\b',
        ).hasMatch(packageDump) ||
        !RegExp(
          '\\bversionName=${RegExp.escape(state.versionName!)}(?:\\s|\$)',
        ).hasMatch(packageDump)) {
      throw _CampaignFailure(
        _stage,
        'Package version changed during metadata repair.',
      );
    }
    for (final entry in const <String>['cache', 'code_cache']) {
      final expected = state.privateTopLevelMetadata[entry];
      if (expected == null) continue;
      final actual = (await _adbShell(deviceId, <String>[
        'run-as',
        appPackage,
        'stat',
        '-c',
        '%a:%u:%g',
        entry,
      ])).trim();
      if (actual != expected) {
        throw _CampaignFailure(
          _stage,
          'Package cache metadata did not restore exactly.',
        );
      }
    }
  }

  Future<void> _restoreNotificationPermission(
    String deviceId,
    _InitialAndroidPackageState state,
  ) async {
    if (state.androidSdk! < 33) return;
    final expected = state.notificationPermissionGranted!;
    if (await _isNotificationPermissionGranted(deviceId) != expected) {
      await _adbShell(deviceId, <String>[
        'pm',
        expected ? 'grant' : 'revoke',
        appPackage,
        'android.permission.POST_NOTIFICATIONS',
      ]);
    }
    if (await _isNotificationPermissionGranted(deviceId) != expected) {
      throw _CampaignFailure(
        _stage,
        'Notification permission restoration failed on $deviceId.',
      );
    }
  }

  Future<void> _verifyPrivateBackupBeforeRestore(
    String deviceId,
    _InitialAndroidPackageState state,
  ) async {
    final backupName = state.privateBackupDirectory;
    final expectedSha = state.privateBackupSha256;
    final expectedSize = state.privateBackupSizeBytes;
    final expectedOwner = state.privateBackupOwner;
    if (backupName == null ||
        expectedSha == null ||
        expectedSize == null ||
        expectedOwner == null) {
      throw _CampaignFailure(_stage, 'Private backup metadata is incomplete.');
    }
    final archive = '$backupName/original.tar';
    final currentAppOwner = (await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'stat',
      '-c',
      '%u:%g',
      '.',
    ])).trim();
    final metadata = (await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'stat',
      '-c',
      '%a:%u:%g:%s',
      archive,
    ])).trim();
    final fields = metadata.split(':');
    final actualSize = fields.length == 4 ? int.tryParse(fields[3]) : null;
    final actualOwner = fields.length == 4 ? '${fields[1]}:${fields[2]}' : '';
    if (fields.length != 4 ||
        fields[0] != '600' ||
        actualOwner != expectedOwner ||
        actualOwner != currentAppOwner ||
        actualSize != expectedSize ||
        actualSize == null ||
        actualSize <= 0 ||
        actualSize > 256 * 1024 * 1024 ||
        await _runAsFileSha256(deviceId, archive) != expectedSha) {
      throw _CampaignFailure(
        _stage,
        'Private backup changed before destructive restoration.',
      );
    }
  }

  Future<List<String>> _installedPackagePaths(String deviceId) async =>
      (await _adbShell(deviceId, <String>[
            'pm',
            'path',
            appPackage,
          ], allowFail: true))
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.startsWith('package:'))
          .map((line) => line.substring('package:'.length))
          .where((path) => path.isNotEmpty)
          .toList(growable: false);

  Future<void> _requireProcessAndActivityAbsent(
    String deviceId, {
    bool environmentBlocked = false,
  }) async {
    final pid = (await _adbShell(deviceId, <String>[
      'pidof',
      appPackage,
    ], allowFail: true)).trim();
    final activities = await _adbShell(deviceId, <String>[
      'dumpsys',
      'activity',
      'activities',
    ]);
    if (!isAndroidAppProcessAndActivityAbsent(
      pidOutput: pid,
      dumpsysActivities: activities,
      packageName: appPackage,
    )) {
      throw _CampaignFailure(
        _stage,
        'App PID or attached activity exists on $deviceId.',
        environmentBlocked: environmentBlocked,
      );
    }
  }

  Future<void> _waitForProcessAndActivityAbsent(String deviceId) => _waitFor(
    'no app PID or attached activity on $deviceId',
    const Duration(seconds: 20),
    () async {
      try {
        await _requireProcessAndActivityAbsent(deviceId);
        return true;
      } on _CampaignFailure {
        return false;
      }
    },
  );

  Future<String> _deviceFileSha256(String deviceId, String path) async {
    final output = await _adbShell(deviceId, <String>['sha256sum', path]);
    final value = output.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw _CampaignFailure(_stage, 'Device file SHA-256 is unavailable.');
    }
    return value;
  }

  Future<String> _runAsFileSha256(String deviceId, String path) async {
    final output = await _adbShell(deviceId, <String>[
      'run-as',
      appPackage,
      'sha256sum',
      path,
    ]);
    final value = output.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw _CampaignFailure(_stage, 'Private backup SHA-256 is unavailable.');
    }
    return value;
  }

  Future<bool> _isNotificationPermissionGranted(String deviceId) async {
    final dump = await _adbShell(deviceId, <String>[
      'dumpsys',
      'package',
      appPackage,
    ]);
    final match = RegExp(
      r'android\.permission\.POST_NOTIFICATIONS:\s+granted=(true|false)',
    ).firstMatch(dump);
    if (match == null) {
      throw _CampaignFailure(
        _stage,
        'Notification permission state is unavailable.',
      );
    }
    return match.group(1) == 'true';
  }

  String _notificationCardsSha256(List<ActiveNotificationCard> cards) {
    final safe =
        cards
            .map(
              (card) => <String, Object?>{
                'id': card.id,
                'titleSha256': sha256
                    .convert(utf8.encode(card.title))
                    .toString(),
                'bodySha256': sha256.convert(utf8.encode(card.body)).toString(),
              },
            )
            .toList(growable: false)
          ..sort(
            (left, right) => jsonEncode(left).compareTo(jsonEncode(right)),
          );
    return sha256.convert(utf8.encode(jsonEncode(safe))).toString();
  }

  bool _isSafePrivateEntry(String value) =>
      RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(value) &&
      value != '.' &&
      value != '..';

  void _writeFirstWakeProfileAotArtifact({
    required _RelayInfo relayInfo,
    required Map<String, Object?> evidence,
  }) {
    if (!_exactRestorationComplete ||
        _initialPackageStates.values.any(
          (state) => !state.packageStateRestored || !state.privateDataRestored,
        )) {
      throw _CampaignFailure(
        _stage,
        'Profile-AOT proof cannot publish before exact state restoration.',
      );
    }
    final build = _build!;
    if (build.buildProfile != _firstWakeProfileAotBuildProfile ||
        build.buildMode != 'standalone_child_builds' ||
        build.childBuildCount != 2) {
      throw _CampaignFailure(
        _stage,
        'Profile-AOT proof build provenance is incomplete.',
      );
    }
    final staleFailure = File(
      '${artifactDir.path}/${_artifactStem}_failure.json',
    );
    if (staleFailure.existsSync()) staleFailure.deleteSync();
    final artifact = <String, Object?>{
      'schema': 'mknoon.plan393.android-first-wake-profile-aot.v1',
      'testCase': _testCase,
      'scenario': _scenario,
      'status': 'passed',
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'mode': evidence['mode'],
      'app': <String, Object?>{
        'revision': build.revision,
        'workingTreeCandidate': true,
        'buildMode': build.buildMode,
        'buildProfile': build.buildProfile,
        'childBuildCount': build.childBuildCount,
        'profileAot': true,
        'senderHarnessApkSha256': build.e2eApkSha256,
        'recipientProfileApkSha256': build.normalApkSha256,
        'recipientDevice': recipientId,
        'senderDevice': senderId,
      },
      'providerInputs': <String, Object?>{
        'serviceAccountSha256': sha256
            .convert(serviceAccount!.readAsBytesSync())
            .toString(),
        'stagingManifestSha256': sha256
            .convert(stagingManifest!.readAsBytesSync())
            .toString(),
      },
      'relay': <String, Object?>{
        'revision': '${relayInfo.version}+sha256:${relayInfo.sha256}',
        'realFcm': true,
      },
      'observation': evidence,
      'restoration': <String, Object?>{
        for (final entry in _initialPackageStates.entries)
          entry.key: <String, Object?>{
            'initiallyInstalled': entry.value.installed,
            'packageStateRestored': entry.value.packageStateRestored,
            'privateDataRestored': entry.value.privateDataRestored,
            'notificationStateRestored': true,
            'appProcessIdle': true,
          },
        'hostBackupDeleted': true,
        'passWrittenAfterRestoration': true,
      },
      'redaction': const <String, Object?>{
        'rawMessageIdentifierPersisted': false,
        'rawPeerIdentifierPersisted': false,
        'rawNotificationCopyPersisted': false,
        'rawCredentialPersisted': false,
        'receiptFixedDomain': true,
      },
      'containsSecrets': false,
    };
    File(
      '${artifactDir.path}/$_artifactStem.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(artifact));
  }

  void _writeDirectTextPassedArtifact({
    required _RelayInfo relayInfo,
    required Map<String, Object?> unreadLifecycle,
  }) {
    final receipt = _directTextTokenReceipt;
    if (!_exactRestorationComplete ||
        receipt == null ||
        _relayTokenRegistrationEvidencePath == null ||
        _directTextRelaySends.length != 2 ||
        _directTextColdLocalNotificationOpenEvidence?.isComplete != true ||
        gateAAuthorization?['authorizationKind'] !=
            backgroundCryptoCurrentTokenAuthorizationKind ||
        receipt['authorizationKind'] !=
            gateAAuthorization?['authorizationKind'] ||
        receipt['authorizationArtifactSha256'] !=
            gateAAuthorization?['authorizationArtifactSha256'] ||
        receipt['gateACommandGenerationId'] !=
            gateAAuthorization?['gateACommandGenerationId'] ||
        receipt['gateAArtifactSha256'] !=
            gateAAuthorization?['gateAArtifactSha256'] ||
        receipt['tokenSha256'] != gateAAuthorization?['tokenSha256'] ||
        receipt['accountIdentitySha256'] !=
            gateAAuthorization?['accountIdentitySha256'] ||
        receipt['transportIdentitySha256'] !=
            gateAAuthorization?['transportIdentitySha256'] ||
        _initialPackageStates.values.any(
          (state) => !state.packageStateRestored || !state.privateDataRestored,
        )) {
      throw _CampaignFailure(
        _stage,
        'Direct-text proof is incomplete at the pass boundary.',
      );
    }
    final staleFailure = File(
      '${artifactDir.path}/${_artifactStem}_failure.json',
    );
    if (staleFailure.existsSync()) staleFailure.deleteSync();
    final authorization = gateAAuthorization!;
    final artifact = <String, Object?>{
      'schema': 'mknoon.direct-text-public-relay-proof.v1',
      'testCase': _testCase,
      'scenario': _scenario,
      'status': 'passed',
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'app': <String, Object?>{
        'revision': _build!.revision,
        'workingTreeCandidate': true,
        'reusedPrebuiltCandidate': reuseWorkingTreeApks,
        'normalApkSha256': _build!.normalApkSha256,
        'senderHarnessApkSha256': _build!.e2eApkSha256,
      },
      'gateAAuthorization': authorization,
      'currentFirebaseTokenProof': receipt,
      'publicRelay': <String, Object?>{
        'revision': '${relayInfo.version}+sha256:${relayInfo.sha256}',
        'sameAccountReregistrationObserved': true,
        'recipientAccountIdentitySha256': sha256
            .convert(utf8.encode(recipient.peerId))
            .toString(),
        'registrationEvidencePath': _relayTokenRegistrationEvidencePath,
        'currentTokenSha256Bound':
            receipt['tokenSha256'] == authorization['tokenSha256'],
        'boundedSends': _directTextRelaySends
            .map((send) => send.toJson())
            .toList(growable: false),
        'behavioralClaim':
            'production sender UI to public relay store to FCM provider send '
            'to killed recipient, after same-account registration of the '
            'current SDK token whose SHA-256 matched the fresh validate-only '
            'Gate A v2 authorization artifact',
        'earlierRegistrationFrameExactCausalAttribution': false,
        'relayPersistenceClaimFromEarlierGate': false,
      },
      'unreadLifecycle': unreadLifecycle,
      'restoration': <String, Object?>{
        for (final entry in _initialPackageStates.entries)
          entry.key: <String, Object?>{
            'initiallyInstalled': entry.value.installed,
            'apkSha256': entry.value.apkSha256,
            'notificationPermissionInitiallyGranted':
                entry.value.notificationPermissionGranted,
            'privateBackupSha256': entry.value.privateBackupSha256,
            'privateTopLevelEntryCount':
                entry.value.privateTopLevelEntries.length,
            'packageStateRestored': entry.value.packageStateRestored,
            'privateDataRestored': entry.value.privateDataRestored,
            'notificationStateRestored': true,
            'appProcessIdle': true,
          },
        'hostBackupDeleted': true,
      },
      'redaction': const <String, Object?>{
        'rawFirebaseTokenPersisted': false,
        'commandPayloadPersisted': false,
        'rawPrivateAppDataPersisted': false,
      },
      'containsSecrets': false,
    };
    File(
      '${artifactDir.path}/$_artifactStem.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(artifact));
  }

  Future<void> _restoreNormalBuilds() async {
    final normalApk = _build?.normalApk;
    if (normalApk == null || !normalApk.existsSync()) return;
    for (final id in [senderId, recipientId]) {
      await _installApk(id, normalApk, allowFail: true);
    }
    if (!keepBuildArtifacts) {
      for (final apk in [_build!.e2eApk, _build!.normalApk]) {
        if (apk.existsSync()) {
          await apk.delete();
        }
      }
      final metadata = File(
        '${artifactDir.path}/'
        '${liveTypedSmoke ? 'working_tree_build.json' : 'clean_head_build.json'}',
      );
      if (metadata.existsSync()) await metadata.delete();
    }
  }

  Future<void> _removeCleanWorktree() async {
    final worktree = _cleanWorktree;
    if (worktree == null) return;
    await _run(
      'git',
      ['worktree', 'remove', '--force', worktree.path],
      workingDirectory: sourceRoot.path,
      allowFail: true,
    );
  }

  Future<void> _installApk(
    String deviceId,
    File apk, {
    bool allowFail = false,
  }) async {
    final targetSha = await _sha256(apk);
    final installedSha = await _installedApkSha256(deviceId);
    if (installedSha == targetSha) {
      if (verbose) stdout.writeln('APK already installed on $deviceId.');
      return;
    }

    var result = await _adb(deviceId, [
      'install',
      '-r',
      '-d',
      '-t',
      apk.path,
    ], allowFail: true);
    if (result.exitCode != 0 &&
        (result.stdout + result.stderr).contains('not enough space')) {
      result = await _adb(deviceId, [
        'install',
        '--fastdeploy',
        '-r',
        '-d',
        '-t',
        apk.path,
      ], allowFail: true);
    }
    if (result.exitCode != 0 && !allowFail) {
      throw _CampaignFailure(
        _stage,
        'Could not install the clean HEAD test build on $deviceId without '
        'uninstalling existing data: ${_commandFailureSummary(result)}',
        environmentBlocked: true,
      );
    }
  }

  Future<String?> _installedApkSha256(String deviceId) async {
    final pathResult = await _adbShell(deviceId, [
      'pm',
      'path',
      appPackage,
    ], allowFail: true);
    String? basePath;
    for (final line in pathResult.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('package:') && trimmed.endsWith('/base.apk')) {
        basePath = trimmed.substring('package:'.length);
        break;
      }
    }
    if (basePath == null) return null;
    final sha = await _adbShell(deviceId, [
      'sha256sum',
      basePath,
    ], allowFail: true);
    final fields = sha.trim().split(RegExp(r'\s+'));
    if (fields.isEmpty || fields.first.length != 64) return null;
    return fields.first;
  }

  Future<void> _grantNotificationPermission(String deviceId) async {
    await _adbShell(deviceId, [
      'pm',
      'grant',
      appPackage,
      'android.permission.POST_NOTIFICATIONS',
    ], allowFail: true);
  }

  Future<void> _launch(String deviceId) async {
    // A verified APK cache hit skips `adb install`, so an older app process may
    // still be alive after the harness replaces its config/export files. Force
    // a cold launch to make bootstrap consume the new files deterministically.
    await _adbShell(deviceId, ['am', 'force-stop', appPackage]);
    await _adbShell(deviceId, [
      'am',
      'start',
      '-W',
      '-n',
      '$appPackage/.MainActivity',
    ]);
  }

  Future<String?> _readAppFile(String deviceId, String name) async {
    final result = await _adbShell(deviceId, [
      'run-as',
      appPackage,
      'cat',
      'app_flutter/$name',
    ], allowFail: true);
    if (result.contains('No such file') || result.trim().isEmpty) return null;
    return result;
  }

  Future<void> _deleteAppFile(String deviceId, String name) async {
    await _adbShell(deviceId, [
      'run-as',
      appPackage,
      'rm',
      '-f',
      'app_flutter/$name',
    ], allowFail: true);
  }

  Future<void> _writeAppFile(
    String deviceId,
    String name,
    String content,
  ) async {
    final temp = File(
      '${Directory.systemTemp.path}/256_${deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}_$name',
    )..writeAsStringSync(content);
    final remote = '/data/local/tmp/256_$name';
    try {
      await _adb(deviceId, ['push', temp.path, remote]);
      await _adbShell(deviceId, [
        'run-as',
        appPackage,
        'mkdir',
        '-p',
        'app_flutter',
      ]);
      await _adbShell(deviceId, [
        'run-as',
        appPackage,
        'cp',
        remote,
        'app_flutter/$name',
      ]);
    } finally {
      await _adbShell(deviceId, ['rm', '-f', remote], allowFail: true);
      if (temp.existsSync()) await temp.delete();
    }
  }

  Future<String> _notificationDump(String deviceId) async {
    _CommandOutput? lastFailure;
    // A device-local proof can outlive an adbd transport replacement. The
    // failed recovery run recovered after the old sub-second retry window, so
    // keep the snapshot bounded while covering the real reconnect interval.
    for (var attempt = 0; attempt < 12; attempt += 1) {
      final result = await _adb(deviceId, [
        'shell',
        'dumpsys',
        'notification',
        '--noredact',
      ], allowFail: true);
      if (result.exitCode == 0) return result.stdout;
      lastFailure = result;
      if (attempt < 11) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw _CampaignFailure(
      _stage,
      'adb notification snapshot failed (${lastFailure!.exitCode}): '
      '${_lastLine(lastFailure.stderr + lastFailure.stdout)}',
    );
  }

  Future<void> _longPressText(String deviceId, String text) async {
    final bounds = await _waitForBounds(
      deviceId,
      text,
      const Duration(seconds: 20),
    );
    await _adbShell(deviceId, [
      'input',
      'swipe',
      '${bounds.$1}',
      '${bounds.$2}',
      '${bounds.$1}',
      '${bounds.$2}',
      '900',
    ]);
  }

  Future<void> _tapText(String deviceId, String text) async {
    final bounds = await _waitForBounds(
      deviceId,
      text,
      const Duration(seconds: 20),
    );
    await _adbShell(deviceId, ['input', 'tap', '${bounds.$1}', '${bounds.$2}']);
  }

  Future<void> _waitForUiText(
    String deviceId,
    String text,
    Duration timeout,
  ) async {
    await _waitForBounds(deviceId, text, timeout);
  }

  Future<(int, int)> _waitForBounds(
    String deviceId,
    String text,
    Duration timeout,
  ) => _waitForValue(
    'UI node "$text" on $deviceId',
    timeout,
    () async => _boundsForText(await _uiDump(deviceId), text),
  );

  Future<String> _uiDump(String deviceId) async {
    const remote = '/data/local/tmp/256_ui.xml';
    return readCompleteAndroidUiHierarchyWithRetry(
      readAttempt: (_) async {
        await _adbShell(deviceId, [
          'uiautomator',
          'dump',
          remote,
        ], allowFail: true);
        final xml = await _adbShell(deviceId, ['cat', remote], allowFail: true);
        await _adbShell(deviceId, ['rm', '-f', remote], allowFail: true);
        return xml;
      },
    );
  }

  (int, int)? _boundsForText(String xml, String target) {
    return findSemanticNodeCenter(xml, target);
  }

  Future<String> _relayJournalSince(DateTime since) async {
    if (relayFixtureProbe != null) {
      final snapshot = await _relayFixtureSnapshot(since);
      return snapshot['journal']! as String;
    }
    final epochSeconds = since.millisecondsSinceEpoch ~/ 1000 - 2;
    return (await _ssh([
      'sudo',
      'journalctl',
      '-u',
      'relay-server',
      '--since',
      '@$epochSeconds',
      '--no-pager',
      '-o',
      'short-iso',
    ])).stdout;
  }

  Future<_CommandOutput> _ssh(List<String> remoteArgs) {
    return _run('ssh', [
      '-o',
      'BatchMode=yes',
      '-o',
      'ConnectTimeout=15',
      '-i',
      relayKey.path,
      relayTarget,
      _shellJoin(remoteArgs),
    ]);
  }

  Future<Map<String, Object?>> _relayFixtureSnapshot(DateTime since) async {
    final probe = relayFixtureProbe;
    if (probe == null) {
      throw _CampaignFailure(_stage, 'Relay fixture probe is unavailable.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = probe.replace(
        queryParameters: <String, String>{
          'kind': 'plan393_relay_snapshot',
          'sinceUnixMs':
              '${since.toUtc().millisecondsSinceEpoch.clamp(0, 1 << 62)}',
        },
      );
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != HttpStatus.ok) {
        throw const FormatException('fixture snapshot status');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('fixture snapshot object');
      }
      final snapshot = decoded.map<String, Object?>(
        (key, value) => MapEntry('$key', value),
      );
      final routesValue = snapshot['selectedRoutes'];
      if (routesValue is! Map) {
        throw const FormatException('fixture routes object');
      }
      final routes = routesValue.map<String, Object?>(
        (key, value) => MapEntry('$key', value),
      );
      final opaque = routes['opaque'];
      final rich = routes['rich'];
      final processStart = snapshot['processStartTimeSeconds'];
      if (snapshot['schema'] != 'mknoon.plan393.relay-fixture-snapshot.v1' ||
          snapshot['backend'] != 'redis' ||
          snapshot['ephemeral'] != true ||
          snapshot['pushTokenState'] != 'encrypted' ||
          snapshot['wakeOutcomeAdmissionEnabled'] != true ||
          snapshot['wakeOutcomeCoordinatorStarted'] != true ||
          snapshot['directReactionPushEnabled'] != true ||
          snapshot['realFcmConfigured'] != true ||
          snapshot['relayVersion'] is! String ||
          !RegExp(
            r'^[0-9a-f]{64}$',
          ).hasMatch('${snapshot['relayBinarySha256']}') ||
          processStart is! num ||
          !processStart.isFinite ||
          processStart <= 0 ||
          opaque is! int ||
          opaque < 0 ||
          rich is! int ||
          rich < 0 ||
          snapshot['journal'] is! String) {
        throw const FormatException('fixture snapshot attestation');
      }
      snapshot['selectedRoutes'] = routes;
      return snapshot;
    } on Object {
      throw _CampaignFailure(
        _stage,
        'The encrypted Redis/FCM relay fixture snapshot is unreadable.',
        environmentBlocked: true,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<_CommandOutput> _adb(
    String deviceId,
    List<String> args, {
    bool allowFail = false,
  }) => _run('adb', ['-s', deviceId, ...args], allowFail: allowFail);

  Future<String> _adbShell(
    String deviceId,
    List<String> args, {
    bool allowFail = false,
  }) async =>
      (await _adb(deviceId, ['shell', ...args], allowFail: allowFail)).stdout;

  Future<_CommandOutput> _run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    bool allowFail = false,
  }) async {
    if (verbose) stdout.writeln('RUN: $executable ${args.join(' ')}');
    final result = await Process.run(
      executable,
      args,
      workingDirectory: workingDirectory,
    );
    final output = _CommandOutput(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
    if (result.exitCode != 0 && !allowFail) {
      throw _CampaignFailure(
        _stage,
        '$executable failed (${result.exitCode}): '
        '${_lastLine(output.stderr + output.stdout)}',
      );
    }
    return output;
  }

  Future<_CommandOutput> _runStreaming(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    stdout.writeln('RUN: $executable ${args.join(' ')}');
    final process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
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
    await Future.wait([outDone, errDone]);
    if (exitCode != 0) {
      throw _CampaignFailure(
        _stage,
        '$executable failed ($exitCode): ${_lastLine(err.toString())}',
      );
    }
    return _CommandOutput(
      exitCode: exitCode,
      stdout: out.toString(),
      stderr: err.toString(),
    );
  }

  Future<String> _sha256(File file) async {
    final output = await _run('shasum', ['-a', '256', file.path]);
    return output.stdout.trim().split(RegExp(r'\s+')).first;
  }
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
  throw _CampaignFailure('wait', 'Timed out waiting for $label.');
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
  throw _CampaignFailure('wait', 'Timed out waiting for $label.');
}

String _shellJoin(List<String> args) => args.map(_shellQuote).join(' ');

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

String _lastLine(String value) {
  final lines = value.trim().split('\n');
  return lines.isEmpty ? '' : lines.last;
}

String _commandFailureSummary(_CommandOutput output) {
  final lines = '${output.stderr}\n${output.stdout}'
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  for (final line in lines.reversed) {
    if (line.contains('Failure') ||
        line.contains('Exception') ||
        line.contains('not enough space')) {
      return line;
    }
  }
  return lines.isEmpty ? 'exit ${output.exitCode}' : lines.last;
}

String _reactionFlowLines(String logcat) => logcat
    .split('\n')
    .where((line) => line.contains('REACTION_SEND_'))
    .join('\n');

String _backgroundPushFlowLines(String logcat) => logcat
    .split('\n')
    .where((line) => line.contains('PUSH_BACKGROUND_'))
    .join('\n');

String _notificationRouteLines(String logcat) =>
    sanitizeAndroidColdLocalNotificationRouteEvidence(logcat);

String _appNotificationRecords(String dump) {
  final section = dump.split(RegExp(r'\nRanking Config:')).first;
  return RegExp(r'NotificationRecord\([\s\S]*?(?=\n\s*NotificationRecord\(|$)')
      .allMatches(section)
      .map((match) => match.group(0)!)
      .where((record) => record.contains('pkg=com.mknoon.app'))
      .join('\n');
}

String? _valueFor(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == name && index + 1 < args.length) {
      return args[index + 1];
    }
    if (argument.startsWith('$name=')) {
      return argument.substring(name.length + 1);
    }
  }
  return null;
}

Uri? _parseRelayFixtureProbe(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'http' ||
      uri.host.isEmpty ||
      uri.port <= 0 ||
      !RegExp(r'^/[0-9a-f]{64}$').hasMatch(uri.path) ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}
