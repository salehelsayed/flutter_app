import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Local WebSocket server for direct peer-to-peer messaging on the same WiFi.
///
/// Incoming path: accepts WS connections, parses JSON messages, emits
/// [LocalChatMessage] on [messageStream].
///
/// Outgoing path: [sendMessage] connects to a remote peer's WS server,
/// sends a JSON message, and waits for an ack.
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

  LocalWsServer({this.idleTimeout = const Duration(seconds: 60)});

  /// The port the server is bound to, or null if not started.
  int? get port => _boundPort;

  /// Stream of messages received from local peers.
  Stream<LocalChatMessage> get messageStream => _messageController.stream;

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

  void _handleInboundMessage(WebSocket ws, dynamic data) {
    if (data is! String) return;

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final from = json['from'] as String?;
      final to = json['to'] as String?;
      final content = json['content'] as String?;

      if (from == null || to == null || content == null) {
        return;
      }

      // Acknowledge receipt.
      ws.add(jsonEncode({'ack': true}));

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

      final payload = jsonEncode({
        'from': fromPeerId,
        'to': toPeerId,
        'content': content,
      });

      ws.add(payload);

      // Wait for ack.
      await ws.firstWhere(
        (event) {
          if (event is! String) return false;
          try {
            final json = jsonDecode(event) as Map<String, dynamic>;
            return json['ack'] == true;
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

    _outboundPool[peerId] = _PooledConnection(
      ws: ws,
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
      idleTimer: Timer(idleTimeout, () => _removeFromPool(peerId)),
    );
  }

  void _removeFromPool(String peerId) {
    final pooled = _outboundPool.remove(peerId);
    if (pooled != null) {
      pooled.idleTimer.cancel();
      pooled.ws.close().catchError((_) {});
    }
  }

  /// Stop the server and close all connections.
  Future<void> stop() async {
    for (final ws in _inboundConnections.toList()) {
      await ws.close().catchError((_) {});
    }
    _inboundConnections.clear();

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
  }
}

class _PooledConnection {
  final WebSocket ws;
  final Timer idleTimer;

  _PooledConnection({required this.ws, required this.idleTimer});
}
