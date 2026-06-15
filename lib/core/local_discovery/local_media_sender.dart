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
  static const Duration defaultOfferTimeout = Duration(seconds: 5);
  static const Duration defaultUploadedTimeout = Duration(seconds: 30);

  final Duration offerTimeout;
  final Duration uploadedTimeout;

  const LocalMediaSender({
    this.offerTimeout = defaultOfferTimeout,
    this.uploadedTimeout = defaultUploadedTimeout,
  });

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
    // 112 Phase 4: the offered bytes are an encrypted blob artifact. The
    // sha256 below covers the CIPHERTEXT (computed over [filePath], which
    // IS the artifact), the receiver stages instead of promoting, and the
    // cleartext offer drops waveform/filename (metadata minimization).
    bool enc = false,
    String? encScheme,
  }) async {
    final sendTimingStopwatch = Stopwatch()..start();
    _LocalMediaUploadAckWaiter? uploadAckWaiter;
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
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_SEND_START',
        details: {
          'id': mediaId,
          'mime': mime,
          'sizeBytes': fileSize,
          'host': host,
          'port': port,
          'toPeerId': toPeerId,
        },
      );

      // 1. Compute SHA-256.
      final sha256Hex = await _computeSha256(file);
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_SHA256_READY',
        details: {
          'id': mediaId,
          'sizeBytes': fileSize,
          'sha256Prefix': sha256Hex.substring(0, 12),
        },
      );

      // 2. Generate token + nonce.
      final token = _generateToken();
      final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

      // 3. Send media_offer via WS. Enc offers never carry waveform or
      // filename — those travel only inside the encrypted envelope.
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
        if (!enc && waveform != null) 'waveform': waveform,
        if (!enc && filename != null) 'filename': filename,
        if (enc) 'enc': true,
        if (enc && encScheme != null) 'encScheme': encScheme,
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

      // 5. Arm the final upload ack wait before HTTP PUT. The receiver may
      // emit media_uploaded immediately after validating bytes, before the
      // sender finishes draining the HTTP response.
      uploadAckWaiter = _watchForUploadResponse(
        ackStream: ackStream,
        mediaId: mediaId,
        nonce: nonce,
      );

      // 6. HTTP PUT file to receiver.
      final client = HttpClient();
      try {
        final uri = Uri.parse('http://$host:$port/media/$mediaId');
        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MEDIA_UPLOAD_HTTP_START',
          details: {
            'id': mediaId,
            'mime': mime,
            'sizeBytes': fileSize,
            'host': host,
            'port': port,
          },
        );
        final req = await client.openUrl('PUT', uri);
        req.headers.set('Authorization', 'Bearer $token');
        req.headers.set('Content-Length', '$fileSize');
        req.headers.contentType = ContentType.parse(mime);

        await req.addStream(file.openRead());
        final response = await req.close();

        if (response.statusCode != HttpStatus.ok) {
          // Drain response body to free resources.
          await response.drain<void>();
          await uploadAckWaiter.cancel(
            reason: 'http_status_${response.statusCode}',
          );
          uploadAckWaiter = null;
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
        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MEDIA_UPLOAD_HTTP_RESPONSE',
          details: {
            'id': mediaId,
            'status': response.statusCode,
            'sizeBytes': fileSize,
          },
        );
      } finally {
        client.close();
      }

      // 7. Wait for media_uploaded via WS.
      final uploadAckResult = await uploadAckWaiter.future;
      uploadAckWaiter = null;
      if (!uploadAckResult.success) {
        emitSendTiming(
          outcome: uploadAckResult.outcome,
          details: {'sizeBytes': fileSize},
        );
        return false;
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_SEND_SUCCESS',
        details: {'id': mediaId, 'size': fileSize},
      );
      emitSendTiming(outcome: 'success', details: {'sizeBytes': fileSize});

      return true;
    } catch (e) {
      await uploadAckWaiter?.cancel(reason: 'send_exception');
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
          .timeout(offerTimeout);

      final json = _parseJson(event);
      final type = json?['type'];
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_OFFER_ACK_RECEIVED',
        details: {'id': mediaId, 'type': type ?? 'unknown'},
      );
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
    } on StateError {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_OFFER_ACK_STREAM_DONE',
        details: {'id': mediaId},
      );
      return false;
    }
  }

  _LocalMediaUploadAckWaiter _watchForUploadResponse({
    required Stream<dynamic> ackStream,
    required String mediaId,
    required String nonce,
  }) {
    final completer = Completer<_LocalMediaUploadAckResult>();
    Timer? timer;
    late final StreamSubscription<dynamic> subscription;

    void complete(_LocalMediaUploadAckResult result) {
      if (completer.isCompleted) {
        return;
      }
      timer?.cancel();
      subscription.cancel();
      completer.complete(result);
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_MEDIA_UPLOAD_ACK_WAIT_ARMED',
      details: {'id': mediaId, 'timeoutMs': uploadedTimeout.inMilliseconds},
    );

    subscription = ackStream.listen(
      (event) {
        final json = _parseJson(event);
        if (json == null) return;
        if (json['id'] != mediaId || json['nonce'] != nonce) return;
        final type = json['type'];
        if (type != 'media_uploaded' && type != 'media_failed') return;

        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MEDIA_UPLOAD_ACK_RECEIVED',
          details: {
            'id': mediaId,
            'type': type,
            'sha256Verified': json['sha256Verified'] == true,
            if (json['reason'] != null) 'reason': json['reason'].toString(),
          },
        );
        if (type == 'media_uploaded') {
          complete(const _LocalMediaUploadAckResult.success());
          return;
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MEDIA_UPLOAD_FAILED',
          details: {
            'id': mediaId,
            'reason': json['reason']?.toString() ?? 'unknown',
          },
        );
        complete(const _LocalMediaUploadAckResult.failure('media_failed'));
      },
      onError: (Object error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MEDIA_UPLOAD_ACK_STREAM_ERROR',
          details: {'id': mediaId, 'error': error.toString()},
        );
        complete(const _LocalMediaUploadAckResult.failure('ack_stream_error'));
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MEDIA_UPLOAD_ACK_STREAM_DONE',
          details: {'id': mediaId},
        );
        complete(const _LocalMediaUploadAckResult.failure('ack_stream_done'));
      },
    );

    timer = Timer(uploadedTimeout, () {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MEDIA_UPLOADED_TIMEOUT',
        details: {'id': mediaId, 'timeoutMs': uploadedTimeout.inMilliseconds},
      );
      complete(const _LocalMediaUploadAckResult.failure('uploaded_timeout'));
    });

    return _LocalMediaUploadAckWaiter(
      future: completer.future,
      cancel: ({required String reason}) async {
        if (completer.isCompleted) {
          return;
        }
        timer?.cancel();
        await subscription.cancel();
        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MEDIA_UPLOAD_ACK_WAIT_CANCELLED',
          details: {'id': mediaId, 'reason': reason},
        );
        completer.complete(
          const _LocalMediaUploadAckResult.failure('cancelled'),
        );
      },
    );
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

class _LocalMediaUploadAckWaiter {
  final Future<_LocalMediaUploadAckResult> future;
  final Future<void> Function({required String reason}) cancel;

  const _LocalMediaUploadAckWaiter({
    required this.future,
    required this.cancel,
  });
}

class _LocalMediaUploadAckResult {
  final bool success;
  final String outcome;

  const _LocalMediaUploadAckResult._({
    required this.success,
    required this.outcome,
  });

  const _LocalMediaUploadAckResult.success()
    : this._(success: true, outcome: 'success');

  const _LocalMediaUploadAckResult.failure(String outcome)
    : this._(success: false, outcome: outcome);
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
