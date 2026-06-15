import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';

enum AccountMigrationRole { newPhone, oldPhone }

enum AccountMigrationQrPresentationStatus {
  loading,
  ready,
  keygenFailed,
  persistenceFailed,
  receiverFailed,
}

class AccountMigrationQrPresentationState {
  final AccountMigrationQrPresentationStatus status;
  final String? qrJson;
  final DateTime? expiresAt;
  final String? confirmationCode;
  final String? errorText;

  const AccountMigrationQrPresentationState._({
    required this.status,
    this.qrJson,
    this.expiresAt,
    this.confirmationCode,
    this.errorText,
  });

  const AccountMigrationQrPresentationState.loading()
    : this._(status: AccountMigrationQrPresentationStatus.loading);

  const AccountMigrationQrPresentationState.ready({
    required String qrJson,
    required DateTime expiresAt,
    required String confirmationCode,
  }) : this._(
         status: AccountMigrationQrPresentationStatus.ready,
         qrJson: qrJson,
         expiresAt: expiresAt,
         confirmationCode: confirmationCode,
       );

  const AccountMigrationQrPresentationState.keygenFailed()
    : this._(status: AccountMigrationQrPresentationStatus.keygenFailed);

  const AccountMigrationQrPresentationState.persistenceFailed()
    : this._(status: AccountMigrationQrPresentationStatus.persistenceFailed);

  const AccountMigrationQrPresentationState.receiverFailed(String errorText)
    : this._(
        status: AccountMigrationQrPresentationStatus.receiverFailed,
        errorText: errorText,
      );

  factory AccountMigrationQrPresentationState.fromBuildResult({
    required BuildMigrationQrPayloadResult result,
    required MigrationQrBuildOutput? output,
  }) {
    switch (result) {
      case BuildMigrationQrPayloadResult.success:
        final buildOutput = output;
        if (buildOutput == null) {
          return const AccountMigrationQrPresentationState.persistenceFailed();
        }
        return AccountMigrationQrPresentationState.ready(
          qrJson: buildOutput.qrJson,
          expiresAt: buildOutput.payload.expiresAt,
          confirmationCode: deriveMigrationPairingConfirmationCode(
            buildOutput.payload,
          ),
        );
      case BuildMigrationQrPayloadResult.keygenFailed:
        return const AccountMigrationQrPresentationState.keygenFailed();
      case BuildMigrationQrPayloadResult.persistenceFailed:
        return const AccountMigrationQrPresentationState.persistenceFailed();
    }
  }
}

enum AccountMigrationOldPhoneStatus {
  waitingForScan,
  authorizing,
  confirmationReady,
  failed,
}

class AccountMigrationOldPhonePresentationState {
  final AccountMigrationOldPhoneStatus status;
  final String? confirmationCode;
  final String? errorText;
  final AccountMigrationMoveSizeEstimate? sizeEstimate;
  final String? sizeCapBlockedMessage;

  const AccountMigrationOldPhonePresentationState._({
    required this.status,
    this.confirmationCode,
    this.errorText,
    this.sizeEstimate,
    this.sizeCapBlockedMessage,
  });

  const AccountMigrationOldPhonePresentationState.waitingForScan()
    : this._(status: AccountMigrationOldPhoneStatus.waitingForScan);

  const AccountMigrationOldPhonePresentationState.authorizing()
    : this._(status: AccountMigrationOldPhoneStatus.authorizing);

  const AccountMigrationOldPhonePresentationState.confirmationReady({
    required String confirmationCode,
    AccountMigrationMoveSizeEstimate? sizeEstimate,
    String? sizeCapBlockedMessage,
  }) : this._(
         status: AccountMigrationOldPhoneStatus.confirmationReady,
         confirmationCode: confirmationCode,
         sizeEstimate: sizeEstimate,
         sizeCapBlockedMessage: sizeCapBlockedMessage,
       );

  const AccountMigrationOldPhonePresentationState.failed(String errorText)
    : this._(
        status: AccountMigrationOldPhoneStatus.failed,
        errorText: errorText,
      );
}

enum AccountMigrationProgressStage {
  preparing,
  connecting,
  encrypting,
  transferringDatabase,
  transferringMedia,
  checking,
  finishing,
  completed,
  cancelled,
  failed,
}

extension AccountMigrationProgressStageStatus on AccountMigrationProgressStage {
  bool get isTerminal {
    switch (this) {
      case AccountMigrationProgressStage.completed:
      case AccountMigrationProgressStage.cancelled:
      case AccountMigrationProgressStage.failed:
        return true;
      case AccountMigrationProgressStage.preparing:
      case AccountMigrationProgressStage.connecting:
      case AccountMigrationProgressStage.encrypting:
      case AccountMigrationProgressStage.transferringDatabase:
      case AccountMigrationProgressStage.transferringMedia:
      case AccountMigrationProgressStage.checking:
      case AccountMigrationProgressStage.finishing:
        return false;
    }
  }

  bool get holdsWakeLock => !isTerminal;
}
