import 'dart:typed_data';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_local_transfer_runtime.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';

abstract class MigrationEntryFileReader {
  Future<int> length(String path);

  Future<String> sha256Hex(String path);

  Stream<Uint8List> openRead(
    String path, {
    required int offset,
    required int chunkSize,
  });

  Future<Uint8List> readAll(String path);
}

class IoMigrationEntryFileReader implements MigrationEntryFileReader {
  const IoMigrationEntryFileReader();

  @override
  Future<int> length(String path) async {
    return File(path).length();
  }

  @override
  Future<String> sha256Hex(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  @override
  Stream<Uint8List> openRead(
    String path, {
    required int offset,
    required int chunkSize,
  }) async* {
    final file = await File(path).open();
    try {
      await file.setPosition(offset);
      while (true) {
        final chunk = await file.read(chunkSize);
        if (chunk.isEmpty) {
          break;
        }
        yield Uint8List.fromList(chunk);
      }
    } finally {
      await file.close();
    }
  }

  @override
  Future<Uint8List> readAll(String path) async {
    return File(path).readAsBytes();
  }
}

class MigrationEntryStreamInput {
  final String entryId;
  final MigrationTransferEntryKind kind;
  final String filePath;
  final String? relativePath;

  /// Optional precomputed size/hash (e.g. from the file manifest scan) so the
  /// source does not stream-hash the same file twice.
  final int? sizeBytes;
  final String? sha256;

  const MigrationEntryStreamInput({
    required this.entryId,
    required this.kind,
    required this.filePath,
    this.relativePath,
    this.sizeBytes,
    this.sha256,
  });
}

class MigrationEntryStreamSource {
  final MigrationEntryFileReader fileReader;
  final int chunkSize;

  const MigrationEntryStreamSource({
    required this.fileReader,
    required this.chunkSize,
  });

  Future<AccountMigrationLocalTransferBundle> build({
    required String sessionId,
    required String bundleId,
    required List<MigrationEntryStreamInput> entries,
    MigrationStreamCrypto? streamCrypto,
    Future<void> Function()? cleanupAfterSuccess,
  }) async {
    if (chunkSize <= 0) {
      throw const MigrationStreamCryptoException('chunk size must be positive');
    }
    final descriptors = <MigrationTransferEntryDescriptor>[];
    final streamingEntries = <AccountMigrationStreamingEntry>[];
    var totalBytes = 0;
    for (final entry in entries) {
      final size = entry.sizeBytes ?? await fileReader.length(entry.filePath);
      final sha256Hex =
          entry.sha256 ?? await fileReader.sha256Hex(entry.filePath);
      final chunkCount = size == 0 ? 1 : ((size + chunkSize - 1) ~/ chunkSize);
      descriptors.add(
        MigrationTransferEntryDescriptor(
          entryId: entry.entryId,
          kind: entry.kind,
          relativePath: entry.relativePath,
          sizeBytes: size,
          sha256: sha256Hex,
          chunkSize: chunkSize,
          chunkCount: chunkCount,
        ),
      );
      streamingEntries.add(
        _FileAccountMigrationStreamingEntry(
          entryId: entry.entryId,
          kind: entry.kind,
          relativePath: entry.relativePath,
          filePath: entry.filePath,
          sizeBytes: size,
          chunkSize: chunkSize,
          fileReader: fileReader,
        ),
      );
      totalBytes += size;
    }

    final manifestSha256 = migrationTransferStringSha256Hex(
      migrationTransferCanonicalJson({
        'protocol_version': MigrationTransferManifest.protocolVersion,
        'session_id': sessionId,
        'bundle_id': bundleId,
        'total_bytes': totalBytes,
        'entries': descriptors.map((entry) => entry.toJson()).toList(),
      }),
    );

    return AccountMigrationLocalTransferBundle(
      manifest: MigrationTransferManifest.v2(
        sessionId: sessionId,
        bundleId: bundleId,
        totalBytes: totalBytes,
        manifestSha256: manifestSha256,
        sessionKem: const MigrationTransferSessionKem(
          algorithm: 'ml-kem-768-hkdf-sha256-aes-256-gcm',
          direction: 'old_to_new',
        ),
        entries: descriptors,
      ),
      encryptedSegments: null,
      streamingEntries: streamingEntries,
      cleanupAfterSuccess: cleanupAfterSuccess,
    );
  }
}

class _FileAccountMigrationStreamingEntry
    implements AccountMigrationStreamingEntry {
  @override
  final String entryId;
  @override
  final MigrationTransferEntryKind kind;
  @override
  final String? relativePath;
  final String filePath;
  @override
  final int sizeBytes;
  final int chunkSize;
  final MigrationEntryFileReader fileReader;

  const _FileAccountMigrationStreamingEntry({
    required this.entryId,
    required this.kind,
    required this.relativePath,
    required this.filePath,
    required this.sizeBytes,
    required this.chunkSize,
    required this.fileReader,
  });

  @override
  Stream<Uint8List> openChunks({int offset = 0}) {
    return fileReader.openRead(filePath, offset: offset, chunkSize: chunkSize);
  }
}
