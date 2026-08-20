#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '_android_app_package.dart';
import 'reaction_notification_proof_support.dart';

const _defaultRelayTarget = 'ubuntu@mknoun.xyz';
const _defaultRelayKey = 'se.pem';
const _reactionEmoji = '👍';
const _androidBuildProfile = 'debug-android-arm64-split-v1';
const _providerObservationDelay = Duration(seconds: 10);

Future<void> main(List<String> args) async {
  final sender = _valueFor(args, '--sender');
  final recipient = _valueFor(args, '--recipient');
  final artifactPath = _valueFor(args, '--artifact-dir');
  final directTextOnly = args.contains('--direct-text-only');
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
      '[--direct-text-only '
      '--gate-a-artifact <gate-a-pass.json> '
      '--gate-a-artifact-sha256 <sha256>] '
      '[--reuse-working-tree-apks] [--verbose]',
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
    verbose: args.contains('--verbose'),
    keepBuildArtifacts: args.contains('--keep-build-artifacts'),
    liveTypedSmoke: args.contains('--live-typed-smoke'),
    durableBackgroundConnected: args.contains('--durable-background-connected'),
    reuseWorkingTreeApks: args.contains('--reuse-working-tree-apks'),
    directTextOnly: directTextOnly,
    gateAArtifact: gateAArtifact,
    gateAArtifactBytes: gateAArtifactBytes,
    gateAAuthorization: gateAAuthorization,
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
  });

  final String revision;
  final File e2eApk;
  final File normalApk;
  final String e2eApkSha256;
  final String normalApkSha256;
}

class _RelayInfo {
  const _RelayInfo({required this.version, required this.sha256});

  final String version;
  final String sha256;
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

class _HeadProvenanceCampaign {
  _HeadProvenanceCampaign({
    required this.senderId,
    required this.recipientId,
    required this.artifactDir,
    required this.sourceRoot,
    required this.relayTarget,
    required this.relayKey,
    required this.verbose,
    required this.keepBuildArtifacts,
    required this.liveTypedSmoke,
    required this.durableBackgroundConnected,
    required this.reuseWorkingTreeApks,
    required this.directTextOnly,
    required this.gateAArtifact,
    required this.gateAArtifactBytes,
    required this.gateAAuthorization,
  }) : sender = _Party(role: 'A', deviceId: senderId),
       recipient = _Party(role: 'B', deviceId: recipientId),
       appPackage = resolveAndroidAppPackage();

  final String senderId;
  final String recipientId;
  final Directory artifactDir;
  final Directory sourceRoot;
  final String relayTarget;
  final File relayKey;
  final bool verbose;
  final bool keepBuildArtifacts;
  final bool liveTypedSmoke;
  final bool durableBackgroundConnected;
  final bool reuseWorkingTreeApks;
  final bool directTextOnly;
  final File? gateAArtifact;
  final List<int>? gateAArtifactBytes;
  Map<String, Object?>? gateAAuthorization;
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
      : liveTypedSmoke
      ? 'android_typed_reaction_smoke'
      : durableBackgroundConnected
      ? 'android_durable_reaction_background_connected'
      : 'head_provenance';

  String get _scenario => directTextOnly
      ? 'android_direct_text_public_relay'
      : liveTypedSmoke
      ? 'android_typed_reaction_smoke'
      : durableBackgroundConnected
      ? 'android_durable_reaction_background_connected'
      : 'head_provenance';

  String get _testCase => directTextOnly
      ? 'TC-DIRECT-TEXT-PUBLIC-RELAY'
      : liveTypedSmoke
      ? 'TC-13-core-smoke'
      : durableBackgroundConnected
      ? 'TC-DURABLE-DIRECT-REACTION'
      : 'TC-00';

  /// Every variant except TC-00 grades the WORKING TREE. TC-00 alone builds
  /// clean HEAD, which is what its `cleanCurrentBuild` claim means.
  bool get _workingTreeBuild =>
      liveTypedSmoke || directTextOnly || durableBackgroundConnected;

  /// The variants whose card must carry the typed reaction copy rather than the
  /// generic "New Message" fallback.
  bool get _typedCopyRequired => liveTypedSmoke || durableBackgroundConnected;

  Future<void> run() async {
    _CampaignFailure? primaryFailure;
    StackTrace? primaryStackTrace;
    _CampaignFailure? cleanupFailure;
    try {
      _stage = 'preflight';
      await _verifyEnvironment();
      final relayInfo = await _readRelayInfo();
      if (directTextOnly) {
        await _captureInitialDeviceState();
      }

      _stage = _workingTreeBuild ? 'working_tree_build' : 'clean_head_build';
      _build = _workingTreeBuild
          ? reuseWorkingTreeApks
                ? await _reuseWorkingTreeApks()
                : await _buildWorkingTreeApks()
          : await _buildCleanHeadApks();

      _stage = 'e2e_setup';
      if (directTextOnly) {
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
      await _prepareE2EParty(sender, 'TC256-A');
      await _prepareE2EParty(recipient, 'TC256-B');
      await _launch(senderId);
      await _launch(recipientId);
      await _collectIdentity(sender);
      await _collectIdentity(recipient);
      await _prepopulateContacts();
      String? messageMarker;
      String? messageId;
      if (!directTextOnly) {
        messageMarker =
            'TC256-${DateTime.now().toUtc().microsecondsSinceEpoch}';
        messageId = await _seedIncomingMessage(messageMarker);
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
      if (durableBackgroundConnected) {
        await _backgroundRecipient();
      } else {
        await _terminateRecipient();
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

      if (!directTextOnly) {
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
        final durableEvidence = File(
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
      if (directTextOnly && !_exactRestorationComplete) {
        await _restoreExactInitialDeviceState();
      } else {
        if (!directTextOnly) await _restoreNormalBuilds();
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
    if (!relayKey.existsSync()) {
      throw _CampaignFailure(
        _stage,
        'Relay SSH key is unavailable at ${relayKey.path}.',
        environmentBlocked: true,
      );
    }
    final ssh = await _ssh(['systemctl', 'is-active', 'relay-server']);
    if (ssh.stdout.trim() != 'active') {
      throw _CampaignFailure(
        _stage,
        'Relay service is not active on the configured capture target.',
        environmentBlocked: true,
      );
    }
  }

  Future<_RelayInfo> _readRelayInfo() async {
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
    if (!builtApk.existsSync()) {
      throw _CampaignFailure(
        _stage,
        'Working-tree normal APK did not materialize.',
      );
    }
    final normalApk = await builtApk.copy(normalTarget.path);
    final result = _BuildArtifacts(
      revision: revision,
      e2eApk: e2eApk,
      normalApk: normalApk,
      e2eApkSha256: await _sha256(e2eApk),
      normalApkSha256: await _sha256(normalApk),
    );
    File('${artifactDir.path}/working_tree_build.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'revision': revision,
        'buildProfile': _androidBuildProfile,
        'dirtyAtBuild': status.stdout.trim().isNotEmpty,
        'directTextRelayTokenProof': directTextOnly,
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
    final initialDump = await _uiDump(recipientId);
    final initialEditor = findNodeBoundsByClass(
      initialDump,
      'android.widget.EditText',
    );
    if (initialEditor == null) {
      throw _CampaignFailure(
        _stage,
        'The recipient conversation did not expose its compose editor.',
      );
    }
    await _adbShell(recipientId, [
      'input',
      'tap',
      '${(initialEditor.$1 + initialEditor.$3) ~/ 2}',
      '${(initialEditor.$2 + initialEditor.$4) ~/ 2}',
    ]);
    await _adbShell(recipientId, ['input', 'text', marker]);
    await _waitForUiText(recipientId, marker, const Duration(seconds: 10));

    final typedDump = await _uiDump(recipientId);
    final typedEditor = findNodeBoundsByClass(
      typedDump,
      'android.widget.EditText',
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
    await _writeAppFile(
      owner.deviceId,
      'intro_e2e_config.json',
      jsonEncode({
        'stepId':
            '256-head-${owner.role.toLowerCase()}-fixture-'
            '${DateTime.now().microsecondsSinceEpoch}',
        'add_contacts': [_contactEntry(contact)],
      }),
    );
    // The clean app's startup fixture inserts contacts before runApp. Relaunch
    // once with the fixture, remove it before the delayed action poller can own
    // it, then relaunch without a pending diagnostic action.
    await _launch(owner.deviceId);
    await _deleteAppFile(owner.deviceId, 'intro_e2e_config.json');
    await _deleteAppFile(owner.deviceId, 'intro_e2e_result.json');
    await _launch(owner.deviceId);
  }

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
      final allChats = findSemanticNodeCenter(dump, 'Show all chats');
      if (allChats == null) {
        throw _CampaignFailure(
          _stage,
          'Could not find the direct chat or chat-list entry point on ${owner.role}.',
        );
      }
      await _adbShell(owner.deviceId, [
        'input',
        'tap',
        '${allChats.$1}',
        '${allChats.$2}',
      ]);
      final contact = await _waitForBounds(
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
        (await _adb(recipientId, ['logcat', '-d', '-v', 'brief'])).stdout,
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
      final title = findSemanticNodeCenter(xml, card.title);
      final body = findSemanticNodeCenter(xml, card.body);
      if (title != null && body != null) return body;
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
        'reusedPrebuiltCandidate': reuseWorkingTreeApks,
        'apkSha256': build.normalApkSha256,
        'senderHarnessApkSha256': build.e2eApkSha256,
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

  Future<String> _notificationDump(String deviceId) async =>
      _adbShell(deviceId, ['dumpsys', 'notification', '--noredact']);

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
    await _adbShell(deviceId, ['uiautomator', 'dump', remote], allowFail: true);
    final xml = await _adbShell(deviceId, ['cat', remote], allowFail: true);
    await _adbShell(deviceId, ['rm', '-f', remote], allowFail: true);
    return xml;
  }

  (int, int)? _boundsForText(String xml, String target) {
    return findSemanticNodeCenter(xml, target);
  }

  Future<String> _relayJournalSince(DateTime since) async {
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
