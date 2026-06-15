import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_app/features/account_migration/application/migration_entry_stream_source.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MigrationEntryStreamSource', () {
    test('emits v2 manifest entries and bounded per-entry chunk streams', () async {
      final reader = _RecordingEntryReader({
        '/tmp/db.snapshot': Uint8List.fromList(utf8.encode('database-bytes')),
        '/tmp/media/photo.jpg': Uint8List.fromList(utf8.encode('photo-bytes')),
        '/tmp/secure.json': Uint8List.fromList(utf8.encode('secure-values')),
      });
      final source = MigrationEntryStreamSource(
        fileReader: reader,
        chunkSize: 5,
      );

      final bundle = await source.build(
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        entries: const [
          MigrationEntryStreamInput(
            entryId: 'database',
            kind: MigrationTransferEntryKind.database,
            filePath: '/tmp/db.snapshot',
          ),
          MigrationEntryStreamInput(
            entryId: 'file-1',
            kind: MigrationTransferEntryKind.file,
            filePath: '/tmp/media/photo.jpg',
            relativePath: 'media/photo.jpg',
          ),
          MigrationEntryStreamInput(
            entryId: 'secure-values',
            kind: MigrationTransferEntryKind.secureValues,
            filePath: '/tmp/secure.json',
          ),
        ],
        streamCrypto: _NeverUsedStreamCrypto(),
      );

      expect(bundle.manifest.protocolVersionValue, 2);
      expect(bundle.manifest.entries.map((entry) => entry.entryId), [
        'database',
        'file-1',
        'secure-values',
      ]);
      expect(bundle.encryptedSegments, isNull);
      expect(bundle.streamingEntries, hasLength(3));
      expect(reader.readAllCalls, 0);

      final emitted = <int>[];
      await for (final chunk in bundle.streamingEntries[1].openChunks()) {
        emitted.add(chunk.length);
      }

      expect(emitted, [5, 5, 1]);
      expect(reader.maxActiveChunks, lessThanOrEqualTo(1));
      expect(reader.readAllCalls, 0);
    });
  });
}

class _RecordingEntryReader implements MigrationEntryFileReader {
  final Map<String, Uint8List> files;
  int readAllCalls = 0;
  int activeChunks = 0;
  int maxActiveChunks = 0;

  _RecordingEntryReader(this.files);

  @override
  Future<int> length(String path) async => files[path]!.length;

  @override
  Future<String> sha256Hex(String path) async {
    return migrationTransferSha256Hex(files[path]!);
  }

  @override
  Stream<Uint8List> openRead(
    String path, {
    required int offset,
    required int chunkSize,
  }) async* {
    final bytes = files[path]!;
    var cursor = offset;
    while (cursor < bytes.length) {
      final end = cursor + chunkSize > bytes.length
          ? bytes.length
          : cursor + chunkSize;
      activeChunks += 1;
      if (activeChunks > maxActiveChunks) {
        maxActiveChunks = activeChunks;
      }
      yield Uint8List.fromList(bytes.sublist(cursor, end));
      activeChunks -= 1;
      cursor = end;
    }
  }

  @override
  Future<Uint8List> readAll(String path) async {
    readAllCalls += 1;
    throw StateError('whole-file read is forbidden in protocol v2');
  }
}

class _NeverUsedStreamCrypto implements MigrationStreamCrypto {
  @override
  Future<MigrationStreamDecryptSession> decapsulateSession({
    required String ownMlKemSecretKey,
    required String sessionId,
    required String bundleId,
    required MigrationStreamDirection direction,
    required String kemCiphertext,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MigrationStreamEncryptSession> encapsulateSession({
    required String recipientMlKemPublicKey,
    required String sessionId,
    required String bundleId,
    required MigrationStreamDirection direction,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MigrationEncryptedChunk> encryptChunk({
    required MigrationStreamEncryptSession session,
    required Uint8List plaintext,
    required MigrationChunkAssociatedData associatedData,
    required String nonce,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> decryptChunk({
    required MigrationStreamDecryptSession session,
    required MigrationEncryptedChunk encryptedChunk,
    required MigrationChunkAssociatedData associatedData,
  }) {
    throw UnimplementedError();
  }
}
