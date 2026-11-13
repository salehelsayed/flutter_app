import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../application/call_endpoint_resolver.dart';
import '../application/call_signaling_context_store.dart';
import '../application/call_signaling_service.dart';
import '../domain/call_id.dart';
import '../domain/call_media.dart';
import '../domain/call_signal_v2.dart';
import 'call_authority_client.dart';
import 'production_call_signaling_adapters.dart';

/// Owns one immutable v2 message's preparation and bounded transport custody.
/// The canonical call/media owner supplies the admission and lifetime fence.
final class ProductionCallV2SignalingAdapter {
  ProductionCallV2SignalingAdapter({
    required CallSignalingService signalingService,
    required CallSignalingContextStore contextStore,
    required ResolveCurrentCallEndpoint resolveCurrentEndpoint,
    required LoadCallSenderSigningPrivateKey loadSenderSigningPrivateKey,
    required int Function() nowMs,
    bool videoEnabled = false,
  }) : _service = signalingService,
       _contexts = contextStore,
       _resolve = resolveCurrentEndpoint,
       _loadSigningKey = loadSenderSigningPrivateKey,
       _nowMs = nowMs,
       _videoEnabled = videoEnabled;

  final CallSignalingService _service;
  final CallSignalingContextStore _contexts;
  final ResolveCurrentCallEndpoint _resolve;
  final LoadCallSenderSigningPrivateKey _loadSigningKey;
  final int Function() _nowMs;
  final bool _videoEnabled;
  final Map<String, _PreparedV2Entry> _entries = {};
  bool _closed = false;

  // Keep failed/retired identities through the existing replay window. No
  // private key, plaintext SDP or candidate is retained in this index.
  static const _maximumIdentities = 128;
  static const _reservedTerminalIdentities = 4;
  static const _replayWindowMs = 10 * 60 * 1000;

  Future<PreparedCallV2Signal> prepare({
    required CallSignalV2 signal,
    required String callHandle,
    required ResolvedCallEndpoint admittedEndpoint,
    required bool Function() canApply,
  }) {
    if (!_videoEnabled || _closed) {
      return _refused(CallSignalingErrorCode.migrationPaused);
    }
    final key = '${signal.callId.value}:${signal.messageId}';
    if (!_allowed(canApply)) {
      _entries[key]?.retire();
      return _refused(CallSignalingErrorCode.migrationPaused);
    }
    final now = _nowMs();
    if (now >= signal.expiresAtMs || CallId.tryParse(callHandle) == null) {
      return _refused(CallSignalingErrorCode.endpointMismatch);
    }
    _entries.removeWhere((_, entry) {
      if (now < entry.retainUntilMs ||
          _contexts.read(entry.context.callId) != null) {
        return false;
      }
      entry.retire();
      return true;
    });
    final endpoint = _snapshotEndpoint(admittedEndpoint);
    final identity = _digest(
      jsonEncode({
        'signal': signal.toMap(),
        'handle': callHandle,
        'endpoint': _endpointIdentity(endpoint),
      }),
    );
    final existing = _entries[key];
    if (existing != null) {
      if (existing.identity != identity) {
        return _refused(CallSignalingErrorCode.endpointMismatch);
      }
      _isCurrent(existing);
      return existing.result.future;
    }
    final terminal =
        signal.event == CallSignalV2Type.reject ||
        signal.event == CallSignalV2Type.terminate;
    final limit =
        _maximumIdentities - (terminal ? 0 : _reservedTerminalIdentities);
    if (_entries.length >= limit) {
      return _refused(CallSignalingErrorCode.transportUnavailable);
    }
    final context = _contexts.read(signal.callId);
    if (context == null ||
        context.wireVersion != CallWireVersion.v2 ||
        context.callHandle != callHandle ||
        context.localAccountPeerId != signal.senderAccountPeerId ||
        context.localDevicePeerId != signal.senderDevicePeerId ||
        context.remoteAccountPeerId != signal.recipientAccountPeerId ||
        context.remoteDevicePeerId != signal.recipientDevicePeerId ||
        !_validEndpoint(endpoint, context, now)) {
      return _refused(CallSignalingErrorCode.endpointMismatch);
    }
    final replayEnd = now + _replayWindowMs;
    final entry = _PreparedV2Entry(
      identity: identity,
      context: context,
      endpoint: endpoint,
      expiresAtMs: signal.expiresAtMs,
      retainUntilMs: signal.expiresAtMs > replayEnd
          ? signal.expiresAtMs
          : replayEnd,
      terminal: terminal,
      canApply: canApply,
    );
    // Reserve the exact Future before the first asynchronous lookup or seal.
    // A failure is retained too: an ID can never acquire new encrypted bytes.
    _entries[key] = entry;
    unawaited(
      _prepare(signal, entry).then<void>(
        entry.result.complete,
        onError: (Object error, StackTrace stack) {
          entry.retire();
          entry.result.completeError(
            CallSignalingException(
              error is CallSignalingException
                  ? error.code
                  : CallSignalingErrorCode.endpointMismatch,
            ),
            stack,
          );
        },
      ),
    );
    return entry.result.future;
  }

  Future<PreparedCallV2Signal> _prepare(
    CallSignalV2 signal,
    _PreparedV2Entry entry,
  ) async {
    if (!_isCurrent(entry)) {
      throw _stale;
    }
    final signingKey = await _loadSigningKey();
    if (!_isCurrent(entry) || signingKey.trim().isEmpty) {
      throw _stale;
    }
    // Retain only a digest to detect rotation; retry loads current authority
    // after the endpoint await and never retains the private signing key.
    final signingKeyDigest = _digest(signingKey);
    final transmission = await _service.prepareV2(
      signal: signal,
      callHandle: entry.context.callHandle,
      endpoint: entry.endpoint,
      senderSigningPrivateKey: signingKey,
      authorize: () => _authorize(entry, signingKeyDigest),
      canApply: () => _isCurrent(entry),
      videoEnabled: _videoEnabled,
    );
    entry.transmission = transmission;
    if (!_isCurrent(entry)) {
      entry.retire();
      throw _stale;
    }
    return PreparedCallV2Signal._(this, entry, signingKeyDigest);
  }

  Future<bool> _authorize(_PreparedV2Entry entry, String keyDigest) async {
    if (!_isCurrent(entry)) {
      return false;
    }
    late final ResolvedCallEndpoint fresh;
    try {
      fresh = _snapshotEndpoint(await _resolve(entry.endpoint.accountPeerId));
    } on CallEndpointResolutionException catch (error) {
      if (error.code == CallEndpointResolutionCode.unavailable) {
        throw const CallSignalingException(
          CallSignalingErrorCode.transportUnavailable,
        );
      }
      return false;
    } on CallAuthorityException catch (error) {
      if (error.code == CallAuthorityErrorCode.bridgeFailure &&
          (error.relayErrorCode == null ||
              error.relayErrorCode == 'CALL_CONTROL_UNAVAILABLE')) {
        throw const CallSignalingException(
          CallSignalingErrorCode.transportUnavailable,
        );
      }
      return false;
    } catch (_) {
      return false;
    }
    if (!_isCurrent(entry) ||
        !_validEndpoint(fresh, entry.context, _nowMs()) ||
        !_sameAuthority(entry.endpoint, fresh)) {
      return false;
    }
    try {
      final key = await _loadSigningKey();
      return _isCurrent(entry) &&
          _validEndpoint(fresh, entry.context, _nowMs()) &&
          key.isNotEmpty &&
          _digest(key) == keyDigest;
    } catch (_) {
      return false;
    }
  }

  bool _isCurrent(_PreparedV2Entry entry) {
    if (entry.retired) {
      return false;
    }
    final current = _contexts.read(entry.context.callId);
    final valid =
        !_closed &&
        _nowMs() < entry.expiresAtMs &&
        _validEndpoint(entry.endpoint, entry.context, _nowMs()) &&
        _allowed(entry.canApply) &&
        (current == null
            ? entry.terminal
            : _sameBinding(entry.context, current));
    if (!valid) {
      entry.retire();
    }
    return valid;
  }

  /// Retires optional/control work while preserving an already-owned terminal.
  void retireCall(CallId callId) {
    for (final entry in _entries.values) {
      if (entry.context.callId == callId && !entry.terminal) {
        entry.retire();
      }
    }
  }

  void close() {
    _closed = true;
    for (final entry in _entries.values) {
      entry.retire();
    }
    _entries.clear();
  }

  @override
  String toString() => 'ProductionCallV2SignalingAdapter';
}

/// A prepared signal never dispatches delivery receipts into the call reducer.
final class PreparedCallV2Signal {
  PreparedCallV2Signal._(this._owner, this._entry, this._keyDigest);

  final ProductionCallV2SignalingAdapter _owner;
  final _PreparedV2Entry _entry;
  final String _keyDigest;

  bool get isAvailable =>
      _owner._isCurrent(_entry) && _entry.transmission?.isAvailable == true;

  Future<CallSignalTransportResult> transmit({
    required bool Function() canApply,
  }) {
    if (!_allowed(canApply) || !isAvailable) {
      close();
      return Future<CallSignalTransportResult>.error(_stale);
    }
    return _entry.transmission!.retry(
      authorize: () => _owner._authorize(_entry, _keyDigest),
      canApply: () => _allowed(canApply) && _owner._isCurrent(_entry),
    );
  }

  void close() => _entry.retire();

  @override
  String toString() => 'PreparedCallV2Signal';
}

final class _PreparedV2Entry {
  _PreparedV2Entry({
    required this.identity,
    required this.context,
    required this.endpoint,
    required this.expiresAtMs,
    required this.retainUntilMs,
    required this.terminal,
    required this.canApply,
  });

  final String identity;
  final CallSignalingContext context;
  final ResolvedCallEndpoint endpoint;
  final int expiresAtMs;
  final int retainUntilMs;
  final bool terminal;
  final bool Function() canApply;
  final result = Completer<PreparedCallV2Signal>();
  CallSignalTransmissionRetry? transmission;
  bool retired = false;

  void retire() {
    retired = true;
    transmission?.close();
    transmission = null;
  }
}

const _stale = CallSignalingException(CallSignalingErrorCode.endpointMismatch);

Future<PreparedCallV2Signal> _refused(CallSignalingErrorCode code) =>
    Future<PreparedCallV2Signal>.error(CallSignalingException(code));

bool _allowed(bool Function() predicate) {
  try {
    return predicate();
  } catch (_) {
    return false;
  }
}

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

bool _sameBinding(CallSignalingContext first, CallSignalingContext next) =>
    first.callId == next.callId &&
    first.wireVersion == next.wireVersion &&
    first.direction == next.direction &&
    first.callHandle == next.callHandle &&
    first.localAccountPeerId == next.localAccountPeerId &&
    first.localDevicePeerId == next.localDevicePeerId &&
    first.remoteAccountPeerId == next.remoteAccountPeerId &&
    first.remoteDevicePeerId == next.remoteDevicePeerId &&
    first.admissionAuthority == next.admissionAuthority;

bool _validEndpoint(
  ResolvedCallEndpoint endpoint,
  CallSignalingContext context,
  int now,
) =>
    endpoint.accountPeerId == context.remoteAccountPeerId &&
    endpoint.devicePeerId == context.remoteDevicePeerId &&
    endpoint.admissionAuthority == context.admissionAuthority &&
    endpoint.expiresAtMs > now &&
    endpoint.capabilities.contains(CallEndpointResolver.voiceCapability) &&
    endpoint.capabilities.contains('video_call_v2');

bool _sameAuthority(ResolvedCallEndpoint first, ResolvedCallEndpoint next) =>
    first.accountPeerId == next.accountPeerId &&
    first.devicePeerId == next.devicePeerId &&
    first.signingPublicKey == next.signingPublicKey &&
    first.mlKemPublicKey == next.mlKemPublicKey &&
    first.deviceKeyEpoch == next.deviceKeyEpoch &&
    first.preferenceEpoch == next.preferenceEpoch &&
    first.admissionAuthority == next.admissionAuthority &&
    first.platform == next.platform &&
    first.routingHandle == next.routingHandle &&
    first.wakeHandle == next.wakeHandle;

ResolvedCallEndpoint _snapshotEndpoint(ResolvedCallEndpoint endpoint) =>
    ResolvedCallEndpoint(
      accountPeerId: endpoint.accountPeerId,
      devicePeerId: endpoint.devicePeerId,
      signingPublicKey: endpoint.signingPublicKey,
      mlKemPublicKey: endpoint.mlKemPublicKey,
      admissionAuthority: endpoint.admissionAuthority,
      deviceKeyEpoch: endpoint.deviceKeyEpoch,
      preferenceEpoch: endpoint.preferenceEpoch,
      platform: endpoint.platform,
      expiresAtMs: endpoint.expiresAtMs,
      routingHandle: endpoint.routingHandle,
      wakeHandle: endpoint.wakeHandle,
      capabilities: Set<String>.unmodifiable(endpoint.capabilities),
    );

Map<String, Object?> _endpointIdentity(ResolvedCallEndpoint endpoint) => {
  'account': endpoint.accountPeerId,
  'device': endpoint.devicePeerId,
  'signing_key': endpoint.signingPublicKey,
  'kem_key': endpoint.mlKemPublicKey,
  'key_epoch': endpoint.deviceKeyEpoch,
  'preference_epoch': endpoint.preferenceEpoch,
  'relationship_fingerprint': endpoint.admissionAuthority?.fingerprint,
  'relationship_revision': endpoint.admissionAuthority?.relationshipRevision,
  'platform': endpoint.platform.name,
  'expires': endpoint.expiresAtMs,
  'routing': endpoint.routingHandle,
  'wake': endpoint.wakeHandle,
  'capabilities': endpoint.capabilities.toList()..sort(),
};
