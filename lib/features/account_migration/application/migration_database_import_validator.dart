import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:sqflite_common/sqlite_api.dart';

enum MigrationDatabaseImportError {
  missingIdentityRow,
  identitySecretColumnsNotNull,
  missingStagedSecret,
}

enum MigrationDatabaseImportResidual { mlKemChallengeUnsupported }

class MigrationDatabaseImportValidationResult {
  final List<MigrationDatabaseImportError> errors;
  final List<MigrationDatabaseImportResidual> residuals;

  const MigrationDatabaseImportValidationResult({
    required this.errors,
    required this.residuals,
  });

  bool get isAccepted => errors.isEmpty;

  bool hasError(MigrationDatabaseImportError error) => errors.contains(error);
}

class MigrationDatabaseImportValidator {
  final MigrationSecureStorageStaging secureStorageStaging;

  const MigrationDatabaseImportValidator({required this.secureStorageStaging});

  Future<MigrationDatabaseImportValidationResult> validate({
    required String sessionId,
    required Database stagedDb,
    required Iterable<MigrationSecureStorageKey> requiredSecretKeys,
  }) async {
    final errors = <MigrationDatabaseImportError>[];
    final identityRows = await stagedDb.query('identity', limit: 1);
    if (identityRows.isEmpty) {
      errors.add(MigrationDatabaseImportError.missingIdentityRow);
    } else {
      final row = identityRows.first;
      if (row['private_key'] != null ||
          row['mnemonic12'] != null ||
          row['ml_kem_secret_key'] != null) {
        errors.add(MigrationDatabaseImportError.identitySecretColumnsNotNull);
      }
    }

    for (final key in requiredSecretKeys) {
      final stagedValue = await secureStorageStaging.readStagedValue(
        sessionId: sessionId,
        key: key,
      );
      if (stagedValue == null || stagedValue.isEmpty) {
        errors.add(MigrationDatabaseImportError.missingStagedSecret);
        break;
      }
    }

    return MigrationDatabaseImportValidationResult(
      errors: List.unmodifiable(errors),
      residuals: const [
        MigrationDatabaseImportResidual.mlKemChallengeUnsupported,
      ],
    );
  }
}
