import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/database/db_write_transaction.dart';

import '../bridge/fake_bridge.dart';

void main() {
  group('db_write_transaction guard', () {
    test('bridge.send invoked inside a dbWriteTransaction zone throws', () async {
      final bridge = FakeBridge();
      await bridge.initialize();

      Object? thrown;
      try {
        await runInDbWriteTransactionZoneForTest(() async {
          await bridge.send(jsonEncode({'cmd': 'payload.verify', 'payload': {}}));
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

    test('bridge.send outside any dbWriteTransaction zone works normally', () async {
      final bridge = FakeBridge();
      await bridge.initialize();

      final result = await bridge.send(
        jsonEncode({'cmd': 'payload.verify', 'payload': {}}),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
    });

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
