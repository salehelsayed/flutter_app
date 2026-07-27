import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_pairing_session_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';
import 'package:flutter_app/features/account_migration/application/migration_transfer_keep_alive.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/presentation/models/account_migration_ui_state.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_journey_screen.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_screen.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

typedef AccountMigrationQrBuildFn =
    Future<(BuildMigrationQrPayloadResult, MigrationQrBuildOutput?)> Function();
typedef AccountMigrationQrScanFn =
    Future<String?> Function(BuildContext context);
typedef AccountMigrationExportAuthorizeFn =
    Future<
      (
        MigrationExportAuthorizationResult,
        AuthenticatedMigrationChannelTranscript?,
      )
    >
    Function(MigrationQrPayload payload);

class AccountMigrationJourneyWired extends StatefulWidget {
  final AccountMigrationRole role;
  final Bridge? bridge;
  final SecureKeyStore secureKeyStore;
  final IdentityRepository? identityRepository;
  final AccountMigrationQrBuildFn? buildQrPayload;
  final AccountMigrationQrScanFn? scanQr;
  final AccountMigrationExportAuthorizeFn? authorizeExport;
  final AccountMigrationTransferRunFn? runTransfer;
  final AccountMigrationSizeGate? sizeGate;
  final String? initialScannedQr;
  final AccountMigrationReceiverStartFn? startReceiver;
  final AccountMigrationReceiverStopFn? stopReceiver;
  final AccountMigrationReceiverEvents? receiverEvents;
  final Future<void> Function()? onReceiverActivated;
  final bool receiverActivationOwnedByParent;
  final BackgroundPreference backgroundPreference;

  /// Holds the platform keep-alive (Android foreground service / iOS
  /// background task) while a transfer or receiver is active, so
  /// backgrounding the app does not suspend the move. Injectable for tests.
  final MigrationTransferKeepAlive? transferKeepAlive;

  const AccountMigrationJourneyWired.newPhone({
    super.key,
    required this.bridge,
    required this.secureKeyStore,
    this.buildQrPayload,
    this.startReceiver,
    this.stopReceiver,
    this.receiverEvents,
    this.onReceiverActivated,
    this.receiverActivationOwnedByParent = false,
    this.transferKeepAlive,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  }) : role = AccountMigrationRole.newPhone,
       identityRepository = null,
       scanQr = null,
       authorizeExport = null,
       runTransfer = null,
       sizeGate = null,
       initialScannedQr = null;

  const AccountMigrationJourneyWired.oldPhone({
    super.key,
    required this.secureKeyStore,
    required this.identityRepository,
    this.scanQr,
    this.authorizeExport,
    this.runTransfer,
    this.sizeGate,
    this.initialScannedQr,
    this.transferKeepAlive,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  }) : role = AccountMigrationRole.oldPhone,
       bridge = null,
       buildQrPayload = null,
       startReceiver = null,
       stopReceiver = null,
       receiverEvents = null,
       onReceiverActivated = null,
       receiverActivationOwnedByParent = false;

  @override
  State<AccountMigrationJourneyWired> createState() =>
      _AccountMigrationJourneyWiredState();
}

class _AccountMigrationJourneyWiredState
    extends State<AccountMigrationJourneyWired> {
  AccountMigrationQrPresentationState _qrState =
      const AccountMigrationQrPresentationState.loading();
  AccountMigrationOldPhonePresentationState _oldPhoneState =
      const AccountMigrationOldPhonePresentationState.waitingForScan();
  AccountMigrationProgressStage? _progressStage;
  String? _progressErrorText;
  AuthenticatedMigrationChannelTranscript? _authorizedTranscript;

  /// Confirm-stage size estimate, kept so the transfer caption can show the
  /// move's total size alongside chunk progress.
  AccountMigrationMoveSizeEstimate? _moveSizeEstimate;
  var _transferRunId = 0;
  var _transferCancellationRequested = false;
  var _transferRunning = false;
  var _receiverFinalizationLocked = false;
  String? _activeReceiverSessionId;
  StreamSubscription<AccountMigrationReceiverEvent>? _receiverEventsSub;
  late final MigrationTransferKeepAlive _transferKeepAlive =
      widget.transferKeepAlive ?? MigrationTransferKeepAlive();
  var _receiverKeepAliveHeld = false;

  // Deterministic segment progress for the transferring stage (both roles:
  // sender segment POSTs and receiver verified segments).
  int? _segmentsDone;
  int? _segmentsTotal;
  DateTime? _segmentProgressStartedAt;

  @override
  void initState() {
    super.initState();
    if (widget.role == AccountMigrationRole.newPhone) {
      _receiverEventsSub = widget.receiverEvents?.listen(_handleReceiverEvent);
      unawaited(_loadNewPhoneQr());
    } else {
      final initialScannedQr = widget.initialScannedQr;
      if (initialScannedQr != null && initialScannedQr.trim().isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            _authorizeScannedQr(initialScannedQr, source: 'initial_scanned_qr'),
          );
        });
      }
    }
  }

  Future<void> _loadNewPhoneQr() async {
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_NEW_PHONE_QR_LOAD_START',
      details: {},
    );
    _resetSegmentProgress();
    setState(() {
      _progressStage = null;
      _progressErrorText = null;
      _qrState = const AccountMigrationQrPresentationState.loading();
    });

    final builder = widget.buildQrPayload ?? _defaultBuildQrPayload;
    final (result, output) = await builder();
    if (!mounted) return;

    var presentationState = AccountMigrationQrPresentationState.fromBuildResult(
      result: result,
      output: output,
    );
    if (result == BuildMigrationQrPayloadResult.success && output != null) {
      final receiverStarter = widget.startReceiver;
      if (receiverStarter != null) {
        final receiverResult = await receiverStarter(output);
        if (!mounted) return;
        if (receiverResult.isStarted) {
          _activeReceiverSessionId = output.payload.sessionId;
          if (!_receiverKeepAliveHeld) {
            _receiverKeepAliveHeld = true;
            unawaited(_transferKeepAlive.acquire(reason: 'new_phone_receiver'));
          }
        } else {
          presentationState =
              AccountMigrationQrPresentationState.receiverFailed(
                receiverResult.safeMessage ??
                    'This phone could not start local transfer. Try again.',
              );
        }
      }
    }

    setState(() {
      _qrState = presentationState;
    });

    emitFlowEvent(
      layer: 'FL',
      event:
          presentationState.status == AccountMigrationQrPresentationStatus.ready
          ? 'ACCOUNT_MIGRATION_NEW_PHONE_QR_READY'
          : 'ACCOUNT_MIGRATION_NEW_PHONE_QR_FAILED',
      details: {
        'result': result.name,
        'status': presentationState.status.name,
        if (output != null) 'sessionId': output.payload.sessionId,
      },
    );
  }

  Future<(BuildMigrationQrPayloadResult, MigrationQrBuildOutput?)>
  _defaultBuildQrPayload() {
    final bridge = widget.bridge;
    if (bridge == null) {
      return Future.value((BuildMigrationQrPayloadResult.keygenFailed, null));
    }
    return buildMigrationQrPayload(
      bridge: bridge,
      repository: SecureKeyStoreMigrationPairingSessionRepository(
        secureKeyStore: widget.secureKeyStore,
      ),
    );
  }

  Future<void> _handleScanQr() async {
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_OLD_PHONE_SCAN_START',
      details: {},
    );
    setState(() {
      _progressStage = null;
      _progressErrorText = null;
      _authorizedTranscript = null;
      _oldPhoneState =
          const AccountMigrationOldPhonePresentationState.authorizing();
    });

    final scanner = widget.scanQr ?? _scanMigrationQr;
    final scanned = await scanner(context);
    if (!mounted) return;

    if (scanned == null || scanned.trim().isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_OLD_PHONE_SCAN_CANCELLED',
        details: {},
      );
      setState(() {
        _oldPhoneState =
            const AccountMigrationOldPhonePresentationState.waitingForScan();
      });
      return;
    }

    await _authorizeScannedQr(scanned, source: 'scanner');
  }

  Future<void> _authorizeScannedQr(
    String scanned, {
    required String source,
  }) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_OLD_PHONE_QR_AUTHORIZE_START',
      details: {'source': source},
    );
    setState(() {
      _progressStage = null;
      _progressErrorText = null;
      _authorizedTranscript = null;
      _oldPhoneState =
          const AccountMigrationOldPhonePresentationState.authorizing();
    });

    final (parseResult, payload) = parseMigrationQrPayload(qrData: scanned);
    if (parseResult != MigrationQrParseResult.success || payload == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_OLD_PHONE_QR_PARSE_FAILED',
        details: {'result': parseResult.name},
      );
      setState(() {
        _oldPhoneState = AccountMigrationOldPhonePresentationState.failed(
          _parseErrorText(parseResult),
        );
      });
      return;
    }

    try {
      final authorizer = widget.authorizeExport ?? _defaultAuthorizeExport;
      final (result, transcript) = await authorizer(payload);
      if (!mounted) return;

      if (result != MigrationExportAuthorizationResult.authorized ||
          transcript == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_OLD_PHONE_AUTHORIZATION_FAILED',
          details: {'result': result.name},
        );
        setState(() {
          _oldPhoneState = AccountMigrationOldPhonePresentationState.failed(
            _authorizationErrorText(result),
          );
        });
        return;
      }

      AccountMigrationMoveSizeEstimate? sizeEstimate;
      String? sizeCapBlockedMessage;
      final sizeGate = widget.sizeGate;
      if (sizeGate != null) {
        try {
          sizeEstimate = await sizeGate.estimateMoveSize();
          if (!mounted) return;
          final maxAccountBytes = sizeGate.policy.maxAccountBytes;
          if (sizeEstimate.totalBytes > maxAccountBytes) {
            sizeCapBlockedMessage = accountMigrationSizeCapBlockedMessage(
              totalBytes: sizeEstimate.totalBytes,
              maxAccountBytes: maxAccountBytes,
            );
            emitFlowEvent(
              layer: 'FL',
              event: 'ACCOUNT_MIGRATION_SIZE_CAP_BLOCKED',
              details: {
                'sessionId': payload.sessionId,
                'totalBytes': sizeEstimate.totalBytes,
                'maxAccountBytes': maxAccountBytes,
                'surface': 'confirmation',
              },
            );
          }
        } catch (error) {
          if (!mounted) return;
          emitFlowEvent(
            layer: 'FL',
            event: 'ACCOUNT_MIGRATION_SIZE_ESTIMATE_FAILED',
            details: {
              'sessionId': payload.sessionId,
              'errorType': accountMigrationTransferErrorType(error),
              'surface': 'confirmation',
            },
          );
        }
      }

      final code = deriveMigrationPairingConfirmationCode(payload);
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_OLD_PHONE_CONFIRMATION_READY',
        details: {'sessionId': payload.sessionId},
      );
      setState(() {
        _authorizedTranscript = transcript;
        _moveSizeEstimate = sizeEstimate;
        _oldPhoneState =
            AccountMigrationOldPhonePresentationState.confirmationReady(
              confirmationCode: code,
              sizeEstimate: sizeEstimate,
              sizeCapBlockedMessage: sizeCapBlockedMessage,
            );
      });
    } catch (_) {
      if (!mounted) return;
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_OLD_PHONE_AUTHORIZATION_ERROR',
        details: {},
      );
      setState(() {
        _oldPhoneState = const AccountMigrationOldPhonePresentationState.failed(
          'The migration QR could not be authorized on this phone.',
        );
      });
    }
  }

  Future<
    (
      MigrationExportAuthorizationResult,
      AuthenticatedMigrationChannelTranscript?,
    )
  >
  _defaultAuthorizeExport(MigrationQrPayload payload) async {
    final identity = await widget.identityRepository?.loadIdentity();
    if (identity == null) {
      throw StateError('No active identity is available for migration export.');
    }

    final (result, authorization) = await authorizeMigrationExport(
      repository: SecureKeyStoreMigrationPairingSessionRepository(
        secureKeyStore: widget.secureKeyStore,
      ),
      payload: payload,
      authorizedAt: DateTime.now().toUtc(),
    );

    if (result != MigrationExportAuthorizationResult.authorized ||
        authorization == null) {
      return (result, null);
    }

    final transcript = AuthenticatedMigrationChannelTranscript(
      sessionId: authorization.sessionId,
      newPhoneEphemeralPublicKey: authorization.newPhoneEphemeralPublicKey,
      oldPhonePeerId: identity.peerId,
      authenticatedChannelBinding:
          'mig011-host-ui:${authorization.sessionId}:'
          '${authorization.authorizedAt.toIso8601String()}',
      authorizationNonce: payload.channelNonce ?? 'mig011-host-ui',
    );
    return (MigrationExportAuthorizationResult.authorized, transcript);
  }

  Future<String?> _scanMigrationQr(BuildContext context) {
    final completer = Completer<String?>();
    final l10n = AppLocalizations.of(context)!;
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute(
            builder: (_) => QRScannerScreen(
              copy: QRScannerScreenCopy(
                title: l10n.account_migration_scan_title,
                instruction: l10n.account_migration_scan_instruction,
                subtitle: l10n.account_migration_scan_subtitle,
                pasteTitle: l10n.account_migration_paste_title,
                pasteHint: l10n.account_migration_paste_hint,
                pasteButton: l10n.account_migration_paste_button,
                pastePayloadHintText: l10n.account_migration_paste_payload_hint,
              ),
              onScanned: (qrData) {
                if (!completer.isCompleted) {
                  completer.complete(qrData);
                }
              },
            ),
          ),
        )
        .whenComplete(() {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        });
    return completer.future;
  }

  String _parseErrorText(MigrationQrParseResult result) {
    switch (result) {
      case MigrationQrParseResult.wrongKind:
      case MigrationQrParseResult.invalidJson:
      case MigrationQrParseResult.missingFields:
      case MigrationQrParseResult.unsupportedVersion:
      case MigrationQrParseResult.malformedTimestamp:
      case MigrationQrParseResult.futureTimestamp:
        return 'This is not a valid Move Account QR code.';
      case MigrationQrParseResult.expired:
        return 'This Move Account QR has expired. Show a new code on the new phone.';
      case MigrationQrParseResult.success:
        return 'This QR code could not be used.';
    }
  }

  String _authorizationErrorText(MigrationExportAuthorizationResult result) {
    switch (result) {
      case MigrationExportAuthorizationResult.authorized:
        return 'This QR code could not be used.';
      case MigrationExportAuthorizationResult.alreadyConsumed:
        return 'This Move Account QR was already used.';
      case MigrationExportAuthorizationResult.expired:
        return 'This Move Account QR has expired. Show a new code on the new phone.';
    }
  }

  void _startTransfer() {
    if (_transferRunning) {
      return;
    }
    if (_oldPhoneState.sizeCapBlockedMessage != null) {
      return;
    }
    unawaited(_runTransfer());
  }

  Future<void> _runTransfer() async {
    final transcript = _authorizedTranscript;
    if (transcript == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_TRANSFER_FAILED',
        details: {'reason': 'missing_authorized_session'},
      );
      if (!mounted) return;
      setState(() {
        _progressStage = AccountMigrationProgressStage.failed;
        _progressErrorText =
            'Scan and authorize the migration QR before starting transfer.';
      });
      return;
    }

    final runId = _transferRunId + 1;
    _transferRunId = runId;
    _transferCancellationRequested = false;
    _transferRunning = true;
    _resetSegmentProgress();
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_TRANSFER_START',
      details: {'sessionId': transcript.sessionId},
    );
    setState(() {
      _progressStage = AccountMigrationProgressStage.preparing;
      _progressErrorText = null;
    });

    final runner =
        widget.runTransfer ?? accountMigrationTransferRunnerUnavailable;
    // Fire-and-forget: the hold is counted synchronously inside acquire, and
    // an extra await here would delay the runner by an event-loop turn.
    unawaited(_transferKeepAlive.acquire(reason: 'old_phone_transfer'));
    try {
      final result = await runner(
        request: AccountMigrationTransferRequest(transcript: transcript),
        onProgress: (step) => _handleTransferProgress(runId, step),
        isCancelled: () =>
            _transferCancellationRequested || runId != _transferRunId,
        onSegmentProgress: (progress) =>
            _handleSegmentProgress(runId, progress),
      );
      if (!_isCurrentTransferRun(runId)) {
        return;
      }
      _transferRunning = false;
      if (!mounted) return;

      if (_transferCancellationRequested ||
          result.failureCode == AccountMigrationTransferFailureCode.cancelled) {
        _setTransferCancelled(runId);
        return;
      }

      if (result.isSuccess) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_TRANSFER_SUCCEEDED',
          details: {'sessionId': transcript.sessionId},
        );
        setState(() {
          _progressStage = AccountMigrationProgressStage.completed;
          _progressErrorText = null;
        });
        return;
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_TRANSFER_FAILED',
        details: {
          'reason': result.failureCode?.name ?? 'unknown',
          'failureCode': result.failureCode?.name ?? 'unknown',
          'sessionId': transcript.sessionId,
          'stage': _progressStage?.name ?? 'none',
        },
      );
      setState(() {
        _progressStage = AccountMigrationProgressStage.failed;
        _progressErrorText = result.safeMessage;
      });
    } catch (error) {
      if (!_isCurrentTransferRun(runId)) {
        return;
      }
      _transferRunning = false;
      if (!mounted) return;
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_TRANSFER_ERROR',
        details: {
          'errorType': accountMigrationTransferErrorType(error),
          'reason': accountMigrationBundleSourceFailureReason(error),
        },
      );
      setState(() {
        _progressStage = AccountMigrationProgressStage.failed;
        _progressErrorText =
            'The account move stopped unexpectedly before final handoff.';
      });
    } finally {
      unawaited(_transferKeepAlive.release(reason: 'old_phone_transfer'));
    }
  }

  void _cancelTransfer() {
    if (_transferRunning) {
      _transferCancellationRequested = true;
    }
    _setTransferCancelled(_transferRunId);
  }

  void _retryTransfer() {
    if (_receiverFinalizationLocked) {
      return;
    }
    _transferRunId += 1;
    _transferRunning = false;
    _transferCancellationRequested = false;
    _resetSegmentProgress();
    _stopActiveReceiver();
    setState(() {
      _progressStage = null;
      _progressErrorText = null;
      _authorizedTranscript = null;
      if (widget.role == AccountMigrationRole.oldPhone) {
        _oldPhoneState =
            const AccountMigrationOldPhonePresentationState.waitingForScan();
      }
    });
    if (widget.role == AccountMigrationRole.newPhone) {
      unawaited(_loadNewPhoneQr());
    }
  }

  void _handleClose() {
    if (_receiverFinalizationLocked) {
      return;
    }
    // Leaving the journey must cancel an in-flight old-phone transfer run so
    // its export network pause is restored at the next checkpoint instead of
    // gating the whole account until the run times out on its own.
    if (_transferRunning) {
      _transferCancellationRequested = true;
    }
    _stopActiveReceiver();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  void dispose() {
    if (_transferRunning) {
      _transferCancellationRequested = true;
    }
    unawaited(_receiverEventsSub?.cancel());
    if (_receiverFinalizationLocked) {
      _releaseReceiverKeepAlive();
    } else {
      _stopActiveReceiver();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_receiverFinalizationLocked,
      child: AccountMigrationJourneyScreen(
        role: widget.role,
        qrState: _qrState,
        oldPhoneState: _oldPhoneState,
        progressStage: _progressStage,
        progressErrorText: _progressErrorText,
        transferProgressFraction:
            _progressStage == AccountMigrationProgressStage.transferringDatabase
            ? _transferProgressFraction
            : null,
        transferProgressDetail:
            _progressStage == AccountMigrationProgressStage.transferringDatabase
            ? _transferProgressDetail
            : null,
        onClose: _receiverFinalizationLocked ? null : _handleClose,
        onRetryQr: _receiverFinalizationLocked ? null : _loadNewPhoneQr,
        onScanQr: _handleScanQr,
        onStartTransfer: _startTransfer,
        onCancelTransfer: _cancelTransfer,
        onRetryTransfer: _receiverFinalizationLocked ? null : _retryTransfer,
        backgroundPreference: widget.backgroundPreference,
      ),
    );
  }

  bool _isCurrentTransferRun(int runId) {
    return mounted && runId == _transferRunId;
  }

  void _handleSegmentProgress(
    int runId,
    AccountMigrationTransferSegmentProgress progress,
  ) {
    if (!_isCurrentTransferRun(runId) || _transferCancellationRequested) {
      return;
    }
    _recordSegmentProgress(
      done: progress.sentSegments,
      total: progress.totalSegments,
    );
  }

  void _recordSegmentProgress({required int done, required int total}) {
    if (!mounted || total <= 0) {
      return;
    }
    _segmentProgressStartedAt ??= DateTime.now();
    final previousDone = _segmentsDone;
    if (previousDone != null && done < previousDone) {
      // Late/duplicate events must not walk the bar backwards.
      return;
    }
    setState(() {
      _segmentsDone = done;
      _segmentsTotal = total;
    });
  }

  void _resetSegmentProgress() {
    _segmentsDone = null;
    _segmentsTotal = null;
    _segmentProgressStartedAt = null;
  }

  /// Fraction for the transferring-stage progress bar, or null for the
  /// indeterminate spinner while no segment counts are known.
  double? get _transferProgressFraction {
    final done = _segmentsDone;
    final total = _segmentsTotal;
    if (done == null || total == null || total <= 0) {
      return null;
    }
    final fraction = done / total;
    return fraction < 0 ? 0 : (fraction > 1 ? 1 : fraction);
  }

  /// "12 of 34 · ~454 MB · about 15s left" — the ETA appears once enough
  /// segments have completed for a linear projection to mean anything; the
  /// account size carries over from the confirm-stage estimate when known.
  String? get _transferProgressDetail {
    final done = _segmentsDone;
    final total = _segmentsTotal;
    if (done == null || total == null || total <= 0) {
      return null;
    }
    final estimate = _moveSizeEstimate;
    final base = estimate == null
        ? '$done of $total'
        : '$done of $total · '
              '~${accountMigrationDisplayMegabytes(estimate.totalBytes)} MB';
    final startedAt = _segmentProgressStartedAt;
    if (startedAt == null || done < 2 || done >= total) {
      return base;
    }
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < const Duration(seconds: 2)) {
      return base;
    }
    final remainingSeconds =
        (elapsed.inMilliseconds / done) * (total - done) / 1000;
    if (remainingSeconds < 5) {
      return '$base · almost done';
    }
    if (remainingSeconds < 90) {
      // Round up to 5s steps so the estimate does not flicker.
      final rounded = ((remainingSeconds / 5).ceil()) * 5;
      return '$base · about ${rounded}s left';
    }
    final minutes = (remainingSeconds / 60).ceil();
    return '$base · about ${minutes}m left';
  }

  void _stopActiveReceiver() {
    _releaseReceiverKeepAlive();
    final sessionId = _activeReceiverSessionId;
    final stopReceiver = widget.stopReceiver;
    if (sessionId == null || stopReceiver == null) {
      return;
    }
    _activeReceiverSessionId = null;
    unawaited(stopReceiver(sessionId));
  }

  void _releaseReceiverKeepAlive() {
    if (_receiverKeepAliveHeld) {
      _receiverKeepAliveHeld = false;
      unawaited(_transferKeepAlive.release(reason: 'new_phone_receiver'));
    }
  }

  void _handleTransferProgress(int runId, AccountMigrationTransferStep step) {
    if (!_isCurrentTransferRun(runId) || _transferCancellationRequested) {
      return;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_TRANSFER_STAGE',
      details: {'stage': step.name},
    );
    setState(() {
      _progressStage = _progressStageForTransferStep(step);
      _progressErrorText = null;
    });
  }

  void _setTransferCancelled(int runId) {
    if (!mounted) return;
    _transferRunId += 1;
    _transferRunning = false;
    _transferCancellationRequested = true;
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_TRANSFER_CANCELLED',
      details: {'runId': runId},
    );
    setState(() {
      _progressStage = AccountMigrationProgressStage.cancelled;
      _progressErrorText = null;
    });
  }

  void _handleReceiverEvent(AccountMigrationReceiverEvent event) {
    if (!mounted || widget.role != AccountMigrationRole.newPhone) {
      return;
    }
    final activeSessionId = _activeReceiverSessionId;
    if (activeSessionId == null || event.sessionId != activeSessionId) {
      return;
    }

    switch (event.type) {
      case AccountMigrationReceiverEventType.receivingSegment:
        {
          // Monotonic guard: never regress from a later or terminal stage on
          // a late segment event.
          final currentStage = _progressStage;
          if (currentStage != null &&
              (currentStage.isTerminal ||
                  currentStage == AccountMigrationProgressStage.checking ||
                  currentStage == AccountMigrationProgressStage.finishing)) {
            return;
          }
          final verifiedCount = event.verifiedCount;
          final segmentCount = event.segmentCount;
          if (verifiedCount != null && segmentCount != null) {
            _recordSegmentProgress(done: verifiedCount, total: segmentCount);
          }
          setState(() {
            _progressStage = AccountMigrationProgressStage.transferringDatabase;
            _progressErrorText = null;
          });
          return;
        }
      case AccountMigrationReceiverEventType.importingBundle:
        {
          final currentStage = _progressStage;
          if (currentStage != null && currentStage.isTerminal) {
            return;
          }
          setState(() {
            _receiverFinalizationLocked = true;
            _progressStage = AccountMigrationProgressStage.checking;
            _progressErrorText = null;
          });
          return;
        }
      case AccountMigrationReceiverEventType.importVerified:
        setState(() {
          _receiverFinalizationLocked = true;
          _progressStage = AccountMigrationProgressStage.checking;
          _progressErrorText = null;
        });
        return;
      case AccountMigrationReceiverEventType.activated:
        if (widget.receiverActivationOwnedByParent) {
          _activeReceiverSessionId = null;
          _releaseReceiverKeepAlive();
        } else {
          _stopActiveReceiver();
        }
        setState(() {
          _receiverFinalizationLocked = widget.receiverActivationOwnedByParent;
          _progressStage = AccountMigrationProgressStage.completed;
          _progressErrorText = null;
        });
        if (!widget.receiverActivationOwnedByParent) {
          final callback = widget.onReceiverActivated;
          if (callback != null) {
            unawaited(callback());
          }
        }
        return;
      case AccountMigrationReceiverEventType.failed:
        setState(() {
          _progressStage = AccountMigrationProgressStage.failed;
          _progressErrorText =
              event.safeMessage ?? 'The final account handoff failed.';
        });
        return;
    }
  }

  AccountMigrationProgressStage _progressStageForTransferStep(
    AccountMigrationTransferStep step,
  ) {
    switch (step) {
      case AccountMigrationTransferStep.preparing:
        return AccountMigrationProgressStage.preparing;
      case AccountMigrationTransferStep.connecting:
        return AccountMigrationProgressStage.connecting;
      case AccountMigrationTransferStep.encrypting:
        return AccountMigrationProgressStage.encrypting;
      case AccountMigrationTransferStep.transferringDatabase:
        return AccountMigrationProgressStage.transferringDatabase;
      case AccountMigrationTransferStep.transferringMedia:
        return AccountMigrationProgressStage.transferringMedia;
      case AccountMigrationTransferStep.checking:
        return AccountMigrationProgressStage.checking;
      case AccountMigrationTransferStep.finishing:
        return AccountMigrationProgressStage.finishing;
    }
  }
}
