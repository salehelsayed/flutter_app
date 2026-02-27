import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_media_sender.dart';
import 'package:flutter_app/core/local_discovery/local_media_server.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Local WebSocket server for direct peer-to-peer messaging on the same WiFi.
///
/// Incoming path: accepts WS connections, parses JSON messages, emits
/// [LocalChatMessage] on [messageStream].
///
/// Outgoing path: [sendMessage] connects to a remote peer's WS server,
/// sends a JSON message, and waits for an ack.
///
/// Media path: HTTP PUT /media/<id> for local WiFi file transfers,
/// coordinated via WS signaling (media_offer / media_offer_accepted /
/// media_uploaded).
///
/// Connection management: outbound connections are pooled by peerId and
/// reused. Idle connections are closed after [idleTimeout].
class LocalWsServer {
  static const int _maxInboundConnections = 10;
  static const Duration _ackTimeout = Duration(seconds: 5);

  final Duration idleTimeout;

  HttpServer? _server;
  int? _boundPort;

  final _messageController = StreamController<LocalChatMessage>.broadcast();
  final _inboundConnections = <WebSocket>{};

  /// Outbound connection pool: peerId → (WebSocket, idle timer).
  final _outboundPool = <String, _PooledConnection>{};

  /// Media server for handling PUT uploads (null until configured).
  LocalMediaServer? _mediaServer;

  /// Maps media ID → sender's inbound WebSocket for sending back
  /// media_uploaded / media_failed notifications.
  final _mediaWsSenders = <String, WebSocket>{};

  /// Media sender for outbound file transfers.
  final _mediaSender = LocalMediaSender();

  LocalWsServer({this.idleTimeout = const Duration(seconds: 60)});

  /// The port the server is bound to, or null if not started.
  int? get port => _boundPort;

  /// Stream of messages received from local peers.
  Stream<LocalChatMessage> get messageStream => _messageController.stream;

  /// Stream of media files received via local WiFi transfer.
  Stream<LocalMediaReady>? get mediaReadyStream =>
      _mediaServer?.mediaReadyStream;

  /// Configure the media server for receiving local file uploads.
  void configureMediaServer(LocalMediaServer mediaServer) {
    _mediaServer = mediaServer;
  }

  /// Start the WebSocket server on a random available port.
  ///
  /// Returns the bound port number.
  Future<int> start() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _boundPort = _server!.port;

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_WS_SERVER_STARTED',
      details: {'port': _boundPort},
    );

    _server!.listen(_handleHttpRequest);
    return _boundPort!;
  }

  void _handleHttpRequest(HttpRequest request) {
    final path = request.uri.path;

    // Media upload route: PUT /media/<id>
    if (path.startsWith('/media/')) {
      final mediaId = path.substring('/media/'.length);
      if (mediaId.isEmpty) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..close();
        return;
      }
      _handleMediaUpload(request, mediaId);
      return;
    }

    // WebSocket upgrade (existing behavior).
    if (_inboundConnections.length >= _maxInboundConnections) {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_WS_SERVER_REJECT_MAX_CONNECTIONS',
        details: {'count': _inboundConnections.length},
      );
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..close();
      return;
    }

    WebSocketTransformer.upgrade(request).then((WebSocket ws) {
      _inboundConnections.add(ws);
      ws.listen(
        (data) => _handleInboundMessage(ws, data),
        onDone: () => _inboundConnections.remove(ws),
        onError: (_) => _inboundConnections.remove(ws),
      );
    }).catchError((_) {
      // Not a WebSocket upgrade request — ignore.
    });
  }

  void _handleMediaUpload(HttpRequest request, String mediaId) {
    if (request.method != 'PUT') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..close();
      return;
    }

    final mediaServer = _mediaServer;
    if (mediaServer == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }

    mediaServer.handleUpload(request, mediaId).then((result) {
      final senderWs = _mediaWsSenders[mediaId];
      if (senderWs != null &&
          senderWs.readyState == WebSocket.open) {
        if (result.success) {
          senderWs.add(jsonEncode({
            'type': 'media_uploaded',
            'id': mediaId,
            'nonce': result.nonce,
            'sha256Verified': true,
          }));
        } else {
          senderWs.add(jsonEncode({
            'type': 'media_failed',
            'id': mediaId,
            'nonce': result.nonce,
            'reason': result.reason,
          }));
        }
      }
      _mediaWsSenders.remove(mediaId);
    });
  }

  void _handleInboundMessage(WebSocket ws, dynamic data) {
    if (data is! String) return;

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;

      // Check for media_offer type first.
      final type = json['type'] as String?;
      if (type == 'media_offer') {
        _handleMediaOffer(ws, json);
        return;
      }

      final from = json['from'] as String?;
      final to = json['to'] as String?;
      final content = json['content'] as String?;

      if (from == null || to == null || content == null) {
        return;
      }

      // Acknowledge receipt — echo back nonce for per-message correlation.
      final nonce = json['nonce'] as String?;
      ws.add(jsonEncode({
        'ack': true,
        if (nonce != null) 'nonce': nonce,
      }));

      final message = LocalChatMessage(
        from: from,
        to: to,
        content: content,
        timestamp: DateTime.now().toUtc(),
        isIncoming: true,
      );

      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_WS_MESSAGE_RECEIVED',
        details: {'from': from, 'to': to},
      );

      _messageController.add(message);
    } catch (_) {
      // Malformed JSON — silently ignore.
    }
  }

  void _handleMediaOffer(WebSocket ws, Map<String, dynamic> json) {
    final mediaServer = _mediaServer;
    if (mediaServer == null) {
      final nonce = json['nonce'] as String?;
      ws.add(jsonEncode({
        'type': 'media_offer_rejected',
        'id': json['id'],
        'nonce': nonce,
        'reason': 'media_not_supported',
      }));
      return;
    }

    final offer = MediaOffer.fromJson(json);

    if (mediaServer.acceptOffer(offer)) {
      // Store the sender's WS for sending media_uploaded back later.
      _mediaWsSenders[offer.id] = ws;

      ws.add(jsonEncode({
        'type': 'media_offer_accepted',
        'id': offer.id,
        'token': offer.token,
        'nonce': offer.nonce,
      }));
    } else {
      ws.add(jsonEncode({
        'type': 'media_offer_rejected',
        'id': offer.id,
        'nonce': offer.nonce,
        'reason': 'validation_failed',
      }));
    }
  }

  /// Send a message to a peer's local WebSocket server.
  ///
  /// Returns true if the peer acknowledged receipt within [_ackTimeout].
  Future<bool> sendMessage(
    String host,
    int port,
    String content,
    String fromPeerId,
    String toPeerId,
  ) async {
    try {
      final ws = await _getOrCreateConnection(toPeerId, host, port);

      // Generate a per-message nonce for ack correlation.
      final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

      final payload = jsonEncode({
        'from': fromPeerId,
        'to': toPeerId,
        'content': content,
        'nonce': nonce,
      });

      ws.add(payload);

      // Wait for ack on the broadcast stream (supports multiple sends on the
      // same pooled connection — unlike ws.firstWhere which would fail with
      // "Stream has already been listened to" on single-subscription streams).
      //
      // Per-message ack correlation: the server echoes back the nonce in the
      // ack response. Each waiter matches only its own nonce, so concurrent
      // sends on the same pooled connection resolve correctly.
      final pooled = _outboundPool[toPeerId];
      final ackStream = pooled?.ackStream ?? ws;

      await ackStream.firstWhere(
        (event) {
          if (event is! String) return false;
          try {
            final json = jsonDecode(event) as Map<String, dynamic>;
            return json['ack'] == true && json['nonce'] == nonce;
          } catch (_) {
            return false;
          }
        },
      ).timeout(_ackTimeout);

      _resetIdleTimer(toPeerId);

      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_WS_MESSAGE_SENT',
        details: {'to': toPeerId, 'host': host, 'port': port},
      );

      return true;
    } catch (e) {
      // Connection failed or ack timeout — remove from pool.
      _removeFromPool(toPeerId);

      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_WS_SEND_FAILED',
        details: {'to': toPeerId, 'error': e.toString()},
      );

      return false;
    }
  }

  /// Send a media file to a peer's local HTTP server.
  ///
  /// Uses the existing pooled WS connection for signaling and HTTP PUT
  /// for file transfer. Returns true if uploaded and SHA-256 verified.
  Future<bool> sendMedia({
    required String host,
    required int port,
    required String toPeerId,
    required String filePath,
    required String mediaId,
    required String mime,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async {
    try {
      final ws = await _getOrCreateConnection(toPeerId, host, port);
      final pooled = _outboundPool[toPeerId];
      final ackStream = pooled?.ackStream ?? ws;

      final result = await _mediaSender.sendMedia(
        host: host,
        port: port,
        ws: ws,
        ackStream: ackStream,
        filePath: filePath,
        mediaId: mediaId,
        mime: mime,
        fromPeerId: fromPeerId,
        toPeerId: toPeerId,
        durationMs: durationMs,
        waveform: waveform,
        filename: filename,
      );

      if (result) {
        _resetIdleTimer(toPeerId);
      }

      return result;
    } catch (e) {
      _removeFromPool(toPeerId);

      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_WS_SEND_MEDIA_FAILED',
        details: {'to': toPeerId, 'error': e.toString()},
      );

      return false;
    }
  }

  Future<WebSocket> _getOrCreateConnection(
    String peerId,
    String host,
    int port,
  ) async {
    final existing = _outboundPool[peerId];
    if (existing != null && existing.ws.readyState == WebSocket.open) {
      _resetIdleTimer(peerId);
      return existing.ws;
    }

    // Clean up stale entry if present.
    _removeFromPool(peerId);

    final ws = await WebSocket.connect('ws://$host:$port')
        .timeout(const Duration(seconds: 5));

    // Create a broadcast stream so multiple sends can each listen for acks
    // without hitting the single-subscription limitation of WebSocket streams.
    final broadcast = StreamController<dynamic>.broadcast();
    final subscription = ws.listen(
      broadcast.add,
      onError: broadcast.addError,
      onDone: () {
        broadcast.close();
        _removeFromPool(peerId);
      },
    );

    _outboundPool[peerId] = _PooledConnection(
      ws: ws,
      ackStream: broadcast.stream,
      broadcast: broadcast,
      subscription: subscription,
      idleTimer: Timer(idleTimeout, () => _removeFromPool(peerId)),
    );

    return ws;
  }

  void _resetIdleTimer(String peerId) {
    final pooled = _outboundPool[peerId];
    if (pooled == null) return;
    pooled.idleTimer.cancel();
    _outboundPool[peerId] = _PooledConnection(
      ws: pooled.ws,
      ackStream: pooled.ackStream,
      broadcast: pooled.broadcast,
      subscription: pooled.subscription,
      idleTimer: Timer(idleTimeout, () => _removeFromPool(peerId)),
    );
  }

  void _removeFromPool(String peerId) {
    final pooled = _outboundPool.remove(peerId);
    if (pooled != null) {
      pooled.idleTimer.cancel();
      pooled.subscription.cancel();
      pooled.broadcast.close();
      pooled.ws.close().catchError((_) {});
    }
  }

  /// Stop the server and close all connections.
  Future<void> stop() async {
    for (final ws in _inboundConnections.toList()) {
      await ws.close().catchError((_) {});
    }
    _inboundConnections.clear();
    _mediaWsSenders.clear();

    for (final peerId in _outboundPool.keys.toList()) {
      _removeFromPool(peerId);
    }

    await _server?.close();
    _server = null;
    _boundPort = null;

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_WS_SERVER_STOPPED',
      details: {},
    );
  }

  void dispose() {
    stop();
    _messageController.close();
    _mediaServer?.dispose();
  }
}

class _PooledConnection {
  final WebSocket ws;

  /// Broadcast stream fed by [subscription]; allows multiple ack listeners.
  final Stream<dynamic> ackStream;
  final StreamController<dynamic> broadcast;
  final StreamSubscription<dynamic> subscription;
  final Timer idleTimer;

  _PooledConnection({
    required this.ws,
    required this.ackStream,
    required this.broadcast,
    required this.subscription,
    required this.idleTimer,
  });
}
