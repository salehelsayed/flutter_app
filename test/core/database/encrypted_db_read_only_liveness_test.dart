import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

void main() {
  const key =
      'a1b2c3d4e5f6071829304152637485960f1e2d3c4b5a69788796a5b4c3d2e1f0';

  group('encrypted read-only SQLCipher liveness', () {
    test('iOS preserves the prior unbounded opener behavior', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final pendingOpen = Completer<Database>();
      final database = _FakeDatabase();
      final passwords = <String>[];
      var waiterCalls = 0;
      var completed = false;
      try {
        final open = openEncryptedDatabaseReadOnlyTolerant(
          path: '/private/messages.db',
          storedKey: key,
          debugHooks: EncryptedReadOnlyOpenDebugHooks(
            enforceAndroidLiveness: false,
            openDatabase:
                ({
                  required path,
                  required password,
                  required readOnly,
                  required singleInstance,
                  required onConfigure,
                }) async {
                  passwords.add(password);
                  await onConfigure(database);
                  return pendingOpen.future;
                },
            elapsed: () => const Duration(days: 1),
            waitForDeadline: (operation, timeout, onTimeout) {
              waiterCalls += 1;
              return operation;
            },
          ),
        );
        open.then((_) => completed = true);

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(completed, isFalse);
        expect(waiterCalls, 0);
        expect(passwords, <String>["x'$key'"]);

        pendingOpen.complete(database);
        expect(await open, same(database));
        expect(completed, isTrue);
      } finally {
        if (!pendingOpen.isCompleted) pendingOpen.complete(database);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('raw timeout never starts legacy fallback', () async {
      final pendingOpen = Completer<Database>();
      final passwords = <String>[];
      final observedBudgets = <Duration>[];

      final open = openEncryptedDatabaseReadOnlyTolerant(
        path: '/private/messages.db',
        // Bare keys are the only mode that is allowed to try legacy after a
        // genuine raw-key rejection.
        storedKey: key,
        debugHooks: EncryptedReadOnlyOpenDebugHooks(
          openDatabase:
              ({
                required path,
                required password,
                required readOnly,
                required singleInstance,
                required onConfigure,
              }) {
                passwords.add(password);
                return pendingOpen.future;
              },
          elapsed: () => Duration.zero,
          waitForDeadline: (operation, timeout, onTimeout) async {
            observedBudgets.add(timeout);
            return onTimeout();
          },
        ),
      );

      await expectLater(
        open,
        throwsA(
          isA<EncryptedDatabaseReadOnlyTimeout>()
              .having((error) => error.attempt, 'attempt', 'raw')
              .having(
                (error) => error.duration,
                'deadline',
                encryptedReadOnlyOpenDeadline,
              ),
        ),
      );
      expect(passwords, <String>["x'$key'"]);
      expect(observedBudgets, <Duration>[encryptedReadOnlyOpenDeadline]);
    });

    test('quick raw rejection gives legacy only remaining budget', () async {
      var elapsed = Duration.zero;
      final observedBudgets = <Duration>[];
      final passwords = <String>[];
      final configuredSql = <String>[];
      final database = _FakeDatabase(onRawQuery: configuredSql.add);

      final result = await openEncryptedDatabaseReadOnlyTolerant(
        path: '/private/messages.db',
        storedKey: key,
        debugHooks: EncryptedReadOnlyOpenDebugHooks(
          openDatabase:
              ({
                required path,
                required password,
                required readOnly,
                required singleInstance,
                required onConfigure,
              }) async {
                expect(readOnly, isTrue);
                expect(singleInstance, isFalse);
                passwords.add(password);
                await onConfigure(database);
                if (password.startsWith("x'")) {
                  elapsed = const Duration(milliseconds: 700);
                  throw StateError('raw key rejected promptly');
                }
                return database;
              },
          elapsed: () => elapsed,
          waitForDeadline: (operation, timeout, onTimeout) {
            observedBudgets.add(timeout);
            return operation;
          },
        ),
      );

      expect(result, same(database));
      expect(passwords, <String>["x'$key'", key]);
      expect(observedBudgets, <Duration>[
        const Duration(seconds: 2),
        const Duration(milliseconds: 1300),
      ]);
      expect(configuredSql, <String>[
        'PRAGMA busy_timeout = 1000',
        'PRAGMA busy_timeout = 1000',
      ]);
    });

    test('late open closes once', () async {
      final pendingOpen = Completer<Database>();
      final database = _FakeDatabase();

      final open = openEncryptedDatabaseReadOnlyTolerant(
        path: '/private/messages.db',
        storedKey: 'raw:$key',
        debugHooks: EncryptedReadOnlyOpenDebugHooks(
          openDatabase:
              ({
                required path,
                required password,
                required readOnly,
                required singleInstance,
                required onConfigure,
              }) => pendingOpen.future,
          elapsed: () => Duration.zero,
          waitForDeadline: (operation, timeout, onTimeout) async {
            return onTimeout();
          },
        ),
      );

      await expectLater(open, throwsA(isA<EncryptedDatabaseReadOnlyTimeout>()));
      expect(database.closeCount, 0);

      pendingOpen.complete(database);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(database.closeCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(database.closeCount, 1);
    });

    test('a source timeout is liveness failure, not a wrong-key signal', () {
      var openCount = 0;
      return expectLater(
        openEncryptedDatabaseReadOnlyTolerant(
          path: '/private/messages.db',
          storedKey: key,
          debugHooks: EncryptedReadOnlyOpenDebugHooks(
            openDatabase:
                ({
                  required path,
                  required password,
                  required readOnly,
                  required singleInstance,
                  required onConfigure,
                }) {
                  openCount += 1;
                  return Future<Database>.error(
                    TimeoutException('native open remained queued'),
                  );
                },
            elapsed: () => Duration.zero,
            waitForDeadline: (operation, timeout, onTimeout) => operation,
          ),
        ).whenComplete(() => expect(openCount, 1)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}

class _FakeDatabase implements Database {
  _FakeDatabase({this.onRawQuery});

  final void Function(String sql)? onRawQuery;
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount += 1;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    onRawQuery?.call(sql);
    return const <Map<String, Object?>>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
