import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/qr_code/domain/models/qr_payload_model.dart';

void main() {
  const testPk = 'cHVibGljLWtleS1iYXNlNjQ=';
  const testNs = '12D3KooWTestPeerIdABCDEF';
  const testRv = '/dns4/relay.example.com/tcp/443/wss';
  const testTs = '2026-01-15T12:00:00.000Z';
  const testSig = 'c2lnbmF0dXJlLWJhc2U2NA==';
  const testMlkem = 'bWxrZW0tcHVibGljLWtleQ==';

  QRPayloadModel makePayload({String? mlkem}) {
    return QRPayloadModel(
      pk: testPk,
      ns: testNs,
      rv: testRv,
      ts: testTs,
      sig: testSig,
      mlkem: mlkem,
    );
  }

  group('QRPayloadModel', () {
    group('fromJson / toJson', () {
      test('round-trips correctly with mlkem', () {
        final original = makePayload(mlkem: testMlkem);
        final json = original.toJson();
        final restored = QRPayloadModel.fromJson(json);

        expect(restored.pk, original.pk);
        expect(restored.ns, original.ns);
        expect(restored.rv, original.rv);
        expect(restored.ts, original.ts);
        expect(restored.sig, original.sig);
        expect(restored.mlkem, original.mlkem);
      });

      test('round-trips correctly without mlkem', () {
        final original = makePayload();
        final json = original.toJson();
        final restored = QRPayloadModel.fromJson(json);

        expect(restored.pk, original.pk);
        expect(restored.ns, original.ns);
        expect(restored.rv, original.rv);
        expect(restored.ts, original.ts);
        expect(restored.sig, original.sig);
        expect(restored.mlkem, isNull);
      });

      test('toJson omits mlkem key when null', () {
        final model = makePayload();
        final json = model.toJson();
        expect(json.containsKey('mlkem'), isFalse);
      });

      test('toJson includes mlkem key when present', () {
        final model = makePayload(mlkem: testMlkem);
        final json = model.toJson();
        expect(json.containsKey('mlkem'), isTrue);
        expect(json['mlkem'], testMlkem);
      });
    });

    group('toJsonString', () {
      test('keys are sorted alphabetically', () {
        final model = makePayload(mlkem: testMlkem);
        final jsonStr = model.toJsonString();
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final keys = decoded.keys.toList();

        final sortedKeys = List<String>.from(keys)..sort();
        expect(keys, equals(sortedKeys));
      });

      test('includes mlkem when present', () {
        final model = makePayload(mlkem: testMlkem);
        final jsonStr = model.toJsonString();
        expect(jsonStr, contains('"mlkem"'));
        expect(jsonStr, contains(testMlkem));
      });

      test('excludes mlkem when null', () {
        final model = makePayload();
        final jsonStr = model.toJsonString();
        expect(jsonStr, isNot(contains('"mlkem"')));
      });
    });

    group('buildUnsignedPayload', () {
      test('excludes sig field', () {
        final payload = QRPayloadModel.buildUnsignedPayload(
          pk: testPk,
          ns: testNs,
          rv: testRv,
          ts: testTs,
        );

        expect(payload.containsKey('sig'), isFalse);
      });

      test('includes mlkem when provided', () {
        final payload = QRPayloadModel.buildUnsignedPayload(
          pk: testPk,
          ns: testNs,
          rv: testRv,
          ts: testTs,
          mlkem: testMlkem,
        );

        expect(payload['mlkem'], testMlkem);
      });

      test('excludes mlkem when null', () {
        final payload = QRPayloadModel.buildUnsignedPayload(
          pk: testPk,
          ns: testNs,
          rv: testRv,
          ts: testTs,
        );

        expect(payload.containsKey('mlkem'), isFalse);
      });

      test('keys are sorted alphabetically', () {
        final payload = QRPayloadModel.buildUnsignedPayload(
          pk: testPk,
          ns: testNs,
          rv: testRv,
          ts: testTs,
          mlkem: testMlkem,
        );

        final keys = payload.keys.toList();
        final sortedKeys = List<String>.from(keys)..sort();
        expect(keys, equals(sortedKeys));
      });
    });

    group('unsignedPayloadToJsonString', () {
      test('produces canonical JSON with sorted keys', () {
        final payload = {
          'ts': testTs,
          'pk': testPk,
          'ns': testNs,
          'rv': testRv,
        };

        final jsonStr =
            QRPayloadModel.unsignedPayloadToJsonString(payload);
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final keys = decoded.keys.toList();

        final sortedKeys = List<String>.from(keys)..sort();
        expect(keys, equals(sortedKeys));
      });
    });

    group('equality', () {
      test('equal when all fields match', () {
        final a = makePayload(mlkem: testMlkem);
        final b = makePayload(mlkem: testMlkem);
        expect(a, equals(b));
      });

      test('not equal when sig differs', () {
        final a = makePayload();
        final b = QRPayloadModel(
          pk: testPk,
          ns: testNs,
          rv: testRv,
          ts: testTs,
          sig: 'different-signature-value',
        );
        expect(a, isNot(equals(b)));
      });

      test('not equal when mlkem differs', () {
        final a = makePayload(mlkem: testMlkem);
        final b = makePayload();
        expect(a, isNot(equals(b)));
      });
    });

    group('hashCode', () {
      test('consistent for equal objects', () {
        final a = makePayload(mlkem: testMlkem);
        final b = makePayload(mlkem: testMlkem);
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different when fields differ', () {
        final a = makePayload(mlkem: testMlkem);
        final b = makePayload();
        expect(a.hashCode, isNot(equals(b.hashCode)));
      });
    });
  });
}
