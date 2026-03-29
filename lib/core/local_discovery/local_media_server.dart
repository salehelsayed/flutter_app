import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Result of an HTTP PUT upload attempt.
class MediaUploadResult {
  final bool success;
  final String mediaId;
  final String nonce;
  final String? reason;
  final LocalMediaReady? mediaReady;

  const MediaUploadResult({
    required this.success,
    required this.mediaId,
    required this.nonce,
    this.reason,
    this.mediaReady,
  });
}

class _PendingTransfer {
  final MediaOffer offer;
  final DateTime createdAt;
  bool isUploading;

  _PendingTransfer({
    required this.offer,
    required this.createdAt,
    this.isUploading = false,
  });
}

/// HTTP PUT handler for receiving media files from local peers.
///
/// Validates MIME type, file size, bearer token, and SHA-256 hash.
/// Files are streamed to a temp directory, then moved to a persistent
/// media directory after the app confirms receipt.
class LocalMediaServer {
  static const int maxFileSize = 5 * 1024 * 1024 * 1024; // 5 GB
  static const Duration pendingTtl = Duration(minutes: 5);
  static const Set<String> allowedMimePrefixes = {
    'image/',
    'video/',
    'audio/',
    'application/pdf',
  };

  final String tempDir;
  final String mediaDir;
  final int maxAcceptedFileSizeBytes;
  final _pendingTransfers = <String, _PendingTransfer>{};
  final _mediaReadyController = StreamController<LocalMediaReady>.broadcast();
  Timer? _cleanupTimer;

  /// Stream of media files received via local WiFi transfer.
  Stream<LocalMediaReady> get mediaReadyStream => _mediaReadyController.stream;

  LocalMediaServer({
    required this.tempDir,
    required this.mediaDir,
    int? maxAcceptedFileSizeBytes,
  }) : maxAcceptedFileSizeBytes = maxAcceptedFileSizeBytes ?? maxFileSize {
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _cleanupExpired(),
    );
  }

  /// Register an incoming media_offer. Returns true if accepted.
  bool acceptOffer(MediaOffer offer) {
    // Reject duplicate ID.
    if (_pendingTransfers.containsKey(offer.id)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_OFFER_REJECTED_DUPLICATE',
        details: {'id': offer.id},
      );
      return false;
    }

    // Validate MIME type.
    final mimeAllowed = allowedMimePrefixes.any(
      (prefix) => offer.mime.startsWith(prefix),
    );
    if (!mimeAllowed) {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_OFFER_REJECTED_MIME',
        details: {'id': offer.id, 'mime': offer.mime},
      );
      return false;
    }

    // Validate size.
    if (offer.size > maxAcceptedFileSizeBytes || offer.size <= 0) {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_OFFER_REJECTED_SIZE',
        details: {'id': offer.id, 'size': offer.size},
      );
      return false;
    }

    _pendingTransfers[offer.id] = _PendingTransfer(
      offer: offer,
      createdAt: DateTime.now(),
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_MEDIA_OFFER_ACCEPTED',
      details: {'id': offer.id, 'mime': offer.mime, 'size': offer.size},
    );

    return true;
  }

  /// Handle HTTP PUT /media/<id>. Streams body to temp file, verifies SHA-256.
  ///
  /// Returns a [MediaUploadResult] indicating success or failure.
  /// The HTTP response is written to [request.response] before returning.
  Future<MediaUploadResult> handleUpload(
    HttpRequest request,
    String mediaId,
  ) async {
    if (!_isSafePathSegment(mediaId)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..reasonPhrase = 'Invalid media ID'
        ..close();
      return const MediaUploadResult(
        success: false,
        mediaId: '',
        nonce: '',
        reason: 'invalid_media_id',
      );
    }

    // Look up pending transfer.
    final pending = _pendingTransfers[mediaId];
    if (pending == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..reasonPhrase = 'No pending offer'
        ..close();
      return MediaUploadResult(
        success: false,
        mediaId: mediaId,
        nonce: '',
        reason: 'no_pending_offer',
      );
    }

    final offer = pending.offer;

    // Validate Authorization header.
    final authHeader = request.headers.value('authorization');
    if (authHeader == null) {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..reasonPhrase = 'Missing Authorization'
        ..close();
      return MediaUploadResult(
        success: false,
        mediaId: mediaId,
        nonce: offer.nonce,
        reason: 'missing_auth',
      );
    }

    if (!authHeader.startsWith('Bearer ') ||
        authHeader.substring(7) != offer.token) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..reasonPhrase = 'Invalid token'
        ..close();
      return MediaUploadResult(
        success: false,
        mediaId: mediaId,
        nonce: offer.nonce,
        reason: 'invalid_token',
      );
    }

    // Reject concurrent upload.
    if (pending.isUploading) {
      request.response
        ..statusCode = HttpStatus.conflict
        ..reasonPhrase = 'Upload already in progress'
        ..close();
      return MediaUploadResult(
        success: false,
        mediaId: mediaId,
        nonce: offer.nonce,
        reason: 'already_uploading',
      );
    }

    pending.isUploading = true;

    // Determine file extension from MIME type.
    final ext = _extensionFromMime(offer.mime);
    final tempFilePath = '$tempDir/$mediaId$ext';

    File? tempFile;
    IOSink? fileSink;

    try {
      // Ensure temp directory exists.
      await Directory(tempDir).create(recursive: true);

      tempFile = File(tempFilePath);
      fileSink = tempFile.openWrite();

      // Stream body to file with incremental SHA-256.
      late Digest computedDigest;
      final digestSink = _CallbackSink<Digest>((d) => computedDigest = d);
      final hashSink = sha256.startChunkedConversion(digestSink);

      var bytesWritten = 0;

      await for (final chunk in request) {
        bytesWritten += chunk.length;

        if (bytesWritten > offer.size) {
          // Too many bytes — abort.
          hashSink.close();
          await fileSink.close();
          await tempFile.delete();
          _pendingTransfers.remove(mediaId);

          request.response
            ..statusCode = HttpStatus.requestEntityTooLarge
            ..reasonPhrase = 'Exceeded declared size'
            ..close();

          return MediaUploadResult(
            success: false,
            mediaId: mediaId,
            nonce: offer.nonce,
            reason: 'size_exceeded',
          );
        }

        fileSink.add(chunk);
        hashSink.add(chunk);
      }

      hashSink.close();
      await fileSink.flush();
      await fileSink.close();
      fileSink = null;

      // Must exactly match declared size.
      if (bytesWritten != offer.size) {
        await tempFile.delete();
        _pendingTransfers.remove(mediaId);

        request.response
          ..statusCode = HttpStatus.badRequest
          ..reasonPhrase = 'Body size mismatch'
          ..close();

        return MediaUploadResult(
          success: false,
          mediaId: mediaId,
          nonce: offer.nonce,
          reason: 'size_mismatch',
        );
      }

      // Verify SHA-256.
      final computedHex = computedDigest.toString();
      if (computedHex != offer.sha256) {
        await tempFile.delete();
        _pendingTransfers.remove(mediaId);

        request.response
          ..statusCode = HttpStatus.badRequest
          ..reasonPhrase = 'SHA-256 mismatch'
          ..close();

        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MEDIA_UPLOAD_SHA256_MISMATCH',
          details: {
            'id': mediaId,
            'expected': offer.sha256,
            'got': computedHex,
          },
        );

        return MediaUploadResult(
          success: false,
          mediaId: mediaId,
          nonce: offer.nonce,
          reason: 'sha256_mismatch',
        );
      }

      // Success — build LocalMediaReady.
      final mediaReady = LocalMediaReady(
        id: mediaId,
        from: offer.from,
        to: offer.to,
        mime: offer.mime,
        size: bytesWritten,
        localPath: tempFilePath,
        sha256: computedHex,
        durationMs: offer.durationMs,
        waveform: offer.waveform,
        filename: offer.filename,
      );

      _mediaReadyController.add(mediaReady);

      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_UPLOAD_SUCCESS',
        details: {'id': mediaId, 'size': bytesWritten},
      );

      request.response
        ..statusCode = HttpStatus.ok
        ..close();

      return MediaUploadResult(
        success: true,
        mediaId: mediaId,
        nonce: offer.nonce,
        mediaReady: mediaReady,
      );
    } catch (e) {
      // Cleanup on error.
      try {
        await fileSink?.close();
      } catch (_) {}
      try {
        await tempFile?.delete();
      } catch (_) {}
      _pendingTransfers.remove(mediaId);

      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..close();
      } catch (_) {}

      return MediaUploadResult(
        success: false,
        mediaId: mediaId,
        nonce: pending.offer.nonce,
        reason: 'internal_error',
      );
    }
  }

  /// Move temp file to persistent media/<contactPeerId>/<id>.<ext> path.
  /// Returns the new path, or null if the temp file doesn't exist.
  Future<String?> persistMedia(String mediaId, String contactPeerId) async {
    if (!_isSafePathSegment(mediaId) || !_isSafePathSegment(contactPeerId)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_PERSIST_REJECTED_PATH',
        details: {'id': mediaId, 'contactPeerId': contactPeerId},
      );
      return null;
    }

    final pending = _pendingTransfers[mediaId];
    if (pending == null) return null;

    final offer = pending.offer;
    final ext = _extensionFromMime(offer.mime);
    final tempFilePath = '$tempDir/$mediaId$ext';
    final tempFile = File(tempFilePath);

    if (!await tempFile.exists()) return null;

    final destDir = '$mediaDir/$contactPeerId';
    await Directory(destDir).create(recursive: true);

    final destPath = '$destDir/$mediaId$ext';
    await tempFile.rename(destPath);
    _pendingTransfers.remove(mediaId);

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_MEDIA_PERSISTED',
      details: {'id': mediaId, 'path': destPath},
    );

    return destPath;
  }

  /// Delete temp file for failed/expired transfers.
  void cleanupMedia(String mediaId) {
    final pending = _pendingTransfers.remove(mediaId);
    if (pending == null) return;

    final ext = _extensionFromMime(pending.offer.mime);
    final tempFilePath = '$tempDir/$mediaId$ext';
    try {
      File(tempFilePath).deleteSync();
    } catch (_) {}
  }

  /// Whether a pending offer exists for the given media ID.
  bool hasPendingOffer(String mediaId) =>
      _pendingTransfers.containsKey(mediaId);

  void _cleanupExpired() {
    final now = DateTime.now();
    final expired = <String>[];

    for (final entry in _pendingTransfers.entries) {
      if (now.difference(entry.value.createdAt) > pendingTtl) {
        expired.add(entry.key);
      }
    }

    for (final id in expired) {
      cleanupMedia(id);
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_EXPIRED',
        details: {'id': id},
      );
    }
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _mediaReadyController.close();
  }

  static String _extensionFromMime(String mime) {
    if (mime.startsWith('image/jpeg')) return '.jpg';
    if (mime.startsWith('image/png')) return '.png';
    if (mime.startsWith('image/gif')) return '.gif';
    if (mime.startsWith('image/webp')) return '.webp';
    if (mime.startsWith('video/mp4')) return '.mp4';
    if (mime.startsWith('video/quicktime')) return '.mov';
    if (mime.startsWith('audio/aac') || mime.startsWith('audio/m4a')) {
      return '.m4a';
    }
    if (mime.startsWith('audio/mpeg')) return '.mp3';
    if (mime.startsWith('audio/ogg')) return '.ogg';
    if (mime == 'application/pdf') return '.pdf';
    return '.bin';
  }

  static bool _isSafePathSegment(String value) {
    if (value.isEmpty) return false;
    if (value.contains('/') || value.contains('\\') || value.contains('..')) {
      return false;
    }
    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value);
  }
}

/// Simple sink that calls a callback with the final value.
class _CallbackSink<T> implements Sink<T> {
  final void Function(T) _callback;
  _CallbackSink(this._callback);

  @override
  void add(T data) => _callback(data);

  @override
  void close() {}
}
