import 'dart:async';

import '../../../core/bridge/bridge.dart';
import '../../../core/bridge/p2p_bridge_client.dart';
import '../application/call_negotiation_effect_executor.dart';
import '../domain/call_engine.dart';
import '../diagnostics/call_diagnostics.dart';
import '../domain/call_id.dart';

typedef CallTurnCredentialFetcher =
    Future<Map<String, dynamic>> Function(Bridge bridge);

/// Reads a fresh native-authenticated bundle for setup or an ICE restart.
/// Only a transient outage returns an empty list; invalid/rejected responses
/// throw. The consumer applies the frozen call policy to that empty result.
/// Retains at most one validated bundle for this call's restart fallback.
/// Every read still attempts refresh; late fetches have no media side effects.
final class BridgeCallIceServerProvider {
  BridgeCallIceServerProvider({
    required Bridge bridge,
    CallTurnCredentialFetcher? fetch,
    DateTime Function()? clock,
    this.requestTimeout = const Duration(seconds: 5),
  }) : _bridge = bridge,
       _fetch = fetch,
       _clock = clock ?? DateTime.now;

  final Bridge _bridge;
  final CallTurnCredentialFetcher? _fetch;
  final DateTime Function() _clock;
  final Duration requestTimeout;
  CallId? _callId;
  bool _closed = false;
  List<CallIceServer> _lastValidServers = const [];

  void close() {
    _closed = true;
    _lastValidServers = const [];
  }

  void _requireOwner(CallId callId) {
    if (_closed || (_callId != null && _callId != callId)) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.mediaUnavailable,
      );
    }
    _callId = callId;
  }

  List<CallIceServer> _unexpiredFallback(CallId callId) {
    _requireOwner(callId);
    final now = _clock().toUtc();
    return _lastValidServers = List.unmodifiable(
      _lastValidServers.where((server) => server.expiresAt.isAfter(now)),
    );
  }

  Future<List<CallIceServer>> read(CallId callId) async {
    _requireOwner(callId);
    final diagnostics = CallDiagnostics.instance;
    final traceId =
        diagnostics.traceForCall(callId: callId.value) ??
        diagnostics.currentTraceId;
    void failed(String reason) => diagnostics.record(
      stage: 'turn',
      action: 'mint',
      outcome: 'failed',
      reason: reason,
      traceId: traceId,
    );
    try {
      diagnostics.record(
        stage: 'turn',
        action: 'mint',
        outcome: 'started',
        traceId: traceId,
      );
      final response =
          await (_fetch?.call(_bridge) ??
                  callP2PTurnCredentialsV1(
                    _bridge,
                    diagnostics: diagnostics.contextForWire(
                      callId: callId.value,
                      traceId: traceId,
                    ),
                  ))
              .timeout(requestTimeout);
      _requireOwner(callId);
      if (response['ok'] != true) {
        if (response['errorCode'] == 'TURN_CREDENTIALS_UNAVAILABLE') {
          failed('turn_credential_failed');
          return _unexpiredFallback(callId);
        }
        failed(
          response['errorCode'] == 'TURN_CREDENTIALS_INVALID_RESPONSE'
              ? 'malformed_response'
              : 'turn_credential_failed',
        );
        throw const CallNegotiationPortException(
          CallNegotiationPortErrorCode.iceServersUnavailable,
        );
      }

      final rawUrls = response['urls'];
      final username = response['username'];
      final password = response['password'];
      final expiresAtMs = response['expiresAtMs'];
      if (rawUrls is! List ||
          rawUrls.isEmpty ||
          rawUrls.length > 16 ||
          username is! String ||
          !validTurnCredentialText(username) ||
          password is! String ||
          !validTurnCredentialText(password) ||
          expiresAtMs is! int) {
        failed('malformed_response');
        throw const CallNegotiationPortException(
          CallNegotiationPortErrorCode.iceServersUnavailable,
        );
      }

      final urls = <String>[];
      for (final value in rawUrls) {
        if (value is! String ||
            value.length > 2048 ||
            !validTurnCredentialUrl(value)) {
          failed('malformed_response');
          throw const CallNegotiationPortException(
            CallNegotiationPortErrorCode.iceServersUnavailable,
          );
        }
        urls.add(value);
      }
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expiresAtMs,
        isUtc: true,
      );
      if (!expiresAt.isAfter(_clock().toUtc()) ||
          !urls.any(
            (url) => url.startsWith('turn:') || url.startsWith('turns:'),
          )) {
        failed('malformed_response');
        throw const CallNegotiationPortException(
          CallNegotiationPortErrorCode.iceServersUnavailable,
        );
      }
      diagnostics.record(
        stage: 'turn',
        action: 'mint',
        outcome: 'ok',
        traceId: traceId,
      );
      return _lastValidServers = List.unmodifiable(<CallIceServer>[
        CallIceServer(
          urls: urls,
          username: username,
          credential: password,
          expiresAt: expiresAt,
        ),
      ]);
    } on TimeoutException {
      failed('timeout');
      return _unexpiredFallback(callId);
    } on CallNegotiationPortException {
      rethrow;
    } catch (_) {
      failed('turn_credential_failed');
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.iceServersUnavailable,
      );
    }
  }
}
