import 'package:flutter_app/features/account_migration/domain/models/migration_cutover_record.dart';

abstract class MigrationCutoverRepository {
  Future<MigrationCutoverRecord?> loadCutover();

  Future<void> saveCutover(MigrationCutoverRecord record);

  Future<void> clearCutover();
}
