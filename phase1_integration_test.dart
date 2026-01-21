import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

void main() {
  late Database db;

  setUpAll(() {
    // Initialize FFI for testing
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Create in-memory database for testing
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('Phase 1 Integration: DB + Model integration', () async {
    // Test: DB + Model integration
    print('Starting Phase 1 Integration Test...');

    // Run migration
    await runIdentityTableMigration(db);
    print('✓ Migration completed');

    // Create a test IdentityModel
    final model = IdentityModel(
      peerId: '12D3KooWTestPeerID',
      publicKey: 'dGVzdFB1YmxpY0tleQ==',
      privateKey: 'dGVzdFByaXZhdGVLZXk=',
      mnemonic12: 'abandon ability able about above absent absorb abstract absurd abuse access accident',
      createdAt: '2025-01-17T12:00:00.000Z',
      updatedAt: '2025-01-17T12:00:00.000Z',
    );
    print('✓ IdentityModel created');

    // Convert to JSON (verify keys match expected format)
    final row = model.toJson();
    print('✓ Model converted to JSON');

    // Verify the JSON has correct camelCase keys
    expect(row.containsKey('peerId'), isTrue, reason: 'Should have peerId key');
    expect(row.containsKey('publicKey'), isTrue, reason: 'Should have publicKey key');
    expect(row.containsKey('privateKey'), isTrue, reason: 'Should have privateKey key');
    expect(row.containsKey('mnemonic12'), isTrue, reason: 'Should have mnemonic12 key');
    expect(row.containsKey('createdAt'), isTrue, reason: 'Should have createdAt key');
    expect(row.containsKey('updatedAt'), isTrue, reason: 'Should have updatedAt key');
    print('✓ JSON keys verified (camelCase)');

    // Verify values match
    expect(row['peerId'], equals(model.peerId));
    expect(row['publicKey'], equals(model.publicKey));
    expect(row['privateKey'], equals(model.privateKey));
    expect(row['mnemonic12'], equals(model.mnemonic12));
    expect(row['createdAt'], equals(model.createdAt));
    expect(row['updatedAt'], equals(model.updatedAt));
    print('✓ JSON values match model');

    // Verify table exists by querying it
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='identity'"
    );
    expect(tables.length, equals(1), reason: 'Identity table should exist');
    print('✓ Identity table exists in database');

    // Test round-trip: JSON -> Model -> JSON
    final modelFromJson = IdentityModel.fromJson(row);
    final rowAgain = modelFromJson.toJson();
    expect(rowAgain, equals(row), reason: 'Round-trip should preserve data');
    print('✓ Round-trip JSON serialization works');

    print('\n✅ Phase 1 Integration Test PASSED!');
    print('   - Database migration works');
    print('   - IdentityModel JSON mapping works');
    print('   - Keys are in correct camelCase format');
  });
}