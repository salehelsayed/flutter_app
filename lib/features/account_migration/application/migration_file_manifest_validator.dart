import 'package:flutter_app/features/account_migration/application/migration_file_manifest_builder.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_file_manifest.dart';

class MigrationFileManifestValidator {
  final MigrationFileManifestBuilder _builder;

  MigrationFileManifestValidator({
    required String documentsRootPath,
    MigrationSecureValueReader? secureValueReader,
  }) : _builder = MigrationFileManifestBuilder(
         documentsRootPath: documentsRootPath,
         secureValueReader: secureValueReader,
       );

  Future<MigrationFileManifest> validateRows({
    Iterable<Map<String, Object?>> chatMediaRows = const [],
    Iterable<Map<String, Object?>> directMediaBlobCustodyRows = const [],
    Iterable<Map<String, Object?>> postMediaRows = const [],
    Iterable<Map<String, Object?>> postMediaRecoveryRows = const [],
    Iterable<Map<String, Object?>> contactRows = const [],
    Iterable<Map<String, Object?>> identityRows = const [],
    Iterable<Map<String, Object?>> groupRows = const [],
  }) {
    return _builder.build(
      chatMediaRows: chatMediaRows,
      directMediaBlobCustodyRows: directMediaBlobCustodyRows,
      postMediaRows: postMediaRows,
      postMediaRecoveryRows: postMediaRecoveryRows,
      contactRows: contactRows,
      identityRows: identityRows,
      groupRows: groupRows,
    );
  }
}
