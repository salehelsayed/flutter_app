import 'package:flutter_app/features/account_migration/application/migration_group_manifest_builder.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_group_manifest.dart';

class MigrationGroupManifestValidator {
  final MigrationGroupManifestBuilder builder;

  const MigrationGroupManifestValidator({required this.builder});

  Future<MigrationGroupManifest> validateRows({
    Iterable<Map<String, Object?>> groupRows = const [],
    Iterable<Map<String, Object?>> committedGroupKeyRows = const [],
    Iterable<Map<String, Object?>> pendingGroupKeyRows = const [],
    Iterable<Map<String, Object?>> groupMemberRows = const [],
    Iterable<Map<String, Object?>> groupMessageRows = const [],
    Iterable<Map<String, Object?>> groupMessageReceiptRows = const [],
    Iterable<Map<String, Object?>> welcomeKeyPackageRows = const [],
    Iterable<Map<String, Object?>> pendingKeyRepairRows = const [],
    Iterable<Map<String, Object?>> pendingMembershipMessageRows = const [],
    Iterable<Map<String, Object?>> welcomeKeyPackageTombstoneRows = const [],
    Iterable<Map<String, Object?>> groupInboxCursorRows = const [],
  }) {
    return builder.build(
      groupRows: groupRows,
      committedGroupKeyRows: committedGroupKeyRows,
      pendingGroupKeyRows: pendingGroupKeyRows,
      groupMemberRows: groupMemberRows,
      groupMessageRows: groupMessageRows,
      groupMessageReceiptRows: groupMessageReceiptRows,
      welcomeKeyPackageRows: welcomeKeyPackageRows,
      pendingKeyRepairRows: pendingKeyRepairRows,
      pendingMembershipMessageRows: pendingMembershipMessageRows,
      welcomeKeyPackageTombstoneRows: welcomeKeyPackageTombstoneRows,
      groupInboxCursorRows: groupInboxCursorRows,
    );
  }
}
