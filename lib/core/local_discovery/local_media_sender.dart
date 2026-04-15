import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Sends a media file to a peer's local HTTP server.
///
/// Protocol:
/// 1. Compute SHA-256 of local file
/// 2. Send `media_offer` via WS
/// 3. Wait for `media_offer_accepted` (5s timeout)
/// 4. HTTP PUT file to receiver's `/media/<id>` endpoint
/// 5. Wait for `media_uploaded` via WS (30s timeout)
class LocalMediaSender {
  static const Duration _offerTimeout = Duration(seconds: 5);
  static const Duration _uploadedTimeout = Duration(seconds: 30);

  /// Send media to a local peer's HTTP server.
  ///
  /// Returns true if the file was uploaded and SHA-256 verified by receiver.
  Future<bool> sendMedia({
    required String host,
    required int port,
    required WebSocket ws,
    required Stream<dynamic> ackStream,
    required String filePath,
    required String mediaId,
    required String mime,
    required String fromPeerId,
    required String toPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async {
    final sendTimingStopwatch = Stopwatch()..start();
    void emitSendTiming({
      required String outcome,
      Map<String, dynamic> details = const {},
    }) {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_SEND_TIMING',
        details: {
          'elapsedMs': sendTimingStopwatch.elapsedMilliseconds,
          'outcome': outcome,
          'mediaId': mediaId,
          ...details,
        },
      );
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MEDIA_SEND_FILE_NOT_FOUND',
          details: {'path': filePath},
        );
        emitSendTiming(outcome: 'file_not_found');
        return false;
      }

      final fileSize = await file.length();

      // 1. Compute SHA-256.
      final sha256Hex = await _computeSha256(file);

      // 2. Generate token + nonce.
      final token = _generateToken();
      final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

      // 3. Send media_offer via WS.
      final offerJson = jsonEncode({
        'type': 'media_offer',
        'id': mediaId,
        'from': fromPeerId,
        'to': toPeerId,
        'mime': mime,
        'size': fileSize,
        'sha256': sha256Hex,
        'token': token,
        'nonce': nonce,
        if (durationMs != null) 'durationMs': durationMs,
        if (waveform != null) 'waveform': waveform,
        if (filename != null) 'filename': filename,
      });

      ws.add(offerJson);

      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_OFFER_SENT',
        details: {'id': mediaId, 'size': fileSize},
      );

      // 4. Wait for media_offer_accepted.
      final offerAccepted = await _waitForOfferResponse(
        ackStream: ackStream,
        mediaId: mediaId,
        nonce: nonce,
      );
      if (!offerAccepted) {
        emitSendTiming(
          outcome: 'offer_rejected_or_timeout',
          details: {'sizeBytes': fileSize},
        );
        return false;
      }

      // 5. HTTP PUT file to receiver.
      final client = HttpClient();
      try {
        final uri = Uri.parse('http://$host:$port/media/$mediaId');
        final req = await client.openUrl('PUT', uri);
        req.headers.set('Authorization', 'Bearer $token');
        req.headers.set('Content-Length', '$fileSize');
        req.headers.contentType = ContentType.parse(mime);

        await req.addStream(file.openRead());
        final response = await req.close();

        if (response.statusCode != HttpStatus.ok) {
          // Drain response body to free resources.
          await response.drain<void>();
          emitFlowEvent(
            layer: 'FL',
            event: 'LOCAL_MEDIA_UPLOAD_HTTP_ERROR',
            details: {'id': mediaId, 'status': response.statusCode},
          );
          emitSendTiming(
            outcome: 'upload_http_error',
            details: {'sizeBytes': fileSize, 'httpStatus': response.statusCode},
          );
          return false;
        }
        await response.drain<void>();
      } finally {
        client.close();
      }

      // 6. Wait for media_uploaded via WS.
      final uploadConfirmed = await _waitForUploadResponse(
        ackStream: ackStream,
        mediaId: mediaId,
        nonce: nonce,
      );
      if (!uploadConfirmed) {
        emitSendTiming(
          outcome: 'uploaded_timeout',
          details: {'sizeBytes': fileSize},
        );
        return false;
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_SEND_SUCCESS',
        details: {'id': mediaId, 'size': fileSize},
      );
      emitSendTiming(
        outcome: 'success',
        details: {'sizeBytes': fileSize},
      );

      return true;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_SEND_ERROR',
        details: {'id': mediaId, 'error': e.toString()},
      );
      emitSendTiming(outcome: 'error');
      return false;
    }
  }

  /// Compute SHA-256 of a file using streaming (no full-file buffer).
  Future<String> _computeSha256(File file) async {
    late Digest result;
    final digestSink = _CallbackSink<Digest>((d) => result = d);
    final hashSink = sha256.startChunkedConversion(digestSink);

    await for (final chunk in file.openRead()) {
      hashSink.add(chunk);
    }

    hashSink.close();
    return result.toString();
  }

  /// Generate a random 32-byte hex token.
  String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<bool> _waitForOfferResponse({
    required Stream<dynamic> ackStream,
    required String mediaId,
    required String nonce,
  }) async {
    try {
      final event = await ackStream
          .firstWhere((event) {
            final json = _parseJson(event);
            if (json == null) return false;
            if (json['id'] != mediaId || json['nonce'] != nonce) return false;
            final type = json['type'];
            return type == 'media_offer_accepted' ||
                type == 'media_offer_rejected';
          })
          .timeout(_offerTimeout);

      final json = _parseJson(event);
      final type = json?['type'];
      if (type == 'media_offer_accepted') return true;

      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_OFFER_REJECTED',
        details: {
          'id': mediaId,
          'reason': json?['reason']?.toString() ?? 'unknown',
        },
      );
      return false;
    } on TimeoutException {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_OFFER_TIMEOUT',
        details: {'id': mediaId},
      );
      return false;
    }
  }

  Future<bool> _waitForUploadResponse({
    required Stream<dynamic> ackStream,
    required String mediaId,
    required String nonce,
  }) async {
    try {
      final event = await ackStream
          .firstWhere((event) {
            final json = _parseJson(event);
            if (json == null) return false;
            if (json['id'] != mediaId || json['nonce'] != nonce) return false;
            final type = json['type'];
            return type == 'media_uploaded' || type == 'media_failed';
          })
          .timeout(_uploadedTimeout);

      final json = _parseJson(event);
      final type = json?['type'];
      if (type == 'media_uploaded') return true;

      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_UPLOAD_FAILED',
        details: {
          'id': mediaId,
          'reason': json?['reason']?.toString() ?? 'unknown',
        },
      );
      return false;
    } on TimeoutException {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_UPLOADED_TIMEOUT',
        details: {'id': mediaId},
      );
      return false;
    }
  }

  Map<String, dynamic>? _parseJson(dynamic event) {
    if (event is! String) return null;
    try {
      return jsonDecode(event) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
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
