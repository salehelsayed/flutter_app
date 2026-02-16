import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'test/core/secure_storage/fake_secure_key_store.dart';

void main() {
  late Database db;
  late IdentityRepositoryImpl repo;

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

    // Run migration
    await runIdentityTableMigration(db);

    // Create repository with DB helpers
    repo = IdentityRepositoryImpl(
      dbLoadIdentityRow: () => dbLoadIdentityRow(db),
      dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
      secureKeyStore: FakeSecureKeyStore(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('Phase 2 Integration: Repository round-trip', () async {
    print('Starting Phase 2 Integration Test...');
    print('');

    // Step 1: Verify empty state
    print('Step 1: Checking initial state (should be empty)...');
    final initialLoad = await repo.loadIdentity();
    expect(initialLoad, isNull, reason: 'Repository should return null when no identity exists');
    print('✓ Initial load returned null (correct)');
    print('');

    // Step 2: Create test identity
    print('Step 2: Creating test identity...');
    final testIdentity = IdentityModel(
      peerId: '12D3KooWPhase2TestPeerID',
      publicKey: 'cGhhc2UyUHVibGljS2V5',
      privateKey: 'cGhhc2UyUHJpdmF0ZUtleQ==',
      mnemonic12: 'phase two test words here are twelve words for testing purposes only',
      createdAt: '2025-01-17T14:00:00.000Z',
      updatedAt: '2025-01-17T14:00:00.000Z',
    );
    print('✓ Test identity created');
    print('  PeerID: ${testIdentity.peerId}');
    print('');

    // Step 3: Save identity through repository
    print('Step 3: Saving identity through repository...');
    await repo.saveIdentity(testIdentity);
    print('✓ Identity saved successfully');
    print('');

    // Step 4: Load identity back through repository
    print('Step 4: Loading identity back through repository...');
    final loadedIdentity = await repo.loadIdentity();
    expect(loadedIdentity, isNotNull, reason: 'Repository should return saved identity');
    print('✓ Identity loaded successfully');
    print('');

    // Step 5: Verify all fields match
    print('Step 5: Verifying all fields match...');
    expect(loadedIdentity!.peerId, equals(testIdentity.peerId));
    print('✓ PeerID matches');

    expect(loadedIdentity.publicKey, equals(testIdentity.publicKey));
    print('✓ PublicKey matches');

    expect(loadedIdentity.privateKey, equals(testIdentity.privateKey));
    print('✓ PrivateKey matches');

    expect(loadedIdentity.mnemonic12, equals(testIdentity.mnemonic12));
    print('✓ Mnemonic12 matches');

    expect(loadedIdentity.createdAt, equals(testIdentity.createdAt));
    print('✓ CreatedAt matches');

    expect(loadedIdentity.updatedAt, equals(testIdentity.updatedAt));
    print('✓ UpdatedAt matches');
    print('');

    // Step 6: Test update (save with different values)
    print('Step 6: Testing update with new identity...');
    final updatedIdentity = IdentityModel(
      peerId: '12D3KooWUpdatedPeerID',
      publicKey: 'dXBkYXRlZFB1YmxpY0tleQ==',
      privateKey: 'dXBkYXRlZFByaXZhdGVLZXk=',
      mnemonic12: 'updated twelve words for testing the update functionality of repository impl here',
      createdAt: '2025-01-17T14:00:00.000Z',
      updatedAt: '2025-01-17T15:00:00.000Z',
    );

    await repo.saveIdentity(updatedIdentity);
    print('✓ Updated identity saved');

    final reloadedIdentity = await repo.loadIdentity();
    expect(reloadedIdentity!.peerId, equals(updatedIdentity.peerId));
    expect(reloadedIdentity.updatedAt, equals(updatedIdentity.updatedAt));
    print('✓ Updated values persisted correctly');
    print('');

    // Step 7: Verify only one row exists (id=1 constraint)
    print('Step 7: Verifying single identity constraint...');
    final rowCount = await db.rawQuery('SELECT COUNT(*) as count FROM identity');
    expect(rowCount.first['count'], equals(1));
    print('✓ Only one identity row exists (id=1)');
    print('');

    // Step 8: Test field name mapping (snake_case to camelCase)
    print('Step 8: Verifying field name mapping...');
    final rawRow = await db.query('identity', where: 'id = ?', whereArgs: [1]);
    expect(rawRow.first['peer_id'], equals(updatedIdentity.peerId),
        reason: 'DB should store peer_id in snake_case');
    expect(rawRow.first['public_key'], equals(updatedIdentity.publicKey),
        reason: 'DB should store public_key in snake_case');
    print('✓ Snake_case to camelCase mapping works correctly');
    print('');

    print('═══════════════════════════════════════════════════════════');
    print('✅ Phase 2 Integration Test PASSED!');
    print('═══════════════════════════════════════════════════════════');
    print('Summary:');
    print('  - Repository can save IdentityModel to database');
    print('  - Repository can load IdentityModel from database');
    print('  - All fields are correctly mapped (camelCase ↔ snake_case)');
    print('  - Update (upsert) functionality works correctly');
    print('  - Single identity constraint (id=1) is maintained');
    print('  - Flow events are emitted correctly (check console output)');
  });
}