import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';

/// Routes per-chunk CPU work (hashing, base64 codec) off the main isolate so
/// large transfers do not jank the UI thread; injectable for host tests.
typedef MigrationChunkWorkExecutor = Future<R> Function<R>(R Function() work);

Future<R> migrationIsolateChunkWorkExecutor<R>(R Function() work) {
  return Isolate.run(work);
}

class MigrationSegmentAssociatedData {
  final int protocolVersion;
  final String sessionId;
  final String bundleId;
  final int segmentIndex;
  final int offset;
  final int plaintextLength;
  final String manifestSha256;
  final String direction;

  const MigrationSegmentAssociatedData({
    this.protocolVersion = MigrationTransferManifest.legacyProtocolVersion,
    required this.sessionId,
    required this.bundleId,
    required this.segmentIndex,
    required this.offset,
    required this.plaintextLength,
    required this.manifestSha256,
    this.direction = 'old_to_new',
  });

  Map<String, Object?> toJson() {
    return {
      'protocol_version': protocolVersion,
      'session_id': sessionId,
      'bundle_id': bundleId,
      'segment_index': segmentIndex,
      'offset': offset,
      'plaintext_length': plaintextLength,
      'manifest_sha256': manifestSha256,
      'direction': direction,
    };
  }

  String toCanonicalJson() => migrationTransferCanonicalJson(toJson());

  String get sha256Hex => migrationTransferStringSha256Hex(toCanonicalJson());
}

enum MigrationStreamDirection {
  oldToNew('old_to_new');

  final String wireValue;

  const MigrationStreamDirection(this.wireValue);
}

class MigrationStreamEncryptSession {
  final String sessionId;
  final String bundleId;
  final MigrationStreamDirection direction;
  final String sessionKey;
  final String kemCiphertext;

  const MigrationStreamEncryptSession({
    required this.sessionId,
    required this.bundleId,
    required this.direction,
    required this.sessionKey,
    required this.kemCiphertext,
  });
}

class MigrationStreamDecryptSession {
  final String sessionId;
  final String bundleId;
  final MigrationStreamDirection direction;
  final String sessionKey;
  final String kemCiphertext;
  final Set<String> _decryptedChunks = <String>{};

  MigrationStreamDecryptSession({
    required this.sessionId,
    required this.bundleId,
    required this.direction,
    required this.sessionKey,
    required this.kemCiphertext,
  });

  bool markDecrypted(MigrationChunkAssociatedData associatedData) {
    return _decryptedChunks.add(
      '${associatedData.entryId}:${associatedData.chunkIndex}:'
      '${associatedData.offset}',
    );
  }
}

class MigrationChunkAssociatedData {
  final int protocolVersion;
  final String sessionId;
  final String bundleId;
  final String entryId;
  final int chunkIndex;
  final int offset;
  final bool isFinal;

  const MigrationChunkAssociatedData({
    this.protocolVersion = MigrationTransferManifest.protocolVersion,
    required this.sessionId,
    required this.bundleId,
    required this.entryId,
    required this.chunkIndex,
    required this.offset,
    required this.isFinal,
  });

  MigrationChunkAssociatedData copyWith({
    int? protocolVersion,
    String? sessionId,
    String? bundleId,
    String? entryId,
    int? chunkIndex,
    int? offset,
    bool? isFinal,
  }) {
    return MigrationChunkAssociatedData(
      protocolVersion: protocolVersion ?? this.protocolVersion,
      sessionId: sessionId ?? this.sessionId,
      bundleId: bundleId ?? this.bundleId,
      entryId: entryId ?? this.entryId,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      offset: offset ?? this.offset,
      isFinal: isFinal ?? this.isFinal,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'protocol_version': protocolVersion,
      'session_id': sessionId,
      'bundle_id': bundleId,
      'entry_id': entryId,
      'chunk_index': chunkIndex,
      'offset': offset,
      'is_final': isFinal,
    };
  }

  String toCanonicalJson() => migrationTransferCanonicalJson(toJson());

  String get sha256Hex => migrationTransferStringSha256Hex(toCanonicalJson());
}

class MigrationEncryptedChunk {
  final String entryId;
  final int chunkIndex;
  final int offset;
  final bool isFinal;
  final String kemCiphertext;
  final String ciphertext;
  final String nonce;
  final String plaintextSha256;
  final String ciphertextSha256;
  final String associatedDataSha256;

  const MigrationEncryptedChunk({
    required this.entryId,
    required this.chunkIndex,
    required this.offset,
    required this.isFinal,
    required this.kemCiphertext,
    required this.ciphertext,
    required this.nonce,
    required this.plaintextSha256,
    required this.ciphertextSha256,
    required this.associatedDataSha256,
  });

  MigrationEncryptedChunk copyWith({
    String? entryId,
    int? chunkIndex,
    int? offset,
    bool? isFinal,
    String? kemCiphertext,
    String? ciphertext,
    String? nonce,
    String? plaintextSha256,
    String? ciphertextSha256,
    String? associatedDataSha256,
  }) {
    return MigrationEncryptedChunk(
      entryId: entryId ?? this.entryId,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      offset: offset ?? this.offset,
      isFinal: isFinal ?? this.isFinal,
      kemCiphertext: kemCiphertext ?? this.kemCiphertext,
      ciphertext: ciphertext ?? this.ciphertext,
      nonce: nonce ?? this.nonce,
      plaintextSha256: plaintextSha256 ?? this.plaintextSha256,
      ciphertextSha256: ciphertextSha256 ?? this.ciphertextSha256,
      associatedDataSha256:
          associatedDataSha256 ?? this.associatedDataSha256,
    );
  }
}

class MigrationStreamCryptoException implements Exception {
  final String message;

  const MigrationStreamCryptoException(this.message);

  @override
  String toString() => 'MigrationStreamCryptoException($message)';
}

abstract class MigrationStreamCrypto {
  Future<MigrationStreamEncryptSession> encapsulateSession({
    required String recipientMlKemPublicKey,
    required String sessionId,
    required String bundleId,
    required MigrationStreamDirection direction,
  });

  Future<MigrationStreamDecryptSession> decapsulateSession({
    required String ownMlKemSecretKey,
    required String sessionId,
    required String bundleId,
    required MigrationStreamDirection direction,
    required String kemCiphertext,
  });

  Future<MigrationEncryptedChunk> encryptChunk({
    required MigrationStreamEncryptSession session,
    required Uint8List plaintext,
    required MigrationChunkAssociatedData associatedData,
    required String nonce,
  });

  Future<Uint8List> decryptChunk({
    required MigrationStreamDecryptSession session,
    required MigrationEncryptedChunk encryptedChunk,
    required MigrationChunkAssociatedData associatedData,
  });
}

String migrationChunkNonceBase64({
  required int entryOrdinal,
  required int chunkIndex,
}) {
  if (entryOrdinal < 0 || chunkIndex < 0) {
    throw const MigrationStreamCryptoException('negative nonce counter');
  }
  final bytes = Uint8List(12);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, entryOrdinal);
  data.setUint64(4, chunkIndex);
  return base64Encode(bytes);
}

class BridgeMigrationStreamCrypto implements MigrationStreamCrypto {
  final Bridge bridge;
  final MigrationChunkWorkExecutor executeChunkWork;

  const BridgeMigrationStreamCrypto({
    required this.bridge,
    this.executeChunkWork = migrationIsolateChunkWorkExecutor,
  });

  @override
  Future<MigrationStreamEncryptSession> encapsulateSession({
    required String recipientMlKemPublicKey,
    required String sessionId,
    required String bundleId,
    required MigrationStreamDirection direction,
  }) async {
    final response = await _sendMigrationCryptoCommand(
      bridge,
      'migration.session.encap',
      {
        'recipientPublicKey': recipientMlKemPublicKey,
        'sessionId': sessionId,
        'bundleId': bundleId,
        'direction': direction.wireValue,
      },
    );
    if (response['ok'] != true) {
      throw MigrationStreamCryptoException(
        response['errorMessage']?.toString() ?? 'session encapsulation failed',
      );
    }
    final sessionKey = response['sessionKey'];
    final kemCiphertext = response['kemCiphertext'];
    if (sessionKey is! String ||
        sessionKey.isEmpty ||
        kemCiphertext is! String ||
        kemCiphertext.isEmpty) {
      throw const MigrationStreamCryptoException(
        'session encapsulation returned incomplete bridge response',
      );
    }
    return MigrationStreamEncryptSession(
      sessionId: sessionId,
      bundleId: bundleId,
      direction: direction,
      sessionKey: sessionKey,
      kemCiphertext: kemCiphertext,
    );
  }

  @override
  Future<MigrationStreamDecryptSession> decapsulateSession({
    required String ownMlKemSecretKey,
    required String sessionId,
    required String bundleId,
    required MigrationStreamDirection direction,
    required String kemCiphertext,
  }) async {
    final response = await _sendMigrationCryptoCommand(
      bridge,
      'migration.session.decap',
      {
        'secretKey': ownMlKemSecretKey,
        'kemCiphertext': kemCiphertext,
        'sessionId': sessionId,
        'bundleId': bundleId,
        'direction': direction.wireValue,
      },
    );
    if (response['ok'] != true) {
      throw MigrationStreamCryptoException(
        response['errorMessage']?.toString() ?? 'session decapsulation failed',
      );
    }
    final sessionKey = response['sessionKey'];
    if (sessionKey is! String || sessionKey.isEmpty) {
      throw const MigrationStreamCryptoException(
        'session decapsulation returned incomplete bridge response',
      );
    }
    return MigrationStreamDecryptSession(
      sessionId: sessionId,
      bundleId: bundleId,
      direction: direction,
      sessionKey: sessionKey,
      kemCiphertext: kemCiphertext,
    );
  }

  @override
  Future<MigrationEncryptedChunk> encryptChunk({
    required MigrationStreamEncryptSession session,
    required Uint8List plaintext,
    required MigrationChunkAssociatedData associatedData,
    required String nonce,
  }) async {
    _assertSessionMatches(session, associatedData);
    final aad = associatedData.toCanonicalJson();
    final (plaintextBase64, plaintextSha256) = await executeChunkWork(
      () => (base64Encode(plaintext), migrationTransferSha256Hex(plaintext)),
    );
    final response = await _sendMigrationCryptoCommand(
      bridge,
      'migration.chunk.encrypt',
      {
        'sessionKey': session.sessionKey,
        'plaintextBase64': plaintextBase64,
        'aad': aad,
        'nonce': nonce,
      },
    );
    if (response['ok'] != true) {
      throw MigrationStreamCryptoException(
        response['errorMessage']?.toString() ?? 'chunk encryption failed',
      );
    }
    final ciphertext = response['ciphertext'];
    final responseNonce = response['nonce'];
    if (ciphertext is! String ||
        ciphertext.isEmpty ||
        responseNonce is! String ||
        responseNonce.isEmpty) {
      throw const MigrationStreamCryptoException(
        'chunk encryption returned incomplete bridge response',
      );
    }
    final ciphertextSha256 = await executeChunkWork(
      () => migrationTransferStringSha256Hex(ciphertext),
    );
    return MigrationEncryptedChunk(
      entryId: associatedData.entryId,
      chunkIndex: associatedData.chunkIndex,
      offset: associatedData.offset,
      isFinal: associatedData.isFinal,
      kemCiphertext: session.kemCiphertext,
      ciphertext: ciphertext,
      nonce: responseNonce,
      plaintextSha256: plaintextSha256,
      ciphertextSha256: ciphertextSha256,
      associatedDataSha256: associatedData.sha256Hex,
    );
  }

  @override
  Future<Uint8List> decryptChunk({
    required MigrationStreamDecryptSession session,
    required MigrationEncryptedChunk encryptedChunk,
    required MigrationChunkAssociatedData associatedData,
  }) async {
    _assertSessionMatches(session, associatedData);
    if (encryptedChunk.entryId != associatedData.entryId ||
        encryptedChunk.chunkIndex != associatedData.chunkIndex ||
        encryptedChunk.offset != associatedData.offset ||
        encryptedChunk.isFinal != associatedData.isFinal ||
        encryptedChunk.associatedDataSha256 != associatedData.sha256Hex) {
      throw const MigrationStreamCryptoException('chunk AAD mismatch');
    }
    if (encryptedChunk.kemCiphertext != session.kemCiphertext) {
      throw const MigrationStreamCryptoException('chunk KEM mismatch');
    }
    final ciphertext = encryptedChunk.ciphertext;
    final ciphertextSha256 = await executeChunkWork(
      () => migrationTransferStringSha256Hex(ciphertext),
    );
    if (encryptedChunk.ciphertextSha256 != ciphertextSha256) {
      throw const MigrationStreamCryptoException('chunk ciphertext tampered');
    }
    if (!session.markDecrypted(associatedData)) {
      throw const MigrationStreamCryptoException('chunk replay rejected');
    }
    final response = await _sendMigrationCryptoCommand(
      bridge,
      'migration.chunk.decrypt',
      {
        'sessionKey': session.sessionKey,
        'ciphertext': encryptedChunk.ciphertext,
        'aad': associatedData.toCanonicalJson(),
        'nonce': encryptedChunk.nonce,
      },
    );
    if (response['ok'] != true) {
      throw MigrationStreamCryptoException(
        response['errorMessage']?.toString() ?? 'chunk decryption failed',
      );
    }
    final plaintextBase64 = response['plaintextBase64'];
    if (plaintextBase64 is! String || plaintextBase64.isEmpty) {
      throw const MigrationStreamCryptoException(
        'chunk decryption returned empty plaintext',
      );
    }
    final (plaintext, plaintextSha256) = await executeChunkWork(() {
      final bytes = Uint8List.fromList(base64Decode(plaintextBase64));
      return (bytes, migrationTransferSha256Hex(bytes));
    });
    if (plaintextSha256 != encryptedChunk.plaintextSha256) {
      throw const MigrationStreamCryptoException('chunk plaintext tampered');
    }
    return plaintext;
  }

  void _assertSessionMatches(
    Object session,
    MigrationChunkAssociatedData associatedData,
  ) {
    final String sessionId;
    final String bundleId;
    if (session is MigrationStreamEncryptSession) {
      sessionId = session.sessionId;
      bundleId = session.bundleId;
    } else if (session is MigrationStreamDecryptSession) {
      sessionId = session.sessionId;
      bundleId = session.bundleId;
    } else {
      throw const MigrationStreamCryptoException('unknown session type');
    }
    if (sessionId != associatedData.sessionId ||
        bundleId != associatedData.bundleId) {
      throw const MigrationStreamCryptoException('chunk session mismatch');
    }
  }
}

Future<Map<String, dynamic>> _sendMigrationCryptoCommand(
  Bridge bridge,
  String command,
  Map<String, Object?> payload,
) async {
  final responseJson = await bridge.send(
    jsonEncode({'cmd': command, 'payload': payload}),
  );
  return jsonDecode(responseJson) as Map<String, dynamic>;
}

class MigrationEncryptedSegment {
  final int index;
  final String kem;
  final String ciphertext;
  final String nonce;
  final String plaintextSha256;
  final String ciphertextSha256;
  final String associatedDataSha256;

  const MigrationEncryptedSegment({
    required this.index,
    required this.kem,
    required this.ciphertext,
    required this.nonce,
    required this.plaintextSha256,
    required this.ciphertextSha256,
    required this.associatedDataSha256,
  });
}

class MigrationSegmentCryptoException implements Exception {
  final String message;

  const MigrationSegmentCryptoException(this.message);

  @override
  String toString() => 'MigrationSegmentCryptoException($message)';
}

abstract class MigrationSegmentCrypto {
  Future<MigrationEncryptedSegment> encryptSegment({
    required Uint8List plaintext,
    required String recipientMlKemPublicKey,
    required MigrationSegmentAssociatedData associatedData,
  });

  Future<Uint8List> decryptSegment({
    required MigrationEncryptedSegment encryptedSegment,
    required String ownMlKemSecretKey,
    required MigrationSegmentAssociatedData associatedData,
  });
}

class BridgeMigrationSegmentCrypto implements MigrationSegmentCrypto {
  final Bridge bridge;

  const BridgeMigrationSegmentCrypto({required this.bridge});

  @override
  Future<MigrationEncryptedSegment> encryptSegment({
    required Uint8List plaintext,
    required String recipientMlKemPublicKey,
    required MigrationSegmentAssociatedData associatedData,
  }) async {
    final payload = migrationTransferCanonicalJson({
      'associated_data': associatedData.toJson(),
      'segment_base64': base64Encode(plaintext),
    });
    final response = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      plaintext: payload,
    );
    if (response['ok'] != true) {
      throw MigrationSegmentCryptoException(
        response['errorMessage']?.toString() ?? 'segment encryption failed',
      );
    }

    final kem = response['kem'];
    final ciphertext = response['ciphertext'];
    final nonce = response['nonce'];
    if (kem is! String ||
        kem.trim().isEmpty ||
        ciphertext is! String ||
        ciphertext.trim().isEmpty ||
        nonce is! String ||
        nonce.trim().isEmpty) {
      throw const MigrationSegmentCryptoException(
        'segment encryption returned incomplete bridge response',
      );
    }

    return MigrationEncryptedSegment(
      index: associatedData.segmentIndex,
      kem: kem,
      ciphertext: ciphertext,
      nonce: nonce,
      plaintextSha256: migrationTransferSha256Hex(plaintext),
      ciphertextSha256: migrationTransferStringSha256Hex(ciphertext),
      associatedDataSha256: associatedData.sha256Hex,
    );
  }

  @override
  Future<Uint8List> decryptSegment({
    required MigrationEncryptedSegment encryptedSegment,
    required String ownMlKemSecretKey,
    required MigrationSegmentAssociatedData associatedData,
  }) async {
    final stopwatch = Stopwatch()..start();
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_SEGMENT_DECRYPT_START',
      details: {
        'sessionId': associatedData.sessionId,
        'bundleId': associatedData.bundleId,
        'segmentIndex': associatedData.segmentIndex,
        'payloadBytes': encryptedSegment.ciphertext.length,
      },
    );

    Never fail(String reason, String message, {String? errorCode}) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_SEGMENT_DECRYPT_FAILED',
        details: {
          'sessionId': associatedData.sessionId,
          'segmentIndex': associatedData.segmentIndex,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'reason': reason,
          'errorCode': errorCode,
        },
      );
      throw MigrationSegmentCryptoException(message);
    }

    if (encryptedSegment.associatedDataSha256 != associatedData.sha256Hex) {
      fail('associatedDataMismatch', 'segment associated data mismatch');
    }
    if (encryptedSegment.ciphertextSha256 !=
        migrationTransferStringSha256Hex(encryptedSegment.ciphertext)) {
      fail('checksumMismatch', 'segment ciphertext checksum mismatch');
    }

    final response = await callDecryptMessage(
      bridge: bridge,
      ownMlKemSecretKey: ownMlKemSecretKey,
      kem: encryptedSegment.kem,
      ciphertext: encryptedSegment.ciphertext,
      nonce: encryptedSegment.nonce,
    );
    if (response['ok'] != true) {
      final errorCode = response['errorCode']?.toString();
      fail(
        errorCode == 'BRIDGE_TIMEOUT' ? 'bridgeTimeout' : 'bridgeRejected',
        response['errorMessage']?.toString() ?? 'segment decryption failed',
        errorCode: errorCode,
      );
    }
    final plaintext = response['plaintext'];
    if (plaintext is! String || plaintext.trim().isEmpty) {
      fail('emptyBridgeResult', 'segment decryption returned empty plaintext');
    }

    final decoded = jsonDecode(plaintext);
    if (decoded is! Map<String, dynamic>) {
      fail('envelopeMalformed', 'segment plaintext envelope is malformed');
    }
    final actualAssociatedData = migrationTransferCanonicalJson(
      decoded['associated_data'],
    );
    if (actualAssociatedData != associatedData.toCanonicalJson()) {
      fail(
        'envelopeAssociatedDataMismatch',
        'segment plaintext associated data mismatch',
      );
    }
    final segmentBase64 = decoded['segment_base64'];
    if (segmentBase64 is! String || segmentBase64.trim().isEmpty) {
      fail('missingPayloadBytes', 'segment plaintext is missing payload bytes');
    }

    final bytes = Uint8List.fromList(base64Decode(segmentBase64));
    if (migrationTransferSha256Hex(bytes) != encryptedSegment.plaintextSha256) {
      fail('payloadChecksumMismatch', 'segment plaintext checksum mismatch');
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_SEGMENT_DECRYPT_DONE',
      details: {
        'sessionId': associatedData.sessionId,
        'segmentIndex': associatedData.segmentIndex,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      },
    );
    return bytes;
  }
}
