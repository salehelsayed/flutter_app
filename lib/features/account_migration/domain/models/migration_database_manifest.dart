import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';

enum MigrationDatabaseCipherPolicy { compatible, unsupported }

enum MigrationDatabaseManifestError {
  unsupportedProtocolVersion,
  importerTooOld,
  unsupportedDatabaseVersion,
  unsupportedCipherPolicy,
  checksumMismatch,
  schemaHashMismatch,
}

class MigrationDatabaseCipherMetadata {
  final String cipherVersion;
  final int? kdfIter;
  final int? cipherPageSize;
  final MigrationDatabaseCipherPolicy policy;

  const MigrationDatabaseCipherMetadata({
    required this.cipherVersion,
    this.kdfIter,
    this.cipherPageSize,
    required this.policy,
  });

  Map<String, Object?> toJson() {
    return {
      'cipher_version': cipherVersion,
      if (kdfIter != null) 'kdf_iter': kdfIter,
      if (cipherPageSize != null) 'cipher_page_size': cipherPageSize,
      'policy': policy.name,
    };
  }
}

class MigrationDatabaseManifest {
  static const int protocolVersion = 1;
  static const String unknownAppVersion = 'unknown';
  static const String unknownBuildNumber = 'unknown';

  final int protocolVersionValue;
  final int minimumImporterProtocolVersion;
  final String sourceAppVersion;
  final String sourceBuildNumber;
  final int databaseVersion;
  final String schemaHash;
  final MigrationDatabaseSchemaInventory schemaInventory;
  final String databaseChecksumSha256;
  final MigrationDatabaseCipherMetadata cipherMetadata;

  const MigrationDatabaseManifest({
    required this.protocolVersionValue,
    required this.minimumImporterProtocolVersion,
    required this.sourceAppVersion,
    required this.sourceBuildNumber,
    required this.databaseVersion,
    required this.schemaHash,
    required this.schemaInventory,
    required this.databaseChecksumSha256,
    required this.cipherMetadata,
  });

  factory MigrationDatabaseManifest.current({
    required String sourceAppVersion,
    required String sourceBuildNumber,
    required MigrationDatabaseSchemaInventory schemaInventory,
    required String databaseChecksumSha256,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) {
    return MigrationDatabaseManifest(
      protocolVersionValue: protocolVersion,
      minimumImporterProtocolVersion: protocolVersion,
      sourceAppVersion: sourceAppVersion,
      sourceBuildNumber: sourceBuildNumber,
      databaseVersion: currentIdentityDatabaseVersion,
      schemaHash: schemaInventory.schemaHash,
      schemaInventory: schemaInventory,
      databaseChecksumSha256: databaseChecksumSha256,
      cipherMetadata: cipherMetadata,
    );
  }

  MigrationDatabaseManifest copyWith({
    int? protocolVersion,
    int? minimumImporterProtocolVersion,
    String? sourceAppVersion,
    String? sourceBuildNumber,
    int? databaseVersion,
    String? schemaHash,
    MigrationDatabaseSchemaInventory? schemaInventory,
    String? databaseChecksumSha256,
    MigrationDatabaseCipherMetadata? cipherMetadata,
  }) {
    return MigrationDatabaseManifest(
      protocolVersionValue: protocolVersion ?? protocolVersionValue,
      minimumImporterProtocolVersion:
          minimumImporterProtocolVersion ?? this.minimumImporterProtocolVersion,
      sourceAppVersion: sourceAppVersion ?? this.sourceAppVersion,
      sourceBuildNumber: sourceBuildNumber ?? this.sourceBuildNumber,
      databaseVersion: databaseVersion ?? this.databaseVersion,
      schemaHash: schemaHash ?? this.schemaHash,
      schemaInventory: schemaInventory ?? this.schemaInventory,
      databaseChecksumSha256:
          databaseChecksumSha256 ?? this.databaseChecksumSha256,
      cipherMetadata: cipherMetadata ?? this.cipherMetadata,
    );
  }

  MigrationDatabaseManifestCompatibility compatibility() {
    final errors = <MigrationDatabaseManifestError>[];
    if (protocolVersionValue != protocolVersion) {
      errors.add(MigrationDatabaseManifestError.unsupportedProtocolVersion);
    }
    if (minimumImporterProtocolVersion > protocolVersion) {
      errors.add(MigrationDatabaseManifestError.importerTooOld);
    }
    if (databaseVersion != currentIdentityDatabaseVersion) {
      errors.add(MigrationDatabaseManifestError.unsupportedDatabaseVersion);
    }
    if (cipherMetadata.policy != MigrationDatabaseCipherPolicy.compatible) {
      errors.add(MigrationDatabaseManifestError.unsupportedCipherPolicy);
    }
    if (schemaHash != schemaInventory.schemaHash) {
      errors.add(MigrationDatabaseManifestError.schemaHashMismatch);
    }
    return MigrationDatabaseManifestCompatibility(errors);
  }

  Map<String, Object?> toJson() {
    return {
      'protocol_version': protocolVersionValue,
      'source_app_version': sourceAppVersion,
      'source_build_number': sourceBuildNumber,
      'minimum_importer_protocol_version': minimumImporterProtocolVersion,
      'database_version': databaseVersion,
      'schema_hash': schemaHash,
      'database_checksum_sha256': databaseChecksumSha256,
      'cipher_metadata': cipherMetadata.toJson(),
      'schema_inventory': schemaInventory.toJson(),
    };
  }
}

class MigrationDatabaseManifestCompatibility {
  final List<MigrationDatabaseManifestError> errors;

  const MigrationDatabaseManifestCompatibility(this.errors);

  bool get isAccepted => errors.isEmpty;

  bool hasError(MigrationDatabaseManifestError error) {
    return errors.contains(error);
  }
}
