import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostic_events.dart';

import '../bridge/fake_bridge.dart';

class _ObservedTransaction implements Transaction {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedDatabase implements Database {
  final transactionValue = _ObservedTransaction();
  final events = <String>[];
  Object? commitError;
  bool? receivedExclusive;
  int transactionCalls = 0;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    transactionCalls++;
    receivedExclusive = exclusive;
    events.add('database_enter');
    final value = await action(transactionValue);
    events.add('database_commit');
    final failure = commitError;
    if (failure != null) throw failure;
    return value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('dbWriteTransaction diagnostic observation', () {
    late void Function(bool, int)? previousObserver;

    setUp(() {
      previousObserver = AppDiagnosticEvents.onStorageTransaction;
    });

    tearDown(() {
      AppDiagnosticEvents.onStorageTransaction = previousObserver;
    });

    for (final observerThrows in [false, true]) {
      test('returns the exact committed body value and observes outside the '
          'transaction zone (observer throws: $observerThrows)', () async {
        final database = _ObservedDatabase();
        final bodyEntered = Completer<void>();
        final releaseBody = Completer<void>();
        final expectedValue = Object();
        final observations = <(bool, int)>[];
        final observerZones = <Zone>[];
        final observerTransactionMarkers = <bool>[];
        final callerZone = Zone.current;
        AppDiagnosticEvents.onStorageTransaction = (successful, durationMs) {
          database.events.add('observer');
          observations.add((successful, durationMs));
          observerZones.add(Zone.current);
          observerTransactionMarkers.add(isInsideDbWriteTransaction());
          if (observerThrows) throw StateError('diagnostic observer failed');
        };

        final pending = dbWriteTransaction<Object>(database, (
          transaction,
        ) async {
          expect(transaction, same(database.transactionValue));
          expect(isInsideDbWriteTransaction(), isTrue);
          database.events.add('body_enter');
          bodyEntered.complete();
          await releaseBody.future;
          expect(isInsideDbWriteTransaction(), isTrue);
          expect(
            () => assertNotInsideDbWriteTransaction(),
            throwsA(isA<BridgeCallInsideDbTransactionError>()),
          );
          return expectedValue;
        }, exclusive: true);

        await bodyEntered.future;
        expect(observations, isEmpty, reason: 'the body has not committed');
        expect(isInsideDbWriteTransaction(), isFalse);
        releaseBody.complete();
        expect(await pending, same(expectedValue));
        expect(database.transactionCalls, 1);
        expect(database.receivedExclusive, isTrue);
        expect(database.events, [
          'database_enter',
          'body_enter',
          'database_commit',
          'observer',
        ]);
        expect(observerZones, [same(callerZone)]);
        expect(observerTransactionMarkers, [false]);
        expect(observations, hasLength(1));
        expect(observations.single.$1, isTrue);
        expect(observations.single.$2, greaterThanOrEqualTo(0));
        expect(isInsideDbWriteTransaction(), isFalse);
      });

      for (final failureSource in ['body', 'database_commit']) {
        test('rethrows the exact $failureSource error and observes failure '
            '(observer throws: $observerThrows)', () async {
          final database = _ObservedDatabase();
          final originalError = StateError('original $failureSource failure');
          final observations = <(bool, int)>[];
          final observerZones = <Zone>[];
          final observerTransactionMarkers = <bool>[];
          final callerZone = Zone.current;
          if (failureSource == 'database_commit') {
            database.commitError = originalError;
          }
          AppDiagnosticEvents.onStorageTransaction = (successful, durationMs) {
            database.events.add('observer');
            observations.add((successful, durationMs));
            observerZones.add(Zone.current);
            observerTransactionMarkers.add(isInsideDbWriteTransaction());
            if (observerThrows) throw ArgumentError('unrelated observer error');
          };

          final pending = dbWriteTransaction<Object>(database, (_) async {
            database.events.add('body_enter');
            await Future<void>.value();
            expect(isInsideDbWriteTransaction(), isTrue);
            if (failureSource == 'body') throw originalError;
            return Object();
          }, exclusive: false);

          await expectLater(pending, throwsA(same(originalError)));
          expect(database.transactionCalls, 1);
          expect(database.receivedExclusive, isFalse);
          expect(database.events, [
            'database_enter',
            'body_enter',
            if (failureSource == 'database_commit') 'database_commit',
            'observer',
          ]);
          expect(observerZones, [same(callerZone)]);
          expect(observerTransactionMarkers, [false]);
          expect(observations, hasLength(1));
          expect(observations.single.$1, isFalse);
          expect(observations.single.$2, greaterThanOrEqualTo(0));
          expect(isInsideDbWriteTransaction(), isFalse);
        });
      }
    }
  });

  group('db_write_transaction guard', () {
    test('bridge.send invoked inside a dbWriteTransaction zone throws', () async {
      final bridge = FakeBridge();
      await bridge.initialize();

      Object? thrown;
      try {
        await runInDbWriteTransactionZoneForTest(() async {
          await bridge.send(
            jsonEncode({'cmd': 'payload.verify', 'payload': {}}),
          );
        });
      } catch (e) {
        thrown = e;
      }

      expect(
        thrown,
        isA<BridgeCallInsideDbTransactionError>(),
        reason:
            'When a bridge.send is invoked from inside a dbWriteTransaction body, '
            'the zone-flag guard must throw BridgeCallInsideDbTransactionError so '
            'that the SQLCipher write lock cannot be held across native '
            'method-channel hops.',
      );
    });

    test(
      'bridge.send outside any dbWriteTransaction zone works normally',
      () async {
        final bridge = FakeBridge();
        await bridge.initialize();

        final result = await bridge.send(
          jsonEncode({'cmd': 'payload.verify', 'payload': {}}),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
      },
    );

    test('isInsideDbWriteTransaction reflects the surrounding zone', () async {
      expect(isInsideDbWriteTransaction(), isFalse);
      await runInDbWriteTransactionZoneForTest(() async {
        expect(isInsideDbWriteTransaction(), isTrue);
      });
      expect(isInsideDbWriteTransaction(), isFalse);
    });

    test(
      'PassthroughCryptoBridge respects the guard for its intercepted commands',
      () async {
        // The PassthroughCryptoBridge subclass intercepts message.encrypt
        // and message.decrypt with early returns before delegating to
        // super.send. Without the override-level guard, those two commands
        // would bypass the parent FakeBridge.send guard. Test pins the
        // patch from /ultrareview run 1 bug_010.
        final bridge = PassthroughCryptoBridge();
        await bridge.initialize();

        for (final cmd in const ['message.encrypt', 'message.decrypt']) {
          Object? thrown;
          try {
            await runInDbWriteTransactionZoneForTest(() async {
              await bridge.send(
                jsonEncode({
                  'cmd': cmd,
                  'payload': {
                    'plaintext': 'p',
                    'ciphertext': 'c',
                    'recipientPublicKey': 'k',
                    'kem': 'k',
                    'nonce': 'n',
                    'secretKey': 's',
                  },
                }),
              );
            });
          } catch (e) {
            thrown = e;
          }
          expect(
            thrown,
            isA<BridgeCallInsideDbTransactionError>(),
            reason: 'PassthroughCryptoBridge.$cmd must trip the guard',
          );
        }
      },
    );

    test(
      'ZeroPeerPublishBridge respects the guard for group:publish',
      () async {
        final bridge = ZeroPeerPublishBridge();
        await bridge.initialize();

        Object? thrown;
        try {
          await runInDbWriteTransactionZoneForTest(() async {
            await bridge.send(
              jsonEncode({
                'cmd': 'group:publish',
                'payload': {'messageId': 'm-1'},
              }),
            );
          });
        } catch (e) {
          thrown = e;
        }
        expect(
          thrown,
          isA<BridgeCallInsideDbTransactionError>(),
          reason:
              'ZeroPeerPublishBridge.group:publish must trip the guard '
              '(/ultrareview run 1 bug_010)',
        );
      },
    );
  });
}
