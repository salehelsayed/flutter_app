import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';

void main() {
  group('MigrationStreamCrypto', () {
    test('uses one session encapsulation and real AAD for chunk AEAD', () async {
      final bridge = FakeBridge();
      final crypto = BridgeMigrationStreamCrypto(bridge: bridge);
      final session = await crypto.encapsulateSession(
        recipientMlKemPublicKey: 'new-phone-mlkem-public',
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        direction: MigrationStreamDirection.oldToNew,
      );
      final chunks = <MigrationEncryptedChunk>[];

      for (var i = 0; i < 3; i += 1) {
        chunks.add(
          await crypto.encryptChunk(
            session: session,
            plaintext: Uint8List.fromList(utf8.encode('chunk-$i')),
            associatedData: MigrationChunkAssociatedData(
              sessionId: 'session-1',
              bundleId: 'bundle-1',
              entryId: i == 2 ? 'file-1' : 'database',
              chunkIndex: i,
              offset: i * 7,
              isFinal: i == 2,
            ),
            nonce: migrationChunkNonceBase64(
              entryOrdinal: i == 2 ? 1 : 0,
              chunkIndex: i,
            ),
          ),
        );
      }

      expect(
        bridge.commandLog.where((cmd) => cmd == 'migration.session.encap'),
        hasLength(1),
      );
      expect(
        bridge.commandLog.where((cmd) => cmd == 'migration.chunk.encrypt'),
        hasLength(3),
      );
      expect(chunks.map((chunk) => chunk.nonce).toSet(), hasLength(3));
      expect(
        chunks.map((chunk) => chunk.associatedDataSha256),
        everyElement(isNotEmpty),
      );
      expect(chunks.map((chunk) => chunk.kemCiphertext).toSet(), hasLength(1));
    });

    test('routes per-chunk hashing through the injectable executor', () async {
      // P2-9: chunk hashing/codec work runs through an injectable executor
      // whose production default is Isolate.run; a counting fake proves the
      // seam is exercised on both the encrypt and decrypt paths.
      var executorCalls = 0;
      Future<R> countingExecutor<R>(R Function() work) async {
        executorCalls += 1;
        return work();
      }

      final crypto = BridgeMigrationStreamCrypto(
        bridge: FakeBridge(),
        executeChunkWork: countingExecutor,
      );
      final encSession = await crypto.encapsulateSession(
        recipientMlKemPublicKey: 'new-phone-mlkem-public',
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        direction: MigrationStreamDirection.oldToNew,
      );
      final aad = MigrationChunkAssociatedData(
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        entryId: 'database',
        chunkIndex: 0,
        offset: 0,
        isFinal: true,
      );
      final encrypted = await crypto.encryptChunk(
        session: encSession,
        plaintext: Uint8List.fromList([1, 2, 3, 4]),
        associatedData: aad,
        nonce: migrationChunkNonceBase64(entryOrdinal: 0, chunkIndex: 0),
      );
      final afterEncrypt = executorCalls;
      expect(afterEncrypt, greaterThanOrEqualTo(2));

      final decSession = await crypto.decapsulateSession(
        ownMlKemSecretKey: 'new-phone-mlkem-secret',
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        direction: MigrationStreamDirection.oldToNew,
        kemCiphertext: encSession.kemCiphertext,
      );
      await crypto.decryptChunk(
        session: decSession,
        encryptedChunk: encrypted,
        associatedData: aad,
      );
      expect(executorCalls, greaterThan(afterEncrypt));

      // The production default executor really runs the work and returns
      // its result (via Isolate.run).
      expect(await migrationIsolateChunkWorkExecutor(() => 21 * 2), 42);
    });

    test('rejects tampered, reordered, replayed, and truncated chunks', () async {
      final bridge = FakeBridge();
      final crypto = BridgeMigrationStreamCrypto(bridge: bridge);
      final encSession = await crypto.encapsulateSession(
        recipientMlKemPublicKey: 'new-phone-mlkem-public',
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        direction: MigrationStreamDirection.oldToNew,
      );
      final decSession = await crypto.decapsulateSession(
        ownMlKemSecretKey: 'new-phone-mlkem-secret',
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        direction: MigrationStreamDirection.oldToNew,
        kemCiphertext: encSession.kemCiphertext,
      );
      final aad = MigrationChunkAssociatedData(
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        entryId: 'database',
        chunkIndex: 0,
        offset: 0,
        isFinal: false,
      );
      final encrypted = await crypto.encryptChunk(
        session: encSession,
        plaintext: Uint8List.fromList([1, 2, 3]),
        associatedData: aad,
        nonce: migrationChunkNonceBase64(entryOrdinal: 0, chunkIndex: 0),
      );

      await expectLater(
        crypto.decryptChunk(
          session: decSession,
          encryptedChunk: encrypted.copyWith(ciphertext: '${encrypted.ciphertext}x'),
          associatedData: aad,
        ),
        throwsA(isA<MigrationStreamCryptoException>()),
      );
      await expectLater(
        crypto.decryptChunk(
          session: decSession,
          encryptedChunk: encrypted,
          associatedData: aad.copyWith(chunkIndex: 1),
        ),
        throwsA(isA<MigrationStreamCryptoException>()),
      );
      await crypto.decryptChunk(
        session: decSession,
        encryptedChunk: encrypted,
        associatedData: aad,
      );
      await expectLater(
        crypto.decryptChunk(
          session: decSession,
          encryptedChunk: encrypted,
          associatedData: aad,
        ),
        throwsA(isA<MigrationStreamCryptoException>()),
      );
      await expectLater(
        crypto.decryptChunk(
          session: decSession,
          encryptedChunk: encrypted.copyWith(isFinal: true),
          associatedData: aad.copyWith(isFinal: true),
        ),
        throwsA(isA<MigrationStreamCryptoException>()),
      );
    });
  });
}
