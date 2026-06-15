import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';

enum AccountMigrationTransferStep {
  preparing,
  connecting,
  encrypting,
  transferringDatabase,
  transferringMedia,
  checking,
  finishing,
}

enum AccountMigrationTransferFailureCode {
  runnerUnavailable,
  cancelled,
  localPeerUnavailable,
  receiverRejected,
  bundleExporterUnavailable,
  bundleImporterUnavailable,
  transferRejected,
  localTransferTimedOut,
  accountTooLargeToMove,
  receiverStorageInsufficient,
  verificationFailed,
  cutoverRejected,
  unknown,
}

class AccountMigrationTransferRequest {
  final AuthenticatedMigrationChannelTranscript transcript;

  const AccountMigrationTransferRequest({required this.transcript});

  String get sessionId => transcript.sessionId;
  String get newPhoneEphemeralPublicKey =>
      transcript.newPhoneEphemeralPublicKey;
  String get oldPhonePeerId => transcript.oldPhonePeerId;
}

class AccountMigrationTransferResult {
  final bool isSuccess;
  final AccountMigrationTransferFailureCode? failureCode;
  final String? safeMessage;

  const AccountMigrationTransferResult._({
    required this.isSuccess,
    this.failureCode,
    this.safeMessage,
  });

  const AccountMigrationTransferResult.success() : this._(isSuccess: true);

  const AccountMigrationTransferResult.failure({
    required AccountMigrationTransferFailureCode code,
    required String safeMessage,
  }) : this._(isSuccess: false, failureCode: code, safeMessage: safeMessage);

  const AccountMigrationTransferResult.cancelled()
    : this._(
        isSuccess: false,
        failureCode: AccountMigrationTransferFailureCode.cancelled,
        safeMessage: 'The account move was cancelled.',
      );
}

typedef AccountMigrationTransferProgressCallback =
    void Function(AccountMigrationTransferStep step);

/// Deterministic progress of the segment-upload phase: the bundle is sent as
/// a fixed, known number of encrypted segments, so the UI can render a real
/// progress bar instead of an indeterminate spinner.
class AccountMigrationTransferSegmentProgress {
  final int sentSegments;
  final int totalSegments;

  const AccountMigrationTransferSegmentProgress({
    required this.sentSegments,
    required this.totalSegments,
  });

  double? get fraction {
    if (totalSegments <= 0) {
      return null;
    }
    final value = sentSegments / totalSegments;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }
}

typedef AccountMigrationTransferSegmentProgressCallback =
    void Function(AccountMigrationTransferSegmentProgress progress);

typedef AccountMigrationTransferRunFn =
    Future<AccountMigrationTransferResult> Function({
      required AccountMigrationTransferRequest request,
      required AccountMigrationTransferProgressCallback onProgress,
      required bool Function() isCancelled,
      AccountMigrationTransferSegmentProgressCallback? onSegmentProgress,
    });

const accountMigrationBundleSourceFailedSafeMessage =
    'The old phone could not assemble the account bundle. Keep both phones open and try again. If it keeps failing, restart the old phone and retry Move Account.';

const accountMigrationLocalTransferStalledSafeMessage =
    'The local transfer between the phones stalled. Keep both phones open, awake, and on the same Wi-Fi, then try Move Account again.';

const accountMigrationFinalHandoffStalledSafeMessage =
    'The final handoff between the phones stalled. Keep both phones open and on the same Wi-Fi, then try Move Account again. Do not erase the old phone until the move completes.';

String accountMigrationTransferErrorType(Object error) {
  final type = error.runtimeType.toString();
  return type.isEmpty ? 'unknown' : type;
}

String accountMigrationBundleSourceFailureReason(Object error) {
  final message = sanitizeDiagnosticText(error).toLowerCase();
  if (message.contains('missing critical secure value')) {
    return 'missingCriticalSecureValue';
  }
  if (message.contains('file manifest has blocking issues')) {
    return 'fileManifestBlockingIssues';
  }
  if (message.contains('file changed while assembling')) {
    return 'fileChangedWhileAssembling';
  }
  if (message.contains('migrationdatabasesnapshotexportexception') ||
      message.contains('sqlcipher') ||
      message.contains('quick_check') ||
      message.contains('integrity check') ||
      message.contains('database')) {
    return 'databaseSnapshotExportFailed';
  }
  if (message.contains('migrationsegmentcryptoexception') ||
      message.contains('encrypt')) {
    return 'segmentEncryptionFailed';
  }
  return 'bundleSourceFailed';
}

enum AccountMigrationReceiverStartFailureCode {
  receiverUnavailable,
  localNetworkUnavailable,
  sessionUnavailable,
  sessionExpired,
  unknown,
}

class AccountMigrationReceiverStartResult {
  final bool isStarted;
  final AccountMigrationReceiverStartFailureCode? failureCode;
  final String? safeMessage;

  const AccountMigrationReceiverStartResult._({
    required this.isStarted,
    this.failureCode,
    this.safeMessage,
  });

  const AccountMigrationReceiverStartResult.started() : this._(isStarted: true);

  const AccountMigrationReceiverStartResult.failure({
    required AccountMigrationReceiverStartFailureCode code,
    required String safeMessage,
  }) : this._(isStarted: false, failureCode: code, safeMessage: safeMessage);
}

typedef AccountMigrationReceiverStartFn =
    Future<AccountMigrationReceiverStartResult> Function(
      MigrationQrBuildOutput output,
    );

typedef AccountMigrationReceiverStopFn =
    Future<void> Function(String sessionId);

enum AccountMigrationReceiverEventType {
  receivingSegment,
  importingBundle,
  importVerified,
  activated,
  failed,
}

class AccountMigrationReceiverEvent {
  final String sessionId;
  final AccountMigrationReceiverEventType type;
  final String? safeMessage;
  final int? segmentIndex;
  final int? segmentCount;
  final int? verifiedCount;

  const AccountMigrationReceiverEvent({
    required this.sessionId,
    required this.type,
    this.safeMessage,
    this.segmentIndex,
    this.segmentCount,
    this.verifiedCount,
  });

  const AccountMigrationReceiverEvent.receivingSegment({
    required String sessionId,
    int? segmentIndex,
    int? segmentCount,
    int? verifiedCount,
  }) : this(
         sessionId: sessionId,
         type: AccountMigrationReceiverEventType.receivingSegment,
         segmentIndex: segmentIndex,
         segmentCount: segmentCount,
         verifiedCount: verifiedCount,
       );

  const AccountMigrationReceiverEvent.importingBundle({
    required String sessionId,
    int? segmentCount,
    int? verifiedCount,
  }) : this(
         sessionId: sessionId,
         type: AccountMigrationReceiverEventType.importingBundle,
         segmentCount: segmentCount,
         verifiedCount: verifiedCount,
       );

  const AccountMigrationReceiverEvent.importVerified({
    required String sessionId,
  }) : this(
         sessionId: sessionId,
         type: AccountMigrationReceiverEventType.importVerified,
       );

  const AccountMigrationReceiverEvent.activated({required String sessionId})
    : this(
        sessionId: sessionId,
        type: AccountMigrationReceiverEventType.activated,
      );

  const AccountMigrationReceiverEvent.failed({
    required String sessionId,
    required String safeMessage,
  }) : this(
         sessionId: sessionId,
         type: AccountMigrationReceiverEventType.failed,
         safeMessage: safeMessage,
       );
}

typedef AccountMigrationReceiverEvents = Stream<AccountMigrationReceiverEvent>;

Future<AccountMigrationTransferResult>
accountMigrationTransferRunnerUnavailable({
  required AccountMigrationTransferRequest request,
  required AccountMigrationTransferProgressCallback onProgress,
  required bool Function() isCancelled,
  AccountMigrationTransferSegmentProgressCallback? onSegmentProgress,
}) async {
  if (isCancelled()) {
    return const AccountMigrationTransferResult.cancelled();
  }
  return const AccountMigrationTransferResult.failure(
    code: AccountMigrationTransferFailureCode.runnerUnavailable,
    safeMessage:
        'Move Account could not start the transfer from this screen. Close this screen, reopen Settings, and start Move Account again.',
  );
}
