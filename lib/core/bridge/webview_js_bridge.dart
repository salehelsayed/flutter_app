import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'js_bridge_client.dart';
import '../utils/flow_event_emitter.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/connection_state.dart';

/// WebView-based JavaScript bridge implementation.
///
/// This bridge uses a WebView to execute JavaScript code with full browser
/// crypto APIs, enabling real libp2p identity generation and P2P networking.
class WebViewJsBridge extends JsBridge {
  WebViewController? _controller;
  bool _initialized = false;
  int _requestId = 0;

  final Map<String, Completer<String>> _pendingRequests = {};
  Completer<void>? _readyCompleter;

  /// Event callback for incoming chat messages.
  void Function(ChatMessage)? onMessageReceived;

  /// Event callback when a peer connects.
  void Function(ConnectionState)? onPeerConnected;

  /// Event callback when a peer disconnects.
  void Function(ConnectionState)? onPeerDisconnected;

  /// Whether the bridge has been initialized.
  bool get isInitialized => _initialized;

  /// The WebView controller (for embedding in widget tree if needed).
  WebViewController? get controller => _controller;

  /// Initialize the WebView and load the bridge HTML.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'ID_BRIDGE_INIT_START',
      details: {'type': 'webview'},
    );

    try {
      _readyCompleter = Completer<void>();

      // Load assets
      final htmlContent = await rootBundle.loadString('assets/js/bridge.html');
      final identityJsCode = await rootBundle.loadString('assets/js/core_lib.js');
      final p2pJsCode = await rootBundle.loadString('assets/js/p2p_lib.js');

      // Inject both JS bundles into HTML
      var fullHtml = htmlContent.replaceFirst(
        '<script src="core_lib.js"></script>',
        '<script>$identityJsCode</script>',
      );
      fullHtml = fullHtml.replaceFirst(
        '<script src="p2p_lib.js"></script>',
        '<script>$p2pJsCode</script>',
      );

      // Create WebView controller
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'FlutterChannel',
          onMessageReceived: _onMessageReceived,
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (url) {
              debugPrint('[WebViewJsBridge] Page finished loading');
            },
            onWebResourceError: (error) {
              debugPrint('[WebViewJsBridge] Error: ${error.description}');
            },
          ),
        )
        ..loadHtmlString(fullHtml);

      _initialized = true;

      // Wait for bridge ready signal (with timeout)
      await _readyCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[WebViewJsBridge] Ready timeout, proceeding anyway');
        },
      );

      emitFlowEvent(
        layer: 'FL',
        event: 'ID_BRIDGE_INIT_SUCCESS',
        details: {'type': 'webview'},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ID_BRIDGE_INIT_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Handle messages from JavaScript.
  void _onMessageReceived(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message);

      // Check for ready signal
      if (data['ready'] == true) {
        _readyCompleter?.complete();
        debugPrint('[WebViewJsBridge] Bridge ready');
        return;
      }

      // Check for push events (P2P events)
      if (data['event'] != null) {
        _handlePushEvent(data);
        return;
      }

      // Handle request/response
      final requestId = data['requestId'] as String?;
      if (requestId != null && _pendingRequests.containsKey(requestId)) {
        _pendingRequests[requestId]!.complete(message.message);
        _pendingRequests.remove(requestId);
      } else {
        debugPrint('[WebViewJsBridge] Received message: ${message.message}');
      }
    } catch (e) {
      debugPrint('[WebViewJsBridge] Error parsing message: $e');
    }
  }

  /// Handle push events from the P2P layer.
  void _handlePushEvent(Map<String, dynamic> data) {
    final event = data['event'] as String;
    final eventData = data['data'] as Map<String, dynamic>? ?? {};

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_PUSH_EVENT_RECEIVED',
      details: {'event': event},
    );

    switch (event) {
      case 'message:received':
        if (onMessageReceived != null) {
          try {
            final chatMessage = ChatMessage.fromJson(eventData);
            onMessageReceived!(chatMessage);
          } catch (e) {
            debugPrint('[WebViewJsBridge] Error parsing chat message: $e');
          }
        }
        break;

      case 'peer:connected':
        if (onPeerConnected != null) {
          try {
            final connState = ConnectionState.fromJson(eventData);
            onPeerConnected!(connState);
          } catch (e) {
            debugPrint('[WebViewJsBridge] Error parsing peer connected: $e');
          }
        }
        break;

      case 'peer:disconnected':
        if (onPeerDisconnected != null) {
          try {
            final connState = ConnectionState.fromJson(eventData);
            onPeerDisconnected!(connState);
          } catch (e) {
            debugPrint('[WebViewJsBridge] Error parsing peer disconnected: $e');
          }
        }
        break;

      default:
        debugPrint('[WebViewJsBridge] Unknown push event: $event');
    }
  }

  @override
  Future<String> send(String message) async {
    if (!_initialized || _controller == null) {
      throw StateError('WebViewJsBridge not initialized. Call initialize() first.');
    }

    final request = jsonDecode(message);
    final requestId = 'req_${++_requestId}';

    // Add requestId to the request
    request['requestId'] = requestId;
    final requestJson = jsonEncode(request);

    emitFlowEvent(
      layer: 'FL',
      event: 'ID_BRIDGE_SEND_REQUEST',
      details: {'cmd': request['cmd'], 'requestId': requestId},
    );

    // Create completer for this request
    final completer = Completer<String>();
    _pendingRequests[requestId] = completer;

    try {
      // Escape the JSON for JavaScript string
      final escapedJson = requestJson
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "\\'")
          .replaceAll('\n', '\\n')
          .replaceAll('\r', '\\r');

      // Call the JavaScript handler
      await _controller!.runJavaScript("handleRequest('$escapedJson')");

      // Wait for response with timeout
      final response = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _pendingRequests.remove(requestId);
          return jsonEncode({
            'ok': false,
            'errorCode': 'TIMEOUT',
            'errorMessage': 'Request timed out',
          });
        },
      );

      emitFlowEvent(
        layer: 'FL',
        event: 'ID_BRIDGE_SEND_RESPONSE',
        details: {'cmd': request['cmd'], 'requestId': requestId},
      );

      return response;
    } catch (e) {
      _pendingRequests.remove(requestId);

      emitFlowEvent(
        layer: 'FL',
        event: 'ID_BRIDGE_SEND_ERROR',
        details: {'cmd': request['cmd'], 'error': e.toString()},
      );

      return jsonEncode({
        'ok': false,
        'errorCode': 'INTERNAL_ERROR',
        'errorMessage': e.toString(),
      });
    }
  }

  /// Dispose of the WebView.
  void dispose() {
    _controller = null;
    _initialized = false;
    _pendingRequests.clear();
    onMessageReceived = null;
    onPeerConnected = null;
    onPeerDisconnected = null;
  }
}
