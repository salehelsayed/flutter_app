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
  });
}
