import 'package:flutter_app/features/account_migration/domain/models/migration_file_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';

typedef MigrationAvailableBytesProvider = Future<int> Function();

enum MigrationStoragePreflightReason {
  accepted,
  storageInsufficient,
  storageUnavailable,
}

class MigrationStoragePreflightResult {
  final bool isAccepted;
  final MigrationStoragePreflightReason reason;
  final int requiredBytes;
  final int optionalBytes;
  final int stagingOverheadBytes;
  final int headroomBytes;
  final int? availableBytes;

  const MigrationStoragePreflightResult({
    required this.isAccepted,
    required this.reason,
    required this.requiredBytes,
    required this.optionalBytes,
    required this.stagingOverheadBytes,
    required this.headroomBytes,
    required this.availableBytes,
  });

  int get totalRequiredWithHeadroom {
    return requiredBytes + stagingOverheadBytes + headroomBytes;
  }
}

class MigrationStoragePreflight {
  static const v1ProtocolImportAmplificationFactor = 3;

  /// Protocol v2 stages entries once on disk and finalizes them by rename
  /// (no decoded copy, no segment+payload coexistence), so import peaks near
  /// 1.2× of the account; 2× keeps conservative margin for the staged DB.
  static const v2ProtocolImportAmplificationFactor = 2;

  final MigrationAvailableBytesProvider availableBytesProvider;
  final int stagingOverheadBytes;
  final int headroomBytes;

  const MigrationStoragePreflight({
    required this.availableBytesProvider,
    this.stagingOverheadBytes = 0,
    this.headroomBytes = 0,
  });

  Future<MigrationStoragePreflightResult> evaluate({
    required MigrationFileManifest manifest,
  }) async {
    final requiredBytes = manifest.totalCriticalBytes;
    final optionalBytes = manifest.totalNonCriticalBytes;
    try {
      final availableBytes = await availableBytesProvider();
      final total = requiredBytes + stagingOverheadBytes + headroomBytes;
      final accepted = availableBytes >= total;
      return MigrationStoragePreflightResult(
        isAccepted: accepted,
        reason: accepted
            ? MigrationStoragePreflightReason.accepted
            : MigrationStoragePreflightReason.storageInsufficient,
        requiredBytes: requiredBytes,
        optionalBytes: optionalBytes,
        stagingOverheadBytes: stagingOverheadBytes,
        headroomBytes: headroomBytes,
        availableBytes: availableBytes,
      );
    } catch (_) {
      return MigrationStoragePreflightResult(
        isAccepted: false,
        reason: MigrationStoragePreflightReason.storageUnavailable,
        requiredBytes: requiredBytes,
        optionalBytes: optionalBytes,
        stagingOverheadBytes: stagingOverheadBytes,
        headroomBytes: headroomBytes,
        availableBytes: null,
      );
    }
  }

  Future<MigrationStoragePreflightResult> evaluateTransfer({
    required MigrationTransferManifest manifest,
  }) {
    final amplificationFactor = manifest.isEntryStreamed
        ? v2ProtocolImportAmplificationFactor
        : v1ProtocolImportAmplificationFactor;
    return _evaluateRequiredBytes(
      requiredBytes: manifest.totalBytes * amplificationFactor,
      optionalBytes: 0,
    );
  }

  Future<MigrationStoragePreflightResult> _evaluateRequiredBytes({
    required int requiredBytes,
    required int optionalBytes,
  }) async {
    try {
      final availableBytes = await availableBytesProvider();
      final total = requiredBytes + stagingOverheadBytes + headroomBytes;
      final accepted = availableBytes >= total;
      return MigrationStoragePreflightResult(
        isAccepted: accepted,
        reason: accepted
            ? MigrationStoragePreflightReason.accepted
            : MigrationStoragePreflightReason.storageInsufficient,
        requiredBytes: requiredBytes,
        optionalBytes: optionalBytes,
        stagingOverheadBytes: stagingOverheadBytes,
        headroomBytes: headroomBytes,
        availableBytes: availableBytes,
      );
    } catch (_) {
      return MigrationStoragePreflightResult(
        isAccepted: false,
        reason: MigrationStoragePreflightReason.storageUnavailable,
        requiredBytes: requiredBytes,
        optionalBytes: optionalBytes,
        stagingOverheadBytes: stagingOverheadBytes,
        headroomBytes: headroomBytes,
        availableBytes: null,
      );
    }
  }
}
