import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_coordinator.dart';
import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_segmented_transfer_service.dart';
import 'package:flutter_app/features/account_migration/application/migration_storage_preflight.dart';
import 'package:flutter_app/features/account_migration/application/migration_transfer_checkpoint_store.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_cutover_record.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_pairing_session_repository.dart';

String accountMigrationLocalPeerIdForSession(String sessionId) {
  final sessionHash = migrationTransferStringSha256Hex(sessionId);
  return 'account-migration-${sessionHash.substring(0, 32)}';
}

const accountMigrationLocalTransferCommandTranscript = 'transcript';
const accountMigrationLocalTransferCommandManifest = 'manifest';
const accountMigrationLocalTransferCommandSegment = 'segment';
const accountMigrationLocalTransferCommandChunk = 'chunk';
const accountMigrationLocalTransferCommandStatus = 'status';
const accountMigrationLocalTransferCommandComplete = 'complete';
const accountMigrationLocalTransferCommandOldBlockProof = 'old-block-proof';
const accountMigrationLocalTransferFieldBundleId = 'bundle_id';
const accountMigrationLocalTransferFieldCutoverReady = 'cutover_ready';
const accountMigrationLocalTransferFieldOldBlockProof = 'old_block_proof';
const accountMigrationLocalTransferFieldNewActiveProof = 'new_active_proof';
const accountMigrationLocalTransferFieldLedger = 'ledger';

class AccountMigrationLocalTransferBundle {
  final MigrationTransferManifest manifest;
  final Map<int, Uint8List> plaintextSegments;
  final List<MigrationEncryptedSegment>? encryptedSegments;
  final List<AccountMigrationStreamingEntry> streamingEntries;

  /// Best-effort deletion of sender-side export artifacts (DB snapshot,
  /// metadata blob) once the move fully succeeds. Never invoked on failure or
  /// cancel — a retried attempt rebuilds the bundle and overwrites them.
  final Future<void> Function()? cleanupAfterSuccess;

  const AccountMigrationLocalTransferBundle({
    required this.manifest,
    this.plaintextSegments = const {},
    this.encryptedSegments,
    this.streamingEntries = const [],
    this.cleanupAfterSuccess,
  });
}

abstract class AccountMigrationStreamingEntry {
  String get entryId;
  MigrationTransferEntryKind get kind;
  String? get relativePath;
  int get sizeBytes;
  Stream<Uint8List> openChunks({int offset = 0});
}

typedef AccountMigrationLocalTransferBundleSource =
    Future<AccountMigrationLocalTransferBundle> Function(
      AccountMigrationTransferRequest request,
    );
typedef AccountMigrationHttpClientFactory = HttpClient Function();

abstract class AccountMigrationLocalBundleReceiver {
  Future<bool> acceptTranscript({
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  });

  Future<bool> acceptManifest({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  });

  Future<bool> acceptSegment({
    required MigrationTransferManifest manifest,
    required MigrationEncryptedSegment segment,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  });

  Future<bool> complete({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  });
}

abstract class AccountMigrationLocalBundleCutoverReceiver
    implements AccountMigrationLocalBundleReceiver {
  Future<MigrationCutoverRecord?> acceptOldBlockProof({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
    required MigrationCutoverRecord oldBlockProof,
  });
}

enum AccountMigrationChunkAcceptCode {
  /// Chunk decrypted, written at its offset, and the entry hash advanced.
  accepted,

  /// Retransmission of bytes already verified — idempotent, no double write.
  duplicate,

  /// Chunk offset is ahead of the entry's verified offset.
  outOfOrder,

  /// Entry id is not part of the accepted manifest.
  unknownEntry,

  /// Chunk metadata contradicts the manifest entry (index/size/final flag).
  entryMismatch,

  /// AEAD authentication or hash verification failed.
  decryptFailed,

  /// No accepted manifest/session for this chunk.
  sessionUnavailable,
}

class AccountMigrationChunkAcceptOutcome {
  final AccountMigrationChunkAcceptCode code;
  final int verifiedChunkCount;
  final int totalChunkCount;

  const AccountMigrationChunkAcceptOutcome({
    required this.code,
    this.verifiedChunkCount = 0,
    this.totalChunkCount = 0,
  });

  bool get isAccepted =>
      code == AccountMigrationChunkAcceptCode.accepted ||
      code == AccountMigrationChunkAcceptCode.duplicate;
}

/// Protocol v2 entry-streamed receiver surface. Kept as a separate interface
/// (mirroring [AccountMigrationLocalBundleCutoverReceiver]) so v1-only fakes
/// implementing [AccountMigrationLocalBundleReceiver] keep compiling, and a
/// build without it rejects chunk/status typed instead of crashing.
abstract class AccountMigrationLocalStreamBundleReceiver
    implements AccountMigrationLocalBundleReceiver {
  Future<AccountMigrationChunkAcceptOutcome> acceptChunk({
    required MigrationTransferManifest manifest,
    required MigrationEncryptedChunk chunk,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  });

  Future<MigrationTransferLedgerStatus?> transferStatus({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  });
}

class AccountMigrationLocalTransferRuntime {
  final LocalDiscoveryService discovery;
  final LocalWsServer wsServer;
  final MigrationPairingSessionRepository pairingSessionRepository;
  final AccountMigrationLocalTransferBundleSource? bundleSource;
  final AccountMigrationLocalBundleReceiver? bundleReceiver;
  final AccountMigrationSizeGate? sizeGate;
  final MigrationStoragePreflight? storagePreflight;
  final MigrationCutoverCoordinator? oldPhoneCutoverCoordinator;
  final MigrationCutoverLeaseCleanup? oldPhoneLeaseCleanup;
  final MigrationSegmentedTransferService? transferService;

  /// Session chunked-AEAD crypto for protocol v2 entry-streamed transfers;
  /// one ML-KEM encapsulation per transfer attempt.
  final MigrationStreamCrypto? streamCrypto;

  final AccountMigrationHttpClientFactory httpClientFactory;
  final Duration peerResolveTimeout;
  final Duration httpTimeout;

  /// Floor throughput used to scale per-command request budgets with payload
  /// size, so one flat [httpTimeout] is not applied to arbitrarily large
  /// segment or import bodies.
  final int transferBytesPerSecondFloor;

  /// Hard upper bound for any single migration command budget, scaled or not.
  final Duration maxCommandTimeout;

  final DateTime Function() now;

  final _receiverSessions = <String, _ReceiverSession>{};

  /// Number of in-flight old-phone export runs that engaged the network
  /// pause. A retried transfer can briefly overlap the abandoned run it
  /// replaces; the pause is only restored when the LAST run exits, so an
  /// abandoned run's cleanup cannot un-pause a live export.
  int _activeExportPauses = 0;

  /// Serializes pause/restore authority writes so an abandoned run's
  /// conditional restore can never interleave with a retried run's pause
  /// (the restore is a non-atomic load-check-save).
  Future<void> _exportAuthorityOps = Future<void>.value();

  /// Whether any old-phone export run currently holds the network pause.
  /// Used by resume-time recovery to avoid restoring under a live export.
  bool get hasActiveExportRun => _activeExportPauses > 0;

  Future<T> _serializeExportAuthorityOp<T>(Future<T> Function() op) {
    final run = _exportAuthorityOps.then((_) => op());
    _exportAuthorityOps = run.then((_) {}, onError: (_) {});
    return run;
  }

  final _receiverEventsController =
      StreamController<AccountMigrationReceiverEvent>.broadcast();

  AccountMigrationReceiverEvents get receiverEvents =>
      _receiverEventsController.stream;

  AccountMigrationLocalTransferRuntime({
    required this.discovery,
    required this.wsServer,
    required this.pairingSessionRepository,
    this.bundleSource,
    this.bundleReceiver,
    this.sizeGate,
    this.storagePreflight,
    this.oldPhoneCutoverCoordinator,
    this.oldPhoneLeaseCleanup,
    this.transferService,
    this.streamCrypto,
    AccountMigrationHttpClientFactory? httpClientFactory,
    this.peerResolveTimeout = const Duration(seconds: 12),
    this.httpTimeout = const Duration(seconds: 10),
    this.transferBytesPerSecondFloor = 64 * 1024,
    this.maxCommandTimeout = const Duration(seconds: 120),
    DateTime Function()? now,
  }) : httpClientFactory = httpClientFactory ?? HttpClient.new,
       now = now ?? DateTime.now;

  Future<AccountMigrationReceiverStartResult> startNewPhoneReceiver(
    MigrationQrBuildOutput output,
  ) async {
    final payload = output.payload;
    final currentTime = now().toUtc();
    if (!payload.expiresAt.isAfter(currentTime)) {
      return const AccountMigrationReceiverStartResult.failure(
        code: AccountMigrationReceiverStartFailureCode.sessionExpired,
        safeMessage:
            'This Move Account QR expired. Create a new code on this phone.',
      );
    }

    final pending = await pairingSessionRepository.loadPendingNewPhoneSession(
      payload.sessionId,
    );
    if (pending == null ||
        pending.newPhoneEphemeralPublicKey !=
            payload.newPhoneEphemeralPublicKey) {
      return const AccountMigrationReceiverStartResult.failure(
        code: AccountMigrationReceiverStartFailureCode.sessionUnavailable,
        safeMessage:
            'The migration pairing session is not available. Create a new code.',
      );
    }

    try {
      final port = await wsServer.start();
      final migrationPeerId = accountMigrationLocalPeerIdForSession(
        payload.sessionId,
      );
      _receiverSessions[payload.sessionId] = _ReceiverSession(
        pendingSession: pending,
      );
      await discovery.startAdvertising(migrationPeerId, port);
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_LOCAL_RECEIVER_STARTED',
        details: {
          'sessionId': payload.sessionId,
          'migrationPeerId': migrationPeerId,
          'port': port,
        },
      );
      return const AccountMigrationReceiverStartResult.started();
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_LOCAL_RECEIVER_START_FAILED',
        details: {'sessionId': payload.sessionId, 'error': error.toString()},
      );
      return const AccountMigrationReceiverStartResult.failure(
        code: AccountMigrationReceiverStartFailureCode.localNetworkUnavailable,
        safeMessage:
            'This phone could not start local transfer. Check local network permission and try again.',
      );
    }
  }

  Future<void> stopNewPhoneReceiver(String sessionId) async {
    final removed = _receiverSessions.remove(sessionId);
    if (removed == null) return;
    await discovery.stopAdvertising();
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_LOCAL_RECEIVER_STOPPED',
      details: {'sessionId': sessionId},
    );
  }

  Future<void> handleMigrationTransferRequest(
    HttpRequest request,
    String path,
  ) async {
    _MigrationRequestContext? context;
    try {
      final parsedPath = _MigrationPath.parse(request.uri);
      if (parsedPath == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_RECEIVER_REQUEST_REJECTED',
          details: {
            'reason': 'unknown_migration_route',
            'statusCode': HttpStatus.notFound,
          },
        );
        await _writeJson(request, HttpStatus.notFound, {
          'ok': false,
          'reason': 'unknown_migration_route',
        });
        return;
      }

      context = _MigrationRequestContext(
        sessionId: parsedPath.sessionId,
        command: parsedPath.command,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_RECEIVER_REQUEST_START',
        details: {
          'sessionId': parsedPath.sessionId,
          'command': parsedPath.command,
          'method': request.method,
        },
      );

      if (request.method != 'POST') {
        await _rejectRequest(
          request,
          context,
          HttpStatus.methodNotAllowed,
          'method_not_allowed',
        );
        return;
      }

      final session = _receiverSessions[parsedPath.sessionId];
      if (session == null) {
        await _rejectRequest(
          request,
          context,
          HttpStatus.notFound,
          'unknown_session',
        );
        return;
      }

      switch (parsedPath.command) {
        case accountMigrationLocalTransferCommandTranscript:
          await _handleTranscript(request, session, context);
          break;
        case accountMigrationLocalTransferCommandManifest:
          await _handleManifest(request, session, context);
          break;
        case accountMigrationLocalTransferCommandSegment:
          await _handleSegment(request, session, context);
          break;
        case accountMigrationLocalTransferCommandChunk:
          await _handleChunk(request, session, context);
          break;
        case accountMigrationLocalTransferCommandStatus:
          await _handleStatus(request, session, context);
          break;
        case accountMigrationLocalTransferCommandComplete:
          await _handleComplete(request, session, context);
          break;
        case accountMigrationLocalTransferCommandOldBlockProof:
          await _handleOldBlockProof(request, session, context);
          break;
        default:
          await _rejectRequest(
            request,
            context,
            HttpStatus.notFound,
            'unknown_migration_command',
          );
          return;
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_RECEIVER_REQUEST_DONE',
        details: {
          'sessionId': context.sessionId,
          'command': context.command,
          'statusCode': context.statusCode,
          'elapsedMs': context.stopwatch.elapsedMilliseconds,
          'writeMs': context.writeMs,
        },
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_LOCAL_RECEIVER_REQUEST_FAILED',
        details: {
          'error': error.toString(),
          'errorType': error.runtimeType.toString(),
          'sessionId': context?.sessionId,
          'command': context?.command,
          'elapsedMs': context?.stopwatch.elapsedMilliseconds,
        },
      );
      try {
        await _writeJson(request, HttpStatus.badRequest, {
          'ok': false,
          'reason': 'malformed_request',
        });
      } catch (_) {
        // The sender may already have timed out and closed the connection;
        // the failure event above is the diagnostic record.
      }
    }
  }

  Future<void> _rejectRequest(
    HttpRequest request,
    _MigrationRequestContext context,
    int statusCode,
    String reason,
  ) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_RECEIVER_REQUEST_REJECTED',
      details: {
        'sessionId': context.sessionId,
        'command': context.command,
        'reason': reason,
        'statusCode': statusCode,
      },
    );
    await _writeTracked(request, statusCode, {
      'ok': false,
      'reason': reason,
    }, context);
  }

  Future<AccountMigrationTransferResult> runOldPhoneTransfer({
    required AccountMigrationTransferRequest request,
    required AccountMigrationTransferProgressCallback onProgress,
    required bool Function() isCancelled,
    AccountMigrationTransferSegmentProgressCallback? onSegmentProgress,
  }) async {
    if (isCancelled()) {
      return const AccountMigrationTransferResult.cancelled();
    }
    onProgress(AccountMigrationTransferStep.preparing);
    final sizeGateFailure = await _checkRuntimeSizeGate(request);
    if (sizeGateFailure != null) {
      return sizeGateFailure;
    }

    final migrationPeerId = accountMigrationLocalPeerIdForSession(
      request.sessionId,
    );
    onProgress(AccountMigrationTransferStep.connecting);
    final peer = await discovery.resolvePeer(
      migrationPeerId,
      timeout: peerResolveTimeout,
    );
    if (isCancelled()) {
      return const AccountMigrationTransferResult.cancelled();
    }
    if (peer == null) {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.localPeerUnavailable,
        safeMessage:
            'The new phone was not found on the local network. Keep both phones on the same Wi-Fi and keep the QR screen open.',
      );
    }

    final httpClient = httpClientFactory();
    try {
      final transcriptResponse = await _postJson(
        httpClient: httpClient,
        peer: peer,
        sessionId: request.sessionId,
        command: accountMigrationLocalTransferCommandTranscript,
        body: request.transcript.toJson(),
      );
      if (!_isOk(transcriptResponse)) {
        return const AccountMigrationTransferResult.failure(
          code: AccountMigrationTransferFailureCode.receiverRejected,
          safeMessage:
              'The new phone rejected this migration pairing. Show a new QR code and scan again.',
        );
      }

      final source = bundleSource;
      if (source == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_TRANSFER_BUNDLE_SOURCE_MISSING',
          details: {'sessionId': request.sessionId},
        );
        return const AccountMigrationTransferResult.failure(
          code: AccountMigrationTransferFailureCode.bundleExporterUnavailable,
          safeMessage:
              'The phones paired locally, but this build cannot assemble the account bundle yet. Update both phones before moving this account.',
        );
      }

      // C4 no-quiesce fix: pause this old phone's account network side effects
      // BEFORE the bundle source freezes the database snapshot, so the relay
      // inbox is not drained (and ACK-deleted) for messages that arrive
      // mid-transfer — those must stay on the relay for the new phone. The
      // pause is superseded by cutover (markOldNetworkBlocked) on success or,
      // on any failure/cancel/exception, restored in the finally below.
      final exportPauseFailure = await _pauseOldPhoneNetworkForExport(request);
      if (exportPauseFailure != null) {
        return exportPauseFailure;
      }
      try {
        return await _runOldPhoneExportAndHandoff(
          httpClient: httpClient,
          request: request,
          peer: peer,
          source: source,
          onProgress: onProgress,
          isCancelled: isCancelled,
          onSegmentProgress: onSegmentProgress,
        );
      } finally {
        await _restoreOldPhoneNetworkIfExportInterrupted(request);
      }
    } on _MigrationPostException {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.localTransferTimedOut,
        safeMessage: accountMigrationLocalTransferStalledSafeMessage,
      );
    } finally {
      httpClient.close(force: true);
    }
  }

  Future<AccountMigrationTransferResult?> _checkRuntimeSizeGate(
    AccountMigrationTransferRequest request,
  ) async {
    final gate = sizeGate;
    if (gate == null) {
      return null;
    }
    try {
      final estimate = await gate.estimateMoveSize();
      final maxBytes = gate.policy.maxAccountBytes;
      if (estimate.totalBytes <= maxBytes) {
        return null;
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_SIZE_CAP_BLOCKED',
        details: {
          'sessionId': request.sessionId,
          'totalBytes': estimate.totalBytes,
          'maxAccountBytes': maxBytes,
          'surface': 'runtime',
        },
      );
      return AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.accountTooLargeToMove,
        safeMessage: accountMigrationSizeCapBlockedMessage(
          totalBytes: estimate.totalBytes,
          maxAccountBytes: maxBytes,
        ),
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_SIZE_ESTIMATE_FAILED',
        details: {
          'sessionId': request.sessionId,
          'errorType': accountMigrationTransferErrorType(error),
        },
      );
      return null;
    }
  }

  Future<AccountMigrationTransferResult> _runOldPhoneExportAndHandoff({
    required HttpClient httpClient,
    required AccountMigrationTransferRequest request,
    required LocalPeer peer,
    required AccountMigrationLocalTransferBundleSource source,
    required AccountMigrationTransferProgressCallback onProgress,
    required bool Function() isCancelled,
    AccountMigrationTransferSegmentProgressCallback? onSegmentProgress,
  }) async {
    onProgress(AccountMigrationTransferStep.encrypting);
    final AccountMigrationLocalTransferBundle bundle;
    try {
      bundle = await source(request);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_TRANSFER_BUNDLE_SOURCE_FAILED',
        details: {
          'sessionId': request.sessionId,
          'errorType': accountMigrationTransferErrorType(error),
          'reason': accountMigrationBundleSourceFailureReason(error),
        },
      );
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.bundleExporterUnavailable,
        safeMessage: accountMigrationBundleSourceFailedSafeMessage,
      );
    }
    if (isCancelled()) {
      return const AccountMigrationTransferResult.cancelled();
    }

    final _MigrationJsonResponse manifestResponse;
    try {
      manifestResponse = await _postJson(
        httpClient: httpClient,
        peer: peer,
        sessionId: request.sessionId,
        command: accountMigrationLocalTransferCommandManifest,
        body: bundle.manifest.toJson(),
      );
    } on _MigrationPostException {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.localTransferTimedOut,
        safeMessage: accountMigrationLocalTransferStalledSafeMessage,
      );
    }
    if (manifestResponse.statusCode == HttpStatus.notImplemented) {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.bundleImporterUnavailable,
        safeMessage:
            'The new phone can pair locally, but it cannot import the account bundle yet. Update both phones before moving this account.',
      );
    }
    final manifestRejectReason = manifestResponse.body?['reason'];
    if (manifestResponse.statusCode == HttpStatus.insufficientStorage &&
        (manifestRejectReason == 'receiver_storage_insufficient' ||
            manifestRejectReason == 'receiver_storage_unavailable')) {
      if (manifestRejectReason == 'receiver_storage_unavailable') {
        return const AccountMigrationTransferResult.failure(
          code: AccountMigrationTransferFailureCode.receiverStorageInsufficient,
          safeMessage: accountMigrationReceiverStorageUnavailableMessage,
        );
      }
      // The receiver's rejection carries its preflight numbers; surface the
      // exact shortfall so the user knows how much to free up.
      int? rejectionBytes(String key) {
        final value = manifestResponse.body?[key];
        return value is int ? value : null;
      }

      final requiredBytes = rejectionBytes('requiredBytes');
      final totalRequiredBytes = requiredBytes == null
          ? null
          : requiredBytes +
                (rejectionBytes('stagingOverheadBytes') ?? 0) +
                (rejectionBytes('headroomBytes') ?? 0);
      return AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.receiverStorageInsufficient,
        safeMessage: accountMigrationReceiverStorageInsufficientMessage(
          requiredBytes: totalRequiredBytes,
          availableBytes: rejectionBytes('availableBytes'),
        ),
      );
    }
    if (!_isOk(manifestResponse)) {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.transferRejected,
        safeMessage: 'The new phone rejected the account bundle manifest.',
      );
    }

    onProgress(AccountMigrationTransferStep.transferringDatabase);
    final transferResult = bundle.manifest.isEntryStreamed
        ? await _sendStreamingEntryChunks(
            httpClient: httpClient,
            bundle: bundle,
            request: request,
            peer: peer,
            isCancelled: isCancelled,
            onSegmentProgress: onSegmentProgress,
          )
        : bundle.encryptedSegments == null
        ? await _exportPlaintextBundleSegments(
            httpClient: httpClient,
            bundle: bundle,
            request: request,
            peer: peer,
            isCancelled: isCancelled,
            onSegmentProgress: onSegmentProgress,
          )
        : await _sendPreparedBundleSegments(
            httpClient: httpClient,
            bundle: bundle,
            request: request,
            peer: peer,
            isCancelled: isCancelled,
            onSegmentProgress: onSegmentProgress,
          );
    if (isCancelled()) {
      return const AccountMigrationTransferResult.cancelled();
    }
    if (!transferResult.isSuccess) {
      if (transferResult.code == MigrationTransferResultCode.transferTimedOut) {
        return const AccountMigrationTransferResult.failure(
          code: AccountMigrationTransferFailureCode.localTransferTimedOut,
          safeMessage: accountMigrationLocalTransferStalledSafeMessage,
        );
      }
      return AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.transferRejected,
        safeMessage: _transferFailureText(transferResult.code),
      );
    }

    onProgress(AccountMigrationTransferStep.checking);
    final _MigrationJsonResponse completeResponse;
    try {
      completeResponse = await _postJson(
        httpClient: httpClient,
        peer: peer,
        sessionId: request.sessionId,
        command: accountMigrationLocalTransferCommandComplete,
        body: {
          accountMigrationLocalTransferFieldBundleId: bundle.manifest.bundleId,
        },
        // v2 entries are hash-verified per chunk on arrival, so complete()
        // only re-validates the staged DB + metadata — not the whole account.
        budgetScaleBytes: bundle.manifest.isEntryStreamed
            ? bundle.manifest.importValidationBytes
            : bundle.manifest.totalBytes,
      );
    } on _MigrationPostException {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.localTransferTimedOut,
        safeMessage: accountMigrationLocalTransferStalledSafeMessage,
      );
    }
    if (!_isOk(completeResponse)) {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.verificationFailed,
        safeMessage:
            'The new phone could not verify the transferred account bundle.',
      );
    }

    if (oldPhoneCutoverCoordinator != null &&
        completeResponse
                .body?[accountMigrationLocalTransferFieldCutoverReady] !=
            true) {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.cutoverRejected,
        safeMessage:
            'The new phone verified the bundle but cannot complete final account handoff. Update both phones and try again.',
      );
    }

    onProgress(AccountMigrationTransferStep.finishing);
    final cutoverFailure = await _runOldPhoneCutoverIfConfigured(
      httpClient: httpClient,
      request: request,
      peer: peer,
      manifest: bundle.manifest,
    );
    if (cutoverFailure != null) {
      return cutoverFailure;
    }
    await _cleanupBundleAfterSuccess(bundle, request);
    return const AccountMigrationTransferResult.success();
  }

  Future<void> _cleanupBundleAfterSuccess(
    AccountMigrationLocalTransferBundle bundle,
    AccountMigrationTransferRequest request,
  ) async {
    final cleanup = bundle.cleanupAfterSuccess;
    if (cleanup == null) {
      return;
    }
    try {
      await cleanup();
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_EXPORT_ARTIFACTS_CLEANED',
        details: {'sessionId': request.sessionId},
      );
    } catch (error) {
      // Export-artifact cleanup must never mask a successful move.
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_EXPORT_ARTIFACTS_CLEANUP_FAILED',
        details: {
          'sessionId': request.sessionId,
          'errorType': accountMigrationTransferErrorType(error),
        },
      );
    }
  }

  /// Writes `migrationExportingNetworkPaused` so the runtime network gate
  /// suppresses inbox drain/ACK, pubsub, sends, and retriers while the export
  /// snapshot is in flight. Returns a typed failure if the pause cannot be
  /// persisted (the export must not proceed un-paused), or null on success.
  Future<AccountMigrationTransferResult?> _pauseOldPhoneNetworkForExport(
    AccountMigrationTransferRequest request,
  ) {
    return _serializeExportAuthorityOp(() async {
      final coordinator = oldPhoneCutoverCoordinator;
      if (coordinator == null) {
        return null;
      }
      try {
        await coordinator.markExportingNetworkPaused(
          accountPeerId: request.oldPhonePeerId,
        );
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_EXPORT_NETWORK_PAUSE_FAILED',
          details: {
            'sessionId': request.sessionId,
            'errorType': accountMigrationTransferErrorType(error),
          },
        );
        return const AccountMigrationTransferResult.failure(
          code: AccountMigrationTransferFailureCode.unknown,
          safeMessage:
              'The old phone could not pause its account network activity to start the move. Try the move again.',
        );
      }
      _activeExportPauses++;
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_EXPORT_NETWORK_PAUSED',
        details: {
          'sessionId': request.sessionId,
          'activeExportRuns': _activeExportPauses,
        },
      );
      return null;
    });
  }

  /// Restores active authority if the export ended while still paused
  /// (failure, cancellation, or a thrown error). After a successful handoff
  /// the authority is `migrationCutoverPendingBlocked`/`migratedOut`, so this
  /// is a no-op there. Never throws: a restore failure must not mask the
  /// transfer result, so it is recorded as telemetry only.
  Future<void> _restoreOldPhoneNetworkIfExportInterrupted(
    AccountMigrationTransferRequest request,
  ) {
    return _serializeExportAuthorityOp(() async {
      final coordinator = oldPhoneCutoverCoordinator;
      if (coordinator == null) {
        return;
      }
      if (_activeExportPauses > 0) {
        _activeExportPauses--;
      }
      if (_activeExportPauses > 0) {
        // Another (retried) export run is still in flight and relies on the
        // pause; the last run to exit performs the restore.
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_EXPORT_NETWORK_RESTORE_DEFERRED',
          details: {
            'sessionId': request.sessionId,
            'activeExportRuns': _activeExportPauses,
          },
        );
        return;
      }
      try {
        final restored = await coordinator.restoreActiveAfterExportInterrupted(
          accountPeerId: request.oldPhonePeerId,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_EXPORT_NETWORK_RESTORED',
          details: {'sessionId': request.sessionId, 'restored': restored},
        );
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_EXPORT_NETWORK_RESTORE_FAILED',
          details: {
            'sessionId': request.sessionId,
            'errorType': accountMigrationTransferErrorType(error),
          },
        );
      }
    });
  }

  Future<AccountMigrationTransferResult?> _runOldPhoneCutoverIfConfigured({
    required HttpClient httpClient,
    required AccountMigrationTransferRequest request,
    required LocalPeer peer,
    required MigrationTransferManifest manifest,
  }) async {
    final cutoverCoordinator = oldPhoneCutoverCoordinator;
    if (cutoverCoordinator == null) {
      return null;
    }
    final leaseCleanup = oldPhoneLeaseCleanup;
    if (leaseCleanup == null) {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.cutoverRejected,
        safeMessage:
            'The old phone could not finish migration cleanup. Try the move again before using this account.',
      );
    }

    final MigrationCutoverRecord oldBlockProof;
    try {
      oldBlockProof = await cutoverCoordinator.markOldNetworkBlocked(
        sessionId: request.sessionId,
        accountPeerId: request.oldPhonePeerId,
        devicePeerId: request.oldPhonePeerId,
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_LOCAL_TRANSFER_CUTOVER_FAILED',
        details: {
          'sessionId': request.sessionId,
          'stage': 'markOldNetworkBlocked',
          'errorType': accountMigrationTransferErrorType(error),
        },
      );
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.cutoverRejected,
        safeMessage:
            'The old phone could not prepare the final account handoff. Keep both phones open and try again.',
      );
    }
    final _MigrationJsonResponse response;
    try {
      response = await _postJson(
        httpClient: httpClient,
        peer: peer,
        sessionId: request.sessionId,
        command: accountMigrationLocalTransferCommandOldBlockProof,
        body: {
          accountMigrationLocalTransferFieldOldBlockProof: oldBlockProof
              .toJson(),
        },
        // Active DB import still runs behind old-block-proof, so its budget
        // stays scaled by the database (not the whole account) under v2.
        budgetScaleBytes: manifest.isEntryStreamed
            ? manifest.importValidationBytes
            : manifest.totalBytes,
        oldNetworkBlocked: true,
      );
    } on _MigrationPostException {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.localTransferTimedOut,
        safeMessage: accountMigrationFinalHandoffStalledSafeMessage,
      );
    }
    if (!_isOk(response)) {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.cutoverRejected,
        safeMessage:
            'The new phone did not accept the final account handoff. Keep both phones open and try again.',
      );
    }
    final proofJson =
        response.body?[accountMigrationLocalTransferFieldNewActiveProof];
    if (proofJson is! Map) {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.cutoverRejected,
        safeMessage:
            'The new phone did not confirm the moved account became active.',
      );
    }
    final newActiveProof = MigrationCutoverRecord.fromJson(
      Map<String, dynamic>.from(proofJson),
    );
    if (newActiveProof.isFailClosed ||
        !newActiveProof.provesNewActiveCommitted) {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.cutoverRejected,
        safeMessage:
            'The new phone did not return a valid active-account proof.',
      );
    }

    final MigrationCutoverRecord oldMigratedOut;
    try {
      oldMigratedOut = await cutoverCoordinator
          .markOldMigratedOutAfterNewActive(
            sessionId: request.sessionId,
            accountPeerId: request.oldPhonePeerId,
            devicePeerId: request.oldPhonePeerId,
            newActiveProof: newActiveProof,
            leaseCleanup: leaseCleanup,
          );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_LOCAL_TRANSFER_CUTOVER_FAILED',
        details: {
          'sessionId': request.sessionId,
          'stage': 'markOldMigratedOutAfterNewActive',
          'errorType': accountMigrationTransferErrorType(error),
        },
      );
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.cutoverRejected,
        safeMessage:
            'The old phone could not safely block its local account after the new phone became active.',
      );
    }
    if (!oldMigratedOut.oldMigratedOutCommitted) {
      return const AccountMigrationTransferResult.failure(
        code: AccountMigrationTransferFailureCode.cutoverRejected,
        safeMessage:
            'The old phone could not safely block its local account after the new phone became active.',
      );
    }
    return null;
  }

  Future<MigrationTransferResult> _exportPlaintextBundleSegments({
    required HttpClient httpClient,
    required AccountMigrationLocalTransferBundle bundle,
    required AccountMigrationTransferRequest request,
    required LocalPeer peer,
    required bool Function() isCancelled,
    AccountMigrationTransferSegmentProgressCallback? onSegmentProgress,
  }) async {
    final service = transferService;
    if (service == null) {
      return const MigrationTransferResult.cryptoRejected();
    }
    final manifest = bundle.manifest;
    final segmentCount = manifest.orderedSegments.length;
    var sentCount = 0;
    var postTimedOut = false;
    onSegmentProgress?.call(
      AccountMigrationTransferSegmentProgress(
        sentSegments: 0,
        totalSegments: segmentCount,
      ),
    );
    final result = await service.exportSegments(
      manifest: manifest,
      plaintextSegments: bundle.plaintextSegments,
      recipientMlKemPublicKey: request.newPhoneEphemeralPublicKey,
      localPathAvailable: true,
      sendLocalSegment: (segment) async {
        if (isCancelled()) return false;
        final postStopwatch = Stopwatch()..start();
        final _MigrationJsonResponse response;
        try {
          response = await _postJson(
            httpClient: httpClient,
            peer: peer,
            sessionId: request.sessionId,
            command: accountMigrationLocalTransferCommandSegment,
            body: _segmentToJson(segment),
            segmentIndex: segment.index,
            segmentCount: segmentCount,
          );
        } on _MigrationPostException {
          postTimedOut = true;
          return false;
        }
        if (!_isOk(response)) {
          return false;
        }
        sentCount += 1;
        _emitSegmentProgress(
          sessionId: request.sessionId,
          bundleId: manifest.bundleId,
          segmentIndex: segment.index,
          segmentCount: segmentCount,
          sentCount: sentCount,
          payloadBytes: segment.ciphertext.length,
          elapsedMs: postStopwatch.elapsedMilliseconds,
        );
        onSegmentProgress?.call(
          AccountMigrationTransferSegmentProgress(
            sentSegments: sentCount,
            totalSegments: segmentCount,
          ),
        );
        return true;
      },
    );
    if (postTimedOut &&
        result.code == MigrationTransferResultCode.sendRejected) {
      return const MigrationTransferResult.transferTimedOut();
    }
    return result;
  }

  Future<MigrationTransferResult> _sendPreparedBundleSegments({
    required HttpClient httpClient,
    required AccountMigrationLocalTransferBundle bundle,
    required AccountMigrationTransferRequest request,
    required LocalPeer peer,
    required bool Function() isCancelled,
    AccountMigrationTransferSegmentProgressCallback? onSegmentProgress,
  }) async {
    final manifest = bundle.manifest;
    if (!manifest.compatibility().isAccepted) {
      return const MigrationTransferResult.manifestRejected();
    }
    final segmentsByIndex = {
      for (final segment in bundle.encryptedSegments!) segment.index: segment,
    };
    final segmentCount = manifest.orderedSegments.length;
    var sentCount = 0;
    onSegmentProgress?.call(
      AccountMigrationTransferSegmentProgress(
        sentSegments: 0,
        totalSegments: segmentCount,
      ),
    );
    for (final descriptor in manifest.orderedSegments) {
      final segment = segmentsByIndex[descriptor.index];
      if (segment == null) {
        return MigrationTransferResult.missingSegment([descriptor.index]);
      }
      if (segment.nonce != descriptor.nonce ||
          segment.plaintextSha256 != descriptor.plaintextSha256 ||
          segment.ciphertextSha256 != descriptor.ciphertextSha256 ||
          migrationTransferStringSha256Hex(segment.ciphertext) !=
              descriptor.ciphertextSha256) {
        return const MigrationTransferResult.manifestRejected();
      }
      if (isCancelled()) {
        return const MigrationTransferResult.sendRejected();
      }
      final postStopwatch = Stopwatch()..start();
      final _MigrationJsonResponse response;
      try {
        response = await _postJson(
          httpClient: httpClient,
          peer: peer,
          sessionId: request.sessionId,
          command: accountMigrationLocalTransferCommandSegment,
          body: _segmentToJson(segment),
          segmentIndex: descriptor.index,
          segmentCount: segmentCount,
        );
      } on _MigrationPostException {
        return const MigrationTransferResult.transferTimedOut();
      }
      if (!_isOk(response)) {
        return const MigrationTransferResult.sendRejected();
      }
      sentCount += 1;
      _emitSegmentProgress(
        sessionId: request.sessionId,
        bundleId: manifest.bundleId,
        segmentIndex: descriptor.index,
        segmentCount: segmentCount,
        sentCount: sentCount,
        payloadBytes: segment.ciphertext.length,
        elapsedMs: postStopwatch.elapsedMilliseconds,
      );
      onSegmentProgress?.call(
        AccountMigrationTransferSegmentProgress(
          sentSegments: sentCount,
          totalSegments: segmentCount,
        ),
      );
    }
    return const MigrationTransferResult.success();
  }

  /// Protocol v2 sender loop: one session encapsulation per attempt, then
  /// every entry streamed from disk chunk-by-chunk (max one chunk in RAM),
  /// resuming from the receiver's per-entry verified-offset ledger.
  Future<MigrationTransferResult> _sendStreamingEntryChunks({
    required HttpClient httpClient,
    required AccountMigrationLocalTransferBundle bundle,
    required AccountMigrationTransferRequest request,
    required LocalPeer peer,
    required bool Function() isCancelled,
    AccountMigrationTransferSegmentProgressCallback? onSegmentProgress,
  }) async {
    final crypto = streamCrypto;
    if (crypto == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_STREAM_CRYPTO_MISSING',
        details: {'sessionId': request.sessionId},
      );
      return const MigrationTransferResult.cryptoRejected();
    }
    final manifest = bundle.manifest;
    if (!manifest.compatibility().isAccepted) {
      return const MigrationTransferResult.manifestRejected();
    }
    final entriesById = {
      for (final entry in bundle.streamingEntries) entry.entryId: entry,
    };
    final totalChunks = manifest.totalChunkCount;

    // Resume point: the receiver's file-backed ledger survives interruption
    // and process restarts, so only unverified (entry, offset) spans resend.
    final _MigrationJsonResponse statusResponse;
    try {
      statusResponse = await _postJson(
        httpClient: httpClient,
        peer: peer,
        sessionId: request.sessionId,
        command: accountMigrationLocalTransferCommandStatus,
        body: {accountMigrationLocalTransferFieldBundleId: manifest.bundleId},
      );
    } on _MigrationPostException {
      return const MigrationTransferResult.transferTimedOut();
    }
    if (!_isOk(statusResponse)) {
      return const MigrationTransferResult.sendRejected();
    }
    final rawLedger =
        statusResponse.body?[accountMigrationLocalTransferFieldLedger];
    final ledger = rawLedger is Map
        ? MigrationTransferLedgerStatus.fromJson(
            Map<String, dynamic>.from(rawLedger),
          )
        : const MigrationTransferLedgerStatus(
            nextEntryId: null,
            nextOffset: 0,
            verifiedEntryIds: [],
            entryOffsets: {},
          );

    // One ML-KEM encapsulation per transfer attempt; a resumed attempt gets a
    // fresh session key, so counter nonces can never repeat across attempts.
    final MigrationStreamEncryptSession session;
    try {
      session = await crypto.encapsulateSession(
        recipientMlKemPublicKey: request.newPhoneEphemeralPublicKey,
        sessionId: request.sessionId,
        bundleId: manifest.bundleId,
        direction: MigrationStreamDirection.oldToNew,
      );
    } on MigrationStreamCryptoException {
      return const MigrationTransferResult.cryptoRejected();
    }

    final verifiedEntries = ledger.verifiedEntryIds.toSet();
    var sentChunks = 0;
    for (final descriptor in manifest.entries) {
      if (descriptor.sizeBytes > 0 &&
          verifiedEntries.contains(descriptor.entryId)) {
        sentChunks += descriptor.chunkCount;
      }
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_LOCAL_TRANSFER_STREAM_START',
      details: {
        'sessionId': request.sessionId,
        'bundleId': manifest.bundleId,
        'entryCount': manifest.entries.length,
        'chunkCount': totalChunks,
        'resumedChunks': sentChunks,
        'totalBytes': manifest.totalBytes,
      },
    );
    onSegmentProgress?.call(
      AccountMigrationTransferSegmentProgress(
        sentSegments: sentChunks,
        totalSegments: totalChunks,
      ),
    );

    for (var ordinal = 0; ordinal < manifest.entries.length; ordinal += 1) {
      final descriptor = manifest.entries[ordinal];
      if (descriptor.sizeBytes == 0 ||
          verifiedEntries.contains(descriptor.entryId)) {
        continue;
      }
      final entry = entriesById[descriptor.entryId];
      if (entry == null) {
        return MigrationTransferResult.missingSegment([ordinal]);
      }
      var offset = ledger.entryOffsets[descriptor.entryId] ?? 0;
      if (offset % descriptor.chunkSize != 0 ||
          offset >= descriptor.sizeBytes) {
        // The ledger must be chunk-aligned; anything else restarts the entry
        // (the receiver re-verifies via the incremental entry hash anyway).
        offset = 0;
      }
      var chunkIndex = offset ~/ descriptor.chunkSize;
      sentChunks += chunkIndex;
      await for (final plaintext in entry.openChunks(offset: offset)) {
        if (isCancelled()) {
          return const MigrationTransferResult.sendRejected();
        }
        final isFinal = offset + plaintext.length >= descriptor.sizeBytes;
        final associatedData = MigrationChunkAssociatedData(
          sessionId: request.sessionId,
          bundleId: manifest.bundleId,
          entryId: descriptor.entryId,
          chunkIndex: chunkIndex,
          offset: offset,
          isFinal: isFinal,
        );
        final MigrationEncryptedChunk encrypted;
        try {
          encrypted = await crypto.encryptChunk(
            session: session,
            plaintext: plaintext,
            associatedData: associatedData,
            nonce: migrationChunkNonceBase64(
              entryOrdinal: ordinal,
              chunkIndex: chunkIndex,
            ),
          );
        } on MigrationStreamCryptoException {
          return const MigrationTransferResult.cryptoRejected();
        }
        final postStopwatch = Stopwatch()..start();
        final _MigrationJsonResponse response;
        try {
          response = await _postJson(
            httpClient: httpClient,
            peer: peer,
            sessionId: request.sessionId,
            command: accountMigrationLocalTransferCommandChunk,
            body: _chunkToJson(encrypted),
            segmentIndex: sentChunks,
            segmentCount: totalChunks,
          );
        } on _MigrationPostException {
          return const MigrationTransferResult.transferTimedOut();
        }
        if (!_isOk(response)) {
          return const MigrationTransferResult.sendRejected();
        }
        offset += plaintext.length;
        chunkIndex += 1;
        sentChunks += 1;
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_LOCAL_TRANSFER_CHUNK_PROGRESS',
          details: {
            'sessionId': request.sessionId,
            'bundleId': manifest.bundleId,
            'entryId': descriptor.entryId,
            'chunkIndex': chunkIndex - 1,
            'chunkCount': totalChunks,
            'sentCount': sentChunks,
            'payloadBytes': encrypted.ciphertext.length,
            'elapsedMs': postStopwatch.elapsedMilliseconds,
          },
        );
        onSegmentProgress?.call(
          AccountMigrationTransferSegmentProgress(
            sentSegments: sentChunks,
            totalSegments: totalChunks,
          ),
        );
      }
      if (offset != descriptor.sizeBytes) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_LOCAL_TRANSFER_ENTRY_TRUNCATED',
          details: {
            'sessionId': request.sessionId,
            'entryId': descriptor.entryId,
            'expectedBytes': descriptor.sizeBytes,
            'streamedBytes': offset,
          },
        );
        return const MigrationTransferResult.sendRejected();
      }
    }
    return const MigrationTransferResult.success();
  }

  void _emitSegmentProgress({
    required String sessionId,
    required String bundleId,
    required int segmentIndex,
    required int segmentCount,
    required int sentCount,
    required int payloadBytes,
    required int elapsedMs,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_LOCAL_TRANSFER_SEGMENT_PROGRESS',
      details: {
        'sessionId': sessionId,
        'bundleId': bundleId,
        'segmentIndex': segmentIndex,
        'segmentCount': segmentCount,
        'sentCount': sentCount,
        'payloadBytes': payloadBytes,
        'elapsedMs': elapsedMs,
      },
    );
  }

  Future<void> _handleTranscript(
    HttpRequest request,
    _ReceiverSession session,
    _MigrationRequestContext context,
  ) async {
    final (decoded, _, _, _) = await _readJsonTimed(request, context);
    final transcript = AuthenticatedMigrationChannelTranscript.fromJson(
      decoded,
    );
    if (transcript.sessionId != session.pendingSession.sessionId ||
        transcript.newPhoneEphemeralPublicKey !=
            session.pendingSession.newPhoneEphemeralPublicKey) {
      await _rejectRequest(
        request,
        context,
        HttpStatus.forbidden,
        'transcript_mismatch',
      );
      return;
    }

    final receiver = bundleReceiver;
    if (receiver != null) {
      final accepted = await receiver.acceptTranscript(
        transcript: transcript,
        pendingSession: session.pendingSession,
      );
      if (!accepted) {
        await _rejectRequest(
          request,
          context,
          HttpStatus.forbidden,
          'transcript_rejected',
        );
        return;
      }
    }

    session.transcript = transcript;
    await _writeTracked(request, HttpStatus.ok, {'ok': true}, context);
  }

  Future<void> _handleManifest(
    HttpRequest request,
    _ReceiverSession session,
    _MigrationRequestContext context,
  ) async {
    final transcript = session.transcript;
    if (transcript == null) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_MANIFEST_REJECTED',
        statusCode: HttpStatus.conflict,
        reason: 'missing_transcript',
      );
      return;
    }

    final receiver = bundleReceiver;
    if (receiver == null) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_MANIFEST_REJECTED',
        statusCode: HttpStatus.notImplemented,
        reason: 'bundle_importer_unavailable',
      );
      return;
    }

    final (decoded, bodyBytes, bodyReadMs, jsonDecodeMs) = await _readJsonTimed(
      request,
      context,
    );
    final parseStart = context.stopwatch.elapsedMilliseconds;
    final manifest = _manifestFromJson(decoded);
    final decodeMs =
        jsonDecodeMs + context.stopwatch.elapsedMilliseconds - parseStart;
    if (!manifest.compatibility().isAccepted) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_MANIFEST_REJECTED',
        statusCode: HttpStatus.badRequest,
        reason: 'manifest_rejected',
      );
      return;
    }
    final preflight = storagePreflight;
    if (preflight != null) {
      final preflightResult = await preflight.evaluateTransfer(
        manifest: manifest,
      );
      if (!preflightResult.isAccepted) {
        final reason =
            preflightResult.reason ==
                MigrationStoragePreflightReason.storageUnavailable
            ? 'receiver_storage_unavailable'
            : 'receiver_storage_insufficient';
        await _rejectCommand(
          request,
          context,
          event: 'ACCOUNT_MIGRATION_RECEIVER_MANIFEST_REJECTED',
          statusCode: HttpStatus.insufficientStorage,
          reason: reason,
          details: {
            'requiredBytes': preflightResult.requiredBytes,
            'availableBytes': preflightResult.availableBytes,
            'stagingOverheadBytes': preflightResult.stagingOverheadBytes,
            'headroomBytes': preflightResult.headroomBytes,
          },
        );
        return;
      }
    }
    final acceptStart = context.stopwatch.elapsedMilliseconds;
    final accepted = await receiver.acceptManifest(
      manifest: manifest,
      transcript: transcript,
      pendingSession: session.pendingSession,
    );
    final acceptMs = context.stopwatch.elapsedMilliseconds - acceptStart;
    if (!accepted) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_MANIFEST_REJECTED',
        statusCode: HttpStatus.forbidden,
        reason: 'manifest_rejected',
      );
      return;
    }
    session.manifest = manifest;
    final wireUnitCount = manifest.isEntryStreamed
        ? manifest.totalChunkCount
        : manifest.segments.length;
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_RECEIVER_MANIFEST_ACCEPTED',
      details: {
        'sessionId': manifest.sessionId,
        'bundleId': manifest.bundleId,
        'segmentCount': wireUnitCount,
        'totalBytes': manifest.totalBytes,
        'bodyBytes': bodyBytes,
        'bodyReadMs': bodyReadMs,
        'decodeMs': decodeMs,
        'acceptMs': acceptMs,
      },
    );
    _receiverEventsController.add(
      AccountMigrationReceiverEvent.receivingSegment(
        sessionId: manifest.sessionId,
        segmentCount: wireUnitCount,
        verifiedCount: manifest.isEntryStreamed
            ? session.verifiedChunkCount
            : session.acceptedSegmentIndexes.length,
      ),
    );
    await _writeTracked(request, HttpStatus.ok, {'ok': true}, context);
  }

  Future<void> _handleSegment(
    HttpRequest request,
    _ReceiverSession session,
    _MigrationRequestContext context,
  ) async {
    final transcript = session.transcript;
    final manifest = session.manifest;
    if (transcript == null || manifest == null) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_SEGMENT_REJECTED',
        statusCode: HttpStatus.conflict,
        reason: 'missing_manifest',
      );
      return;
    }

    final receiver = bundleReceiver;
    if (receiver == null) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_SEGMENT_REJECTED',
        statusCode: HttpStatus.notImplemented,
        reason: 'bundle_importer_unavailable',
      );
      return;
    }

    final (decoded, bodyBytes, bodyReadMs, jsonDecodeMs) = await _readJsonTimed(
      request,
      context,
    );
    final parseStart = context.stopwatch.elapsedMilliseconds;
    final segment = _segmentFromJson(decoded);
    final decodeMs =
        jsonDecodeMs + context.stopwatch.elapsedMilliseconds - parseStart;
    final acceptStart = context.stopwatch.elapsedMilliseconds;
    final accepted = await receiver.acceptSegment(
      manifest: manifest,
      segment: segment,
      transcript: transcript,
      pendingSession: session.pendingSession,
    );
    final acceptMs = context.stopwatch.elapsedMilliseconds - acceptStart;
    if (!accepted) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_SEGMENT_REJECTED',
        statusCode: HttpStatus.badRequest,
        reason: 'segment_rejected',
        segmentIndex: segment.index,
      );
      return;
    }
    session.acceptedSegmentIndexes.add(segment.index);
    final verifiedCount = session.acceptedSegmentIndexes.length;
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_RECEIVER_SEGMENT_ACCEPTED',
      details: {
        'sessionId': manifest.sessionId,
        'segmentIndex': segment.index,
        'segmentCount': manifest.segments.length,
        'verifiedCount': verifiedCount,
        'bodyBytes': bodyBytes,
        'bodyReadMs': bodyReadMs,
        'decodeMs': decodeMs,
        'acceptMs': acceptMs,
      },
    );
    _receiverEventsController.add(
      AccountMigrationReceiverEvent.receivingSegment(
        sessionId: manifest.sessionId,
        segmentIndex: segment.index,
        segmentCount: manifest.segments.length,
        verifiedCount: verifiedCount,
      ),
    );
    await _writeTracked(request, HttpStatus.ok, {'ok': true}, context);
  }

  Future<void> _handleChunk(
    HttpRequest request,
    _ReceiverSession session,
    _MigrationRequestContext context,
  ) async {
    final transcript = session.transcript;
    final manifest = session.manifest;
    if (transcript == null || manifest == null) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_CHUNK_REJECTED',
        statusCode: HttpStatus.conflict,
        reason: 'missing_manifest',
      );
      return;
    }

    final receiver = bundleReceiver;
    if (receiver is! AccountMigrationLocalStreamBundleReceiver) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_CHUNK_REJECTED',
        statusCode: HttpStatus.notImplemented,
        reason: 'stream_importer_unavailable',
      );
      return;
    }
    if (!manifest.isEntryStreamed) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_CHUNK_REJECTED',
        statusCode: HttpStatus.conflict,
        reason: 'manifest_not_entry_streamed',
      );
      return;
    }

    final (decoded, bodyBytes, bodyReadMs, jsonDecodeMs) = await _readJsonTimed(
      request,
      context,
    );
    final parseStart = context.stopwatch.elapsedMilliseconds;
    final chunk = _chunkFromJson(decoded);
    final decodeMs =
        jsonDecodeMs + context.stopwatch.elapsedMilliseconds - parseStart;
    final acceptStart = context.stopwatch.elapsedMilliseconds;
    final outcome = await receiver.acceptChunk(
      manifest: manifest,
      chunk: chunk,
      transcript: transcript,
      pendingSession: session.pendingSession,
    );
    final acceptMs = context.stopwatch.elapsedMilliseconds - acceptStart;
    if (outcome.isAccepted) {
      session.verifiedChunkCount = outcome.verifiedChunkCount;
    }
    if (!outcome.isAccepted) {
      final statusCode = switch (outcome.code) {
        AccountMigrationChunkAcceptCode.sessionUnavailable ||
        AccountMigrationChunkAcceptCode.outOfOrder => HttpStatus.conflict,
        _ => HttpStatus.badRequest,
      };
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_CHUNK_REJECTED',
        statusCode: statusCode,
        reason: outcome.code == AccountMigrationChunkAcceptCode.outOfOrder
            ? 'chunk_out_of_order'
            : 'chunk_rejected',
        details: {'code': outcome.code.name, 'entryId': chunk.entryId},
      );
      return;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_RECEIVER_CHUNK_ACCEPTED',
      details: {
        'sessionId': manifest.sessionId,
        'entryId': chunk.entryId,
        'chunkIndex': chunk.chunkIndex,
        'duplicate': outcome.code == AccountMigrationChunkAcceptCode.duplicate,
        'verifiedCount': outcome.verifiedChunkCount,
        'chunkCount': outcome.totalChunkCount,
        'bodyBytes': bodyBytes,
        'bodyReadMs': bodyReadMs,
        'decodeMs': decodeMs,
        'acceptMs': acceptMs,
      },
    );
    _receiverEventsController.add(
      AccountMigrationReceiverEvent.receivingSegment(
        sessionId: manifest.sessionId,
        segmentIndex: chunk.chunkIndex,
        segmentCount: outcome.totalChunkCount,
        verifiedCount: outcome.verifiedChunkCount,
      ),
    );
    await _writeTracked(request, HttpStatus.ok, {'ok': true}, context);
  }

  Future<void> _handleStatus(
    HttpRequest request,
    _ReceiverSession session,
    _MigrationRequestContext context,
  ) async {
    final transcript = session.transcript;
    final manifest = session.manifest;
    if (transcript == null || manifest == null) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_STATUS_REJECTED',
        statusCode: HttpStatus.conflict,
        reason: 'missing_manifest',
      );
      return;
    }

    final receiver = bundleReceiver;
    if (receiver is! AccountMigrationLocalStreamBundleReceiver) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_STATUS_REJECTED',
        statusCode: HttpStatus.notImplemented,
        reason: 'stream_importer_unavailable',
      );
      return;
    }

    final (decoded, _, _, _) = await _readJsonTimed(request, context);
    final requestedBundleId =
        decoded[accountMigrationLocalTransferFieldBundleId];
    if (requestedBundleId != manifest.bundleId) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_STATUS_REJECTED',
        statusCode: HttpStatus.conflict,
        reason: 'bundle_mismatch',
      );
      return;
    }
    final ledgerStatus = await receiver.transferStatus(
      manifest: manifest,
      transcript: transcript,
      pendingSession: session.pendingSession,
    );
    if (ledgerStatus == null) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_STATUS_REJECTED',
        statusCode: HttpStatus.conflict,
        reason: 'status_unavailable',
      );
      return;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_RECEIVER_STATUS_SERVED',
      details: {
        'sessionId': manifest.sessionId,
        'verifiedEntryCount': ledgerStatus.verifiedEntryIds.length,
        'entryCount': manifest.entries.length,
      },
    );
    await _writeTracked(request, HttpStatus.ok, {
      'ok': true,
      accountMigrationLocalTransferFieldLedger: ledgerStatus.toJson(),
    }, context);
  }

  Future<void> _handleComplete(
    HttpRequest request,
    _ReceiverSession session,
    _MigrationRequestContext context,
  ) async {
    final transcript = session.transcript;
    final manifest = session.manifest;
    if (transcript == null || manifest == null) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_COMPLETE_REJECTED',
        statusCode: HttpStatus.conflict,
        reason: 'missing_manifest',
      );
      return;
    }

    final receiver = bundleReceiver;
    if (receiver == null) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_COMPLETE_REJECTED',
        statusCode: HttpStatus.notImplemented,
        reason: 'bundle_importer_unavailable',
      );
      return;
    }

    final (_, _, bodyReadMs, decodeMs) = await _readJsonTimed(request, context);
    _receiverEventsController.add(
      AccountMigrationReceiverEvent.importingBundle(
        sessionId: manifest.sessionId,
        segmentCount: manifest.isEntryStreamed
            ? manifest.totalChunkCount
            : manifest.segments.length,
        verifiedCount: manifest.isEntryStreamed
            ? session.verifiedChunkCount
            : session.acceptedSegmentIndexes.length,
      ),
    );
    final acceptStart = context.stopwatch.elapsedMilliseconds;
    final accepted = await receiver.complete(
      manifest: manifest,
      transcript: transcript,
      pendingSession: session.pendingSession,
    );
    final acceptMs = context.stopwatch.elapsedMilliseconds - acceptStart;
    if (!accepted) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_COMPLETE_REJECTED',
        statusCode: HttpStatus.badRequest,
        reason: 'bundle_verification_failed',
      );
      return;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_RECEIVER_COMPLETE_ACCEPTED',
      details: {
        'sessionId': manifest.sessionId,
        'verifiedCount': manifest.isEntryStreamed
            ? session.verifiedChunkCount
            : session.acceptedSegmentIndexes.length,
        'bodyReadMs': bodyReadMs,
        'decodeMs': decodeMs,
        'acceptMs': acceptMs,
      },
    );
    _receiverEventsController.add(
      AccountMigrationReceiverEvent.importVerified(
        sessionId: manifest.sessionId,
      ),
    );
    await _writeTracked(request, HttpStatus.ok, {
      'ok': true,
      accountMigrationLocalTransferFieldCutoverReady:
          receiver is AccountMigrationLocalBundleCutoverReceiver,
    }, context);
  }

  Future<void> _handleOldBlockProof(
    HttpRequest request,
    _ReceiverSession session,
    _MigrationRequestContext context,
  ) async {
    final transcript = session.transcript;
    final manifest = session.manifest;
    if (transcript == null || manifest == null) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_OLD_BLOCK_PROOF_REJECTED',
        statusCode: HttpStatus.conflict,
        reason: 'missing_manifest',
      );
      return;
    }

    final receiver = bundleReceiver;
    if (receiver is! AccountMigrationLocalBundleCutoverReceiver) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_OLD_BLOCK_PROOF_REJECTED',
        statusCode: HttpStatus.notImplemented,
        reason: 'cutover_receiver_unavailable',
      );
      return;
    }

    final (decoded, _, _, _) = await _readJsonTimed(request, context);
    final rawProof = decoded[accountMigrationLocalTransferFieldOldBlockProof];
    if (rawProof is! Map) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_OLD_BLOCK_PROOF_REJECTED',
        statusCode: HttpStatus.badRequest,
        reason: 'missing_old_block_proof',
      );
      return;
    }
    final oldBlockProof = MigrationCutoverRecord.fromJson(
      Map<String, dynamic>.from(rawProof),
    );
    if (oldBlockProof.isFailClosed) {
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_OLD_BLOCK_PROOF_REJECTED',
        statusCode: HttpStatus.badRequest,
        reason: 'invalid_old_block_proof',
      );
      return;
    }

    final acceptStart = context.stopwatch.elapsedMilliseconds;
    final newActiveProof = await receiver.acceptOldBlockProof(
      manifest: manifest,
      transcript: transcript,
      pendingSession: session.pendingSession,
      oldBlockProof: oldBlockProof,
    );
    final acceptMs = context.stopwatch.elapsedMilliseconds - acceptStart;
    if (newActiveProof == null || !newActiveProof.provesNewActiveCommitted) {
      _receiverEventsController.add(
        AccountMigrationReceiverEvent.failed(
          sessionId: manifest.sessionId,
          safeMessage:
              'The final account handoff was rejected. Keep both phones open and try again.',
        ),
      );
      await _rejectCommand(
        request,
        context,
        event: 'ACCOUNT_MIGRATION_RECEIVER_OLD_BLOCK_PROOF_REJECTED',
        statusCode: HttpStatus.badRequest,
        reason: 'cutover_rejected',
      );
      return;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_RECEIVER_OLD_BLOCK_PROOF_ACCEPTED',
      details: {'sessionId': manifest.sessionId, 'acceptMs': acceptMs},
    );
    _receiverEventsController.add(
      AccountMigrationReceiverEvent.activated(sessionId: manifest.sessionId),
    );
    await _writeTracked(request, HttpStatus.ok, {
      'ok': true,
      accountMigrationLocalTransferFieldNewActiveProof: newActiveProof.toJson(),
    }, context);
  }

  Future<void> _rejectCommand(
    HttpRequest request,
    _MigrationRequestContext context, {
    required String event,
    required int statusCode,
    required String reason,
    int? segmentIndex,
    Map<String, Object?>? details,
  }) async {
    emitFlowEvent(
      layer: 'FL',
      event: event,
      details: {
        'sessionId': context.sessionId,
        'segmentIndex': ?segmentIndex,
        'reason': reason,
        'statusCode': statusCode,
        ...?details,
      },
    );
    await _writeTracked(request, statusCode, {
      'ok': false,
      'reason': reason,
      ...?details,
    }, context);
  }

  String _commandStageFor(String command) {
    switch (command) {
      case accountMigrationLocalTransferCommandTranscript:
        return 'transcriptPairing';
      case accountMigrationLocalTransferCommandManifest:
        return 'manifestAcceptance';
      case accountMigrationLocalTransferCommandSegment:
        return 'segmentTransfer';
      case accountMigrationLocalTransferCommandChunk:
        return 'chunkTransfer';
      case accountMigrationLocalTransferCommandStatus:
        return 'resumeStatus';
      case accountMigrationLocalTransferCommandComplete:
        return 'completeVerification';
      case accountMigrationLocalTransferCommandOldBlockProof:
        return 'oldBlockProofCutover';
    }
    return command;
  }

  Duration _commandBudget(int budgetScaleBytes) {
    final floorMs = httpTimeout.inMilliseconds;
    final capMs = maxCommandTimeout.inMilliseconds < floorMs
        ? floorMs
        : maxCommandTimeout.inMilliseconds;
    final scaledMs = transferBytesPerSecondFloor <= 0
        ? floorMs
        : floorMs + (budgetScaleBytes * 1000 ~/ transferBytesPerSecondFloor);
    return Duration(milliseconds: scaledMs.clamp(floorMs, capMs));
  }

  Future<_MigrationJsonResponse> _postJson({
    required HttpClient httpClient,
    required LocalPeer peer,
    required String sessionId,
    required String command,
    required Map<String, Object?> body,
    int? segmentIndex,
    int? segmentCount,
    int? budgetScaleBytes,
    bool oldNetworkBlocked = false,
  }) async {
    final encodedBody = jsonEncode(body);
    final payloadBytes = encodedBody.length;
    final requestBudget = _commandBudget(budgetScaleBytes ?? payloadBytes);
    final commandStage = _commandStageFor(command);
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_START',
      details: {
        'sessionId': sessionId,
        'command': command,
        'commandStage': commandStage,
        'segmentIndex': ?segmentIndex,
        'segmentCount': ?segmentCount,
        'payloadBytes': payloadBytes,
        'timeoutMs': requestBudget.inMilliseconds,
        'httpTimeoutMs': httpTimeout.inMilliseconds,
      },
    );

    final stopwatch = Stopwatch()..start();
    var phase = 'connect';
    var phaseBudget = httpTimeout;

    Never failPost({required String errorType, required String reason}) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED',
        details: {
          'sessionId': sessionId,
          'command': command,
          'commandStage': commandStage,
          'segmentIndex': ?segmentIndex,
          'segmentCount': ?segmentCount,
          'payloadBytes': payloadBytes,
          'phase': phase,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'timeoutMs': phaseBudget.inMilliseconds,
          'errorType': errorType,
          'reason': reason,
          if (oldNetworkBlocked)
            'authorityRisk': 'oldNetworkBlockedWithoutNewActiveProof',
        },
      );
      throw _MigrationPostException(
        command: command,
        commandStage: commandStage,
        phase: phase,
        errorType: errorType,
        reason: reason,
      );
    }

    try {
      final encodedSessionId = Uri.encodeComponent(sessionId);
      final request = await httpClient
          .post(peer.host, peer.port, '/migration/$encodedSessionId/$command')
          .timeout(httpTimeout);
      final connectMs = stopwatch.elapsedMilliseconds;
      phase = 'bodyWrite';
      request.headers.contentType = ContentType.json;
      request.write(encodedBody);
      final bodyWriteMs = stopwatch.elapsedMilliseconds - connectMs;
      phase = 'closeAwaitResponse';
      phaseBudget = requestBudget;
      final response = await request.close().timeout(requestBudget);
      final responseWaitMs =
          stopwatch.elapsedMilliseconds - connectMs - bodyWriteMs;
      phase = 'responseBodyDrain';
      phaseBudget = httpTimeout;
      final responseBody = await utf8.decoder
          .bind(response)
          .join()
          .timeout(httpTimeout);
      final drainMs =
          stopwatch.elapsedMilliseconds -
          connectMs -
          bodyWriteMs -
          responseWaitMs;
      phase = 'decodeResponse';
      Map<String, dynamic>? decoded;
      if (responseBody.trim().isNotEmpty) {
        final value = jsonDecode(responseBody);
        if (value is Map<String, dynamic>) {
          decoded = value;
        }
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_RESPONSE',
        details: {
          'sessionId': sessionId,
          'command': command,
          'commandStage': commandStage,
          'segmentIndex': ?segmentIndex,
          'statusCode': response.statusCode,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'connectMs': connectMs,
          'bodyWriteMs': bodyWriteMs,
          'responseWaitMs': responseWaitMs,
          'drainMs': drainMs,
        },
      );
      return _MigrationJsonResponse(
        statusCode: response.statusCode,
        body: decoded,
      );
    } on TimeoutException {
      failPost(errorType: 'TimeoutException', reason: 'timeout');
    } on SocketException {
      failPost(errorType: 'SocketException', reason: 'socketError');
    } on HttpException {
      failPost(errorType: 'HttpException', reason: 'httpError');
    } on FormatException {
      failPost(errorType: 'FormatException', reason: 'malformedResponse');
    }
  }

  bool _isOk(_MigrationJsonResponse response) {
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  String _transferFailureText(MigrationTransferResultCode code) {
    switch (code) {
      case MigrationTransferResultCode.success:
        return 'The account bundle transfer completed.';
      case MigrationTransferResultCode.noLocalPath:
        return 'The new phone is not available over the local network.';
      case MigrationTransferResultCode.relayOrCloudForbidden:
        return 'Account migration cannot use relay or cloud fallback.';
      case MigrationTransferResultCode.manifestRejected:
        return 'The account bundle manifest was rejected.';
      case MigrationTransferResultCode.missingSegment:
        return 'The account bundle is missing one or more transfer segments.';
      case MigrationTransferResultCode.sendRejected:
        return 'The new phone rejected an account bundle segment.';
      case MigrationTransferResultCode.checkpointConflict:
        return 'The new phone found a conflicting transfer checkpoint.';
      case MigrationTransferResultCode.cryptoRejected:
        return 'The account bundle could not be encrypted for this session.';
      case MigrationTransferResultCode.transferTimedOut:
        return accountMigrationLocalTransferStalledSafeMessage;
    }
  }
}

class _ReceiverSession {
  final MigrationPendingPairingSession pendingSession;
  AuthenticatedMigrationChannelTranscript? transcript;
  MigrationTransferManifest? manifest;
  final acceptedSegmentIndexes = <int>{};

  /// Protocol v2 progress mirror (authoritative state lives in the
  /// receiver's file-backed ledger).
  int verifiedChunkCount = 0;

  _ReceiverSession({required this.pendingSession});
}

class _MigrationRequestContext {
  final String sessionId;
  final String command;
  final Stopwatch stopwatch = Stopwatch()..start();
  int? statusCode;
  int writeMs = 0;

  _MigrationRequestContext({required this.sessionId, required this.command});
}

class _MigrationPostException implements Exception {
  final String command;
  final String commandStage;
  final String phase;
  final String errorType;
  final String reason;

  const _MigrationPostException({
    required this.command,
    required this.commandStage,
    required this.phase,
    required this.errorType,
    required this.reason,
  });

  @override
  String toString() =>
      'MigrationPostException($command/$commandStage/$phase: $reason)';
}

class _MigrationPath {
  final String sessionId;
  final String command;

  const _MigrationPath({required this.sessionId, required this.command});

  static _MigrationPath? parse(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length < 3 || segments.first != 'migration') {
      return null;
    }
    return _MigrationPath(
      sessionId: Uri.decodeComponent(segments[1]),
      command: segments[2],
    );
  }
}

class _MigrationJsonResponse {
  final int statusCode;
  final Map<String, dynamic>? body;

  const _MigrationJsonResponse({required this.statusCode, this.body});
}

Future<(Map<String, dynamic>, int, int, int)> _readJsonTimed(
  HttpRequest request,
  _MigrationRequestContext context,
) async {
  final readStart = context.stopwatch.elapsedMilliseconds;
  final body = await utf8.decoder.bind(request).join();
  final bodyReadMs = context.stopwatch.elapsedMilliseconds - readStart;
  final decodeStart = context.stopwatch.elapsedMilliseconds;
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected JSON object');
  }
  final decodeMs = context.stopwatch.elapsedMilliseconds - decodeStart;
  return (decoded, body.length, bodyReadMs, decodeMs);
}

Future<void> _writeTracked(
  HttpRequest request,
  int statusCode,
  Map<String, Object?> body,
  _MigrationRequestContext context,
) async {
  final writeStart = context.stopwatch.elapsedMilliseconds;
  context.statusCode = statusCode;
  await _writeJson(request, statusCode, body);
  context.writeMs += context.stopwatch.elapsedMilliseconds - writeStart;
}

Future<void> _writeJson(
  HttpRequest request,
  int statusCode,
  Map<String, Object?> body,
) async {
  request.response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}

MigrationTransferManifest _manifestFromJson(Map<String, dynamic> json) {
  return MigrationTransferManifest.fromJson(json);
}

Map<String, Object?> _segmentToJson(MigrationEncryptedSegment segment) {
  return {
    'index': segment.index,
    'kem': segment.kem,
    'ciphertext': segment.ciphertext,
    'nonce': segment.nonce,
    'plaintext_sha256': segment.plaintextSha256,
    'ciphertext_sha256': segment.ciphertextSha256,
    'associated_data_sha256': segment.associatedDataSha256,
  };
}

MigrationEncryptedSegment _segmentFromJson(Map<String, dynamic> json) {
  return MigrationEncryptedSegment(
    index: json['index'] as int,
    kem: json['kem'] as String,
    ciphertext: json['ciphertext'] as String,
    nonce: json['nonce'] as String,
    plaintextSha256: json['plaintext_sha256'] as String,
    ciphertextSha256: json['ciphertext_sha256'] as String,
    associatedDataSha256: json['associated_data_sha256'] as String,
  );
}

Map<String, Object?> _chunkToJson(MigrationEncryptedChunk chunk) {
  return {
    'entry_id': chunk.entryId,
    'chunk_index': chunk.chunkIndex,
    'offset': chunk.offset,
    'is_final': chunk.isFinal,
    'kem_ciphertext': chunk.kemCiphertext,
    'ciphertext': chunk.ciphertext,
    'nonce': chunk.nonce,
    'plaintext_sha256': chunk.plaintextSha256,
    'ciphertext_sha256': chunk.ciphertextSha256,
    'associated_data_sha256': chunk.associatedDataSha256,
  };
}

MigrationEncryptedChunk _chunkFromJson(Map<String, dynamic> json) {
  return MigrationEncryptedChunk(
    entryId: json['entry_id'] as String,
    chunkIndex: json['chunk_index'] as int,
    offset: json['offset'] as int,
    isFinal: json['is_final'] as bool,
    kemCiphertext: json['kem_ciphertext'] as String,
    ciphertext: json['ciphertext'] as String,
    nonce: json['nonce'] as String,
    plaintextSha256: json['plaintext_sha256'] as String,
    ciphertextSha256: json['ciphertext_sha256'] as String,
    associatedDataSha256: json['associated_data_sha256'] as String,
  );
}
