import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common/sqlite_api.dart';

enum MigrationDatabaseTableTransferPolicy { accountPortable, installationLocal }

class MigrationDatabaseSchemaInventory {
  static const Set<String> installationLocalTableNames = <String>{
    'notification_completed_outcome_outbox',
  };

  final Map<String, List<String>> tables;

  MigrationDatabaseSchemaInventory._(Map<String, List<String>> tables)
    : tables = _canonicalize(tables);

  factory MigrationDatabaseSchemaInventory.fromTables(
    Map<String, List<String>> tables,
  ) {
    return MigrationDatabaseSchemaInventory._(tables);
  }

  static Future<MigrationDatabaseSchemaInventory> fromDatabase(
    DatabaseExecutor db,
  ) async {
    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
      'ORDER BY name',
    );
    final tables = <String, List<String>>{};
    for (final row in tableRows) {
      final tableName = row['name'] as String?;
      if (tableName == null || tableName.isEmpty) {
        continue;
      }
      final columnRows = await db.rawQuery(
        'PRAGMA table_info(${_quoteIdentifier(tableName)})',
      );
      final columns = columnRows
          .map((column) => column['name'])
          .whereType<String>()
          .toList(growable: false);
      tables[tableName] = columns;
    }
    return MigrationDatabaseSchemaInventory._(tables);
  }

  List<String> get tableNames => List.unmodifiable(tables.keys);

  List<String> get transferableTableNames =>
      List.unmodifiable(tableNames.where((name) => !isInstallationLocal(name)));

  List<String> get presentInstallationLocalTableNames =>
      List.unmodifiable(tableNames.where(isInstallationLocal));

  static bool isInstallationLocal(String tableName) =>
      installationLocalTableNames.contains(tableName);

  static MigrationDatabaseTableTransferPolicy transferPolicyFor(
    String tableName,
  ) => isInstallationLocal(tableName)
      ? MigrationDatabaseTableTransferPolicy.installationLocal
      : MigrationDatabaseTableTransferPolicy.accountPortable;

  String get schemaHash {
    final canonical = jsonEncode(toJson());
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  bool hasColumn(String tableName, String columnName) {
    return tables[tableName]?.contains(columnName) ?? false;
  }

  Map<String, Object?> toJson() {
    return {
      for (final entry in tables.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    };
  }

  static Map<String, List<String>> _canonicalize(
    Map<String, List<String>> source,
  ) {
    final sortedNames =
        source.keys.where((name) => !name.startsWith('sqlite_')).toList()
          ..sort();
    return {
      for (final name in sortedNames)
        name: (List<String>.from(source[name] ?? const [])..sort()),
    };
  }

  static String _quoteIdentifier(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }
}
