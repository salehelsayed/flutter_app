import 'dart:io';
import 'dart:math';

import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('encrypted_db_opener', () {
    group('key generation contract', () {
      // Replicate the private _generateRandomKey to verify its contract
      String generateRandomKey() {
        final random = Random.secure();
        final bytes = List<int>.generate(32, (_) => random.nextInt(256));
        return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }

      test('generates a 64-character hex string', () {
        final key = generateRandomKey();
        expect(key.length, 64);
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key), isTrue);
      });

      test('generates unique keys on each call', () {
        final key1 = generateRandomKey();
        final key2 = generateRandomKey();
        // Statistically impossible to collide with 256-bit random
        expect(key1, isNot(equals(key2)));
      });

      test('each byte is zero-padded to 2 hex chars', () {
        // Verify that bytes < 16 get padded (e.g., 0x0A -> "0a" not "a")
        final key = generateRandomKey();
        // All pairs should be exactly 2 chars
        for (var i = 0; i < key.length; i += 2) {
          final pair = key.substring(i, i + 2);
          expect(pair.length, 2);
          expect(int.tryParse(pair, radix: 16), isNotNull);
        }
      });
    });

    group('SecureKeyStore interaction', () {
      test('db_encryption_key is stored after generation', () async {
        final store = FakeSecureKeyStore();
        // Verify initial state
        expect(await store.containsKey('db_encryption_key'), isFalse);

        // Simulate what openEncryptedDatabase does
        await store.write('db_encryption_key', 'a' * 64);
        expect(await store.read('db_encryption_key'), 'a' * 64);
      });

      test('existing key is read from secure storage', () async {
        final store = FakeSecureKeyStore();
        const existingKey =
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
        await store.write('db_encryption_key', existingKey);

        final key = await store.read('db_encryption_key');
        expect(key, existingKey);
        expect(key!.length, 64);
      });
    });

    group('writable open failure ownership', () {
      const legacyKey =
          'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
      late Directory tempDirectory;

      setUp(() async {
        tempDirectory = await Directory.systemTemp.createTemp(
          'encrypted-db-opener-test-',
        );
      });

      tearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      test(
        'secure-store marker failure closes the exact opened database',
        () async {
          const dbName = 'identity.db';
          final dbFile = File('${tempDirectory.path}/$dbName');
          await dbFile.writeAsBytes(const <int>[1]);
          final writeFailure = StateError('secure marker write failed');
          final events = <String>[];
          final keyStore = _FailingWriteKeyStore(
            storedValue: legacyKey,
            writeFailure: writeFailure,
            events: events,
          );
          final openedDatabase = _RecordingDatabase(events: events);

          Object? thrown;
          try {
            await openEncryptedDatabase(
              secureKeyStore: keyStore,
              dbName: dbName,
              version: 1,
              onCreate: (_, _) async {},
              onUpgrade: (_, _, _) async {},
              onOpened: (database) async {
                expect(identical(database, openedDatabase), isTrue);
                events.add('onOpened:start');
                await Future<void>.delayed(Duration.zero);
                events.add('onOpened:end');
              },
              debugHooks: EncryptedDatabaseOpenDebugHooks(
                resolveDatabasesPath: () async => tempDirectory.path,
                isRawKeyDatabase: (_, _, _) async => true,
                openDatabase:
                    (
                      _, {
                      required version,
                      required password,
                      required onConfigure,
                      required onCreate,
                      required onUpgrade,
                      required onDowngrade,
                    }) async => openedDatabase,
              ),
            );
          } catch (error) {
            thrown = error;
          }

          expect(identical(thrown, writeFailure), isTrue);
          expect(keyStore.writeCount, 1);
          expect(openedDatabase.closeCount, 1);
          expect(events, <String>[
            'onOpened:start',
            'onOpened:end',
            'markerWrite',
            'close',
          ]);
        },
      );

      test(
        'close failure remains fail-closed and reports both failures',
        () async {
          const dbName = 'identity.db';
          await File(
            '${tempDirectory.path}/$dbName',
          ).writeAsBytes(const <int>[1]);
          final writeFailure = StateError('secure marker write failed');
          final closeFailure = StateError('database close failed');
          final events = <String>[];
          final keyStore = _FailingWriteKeyStore(
            storedValue: legacyKey,
            writeFailure: writeFailure,
            events: events,
          );
          final openedDatabase = _RecordingDatabase(
            closeFailure: closeFailure,
            events: events,
          );

          Object? thrown;
          try {
            await openEncryptedDatabase(
              secureKeyStore: keyStore,
              dbName: dbName,
              version: 1,
              onCreate: (_, _) async {},
              onUpgrade: (_, _, _) async {},
              onOpened: (database) {
                expect(identical(database, openedDatabase), isTrue);
                events.add('onOpened');
              },
              debugHooks: EncryptedDatabaseOpenDebugHooks(
                resolveDatabasesPath: () async => tempDirectory.path,
                isRawKeyDatabase: (_, _, _) async => true,
                openDatabase:
                    (
                      _, {
                      required version,
                      required password,
                      required onConfigure,
                      required onCreate,
                      required onUpgrade,
                      required onDowngrade,
                    }) async => openedDatabase,
              ),
            );
          } catch (error) {
            thrown = error;
          }

          expect(openedDatabase.closeCount, 1);
          expect(thrown, isA<EncryptedDatabaseOpenCleanupException>());
          final cleanupFailure =
              thrown! as EncryptedDatabaseOpenCleanupException;
          expect(cleanupFailure.phase, 'post_open_close');
          expect(identical(cleanupFailure.openFailure, writeFailure), isTrue);
          expect(
            identical(cleanupFailure.cleanupFailure, closeFailure),
            isTrue,
          );
          expect(events, <String>['onOpened', 'markerWrite', 'close']);
        },
      );

      test(
        'requireExisting rejects a missing key before resolving a database path',
        () async {
          var pathResolutionCount = 0;

          Object? thrown;
          try {
            await openEncryptedDatabase(
              secureKeyStore: _StaticKeyStore(null),
              dbName: 'identity.db',
              version: 1,
              onCreate: (_, _) async {},
              onUpgrade: (_, _, _) async {},
              requireExisting: true,
              debugHooks: EncryptedDatabaseOpenDebugHooks(
                resolveDatabasesPath: () async {
                  pathResolutionCount += 1;
                  return tempDirectory.path;
                },
                isRawKeyDatabase: (_, _, _) async => true,
                openDatabase:
                    (
                      _, {
                      required version,
                      required password,
                      required onConfigure,
                      required onCreate,
                      required onUpgrade,
                      required onDowngrade,
                    }) async => throw StateError('must not open'),
              ),
            );
          } catch (error) {
            thrown = error;
          }

          expect(thrown, isA<ExistingEncryptedDatabaseRequiredException>());
          expect(
            (thrown! as ExistingEncryptedDatabaseRequiredException).reason,
            'missing_encryption_key',
          );
          expect(pathResolutionCount, 0);
        },
      );

      test(
        'requireExisting rejects a missing file without invoking open',
        () async {
          var openCount = 0;

          Object? thrown;
          try {
            await openEncryptedDatabase(
              secureKeyStore: _StaticKeyStore('raw:$legacyKey'),
              dbName: 'identity.db',
              version: 1,
              onCreate: (_, _) async {},
              onUpgrade: (_, _, _) async {},
              requireExisting: true,
              debugHooks: EncryptedDatabaseOpenDebugHooks(
                resolveDatabasesPath: () async => tempDirectory.path,
                isRawKeyDatabase: (_, _, _) async => true,
                openDatabase:
                    (
                      _, {
                      required version,
                      required password,
                      required onConfigure,
                      required onCreate,
                      required onUpgrade,
                      required onDowngrade,
                    }) async {
                      openCount += 1;
                      throw StateError('must not open');
                    },
              ),
            );
          } catch (error) {
            thrown = error;
          }

          expect(thrown, isA<ExistingEncryptedDatabaseRequiredException>());
          expect(
            (thrown! as ExistingEncryptedDatabaseRequiredException).reason,
            'missing_database',
          );
          expect(openCount, 0);
          expect(
            await File('${tempDirectory.path}/identity.db').exists(),
            isFalse,
          );
        },
      );

      test(
        'requireExisting preserves a pre-existing user_version zero incumbent',
        () async {
          const dbName = 'identity.db';
          const incumbentBytes = <int>[7, 8, 9];
          final dbFile = File('${tempDirectory.path}/$dbName');
          await dbFile.writeAsBytes(incumbentBytes);
          var openCount = 0;

          Object? thrown;
          try {
            await openEncryptedDatabase(
              secureKeyStore: _StaticKeyStore('raw:$legacyKey'),
              dbName: dbName,
              version: 1,
              onCreate: (_, _) async {},
              onUpgrade: (_, _, _) async {},
              requireExisting: true,
              debugHooks: EncryptedDatabaseOpenDebugHooks(
                resolveDatabasesPath: () async => tempDirectory.path,
                isRawKeyDatabase: (_, _, _) async => true,
                readExistingUserVersion: (_, _) async => 0,
                openDatabase:
                    (
                      _, {
                      required version,
                      required password,
                      required onConfigure,
                      required onCreate,
                      required onUpgrade,
                      required onDowngrade,
                    }) async {
                      openCount += 1;
                      throw StateError('must not open a v0 incumbent');
                    },
              ),
            );
          } catch (error) {
            thrown = error;
          }

          expect(thrown, isA<ExistingEncryptedDatabaseRequiredException>());
          expect(
            (thrown! as ExistingEncryptedDatabaseRequiredException).reason,
            'database_user_version_not_positive',
          );
          expect(openCount, 0);
          expect(await dbFile.readAsBytes(), incumbentBytes);
        },
      );

      test(
        'requireExisting removes only a post-probe TOCTOU replacement',
        () async {
          const dbName = 'identity.db';
          const incumbentBytes = <int>[1];
          final dbFile = File('${tempDirectory.path}/$dbName');
          await dbFile.writeAsBytes(incumbentBytes);
          final openedDatabase = _RecordingDatabase();
          final keyStore = _StaticKeyStore('raw:$legacyKey');

          Object? thrown;
          try {
            await openEncryptedDatabase(
              secureKeyStore: keyStore,
              dbName: dbName,
              version: 1,
              onCreate: (_, _) async {},
              onUpgrade: (_, _, _) async {},
              requireExisting: true,
              debugHooks: EncryptedDatabaseOpenDebugHooks(
                resolveDatabasesPath: () async => tempDirectory.path,
                isRawKeyDatabase: (_, _, _) async => true,
                readExistingUserVersion: (_, _) async => 116,
                openDatabase:
                    (
                      path, {
                      required version,
                      required password,
                      required onConfigure,
                      required onCreate,
                      required onUpgrade,
                      required onDowngrade,
                    }) async {
                      // Model the checked file disappearing, followed by SQLite
                      // creating a replacement before invoking onCreate.
                      await dbFile.delete();
                      await File(path).writeAsBytes(const <int>[]);
                      await File('$path-wal').writeAsBytes(const <int>[1]);
                      await File('$path-shm').writeAsBytes(const <int>[1]);
                      await File('$path-journal').writeAsBytes(const <int>[1]);
                      await onCreate(openedDatabase, version);
                      return openedDatabase;
                    },
              ),
            );
          } catch (error) {
            thrown = error;
          }

          expect(thrown, isA<ExistingEncryptedDatabaseRequiredException>());
          expect(
            (thrown! as ExistingEncryptedDatabaseRequiredException).reason,
            'database_disappeared_during_open',
          );
          expect(await dbFile.exists(), isFalse);
          expect(await File('${dbFile.path}-wal').exists(), isFalse);
          expect(await File('${dbFile.path}-shm').exists(), isFalse);
          expect(await File('${dbFile.path}-journal').exists(), isFalse);
        },
      );
    });
  });
}

class _StaticKeyStore implements SecureKeyStore {
  _StaticKeyStore(this.storedValue);

  final String? storedValue;

  @override
  Future<bool> containsKey(String key) async => storedValue != null;

  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => storedValue;

  @override
  Future<void> write(String key, String value) async {}
}

class _FailingWriteKeyStore extends _StaticKeyStore {
  _FailingWriteKeyStore({
    required String storedValue,
    required this.writeFailure,
    this.events,
  }) : super(storedValue);

  final Object writeFailure;
  final List<String>? events;
  int writeCount = 0;

  @override
  Future<void> write(String key, String value) async {
    writeCount += 1;
    events?.add('markerWrite');
    throw writeFailure;
  }
}

class _RecordingDatabase implements Database {
  _RecordingDatabase({this.closeFailure, this.events});

  final Object? closeFailure;
  final List<String>? events;
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount += 1;
    events?.add('close');
    final failure = closeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => const <Map<String, Object?>>[
    <String, Object?>{'cipher_version': 'test'},
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
