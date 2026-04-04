# 42 — Local Backup — Client Side (Flutter App) — TDD Plan

## Overview

Changes to the Flutter app to support:
1. Pairing with the desktop `mknoon-backup` binary
2. Pushing encrypted backups over WiFi (full + incremental)
3. Scheduling background backups (~hourly)
4. Restoring from a backup on a new/reset device

---

## Architecture — New Files

```
lib/
├── core/
│   ├── backup/
│   │   ├── backup_service.dart              # orchestrates full backup flow
│   │   ├── backup_crypto.dart               # encrypt secrets + DB for backup
│   │   ├── backup_manifest.dart             # manifest model + diff
│   │   ├── backup_transfer.dart             # HTTP push to desktop
│   │   ├── backup_scheduler.dart            # background task scheduling
│   │   └── backup_pairing.dart              # pairing state persistence
│   └── local_discovery/
│       └── (existing bonsoir_discovery_service.dart — reuse)
├── features/
│   ├── settings/
│   │   └── presentation/
│   │       └── widgets/
│   │           └── backup_settings_card.dart # settings UI entry point
│   └── backup/
│       ├── application/
│       │   ├── pair_with_desktop_use_case.dart
│       │   ├── push_backup_use_case.dart
│       │   ├── restore_from_backup_use_case.dart
│       │   └── schedule_backup_use_case.dart
│       └── presentation/
│           ├── screens/
│           │   ├── backup_pair_screen.dart     # QR scanner + passphrase
│           │   ├── backup_pair_wired.dart
│           │   ├── backup_status_screen.dart   # shows last backup, paired device
│           │   ├── backup_status_wired.dart
│           │   ├── backup_restore_screen.dart  # QR scanner + passphrase for restore
│           │   └── backup_restore_wired.dart
│           └── widgets/
│               └── backup_progress_indicator.dart

test/
├── core/
│   └── backup/
│       ├── backup_service_test.dart
│       ├── backup_crypto_test.dart
│       ├── backup_manifest_test.dart
│       ├── backup_transfer_test.dart
│       ├── backup_scheduler_test.dart
│       └── backup_pairing_test.dart
├── features/
│   └── backup/
│       ├── application/
│       │   ├── pair_with_desktop_use_case_test.dart
│       │   ├── push_backup_use_case_test.dart
│       │   ├── restore_from_backup_use_case_test.dart
│       │   └── schedule_backup_use_case_test.dart
│       └── presentation/
│           ├── screens/
│           │   ├── backup_pair_screen_test.dart
│           │   ├── backup_status_screen_test.dart
│           │   └── backup_restore_screen_test.dart
│           └── widgets/
│               └── backup_progress_indicator_test.dart
```

---

## Session 1 — Backup Crypto Layer

### 1A. Backup Crypto (backup_crypto.dart)

Encrypts secrets bundle and DB file for transit to desktop.
Uses the shared pairing key (derived from passphrase during pairing).

**Tests (backup_crypto_test.dart):**

```dart
group('BackupCrypto', () {

  test('encryptSecrets roundtrips with correct key', () {
    // Given
    final secrets = BackupSecrets(
      identityPrivateKey: 'ed25519-priv-key-hex',
      mnemonic12: 'word1 word2 ... word12',
      mlKemSecretKey: 'mlkem-secret-base64',
      dbEncryptionKey: 'aabbccdd...64hex',
    );
    final key = Uint8List(32); // test key
    fillRandom(key);

    // When
    final encrypted = BackupCrypto.encryptSecrets(secrets, key);
    final decrypted = BackupCrypto.decryptSecrets(encrypted, key);

    // Then
    expect(decrypted.identityPrivateKey, equals(secrets.identityPrivateKey));
    expect(decrypted.mnemonic12, equals(secrets.mnemonic12));
    expect(decrypted.mlKemSecretKey, equals(secrets.mlKemSecretKey));
    expect(decrypted.dbEncryptionKey, equals(secrets.dbEncryptionKey));
  });

  test('encryptSecrets with wrong key throws', () {
    final secrets = BackupSecrets(...);
    final keyA = randomKey(32);
    final keyB = randomKey(32);

    final encrypted = BackupCrypto.encryptSecrets(secrets, keyA);
    expect(
      () => BackupCrypto.decryptSecrets(encrypted, keyB),
      throwsA(isA<BackupDecryptionError>()),
    );
  });

  test('encryptSecrets output differs each call (random nonce)', () {
    final secrets = BackupSecrets(...);
    final key = randomKey(32);

    final a = BackupCrypto.encryptSecrets(secrets, key);
    final b = BackupCrypto.encryptSecrets(secrets, key);
    expect(a, isNot(equals(b)));
  });

  test('deriveKeyFromPassphrase is deterministic with same salt', () {
    final salt = Uint8List(16);
    final keyA = BackupCrypto.deriveKey('mypassphrase', salt);
    final keyB = BackupCrypto.deriveKey('mypassphrase', salt);
    expect(keyA, equals(keyB));
  });

  test('deriveKeyFromPassphrase differs with different passphrase', () {
    final salt = Uint8List(16);
    final keyA = BackupCrypto.deriveKey('pass1', salt);
    final keyB = BackupCrypto.deriveKey('pass2', salt);
    expect(keyA, isNot(equals(keyB)));
  });

  test('deriveKey output is 32 bytes', () {
    final key = BackupCrypto.deriveKey('pass', Uint8List(16));
    expect(key.length, equals(32));
  });

  test('generateSalt returns 16 random bytes', () {
    final a = BackupCrypto.generateSalt();
    final b = BackupCrypto.generateSalt();
    expect(a.length, equals(16));
    expect(a, isNot(equals(b)));
  });

});
```

**Implementation:**
- `BackupSecrets` data class: 4 fields (private key, mnemonic, ML-KEM secret, DB key)
- `BackupCrypto.encryptSecrets(secrets, key)` → JSON encode → AES-256-GCM (nonce prepended)
- `BackupCrypto.decryptSecrets(ciphertext, key)` → split nonce → GCM open → JSON decode
- `BackupCrypto.deriveKey(passphrase, salt)` → Argon2id (via `cryptography` package or bridge call)
- `BackupCrypto.generateSalt()` → `Random.secure().nextBytes(16)`

**Dependencies:** `pointycastle` or `cryptography` package for Argon2id + AES-GCM.
Alternative: delegate to Go bridge via new commands `backup:derive_key`, `backup:encrypt`, `backup:decrypt` — keeps crypto in Go (consistent with existing pattern).

---

### 1B. Backup Secrets Collection

Collects all secrets from SecureKeyStore into a BackupSecrets object.

**Tests (backup_crypto_test.dart continued):**

```dart
group('collectSecrets', () {

  test('reads all 4 secrets from SecureKeyStore', () async {
    final store = FakeSecureKeyStore();
    await store.write('identity_private_key', 'priv-key');
    await store.write('identity_mnemonic12', 'word1 word2 ...');
    await store.write('identity_ml_kem_secret_key', 'mlkem-secret');
    await store.write('db_encryption_key', 'db-key-hex');

    final secrets = await BackupCrypto.collectSecrets(store);

    expect(secrets.identityPrivateKey, equals('priv-key'));
    expect(secrets.mnemonic12, equals('word1 word2 ...'));
    expect(secrets.mlKemSecretKey, equals('mlkem-secret'));
    expect(secrets.dbEncryptionKey, equals('db-key-hex'));
  });

  test('throws if any secret missing', () async {
    final store = FakeSecureKeyStore();
    // only write 3 of 4
    await store.write('identity_private_key', 'priv-key');
    await store.write('identity_mnemonic12', 'word1 ...');
    await store.write('db_encryption_key', 'db-key-hex');

    expect(
      () => BackupCrypto.collectSecrets(store),
      throwsA(isA<BackupSecretsIncompleteError>()),
    );
  });

});
```

---

## Session 2 — Backup Manifest

### 2A. Manifest Model (backup_manifest.dart)

Tracks files included in a backup for incremental diffing.

**Tests (backup_manifest_test.dart):**

```dart
group('BackupManifest', () {

  test('addEntry and entries roundtrip', () {
    final manifest = BackupManifest();
    manifest.addEntry(ManifestEntry(
      path: 'media/peer1/abc.jpg',
      sha256: 'aabbcc...',
      sizeBytes: 12345,
      modifiedAt: DateTime(2026, 4, 1),
    ));
    expect(manifest.entries.length, equals(1));
    expect(manifest.entries.first.path, equals('media/peer1/abc.jpg'));
  });

  test('toJson / fromJson roundtrip', () {
    final manifest = BackupManifest()
      ..addEntry(ManifestEntry(path: 'a.jpg', sha256: 'aa', sizeBytes: 1, modifiedAt: DateTime(2026)))
      ..addEntry(ManifestEntry(path: 'b.mp4', sha256: 'bb', sizeBytes: 2, modifiedAt: DateTime(2026)));

    final json = manifest.toJson();
    final restored = BackupManifest.fromJson(json);

    expect(restored.entries.length, equals(2));
    expect(restored.entries[0].sha256, equals('aa'));
  });

  test('diff: detects added files', () {
    final prev = BackupManifest()
      ..addEntry(ManifestEntry(path: 'a.jpg', sha256: 'aa', sizeBytes: 1, modifiedAt: DateTime(2026)));
    final curr = BackupManifest()
      ..addEntry(ManifestEntry(path: 'a.jpg', sha256: 'aa', sizeBytes: 1, modifiedAt: DateTime(2026)))
      ..addEntry(ManifestEntry(path: 'b.jpg', sha256: 'bb', sizeBytes: 2, modifiedAt: DateTime(2026)));

    final diff = BackupManifest.diff(prev, curr);
    expect(diff.added, equals(['b.jpg']));
    expect(diff.removed, isEmpty);
    expect(diff.changed, isEmpty);
  });

  test('diff: detects changed files (different hash)', () {
    final prev = BackupManifest()
      ..addEntry(ManifestEntry(path: 'a.jpg', sha256: 'aa', sizeBytes: 1, modifiedAt: DateTime(2026)));
    final curr = BackupManifest()
      ..addEntry(ManifestEntry(path: 'a.jpg', sha256: 'xx', sizeBytes: 1, modifiedAt: DateTime(2026)));

    final diff = BackupManifest.diff(prev, curr);
    expect(diff.changed, equals(['a.jpg']));
  });

  test('diff: detects removed files', () {
    final prev = BackupManifest()
      ..addEntry(ManifestEntry(path: 'a.jpg', sha256: 'aa', sizeBytes: 1, modifiedAt: DateTime(2026)))
      ..addEntry(ManifestEntry(path: 'b.jpg', sha256: 'bb', sizeBytes: 2, modifiedAt: DateTime(2026)));
    final curr = BackupManifest()
      ..addEntry(ManifestEntry(path: 'a.jpg', sha256: 'aa', sizeBytes: 1, modifiedAt: DateTime(2026)));

    final diff = BackupManifest.diff(prev, curr);
    expect(diff.removed, equals(['b.jpg']));
  });

  test('diff: no changes returns empty diff', () {
    final m = BackupManifest()
      ..addEntry(ManifestEntry(path: 'a.jpg', sha256: 'aa', sizeBytes: 1, modifiedAt: DateTime(2026)));

    final diff = BackupManifest.diff(m, m);
    expect(diff.added, isEmpty);
    expect(diff.removed, isEmpty);
    expect(diff.changed, isEmpty);
  });

  test('buildFromDirectory hashes all files', () async {
    // Given a temp directory with 3 test files
    final dir = await createTempMediaDir({'a.jpg': [1,2,3], 'b.mp4': [4,5]});

    final manifest = await BackupManifest.buildFromDirectory(dir.path);

    expect(manifest.entries.length, equals(2));
    expect(manifest.entries.every((e) => e.sha256.isNotEmpty), isTrue);
  });

  test('database and secrets entries always marked as changed', () {
    final prev = BackupManifest()
      ..addEntry(ManifestEntry(path: 'database.db', sha256: 'same', sizeBytes: 1, modifiedAt: DateTime(2026)));
    final curr = BackupManifest()
      ..addEntry(ManifestEntry(path: 'database.db', sha256: 'same', sizeBytes: 1, modifiedAt: DateTime(2026)));

    final diff = BackupManifest.diff(prev, curr, alwaysSend: ['database.db', 'secrets.json']);
    expect(diff.changed, contains('database.db'));
  });

});
```

---

## Session 3 — Pairing

### 3A. Backup Pairing State (backup_pairing.dart)

Persists pairing info (desktop IP, shared key, device name) in SecureKeyStore.

**Tests (backup_pairing_test.dart):**

```dart
group('BackupPairing', () {

  test('savePairing persists to SecureKeyStore', () async {
    final store = FakeSecureKeyStore();
    final pairing = BackupPairingStore(secureKeyStore: store);

    await pairing.save(BackupPairingState(
      desktopDeviceName: 'My MacBook',
      sharedKeyBase64: 'base64encodedkey==',
      salt: 'base64salt==',
      pairedAt: DateTime(2026, 4, 2),
    ));

    expect(await store.containsKey('backup_pairing_state'), isTrue);
  });

  test('loadPairing roundtrips', () async {
    final store = FakeSecureKeyStore();
    final pairing = BackupPairingStore(secureKeyStore: store);
    final state = BackupPairingState(
      desktopDeviceName: 'My MacBook',
      sharedKeyBase64: 'key==',
      salt: 'salt==',
      pairedAt: DateTime(2026, 4, 2),
    );

    await pairing.save(state);
    final loaded = await pairing.load();

    expect(loaded, isNotNull);
    expect(loaded!.desktopDeviceName, equals('My MacBook'));
    expect(loaded.sharedKeyBase64, equals('key=='));
  });

  test('loadPairing returns null when not paired', () async {
    final store = FakeSecureKeyStore();
    final pairing = BackupPairingStore(secureKeyStore: store);

    expect(await pairing.load(), isNull);
  });

  test('deletePairing clears state', () async {
    final store = FakeSecureKeyStore();
    final pairing = BackupPairingStore(secureKeyStore: store);
    await pairing.save(BackupPairingState(...));

    await pairing.delete();

    expect(await pairing.load(), isNull);
  });

  test('isPaired returns true after save', () async {
    final store = FakeSecureKeyStore();
    final pairing = BackupPairingStore(secureKeyStore: store);

    expect(await pairing.isPaired(), isFalse);
    await pairing.save(BackupPairingState(...));
    expect(await pairing.isPaired(), isTrue);
  });

  test('updateLastBackupTime', () async {
    final store = FakeSecureKeyStore();
    final pairing = BackupPairingStore(secureKeyStore: store);
    await pairing.save(BackupPairingState(
      ..., lastBackupAt: null,
    ));

    final now = DateTime(2026, 4, 2, 14, 30);
    await pairing.updateLastBackupTime(now);

    final loaded = await pairing.load();
    expect(loaded!.lastBackupAt, equals(now));
  });

});
```

---

### 3B. Pair With Desktop Use Case (pair_with_desktop_use_case.dart)

Orchestrates: scan QR → parse payload → derive shared key → complete pairing via HTTP → persist.

**Tests (pair_with_desktop_use_case_test.dart):**

```dart
group('pairWithDesktop', () {

  test('parses QR payload correctly', () {
    final qrData = '{"ip":"192.168.1.42","port":8470,'
        '"sessionPubKey":"base64...","deviceName":"MacBook"}';

    final payload = PairingQRPayload.fromJson(jsonDecode(qrData));

    expect(payload.ip, equals('192.168.1.42'));
    expect(payload.port, equals(8470));
    expect(payload.deviceName, equals('MacBook'));
    expect(payload.sessionPubKey, isNotEmpty);
  });

  test('completes pairing with valid passphrase', () async {
    // Given: mock HTTP server simulating desktop
    final mockDesktop = await startMockDesktopServer();
    final store = FakeSecureKeyStore();
    final pairingStore = BackupPairingStore(secureKeyStore: store);

    // When
    await pairWithDesktop(
      qrPayload: PairingQRPayload(
        ip: 'localhost',
        port: mockDesktop.port,
        sessionPubKey: mockDesktop.sessionPubKey,
        deviceName: 'Test Desktop',
      ),
      passphrase: 'correct horse battery staple',
      pairingStore: pairingStore,
    );

    // Then
    expect(await pairingStore.isPaired(), isTrue);
    final state = await pairingStore.load();
    expect(state!.desktopDeviceName, equals('Test Desktop'));

    await mockDesktop.close();
  });

  test('rejects empty passphrase', () async {
    expect(
      () => pairWithDesktop(
        qrPayload: PairingQRPayload(...),
        passphrase: '',
        pairingStore: BackupPairingStore(...),
      ),
      throwsA(isA<BackupPairingError>()),
    );
  });

  test('reports error when desktop unreachable', () async {
    expect(
      () => pairWithDesktop(
        qrPayload: PairingQRPayload(ip: '192.168.1.99', port: 9999, ...),
        passphrase: 'pass',
        pairingStore: BackupPairingStore(...),
      ),
      throwsA(isA<BackupPairingError>()),
    );
  });

  test('reports error when desktop rejects passphrase proof', () async {
    final mockDesktop = await startMockDesktopServer(rejectPairing: true);

    expect(
      () => pairWithDesktop(
        qrPayload: PairingQRPayload(ip: 'localhost', port: mockDesktop.port, ...),
        passphrase: 'wrong-pass',
        pairingStore: BackupPairingStore(...),
      ),
      throwsA(isA<BackupPairingError>()),
    );

    await mockDesktop.close();
  });

});
```

---

## Session 4 — Backup Transfer

### 4A. HTTP Push to Desktop (backup_transfer.dart)

Sends encrypted backup files to the desktop over local network HTTP.

**Tests (backup_transfer_test.dart):**

```dart
group('BackupTransfer', () {

  test('pushBackup sends multipart POST to desktop', () async {
    final mockServer = await startMockBackupReceiver();
    final transfer = BackupTransfer();

    await transfer.push(
      desktopUrl: 'http://localhost:${mockServer.port}',
      authToken: 'valid-token',
      manifest: BackupManifest()..addEntry(...),
      files: {
        'secrets.enc': Uint8List.fromList([1, 2, 3]),
        'database.db.enc': Uint8List.fromList([4, 5, 6]),
      },
      mediaFiles: {'media/p1/a.jpg.enc': File(tempPath)},
    );

    expect(mockServer.receivedManifest, isNotNull);
    expect(mockServer.receivedFiles.keys, containsAll([
      'secrets.enc', 'database.db.enc', 'media/p1/a.jpg.enc',
    ]));

    await mockServer.close();
  });

  test('pushBackup streams large files without loading into memory', () async {
    // Given: a 100 MB temp file
    final bigFile = await createTempFile(sizeBytes: 100 * 1024 * 1024);
    final mockServer = await startMockBackupReceiver();
    final transfer = BackupTransfer();

    // When + Then: should not OOM
    await transfer.push(
      desktopUrl: 'http://localhost:${mockServer.port}',
      authToken: 'token',
      manifest: BackupManifest()..addEntry(...),
      files: {},
      mediaFiles: {'media/p1/big.mp4.enc': bigFile},
    );

    expect(mockServer.receivedFiles['media/p1/big.mp4.enc']?.length,
        equals(100 * 1024 * 1024));

    await mockServer.close();
    await bigFile.delete();
  });

  test('pushBackup reports progress via callback', () async {
    final mockServer = await startMockBackupReceiver();
    final progress = <BackupProgress>[];

    await BackupTransfer().push(
      desktopUrl: 'http://localhost:${mockServer.port}',
      authToken: 'token',
      manifest: BackupManifest()..addEntry(...)..addEntry(...),
      files: {'a': Uint8List(100), 'b': Uint8List(200)},
      mediaFiles: {},
      onProgress: progress.add,
    );

    expect(progress.last.filesCompleted, equals(2));
    expect(progress.last.isComplete, isTrue);

    await mockServer.close();
  });

  test('pushBackup retries on transient network failure', () async {
    final mockServer = await startMockBackupReceiver(failFirstN: 2);

    await BackupTransfer(maxRetries: 3).push(
      desktopUrl: 'http://localhost:${mockServer.port}',
      authToken: 'token',
      manifest: BackupManifest()..addEntry(...),
      files: {'a': Uint8List(10)},
      mediaFiles: {},
    );

    expect(mockServer.requestCount, equals(3)); // 2 failures + 1 success
    await mockServer.close();
  });

  test('pushBackup throws after max retries exhausted', () async {
    final mockServer = await startMockBackupReceiver(failFirstN: 100);

    expect(
      () => BackupTransfer(maxRetries: 3).push(
        desktopUrl: 'http://localhost:${mockServer.port}',
        authToken: 'token',
        manifest: BackupManifest()..addEntry(...),
        files: {'a': Uint8List(10)},
        mediaFiles: {},
      ),
      throwsA(isA<BackupTransferError>()),
    );

    await mockServer.close();
  });

  test('generateAuthToken creates valid HMAC from shared key', () {
    final key = Uint8List(32);
    final token = BackupTransfer.generateAuthToken(key);
    expect(token, isNotEmpty);
    expect(BackupTransfer.verifyAuthToken(key, token), isTrue);
  });

  test('generateAuthToken with different key fails verification', () {
    final keyA = randomBytes(32);
    final keyB = randomBytes(32);
    final token = BackupTransfer.generateAuthToken(keyA);
    expect(BackupTransfer.verifyAuthToken(keyB, token), isFalse);
  });

});
```

---

## Session 5 — Backup Service (Orchestrator)

### 5A. Backup Service (backup_service.dart)

Top-level orchestrator: collect data → build manifest → encrypt → transfer.

**Tests (backup_service_test.dart):**

```dart
group('BackupService', () {

  test('performBackup collects secrets, DB, and media', () async {
    // Given
    final secureKeyStore = FakeSecureKeyStore();
    await secureKeyStore.write('identity_private_key', 'pk');
    await secureKeyStore.write('identity_mnemonic12', 'w1 w2 ...');
    await secureKeyStore.write('identity_ml_kem_secret_key', 'mlk');
    await secureKeyStore.write('db_encryption_key', 'dbk');

    final db = await openTestDatabase(); // in-memory with test data
    final mediaDir = await createTempMediaDir({
      'media/peer1/a.jpg': [1, 2, 3],
      'media/peer1/b.mp4': [4, 5, 6],
    });

    final mockServer = await startMockBackupReceiver();
    final pairingStore = BackupPairingStore(secureKeyStore: secureKeyStore);
    await pairingStore.save(BackupPairingState(
      sharedKeyBase64: base64Encode(randomBytes(32)),
      desktopDeviceName: 'Test',
      salt: base64Encode(randomBytes(16)),
      pairedAt: DateTime.now(),
    ));

    final service = BackupService(
      secureKeyStore: secureKeyStore,
      dbPath: db.path,
      mediaBaseDir: mediaDir.path,
      pairingStore: pairingStore,
      desktopUrl: 'http://localhost:${mockServer.port}',
    );

    // When
    await service.performBackup();

    // Then
    expect(mockServer.receivedFiles.containsKey('secrets.enc'), isTrue);
    expect(mockServer.receivedFiles.containsKey('database.db.enc'), isTrue);
    expect(mockServer.receivedFiles.containsKey('media/peer1/a.jpg'), isTrue);
    expect(mockServer.receivedFiles.containsKey('media/peer1/b.mp4'), isTrue);

    await mockServer.close();
  });

  test('performBackup skips when not paired', () async {
    final store = FakeSecureKeyStore();
    final pairingStore = BackupPairingStore(secureKeyStore: store);
    final service = BackupService(pairingStore: pairingStore, ...);

    final result = await service.performBackup();

    expect(result, equals(BackupResult.notPaired));
  });

  test('performBackup skips when desktop not reachable on network', () async {
    final store = FakeSecureKeyStore();
    final pairingStore = BackupPairingStore(secureKeyStore: store);
    await pairingStore.save(BackupPairingState(...));

    final service = BackupService(
      pairingStore: pairingStore,
      desktopUrl: 'http://192.168.1.99:9999', // unreachable
      ...
    );

    final result = await service.performBackup();

    expect(result, equals(BackupResult.desktopUnreachable));
  });

  test('performBackup uses mDNS to discover desktop IP', () async {
    final discoveredUrl = <String>[];
    final service = BackupService(
      discoveryService: FakeBackupDiscovery(
        services: [BackupServiceInfo(ip: '192.168.1.42', port: 8470)],
      ),
      ...
    );

    // Discovery should find the desktop without a hardcoded URL
    await service.performBackup();
    // ... assert discovery was called
  });

  test('performBackup does incremental after first full backup', () async {
    final store = FakeSecureKeyStore();
    final pairingStore = BackupPairingStore(secureKeyStore: store);
    await pairingStore.save(BackupPairingState(..., lastManifestJson: '...'));

    final mockServer = await startMockBackupReceiver();
    final service = BackupService(
      pairingStore: pairingStore,
      desktopUrl: 'http://localhost:${mockServer.port}',
      ...
    );

    // Add one new media file since last manifest
    await addMediaFile('media/peer1/new.jpg', [7, 8, 9]);

    await service.performBackup();

    // Only new file + DB + secrets should be sent
    // (not the old media files)
    expect(mockServer.receivedFiles.keys, containsAll([
      'secrets.enc', 'database.db.enc', 'media/peer1/new.jpg',
    ]));
    expect(mockServer.receivedFiles.keys, isNot(contains('media/peer1/a.jpg')));

    await mockServer.close();
  });

  test('performBackup updates lastBackupAt on success', () async {
    final mockServer = await startMockBackupReceiver();
    final pairingStore = BackupPairingStore(...);
    await pairingStore.save(BackupPairingState(lastBackupAt: null, ...));

    final service = BackupService(
      pairingStore: pairingStore,
      desktopUrl: 'http://localhost:${mockServer.port}',
      ...
    );

    await service.performBackup();

    final state = await pairingStore.load();
    expect(state!.lastBackupAt, isNotNull);

    await mockServer.close();
  });

  test('performBackup emits FLOW event', () async {
    final events = <String>[];
    final service = BackupService(
      onFlowEvent: events.add,
      ...
    );

    await service.performBackup();

    expect(events, contains(contains('backup:push')));
  });

});
```

---

## Session 6 — mDNS Discovery for Desktop

### 6A. Discover Desktop Backup Service

Reuse existing Bonsoir infrastructure, new service type `_mknoon-backup._tcp`.

**Tests (in backup_service_test.dart or separate):**

```dart
group('BackupDiscovery', () {

  test('discovers _mknoon-backup._tcp service', () async {
    // This is an integration test — requires real mDNS
    // For unit tests, use FakeBackupDiscovery
    final fake = FakeBackupDiscovery(
      services: [
        BackupServiceInfo(ip: '192.168.1.42', port: 8470, deviceName: 'MacBook'),
      ],
    );

    final found = await fake.discover(timeout: Duration(seconds: 2));

    expect(found.length, equals(1));
    expect(found.first.ip, equals('192.168.1.42'));
    expect(found.first.deviceName, equals('MacBook'));
  });

  test('returns empty list when no desktop found', () async {
    final fake = FakeBackupDiscovery(services: []);

    final found = await fake.discover(timeout: Duration(seconds: 1));

    expect(found, isEmpty);
  });

  test('filters to only paired desktop by device ID', () async {
    final fake = FakeBackupDiscovery(services: [
      BackupServiceInfo(ip: '192.168.1.42', port: 8470, deviceId: 'AAAA'),
      BackupServiceInfo(ip: '192.168.1.43', port: 8470, deviceId: 'BBBB'),
    ]);

    final found = await fake.discoverPaired(
      pairedDeviceId: 'AAAA',
      timeout: Duration(seconds: 2),
    );

    expect(found.length, equals(1));
    expect(found.first.ip, equals('192.168.1.42'));
  });

});
```

---

## Session 7 — Background Scheduling

### 7A. Backup Scheduler (backup_scheduler.dart)

Platform-specific background task registration.

**Tests (backup_scheduler_test.dart):**

```dart
group('BackupScheduler', () {

  test('schedulePeriodicBackup registers task', () async {
    final scheduler = FakeBackupScheduler();

    await scheduler.schedulePeriodicBackup(
      interval: Duration(hours: 1),
    );

    expect(scheduler.isScheduled, isTrue);
    expect(scheduler.scheduledInterval, equals(Duration(hours: 1)));
  });

  test('cancelPeriodicBackup unregisters task', () async {
    final scheduler = FakeBackupScheduler();
    await scheduler.schedulePeriodicBackup(interval: Duration(hours: 1));

    await scheduler.cancelPeriodicBackup();

    expect(scheduler.isScheduled, isFalse);
  });

  test('onTrigger calls BackupService.performBackup', () async {
    var backupCalled = false;
    final scheduler = FakeBackupScheduler(
      onTrigger: () async { backupCalled = true; },
    );

    await scheduler.simulateTrigger();

    expect(backupCalled, isTrue);
  });

  test('schedulePeriodicBackup is idempotent', () async {
    final scheduler = FakeBackupScheduler();
    await scheduler.schedulePeriodicBackup(interval: Duration(hours: 1));
    await scheduler.schedulePeriodicBackup(interval: Duration(hours: 1));

    expect(scheduler.registrationCount, equals(1)); // not 2
  });

});
```

**Implementation (platform-specific):**
- **iOS:** `BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.mknoon.backup")` + `BGAppRefreshTaskRequest` with `earliestBeginDate` = 1 hour. Requires `Info.plist` entry for `BGTaskSchedulerPermittedIdentifiers`.
- **Android:** `workmanager` package → `Workmanager().registerPeriodicTask("backup", "com.mknoon.backup", frequency: Duration(hours: 1))`.
- **Both:** Also trigger backup on `AppLifecycleState.resumed` (guaranteed sync point).

**New native code:**
- `ios/Runner/AppDelegate.swift`: register BGTask handler that calls back into Dart via isolate
- `android/app/src/main/kotlin/.../BackupWorker.kt`: WorkManager worker
- Or use `workmanager` Flutter package (wraps both platforms)

---

## Session 8 — Restore Flow

### 8A. Restore From Backup Use Case (restore_from_backup_use_case.dart)

New phone: enter passphrase → scan QR from laptop → download + decrypt backup → restore.

**Tests (restore_from_backup_use_case_test.dart):**

```dart
group('restoreFromBackup', () {

  test('parses restore QR payload', () {
    final qrData = '{"ip":"192.168.1.42","port":8470,'
        '"sessionToken":"abc123","snapshotId":"latest"}';

    final payload = RestoreQRPayload.fromJson(jsonDecode(qrData));

    expect(payload.ip, equals('192.168.1.42'));
    expect(payload.sessionToken, equals('abc123'));
  });

  test('downloads and restores full backup', () async {
    // Given: mock desktop serving a backup
    final mockDesktop = await startMockRestoreServer(
      manifest: testManifest,
      files: {
        'secrets.enc': encryptedSecrets,
        'database.db.enc': encryptedDb,
        'media/p1/a.jpg': encryptedMediaA,
      },
    );
    final store = FakeSecureKeyStore();
    final tempDir = await Directory.systemTemp.createTemp('restore_test');

    // When
    await restoreFromBackup(
      restorePayload: RestoreQRPayload(
        ip: 'localhost', port: mockDesktop.port,
        sessionToken: 'tok', snapshotId: 'latest',
      ),
      passphrase: 'correct horse battery staple',
      secureKeyStore: store,
      restoreDir: tempDir.path,
    );

    // Then — secrets restored to SecureKeyStore
    expect(await store.read('identity_private_key'), equals('pk'));
    expect(await store.read('identity_mnemonic12'), equals('w1 w2 ...'));
    expect(await store.read('identity_ml_kem_secret_key'), equals('mlk'));
    expect(await store.read('db_encryption_key'), equals('dbk'));

    // Then — DB file placed correctly
    expect(File('${tempDir.path}/identity.db').existsSync(), isTrue);

    // Then — media files placed correctly
    expect(File('${tempDir.path}/media/p1/a.jpg').existsSync(), isTrue);

    await mockDesktop.close();
  });

  test('wrong passphrase fails decryption', () async {
    final mockDesktop = await startMockRestoreServer(...);

    expect(
      () => restoreFromBackup(
        restorePayload: RestoreQRPayload(
          ip: 'localhost', port: mockDesktop.port, ...
        ),
        passphrase: 'wrong-passphrase',
        secureKeyStore: FakeSecureKeyStore(),
        restoreDir: '/tmp/test',
      ),
      throwsA(isA<BackupDecryptionError>()),
    );

    await mockDesktop.close();
  });

  test('reports download progress', () async {
    final mockDesktop = await startMockRestoreServer(...);
    final progress = <RestoreProgress>[];

    await restoreFromBackup(
      ...,
      onProgress: progress.add,
    );

    expect(progress.last.isComplete, isTrue);
    expect(progress.last.filesDownloaded, greaterThan(0));

    await mockDesktop.close();
  });

  test('handles network interruption mid-restore', () async {
    final mockDesktop = await startMockRestoreServer(dropAfterFiles: 1);

    expect(
      () => restoreFromBackup(...),
      throwsA(isA<BackupTransferError>()),
    );

    // Partial files should be cleaned up
    expect(Directory('/tmp/test/media').listSync(), isEmpty);

    await mockDesktop.close();
  });

  test('restore completes pairing handshake with desktop', () async {
    // After restore, the new phone should re-pair with the desktop
    final mockDesktop = await startMockRestoreServer(...);

    await restoreFromBackup(...);

    expect(mockDesktop.receivedRestoreComplete, isTrue);
    await mockDesktop.close();
  });

});
```

---

## Session 9 — Startup Router Changes

### 9A. Restore Option on Welcome Screen

When a fresh app launches (no identity), show "Restore from backup" alongside
"Create new identity" and "Restore from mnemonic".

**Tests (startup_router adjustments):**

```dart
group('StartupRouter — restore from backup option', () {

  test('shows restore-from-backup button when no identity', () async {
    await tester.pumpWidget(buildStartupRouter(identity: null));

    expect(find.text('Restore from backup'), findsOneWidget);
  });

  test('tapping restore-from-backup navigates to backup_restore_screen', () async {
    await tester.pumpWidget(buildStartupRouter(identity: null));
    await tester.tap(find.text('Restore from backup'));
    await tester.pumpAndSettle();

    expect(find.byType(BackupRestoreScreen), findsOneWidget);
  });

  test('does not show restore-from-backup when identity exists', () async {
    await tester.pumpWidget(buildStartupRouter(identity: existingIdentity));

    expect(find.text('Restore from backup'), findsNothing);
  });

});
```

---

## Session 10 — Settings UI

### 10A. Backup Settings Card (backup_settings_card.dart)

Entry point in Settings screen for managing backup.

**Tests (in settings or backup presentation tests):**

```dart
group('BackupSettingsCard', () {

  test('shows "Set up backup" when not paired', () async {
    await tester.pumpWidget(buildBackupSettingsCard(isPaired: false));

    expect(find.text('Set up backup'), findsOneWidget);
    expect(find.text('Last backup'), findsNothing);
  });

  test('shows paired status and last backup time when paired', () async {
    await tester.pumpWidget(buildBackupSettingsCard(
      isPaired: true,
      desktopName: 'My MacBook',
      lastBackup: DateTime(2026, 4, 2, 14, 30),
    ));

    expect(find.text('My MacBook'), findsOneWidget);
    expect(find.textContaining('14:30'), findsOneWidget);
  });

  test('tapping "Set up backup" navigates to pair screen', () async {
    await tester.pumpWidget(buildBackupSettingsCard(isPaired: false));
    await tester.tap(find.text('Set up backup'));
    await tester.pumpAndSettle();

    expect(find.byType(BackupPairScreen), findsOneWidget);
  });

  test('tapping "Back up now" triggers immediate backup', () async {
    var backupTriggered = false;
    await tester.pumpWidget(buildBackupSettingsCard(
      isPaired: true,
      onBackupNow: () { backupTriggered = true; },
    ));

    await tester.tap(find.text('Back up now'));
    expect(backupTriggered, isTrue);
  });

  test('shows backup progress during active backup', () async {
    await tester.pumpWidget(buildBackupSettingsCard(
      isPaired: true,
      backupInProgress: true,
      progress: BackupProgress(bytesTransferred: 50, totalBytes: 100),
    ));

    expect(find.byType(BackupProgressIndicator), findsOneWidget);
  });

  test('shows "Unpair" option', () async {
    await tester.pumpWidget(buildBackupSettingsCard(isPaired: true));

    expect(find.text('Unpair'), findsOneWidget);
  });

});
```

---

### 10B. Backup Pair Screen (backup_pair_screen.dart)

QR scanner → passphrase input → pairing handshake.

**Tests (backup_pair_screen_test.dart):**

```dart
group('BackupPairScreen', () {

  test('shows passphrase input first', () async {
    await tester.pumpWidget(buildBackupPairScreen());

    expect(find.text('Enter a backup passphrase'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  test('enables scan button only with passphrase ≥ 8 chars', () async {
    await tester.pumpWidget(buildBackupPairScreen());

    // Too short
    await tester.enterText(find.byType(TextField), 'short');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.text('Scan QR')).enabled, isFalse);

    // Long enough
    await tester.enterText(find.byType(TextField), 'long enough passphrase');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.text('Scan QR')).enabled, isTrue);
  });

  test('shows QR scanner after passphrase confirmed', () async {
    await tester.pumpWidget(buildBackupPairScreen());
    await tester.enterText(find.byType(TextField), 'my backup passphrase');
    await tester.tap(find.text('Scan QR'));
    await tester.pumpAndSettle();

    expect(find.byType(MobileScanner), findsOneWidget);
  });

  test('shows success state after pairing completes', () async {
    await tester.pumpWidget(buildBackupPairScreen(
      pairUseCase: FakePairUseCase(succeeds: true),
    ));

    // Simulate full flow: passphrase → scan → success
    await simulateFullPairingFlow(tester);

    expect(find.text('Paired'), findsOneWidget);
  });

  test('shows error on pairing failure', () async {
    await tester.pumpWidget(buildBackupPairScreen(
      pairUseCase: FakePairUseCase(succeeds: false),
    ));

    await simulateFullPairingFlow(tester);

    expect(find.textContaining('Failed'), findsOneWidget);
  });

});
```

---

### 10C. Backup Restore Screen (backup_restore_screen.dart)

For new phone: passphrase → scan QR from laptop → download → progress → done.

**Tests (backup_restore_screen_test.dart):**

```dart
group('BackupRestoreScreen', () {

  test('shows passphrase input', () async {
    await tester.pumpWidget(buildBackupRestoreScreen());

    expect(find.text('Enter your backup passphrase'), findsOneWidget);
  });

  test('shows QR scanner after passphrase entered', () async {
    await tester.pumpWidget(buildBackupRestoreScreen());
    await tester.enterText(find.byType(TextField), 'my passphrase');
    await tester.tap(find.text('Scan QR'));
    await tester.pumpAndSettle();

    expect(find.byType(MobileScanner), findsOneWidget);
  });

  test('shows download progress', () async {
    await tester.pumpWidget(buildBackupRestoreScreen(
      restoreState: RestoreState.downloading,
      progress: RestoreProgress(filesDownloaded: 3, totalFiles: 10),
    ));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('3 / 10'), findsOneWidget);
  });

  test('shows success and navigates to feed', () async {
    await tester.pumpWidget(buildBackupRestoreScreen(
      restoreState: RestoreState.complete,
    ));

    expect(find.text('Restored'), findsOneWidget);
    // After delay or tap, navigates to main app
  });

  test('shows error with retry option on failure', () async {
    await tester.pumpWidget(buildBackupRestoreScreen(
      restoreState: RestoreState.failed,
      error: 'Wrong passphrase',
    ));

    expect(find.textContaining('Wrong passphrase'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

});
```

---

## Session 11 — DI Chain + Lifecycle Integration

### 11A. Wire BackupService into main.dart

**Changes:**
- Construct `BackupPairingStore(secureKeyStore: secureKeyStore)` after SecureKeyStore
- Construct `BackupService(...)` after all DB + media deps are ready
- Pass `BackupService` into `MyApp` → `SettingsScreen`
- Schedule backup on `AppLifecycleState.resumed`

**Tests (app lifecycle integration):**

```dart
group('Backup lifecycle integration', () {

  test('backup triggered on app resume when paired', () async {
    var backupTriggered = false;
    final service = FakeBackupService(
      onPerformBackup: () { backupTriggered = true; },
    );

    // Simulate resume
    await handleAppResumed(backupService: service);

    expect(backupTriggered, isTrue);
  });

  test('backup NOT triggered on resume when not paired', () async {
    var backupTriggered = false;
    final service = FakeBackupService(
      paired: false,
      onPerformBackup: () { backupTriggered = true; },
    );

    await handleAppResumed(backupService: service);

    expect(backupTriggered, isFalse);
  });

  test('backup runs in background without blocking resume', () async {
    // Backup should be fire-and-forget during resume
    final service = FakeBackupService(
      delay: Duration(seconds: 5), // simulate slow backup
    );

    final stopwatch = Stopwatch()..start();
    await handleAppResumed(backupService: service);
    stopwatch.stop();

    // Resume should return immediately, not wait 5 seconds
    expect(stopwatch.elapsedMilliseconds, lessThan(500));
  });

});
```

---

## Session 12 — Localization

### 12A. Add backup-related strings to ARB files

**Strings needed:**
```
backupSettingsTitle: "Backup"
backupSetUp: "Set up backup"
backupPaired: "Paired with {deviceName}"
backupLastBackup: "Last backup: {time}"
backupNow: "Back up now"
backupUnpair: "Unpair"
backupPassphraseHint: "Enter a backup passphrase"
backupPassphraseMinLength: "At least 8 characters"
backupScanQR: "Scan QR on your computer"
backupPairing: "Pairing..."
backupPaired: "Paired"
backupFailed: "Pairing failed"
backupInProgress: "Backing up..."
backupComplete: "Backup complete"
restoreTitle: "Restore from backup"
restorePassphraseHint: "Enter your backup passphrase"
restoreScanQR: "Scan QR on your computer"
restoreDownloading: "Downloading backup..."
restoreProgress: "{current} / {total} files"
restoreComplete: "Restored"
restoreFailed: "Restore failed"
restoreWrongPassphrase: "Wrong passphrase — try again"
restoreTryAgain: "Try again"
```

**Tests:** Existing l10n test infrastructure covers presence of keys in all ARB files.

---

## Implementation Order (Recommended)

| Session | What | Depends on |
|---------|------|------------|
| 1 | Crypto layer (encrypt/decrypt secrets, key derivation) | Nothing |
| 2 | Manifest model + diff | Nothing |
| 3 | Pairing state persistence | Session 1 (uses crypto for key storage) |
| 4 | HTTP transfer (push backup to desktop) | Session 1, 2 |
| 5 | Backup service orchestrator | Session 1, 2, 3, 4 |
| 6 | mDNS discovery for desktop | Nothing (uses existing Bonsoir) |
| 7 | Background scheduling (BGTask/WorkManager) | Session 5 |
| 8 | Restore flow (download from desktop) | Session 1 |
| 9 | Startup router (restore option) | Session 8 |
| 10 | Settings UI (pair, status, backup now) | Session 3, 5 |
| 11 | DI chain + lifecycle wiring | Session 5, 6, 7 |
| 12 | Localization | Session 10 |

---

## New Dependencies

| Package | Purpose | Notes |
|---------|---------|-------|
| `workmanager` | Background task scheduling (iOS BGTask + Android WorkManager) | Wraps both platforms |
| `pointycastle` or `cryptography` | Argon2id + AES-GCM in Dart | OR delegate all crypto to Go bridge |
| `http` | HTTP client for pushing backups | Already in pubspec as dep |

**Recommended:** Delegate Argon2id + AES-GCM to the Go bridge (new commands `backup:derive_key`, `backup:encrypt_file`, `backup:decrypt_file`). Keeps all crypto in Go, consistent with existing pattern. Avoids adding a new Dart crypto package.
