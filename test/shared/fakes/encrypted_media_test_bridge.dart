import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';

import '../../core/bridge/fake_bridge.dart';

/// Content-transforming blob-crypto bridge shared by the posts media
/// encryption suites (doc 113).
///
/// Extracted from `post_pass_encrypted_media_integration_test.dart` with two
/// deliberate fidelity fixes over the in-file original (which was key-blind):
/// - `blob:keygen` mints a DISTINCT key per call (the original returned one
///   static key forever), so distinct-key-per-attachment and
///   fresh-key-on-retry assertions are meaningful.
/// - `blob:encrypt`/`blob:decrypt` XOR with the PAYLOAD-PROVIDED key/nonce
///   (the original ignored `keyBase64` and used the static key), so a wrong
///   or stale key produces garbage instead of silently round-tripping.
///
/// Never use the shared [FakeBridge]/[PassthroughCryptoBridge] `blob:encrypt`
/// for ciphertext-content or hash-provenance assertions — it copies bytes
/// unchanged.
class EncryptedMediaTestBridge extends PassthroughCryptoBridge {
  final RelayMediaStore relayStore;

  /// Restores the legacy single-static-key behavior for consumer suites whose
  /// assertions depend on keygen determinism. Leave false everywhere else.
  final bool fixedKeyMode;

  /// Offsets the deterministic key/nonce sequence so two bridge instances
  /// (e.g. two users in one test) never mint identical keys.
  final int seedSalt;

  bool failBlobKeygen = false;
  bool failBlobEncrypt = false;
  bool failBlobDecrypt = false;
  bool failMediaUpload = false;
  bool failMediaDownload = false;

  int _keygenCounter = 0;
  int _nonceCounter = 0;

  EncryptedMediaTestBridge(
    this.relayStore, {
    this.fixedKeyMode = false,
    this.seedSalt = 0,
  });

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == null) {
      return super.send(message);
    }

    switch (cmd) {
      case 'blob:keygen':
        _record(message, cmd);
        if (failBlobKeygen) {
          return jsonEncode({
            'ok': false,
            'errorMessage': 'blob keygen unavailable',
          });
        }
        final seed = fixedKeyMode ? 0 : seedSalt + _keygenCounter++;
        return jsonEncode({
          'ok': true,
          'keyBase64': base64Encode(deriveTestBlobKey(seed)),
        });
      case 'blob:encrypt':
        _record(message, cmd);
        if (failBlobEncrypt) {
          return jsonEncode({
            'ok': false,
            'errorMessage': 'blob encrypt unavailable',
          });
        }
        final payload = parsed['payload'] as Map<String, dynamic>;
        final filePath = payload['filePath'] as String;
        final keyBase64 = payload['keyBase64'] as String;
        final nonce = deriveTestBlobNonce(
          fixedKeyMode ? 0 : seedSalt + _nonceCounter++,
        );
        final plaintext = File(filePath).readAsBytesSync();
        final encryptedPath = '$filePath.enc';
        File(encryptedPath).writeAsBytesSync(
          xorWithKeyAndNonce(plaintext, base64Decode(keyBase64), nonce),
          flush: true,
        );
        return jsonEncode({
          'ok': true,
          'encryptedPath': encryptedPath,
          'nonce': base64Encode(nonce),
        });
      case 'blob:decrypt':
        _record(message, cmd);
        if (failBlobDecrypt) {
          return jsonEncode({
            'ok': false,
            'errorMessage': 'blob decrypt unavailable',
          });
        }
        final payload = parsed['payload'] as Map<String, dynamic>;
        final filePath = payload['filePath'] as String;
        final keyBase64 = payload['keyBase64'] as String;
        final nonceBase64 = payload['nonce'] as String;
        final ciphertext = File(filePath).readAsBytesSync();
        final decryptedPath = '$filePath.dec';
        File(decryptedPath).writeAsBytesSync(
          xorWithKeyAndNonce(
            ciphertext,
            base64Decode(keyBase64),
            base64Decode(nonceBase64),
          ),
          flush: true,
        );
        return jsonEncode({'ok': true, 'decryptedPath': decryptedPath});
      case 'media:upload':
        _record(message, cmd);
        if (failMediaUpload) {
          return jsonEncode({
            'ok': false,
            'errorMessage': 'media upload unavailable',
          });
        }
        final payload = parsed['payload'] as Map<String, dynamic>;
        final blobId = payload['id'] as String;
        final filePath = payload['filePath'] as String;
        final allowedPeers =
            (payload['allowedPeers'] as List<dynamic>? ?? const [])
                .map((value) => value.toString())
                .toList(growable: false);
        final mime = payload['mime'] as String;
        relayStore.uploadedBytesByBlobId[blobId] =
            File(filePath).readAsBytesSync();
        relayStore.allowedPeersByBlobId[blobId] = allowedPeers;
        relayStore.mimeByBlobId[blobId] = mime;
        return jsonEncode({'ok': true, 'id': blobId});
      case 'media:download':
        _record(message, cmd);
        if (failMediaDownload) {
          return jsonEncode({
            'ok': false,
            'errorMessage': 'media download unavailable',
          });
        }
        final payload = parsed['payload'] as Map<String, dynamic>;
        final blobId = payload['id'] as String;
        final outputPath = payload['outputPath'] as String;
        final bytes = relayStore.uploadedBytesByBlobId[blobId];
        if (bytes == null) {
          return jsonEncode({'ok': false, 'errorMessage': 'blob not found'});
        }
        File(outputPath).writeAsBytesSync(bytes, flush: true);
        return jsonEncode({
          'ok': true,
          'id': blobId,
          'mime': relayStore.mimeByBlobId[blobId] ?? 'application/octet-stream',
          'size': bytes.length,
        });
      case 'media:delete':
        _record(message, cmd);
        relayStore.deletedBlobIds.add(
          (parsed['payload'] as Map<String, dynamic>)['id'] as String,
        );
        return jsonEncode({'ok': true});
      default:
        return super.send(message);
    }
  }

  void _record(String message, String cmd) {
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;
    commandLog.add(cmd);
  }
}

/// Captures what an encrypted-media test "relay" has stored, keyed by blobId.
class RelayMediaStore {
  final Map<String, List<int>> uploadedBytesByBlobId = <String, List<int>>{};
  final Map<String, List<String>> allowedPeersByBlobId =
      <String, List<String>>{};
  final Map<String, String> mimeByBlobId = <String, String>{};
  final List<String> deletedBlobIds = <String>[];

  Iterable<String> get blobIds => uploadedBytesByBlobId.keys;
  Map<String, List<int>> get ciphertextByBlobId => uploadedBytesByBlobId;
}

/// Temp-dir [MediaFileManager] for posts attachments (no path_provider).
class TempPostMediaFileManager extends MediaFileManager {
  final String baseDir;

  TempPostMediaFileManager(this.baseDir);

  @override
  Future<String> localPathForPostAttachment({
    required String postId,
    required String blobId,
    required String mime,
  }) async {
    final relative = MediaFilePathConvention.relativePathForPostAttachment(
      postId: postId,
      blobId: blobId,
      mime: mime,
    );
    final file = File('$baseDir/$relative');
    file.parent.createSync(recursive: true);
    return file.path;
  }

  @override
  String relativePathForPostAttachment({
    required String postId,
    required String blobId,
    required String mime,
  }) {
    return MediaFilePathConvention.relativePathForPostAttachment(
      postId: postId,
      blobId: blobId,
      mime: mime,
    );
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('post_media/')) {
      return '$baseDir/$storedPath';
    }
    return storedPath;
  }
}

Uint8List deriveTestBlobKey(int seed) {
  return Uint8List.fromList(
    List<int>.generate(32, (index) => (index * 7 + 11 + seed * 31) & 0xff),
  );
}

Uint8List deriveTestBlobNonce(int seed) {
  return Uint8List.fromList(
    List<int>.generate(12, (index) => (index * 13 + 3 + seed * 29) & 0xff),
  );
}

Uint8List xorWithKeyAndNonce(List<int> input, List<int> key, List<int> nonce) {
  return Uint8List.fromList(
    List<int>.generate(
      input.length,
      (index) =>
          input[index] ^
          key[index % key.length] ^
          nonce[index % nonce.length],
    ),
  );
}
