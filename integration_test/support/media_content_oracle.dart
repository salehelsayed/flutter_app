import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

/// Test-only evidence. It neither downloads/opens media nor grants authority.
/// Native crypto, transport, current SQL policy and viewers remain their owners.
class MediaOracleFailure implements Exception {
  const MediaOracleFailure(this.code);
  final String code;
  @override
  String toString() => 'MediaOracleFailure($code)';
}

class MediaFileFingerprint {
  const MediaFileFingerprint._(this.bytes, this.sha256Hex);
  final int bytes;
  final String sha256Hex;
  Map<String, Object> toJson() => {'bytes': bytes, 'sha256': sha256Hex};
  bool sameBytes(MediaFileFingerprint other) =>
      bytes == other.bytes && sha256Hex == other.sha256Hex;
}

/// Stream the whole regular file; never substitute a thumbnail/prefix/stat.
Future<MediaFileFingerprint> fingerprintMediaFile(File input) async {
  try {
    final file = File(await input.resolveSymbolicLinks());
    final before = await file.stat();
    if (before.type != FileSystemEntityType.file || before.size <= 0) {
      throw const MediaOracleFailure('EMPTY_OR_NON_FILE');
    }
    var readBytes = 0;
    final digest = await sha256
        .bind(
          file.openRead().map((chunk) {
            readBytes += chunk.length;
            return chunk;
          }),
        )
        .first;
    final after = await file.stat();
    if (before.size != after.size ||
        before.modified != after.modified ||
        readBytes != before.size) {
      throw const MediaOracleFailure('FILE_CHANGED_DURING_HASH');
    }
    return MediaFileFingerprint._(readBytes, digest.toString());
  } on MediaOracleFailure {
    rethrow;
  } catch (_) {
    throw const MediaOracleFailure('FILE_UNREADABLE');
  }
}

class MediaWireIdentity {
  MediaWireIdentity({
    required this.runId,
    required this.owner,
    required this.messageId,
    required this.attachmentId,
  }) {
    if (runId.trim().isEmpty ||
        messageId.trim().isEmpty ||
        attachmentId.trim().isEmpty) {
      throw const MediaOracleFailure('INCOMPLETE_IDENTITY');
    }
  }
  final MediaOwnerLane owner;
  final String runId;
  final String messageId;
  final String attachmentId;
  String get digest => sha256
      .convert(
        utf8.encode(jsonEncode([runId, owner.name, messageId, attachmentId])),
      )
      .toString();
  bool matches(MediaAttachment row) =>
      row.ownerLane == owner &&
      row.messageId == messageId &&
      row.id == attachmentId;
  @override
  String toString() => 'MediaWireIdentity(redacted)';
}

class EncryptedMediaSourceCapture {
  const EncryptedMediaSourceCapture._(
    this.plaintext,
    this.ciphertext,
    this.runtimePlatform,
  );
  final MediaFileFingerprint plaintext;
  final MediaFileFingerprint ciphertext;
  final String runtimePlatform;
  static const boundary = 'actual blob:encrypt payload.filePath';
  Map<String, Object> toJson() => {
    'boundary': boundary,
    'plaintext': plaintext.toJson(),
    'ciphertext': ciphertext.toJson(),
    'runtime_platform': runtimePlatform,
  };
}

/// Observe the EXACT file passed to native encryption, after processing and
/// durable preparation. Original quality is still allowed to alter the file.
///
/// The native invocation/response/exception pass through unchanged, once. An
/// observation error is retained as a detail-free failure; it cannot turn a
/// native success into an application failure. A later required capture fails
/// the test if this observer could not establish its evidence.
class MediaEncryptionInputObserver {
  final _captures = <String, EncryptedMediaSourceCapture>{};
  final _conflicted = <String>{};
  final _failures = <String>[];
  List<String> get failures => List.unmodifiable(_failures);
  int get captureCount => _captures.length;

  Future<String> observe(
    String request,
    Future<String> Function() invokeNative,
  ) async {
    String? path;
    try {
      final decoded = jsonDecode(request);
      if (decoded is Map && decoded['cmd'] == 'blob:encrypt') {
        final payload = decoded['payload'];
        if (payload is Map &&
            payload['filePath'] is String &&
            (payload['filePath'] as String).isNotEmpty) {
          path = payload['filePath'] as String;
        }
      }
    } catch (_) {
      /* Non-JSON commands are transparent. */
    }
    if (path == null) return invokeNative();
    MediaFileFingerprint? before;
    try {
      before = await fingerprintMediaFile(File(path));
    } on MediaOracleFailure catch (error) {
      _failures.add(error.code);
    }
    final response = await invokeNative();
    try {
      final decoded = jsonDecode(response);
      if (decoded is! Map || decoded['ok'] != true) return response;
      if (before == null || decoded['encryptedPath'] is! String) {
        throw const MediaOracleFailure('ENCRYPTION_CAPTURE_INCOMPLETE');
      }
      final after = await fingerprintMediaFile(File(path));
      if (!before.sameBytes(after)) {
        throw const MediaOracleFailure('ENCRYPTION_INPUT_CHANGED');
      }
      final cipher = await fingerprintMediaFile(
        File(decoded['encryptedPath'] as String),
      );
      // The current blob AES-GCM contract appends a 16-byte tag.
      if (cipher.bytes != before.bytes + 16) {
        throw const MediaOracleFailure('ENCRYPTED_SIZE_CONTRACT_MISMATCH');
      }
      final previous = _captures[cipher.sha256Hex];
      if (_conflicted.contains(cipher.sha256Hex) ||
          (previous != null && !previous.plaintext.sameBytes(before))) {
        _captures.remove(cipher.sha256Hex);
        _conflicted.add(cipher.sha256Hex);
        throw const MediaOracleFailure('CONFLICTING_CIPHERTEXT_CAPTURE');
      }
      _captures[cipher.sha256Hex] = EncryptedMediaSourceCapture._(
        before,
        cipher,
        Platform.operatingSystem,
      );
    } on MediaOracleFailure catch (error) {
      _failures.add(error.code);
    } catch (_) {
      _failures.add('ENCRYPTION_CAPTURE_INCOMPLETE');
    }
    return response;
  }

  SentMediaBinding bindSentRow(
    MediaAttachment row,
    MediaWireIdentity identity,
  ) {
    if (!identity.matches(row)) {
      throw const MediaOracleFailure('SENT_IDENTITY_MISMATCH');
    }
    final capture = _captures[row.contentHash?.toLowerCase()];
    if (capture == null) {
      throw const MediaOracleFailure('ACTUAL_SENT_SOURCE_NOT_CAPTURED');
    }
    if (row.size != capture.plaintext.bytes) {
      throw const MediaOracleFailure('SENT_PLAINTEXT_SIZE_MISMATCH');
    }
    return SentMediaBinding._(identity, capture, row.mime.trim().toLowerCase());
  }
}

class SentMediaBinding {
  const SentMediaBinding._(this.identity, this.source, this.mime);
  final MediaWireIdentity identity;
  final EncryptedMediaSourceCapture source;
  final String mime;

  /// Redacted cross-process artifact. Pin its digest from the actual sender
  /// through the owned test driver. It is test provenance, not attestation of
  /// remotely supplied metadata or an arbitrary native delegate's correctness.
  Map<String, Object> toSenderReceipt() => {
    'schema': 1,
    'identity_sha256': identity.digest,
    'mime': mime,
    'source': source.toJson(),
  };
  String get senderReceiptSha256 => _receiptDigest(toSenderReceipt());

  static SentMediaBinding fromSenderReceipt({
    required Map<String, Object?> receipt,
    required String expectedReceiptSha256,
    required MediaWireIdentity expectedIdentity,
  }) {
    try {
      bool keys(Map value, Set<String> expected) =>
          value.keys.toSet().containsAll(expected) &&
          value.length == expected.length;
      if (_receiptDigest(receipt) != expectedReceiptSha256 ||
          !keys(receipt, {'schema', 'identity_sha256', 'mime', 'source'}) ||
          receipt['schema'] != 1 ||
          receipt['identity_sha256'] != expectedIdentity.digest ||
          receipt['mime'] is! String ||
          (receipt['mime'] as String).trim().isEmpty) {
        throw const MediaOracleFailure('SENDER_RECEIPT_NOT_PINNED');
      }
      final source = receipt['source'];
      if (source is! Map ||
          !keys(source, {
            'boundary',
            'plaintext',
            'ciphertext',
            'runtime_platform',
          }) ||
          source['boundary'] != EncryptedMediaSourceCapture.boundary ||
          source['runtime_platform'] is! String) {
        throw const MediaOracleFailure('SENDER_CAPTURE_BOUNDARY_INVALID');
      }
      MediaFileFingerprint read(Object? value) {
        if (value is! Map ||
            !keys(value, {'bytes', 'sha256'}) ||
            value['bytes'] is! int ||
            (value['bytes'] as int) <= 0 ||
            value['sha256'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(value['sha256'] as String)) {
          throw const MediaOracleFailure('SENDER_FINGERPRINT_INVALID');
        }
        return MediaFileFingerprint._(
          value['bytes'] as int,
          value['sha256'] as String,
        );
      }

      final plain = read(source['plaintext']);
      final cipher = read(source['ciphertext']);
      if (cipher.bytes != plain.bytes + 16) {
        throw const MediaOracleFailure('ENCRYPTED_SIZE_CONTRACT_MISMATCH');
      }
      return SentMediaBinding._(
        expectedIdentity,
        EncryptedMediaSourceCapture._(
          plain,
          cipher,
          source['runtime_platform'] as String,
        ),
        (receipt['mime'] as String).trim().toLowerCase(),
      );
    } on MediaOracleFailure {
      rethrow;
    } catch (_) {
      throw const MediaOracleFailure('SENDER_RECEIPT_INVALID');
    }
  }
}

String _receiptDigest(Object? value) {
  Object? canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: canonical(v[key])};
    }
    if (v is List) return v.map(canonical).toList();
    return v;
  }

  return sha256.convert(utf8.encode(jsonEncode(canonical(value)))).toString();
}

class MediaByteEquality {
  const MediaByteEquality._(this.sent, this.receiver, this.qualifiedPath);
  final SentMediaBinding sent;
  final MediaFileFingerprint receiver;

  /// Local-only: never serialize/mail a peer-bearing filesystem path.
  final String qualifiedPath;
  Map<String, Object> toJson() => {
    'identity_sha256': sent.identity.digest,
    'source': sent.source.toJson(),
    'receiver_plaintext': receiver.toJson(),
    'mime': sent.mime,
    'sender_receipt_sha256': sent.senderReceiptSha256,
    'byte_gate': 'PASS',
    'native_gate': 'NOT_RUN',
  };
}

/// [assertCurrentReadAuthority] MUST use current parent/row authority. For a
/// private item call this only inside its actual protected viewer grant, before
/// first-frame consumption. No independent unprotected player/file export.
Future<MediaByteEquality> verifyReceivedMediaBytes({
  required SentMediaBinding sent,
  required Future<MediaAttachment?> Function() loadCurrentReceivedRow,
  required Future<void> Function(MediaAttachment row)
  assertCurrentReadAuthority,
  required Future<String> Function(String storedPath) resolveStoredPath,
}) async {
  Future<MediaAttachment> current() async {
    final row = await loadCurrentReceivedRow();
    if (row == null || !sent.identity.matches(row)) {
      throw const MediaOracleFailure('RECEIVER_IDENTITY_MISMATCH');
    }
    if (row.downloadStatus != 'done' ||
        row.localPath == null ||
        row.contentHash?.toLowerCase() != sent.source.ciphertext.sha256Hex ||
        row.size != sent.source.plaintext.bytes ||
        row.mime.trim().toLowerCase() != sent.mime) {
      throw const MediaOracleFailure('RECEIVER_NOT_CURRENT_COMPLETE_FILE');
    }
    await assertCurrentReadAuthority(row);
    return row;
  }

  final before = await current();
  final path = await resolveStoredPath(before.localPath!);
  final received = await fingerprintMediaFile(File(path));
  final after = await current();
  if (before.localPath != after.localPath ||
      path != await resolveStoredPath(after.localPath!)) {
    throw const MediaOracleFailure('RECEIVER_PATH_CHANGED');
  }
  if (!sent.source.plaintext.sameBytes(received)) {
    throw const MediaOracleFailure('RECEIVER_PLAINTEXT_MISMATCH');
  }
  return MediaByteEquality._(sent, received, path);
}

enum NativeMediaOpenKind {
  decodedImage,
  renderedVideo,
  playedAudio,
  renderedPdf,
}

/// Structured observations returned by a REVIEWED existing native assertion,
/// never a nativePlayed=true flag. This is test evidence, not attestation of an
/// arbitrary delegate's correctness. The runbook names each required observer.
class NativeMediaOpenObservation {
  const NativeMediaOpenObservation({
    required this.kind,
    required this.identitySha256,
    required this.plaintextSha256,
    required this.nativeBackend,
    required this.proofArtifact,
    this.width,
    this.height,
    this.startPositionMs,
    this.endPositionMs,
    this.durationMs,
    this.renderedPages,
  });
  final NativeMediaOpenKind kind;
  final String identitySha256;
  final String plaintextSha256;
  final String nativeBackend;
  final File proofArtifact;
  final int? width,
      height,
      startPositionMs,
      endPositionMs,
      durationMs,
      renderedPages;
}

/// The callback executes real native assertions in the existing campaign. A
/// host, byte-only result, stale identity, metadata-only video, or presented-only
/// PDF cannot pass this gate. Private owners retain their normal settle rules;
/// the file is deliberately not reread after a view-once open consumes it.
Future<Map<String, Object>> verifyNativeMediaOpen({
  required MediaByteEquality equality,
  required String observerCase,
  required Future<void> Function() assertCurrentOpenAuthority,
  required Future<NativeMediaOpenObservation> Function(MediaByteEquality proof)
  assertNativeOpen,
}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    throw const MediaOracleFailure('NATIVE_TARGET_REQUIRED');
  }
  if (!{'android', 'ios'}.contains(equality.sent.source.runtimePlatform)) {
    throw const MediaOracleFailure('NATIVE_SOURCE_REQUIRED');
  }
  if (observerCase.trim().isEmpty) {
    throw const MediaOracleFailure('NATIVE_OBSERVER_UNIDENTIFIED');
  }
  await assertCurrentOpenAuthority();
  final atOpen = await fingerprintMediaFile(File(equality.qualifiedPath));
  if (!atOpen.sameBytes(equality.receiver)) {
    throw const MediaOracleFailure('RECEIVER_CHANGED_BEFORE_NATIVE_OPEN');
  }
  final observed = await assertNativeOpen(equality);
  validateNativeMediaObservation(equality, observed);
  final artifact = await fingerprintMediaFile(observed.proofArtifact);
  return {
    ...equality.toJson(),
    'native_gate': 'PASS_EXISTING_ASSERTION',
    'native_platform': Platform.operatingSystem,
    'observer_case': observerCase,
    'native_kind': observed.kind.name,
    'native_backend': observed.nativeBackend,
    'native_artifact': artifact.toJson(),
    if (observed.width != null) 'decoded_width': observed.width!,
    if (observed.height != null) 'decoded_height': observed.height!,
    if (observed.durationMs != null) 'duration_ms': observed.durationMs!,
    if (observed.startPositionMs != null)
      'start_position_ms': observed.startPositionMs!,
    if (observed.endPositionMs != null)
      'end_position_ms': observed.endPositionMs!,
    if (observed.renderedPages != null)
      'rendered_pages': observed.renderedPages!,
  };
}

/// Pure structural validation is host-testable. It does not execute a native
/// probe or turn an external receipt into native proof on a host.
void validateNativeMediaObservation(
  MediaByteEquality equality,
  NativeMediaOpenObservation observed,
) {
  if (observed.identitySha256 != equality.sent.identity.digest ||
      observed.plaintextSha256 != equality.receiver.sha256Hex ||
      observed.nativeBackend.trim().isEmpty) {
    throw const MediaOracleFailure('NATIVE_OBSERVATION_NOT_BOUND_TO_FILE');
  }
  final image = observed.kind == NativeMediaOpenKind.decodedImage;
  final video = observed.kind == NativeMediaOpenKind.renderedVideo;
  final audio = observed.kind == NativeMediaOpenKind.playedAudio;
  final mime = equality.sent.mime;
  if (!(image && mime.startsWith('image/') ||
      video && mime.startsWith('video/') ||
      audio && mime.startsWith('audio/') ||
      observed.kind == NativeMediaOpenKind.renderedPdf &&
          mime == 'application/pdf')) {
    throw const MediaOracleFailure('NATIVE_KIND_DOES_NOT_MATCH_MEDIA');
  }
  if ((image || video) &&
      ((observed.width ?? 0) <= 0 || (observed.height ?? 0) <= 0)) {
    throw const MediaOracleFailure('NATIVE_FRAME_NOT_DECODED');
  }
  if ((video || audio) &&
      ((observed.durationMs ?? 0) <= 0 ||
          (observed.startPositionMs ?? -1) < 0 ||
          (observed.endPositionMs ?? 0) - (observed.startPositionMs ?? 0) <
              250 ||
          observed.endPositionMs! > observed.durationMs!)) {
    throw const MediaOracleFailure('NATIVE_PLAYBACK_DID_NOT_ADVANCE');
  }
  if (observed.kind == NativeMediaOpenKind.renderedPdf &&
      (observed.renderedPages ?? 0) < 1) {
    throw const MediaOracleFailure('NATIVE_PDF_PAGE_NOT_RENDERED');
  }
}
