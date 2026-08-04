import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('MigrationDatabaseSchemaInventory', () {
    Database? db;

    tearDown(() async {
      final currentDb = db;
      db = null;
      if (currentDb != null && currentDb.isOpen) {
        await currentDb.close();
      }
    });

    test(
      'captures durable tables and schema-version-74 account columns',
      () async {
        db = await _openVersion74Fixture(includeLogicalDeliveryId: true);

        final inventory = await MigrationDatabaseSchemaInventory.fromDatabase(
          db!,
        );

        expect(inventory.tableNames, contains('identity'));
        expect(inventory.tableNames, contains('group_members'));
        expect(inventory.tableNames, contains('group_messages'));
        expect(inventory.tableNames, contains('inbox_staging_entries'));
        expect(inventory.tableNames, contains('group_pending_key_repairs'));
        expect(
          inventory.tableNames,
          contains('group_welcome_key_package_tombstones'),
        );
        expect(inventory.tableNames, contains('group_sync_receipts'));
        expect(inventory.tableNames, isNot(contains('sqlite_sequence')));
        expect(inventory.hasColumn('group_members', 'devices_json'), isTrue);
        expect(
          inventory.hasColumn('group_messages', 'transport_peer_id'),
          isTrue,
        );
        expect(
          inventory.hasColumn('group_messages', 'last_send_attempt_at'),
          isTrue,
        );
        expect(
          inventory.hasColumn('group_messages', 'logical_delivery_id'),
          isTrue,
        );
      },
    );

    test('schema hash changes when a durable column is missing', () async {
      db = await _openVersion74Fixture(includeLogicalDeliveryId: true);
      final full = await MigrationDatabaseSchemaInventory.fromDatabase(db!);
      await db!.close();
      db = null;

      db = await _openVersion74Fixture(includeLogicalDeliveryId: false);
      final missingColumn = await MigrationDatabaseSchemaInventory.fromDatabase(
        db!,
      );

      expect(
        missingColumn.hasColumn('group_messages', 'logical_delivery_id'),
        isFalse,
      );
      expect(missingColumn.schemaHash, isNot(full.schemaHash));
    });

    test(
      'v107 inventory includes every typed direct notification authority',
      () async {
        db = await openDatabase(
          inMemoryDatabasePath,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );

        final inventory = await MigrationDatabaseSchemaInventory.fromDatabase(
          db!,
        );

        expect(currentIdentityDatabaseVersion, 107);
        expect(
          inventory.tableNames,
          containsAll(<String>[
            'direct_notification_display_outbox',
            'direct_notification_read_acknowledgements',
            'direct_notification_reaction_terminal_events',
            'direct_notification_reconciliation_outbox',
          ]),
        );
        expect(
          inventory.hasColumn(
            'direct_notification_reaction_terminal_events',
            'peer_id',
          ),
          isTrue,
        );
        expect(
          inventory.hasColumn(
            'direct_notification_reaction_terminal_events',
            'terminal_event_id',
          ),
          isTrue,
        );
        expect(
          inventory.hasColumn('message_reactions', 'direct_peer_id'),
          isFalse,
        );
      },
    );
  });
}

Future<Database> _openVersion74Fixture({
  required bool includeLogicalDeliveryId,
}) async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    version: 1,
    singleInstance: false,
  );
  await db.execute('''
CREATE TABLE identity (
  id INTEGER PRIMARY KEY,
  peer_id TEXT NOT NULL,
  public_key TEXT NOT NULL,
  private_key TEXT,
  mnemonic12 TEXT,
  ml_kem_secret_key TEXT,
  username TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');
  await db.execute('''
CREATE TABLE group_members (
  group_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  devices_json TEXT,
  permissions_json TEXT,
  PRIMARY KEY(group_id, peer_id)
)
''');
  await db.execute('''
CREATE TABLE group_messages (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  transport_peer_id TEXT,
  last_send_attempt_at TEXT
  ${includeLogicalDeliveryId ? ', logical_delivery_id TEXT' : ''}
)
''');
  await db.execute('''
CREATE TABLE inbox_staging_entries (
  entry_id TEXT PRIMARY KEY,
  payload_json TEXT NOT NULL
)
''');
  await db.execute('''
CREATE TABLE group_pending_key_repairs (
  repair_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL
)
''');
  await db.execute('''
CREATE TABLE group_welcome_key_package_tombstones (
  package_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL
)
''');
  await db.execute('''
CREATE TABLE group_sync_receipts (
  group_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  last_message_id TEXT,
  PRIMARY KEY(group_id, peer_id)
)
''');
  return db;
}
