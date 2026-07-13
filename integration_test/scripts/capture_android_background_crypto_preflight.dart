#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '_android_app_package.dart';
import 'reaction_notification_proof_support.dart';

const _target = 'integration_test/android_background_crypto_preflight_app.dart';
const _requestFile = 'files/tc256_reaction_preflight_request.json';
const _cleanupIndexFile = 'files/tc256_cleanup_index.json';
const _postForegroundMarker = 'files/tc256_post_foreground';
const _clearNotificationsMarker = 'files/tc256_clear_notifications';
const _fcmRefreshCommand = 'files/tc256_fcm_refresh_command.json';
const _cleanupCommandSchema = 'mknoon.tc256-cleanup-command.v1';
const _debugApkPath = 'build/app/outputs/flutter-apk/app-debug.apk';
const _defaultServiceAccount =
    'mknoon-c6e62-firebase-adminsdk-fbsvc-70e1a8d4fb.json';
const _postNotificationsPermission = 'android.permission.POST_NOTIFICATIONS';

Future<void> main(List<String> args) async {
  final cleanupOnly = args.contains('--cleanup-only');
  final setupOnly = args.contains('--setup-only');
  final ordinaryOnly = args.contains('--ordinary-only');
  final resetOnly = args.contains('--reset-only');
  final providerDiagnosticOnly = args.contains('--provider-diagnostic-only');
  final refreshUnregisteredToken = args.contains(
    '--refresh-unregistered-token',
  );
  final priorProviderDiagnosticPath = _valueFor(
    args,
    '--prior-provider-diagnostic',
  );
  if (<bool>[
        cleanupOnly,
        setupOnly,
        ordinaryOnly,
        resetOnly,
        providerDiagnosticOnly,
      ].where((value) => value).length >
      1) {
    stderr.writeln(
      '--cleanup-only, --setup-only, --ordinary-only, --reset-only, and '
      '--provider-diagnostic-only are mutually exclusive',
    );
    exit(64);
  }
  if ((refreshUnregisteredToken &&
          (!providerDiagnosticOnly || priorProviderDiagnosticPath == null)) ||
      (!refreshUnregisteredToken && priorProviderDiagnosticPath != null)) {
    stderr.writeln(
      '--refresh-unregistered-token requires --provider-diagnostic-only and '
      '--prior-provider-diagnostic <completed-unregistered-artifact>',
    );
    exit(64);
  }
  if (args.contains('--dry-run')) {
    stdout.writeln(
      const JsonEncoder.withIndent(' ').convert(
        backgroundCryptoPreflightDryRunManifest(
          cleanupOnly: cleanupOnly,
          setupOnly: setupOnly,
          ordinaryOnly: ordinaryOnly,
          resetOnly: resetOnly,
          providerDiagnosticOnly: providerDiagnosticOnly,
          refreshUnregisteredToken: refreshUnregisteredToken,
        ),
      ),
    );
    return;
  }
  String? priorProviderDiagnosticSha256;
  String? priorProviderSubjectTokenSha256;
  DateTime? priorProviderDiagnosticCapturedAt;
  if (refreshUnregisteredToken) {
    try {
      final priorFile = File(priorProviderDiagnosticPath!);
      final priorStat = priorFile.statSync();
      if (priorStat.type != FileSystemEntityType.file ||
          priorStat.size <= 0 ||
          priorStat.size > 64 * 1024) {
        throw const FormatException('prior provider artifact size rejected');
      }
      final priorBytes = priorFile.readAsBytesSync();
      final authorization =
          parseBackgroundCryptoUnregisteredDiagnosticAuthorization(
            jsonDecode(utf8.decode(priorBytes, allowMalformed: false)),
            now: DateTime.now().toUtc(),
          );
      priorProviderDiagnosticSha256 = sha256.convert(priorBytes).toString();
      priorProviderSubjectTokenSha256 =
          authorization['subjectTokenSha256']! as String;
      priorProviderDiagnosticCapturedAt = DateTime.parse(
        authorization['capturedAt']! as String,
      );
    } on Object {
      stderr.writeln(
        'Prior provider diagnostic is not exact sanitized UNREGISTERED '
        'authorization.',
      );
      exit(64);
    }
  }
  final recipient = _valueFor(args, '--recipient');
  final artifactPath = _valueFor(args, '--artifact-dir');
  if (recipient == null || artifactPath == null) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/'
      'capture_android_background_crypto_preflight.dart '
      '--recipient <android-id> --artifact-dir <dir> '
      '[--service-account <file>] '
      '[--cleanup-only|--setup-only|--ordinary-only|--reset-only|'
      '--provider-diagnostic-only] [--refresh-unregistered-token '
      '--prior-provider-diagnostic <artifact>] [--verbose]\n'
      'or: ... --dry-run (no build, device, provider, or secret access)',
    );
    exit(64);
  }

  final campaign = _Campaign(
    recipient: recipient,
    artifactDir: Directory(artifactPath)..createSync(recursive: true),
    serviceAccount: File(
      _valueFor(args, '--service-account') ??
          Platform.environment['FIREBASE_SERVICE_ACCOUNT'] ??
          _defaultServiceAccount,
    ).absolute,
    verbose: args.contains('--verbose'),
    cleanupOnly: cleanupOnly,
    setupOnly: setupOnly,
    ordinaryOnly: ordinaryOnly,
    resetOnly: resetOnly,
    providerDiagnosticOnly: providerDiagnosticOnly,
    refreshUnregisteredToken: refreshUnregisteredToken,
    priorProviderDiagnosticSha256: priorProviderDiagnosticSha256,
    priorProviderSubjectTokenSha256: priorProviderSubjectTokenSha256,
    priorProviderDiagnosticCapturedAt: priorProviderDiagnosticCapturedAt,
  );
  try {
    await campaign.run();
  } on _CampaignCompositeFailure catch (failure) {
    campaign.writeFailure(failure);
    stderr.writeln('TC-07 PREFLIGHT FAILED [${failure.verdict}]');
    exit(failure.exitCode);
  } on Object catch (error) {
    final failure = _CampaignCompositeFailure(
      primary: _CampaignFailure(
        campaign.stage,
        'unexpected controller failure',
        type: error.runtimeType.toString(),
      ),
    );
    campaign.writeFailure(failure);
    stderr.writeln('TC-07 PREFLIGHT FAILED [${failure.verdict}]');
    exit(failure.exitCode);
  }
}

class _CampaignFailure implements Exception {
  const _CampaignFailure(
    this.stage,
    this.message, {
    this.environmentBlocked = false,
    String? type,
    this.setupReason,
    this.setupPhase,
    this.cleanupReason,
    this.cleanupPhase,
    this.campaignReason,
    this.campaignPhase,
    this.syntheticCaseId,
    this.notificationClearReason,
    this.notificationClearPhase,
    this.notificationClearBoundary,
    this.notificationClearObservation,
    this.postClearReason,
    this.postClearBoundary,
    this.postClearObservation,
    this.postClearPollCount,
    this.postClearBaselineCount,
    this.postClearBaselineHash,
  }) : type = type ?? '_CampaignFailure';

  final String stage;
  final String message;
  final bool environmentBlocked;
  final String type;
  final BackgroundCryptoSetupReason? setupReason;
  final BackgroundCryptoSetupPhase? setupPhase;
  final BackgroundCryptoCleanupReason? cleanupReason;
  final BackgroundCryptoCleanupPhase? cleanupPhase;
  final BackgroundCryptoCampaignReason? campaignReason;
  final BackgroundCryptoCampaignPhase? campaignPhase;
  final String? syntheticCaseId;
  final BackgroundCryptoNotificationClearReason? notificationClearReason;
  final BackgroundCryptoNotificationClearPhase? notificationClearPhase;
  final BackgroundCryptoNotificationClearBoundary? notificationClearBoundary;
  final BackgroundCryptoNotificationClearObservation?
  notificationClearObservation;
  final BackgroundCryptoPostClearReason? postClearReason;
  final BackgroundCryptoPostClearBoundary? postClearBoundary;
  final BackgroundCryptoPostClearObservation? postClearObservation;
  final int? postClearPollCount;
  final int? postClearBaselineCount;
  final String? postClearBaselineHash;

  BackgroundCryptoFailureRecord toRecord() {
    final safeSetupPhase =
        setupPhase ??
        (stage == 'setup' ? BackgroundCryptoSetupPhase.appInit : null);
    final candidateReason =
        setupReason ??
        (stage == 'setup' ? BackgroundCryptoSetupReason.operationFailed : null);
    final safeSetupReason = safeSetupPhase == null || candidateReason == null
        ? candidateReason
        : backgroundCryptoTerminalSetupReason(
            phase: safeSetupPhase,
            reason: candidateReason,
          );
    return BackgroundCryptoFailureRecord(
      stage: stage,
      type: type,
      environmentBlocked: environmentBlocked,
      setupReason: safeSetupReason,
      setupPhase: safeSetupPhase,
      cleanupReason: cleanupReason,
      cleanupPhase: cleanupPhase,
      campaignReason: campaignReason,
      campaignPhase: campaignPhase,
      syntheticCaseId: syntheticCaseId,
      notificationClearReason: notificationClearReason,
      notificationClearPhase: notificationClearPhase,
      notificationClearBoundary: notificationClearBoundary,
      notificationClearObservation: notificationClearObservation,
      postClearReason: postClearReason,
      postClearBoundary: postClearBoundary,
      postClearObservation: postClearObservation,
      postClearPollCount: postClearPollCount,
      postClearBaselineCount: postClearBaselineCount,
      postClearBaselineHash: postClearBaselineHash,
    );
  }
}

class _CampaignCompositeFailure implements Exception {
  const _CampaignCompositeFailure({
    this.primary,
    this.cleanup,
    this.restoration,
  });

  final _CampaignFailure? primary;
  final _CampaignFailure? cleanup;
  final _CampaignFailure? restoration;

  String get verdict => backgroundCryptoCompositeFailureVerdict(
    primary: primary?.toRecord(),
    cleanup: cleanup?.toRecord(),
    restoration: restoration?.toRecord(),
  );

  int get exitCode => backgroundCryptoCompositeExitCode(
    primary: primary?.toRecord(),
    cleanup: cleanup?.toRecord(),
    restoration: restoration?.toRecord(),
  );
}

class _CommandOutput {
  const _CommandOutput(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

class _ProcessAndTaskAbsenceTimeout implements Exception {
  const _ProcessAndTaskAbsenceTimeout();
}

({BackgroundCryptoSetupPhase phase, BackgroundCryptoSetupReason reason})
_redactedSetupDiagnostic(
  Map<String, dynamic>? marker, {
  BackgroundCryptoSetupPhase fallbackPhase = BackgroundCryptoSetupPhase.appInit,
  BackgroundCryptoSetupReason fallbackReason =
      BackgroundCryptoSetupReason.operationFailed,
}) {
  final phase =
      backgroundCryptoSetupPhaseFromWire(marker?['phase']) ?? fallbackPhase;
  final parsedReason = marker?.containsKey('reason') == true
      ? backgroundCryptoSetupReasonFromWire(marker?['reason'])
      : fallbackReason;
  return (
    phase: phase,
    reason: backgroundCryptoTerminalSetupReason(
      phase: phase,
      reason: parsedReason,
    ),
  );
}

class _Campaign {
  _Campaign({
    required this.recipient,
    required this.artifactDir,
    required this.serviceAccount,
    required this.verbose,
    required this.cleanupOnly,
    required this.setupOnly,
    required this.ordinaryOnly,
    required this.resetOnly,
    required this.providerDiagnosticOnly,
    required this.refreshUnregisteredToken,
    required this.priorProviderDiagnosticSha256,
    required this.priorProviderSubjectTokenSha256,
    required this.priorProviderDiagnosticCapturedAt,
  }) : appPackage = resolveAndroidAppPackage();

  final String recipient;
  final Directory artifactDir;
  final File serviceAccount;
  final bool verbose;
  final bool cleanupOnly;
  final bool setupOnly;
  final bool ordinaryOnly;
  final bool resetOnly;
  final bool providerDiagnosticOnly;
  final bool refreshUnregisteredToken;
  final String? priorProviderDiagnosticSha256;
  final String? priorProviderSubjectTokenSha256;
  final DateTime? priorProviderDiagnosticCapturedAt;
  final String appPackage;

  String stage = 'preflight';
  Directory? _secretTempDir;
  Directory? _installedAppBackupDir;
  final List<File> _installedAppApks = <File>[];
  final List<String> _restoredInstalledApkHashes = <String>[];
  File? _localApkBackup;
  bool _localApkExisted = false;
  bool _backupCaptured = false;
  bool _replacementAttempted = false;
  bool _preflightInstalled = false;
  bool _syntheticCleanupConfirmed = false;
  bool _privateProviderTempDeleted = false;
  String _eventId = '';
  String _targetMessageId = '';
  late String _androidTargetPlatform;
  late int _androidSdk;
  bool _notificationPermissionCaptured = false;
  bool _notificationPermissionInitiallyGranted = false;
  bool _setupReady = false;
  BackgroundCryptoSetupPhase? _lastSetupPhase;
  BackgroundCryptoCleanupPhase? _lastCleanupPhase;
  BackgroundCryptoCampaignPhase? _currentCampaignPhase;
  BackgroundCryptoNotificationClearPhase? _lastNotificationClearPhase;
  bool _notificationClearCommandAcknowledged = false;
  String? _currentSyntheticCaseId;
  int _providerRequestsAttempted = 0;
  int _providerRequestsSucceeded = 0;
  int _providerValidationAttempts = 0;
  int _providerValidationSucceeded = 0;
  Map<String, Object?>? _lastProviderDiagnostic;
  String? _fcmRefreshGenerationId;
  DateTime? _fcmRefreshIssuedAt;
  Map<String, Object?>? _tokenRegistrationEvidence;
  final List<Map<String, Object?>> _providerReceiptEvidence =
      <Map<String, Object?>>[];
  final List<Map<String, Object?>> _providerDeliveryEligibilityEvidence =
      <Map<String, Object?>>[];
  int _reactionRowsExecuted = 0;
  final List<Map<String, Object?>> _successfulCleanupEvidence =
      <Map<String, Object?>>[];
  Map<String, Object?>? _successfulRestorationEvidence;
  Set<int> _baselineNotificationIds = <int>{};
  final List<Map<String, Object?>> _resetBaselineEvidence =
      <Map<String, Object?>>[];
  final List<Map<String, int>> _notificationClearOwnershipEvidence =
      <Map<String, int>>[];
  final List<Map<String, Object?>> _ordinaryEvidence = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _negativeAuthorizationEvidence =
      <Map<String, Object?>>[];
  final List<String> _capturedSafeMarkerLines = <String>[];
  final Map<String, int> _conversationNotificationIds = <String, int>{};
  final Map<String, int> _ordinaryContextCounts = <String, int>{};

  void _enterCampaignPhase(
    BackgroundCryptoCampaignPhase phase,
    String syntheticCaseId,
  ) {
    if (!isBackgroundCryptoSyntheticCaseId(syntheticCaseId)) {
      throw StateError('unreserved synthetic campaign case');
    }
    _currentCampaignPhase = phase;
    _currentSyntheticCaseId = syntheticCaseId;
  }

  _CampaignFailure _campaignFailure(
    BackgroundCryptoCampaignReason reason,
    String message,
  ) {
    final phase = _currentCampaignPhase;
    final caseId = _currentSyntheticCaseId;
    if (phase == null ||
        caseId == null ||
        !isBackgroundCryptoSyntheticCaseId(caseId)) {
      throw StateError('campaign failure is missing finite context');
    }
    return _CampaignFailure(
      stage,
      message,
      campaignReason: reason,
      campaignPhase: phase,
      syntheticCaseId: caseId,
    );
  }

  _CampaignFailure _postClearFailure({
    required BackgroundCryptoPostClearReason reason,
    required BackgroundCryptoPostClearBoundary boundary,
    required BackgroundCryptoPostClearObservation observation,
    required String message,
    int? pollCount,
    BackgroundCryptoNotificationResetSnapshot? lastBaseline,
  }) {
    final phase = _currentCampaignPhase;
    final caseId = _currentSyntheticCaseId;
    return _CampaignFailure(
      stage,
      message,
      campaignReason: phase == null
          ? null
          : BackgroundCryptoCampaignReason.cardVerificationFailed,
      campaignPhase: phase,
      syntheticCaseId: phase == null ? null : caseId,
      postClearReason: reason,
      postClearBoundary: boundary,
      postClearObservation: observation,
      postClearPollCount: pollCount,
      postClearBaselineCount: lastBaseline?.baselineIds.length,
      postClearBaselineHash: lastBaseline?.baselineHash,
    );
  }

  Future<void> run() async {
    _CampaignFailure? primaryFailure;
    try {
      await _runPrimary();
    } on _CampaignFailure catch (failure) {
      primaryFailure = failure;
    } on Object catch (error) {
      final diagnostic = backgroundCryptoHostSetupFailure(
        lastObservedPhase: _lastSetupPhase,
      );
      final cleanupPhase = _lastCleanupPhase;
      final campaignPhase = _currentCampaignPhase;
      primaryFailure = _CampaignFailure(
        stage,
        'unexpected primary campaign failure',
        type: stage == 'setup' || cleanupPhase != null || campaignPhase != null
            ? '_CampaignFailure'
            : error.runtimeType.toString(),
        setupReason: stage == 'setup' ? diagnostic.reason : null,
        setupPhase: stage == 'setup' ? diagnostic.phase : null,
        cleanupReason: cleanupPhase == null
            ? null
            : BackgroundCryptoCleanupReason.operationFailed,
        cleanupPhase: cleanupPhase,
        campaignReason: campaignPhase == null
            ? null
            : BackgroundCryptoCampaignReason.operationFailed,
        campaignPhase: campaignPhase,
        syntheticCaseId: campaignPhase == null ? null : _currentSyntheticCaseId,
        notificationClearReason: _lastNotificationClearPhase == null
            ? null
            : BackgroundCryptoNotificationClearReason.operationFailed,
        notificationClearPhase: _lastNotificationClearPhase,
        notificationClearBoundary: _lastNotificationClearPhase == null
            ? null
            : BackgroundCryptoNotificationClearBoundary.appPhase,
        notificationClearObservation: _lastNotificationClearPhase == null
            ? null
            : BackgroundCryptoNotificationClearObservation.observed,
      );
    }

    if (primaryFailure != null) {
      try {
        // Persist finite diagnostics and counters before recovery clears logs.
        // The final composite artifact later replaces this checkpoint.
        writeFailure(_CampaignCompositeFailure(primary: primaryFailure));
      } on Object {
        // Artifact I/O must never bypass unconditional cleanup/restoration.
      }
    }

    var cleanupFailure = await _attemptPreRestorationCleanup();
    final restorationFailure = await _attemptOutermostRestoration();
    if (primaryFailure != null ||
        cleanupFailure != null ||
        restorationFailure != null) {
      final staleArtifactFailure = await _deleteStalePassArtifacts();
      cleanupFailure ??= staleArtifactFailure;
      throw _CampaignCompositeFailure(
        primary: primaryFailure,
        cleanup: cleanupFailure,
        restoration: restorationFailure,
      );
    }

    try {
      await _recordRestorationSuccess();
    } on _CampaignFailure catch (failure) {
      final staleFailure = await _deleteStalePassArtifacts();
      throw _CampaignCompositeFailure(
        cleanup: staleFailure,
        restoration: failure,
      );
    } on Object catch (error) {
      final staleFailure = await _deleteStalePassArtifacts();
      throw _CampaignCompositeFailure(
        cleanup: staleFailure,
        restoration: _CampaignFailure(
          'finalize_restoration_evidence',
          'failed to finalize restoration evidence',
          type: error.runtimeType.toString(),
        ),
      );
    }
    final restoredArtifact = File(_passArtifactPath);
    if (await restoredArtifact.exists()) {
      stdout.writeln(
        'PASS: TC-07 ${cleanupOnly
            ? 'cleanup'
            : setupOnly
            ? 'setup'
            : resetOnly
            ? 'reset'
            : providerDiagnosticOnly
            ? 'provider diagnostic'
            : 'preflight'} captured at '
        '${restoredArtifact.path}',
      );
    }
  }

  Future<void> _runPrimary() async {
    stage = 'preflight';
    await _requireDevice();
    if (!cleanupOnly &&
        !setupOnly &&
        !resetOnly &&
        !serviceAccount.existsSync()) {
      throw _CampaignFailure(
        stage,
        'Firebase service account is unavailable.',
        environmentBlocked: true,
      );
    }
    if (!cleanupOnly && !setupOnly && !resetOnly) {
      final credentialMode = serviceAccount.statSync().mode & 0x1ff;
      if (credentialMode != 0x180) {
        throw _CampaignFailure(
          stage,
          'Firebase service account must be mode 0600.',
          environmentBlocked: true,
        );
      }
    }

    stage = 'backup_installed_app';
    await _backupInstalledApp();

    stage = 'build';
    await _runChecked('flutter', [
      'build',
      'apk',
      '--debug',
      '--target',
      _target,
      if (ordinaryOnly || resetOnly || providerDiagnosticOnly)
        '--dart-define=MKNOON_TC256_ORDINARY_ONLY=true',
      '--target-platform',
      _androidTargetPlatform,
    ]);
    final apk = File(_debugApkPath);
    if (!apk.existsSync()) {
      throw _CampaignFailure(stage, 'preflight APK was not produced');
    }

    stage = 'setup';
    _replacementAttempted = true;
    await _adb(['install', '-r', '-t', '-d', apk.absolute.path]);
    _preflightInstalled = true;
    if (!cleanupOnly && _androidSdk >= 33) {
      await _adbShell([
        'pm',
        'grant',
        appPackage,
        _postNotificationsPermission,
      ]);
    }
    await _runAs([
      'rm',
      '-f',
      _postForegroundMarker,
      _clearNotificationsMarker,
      _fcmRefreshCommand,
    ], allowFailure: true);

    if (cleanupOnly) {
      stage = 'cleanup_only';
      final cleanupLog = await _runCleanupCommand(mode: 'cleanup-only');
      await _verifyPrivateBundleAbsent();
      _syntheticCleanupConfirmed = true;
      await _writeCleanupOnlyArtifact(cleanupLog);
      return;
    }

    if (refreshUnregisteredToken) {
      await _stageFcmRefreshCommand();
    }
    await _prepareFixtureColdLaunch();
    final setupLog = await _waitForLog(
      (log) =>
          log.contains('MKNOON_256_CRYPTO_PREFLIGHT') &&
          log.contains('"event":"ready"') &&
          !log.contains('"postForeground":true'),
      timeout: const Duration(minutes: 2),
      description: 'redacted preflight-ready marker',
    );
    if (setupLog.contains('"event":"setup_error"')) {
      final marker = _latestPreflightMarker(setupLog, event: 'setup_error');
      final diagnostic = _redactedSetupDiagnostic(marker);
      throw _CampaignFailure(
        stage,
        'device fixture setup reported an error',
        setupReason: diagnostic.reason,
        setupPhase: diagnostic.phase,
      );
    }

    _lastSetupPhase = BackgroundCryptoSetupPhase.bundleValidation;
    final requestRaw = await _runAs([
      'cat',
      _requestFile,
    ], suppressVerbose: true);
    final decodedRequest = jsonDecode(requestRaw.stdout);
    if (decodedRequest is! Map) {
      throw _CampaignFailure(
        stage,
        'private fixture bundle is not an object',
        setupReason: BackgroundCryptoSetupReason.schemaGuard,
        setupPhase: BackgroundCryptoSetupPhase.bundleValidation,
      );
    }
    final request = decodedRequest.cast<String, dynamic>();
    final bundleErrors = validateBackgroundCryptoPreflightBundle(
      request,
      requireReaction: !(ordinaryOnly || resetOnly || providerDiagnosticOnly),
    );
    if (bundleErrors.isNotEmpty) {
      throw _CampaignFailure(
        stage,
        'private fixture bundle failed ${bundleErrors.length} contract checks',
        setupReason: BackgroundCryptoSetupReason.schemaGuard,
        setupPhase: BackgroundCryptoSetupPhase.bundleValidation,
      );
    }
    try {
      final parsedObservation = parseBackgroundCryptoFcmTokenObservation(
        request,
        expectedGenerationId: _fcmRefreshGenerationId,
        expectedPriorTokenSha256: refreshUnregisteredToken
            ? priorProviderSubjectTokenSha256
            : null,
        requireForcedRefresh: refreshUnregisteredToken,
        now: DateTime.now().toUtc(),
      );
      if (refreshUnregisteredToken) {
        final issuedAt = _fcmRefreshIssuedAt;
        final observedAt = DateTime.tryParse(
          parsedObservation['observedAt']?.toString() ?? '',
        );
        if (issuedAt == null || observedAt == null) {
          throw const FormatException('FCM command age evidence is missing');
        }
        final age = observedAt.difference(issuedAt);
        if (age.isNegative || age > const Duration(seconds: 165)) {
          throw const FormatException('FCM command age evidence is invalid');
        }
        _tokenRegistrationEvidence = <String, Object?>{
          ...parsedObservation,
          'commandIssuedAt': issuedAt.toIso8601String(),
          'commandAgeAtObservationMs': age.inMilliseconds,
        };
      } else {
        _tokenRegistrationEvidence = parsedObservation;
      }
    } on FormatException {
      throw _CampaignFailure(
        stage,
        'private FCM token freshness evidence failed validation',
        setupReason: BackgroundCryptoSetupReason.schemaGuard,
        setupPhase: BackgroundCryptoSetupPhase.bundleValidation,
      );
    }
    _setupReady = true;
    if (setupOnly) {
      _persistSetupReadyCheckpoint();
    }
    if (setupOnly) {
      stage = 'setup_only_cleanup';
      final cleanupLog = await _runCleanupCommand(mode: 'setup-only');
      await _verifyPrivateBundleAbsent();
      _syntheticCleanupConfirmed = true;
      await _writeSetupOnlyArtifact(cleanupLog);
      return;
    }
    if (resetOnly) {
      stage = 'reset_only';
      _enterCampaignPhase(
        BackgroundCryptoCampaignPhase.cardVerify,
        'direct-text',
      );
      await _captureNotificationBaseline();
      await _clearSyntheticCards();
      stage = 'reset_only_cleanup';
      final cleanupLog = await _runCleanupCommand(mode: 'recovery');
      await _verifyPrivateBundleAbsent();
      _syntheticCleanupConfirmed = true;
      await _writeResetOnlyArtifact(cleanupLog);
      return;
    }
    final token = request['token']! as String;
    final ordinaryCases = (request['ordinaryCases']! as List)
        .map((value) => (value as Map).cast<String, dynamic>())
        .toList(growable: false);
    final negativeCases = (request['negativeCases']! as List)
        .map((value) => (value as Map).cast<String, dynamic>())
        .toList(growable: false);
    if (providerDiagnosticOnly) {
      await _runProviderDiagnosticOnly(
        token: token,
        testCase: ordinaryCases.first,
      );
      return;
    }
    Map<String, dynamic>? reactionData;
    if (!ordinaryOnly) {
      final reaction = request['reaction'];
      final candidate = reaction is Map ? reaction['data'] : null;
      if (candidate is! Map || candidate['type'] != 'message_reaction') {
        throw _CampaignFailure(
          stage,
          'private reaction request is incomplete',
          setupReason: BackgroundCryptoSetupReason.schemaGuard,
          setupPhase: BackgroundCryptoSetupPhase.bundleValidation,
        );
      }
      reactionData = candidate.cast<String, dynamic>();
      _eventId = reactionData['event_id']?.toString() ?? '';
      _targetMessageId = reactionData['target_message_id']?.toString() ?? '';
      if (_eventId.isEmpty || _targetMessageId.isEmpty) {
        throw _CampaignFailure(
          stage,
          'reaction identity is incomplete',
          setupReason: BackgroundCryptoSetupReason.schemaGuard,
          setupPhase: BackgroundCryptoSetupPhase.bundleValidation,
        );
      }
    }

    stage = 'provider_preflight';
    final firstCaseId = ordinaryOnly
        ? ordinaryCases.first['id']! as String
        : 'reaction';
    _enterCampaignPhase(
      BackgroundCryptoCampaignPhase.requestPrepare,
      firstCaseId,
    );
    try {
      _secretTempDir = await Directory.systemTemp.createTemp(
        'mknoon-tc256-fcm-',
      );
      await _captureNotificationBaseline();
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.requestPrepareFailed,
        'campaign request workspace preparation failed',
      );
    }

    DateTime? reactionSentAt;
    if (!ordinaryOnly) {
      reactionSentAt = await _exerciseLegacyReaction(
        token: token,
        data: reactionData!,
      );
      await _runNegativeAuthorizationMatrix(
        token: token,
        negativeCases: negativeCases,
      );
      await _runOrdinaryMatrix(token: token, ordinaryCases: ordinaryCases);
    } else {
      await _runOrdinaryMatrix(token: token, ordinaryCases: ordinaryCases);
      await _runNegativeAuthorizationMatrix(
        token: token,
        negativeCases: negativeCases,
      );
    }

    stage = 'post_foreground_callback';
    _currentCampaignPhase = null;
    _currentSyntheticCaseId = null;
    final foregroundLog = await _runCleanupCommand(
      mode: 'post-proof',
      requirePostProofNode: true,
    );
    await _verifyPrivateBundleAbsent();
    _syntheticCleanupConfirmed = true;
    _lastCleanupPhase = null;

    stage = 'artifact';
    final filteredLines = <String>[
      ..._capturedSafeMarkerLines,
      ..._safeMarkerLines(foregroundLog),
    ];
    final flowEvidence = File(
      '${artifactDir.path}/android_background_crypto_preflight_flow.log',
    );
    await flowEvidence.writeAsString(
      '${filteredLines.toSet().join('\n')}\n',
      flush: true,
    );
    final capturedAt = DateTime.now().toUtc();
    final artifact = <String, Object?>{
      'testCase': 'TC-07',
      'scenario': 'android_background_crypto_preflight',
      'status': 'passed',
      'capturedAt': capturedAt.toIso8601String(),
      'mode': ordinaryOnly ? 'ordinary-only' : 'full',
      'setupReady': true,
      'reactionRows': ordinaryOnly ? 0 : 1,
      'reactionRowsExecuted': _reactionRowsExecuted,
      'ordinaryCasesPlanned': backgroundCryptoPreflightOrdinaryRows.length,
      'ordinaryCasesExecuted': _ordinaryEvidence.length,
      'negativeCasesPlanned': backgroundCryptoPreflightNegativeRows.length,
      'negativeCasesExecuted': _negativeAuthorizationEvidence.length,
      'providerRequestsAttempted': _providerRequestsAttempted,
      'providerRequestsSucceeded': _providerRequestsSucceeded,
      'providerReceipts': List<Map<String, Object?>>.unmodifiable(
        _providerReceiptEvidence,
      ),
      'providerDeliveryEligibility': List<Map<String, Object?>>.unmodifiable(
        _providerDeliveryEligibilityEvidence,
      ),
      'caseExecutionOrder': backgroundCryptoCampaignCaseOrder(
        ordinaryOnly: ordinaryOnly,
      ),
      'resetBaselines': _resetBaselineEvidence,
      'notificationClearOwnership': _notificationClearOwnershipEvidence,
      'recipient': {
        'deviceId': recipient,
        'platform': 'android',
        'targetPlatform': _androidTargetPlatform,
        'activityAbsentBeforeFcm': true,
        'activityAbsentDuringCallback': true,
      },
      if (!ordinaryOnly)
        'reaction': {
          'eventIdSha256': sha256.convert(utf8.encode(_eventId)).toString(),
          'targetIdSha256': sha256
              .convert(utf8.encode(_targetMessageId))
              .toString(),
          'remoteType': 'message_reaction',
        },
      if (!ordinaryOnly)
        'background': {
          'receivedAtOrAfter': reactionSentAt!.toIso8601String(),
          'generatedPluginRegistration': true,
          'nativeSurface': 'decryptMessage_only',
          'cryptoPluginCallObserved': true,
          'decryptSucceeded': true,
          'trustedActorTitle': 'TC256 Alice',
          'semanticBody': 'Reacted 👍 to your message',
          'matchingCards': 1,
        },
      'ordinaryMessages': {
        'schema': backgroundCryptoPreflightBundleSchema,
        'caseCount': _ordinaryEvidence.length,
        'contexts': const <String>['direct', 'group', 'announcement'],
        'modalities': const <String>['text', 'image', 'video', 'voice'],
        'nativeSurfaces': const <String>['decryptMessage', 'decryptGroup'],
        'activityAbsentBeforeEveryFcm': true,
        'activityAbsentDuringEveryCallback': true,
        'cryptoPluginCallObservedEveryCase': true,
        'decryptSucceededEveryCase': true,
        'exactlyOnePixelCardEveryCase': true,
        'trustedDatabaseTitlesVerified': true,
        'localizedTypedBodiesVerified': true,
        'routePayloadsVerified': true,
        'androidCategoryMsgVerified': true,
        'stableConversationReplacementVerified': true,
        'groupProviderAccountIdOmitted': true,
        'groupProviderTransportIdentityPresent': true,
        'transportAndAccountIdentitiesDistinct': true,
        'trustedLocalActorMappingVerified': true,
        'trustedLocalActorRolesVerified': true,
        'trustedDatabaseActorPrefixesVerified': true,
        'maliciousDecryptedNamesIgnored': true,
        'cases': _ordinaryEvidence,
      },
      'authorizationRejections': {
        'caseCount': _negativeAuthorizationEvidence.length,
        'expectedSuppressionReason': 'group_message_local_state_ineligible',
        'zeroCardsEveryCase': true,
        'zeroClaimsEveryCase': true,
        'zeroToneReservationsEveryCase': true,
        'zeroShownMarkersEveryCase': true,
        'zeroDecryptMarkersEveryCase': true,
        'zeroForbiddenDownstreamStageFamiliesEveryCase': true,
        'expectedEligibilitySuppressionEveryCase': true,
        'activityAbsentEveryCase': true,
        'cases': _negativeAuthorizationEvidence,
      },
      'foreground': {
        'goEventCallbackObserved': true,
        'event': 'node:startup_timing',
        'afterBackgroundDecrypt': true,
      },
      'redaction': {
        'fcmTokenPersisted': false,
        'secretKeyPersisted': false,
        'ciphertextPersisted': false,
        'plaintextPersisted': false,
      },
      'cleanup': {
        'syntheticRowsRemoved': true,
        'syntheticNotificationDismissed': true,
        'syntheticClaimsRemoved': true,
        'syntheticStagedEnvelopesRemoved': true,
        'recentNotificationGateRestored': true,
        'recentRemoteNotificationGateRestored': true,
        'privateProviderBundleDeleted': true,
        'fcmRefreshCommandDeleted': true,
        'clearNotificationsMarkerDeleted': true,
        'notificationPermissionRestored': false,
        'installedCandidateRestored': false,
        'localBuildArtifactRestoredToPriorState': false,
      },
      'successfulCleanupEvidence': List<Map<String, Object?>>.unmodifiable(
        _successfulCleanupEvidence,
      ),
      'evidencePath': flowEvidence.path,
    };
    final artifactFile = File(
      '${artifactDir.path}/android_background_crypto_preflight.json',
    );
    await artifactFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(artifact),
      flush: true,
    );
  }

  String get _passArtifactPath => cleanupOnly
      ? '${artifactDir.path}/android_background_crypto_cleanup.json'
      : setupOnly
      ? '${artifactDir.path}/android_background_crypto_setup.json'
      : resetOnly
      ? '${artifactDir.path}/android_background_crypto_reset.json'
      : providerDiagnosticOnly
      ? '${artifactDir.path}/android_provider_diagnostic.json'
      : '${artifactDir.path}/android_background_crypto_preflight.json';

  String get _failureArtifactPath => setupOnly
      ? '${artifactDir.path}/android_background_crypto_setup_failure.json'
      : resetOnly
      ? '${artifactDir.path}/android_background_crypto_reset_failure.json'
      : providerDiagnosticOnly
      ? '${artifactDir.path}/android_provider_diagnostic_failure.json'
      : '${artifactDir.path}/android_background_crypto_preflight_failure.json';

  Future<_CampaignFailure?> _attemptPreRestorationCleanup() async {
    _CampaignFailure? cleanupFailure;
    try {
      if (_preflightInstalled && !_syntheticCleanupConfirmed) {
        stage = 'cleanup_synthetic_state';
        try {
          // Legacy source contract anchor; the command-anchored wait happens
          // inside `_runCleanupCommand` before restoration is allowed:
          // description: 'acknowledged synthetic-state cleanup marker'
          await _runCleanupCommand(mode: 'recovery');
          await _verifyPrivateBundleAbsent();
          _syntheticCleanupConfirmed = true;
        } on _CampaignFailure catch (failure) {
          cleanupFailure = failure;
        } on Object catch (error) {
          final cleanupPhase = _lastCleanupPhase;
          cleanupFailure = _CampaignFailure(
            stage,
            'synthetic-state cleanup failed unexpectedly',
            type: cleanupPhase == null
                ? error.runtimeType.toString()
                : '_CampaignFailure',
            cleanupReason: cleanupPhase == null
                ? null
                : BackgroundCryptoCleanupReason.operationFailed,
            cleanupPhase: cleanupPhase,
          );
        }
      }
      if (_preflightInstalled) {
        final removal = await _runAs([
          'rm',
          '-f',
          ...backgroundCryptoRecoveryPrivateArtifactPaths,
        ]);
        final residueExitCodes = <String, int>{};
        for (final path in backgroundCryptoRecoveryPrivateArtifactPaths) {
          final residueProbe = await _runAs([
            'test',
            '!',
            '-e',
            path,
          ], suppressVerbose: true);
          residueExitCodes[path] = residueProbe.exitCode;
        }
        if (!backgroundCryptoRecoveryFallbackIsVerified(
          removalExitCode: removal.exitCode,
          absenceProbeExitCodes: residueExitCodes,
        )) {
          cleanupFailure ??= const _CampaignFailure(
            'cleanup_private_bundle',
            'private recovery artifact residue could not be removed',
            cleanupReason:
                BackgroundCryptoCleanupReason.privateResidueVerificationFailed,
            cleanupPhase:
                BackgroundCryptoCleanupPhase.privateResidueVerification,
          );
        }
      }
      final temp = _secretTempDir;
      if (temp != null) {
        try {
          if (await temp.exists()) await temp.delete(recursive: true);
          if (await temp.exists()) {
            throw const FileSystemException(
              'private provider temp directory survived deletion',
            );
          }
          _privateProviderTempDeleted = true;
        } on FileSystemException catch (error) {
          cleanupFailure ??= _CampaignFailure(
            'cleanup_private_temp',
            'private provider temp directory could not be removed',
            type: error.runtimeType.toString(),
            cleanupReason:
                BackgroundCryptoCleanupReason.privateResidueVerificationFailed,
            cleanupPhase:
                BackgroundCryptoCleanupPhase.privateResidueVerification,
          );
        }
      }
    } on _CampaignFailure catch (failure) {
      cleanupFailure ??= failure;
    } on Object catch (error) {
      final cleanupPhase = _lastCleanupPhase;
      cleanupFailure ??= _CampaignFailure(
        'cleanup_before_restore',
        'pre-restoration cleanup failed unexpectedly',
        type: cleanupPhase == null
            ? error.runtimeType.toString()
            : '_CampaignFailure',
        cleanupReason: cleanupPhase == null
            ? null
            : BackgroundCryptoCleanupReason.operationFailed,
        cleanupPhase: cleanupPhase,
      );
    }
    return cleanupFailure;
  }

  Future<_CampaignFailure?> _attemptOutermostRestoration() async {
    stage = 'restore_installed_app';
    _CampaignFailure? restoreFailure;
    try {
      await _restoreInstalledApp();
    } on _CampaignFailure catch (failure) {
      restoreFailure = failure;
    } on Object catch (error) {
      restoreFailure = _CampaignFailure(
        'restore_installed_app',
        'installed candidate restoration failed unexpectedly',
        type: error.runtimeType.toString(),
      );
    }
    try {
      await _restoreNotificationPermission();
    } on _CampaignFailure catch (failure) {
      restoreFailure ??= failure;
    } on Object catch (error) {
      restoreFailure ??= _CampaignFailure(
        'restore_notification_permission',
        'notification permission restoration failed unexpectedly',
        type: error.runtimeType.toString(),
      );
    }
    try {
      await _restoreLocalBuildArtifact();
    } on _CampaignFailure catch (failure) {
      restoreFailure ??= failure;
    } on Object catch (error) {
      restoreFailure ??= _CampaignFailure(
        'restore_local_build_artifact',
        'local build artifact restoration failed unexpectedly',
        type: error.runtimeType.toString(),
      );
    }
    final appBackup = _installedAppBackupDir;
    if (restoreFailure == null && appBackup != null) {
      try {
        if (await appBackup.exists()) await appBackup.delete(recursive: true);
      } on FileSystemException catch (error) {
        restoreFailure = _CampaignFailure(
          'restore_backup_cleanup',
          'installed-app backup directory could not be removed',
          type: error.runtimeType.toString(),
        );
      }
    }
    if (restoreFailure == null && _backupCaptured) {
      _successfulRestorationEvidence = <String, Object?>{
        'installedCandidateRestored': _replacementAttempted,
        'installedCandidateBytesVerified': _replacementAttempted,
        'installedCandidateApkSha256': List<String>.unmodifiable(
          _restoredInstalledApkHashes,
        ),
        'localBuildArtifactRestoredToPriorState': true,
        'localBuildArtifactBytesVerified': true,
        'notificationPermissionRestored': _notificationPermissionCaptured,
        'notificationPermissionInitiallyGranted':
            _notificationPermissionInitiallyGranted,
      };
    }
    return restoreFailure;
  }

  Future<_CampaignFailure?> _deleteStalePassArtifacts() async {
    _CampaignFailure? failure;
    for (final path in <String>{
      '${artifactDir.path}/android_background_crypto_preflight.json',
      '${artifactDir.path}/android_background_crypto_cleanup.json',
      '${artifactDir.path}/android_background_crypto_setup.json',
      '${artifactDir.path}/android_background_crypto_reset.json',
      '${artifactDir.path}/android_provider_diagnostic.json',
      '${artifactDir.path}/android_background_crypto_preflight_flow.log',
    }) {
      final file = File(path);
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException catch (error) {
        failure ??= _CampaignFailure(
          'cleanup_stale_artifacts',
          'stale pass artifact could not be removed',
          type: error.runtimeType.toString(),
        );
      }
    }
    return failure;
  }

  void _persistSetupReadyCheckpoint() {
    final artifact = File(_failureArtifactPath);
    artifact.writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(<String, Object?>{
        'testCase': 'TC-07-setup',
        'scenario': 'android_background_crypto_setup',
        'schema': backgroundCryptoSetupArtifactSchema,
        'status': 'in_progress',
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'mode': 'setup-only',
        'setupStatus': 'ready',
        'setupReady': true,
        'setupPhase': BackgroundCryptoSetupPhase.bundleValidation.wireName,
        'coldReadyMarkerObserved': true,
        'fixtureBundleValidated': true,
        'providerCodePathEntered': false,
        'providerRequestsSent': 0,
        'reactionCasesExecuted': 0,
        'ordinaryCasesExecuted': 0,
        'negativeCasesExecuted': 0,
        'containsSecrets': false,
      }),
      flush: true,
    );
  }

  void writeFailure(_CampaignCompositeFailure failure) {
    final artifact = File(_failureArtifactPath);
    final primaryRecord = failure.primary?.toRecord();
    final body = buildBackgroundCryptoCompositeFailureArtifact(
      capturedAt: DateTime.now().toUtc(),
      primary: primaryRecord,
      cleanup: failure.cleanup?.toRecord(),
      restoration: failure.restoration?.toRecord(),
    );
    final plannedReactionRows =
        cleanupOnly ||
            setupOnly ||
            ordinaryOnly ||
            resetOnly ||
            providerDiagnosticOnly
        ? 0
        : 1;
    final plannedOrdinaryRows =
        cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
        ? 0
        : backgroundCryptoPreflightOrdinaryRows.length;
    final plannedNegativeRows =
        cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
        ? 0
        : backgroundCryptoPreflightNegativeRows.length;
    body
      ..['mode'] = cleanupOnly
          ? 'cleanup-only'
          : setupOnly
          ? 'setup-only'
          : resetOnly
          ? 'reset-only'
          : providerDiagnosticOnly
          ? 'provider-diagnostic-only'
          : ordinaryOnly
          ? 'ordinary-only'
          : 'full'
      ..['setupReady'] = _setupReady
      ..['reactionRows'] = plannedReactionRows
      ..['reactionRowsExecuted'] = _reactionRowsExecuted
      ..['ordinaryCasesPlanned'] = plannedOrdinaryRows
      ..['ordinaryCasesExecuted'] = _ordinaryEvidence.length
      ..['negativeCasesPlanned'] = plannedNegativeRows
      ..['negativeCasesExecuted'] = _negativeAuthorizationEvidence.length
      ..['providerRequestsAttempted'] = _providerRequestsAttempted
      ..['providerRequestsSucceeded'] = _providerRequestsSucceeded
      ..['providerValidationAttempts'] = _providerValidationAttempts
      ..['providerValidationSucceeded'] = _providerValidationSucceeded
      ..['deliveryAttempted'] = _providerRequestsAttempted > 0
      ..['providerReceipts'] = _providerReceiptEvidence
      ..['providerDeliveryEligibility'] = _providerDeliveryEligibilityEvidence
      ..['caseExecutionOrder'] =
          cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
          ? const <String>[]
          : backgroundCryptoCampaignCaseOrder(ordinaryOnly: ordinaryOnly)
      ..['resetBaselines'] = _resetBaselineEvidence
      ..['notificationClearOwnership'] = _notificationClearOwnershipEvidence
      ..addAll(<String, Object?>{
        if (primaryRecord?.campaignPhase case final phase?)
          'campaignPhase': phase.wireName,
        if (primaryRecord?.campaignReason case final reason?)
          'campaignReason': reason.wireName,
        if (primaryRecord?.notificationClearPhase case final phase?)
          'notificationClearPhase': phase.wireName,
        if (primaryRecord?.notificationClearReason case final reason?)
          'notificationClearReason': reason.wireName,
        if (primaryRecord?.notificationClearBoundary case final boundary?)
          'notificationClearBoundary': boundary.wireName,
        if (primaryRecord?.notificationClearObservation case final observation?)
          'notificationClearObservation': observation.wireName,
        if (primaryRecord?.postClearReason case final reason?)
          'postClearReason': reason.wireName,
        if (primaryRecord?.postClearBoundary case final boundary?)
          'postClearBoundary': boundary.wireName,
        if (primaryRecord?.postClearObservation case final observation?)
          'postClearObservation': observation.wireName,
        'postClearPollCount': ?primaryRecord?.postClearPollCount,
        'postClearBaselineCount': ?primaryRecord?.postClearBaselineCount,
        'postClearBaselineHash': ?primaryRecord?.postClearBaselineHash,
        'currentSyntheticCaseId': ?primaryRecord?.syntheticCaseId,
        if (_successfulCleanupEvidence.isNotEmpty)
          'successfulCleanupEvidence': _successfulCleanupEvidence,
        'successfulRestorationEvidence': ?_successfulRestorationEvidence,
        'providerDiagnostic': ?_lastProviderDiagnostic,
        if (refreshUnregisteredToken)
          'tokenRegistration': <String, Object?>{
            ...?_tokenRegistrationEvidence,
            'priorDiagnosticSha256': priorProviderDiagnosticSha256,
          },
      })
      ..['containsSecrets'] = false;
    if (resetOnly) {
      body
        ..['testCase'] = 'TC-07-reset'
        ..['scenario'] = 'android_background_crypto_reset'
        ..['schema'] = backgroundCryptoResetArtifactSchema
        ..['providerCodePathEntered'] = false
        ..['providerTempCreated'] = false
        ..['oauthAttempted'] = false;
    }
    if (providerDiagnosticOnly) {
      body
        ..['testCase'] = 'TC-07-provider-diagnostic'
        ..['scenario'] = 'android_provider_validate_only'
        ..['schema'] = backgroundCryptoProviderDiagnosticArtifactSchema
        ..['deliveryAttempted'] = false
        ..['reactionRowsExecuted'] = 0
        ..['ordinaryCasesExecuted'] = 0
        ..['negativeCasesExecuted'] = 0;
    }
    if (setupOnly) {
      final recordedSetupPhase =
          primaryRecord?.redactedSetupPhase ??
          (_setupReady
              ? BackgroundCryptoSetupPhase.bundleValidation
              : _lastSetupPhase);
      body
        ..['testCase'] = 'TC-07-setup'
        ..['scenario'] = 'android_background_crypto_setup'
        ..['schema'] = backgroundCryptoSetupArtifactSchema
        ..['mode'] = 'setup-only'
        ..['setupStatus'] = _setupReady ? 'ready' : 'failed'
        ..['setupReady'] = _setupReady
        ..['coldReadyMarkerObserved'] = _setupReady
        ..['fixtureBundleValidated'] = _setupReady
        ..addAll(<String, Object?>{
          if (recordedSetupPhase != null)
            'setupPhase': recordedSetupPhase.wireName,
          if (primaryRecord?.redactedSetupReason case final reason?)
            'setupReason': reason.wireName,
          if (primaryRecord?.redactedCleanupPhase case final phase?)
            'cleanupPhase': phase.wireName,
          if (primaryRecord?.redactedCleanupReason case final reason?)
            'cleanupReason': reason.wireName,
          if (_successfulCleanupEvidence.isNotEmpty)
            'successfulCleanupEvidence': _successfulCleanupEvidence,
          'successfulRestorationEvidence': ?_successfulRestorationEvidence,
        })
        ..['providerCodePathEntered'] = false
        ..['providerTempCreated'] = false
        ..['oauthAttempted'] = false
        ..['providerRequestsSent'] = 0
        ..['reactionCasesExecuted'] = 0
        ..['ordinaryCasesExecuted'] = 0
        ..['negativeCasesExecuted'] = 0
        ..['containsSecrets'] = false;
    }
    artifact.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(body));
  }

  Future<String> _runCleanupCommand({
    required String mode,
    bool requirePostProofNode = false,
  }) async {
    if (!backgroundCryptoCleanupCommandModes.contains(mode)) {
      throw _CampaignFailure(
        stage,
        'unsupported reserved cleanup mode',
        cleanupReason: BackgroundCryptoCleanupReason.commandStagingFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.commandStaging,
      );
    }
    final commandId =
        'tc256-${DateTime.now().toUtc().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(0x7fffffff)}';
    final command = jsonEncode(<String, Object?>{
      'schema': _cleanupCommandSchema,
      'commandId': commandId,
      'mode': mode,
    });
    final commandBytes = utf8.encode(command);
    _lastCleanupPhase = BackgroundCryptoCleanupPhase.commandStaging;
    late final BackgroundCryptoStagedFileReceipt commandReceipt;
    try {
      commandReceipt = await copyBackgroundCryptoCommandBytesToAppPrivateFile(
        bytes: commandBytes,
        run: _runPrivateFileTransport,
      );
    } on BackgroundCryptoStagedFileFailure catch (failure) {
      final cleanup = failure.cleanupStages.isEmpty
          ? 'none'
          : failure.cleanupStages.join(',');
      throw _CampaignFailure(
        stage,
        'cleanup command transport failed at '
        '${failure.primaryStage ?? 'cleanup'}; staging cleanup failures=$cleanup',
        type: failure.primaryType ?? failure.runtimeType.toString(),
        cleanupReason: BackgroundCryptoCleanupReason.commandStagingFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.commandStaging,
      );
    } on Object {
      throw _CampaignFailure(
        stage,
        'cleanup command staging failed unexpectedly',
        cleanupReason: BackgroundCryptoCleanupReason.commandStagingFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.commandStaging,
      );
    }
    await _prepareCleanupCommandColdLaunch();
    _lastCleanupPhase = BackgroundCryptoCleanupPhase.acknowledgement;
    late final String log;
    try {
      log = await _waitForLog(
        (candidate) {
          try {
            backgroundCryptoCleanupEvidenceFromLog(
              candidate,
              commandId: commandId,
              commandSha256: commandReceipt.sha256,
              commandByteLength: commandReceipt.byteLength,
              mode: mode,
            );
          } on FormatException {
            return false;
          }
          return !requirePostProofNode ||
              (candidate.contains('"event":"post_foreground_node_started"') &&
                  candidate.contains('"event":"node:startup_timing"'));
        },
        timeout: const Duration(minutes: 2),
        description: 'command-anchored reserved cleanup acknowledgement',
      );
    } on Object {
      throw _CampaignFailure(
        stage,
        'cleanup acknowledgement failed',
        cleanupReason: BackgroundCryptoCleanupReason.acknowledgementFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.acknowledgement,
      );
    }
    late final Map<String, Object?> cleanupEvidence;
    try {
      cleanupEvidence = backgroundCryptoCleanupEvidenceFromLog(
        log,
        commandId: commandId,
        commandSha256: commandReceipt.sha256,
        commandByteLength: commandReceipt.byteLength,
        mode: mode,
      );
    } on FormatException {
      throw _CampaignFailure(
        stage,
        'cleanup receipt validation failed',
        cleanupReason: BackgroundCryptoCleanupReason.acknowledgementFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.acknowledgement,
      );
    }
    final commandProbe = await _runAs(
      ['ls', _postForegroundMarker],
      allowFailure: true,
      suppressVerbose: true,
    );
    if (commandProbe.exitCode == 0) {
      throw _CampaignFailure(
        stage,
        'acknowledged cleanup command file remained',
        cleanupReason: BackgroundCryptoCleanupReason.acknowledgementFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.acknowledgement,
      );
    }
    _successfulCleanupEvidence.add(
      Map<String, Object?>.unmodifiable(cleanupEvidence),
    );
    return log;
  }

  Future<void> _prepareCleanupCommandColdLaunch() async {
    _lastCleanupPhase = BackgroundCryptoCleanupPhase.appQuiescence;
    try {
      if (!isValidAndroidAppPackage(appPackage)) {
        throw const FormatException('invalid validated package');
      }
      await _adbShell(['am', 'force-stop', appPackage]);
      await _waitForProcessAndTaskAbsent();
    } on Object {
      throw _CampaignFailure(
        stage,
        'cleanup cold-launch quiescence failed',
        cleanupReason: BackgroundCryptoCleanupReason.quiescenceFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.appQuiescence,
      );
    }
    _lastCleanupPhase = BackgroundCryptoCleanupPhase.logReset;
    try {
      await _adb(['logcat', '-c']);
    } on Object {
      throw _CampaignFailure(
        stage,
        'cleanup log reset failed',
        cleanupReason: BackgroundCryptoCleanupReason.logResetFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.logReset,
      );
    }
    _lastCleanupPhase = BackgroundCryptoCleanupPhase.appLaunch;
    try {
      await _launchExplicitActivityClearingStoppedState();
    } on Object {
      throw _CampaignFailure(
        stage,
        'cleanup explicit launch failed',
        cleanupReason: BackgroundCryptoCleanupReason.appLaunchFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.appLaunch,
      );
    }
  }

  Future<BackgroundCryptoTransportResult> _runPrivateFileTransport(
    BackgroundCryptoTransportInvocation invocation,
  ) async {
    final output = switch (invocation.channel) {
      BackgroundCryptoTransportChannel.adb => await _adb(
        invocation.arguments,
        allowFailure: true,
        suppressVerbose: true,
      ),
      BackgroundCryptoTransportChannel.shell => await _adbShell(
        invocation.arguments,
        allowFailure: true,
        suppressVerbose: true,
      ),
      BackgroundCryptoTransportChannel.runAs => await _runAs(
        invocation.arguments,
        allowFailure: true,
        suppressVerbose: true,
      ),
    };
    return BackgroundCryptoTransportResult(
      exitCode: output.exitCode,
      stdout: output.stdout,
      stderr: output.stderr,
    );
  }

  Future<void> _stageFcmRefreshCommand() async {
    if (priorProviderDiagnosticSha256 == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(priorProviderDiagnosticSha256!) ||
        priorProviderSubjectTokenSha256 == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(priorProviderSubjectTokenSha256!) ||
        priorProviderDiagnosticCapturedAt == null) {
      throw _CampaignFailure(
        stage,
        'FCM refresh authorization is unavailable',
        setupReason: BackgroundCryptoSetupReason.schemaGuard,
        setupPhase: BackgroundCryptoSetupPhase.fcmToken,
      );
    }
    final now = DateTime.now().toUtc();
    final diagnosticAge = now.difference(priorProviderDiagnosticCapturedAt!);
    if (diagnosticAge.isNegative ||
        diagnosticAge > const Duration(minutes: 30)) {
      throw _CampaignFailure(
        stage,
        'FCM refresh authorization expired before command staging',
        setupReason: BackgroundCryptoSetupReason.schemaGuard,
        setupPhase: BackgroundCryptoSetupPhase.fcmToken,
      );
    }
    final generationId =
        'tc256-token-refresh-${now.microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(0x7fffffff)}';
    final bytes = utf8.encode(
      jsonEncode(<String, Object?>{
        'schema': backgroundCryptoFcmRefreshCommandSchema,
        'commandId': generationId,
        'issuedAt': now.toIso8601String(),
        'maxAgeSeconds': 120,
        'subjectTokenSha256': priorProviderSubjectTokenSha256,
      }),
    );
    try {
      await copyBackgroundCryptoCommandBytesToAppPrivateFile(
        bytes: bytes,
        run: _runPrivateFileTransport,
        appPrivatePath: backgroundCryptoAppPrivateFcmRefreshCommandPath,
      );
      _fcmRefreshGenerationId = generationId;
      _fcmRefreshIssuedAt = now;
    } on BackgroundCryptoStagedFileFailure {
      throw _CampaignFailure(
        stage,
        'bounded FCM refresh command staging failed',
        setupReason: BackgroundCryptoSetupReason.operationFailed,
        setupPhase: BackgroundCryptoSetupPhase.fcmToken,
      );
    }
  }

  Future<void> _verifyPrivateBundleAbsent() async {
    _lastCleanupPhase = BackgroundCryptoCleanupPhase.privateResidueVerification;
    for (final path in <String>[
      _requestFile,
      _cleanupIndexFile,
      _fcmRefreshCommand,
    ]) {
      final probe = await _runAs(
        ['ls', path],
        allowFailure: true,
        suppressVerbose: true,
      );
      if (probe.exitCode == 0) {
        throw _CampaignFailure(
          stage,
          'private cleanup artifact remained after acknowledgement',
          cleanupReason:
              BackgroundCryptoCleanupReason.privateResidueVerificationFailed,
          cleanupPhase: BackgroundCryptoCleanupPhase.privateResidueVerification,
        );
      }
    }
  }

  Future<void> _writeCleanupOnlyArtifact(String log) async {
    final cleanup = _latestPreflightMarker(log, event: 'cleanup_complete');
    if (cleanup == null) {
      throw _CampaignFailure(
        stage,
        'cleanup-only acknowledgement could not be parsed',
        cleanupReason: BackgroundCryptoCleanupReason.acknowledgementFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.acknowledgement,
      );
    }
    const countFields = backgroundCryptoCleanupZeroCountFields;
    final artifact = <String, Object?>{
      'testCase': 'TC-07',
      'scenario': 'android_background_crypto_cleanup',
      'schema': backgroundCryptoCleanupArtifactSchema,
      'status': 'passed',
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'recipient': <String, Object?>{
        'deviceId': recipient,
        'platform': 'android',
        'targetPlatform': _androidTargetPlatform,
      },
      'mode': 'cleanup-only',
      'successfulCleanupEvidence': List<Map<String, Object?>>.unmodifiable(
        _successfulCleanupEvidence,
      ),
      'providerRequestsSent': 0,
      'ordinaryCasesExecuted': 0,
      'mainReexecuted': cleanup['mainReexecuted'] == true,
      'reservedOnly': cleanup['reservedOnly'] == true,
      'cleanup': <String, Object?>{
        for (final field in countFields) field: cleanup[field],
        'privateProviderBundleDeleted': true,
        'cleanupIndexDeleted': true,
        'fcmRefreshCommandDeleted': true,
        'clearNotificationsMarkerDeleted': true,
        'boundedReactionClaimsVerified': true,
        'bothRecentGatesScrubbed': true,
        'notificationPermissionRestored': false,
        'installedCandidateRestored': false,
        'localBuildArtifactRestoredToPriorState': false,
      },
      'redaction': const <String, Object?>{
        'fcmTokenPersisted': false,
        'secretKeyPersisted': false,
        'ciphertextPersisted': false,
        'plaintextPersisted': false,
      },
    };
    await File(_passArtifactPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(artifact),
      flush: true,
    );
  }

  Future<void> _writeSetupOnlyArtifact(String log) async {
    final cleanup = _latestPreflightMarker(log, event: 'cleanup_complete');
    if (cleanup == null) {
      throw _CampaignFailure(
        stage,
        'setup-only cleanup acknowledgement could not be parsed',
        cleanupReason: BackgroundCryptoCleanupReason.acknowledgementFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.acknowledgement,
      );
    }
    const countFields = backgroundCryptoCleanupZeroCountFields;
    final artifact = <String, Object?>{
      'testCase': 'TC-07-setup',
      'scenario': 'android_background_crypto_setup',
      'schema': backgroundCryptoSetupArtifactSchema,
      'status': 'passed',
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'recipient': <String, Object?>{
        'deviceId': recipient,
        'platform': 'android',
        'targetPlatform': _androidTargetPlatform,
      },
      'mode': 'setup-only',
      'setupStatus': 'ready',
      'setupReady': true,
      'setupPhase': BackgroundCryptoSetupPhase.bundleValidation.wireName,
      'coldReadyMarkerObserved': true,
      'fixtureBundleValidated': true,
      'providerCodePathEntered': false,
      'providerTempCreated': false,
      'oauthAttempted': false,
      'providerRequestsSent': 0,
      'reactionCasesExecuted': 0,
      'ordinaryCasesExecuted': 0,
      'negativeCasesExecuted': 0,
      'successfulCleanupEvidence': List<Map<String, Object?>>.unmodifiable(
        _successfulCleanupEvidence,
      ),
      'mainReexecutedForCleanup': cleanup['mainReexecuted'] == true,
      'reservedOnlyCleanup': cleanup['reservedOnly'] == true,
      'cleanup': <String, Object?>{
        for (final field in countFields) field: cleanup[field],
        'privateProviderBundleDeleted': true,
        'cleanupIndexDeleted': true,
        'fcmRefreshCommandDeleted': true,
        'clearNotificationsMarkerDeleted': true,
        'boundedReactionClaimsVerified': true,
        'bothRecentGatesScrubbed': true,
        'notificationPermissionRestored': false,
        'installedCandidateRestored': false,
        'localBuildArtifactRestoredToPriorState': false,
      },
      'redaction': const <String, Object?>{
        'setupFailureTextPersisted': false,
        'fcmTokenPersisted': false,
        'secretKeyPersisted': false,
        'ciphertextPersisted': false,
        'plaintextPersisted': false,
      },
      'containsSecrets': false,
    };
    await File(_passArtifactPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(artifact),
      flush: true,
    );
  }

  Future<void> _writeResetOnlyArtifact(String log) async {
    final cleanup = _latestPreflightMarker(log, event: 'cleanup_complete');
    if (cleanup == null) {
      throw _CampaignFailure(
        stage,
        'reset-only cleanup acknowledgement could not be parsed',
        cleanupReason: BackgroundCryptoCleanupReason.acknowledgementFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.acknowledgement,
      );
    }
    const countFields = backgroundCryptoCleanupZeroCountFields;
    final artifact = <String, Object?>{
      'testCase': 'TC-07-reset',
      'scenario': 'android_background_crypto_reset',
      'schema': backgroundCryptoResetArtifactSchema,
      'status': 'passed',
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'mode': 'reset-only',
      'setupReady': true,
      'providerCodePathEntered': false,
      'providerTempCreated': false,
      'oauthAttempted': false,
      'providerRequestsSent': 0,
      'reactionCasesExecuted': 0,
      'ordinaryCasesExecuted': 0,
      'negativeCasesExecuted': 0,
      'notificationClearOwnership': _notificationClearOwnershipEvidence,
      'resetBaselines': _resetBaselineEvidence,
      'successfulCleanupEvidence': List<Map<String, Object?>>.unmodifiable(
        _successfulCleanupEvidence,
      ),
      'cleanup': <String, Object?>{
        for (final field in countFields) field: cleanup[field],
        'privateProviderBundleDeleted': true,
        'cleanupIndexDeleted': true,
        'fcmRefreshCommandDeleted': true,
        'clearNotificationsMarkerDeleted': true,
        'boundedReactionClaimsVerified': true,
        'bothRecentGatesScrubbed': true,
        'notificationPermissionRestored': false,
        'installedCandidateRestored': false,
        'localBuildArtifactRestoredToPriorState': false,
      },
      'redaction': const <String, Object?>{
        'fcmTokenPersisted': false,
        'secretKeyPersisted': false,
        'ciphertextPersisted': false,
        'plaintextPersisted': false,
      },
      'containsSecrets': false,
    };
    await File(_passArtifactPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(artifact),
      flush: true,
    );
  }

  Future<void> _writeProviderDiagnosticArtifact({
    required String cleanupLog,
    required Map<String, Object?> receipt,
    required String subjectTokenSha256,
  }) async {
    final cleanup = _latestPreflightMarker(
      cleanupLog,
      event: 'cleanup_complete',
    );
    if (cleanup == null) {
      throw _CampaignFailure(
        stage,
        'provider diagnostic cleanup acknowledgement could not be parsed',
        cleanupReason: BackgroundCryptoCleanupReason.acknowledgementFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.acknowledgement,
      );
    }
    const countFields = backgroundCryptoCleanupZeroCountFields;
    final artifact = <String, Object?>{
      'testCase': 'TC-07-provider-diagnostic',
      'scenario': 'android_provider_validate_only',
      'schema': backgroundCryptoProviderDiagnosticArtifactSchema,
      'status': 'completed',
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'mode': 'provider-diagnostic-only',
      'setupReady': true,
      'fixtureCaseId': 'direct-text',
      'providerValidationAttempts': _providerValidationAttempts,
      'providerValidationSucceeded': _providerValidationSucceeded,
      'providerDiagnostic': receipt,
      'subjectTokenSha256': subjectTokenSha256,
      'deliveryAttempted': false,
      'providerRequestsAttempted': 0,
      'providerRequestsSucceeded': 0,
      'reactionCasesExecuted': 0,
      'ordinaryCasesExecuted': 0,
      'negativeCasesExecuted': 0,
      'callbacksObserved': 0,
      'notificationCardsObserved': 0,
      if (refreshUnregisteredToken)
        'tokenRegistration': <String, Object?>{
          ...?_tokenRegistrationEvidence,
          'priorDiagnosticSha256': priorProviderDiagnosticSha256,
        },
      'successfulCleanupEvidence': List<Map<String, Object?>>.unmodifiable(
        _successfulCleanupEvidence,
      ),
      'cleanup': <String, Object?>{
        for (final field in countFields) field: cleanup[field],
        'privateProviderBundleDeleted': true,
        'cleanupIndexDeleted': true,
        'fcmRefreshCommandDeleted': true,
        'clearNotificationsMarkerDeleted': true,
        'privateProviderTempDeleted': false,
        'boundedReactionClaimsVerified': true,
        'bothRecentGatesScrubbed': true,
        'notificationPermissionRestored': false,
        'installedCandidateRestored': false,
        'localBuildArtifactRestoredToPriorState': false,
      },
      'redaction': const <String, Object?>{
        'providerMessagePersisted': false,
        'fcmTokenPersisted': false,
        'credentialPersisted': false,
        'jwtPersisted': false,
        'providerUrlPersisted': false,
        'payloadPersisted': false,
        'rawHeaderPersisted': false,
      },
      'containsSecrets': false,
    };
    await File(_passArtifactPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(artifact),
      flush: true,
    );
  }

  Map<String, dynamic>? _latestPreflightMarker(
    String log, {
    required String event,
  }) {
    const anchor = 'MKNOON_256_CRYPTO_PREFLIGHT ';
    for (final line in log.split('\n').reversed) {
      final start = line.indexOf(anchor);
      if (start < 0) continue;
      try {
        final decoded = jsonDecode(line.substring(start + anchor.length));
        if (decoded is Map<String, dynamic> && decoded['event'] == event) {
          return decoded;
        }
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  Future<void> _captureNotificationBaseline() async {
    _baselineNotificationIds = (await _activeNotificationCards())
        .map((card) => card.id)
        .whereType<int>()
        .toSet();
  }

  Future<List<ActiveNotificationCard>> _activeNotificationCards() async {
    final dump = (await _adbShell([
      'dumpsys',
      'notification',
      '--noredact',
    ], suppressVerbose: true)).stdout;
    return extractActiveNotificationCards(dump, packageName: appPackage);
  }

  Future<List<ActiveNotificationCard>> _syntheticNotificationCards() async {
    return backgroundCryptoCardsOutsideBaseline(
      await _activeNotificationCards(),
      baselineIds: _baselineNotificationIds,
    );
  }

  Future<void> _clearSyntheticCards() async {
    await _prepareNotificationClearColdLaunch();
    final clearLog = await _waitForLog(
      (_) => false,
      timeout: const Duration(minutes: 1),
      description: 'synthetic-notification cleanup acknowledgement',
    );
    final clearMarker = backgroundCryptoNotificationClearCompletionFromLog(
      clearLog,
    );
    const countFields = backgroundCryptoNotificationClearCountFields;
    if (clearMarker == null ||
        countFields.any(
          (field) =>
              clearMarker[field] is! int || (clearMarker[field]! as int) < 0,
        )) {
      throw _CampaignFailure(
        stage,
        'notification clear ownership counts were unavailable',
        campaignReason: BackgroundCryptoCampaignReason.cardVerificationFailed,
        campaignPhase: _currentCampaignPhase,
        syntheticCaseId: _currentSyntheticCaseId,
        notificationClearPhase:
            BackgroundCryptoNotificationClearPhase.markerWrite,
        notificationClearReason:
            BackgroundCryptoNotificationClearReason.rejectedSchema,
        notificationClearBoundary:
            BackgroundCryptoNotificationClearBoundary.completionSchema,
        notificationClearObservation:
            BackgroundCryptoNotificationClearObservation.observed,
      );
    }
    _notificationClearOwnershipEvidence.add(<String, int>{
      'total': clearMarker['fixtureNotificationCardsCleared']! as int,
      'route': clearMarker['fixtureNotificationRouteOwnedCardsCleared']! as int,
      'copy': clearMarker['fixtureNotificationCopyOwnedCardsCleared']! as int,
      'knownId':
          clearMarker['fixtureNotificationKnownIdOwnedCardsCleared']! as int,
    });
    try {
      await _quiescePackageForPushDelivery();
    } on _ProcessAndTaskAbsenceTimeout {
      throw _postClearFailure(
        reason: BackgroundCryptoPostClearReason.processAbsenceTimeout,
        boundary: BackgroundCryptoPostClearBoundary.processAbsence,
        observation: BackgroundCryptoPostClearObservation.notObserved,
        message: 'post-clear process and task absence timed out',
      );
    } on Object {
      throw _postClearFailure(
        reason: BackgroundCryptoPostClearReason.deliveryQuiescenceFailed,
        boundary: BackgroundCryptoPostClearBoundary.deliveryQuiescence,
        observation: BackgroundCryptoPostClearObservation.notObserved,
        message: 'post-clear delivery quiescence failed',
      );
    }
    final reset = await _waitForNotificationResetConvergence();
    _baselineNotificationIds = reset.baselineIds;
    _resetBaselineEvidence.add(<String, Object?>{
      'count': reset.baselineIds.length,
      'sha256': reset.baselineHash,
    });
  }

  Future<void> _prepareNotificationClearColdLaunch() async {
    _lastNotificationClearPhase = null;
    _notificationClearCommandAcknowledged = false;
    try {
      await _runAs(['touch', _clearNotificationsMarker]);
      await _adbShell(['am', 'force-stop', appPackage]);
      await _waitForProcessAndTaskAbsent();
    } on Object {
      throw _CampaignFailure(
        stage,
        'notification clear command delivery or quiescence failed',
        campaignReason: BackgroundCryptoCampaignReason.cardVerificationFailed,
        campaignPhase: _currentCampaignPhase,
        syntheticCaseId: _currentSyntheticCaseId,
        notificationClearReason:
            BackgroundCryptoNotificationClearReason.operationFailed,
        notificationClearBoundary:
            BackgroundCryptoNotificationClearBoundary.commandDelivery,
        notificationClearObservation:
            BackgroundCryptoNotificationClearObservation.notObserved,
      );
    }
    try {
      await _adb(['logcat', '-c']);
      await _launchExplicitActivityClearingStoppedState();
    } on Object {
      throw _CampaignFailure(
        stage,
        'notification clear cold launch failed',
        campaignReason: BackgroundCryptoCampaignReason.cardVerificationFailed,
        campaignPhase: _currentCampaignPhase,
        syntheticCaseId: _currentSyntheticCaseId,
        notificationClearReason:
            BackgroundCryptoNotificationClearReason.operationFailed,
        notificationClearBoundary:
            BackgroundCryptoNotificationClearBoundary.appLaunch,
        notificationClearObservation:
            BackgroundCryptoNotificationClearObservation.notObserved,
      );
    }
  }

  Future<BackgroundCryptoNotificationResetSnapshot>
  _waitForNotificationResetConvergence() async {
    var pollCount = 0;
    BackgroundCryptoNotificationResetSnapshot? lastBaseline;
    BackgroundCryptoNotificationResetSnapshot? reset;
    try {
      reset = await waitForBackgroundCryptoNotificationResetConvergence(
        poll: () async {
          pollCount++;
          final cards = await _activeNotificationCards();
          lastBaseline = classifyBackgroundCryptoNotificationReset(
            cards,
            knownFixtureIds: _conversationNotificationIds.values.toSet(),
          );
          return cards;
        },
        timeout: const Duration(seconds: 5),
        interval: const Duration(milliseconds: 200),
        knownFixtureIds: _conversationNotificationIds.values.toSet(),
      );
    } on Object {
      throw _postClearFailure(
        reason: BackgroundCryptoPostClearReason.baselinePollFailed,
        boundary: BackgroundCryptoPostClearBoundary.baselinePolling,
        observation: BackgroundCryptoPostClearObservation.notObserved,
        message: 'post-clear notification baseline poll failed',
        pollCount: pollCount,
        lastBaseline: lastBaseline,
      );
    }
    if (reset != null) return reset;
    throw _postClearFailure(
      reason: BackgroundCryptoPostClearReason.convergenceTimeout,
      boundary: BackgroundCryptoPostClearBoundary.convergence,
      observation: BackgroundCryptoPostClearObservation.notObserved,
      message: 'post-clear notification baseline did not converge',
      pollCount: pollCount,
      lastBaseline: lastBaseline,
    );
  }

  Future<void> _prepareHeadlessCase(String caseId) async {
    _enterCampaignPhase(
      BackgroundCryptoCampaignPhase.headlessQuiescence,
      caseId,
    );
    try {
      await _adb(['logcat', '-c']);
      await _quiescePackageForPushDelivery();
      if (await _hasLivePackageActivity()) {
        throw StateError('Activity remained live');
      }
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.headlessQuiescenceFailed,
        'headless recipient quiescence failed',
      );
    }
  }

  Future<DateTime> _exerciseLegacyReaction({
    required String token,
    required Map<String, dynamic> data,
  }) async {
    const caseId = 'reaction';
    stage = 'reaction';
    await _prepareHeadlessCase(caseId);
    final sentAt = DateTime.now().toUtc();
    await _sendPrivateProviderRequest(
      token: token,
      data: data,
      kind: 'reaction',
      id: caseId,
    );
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.receiveWait, caseId);
    try {
      await _waitForLog(
        (log) => log.contains('PUSH_BACKGROUND_MESSAGE_RECEIVED'),
        timeout: const Duration(minutes: 2),
        description: 'reaction receive marker',
      );
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.receiveTimeout,
        'reaction receive wait failed',
      );
    }
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.cryptoWait, caseId);
    late final String backgroundLog;
    try {
      backgroundLog = await _waitForLog(
        (log) =>
            log.contains('PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK') &&
            log.contains('PUSH_ANDROID_DATA_DECRYPT_OK'),
        timeout: const Duration(minutes: 2),
        description: 'reaction crypto/decrypt markers',
      );
      if (await _hasLivePackageActivity()) {
        throw StateError('Activity launched during reaction callback');
      }
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cryptoTimeout,
        'reaction crypto wait failed',
      );
    }
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.cardVerify, caseId);
    late final String displayLog;
    try {
      displayLog = await _waitForLog(
        (log) => log.contains('PUSH_BACKGROUND_NOTIFICATION_SHOWN'),
        timeout: const Duration(minutes: 1),
        description: 'reaction notification shown marker',
      );
      final matchingCards = await _syntheticNotificationCards();
      if (matchingCards.length != 1 ||
          matchingCards.single.title != 'TC256 Alice' ||
          matchingCards.single.body != 'Reacted 👍 to your message') {
        throw StateError('reaction notification card mismatch');
      }
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cardVerificationFailed,
        'reaction notification card verification failed',
      );
    }
    _capturedSafeMarkerLines.addAll(
      _safeMarkerLines('$backgroundLog\n$displayLog'),
    );
    _reactionRowsExecuted = 1;
    return sentAt;
  }

  Future<void> _runOrdinaryMatrix({
    required String token,
    required List<Map<String, dynamic>> ordinaryCases,
  }) async {
    if (ordinaryCases.length != backgroundCryptoPreflightOrdinaryRows.length ||
        ordinaryCases.first['id'] != 'direct-text') {
      throw StateError('ordinary matrix order was not validated');
    }
    String? currentContext;
    for (final ordinaryCase in ordinaryCases) {
      final id = ordinaryCase['id']! as String;
      final context = ordinaryCase['context']! as String;
      if (context != currentContext) {
        stage = 'clear_${context}_cards';
        _enterCampaignPhase(BackgroundCryptoCampaignPhase.cardVerify, id);
        try {
          await _clearSyntheticCards();
        } on _CampaignFailure {
          rethrow;
        } on Object {
          throw _campaignFailure(
            BackgroundCryptoCampaignReason.cardVerificationFailed,
            'ordinary context card reset failed',
          );
        }
        currentContext = context;
      }
      await _exerciseOrdinaryCase(token: token, testCase: ordinaryCase);
    }
    if (_ordinaryEvidence.length !=
        backgroundCryptoPreflightOrdinaryRows.length) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cardVerificationFailed,
        'ordinary proof matrix did not complete',
      );
    }
  }

  Future<void> _runNegativeAuthorizationMatrix({
    required String token,
    required List<Map<String, dynamic>> negativeCases,
  }) async {
    final firstCaseId = negativeCases.first['id']! as String;
    stage = 'clear_authorization_negative_cards';
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.cardVerify, firstCaseId);
    try {
      await _clearSyntheticCards();
    } on _CampaignFailure {
      rethrow;
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cardVerificationFailed,
        'authorization card reset failed',
      );
    }
    for (final negativeCase in negativeCases) {
      await _exerciseNegativeAuthorizationCase(
        token: token,
        testCase: negativeCase,
      );
    }
    if (_negativeAuthorizationEvidence.length !=
        backgroundCryptoPreflightNegativeRows.length) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.eligibilityFailed,
        'authorization rejection matrix did not complete',
      );
    }
  }

  Future<void> _sendPrivateProviderRequest({
    required String token,
    required Map<String, dynamic> data,
    required String kind,
    required String id,
    String expectedOutcome = 'display',
    String? rejectionReason,
  }) async {
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.requestPrepare, id);
    final temp = _secretTempDir;
    if (temp == null) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.requestPrepareFailed,
        'private request directory is unavailable',
      );
    }
    final safeId = id.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
    final requestFile = File('${temp.path}/$safeId.json');
    try {
      try {
        await requestFile.writeAsString(
          jsonEncode(<String, Object?>{
            'token': token,
            'data': data,
            'transportContract': <String, Object?>{
              'caseId': safeId,
              'expectedOutcome': expectedOutcome,
              'rejectionReason': ?rejectionReason,
            },
          }),
          flush: true,
        );
      } on Object {
        throw _campaignFailure(
          BackgroundCryptoCampaignReason.requestPrepareFailed,
          'private provider request preparation failed',
        );
      }
      _enterCampaignPhase(
        BackgroundCryptoCampaignPhase.deliveryEligibility,
        id,
      );
      await _requirePackageEligibleForDataOnlyFcm(id);
      _providerRequestsAttempted++;
      _enterCampaignPhase(BackgroundCryptoCampaignPhase.oauth, id);
      final provider = await _run('node', [
        'scripts/send_fcm_provider_probe.js',
        '--request-file',
        requestFile.path,
        '--service-account',
        serviceAccount.path,
        '--mode',
        'data-only',
        '--kind',
        kind,
        '--probe-id',
        'tc256-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      ]);
      late final Map<String, Object?> providerReceipt;
      try {
        providerReceipt = parseBackgroundCryptoProviderResult(
          provider.exitCode == 0 ? provider.stdout : provider.stderr,
          exitCode: provider.exitCode,
          expectValidateOnly: false,
        );
      } on FormatException {
        _enterCampaignPhase(BackgroundCryptoCampaignPhase.requestPrepare, id);
        throw _campaignFailure(
          BackgroundCryptoCampaignReason.requestPrepareFailed,
          'provider result schema was rejected',
        );
      }
      _lastProviderDiagnostic = providerReceipt;
      _providerReceiptEvidence.add(
        Map<String, Object?>.unmodifiable(<String, Object?>{
          'caseId': id,
          'expectedOutcome': expectedOutcome,
          ...providerReceipt,
        }),
      );
      if (provider.exitCode != 0) {
        if (provider.exitCode == 70) {
          throw _campaignFailure(
            BackgroundCryptoCampaignReason.oauthFailed,
            'provider OAuth failed',
          );
        }
        if (provider.exitCode == 71) {
          _enterCampaignPhase(BackgroundCryptoCampaignPhase.providerSend, id);
          throw _campaignFailure(
            BackgroundCryptoCampaignReason.providerSendFailed,
            'provider send failed',
          );
        }
        _enterCampaignPhase(BackgroundCryptoCampaignPhase.requestPrepare, id);
        throw _campaignFailure(
          BackgroundCryptoCampaignReason.requestPrepareFailed,
          'provider request validation failed',
        );
      }
      _enterCampaignPhase(BackgroundCryptoCampaignPhase.providerSend, id);
      _providerRequestsSucceeded++;
    } finally {
      try {
        if (await requestFile.exists()) await requestFile.delete();
        if (await requestFile.exists()) {
          throw const FileSystemException(
            'private provider request survived deletion',
          );
        }
      } on FileSystemException {
        _enterCampaignPhase(BackgroundCryptoCampaignPhase.requestPrepare, id);
        throw _campaignFailure(
          BackgroundCryptoCampaignReason.requestPrepareFailed,
          'private provider request file could not be removed',
        );
      }
    }
  }

  Future<void> _exerciseOrdinaryCase({
    required String token,
    required Map<String, dynamic> testCase,
  }) async {
    final id = testCase['id']! as String;
    final context = testCase['context']! as String;
    final modality = testCase['modality']! as String;
    final providerKind = testCase['providerKind']! as String;
    final remoteType = testCase['remoteType']! as String;
    final conversationKey = testCase['conversationKey']! as String;
    final messageId = testCase['messageId']! as String;
    final expectedTitle = testCase['expectedTitle']! as String;
    final expectedBody = testCase['expectedBody']! as String;
    final expectedPayload = testCase['expectedPayload']! as String;
    final expectedCategory = testCase['expectedCategory']! as String;
    final forbiddenDisplayValues = (testCase['forbiddenDisplayValues']! as List)
        .cast<String>();
    final data = (testCase['data']! as Map).cast<String, dynamic>();
    final trustedActorAccountPeerId = testCase['trustedActorAccountPeerId']
        ?.toString();
    final trustedActorTransportPeerId = testCase['trustedActorTransportPeerId']
        ?.toString();
    final trustedActorRole = testCase['trustedActorRole']?.toString();
    final trustedActorName = testCase['trustedActorName']?.toString();

    stage = 'ordinary_$id';
    await _prepareHeadlessCase(id);
    final sentAt = DateTime.now().toUtc();
    await _sendPrivateProviderRequest(
      token: token,
      data: data,
      kind: providerKind,
      id: id,
    );
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.receiveWait, id);
    try {
      await _waitForLog(
        (log) => log.contains('PUSH_BACKGROUND_MESSAGE_RECEIVED'),
        timeout: const Duration(minutes: 2),
        description: '$id receive marker',
      );
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.receiveTimeout,
        'ordinary receive wait failed',
      );
    }
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.cryptoWait, id);
    late final String backgroundLog;
    try {
      backgroundLog = await _waitForLog(
        (log) =>
            log.contains('PUSH_BACKGROUND_MESSAGE_CRYPTO_PLUGIN_OK') &&
            log.contains('PUSH_ANDROID_DATA_DECRYPT_OK'),
        timeout: const Duration(minutes: 2),
        description: '$id crypto/decrypt markers',
      );
      if (await _hasLivePackageActivity()) {
        throw StateError('Activity launched during ordinary callback');
      }
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cryptoTimeout,
        'ordinary crypto wait failed',
      );
    }
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.cardVerify, id);
    late final String displayLog;
    try {
      displayLog = await _waitForLog(
        (log) => log.contains('PUSH_BACKGROUND_NOTIFICATION_SHOWN'),
        timeout: const Duration(minutes: 1),
        description: '$id notification shown marker',
      );
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cardVerificationFailed,
        'ordinary notification display wait failed',
      );
    }
    final cards = await _syntheticNotificationCards();
    if (cards.length != 1) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cardVerificationFailed,
        'ordinary card count verification failed',
      );
    }
    final card = cards.single;
    final cardErrors = validateOrdinaryMessageNotificationCard(
      card,
      expectedTitle: expectedTitle,
      expectedBody: expectedBody,
    );
    if (cardErrors.isNotEmpty) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cardVerificationFailed,
        'ordinary trusted notification copy failed',
      );
    }
    if (card.category != expectedCategory) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cardVerificationFailed,
        'ordinary notification category failed',
      );
    }
    final rendered = '${card.title}\n${card.body}';
    if (forbiddenDisplayValues.any(rendered.contains)) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cardVerificationFailed,
        'ordinary notification rendered an untrusted name',
      );
    }
    if (context != 'direct') {
      if (trustedActorAccountPeerId == null ||
          trustedActorTransportPeerId == null ||
          trustedActorRole == null ||
          trustedActorName == null ||
          trustedActorAccountPeerId == trustedActorTransportPeerId ||
          data['sender_transport_peer_id'] != trustedActorTransportPeerId ||
          data.containsKey('sender_id') ||
          !card.body.startsWith('$trustedActorName: ')) {
        throw _campaignFailure(
          BackgroundCryptoCampaignReason.cardVerificationFailed,
          'ordinary trusted transport/member mapping failed',
        );
      }
      final expectedRole = context == 'announcement' ? 'admin' : 'writer';
      if (trustedActorRole != expectedRole) {
        throw _campaignFailure(
          BackgroundCryptoCampaignReason.cardVerificationFailed,
          'ordinary trusted role verification failed',
        );
      }
    }
    final notificationId = card.id;
    if (notificationId == null) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cardVerificationFailed,
        'ordinary notification ID unavailable',
      );
    }
    final priorId = _conversationNotificationIds[conversationKey];
    if (priorId != null && priorId != notificationId) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cardVerificationFailed,
        'ordinary stable notification replacement failed',
      );
    }
    if (_conversationNotificationIds.entries.any(
      (entry) => entry.key != conversationKey && entry.value == notificationId,
    )) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.cardVerificationFailed,
        'ordinary notification ID context collision',
      );
    }
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.routeVerify, id);
    final observedPayload = extractBackgroundNotificationShownPayload(
      displayLog,
    );
    if (observedPayload != expectedPayload) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.routeVerificationFailed,
        'ordinary route verification failed',
      );
    }
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.cardVerify, id);
    _conversationNotificationIds[conversationKey] = notificationId;
    final sequence = _ordinaryContextCounts.update(
      context,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    _capturedSafeMarkerLines.addAll(
      _safeMarkerLines('$backgroundLog\n$displayLog'),
    );
    _ordinaryEvidence.add(<String, Object?>{
      'id': id,
      'context': context,
      'modality': modality,
      'providerKind': providerKind,
      'remoteType': remoteType,
      'sentAt': sentAt.toIso8601String(),
      'sequenceWithinConversation': sequence,
      'messageIdSha256': _sha256(messageId),
      'trustedTitleSha256': _sha256(expectedTitle),
      'localizedBodySha256': _sha256(expectedBody),
      'routePayloadSha256': _sha256(expectedPayload),
      'notificationId': notificationId,
      'category': card.category,
      'matchingPixelCards': 1,
      'replacementObserved': priorId != null,
      'activityAbsentBeforeFcm': true,
      'activityAbsentDuringCallback': true,
      'providerSenderIdOmitted': context == 'direct'
          ? false
          : !data.containsKey('sender_id'),
      'providerTransportIdentityPresent': context == 'direct'
          ? false
          : data['sender_transport_peer_id'] == trustedActorTransportPeerId,
      'transportAndAccountIdentitiesDistinct': context == 'direct'
          ? false
          : trustedActorTransportPeerId != trustedActorAccountPeerId,
      if (context != 'direct')
        'trustedActorAccountIdSha256': _sha256(trustedActorAccountPeerId!),
      if (context != 'direct')
        'trustedActorTransportIdSha256': _sha256(trustedActorTransportPeerId!),
      if (context != 'direct') 'trustedActorRole': trustedActorRole,
      'trustedLocalActorPrefixVerified': context == 'direct'
          ? false
          : card.body.startsWith('$trustedActorName: '),
      'untrustedNamesAbsent': true,
    });
  }

  Future<void> _exerciseNegativeAuthorizationCase({
    required String token,
    required Map<String, dynamic> testCase,
  }) async {
    final id = testCase['id']! as String;
    final context = testCase['context']! as String;
    final providerKind = testCase['providerKind']! as String;
    final rejectionReason = testCase['rejectionReason']! as String;
    final expectedSuppressionReason =
        testCase['expectedSuppressionReason']! as String;
    final conversationKey = testCase['conversationKey']! as String;
    final messageId = testCase['messageId']! as String;
    final remoteType = testCase['remoteType']! as String;
    final data = (testCase['data']! as Map).cast<String, dynamic>();
    final claimPath =
        'files/ReactionNotificationClaims/NotificationServiceDedupe/'
        '$remoteType-$messageId';
    final toneIdentity = _sha256(conversationKey);
    final tonePaths = <String>[
      'files/ReactionNotificationClaims/NotificationToneLeases/'
          '$toneIdentity.lease',
      'files/ReactionNotificationClaims/NotificationToneLeases/'
          '.$toneIdentity.pending-tone',
    ];

    stage = 'authorization_negative_$id';
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.eligibility, id);
    if ((await _syntheticNotificationCards()).isNotEmpty) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.eligibilityFailed,
        'authorization case started with a reserved card',
      );
    }
    try {
      await _requireAppPrivatePathsAbsent(<String>[claimPath, ...tonePaths]);
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.eligibilityFailed,
        'authorization case started with reserved residue',
      );
    }
    await _prepareHeadlessCase(id);

    final sentAt = DateTime.now().toUtc();
    await _sendPrivateProviderRequest(
      token: token,
      data: data,
      kind: providerKind,
      id: id,
      expectedOutcome: 'suppress',
      rejectionReason: rejectionReason,
    );
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.receiveWait, id);
    try {
      await _waitForLog(
        (log) => log.contains('PUSH_BACKGROUND_MESSAGE_RECEIVED'),
        timeout: const Duration(minutes: 2),
        description: '$id receive marker',
      );
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.receiveTimeout,
        'authorization receive wait failed',
      );
    }
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.eligibility, id);
    try {
      await _waitForLog(
        (log) => backgroundCryptoExpectedAuthorizationSuppressionObserved(
          log,
          reason: expectedSuppressionReason,
        ),
        timeout: const Duration(minutes: 2),
        description: '$id authenticated local-state suppression marker',
      );
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.eligibilityFailed,
        'authorization eligibility wait failed',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final settledLog = (await _adb(['logcat', '-d'])).stdout;
    if (!backgroundCryptoExpectedAuthorizationSuppressionObserved(
      settledLog,
      reason: expectedSuppressionReason,
    )) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.eligibilityFailed,
        'authorization terminal suppression proof failed',
      );
    }
    final forbiddenStageFamilies =
        backgroundCryptoForbiddenAuthorizationStageFamilies(settledLog);
    if (forbiddenStageFamilies.isNotEmpty) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.eligibilityFailed,
        'authorization crossed a forbidden stage family',
      );
    }
    if (await _hasLivePackageActivity()) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.eligibilityFailed,
        'authorization launched an Activity',
      );
    }
    if ((await _syntheticNotificationCards()).isNotEmpty) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.eligibilityFailed,
        'authorization created a notification card',
      );
    }
    try {
      await _requireAppPrivatePathsAbsent(<String>[claimPath, ...tonePaths]);
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.eligibilityFailed,
        'authorization created reserved residue',
      );
    }

    _negativeAuthorizationEvidence.add(<String, Object?>{
      'id': id,
      'context': context,
      'rejectionReason': rejectionReason,
      'sentAt': sentAt.toIso8601String(),
      'messageIdSha256': _sha256(messageId),
      'providerSenderAccountIdOmitted': !data.containsKey('sender_id'),
      'providerTransportFieldState':
          data.containsKey('sender_transport_peer_id')
          ? rejectionReason == 'unknown_transport'
                ? 'reserved-unknown'
                : 'trusted-local-non-admin'
          : 'omitted',
      'suppressedBeforeDecrypt': true,
      'expectedEligibilitySuppressionObserved': true,
      'forbiddenDownstreamStageFamiliesObserved': 0,
      'matchingPixelCards': 0,
      'eventClaimFiles': 0,
      'toneLeaseFiles': 0,
      'shownMarkers': 0,
      'activityAbsentBeforeFcm': true,
      'activityAbsentDuringCallback': true,
    });
  }

  Future<void> _requireAppPrivatePathsAbsent(List<String> paths) async {
    for (final path in paths) {
      final probe = await _runAs(
        ['ls', path],
        allowFailure: true,
        suppressVerbose: true,
      );
      if (probe.exitCode == 0) {
        throw _CampaignFailure(stage, 'reserved authorization residue exists');
      }
    }
  }

  Future<void> _runProviderDiagnosticOnly({
    required String token,
    required Map<String, dynamic> testCase,
  }) async {
    const id = 'direct-text';
    if (testCase['id'] != id || testCase['providerKind'] != 'chat') {
      throw const _CampaignFailure(
        'provider_diagnostic',
        'provider diagnostic fixture row is not the reserved direct text row',
      );
    }
    stage = 'provider_diagnostic';
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.requestPrepare, id);
    try {
      _secretTempDir = await Directory.systemTemp.createTemp(
        'mknoon-tc256-fcm-validate-',
      );
      await _captureNotificationBaseline();
      await _adb(['logcat', '-c']);
      await _adbShell(['am', 'force-stop', appPackage]);
      await _waitForProcessAndTaskAbsent();
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.requestPrepareFailed,
        'provider diagnostic quiescence failed',
      );
    }
    final receipt = await _validateProviderOnly(
      token: token,
      data: (testCase['data']! as Map).cast<String, dynamic>(),
      kind: testCase['providerKind']! as String,
      id: id,
    );
    _enterCampaignPhase(BackgroundCryptoCampaignPhase.eligibility, id);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final log = (await _adb(['logcat', '-d'])).stdout;
    const forbiddenCallbacks = <String>[
      'PUSH_BACKGROUND_MESSAGE_RECEIVED',
      'PUSH_BACKGROUND_MESSAGE_CRYPTO_PLUGIN_OK',
      'PUSH_ANDROID_DATA_DECRYPT_OK',
      'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
    ];
    if (forbiddenCallbacks.any(log.contains) ||
        (await _syntheticNotificationCards()).isNotEmpty ||
        await _hasLivePackageActivity()) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.eligibilityFailed,
        'validate-only provider diagnostic crossed a delivery boundary',
      );
    }

    stage = 'provider_diagnostic_cleanup';
    _currentCampaignPhase = null;
    _currentSyntheticCaseId = null;
    final cleanupLog = await _runCleanupCommand(mode: 'recovery');
    await _verifyPrivateBundleAbsent();
    _syntheticCleanupConfirmed = true;
    await _writeProviderDiagnosticArtifact(
      cleanupLog: cleanupLog,
      receipt: receipt,
      subjectTokenSha256: sha256.convert(utf8.encode(token.trim())).toString(),
    );
  }

  Future<Map<String, Object?>> _validateProviderOnly({
    required String token,
    required Map<String, dynamic> data,
    required String kind,
    required String id,
  }) async {
    final temp = _secretTempDir;
    if (temp == null) {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.requestPrepareFailed,
        'private validation directory is unavailable',
      );
    }
    final requestFile = File('${temp.path}/provider-validate-only.json');
    try {
      await requestFile.writeAsString(
        jsonEncode(<String, Object?>{
          'token': token,
          'data': data,
          'transportContract': <String, Object?>{
            'caseId': id,
            'expectedOutcome': 'display',
          },
        }),
        flush: true,
      );
      _providerValidationAttempts++;
      _enterCampaignPhase(BackgroundCryptoCampaignPhase.oauth, id);
      final provider = await _run('node', [
        'scripts/send_fcm_provider_probe.js',
        '--request-file',
        requestFile.path,
        '--service-account',
        serviceAccount.path,
        '--mode',
        'data-only',
        '--kind',
        kind,
        '--probe-id',
        'tc256-validate-${DateTime.now().toUtc().microsecondsSinceEpoch}',
        '--validate-only',
      ]);
      late final Map<String, Object?> receipt;
      try {
        receipt = parseBackgroundCryptoProviderResult(
          provider.exitCode == 0 ? provider.stdout : provider.stderr,
          exitCode: provider.exitCode,
          expectValidateOnly: true,
        );
      } on FormatException {
        _enterCampaignPhase(BackgroundCryptoCampaignPhase.requestPrepare, id);
        throw _campaignFailure(
          BackgroundCryptoCampaignReason.requestPrepareFailed,
          'provider diagnostic result schema was rejected',
        );
      }
      _lastProviderDiagnostic = receipt;
      _providerReceiptEvidence.add(
        Map<String, Object?>.unmodifiable(<String, Object?>{
          'caseId': id,
          ...receipt,
        }),
      );
      if (provider.exitCode == 0) _providerValidationSucceeded++;
      _enterCampaignPhase(
        receipt['stage'] == 'oauth'
            ? BackgroundCryptoCampaignPhase.oauth
            : BackgroundCryptoCampaignPhase.providerSend,
        id,
      );
      return receipt;
    } on _CampaignFailure {
      rethrow;
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.requestPrepareFailed,
        'provider diagnostic request preparation failed',
      );
    } finally {
      try {
        if (await requestFile.exists()) await requestFile.delete();
        if (await requestFile.exists()) {
          throw const FileSystemException(
            'private provider validation request survived deletion',
          );
        }
      } on FileSystemException {
        _enterCampaignPhase(BackgroundCryptoCampaignPhase.requestPrepare, id);
        throw _campaignFailure(
          BackgroundCryptoCampaignReason.requestPrepareFailed,
          'private provider validation request could not be removed',
        );
      }
    }
  }

  Future<void> _requireDevice() async {
    final devices = await _run('adb', ['devices']);
    if (!devices.stdout.contains('$recipient\tdevice')) {
      throw _CampaignFailure(
        stage,
        'Android target is unavailable.',
        environmentBlocked: true,
      );
    }
    final abi = (await _adbShell([
      'getprop',
      'ro.product.cpu.abi',
    ], suppressVerbose: true)).stdout.trim();
    _androidTargetPlatform = switch (abi) {
      'arm64-v8a' => 'android-arm64',
      'armeabi-v7a' => 'android-arm',
      'x86_64' => 'android-x64',
      _ => throw _CampaignFailure(
        stage,
        'Android target ABI is unsupported by the Flutter preflight build.',
        environmentBlocked: true,
      ),
    };
    final sdkRaw = (await _adbShell([
      'getprop',
      'ro.build.version.sdk',
    ], suppressVerbose: true)).stdout.trim();
    _androidSdk = int.tryParse(sdkRaw) ?? 0;
    if (_androidSdk <= 0) {
      throw _CampaignFailure(
        stage,
        'Android target SDK could not be resolved.',
        environmentBlocked: true,
      );
    }
  }

  Future<void> _backupInstalledApp() async {
    final paths = await _adbShell(['pm', 'path', appPackage]);
    final installedPaths = paths.stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('package:'))
        .map((line) => line.substring('package:'.length))
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (installedPaths.isEmpty) {
      throw _CampaignFailure(
        stage,
        'the existing candidate app is unavailable for restoration',
        environmentBlocked: true,
      );
    }
    await _captureNotificationPermission();

    final backupDir = await Directory.systemTemp.createTemp(
      'mknoon-tc256-installed-app-',
    );
    _installedAppBackupDir = backupDir;
    final localApk = File(_debugApkPath);
    _localApkExisted = await localApk.exists();
    if (_localApkExisted) {
      try {
        _localApkBackup = await localApk.copy(
          '${backupDir.path}/local-app-debug.apk',
        );
      } on FileSystemException {
        throw _CampaignFailure(stage, 'failed to back up local debug APK');
      }
    }
    for (var index = 0; index < installedPaths.length; index++) {
      final destination = File('${backupDir.path}/installed-$index.apk');
      await _adb(['pull', installedPaths[index], destination.path]);
      if (!await destination.exists() || await destination.length() == 0) {
        throw _CampaignFailure(stage, 'failed to back up installed APK');
      }
      _installedAppApks.add(destination);
    }
    _backupCaptured = true;
  }

  Future<void> _captureNotificationPermission() async {
    if (_androidSdk < 33) {
      _notificationPermissionInitiallyGranted = true;
      _notificationPermissionCaptured = true;
      return;
    }
    final granted = await _isNotificationPermissionGranted();
    _notificationPermissionInitiallyGranted = granted;
    _notificationPermissionCaptured = true;
  }

  Future<bool> _isNotificationPermissionGranted() async {
    final result = await _adbShell([
      'dumpsys',
      'package',
      appPackage,
    ], suppressVerbose: true);
    final match = RegExp(
      r'android\.permission\.POST_NOTIFICATIONS:\s+granted=(true|false)',
    ).firstMatch(result.stdout);
    if (match == null) {
      throw _CampaignFailure(
        stage,
        'notification permission state could not be resolved',
      );
    }
    return match.group(1) == 'true';
  }

  Future<void> _restoreNotificationPermission() async {
    if (!_notificationPermissionCaptured || _androidSdk < 33) return;
    if (await _isNotificationPermissionGranted() ==
        _notificationPermissionInitiallyGranted) {
      return;
    }
    final operation = _notificationPermissionInitiallyGranted
        ? 'grant'
        : 'revoke';
    await _adbShell([
      'pm',
      operation,
      appPackage,
      _postNotificationsPermission,
    ]);
    final granted = await _isNotificationPermissionGranted();
    if (granted != _notificationPermissionInitiallyGranted) {
      throw _CampaignFailure(
        'restore_notification_permission',
        'notification permission did not return to its preflight state',
      );
    }
  }

  Future<void> _restoreInstalledApp() async {
    if (!_replacementAttempted || _installedAppApks.isEmpty) return;
    final args = _installedAppApks.length == 1
        ? <String>['install', '-r', '-t', '-d', _installedAppApks.single.path]
        : <String>[
            'install-multiple',
            '-r',
            '-t',
            '-d',
            ..._installedAppApks.map((file) => file.path),
          ];
    await _adb(args);
    final restoredPaths =
        (await _adbShell(['pm', 'path', appPackage], suppressVerbose: true))
            .stdout
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.startsWith('package:'))
            .map((line) => line.substring('package:'.length))
            .where((path) => path.isNotEmpty)
            .toList(growable: false);
    if (restoredPaths.length != _installedAppApks.length) {
      throw _CampaignFailure(
        'restore_installed_app',
        'restored candidate APK set differs from its backup',
      );
    }
    final expectedHashes = <String>[];
    for (final file in _installedAppApks) {
      expectedHashes.add(await _sha256File(file));
    }
    final restoredHashes = <String>[];
    for (final path in restoredPaths) {
      final output = await _adbShell([
        'sha256sum',
        path,
      ], suppressVerbose: true);
      final hash = output.stdout.trim().split(RegExp(r'\s+')).firstOrNull;
      if (hash == null || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)) {
        throw _CampaignFailure(
          'restore_installed_app',
          'restored candidate APK hash could not be resolved',
        );
      }
      restoredHashes.add(hash.toLowerCase());
    }
    expectedHashes.sort();
    restoredHashes.sort();
    if (!_sameStrings(expectedHashes, restoredHashes)) {
      throw _CampaignFailure(
        'restore_installed_app',
        'restored candidate APK bytes differ from their backup',
      );
    }
    _restoredInstalledApkHashes
      ..clear()
      ..addAll(restoredHashes);
  }

  Future<void> _restoreLocalBuildArtifact() async {
    if (!_backupCaptured) return;
    final localApk = File(_debugApkPath);
    final backup = _localApkBackup;
    try {
      if (backup != null && await backup.exists()) {
        await localApk.parent.create(recursive: true);
        await backup.copy(localApk.path);
        if (await _sha256File(backup) != await _sha256File(localApk)) {
          throw const FileSystemException(
            'restored local debug APK hash differs from backup',
          );
        }
      } else if (!_localApkExisted && await localApk.exists()) {
        await localApk.delete();
      }
    } on FileSystemException {
      throw _CampaignFailure(stage, 'failed to restore local debug APK');
    }
  }

  Future<String> _sha256File(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  Future<void> _recordRestorationSuccess() async {
    final artifact = File(_passArtifactPath);
    if (!await artifact.exists()) return;
    try {
      final decoded = jsonDecode(await artifact.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('TC-07 artifact is not a JSON object');
      }
      final cleanup = decoded['cleanup'];
      if (cleanup is! Map<String, dynamic>) {
        throw const FormatException('TC-07 cleanup record is missing');
      }
      cleanup['installedCandidateRestored'] = true;
      cleanup['installedCandidateBytesVerified'] = true;
      cleanup['installedCandidateApkSha256'] = List<String>.unmodifiable(
        _restoredInstalledApkHashes,
      );
      cleanup['localBuildArtifactRestoredToPriorState'] = true;
      cleanup['localBuildArtifactBytesVerified'] = true;
      cleanup['notificationPermissionRestored'] = true;
      cleanup['notificationPermissionInitiallyGranted'] =
          _notificationPermissionInitiallyGranted;
      if (_secretTempDir != null) {
        cleanup['privateProviderTempDeleted'] = _privateProviderTempDeleted;
        decoded['privateProviderTempDeleted'] = _privateProviderTempDeleted;
      }
      if (_successfulRestorationEvidence case final evidence?) {
        decoded['successfulRestorationEvidence'] = evidence;
      }
      await artifact.writeAsString(
        const JsonEncoder.withIndent('  ').convert(decoded),
        flush: true,
      );
      final staleFailure = File(_failureArtifactPath);
      if (await staleFailure.exists()) await staleFailure.delete();
    } on Object {
      if (await artifact.exists()) await artifact.delete();
      throw const _CampaignFailure(
        'finalize_restoration_evidence',
        'failed to finalize cleanup evidence',
      );
    }
  }

  Future<void> _launchExplicitActivityClearingStoppedState() async {
    // An explicit component start clears Android's force-stop/stopped state.
    await _adbShell(['am', 'start', '-W', '-n', '$appPackage/.MainActivity']);
  }

  Future<void> _quiescePackageForPushDelivery() async {
    await _adbShell(['input', 'keyevent', 'KEYCODE_HOME']);
    await Future<void>.delayed(const Duration(seconds: 1));
    await _adbShell(['am', 'kill', appPackage]);
    if (!await _processAndTaskAbsentWithin(const Duration(seconds: 5))) {
      // `stop-app` preserves ordinary push wake eligibility. Never fall back to
      // `am force-stop` here: that sets Android's stopped-package bit and would
      // require an explicit relaunch before any data-only FCM delivery.
      await _adbShell(['cmd', 'activity', 'stop-app', appPackage]);
    }
    await _waitForProcessAndTaskAbsent();
  }

  Future<void> _requirePackageEligibleForDataOnlyFcm(String caseId) async {
    try {
      final currentUser = (await _adbShell([
        'am',
        'get-current-user',
      ], suppressVerbose: true)).stdout.trim();
      final userId = int.tryParse(currentUser);
      if (userId == null || userId < 0) {
        throw const FormatException('Android current user is invalid');
      }
      final packageDump = (await _adbShell([
        'dumpsys',
        'package',
        appPackage,
      ], suppressVerbose: true)).stdout;
      // This is the final device-state read before the provider process starts.
      if (androidPackageStoppedForUser(
        packageDump,
        packageName: appPackage,
        userId: userId,
      )) {
        throw StateError(
          'force-stopped Android package cannot receive data-only FCM',
        );
      }
      _providerDeliveryEligibilityEvidence.add(<String, Object?>{
        'caseId': caseId,
        'userId': userId,
        'stopped': false,
      });
    } on Object {
      throw _campaignFailure(
        BackgroundCryptoCampaignReason.deliveryEligibilityFailed,
        'Android package delivery eligibility assertion failed',
      );
    }
  }

  Future<void> _prepareFixtureColdLaunch() async {
    _lastSetupPhase = BackgroundCryptoSetupPhase.appQuiescence;
    try {
      if (!isValidAndroidAppPackage(appPackage)) {
        throw const FormatException('invalid validated package');
      }
      await _adbShell(['am', 'force-stop', appPackage]);
      await _waitForProcessAndTaskAbsent();
    } on Object {
      throw _CampaignFailure(
        stage,
        'fixture cold-launch quiescence failed',
        setupReason: BackgroundCryptoSetupReason.quiescenceFailed,
        setupPhase: BackgroundCryptoSetupPhase.appQuiescence,
      );
    }
    await _adb(['logcat', '-c']);
    _lastSetupPhase = null;
    await _launchExplicitActivityClearingStoppedState();
  }

  Future<bool> _processAndTaskAbsentWithin(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final pid = await _adbShell(
        ['pidof', appPackage],
        allowFailure: true,
        suppressVerbose: true,
      );
      final activities = await _adbShell([
        'dumpsys',
        'activity',
        'activities',
      ], suppressVerbose: true);
      if (androidProcessAndTaskAreAbsent(
        pidExitCode: pid.exitCode,
        pidOutput: pid.stdout,
        pidStderr: pid.stderr,
        activityDump: activities.stdout,
        packageName: appPackage,
      )) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<void> _waitForProcessAndTaskAbsent() async {
    if (await _processAndTaskAbsentWithin(const Duration(seconds: 20))) {
      return;
    }
    throw const _ProcessAndTaskAbsenceTimeout();
  }

  Future<bool> _hasLivePackageActivity() async {
    final output = await _adbShell([
      'dumpsys',
      'activity',
      'activities',
    ], suppressVerbose: true);
    return androidActivityIsAttached(output.stdout, packageName: appPackage);
  }

  Future<String> _waitForLog(
    bool Function(String log) predicate, {
    required Duration timeout,
    required String description,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final log = (await _run('adb', ['-s', recipient, 'logcat', '-d'])).stdout;
      final phaseMarker = _latestPreflightMarker(log, event: 'setup_phase');
      _lastSetupPhase =
          backgroundCryptoSetupPhaseFromWire(phaseMarker?['phase']) ??
          _lastSetupPhase;
      final clearPhaseMarker = _latestPreflightMarker(
        log,
        event: 'notification_clear_phase',
      );
      _lastNotificationClearPhase =
          backgroundCryptoNotificationClearPhaseFromWire(
            clearPhaseMarker?['phase'],
          ) ??
          _lastNotificationClearPhase;
      if (backgroundCryptoNotificationClearCommandAckFromLog(log)) {
        _notificationClearCommandAcknowledged = true;
      }
      if (log.contains('"event":"notification_clear_error"')) {
        final marker = _latestPreflightMarker(
          log,
          event: 'notification_clear_error',
        );
        final phase = backgroundCryptoNotificationClearPhaseFromWire(
          marker?['phase'],
        );
        final reason = backgroundCryptoNotificationClearReasonFromWire(
          marker?['reason'],
        );
        throw _CampaignFailure(
          stage,
          'device notification clear subphase failed',
          campaignReason: _currentCampaignPhase == null
              ? null
              : BackgroundCryptoCampaignReason.cardVerificationFailed,
          campaignPhase: _currentCampaignPhase,
          syntheticCaseId: _currentCampaignPhase == null
              ? null
              : _currentSyntheticCaseId,
          notificationClearPhase: phase ?? _lastNotificationClearPhase,
          notificationClearReason:
              reason ?? BackgroundCryptoNotificationClearReason.operationFailed,
          notificationClearBoundary:
              BackgroundCryptoNotificationClearBoundary.appPhase,
          notificationClearObservation:
              BackgroundCryptoNotificationClearObservation.observed,
        );
      }
      if (log.contains('"event":"setup_error"')) {
        final marker = _latestPreflightMarker(log, event: 'setup_error');
        final diagnostic = _redactedSetupDiagnostic(
          marker,
          fallbackPhase: _lastSetupPhase ?? BackgroundCryptoSetupPhase.appInit,
        );
        throw _CampaignFailure(
          stage,
          'device emitted setup_error',
          type: '_CampaignFailure',
          setupReason: diagnostic.reason,
          setupPhase: diagnostic.phase,
        );
      }
      if (description == 'synthetic-notification cleanup acknowledgement') {
        try {
          final completion = backgroundCryptoNotificationClearCompletionFromLog(
            log,
          );
          if (completion != null) {
            _lastNotificationClearPhase =
                BackgroundCryptoNotificationClearPhase.markerWrite;
            return log;
          }
        } on FormatException {
          throw _CampaignFailure(
            stage,
            'notification clear completion marker schema was rejected',
            campaignReason: _currentCampaignPhase == null
                ? null
                : BackgroundCryptoCampaignReason.cardVerificationFailed,
            campaignPhase: _currentCampaignPhase,
            syntheticCaseId: _currentCampaignPhase == null
                ? null
                : _currentSyntheticCaseId,
            notificationClearPhase:
                BackgroundCryptoNotificationClearPhase.markerWrite,
            notificationClearReason:
                BackgroundCryptoNotificationClearReason.rejectedSchema,
            notificationClearBoundary:
                BackgroundCryptoNotificationClearBoundary.completionSchema,
            notificationClearObservation:
                BackgroundCryptoNotificationClearObservation.observed,
          );
        }
      }
      if (predicate(log)) return log;
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    final diagnostic = backgroundCryptoHostSetupFailure(
      lastObservedPhase: _lastSetupPhase,
    );
    if (description == 'synthetic-notification cleanup acknowledgement') {
      throw _CampaignFailure(
        stage,
        'notification clear completion marker was missing',
        campaignReason: _currentCampaignPhase == null
            ? null
            : BackgroundCryptoCampaignReason.cardVerificationFailed,
        campaignPhase: _currentCampaignPhase,
        syntheticCaseId: _currentCampaignPhase == null
            ? null
            : _currentSyntheticCaseId,
        notificationClearPhase: _lastNotificationClearPhase,
        notificationClearReason:
            BackgroundCryptoNotificationClearReason.missingMarker,
        notificationClearBoundary: _lastNotificationClearPhase != null
            ? BackgroundCryptoNotificationClearBoundary.appPhase
            : _notificationClearCommandAcknowledged
            ? BackgroundCryptoNotificationClearBoundary.commandAck
            : BackgroundCryptoNotificationClearBoundary.appLaunch,
        notificationClearObservation: _lastNotificationClearPhase == null
            ? BackgroundCryptoNotificationClearObservation.notObserved
            : BackgroundCryptoNotificationClearObservation.observed,
      );
    }
    throw _CampaignFailure(
      stage,
      'timed out waiting for $description',
      setupReason: stage == 'setup' ? diagnostic.reason : null,
      setupPhase: stage == 'setup' ? diagnostic.phase : null,
    );
  }

  List<String> _safeMarkerLines(String log) {
    const allowed = <String>[
      'PUSH_BACKGROUND_MESSAGE_RECEIVED',
      'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
      'PUSH_BACKGROUND_MESSAGE_CRYPTO_PLUGIN_OK',
      'PUSH_ANDROID_DATA_DECRYPT_OK',
      'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
      'cleanup_complete',
      'node:startup_timing',
      'post_foreground_node_started',
    ];
    return log
        .split('\n')
        .where((line) {
          if (!allowed.any(line.contains)) return false;
          return !line.contains('ciphertext') &&
              !line.contains('secretKey') &&
              !line.contains('fcmToken');
        })
        .toList(growable: false);
  }

  Future<_CommandOutput> _adb(
    List<String> args, {
    bool allowFailure = false,
    bool suppressVerbose = false,
  }) => _runChecked(
    'adb',
    ['-s', recipient, ...args],
    allowFailure: allowFailure,
    suppressVerbose: suppressVerbose,
  );

  Future<_CommandOutput> _adbShell(
    List<String> args, {
    bool allowFailure = false,
    bool suppressVerbose = false,
  }) => _adb(
    ['shell', ...args],
    allowFailure: allowFailure,
    suppressVerbose: suppressVerbose,
  );

  Future<_CommandOutput> _runAs(
    List<String> args, {
    bool allowFailure = false,
    bool suppressVerbose = false,
  }) => _adbShell(
    ['run-as', appPackage, ...args],
    allowFailure: allowFailure,
    suppressVerbose: suppressVerbose,
  );

  Future<_CommandOutput> _runChecked(
    String executable,
    List<String> args, {
    bool allowFailure = false,
    bool suppressVerbose = false,
  }) async {
    final output = await _run(executable, args);
    if (verbose && !suppressVerbose) {
      stdout.write(output.stdout);
      stderr.write(output.stderr);
    }
    if (!allowFailure && output.exitCode != 0) {
      final diagnostic = backgroundCryptoHostSetupFailure(
        lastObservedPhase: _lastSetupPhase,
      );
      final campaignPhase = _currentCampaignPhase;
      throw _CampaignFailure(
        stage,
        '$executable command failed with exit ${output.exitCode}',
        environmentBlocked: stage == 'preflight' || stage == 'build',
        setupReason: stage == 'setup' ? diagnostic.reason : null,
        setupPhase: stage == 'setup' ? diagnostic.phase : null,
        campaignReason: campaignPhase == null
            ? null
            : BackgroundCryptoCampaignReason.operationFailed,
        campaignPhase: campaignPhase,
        syntheticCaseId: campaignPhase == null ? null : _currentSyntheticCaseId,
      );
    }
    return output;
  }

  Future<_CommandOutput> _run(String executable, List<String> args) async {
    final result = await Process.run(executable, args);
    return _CommandOutput(
      result.exitCode,
      result.stdout.toString(),
      result.stderr.toString(),
    );
  }
}

String? _valueFor(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    final current = args[index];
    if (current == name && index + 1 < args.length) return args[index + 1];
    if (current.startsWith('$name=')) {
      return current.substring(name.length + 1);
    }
  }
  return null;
}

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();
