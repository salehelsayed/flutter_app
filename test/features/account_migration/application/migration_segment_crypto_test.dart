import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';

void main() {
  group('BridgeMigrationSegmentCrypto', () {
    test(
      'encrypts and decrypts one bounded segment through message crypto',
      () async {
        final bridge = FakeBridge();
        final crypto = BridgeMigrationSegmentCrypto(bridge: bridge);
        final associatedData = _associatedData();
        final plaintext = Uint8List.fromList(utf8.encode('segment bytes'));

        final encrypted = await crypto.encryptSegment(
          plaintext: plaintext,
          recipientMlKemPublicKey: 'new-phone-mlkem-public',
          associatedData: associatedData,
        );
        final decrypted = await crypto.decryptSegment(
          encryptedSegment: encrypted,
          ownMlKemSecretKey: 'new-phone-mlkem-secret',
          associatedData: associatedData,
        );

        expect(decrypted, plaintext);
        expect(encrypted.associatedDataSha256, associatedData.sha256Hex);
        expect(
          encrypted.plaintextSha256,
          migrationTransferSha256Hex(plaintext),
        );
        expect(
          bridge.commandLog,
          containsAllInOrder(['message.encrypt', 'message.decrypt']),
        );
        expect(bridge.commandLog, isNot(contains('blob:encrypt')));
        expect(bridge.commandLog, isNot(contains('blob:decrypt')));
      },
    );

    test('rejects wrong associated data before decrypting', () async {
      final bridge = FakeBridge();
      final crypto = BridgeMigrationSegmentCrypto(bridge: bridge);
      final associatedData = _associatedData();
      final encrypted = await crypto.encryptSegment(
        plaintext: Uint8List.fromList([1, 2, 3]),
        recipientMlKemPublicKey: 'new-phone-mlkem-public',
        associatedData: associatedData,
      );

      expect(
        () => crypto.decryptSegment(
          encryptedSegment: encrypted,
          ownMlKemSecretKey: 'new-phone-mlkem-secret',
          associatedData: _associatedData(sessionId: 'other-session'),
        ),
        throwsA(isA<MigrationSegmentCryptoException>()),
      );
    });

    test('rejects ciphertext checksum tampering', () async {
      final bridge = FakeBridge();
      final crypto = BridgeMigrationSegmentCrypto(bridge: bridge);
      final associatedData = _associatedData();
      final encrypted = await crypto.encryptSegment(
        plaintext: Uint8List.fromList([1, 2, 3]),
        recipientMlKemPublicKey: 'new-phone-mlkem-public',
        associatedData: associatedData,
      );

      expect(
        () => crypto.decryptSegment(
          encryptedSegment: MigrationEncryptedSegment(
            index: encrypted.index,
            kem: encrypted.kem,
            ciphertext: '${encrypted.ciphertext}tampered',
            nonce: encrypted.nonce,
            plaintextSha256: encrypted.plaintextSha256,
            ciphertextSha256: encrypted.ciphertextSha256,
            associatedDataSha256: encrypted.associatedDataSha256,
          ),
          ownMlKemSecretKey: 'new-phone-mlkem-secret',
          associatedData: associatedData,
        ),
        throwsA(isA<MigrationSegmentCryptoException>()),
      );
    });

    test(
      'emits decrypt start and done telemetry bracketing bridge decrypt '
      'events',
      () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final bridge = FakeBridge();
        final crypto = BridgeMigrationSegmentCrypto(bridge: bridge);
        final associatedData = _associatedData();
        final plaintext = Uint8List.fromList(utf8.encode('segment bytes'));
        final encrypted = await crypto.encryptSegment(
          plaintext: plaintext,
          recipientMlKemPublicKey: 'new-phone-mlkem-public',
          associatedData: associatedData,
        );
        events.clear();

        final decrypted = await crypto.decryptSegment(
          encryptedSegment: encrypted,
          ownMlKemSecretKey: 'new-phone-mlkem-secret',
          associatedData: associatedData,
        );

        expect(decrypted, plaintext);
        final names = events
            .map((event) => event['event'] as String)
            .toList(growable: false);
        final startIndex = names.indexOf(
          'ACCOUNT_MIGRATION_SEGMENT_DECRYPT_START',
        );
        final requestIndex = names.indexOf('MLKEM_FL_BRIDGE_DECRYPT_REQUEST');
        final responseIndex = names.indexOf('MLKEM_FL_BRIDGE_DECRYPT_RESPONSE');
        final doneIndex = names.indexOf('ACCOUNT_MIGRATION_SEGMENT_DECRYPT_DONE');
        expect(startIndex, isNonNegative);
        expect(requestIndex, isNonNegative);
        expect(responseIndex, isNonNegative);
        expect(doneIndex, isNonNegative);
        expect(
          startIndex < requestIndex &&
              requestIndex < responseIndex &&
              responseIndex < doneIndex,
          isTrue,
          reason:
              'generic bridge decrypt events must fall between segment '
              'decrypt start/done: $names',
        );
        final startDetails = events[startIndex]['details'] as Map;
        expect(startDetails['sessionId'], 'session-1');
        expect(startDetails['bundleId'], 'bundle-1');
        expect(startDetails['segmentIndex'], 0);
        expect(startDetails['payloadBytes'], encrypted.ciphertext.length);
        final doneDetails = events[doneIndex]['details'] as Map;
        expect(doneDetails['sessionId'], 'session-1');
        expect(doneDetails['segmentIndex'], 0);
        expect(doneDetails['elapsedMs'], isA<int>());
      },
    );

    test('classifies bridge timeout decrypt failure with errorCode', () async {
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final bridge = FakeBridge();
      final crypto = BridgeMigrationSegmentCrypto(bridge: bridge);
      final associatedData = _associatedData();
      final encrypted = await crypto.encryptSegment(
        plaintext: Uint8List.fromList(utf8.encode('segment bytes')),
        recipientMlKemPublicKey: 'new-phone-mlkem-public',
        associatedData: associatedData,
      );
      bridge.responses['message.decrypt'] = {
        'ok': false,
        'errorCode': 'BRIDGE_TIMEOUT',
        'errorMessage': 'Bridge call timed out after 10s',
      };
      events.clear();

      await expectLater(
        crypto.decryptSegment(
          encryptedSegment: encrypted,
          ownMlKemSecretKey: 'new-phone-mlkem-secret',
          associatedData: associatedData,
        ),
        throwsA(isA<MigrationSegmentCryptoException>()),
      );

      final failed = events.singleWhere(
        (event) => event['event'] == 'ACCOUNT_MIGRATION_SEGMENT_DECRYPT_FAILED',
      );
      final details = failed['details'] as Map;
      expect(details['sessionId'], 'session-1');
      expect(details['segmentIndex'], 0);
      expect(details['elapsedMs'], isA<int>());
      expect(details['reason'], 'bridgeTimeout');
      expect(details['errorCode'], 'BRIDGE_TIMEOUT');
    });

    test('classifies plain bridge rejection without timeout code', () async {
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final bridge = FakeBridge();
      final crypto = BridgeMigrationSegmentCrypto(bridge: bridge);
      final associatedData = _associatedData();
      final encrypted = await crypto.encryptSegment(
        plaintext: Uint8List.fromList(utf8.encode('segment bytes')),
        recipientMlKemPublicKey: 'new-phone-mlkem-public',
        associatedData: associatedData,
      );
      bridge.responses['message.decrypt'] = {
        'ok': false,
        'errorMessage': 'decrypt refused',
      };
      events.clear();

      await expectLater(
        crypto.decryptSegment(
          encryptedSegment: encrypted,
          ownMlKemSecretKey: 'new-phone-mlkem-secret',
          associatedData: associatedData,
        ),
        throwsA(isA<MigrationSegmentCryptoException>()),
      );

      final failed = events.singleWhere(
        (event) => event['event'] == 'ACCOUNT_MIGRATION_SEGMENT_DECRYPT_FAILED',
      );
      final details = failed['details'] as Map;
      expect(details['reason'], 'bridgeRejected');
      expect(details['errorCode'], isNull);
    });

    test(
      'reports checksum mismatch for tampered ciphertext without calling '
      'the bridge',
      () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final bridge = FakeBridge();
        final crypto = BridgeMigrationSegmentCrypto(bridge: bridge);
        final associatedData = _associatedData();
        final encrypted = await crypto.encryptSegment(
          plaintext: Uint8List.fromList([1, 2, 3]),
          recipientMlKemPublicKey: 'new-phone-mlkem-public',
          associatedData: associatedData,
        );
        events.clear();

        await expectLater(
          crypto.decryptSegment(
            encryptedSegment: MigrationEncryptedSegment(
              index: encrypted.index,
              kem: encrypted.kem,
              ciphertext: '${encrypted.ciphertext}tampered',
              nonce: encrypted.nonce,
              plaintextSha256: encrypted.plaintextSha256,
              ciphertextSha256: encrypted.ciphertextSha256,
              associatedDataSha256: encrypted.associatedDataSha256,
            ),
            ownMlKemSecretKey: 'new-phone-mlkem-secret',
            associatedData: associatedData,
          ),
          throwsA(isA<MigrationSegmentCryptoException>()),
        );

        final failed = events.singleWhere(
          (event) =>
              event['event'] == 'ACCOUNT_MIGRATION_SEGMENT_DECRYPT_FAILED',
        );
        expect((failed['details'] as Map)['reason'], 'checksumMismatch');
        expect(
          events.map((event) => event['event']),
          isNot(contains('MLKEM_FL_BRIDGE_DECRYPT_REQUEST')),
          reason: 'pre-bridge checksum failures must not call the bridge',
        );
      },
    );
  });
}

MigrationSegmentAssociatedData _associatedData({
  String sessionId = 'session-1',
}) {
  return MigrationSegmentAssociatedData(
    sessionId: sessionId,
    bundleId: 'bundle-1',
    segmentIndex: 0,
    offset: 0,
    plaintextLength: 13,
    manifestSha256: 'manifest-hash',
  );
}
