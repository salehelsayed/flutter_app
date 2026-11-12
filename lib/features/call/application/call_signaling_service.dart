import '../diagnostics/call_diagnostics.dart';

import 'dart:async';
import 'dart:math';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../domain/call_event.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal.dart';
import '../domain/call_signal_v2.dart';
import '../domain/call_wire_signal.dart';
import '../infrastructure/call_mailbox_client.dart';
import '../infrastructure/p2p_call_transport.dart';
import '../infrastructure/secure_call_envelope_codec.dart';
import 'call_coordinator.dart';
import 'call_endpoint_resolver.dart';
import 'call_network_gate.dart';

enum CallSignalingErrorCode {
  migrationPaused,
  endpointMismatch,
  transportUnavailable,
}

final class CallSignalingException implements Exception {
  const CallSignalingException(this.code, {this.retry});

  final CallSignalingErrorCode code;
  final CallSignalTransmissionRetry? retry;

  @override
  String toString() => 'Call signaling failed: ${code.name}';
}

final class CallSignalTransportResult {
  const CallSignalTransportResult({
    required this.directAccepted,
    required this.mailboxStored,
    required this.directRoute,
    this.wakeDispatched = false,
  }) : _directSettled = true,
       _mailboxStoreSettled = null;

  const CallSignalTransportResult._race({
    required this.directAccepted,
    required this.mailboxStored,
    required this.directRoute,
    required bool directSettled,
    required Future<void> mailboxStoreSettled,
    this.wakeDispatched = false,
  }) : _directSettled = directSettled,
       _mailboxStoreSettled = mailboxStoreSettled;

  final bool directAccepted;
  final bool mailboxStored;

  /// The relay alerted the callee's device for this signal (its store
  /// receipt said `wake: dispatched`). Recipient alerting still requires the
  /// authenticated remote ringing signal.
  final bool wakeDispatched;
  final CallDirectRoute directRoute;
  final bool _directSettled;
  final Future<void>? _mailboxStoreSettled;

  bool get delivered => directAccepted || mailboxStored;

  /// Completes without error after this exact mailbox write either settles in
  /// custody or definitively fails. A retirement path can await this handoff
  /// before issuing mailbox cancellation without delaying direct delivery.
  Future<void> get mailboxStoreSettled =>
      _mailboxStoreSettled ?? Future<void>.value();

  @override
  String toString() =>
      'CallSignalTransportResult(directAccepted: $directAccepted, '
      'mailboxStored: $mailboxStored, route: ${directRoute.name})';
}

enum _CallSignalingLeg {
  directSend('direct_send'),
  mailboxStore('mailbox_store');

  const _CallSignalingLeg(this.operation);

  final String operation;
}

/// Encodes one canonical signal exactly once, then races the dedicated direct
/// stream and ephemeral call mailbox. Neither leg uses chat serialization,
/// durable chat outbox, or the generic retrier.
final class CallSignalingService {
  CallSignalingService({
    required SecureCallEnvelopeCodec codec,
    required CallDirectTransport directTransport,
    required CallMailboxClient mailboxClient,
    // Transport-only runtimes (the headless decline reply) pass no
    // coordinator: [transmit] works, [send] fails closed.
    CallCoordinator? coordinator,
    required CallNetworkEffectsAllowed networkEffectsAllowed,
    int Function()? nowMs,
    double Function()? retryJitter,
  }) : _codec = codec,
       _directTransport = directTransport,
       _mailboxClient = mailboxClient,
       _coordinator = coordinator,
       _networkEffectsAllowed = networkEffectsAllowed,
       _nowMs = nowMs ?? _systemNowMs,
       _retryJitter = retryJitter ?? Random().nextDouble;

  final SecureCallEnvelopeCodec _codec;
  final CallDirectTransport _directTransport;
  final CallMailboxClient _mailboxClient;
  final CallCoordinator? _coordinator;
  final CallNetworkEffectsAllowed _networkEffectsAllowed;
  final int Function() _nowMs;
  final double Function() _retryJitter;
  final Map<String, _TerminalSignalRetry> _terminalRetries = {};
  final Map<String, CallSignalTransmissionRetry> _transmissionRetries = {};
  // Separate optional-media custody cannot evict a v1 negotiation or terminal.
  final Map<String, CallSignalTransmissionRetry> _v2Retries = {};
  // No bytes or owner callbacks: fail closed rather than forget a live identity.
  final Map<String, int> _v2Identities = {};
  static const _maxV2Identities = 128;
  bool _closed = false;
  bool _terminalRetriesStopped = false;

  static const _terminalRetryBudget = Duration(seconds: 15);
  static const _maxTerminalRetries = 5;
  static const _maxPendingTerminalRetries = 4;
  static int _systemNowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Prepares one v2 envelope without writing either transport leg.
  Future<CallSignalTransmissionRetry> prepareV2({
    required CallSignalV2 signal,
    required String callHandle,
    required ResolvedCallEndpoint endpoint,
    required String senderSigningPrivateKey,
    required Future<bool> Function() authorize,
    required bool Function() canApply,
    bool videoEnabled = false,
  }) async {
    if (!videoEnabled || _closed || _terminalRetriesStopped || !canApply()) {
      throw const CallSignalingException(
        CallSignalingErrorCode.migrationPaused,
      );
    }
    bool current() =>
        !_closed &&
        !_terminalRetriesStopped &&
        canApply() &&
        _nowMs() < signal.expiresAtMs &&
        _validV2Endpoint(
          endpoint,
          signal.recipientAccountPeerId,
          signal.recipientDevicePeerId,
        );
    if (!current()) {
      throw const CallSignalingException(
        CallSignalingErrorCode.endpointMismatch,
      );
    }
    final terminalPriority =
        signal.event == CallSignalV2Type.reject ||
        signal.event == CallSignalV2Type.terminate;
    final key = '${signal.callId.value}:${signal.messageId}';
    _v2Identities.removeWhere((_, expiry) => _nowMs() >= expiry);
    // Optional churn cannot fill the last terminal identity slots either.
    final identityLimit =
        _maxV2Identities - (terminalPriority ? 0 : _maxPendingTerminalRetries);
    if (_v2Identities.containsKey(key) ||
        _v2Identities.length >= identityLimit) {
      throw const CallSignalingException(
        CallSignalingErrorCode.transportUnavailable,
      );
    }
    // Reserve before the first await, including unsuccessful preparation. The
    // root caches this preparation Future and never regenerates a closed ID.
    _v2Identities[key] = signal.expiresAtMs;
    final localDeadlineMs = _nowMs() + _terminalRetryBudget.inMilliseconds;
    if (!await callNetworkEffectsAreAllowed(_networkEffectsAllowed) ||
        !current()) {
      throw const CallSignalingException(
        CallSignalingErrorCode.migrationPaused,
      );
    }
    if (!await authorize() || !current()) {
      throw const CallSignalingException(
        CallSignalingErrorCode.endpointMismatch,
      );
    }
    final envelope = await _codec.encodeV2(
      signal: signal,
      callHandle: callHandle,
      recipientMlKemPublicKey: endpoint.mlKemPublicKey,
      senderSigningPrivateKey: senderSigningPrivateKey,
    );
    if (!current() || _nowMs() >= localDeadlineMs) {
      throw const CallSignalingException(
        CallSignalingErrorCode.endpointMismatch,
      );
    }
    final retry = _retainTransmission(
      signal: signal,
      callHandle: callHandle,
      endpoint: endpoint,
      envelope: envelope,
      replayable: true,
      terminalPriority: terminalPriority,
      localDeadlineMs: localDeadlineMs,
      protectedResult: switch (signal.event) {
        CallSignalV2Type.reject ||
        CallSignalV2Type.terminate ||
        CallSignalV2Type.mediaResponse ||
        CallSignalV2Type.mediaCommit ||
        CallSignalV2Type.mediaCommitAck ||
        CallSignalV2Type.mediaAbort => true,
        _ => false,
      },
    );
    if (retry == null) {
      throw const CallSignalingException(
        CallSignalingErrorCode.transportUnavailable,
      );
    }
    return retry;
  }

  bool _validV2Endpoint(
    ResolvedCallEndpoint endpoint,
    String account,
    String device,
  ) =>
      endpoint.accountPeerId == account &&
      endpoint.devicePeerId == device &&
      _nowMs() < endpoint.expiresAtMs &&
      endpoint.routingHandle.trim().isNotEmpty &&
      _wakeHandleGrammar.hasMatch(endpoint.wakeHandle) &&
      endpoint.capabilities.contains('voice_call_v1') &&
      endpoint.capabilities.contains('video_call_v2');

  /// Only fixed counts are exposed; retained signaling bytes stay private.
  int get pendingTerminalRetryCount => _terminalRetries.length;
  int get pendingTransmissionRetryCount =>
      _transmissionRetries.length + _v2Retries.length;

  /// Quiesces retry work immediately while preserving the coordinator's one
  /// normal appShutdown terminal send. No failed send can re-arm retries.
  void stopRetries() {
    if (_terminalRetriesStopped) return;
    _terminalRetriesStopped = true;
    for (final entry in _terminalRetries.values.toList(growable: false)) {
      _removeTerminalRetry(entry);
    }
    for (final entry in [
      ..._transmissionRetries.values,
      ..._v2Retries.values,
    ]) {
      entry.close();
    }
  }

  /// Closes all signaling after runtime/coordinator shutdown settles. Already
  /// submitted writes remain bounded by their transport owner.
  void close() {
    if (_closed) return;
    _closed = true;
    stopRetries();
  }

  static final RegExp _wakeHandleGrammar = RegExp(r'^[0-9a-f]{32}$');

  Future<CallSignalTransportResult> send({
    required CallSignal signal,
    required String callHandle,
    required ResolvedCallEndpoint endpoint,
    required String senderSigningPrivateKey,
  }) async {
    final result = await transmit(
      signal: signal,
      callHandle: callHandle,
      endpoint: endpoint,
      senderSigningPrivateKey: senderSigningPrivateKey,
    );

    await _dispatchReceipts(signal: signal, result: result);
    return result;
  }

  /// Performs only the dedicated call-network writes and returns their
  /// receipts. Effect executors use this entrypoint because they already run
  /// inside the coordinator's serialized dispatch lane; receipt events are
  /// returned to that lane instead of recursively dispatching here.
  Future<CallSignalTransportResult> transmit({
    required CallSignal signal,
    required String callHandle,
    required ResolvedCallEndpoint endpoint,
    required String senderSigningPrivateKey,
    Future<bool> Function()? authorizeTerminalRetry,
    bool retainForRetry = false,
    bool Function()? canApply,
  }) async {
    if (_closed || canApply?.call() == false) {
      throw const CallSignalingException(
        CallSignalingErrorCode.migrationPaused,
      );
    }
    var networkEffectsAllowed = false;
    try {
      networkEffectsAllowed = await callNetworkEffectsAreAllowed(
        _networkEffectsAllowed,
      );
    } catch (_) {
      networkEffectsAllowed = false;
    }
    if (_closed || !networkEffectsAllowed || canApply?.call() == false) {
      throw const CallSignalingException(
        CallSignalingErrorCode.migrationPaused,
      );
    }
    if (signal.recipientAccountPeerId != endpoint.accountPeerId ||
        signal.recipientDevicePeerId != endpoint.devicePeerId ||
        endpoint.expiresAtMs <= signal.createdAtMs ||
        endpoint.routingHandle.trim().isEmpty ||
        !_wakeHandleGrammar.hasMatch(endpoint.wakeHandle)) {
      throw const CallSignalingException(
        CallSignalingErrorCode.endpointMismatch,
      );
    }

    final envelope = await _codec.encode(
      signal: signal,
      callHandle: callHandle,
      recipientMlKemPublicKey: endpoint.mlKemPublicKey,
      senderSigningPrivateKey: senderSigningPrivateKey,
    );

    if (_closed || canApply?.call() == false) {
      throw const CallSignalingException(
        CallSignalingErrorCode.migrationPaused,
      );
    }
    // Invoke both before awaiting either so a slow/unreachable direct path can
    // never delay custody at the call mailbox.
    final directFuture = _sendDirect(
      callHandle: callHandle,
      recipientDevicePeerId: endpoint.devicePeerId,
      envelopeJson: envelope,
    );
    final mailboxFuture = _storeMailbox(
      messageId: signal.messageId,
      createdAtMs: signal.createdAtMs,
      expiresAtMs: signal.expiresAtMs,
      callHandle: callHandle,
      endpoint: endpoint,
      envelope: envelope,
    );
    try {
      return await _firstSufficientResult(
        directFuture: directFuture,
        mailboxFuture: mailboxFuture,
      );
    } on CallSignalingException catch (error) {
      if (error.code == CallSignalingErrorCode.transportUnavailable &&
          authorizeTerminalRetry != null &&
          (signal.event == CallSignalType.terminate ||
              signal.event == CallSignalType.reject)) {
        _retainTerminalRetry(
          signal: signal,
          callHandle: callHandle,
          endpoint: endpoint,
          envelope: envelope,
          authorize: authorizeTerminalRetry,
        );
      }
      if (error.code == CallSignalingErrorCode.transportUnavailable &&
          retainForRetry &&
          (signal.event == CallSignalType.offer ||
              signal.event == CallSignalType.answer ||
              signal.event == CallSignalType.ice ||
              signal.event == CallSignalType.iceRestart)) {
        throw CallSignalingException(
          error.code,
          retry: _retainTransmission(
            signal: signal,
            callHandle: callHandle,
            endpoint: endpoint,
            envelope: envelope,
          ),
        );
      }
      // The original result is unchanged. Local terminal cleanup must never
      // await connectivity restoration or keep a media/native owner alive.
      rethrow;
    }
  }

  void _retainTerminalRetry({
    required CallSignal signal,
    required String callHandle,
    required ResolvedCallEndpoint endpoint,
    required String envelope,
    required Future<bool> Function() authorize,
  }) {
    final deadlineMs = min(
      min(signal.expiresAtMs, endpoint.expiresAtMs),
      signal.createdAtMs + _terminalRetryBudget.inMilliseconds,
    );
    if (_closed || _terminalRetriesStopped || _nowMs() >= deadlineMs) return;
    if (_terminalRetries.containsKey(signal.callId.value)) return;
    while (_terminalRetries.length >= _maxPendingTerminalRetries) {
      _removeTerminalRetry(_terminalRetries.values.first);
    }
    final entry = _TerminalSignalRetry(
      signal: signal,
      callHandle: callHandle,
      endpoint: endpoint,
      envelope: envelope,
      authorize: authorize,
      deadlineMs: deadlineMs,
    );
    _terminalRetries[signal.callId.value] = entry;
    // This timer also retires retained bytes when authorization or transport
    // stays pending. Its completion cannot start a successor retry.
    entry.expiryTimer = Timer(
      Duration(milliseconds: deadlineMs - _nowMs()),
      () => _removeTerminalRetry(entry),
    );
    _scheduleTerminalRetry(entry);
  }

  bool _terminalRetryIsCurrent(_TerminalSignalRetry entry) =>
      !_closed &&
      !_terminalRetriesStopped &&
      identical(_terminalRetries[entry.callKey], entry) &&
      _nowMs() < entry.deadlineMs;

  void _removeTerminalRetry(_TerminalSignalRetry entry) {
    if (!identical(_terminalRetries[entry.callKey], entry)) return;
    _terminalRetries.remove(entry.callKey);
    entry.retryTimer?.cancel();
    entry.expiryTimer?.cancel();
    entry.clear();
  }

  void _scheduleTerminalRetry(_TerminalSignalRetry entry) {
    if (!_terminalRetryIsCurrent(entry) ||
        entry.attempts >= _maxTerminalRetries) {
      _removeTerminalRetry(entry);
      return;
    }
    final baseMs = min(500 * (1 << entry.attempts), 4000);
    final jitter = _retryJitter().clamp(0.0, 1.0);
    final delayMs = (baseMs * (0.8 + 0.4 * jitter)).round();
    if (_nowMs() + delayMs >= entry.deadlineMs) return;
    entry.retryTimer = Timer(
      Duration(milliseconds: delayMs),
      () => unawaited(_retryTerminal(entry)),
    );
  }

  Future<void> _retryTerminal(_TerminalSignalRetry entry) async {
    if (!_terminalRetryIsCurrent(entry)) return;
    entry.attempts++;
    try {
      if (!await callNetworkEffectsAreAllowed(_networkEffectsAllowed) ||
          !_terminalRetryIsCurrent(entry) ||
          !await entry.authorize!() ||
          !_terminalRetryIsCurrent(entry)) {
        _removeTerminalRetry(entry);
        return;
      }
      final result = await _firstSufficientResult(
        directFuture: _sendDirect(
          callHandle: entry.callHandle!,
          recipientDevicePeerId: entry.endpoint!.devicePeerId,
          envelopeJson: entry.envelope!,
        ),
        mailboxFuture: _storeMailbox(
          messageId: entry.signal!.messageId,
          createdAtMs: entry.signal!.createdAtMs,
          expiresAtMs: entry.signal!.expiresAtMs,
          callHandle: entry.callHandle!,
          endpoint: entry.endpoint!,
          envelope: entry.envelope!,
        ),
      );
      if (result.delivered) _removeTerminalRetry(entry);
    } on CallSignalingException catch (error) {
      if (error.code == CallSignalingErrorCode.transportUnavailable) {
        _scheduleTerminalRetry(entry);
      } else {
        _removeTerminalRetry(entry);
      }
    } catch (_) {
      // Identity/authority failures are not transport retry permission.
      _removeTerminalRetry(entry);
    }
  }

  CallSignalTransmissionRetry? _retainTransmission({
    required CallWireSignal signal,
    required String callHandle,
    required ResolvedCallEndpoint endpoint,
    required String envelope,
    bool replayable = false,
    bool protectedResult = false,
    bool terminalPriority = false,
    int? localDeadlineMs,
  }) {
    final deadlineMs = min(
      min(signal.expiresAtMs, endpoint.expiresAtMs),
      min(
        signal.createdAtMs + _terminalRetryBudget.inMilliseconds,
        localDeadlineMs ?? signal.expiresAtMs,
      ),
    );
    if (_closed || _terminalRetriesStopped || _nowMs() >= deadlineMs) {
      return null;
    }
    final key = '${signal.callId.value}:${signal.messageId}';
    final entries = replayable ? _v2Retries : _transmissionRetries;
    entries[key]?.close();
    while (entries.length >= _maxPendingTerminalRetries) {
      CallSignalTransmissionRetry? victim;
      for (final entry in entries.values) {
        if (!entry._protectedResult ||
            (terminalPriority && !entry._terminalPriority)) {
          victim = entry;
          break;
        }
      }
      // Optional churn cannot erase selected results or terminal custody.
      // Terminal delivery takes priority over optional reconciliation material.
      if (victim == null) return null;
      victim.close();
    }
    final retry = CallSignalTransmissionRetry._(
      this,
      key,
      deadlineMs,
      _CallRetryTransmission(
        messageId: signal.messageId,
        createdAtMs: signal.createdAtMs,
        expiresAtMs: signal.expiresAtMs,
        callHandle: callHandle,
        endpoint: endpoint,
        envelope: envelope,
      ),
      replayable: replayable,
      protectedResult: protectedResult,
      terminalPriority: terminalPriority,
    );
    entries[key] = retry;
    retry._expiryTimer = Timer(
      Duration(milliseconds: deadlineMs - _nowMs()),
      retry.close,
    );
    return retry;
  }

  bool _transmissionRetryIsCurrent(CallSignalTransmissionRetry retry) =>
      !_closed &&
      !_terminalRetriesStopped &&
      identical(
        (retry._replayable ? _v2Retries : _transmissionRetries)[retry._key],
        retry,
      ) &&
      retry._transmission != null &&
      _nowMs() < retry._deadlineMs &&
      (!retry._replayable ||
          _validV2Endpoint(
            retry._transmission!.endpoint,
            retry._transmission!.endpoint.accountPeerId,
            retry._transmission!.endpoint.devicePeerId,
          ));

  void _closeTransmissionRetry(CallSignalTransmissionRetry retry) {
    final entries = retry._replayable ? _v2Retries : _transmissionRetries;
    if (identical(entries[retry._key], retry)) entries.remove(retry._key);
    retry._expiryTimer?.cancel();
    retry._transmission = null;
    retry._pendingDirect = null;
    retry._pendingMailbox = null;
  }

  Future<CallSignalTransportResult> _retryTransmission(
    CallSignalTransmissionRetry retry, {
    required Future<bool> Function() authorize,
    required bool Function() canApply,
  }) async {
    if (!_transmissionRetryIsCurrent(retry) ||
        !canApply() ||
        retry._attempts >= 4) {
      retry.close();
      throw const CallSignalingException(
        CallSignalingErrorCode.transportUnavailable,
      );
    }
    retry._attempts++;
    try {
      if (!await callNetworkEffectsAreAllowed(_networkEffectsAllowed) ||
          !_transmissionRetryIsCurrent(retry) ||
          !canApply()) {
        throw const CallSignalingException(
          CallSignalingErrorCode.migrationPaused,
        );
      }
      if (!await authorize() ||
          !_transmissionRetryIsCurrent(retry) ||
          !canApply()) {
        throw const CallSignalingException(
          CallSignalingErrorCode.endpointMismatch,
        );
      }
      final material = retry._transmission!;
      bool admitted() => _transmissionRetryIsCurrent(retry) && canApply();
      // A successful sibling must not make a still pending leg multiply on
      // replay. Settled legs may be retried; pending legs keep the same bytes.
      var direct = retry._replayable ? retry._pendingDirect : null;
      if (direct == null) {
        direct = _sendDirect(
          callHandle: material.callHandle,
          recipientDevicePeerId: material.endpoint.devicePeerId,
          envelopeJson: material.envelope,
          admitted: retry._replayable ? admitted : null,
        );
        if (retry._replayable) {
          final started = direct;
          retry._pendingDirect = started;
          unawaited(
            started.then((_) {
              if (identical(retry._pendingDirect, started)) {
                retry._pendingDirect = null;
              }
            }),
          );
        }
      }
      var mailbox = retry._replayable ? retry._pendingMailbox : null;
      if (mailbox == null) {
        mailbox = _storeMailbox(
          messageId: material.messageId,
          createdAtMs: material.createdAtMs,
          expiresAtMs: material.expiresAtMs,
          callHandle: material.callHandle,
          endpoint: material.endpoint,
          envelope: material.envelope,
          admitted: retry._replayable ? admitted : null,
        );
        if (retry._replayable) {
          final started = mailbox;
          retry._pendingMailbox = started;
          unawaited(
            started.then((_) {
              if (identical(retry._pendingMailbox, started)) {
                retry._pendingMailbox = null;
              }
            }),
          );
        }
      }
      final result = await _firstSufficientResult(
        directFuture: direct,
        mailboxFuture: mailbox,
      );
      if (!_transmissionRetryIsCurrent(retry) || !canApply()) {
        throw const CallSignalingException(
          CallSignalingErrorCode.migrationPaused,
        );
      }
      if (!retry._replayable || retry._attempts >= 4) retry.close();
      return result;
    } on CallSignalingException catch (error) {
      if (error.code != CallSignalingErrorCode.transportUnavailable ||
          !_transmissionRetryIsCurrent(retry) ||
          retry._attempts >= 4 ||
          (retry._replayable && !canApply())) {
        retry.close();
      }
      rethrow;
    } catch (_) {
      retry.close();
      rethrow;
    }
  }

  Future<CallSignalTransportResult> _firstSufficientResult({
    required Future<CallDirectSendResult> directFuture,
    required Future<_MailboxLegResult> mailboxFuture,
  }) {
    final result = Completer<CallSignalTransportResult>();
    final mailboxStoreSettled = mailboxFuture.then<void>((_) {});
    CallDirectSendResult? direct;
    bool? mailboxStored;
    var wakeDispatched = false;
    var resolutionQueued = false;

    void resolve() {
      resolutionQueued = false;
      if (result.isCompleted) return;

      final currentDirect = direct;
      final currentMailboxStored = mailboxStored;
      if ((currentDirect?.accepted ?? false) || currentMailboxStored == true) {
        result.complete(
          CallSignalTransportResult._race(
            directAccepted: currentDirect?.accepted ?? false,
            mailboxStored: currentMailboxStored ?? false,
            directRoute: currentDirect?.route ?? CallDirectRoute.unknown,
            directSettled: currentDirect != null,
            mailboxStoreSettled: mailboxStoreSettled,
            wakeDispatched: wakeDispatched,
          ),
        );
        return;
      }
      if (currentDirect != null && currentMailboxStored != null) {
        result.completeError(
          const CallSignalingException(
            CallSignalingErrorCode.transportUnavailable,
          ),
        );
      }
    }

    void queueResolution() {
      if (result.isCompleted || resolutionQueued) return;
      resolutionQueued = true;
      // Preserve receipts from legs that settle in the same event-loop turn
      // without waiting for a genuinely slow or hung sibling transport.
      scheduleMicrotask(resolve);
    }

    unawaited(
      directFuture.then<void>((value) {
        direct = value;
        queueResolution();
      }),
    );
    unawaited(
      mailboxFuture.then<void>((value) {
        mailboxStored = value.stored;
        wakeDispatched = value.wakeDispatched;
        queueResolution();
      }),
    );
    return result.future;
  }

  Future<void> _dispatchReceipts({
    required CallSignal signal,
    required CallSignalTransportResult result,
  }) async {
    final coordinator = _coordinator;
    if (coordinator == null) {
      throw StateError('receipt dispatch requires a coordinator');
    }
    // Mailbox custody can win while direct is still unresolved. Do not turn
    // that provisional false value into a synthetic direct-failure event.
    if (result._directSettled) {
      await coordinator.dispatch(
        CallEvent(
          type: result.directAccepted
              ? CallEventType.directAccepted
              : CallEventType.directFailed,
          eventId:
              '${signal.messageId}:${result.directAccepted ? 'direct-ok' : 'direct-failed'}',
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            signal.createdAtMs,
            isUtc: true,
          ),
          callId: signal.callId,
          contactPeerId: signal.recipientAccountPeerId,
          localAccountPeerId: signal.senderAccountPeerId,
          localDeviceId: signal.senderDevicePeerId,
          remoteAccountPeerId: signal.recipientAccountPeerId,
          remoteDeviceId: signal.recipientDevicePeerId,
          transportRoute: _routeClass(result.directRoute),
        ),
      );
    }
    if (result.mailboxStored) {
      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.mailboxStored,
          eventId: '${signal.messageId}:mailbox-stored',
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            signal.createdAtMs,
            isUtc: true,
          ),
          callId: signal.callId,
          contactPeerId: signal.recipientAccountPeerId,
          localAccountPeerId: signal.senderAccountPeerId,
          localDeviceId: signal.senderDevicePeerId,
          remoteAccountPeerId: signal.recipientAccountPeerId,
          remoteDeviceId: signal.recipientDevicePeerId,
          transportRoute: CallRouteClass.ephemeralMailbox,
        ),
      );
    }
    if (result.wakeDispatched) {
      // The relay alerted the callee's device. A headless callee rings
      // without signalling anything until it is answered, so this receipt is
      // the caller's only sign that the far end is being alerted.
      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.wakeRequested,
          eventId: '${signal.messageId}:wake-dispatched',
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            signal.createdAtMs,
            isUtc: true,
          ),
          callId: signal.callId,
          contactPeerId: signal.recipientAccountPeerId,
          localAccountPeerId: signal.senderAccountPeerId,
          localDeviceId: signal.senderDevicePeerId,
          remoteAccountPeerId: signal.recipientAccountPeerId,
          remoteDeviceId: signal.recipientDevicePeerId,
          transportRoute: CallRouteClass.ephemeralMailbox,
        ),
      );
    }
  }

  Future<CallDirectSendResult> _sendDirect({
    required String callHandle,
    required String recipientDevicePeerId,
    required String envelopeJson,
    bool Function()? admitted,
  }) async {
    final diagnostics = CallDiagnostics.instance;
    final traceId = diagnostics.traceForCall(callHandle: callHandle);
    diagnostics.record(
      stage: 'signaling',
      action: 'send_direct',
      outcome: 'started',
      traceId: traceId,
    );
    try {
      if (admitted != null && !admitted()) {
        throw const CallSignalingException(
          CallSignalingErrorCode.endpointMismatch,
        );
      }
      admitted = null; // Do not retain owner callbacks across transport waits.
      final result = await _directTransport.send(
        recipientDevicePeerId: recipientDevicePeerId,
        envelopeJson: envelopeJson,
      );
      diagnostics.record(
        stage: 'signaling',
        action: 'send_direct',
        outcome: result.accepted ? 'ok' : 'failed',
        reason: result.accepted ? 'none' : 'transport_failed',
        traceId: traceId,
      );
      _emitLegResult(_CallSignalingLeg.directSend, result.accepted);
      return result;
    } catch (_) {
      diagnostics.record(
        stage: 'signaling',
        action: 'send_direct',
        outcome: 'failed',
        reason: 'transport_failed',
        traceId: traceId,
      );
      _emitLegResult(_CallSignalingLeg.directSend, false);
      // A failed direct leg cannot erase committed mailbox custody.
      return const CallDirectSendResult(
        outcome: CallDirectTransportOutcome.failed,
        transportAcknowledged: false,
        route: CallDirectRoute.unknown,
      );
    }
  }

  Future<_MailboxLegResult> _storeMailbox({
    required String messageId,
    required int createdAtMs,
    required int expiresAtMs,
    required String callHandle,
    required ResolvedCallEndpoint endpoint,
    required String envelope,
    bool Function()? admitted,
  }) async {
    final diagnostics = CallDiagnostics.instance;
    final traceId = diagnostics.traceForCall(callHandle: callHandle);
    void record(bool stored) => diagnostics.record(
      stage: 'signaling',
      action: 'commit',
      outcome: stored ? 'ok' : 'failed',
      reason: stored ? 'none' : 'transport_failed',
      traceId: traceId,
      values: <String, Object?>{'storeCommitted': stored},
    );
    try {
      if (admitted != null && !admitted()) {
        throw const CallSignalingException(
          CallSignalingErrorCode.endpointMismatch,
        );
      }
      admitted = null; // Do not retain owner callbacks across transport waits.
      final result = await _mailboxClient.store(
        CallMailboxStoreRequest(
          recipientDevicePeerId: endpoint.devicePeerId,
          callHandle: callHandle,
          messageId: messageId,
          envelopeJson: envelope,
          expiresAtMs: expiresAtMs,
          wakeHandle: endpoint.wakeHandle,
        ),
      );
      final stored =
          result.expiresAtMs > createdAtMs && result.expiresAtMs <= expiresAtMs;
      record(stored);
      _emitLegResult(
        _CallSignalingLeg.mailboxStore,
        stored,
        wake: result.wake.name,
      );
      return (
        stored: stored,
        wakeDispatched:
            stored && result.wake == CallMailboxWakeStatus.dispatched,
      );
    } catch (_) {
      record(false);
      _emitLegResult(_CallSignalingLeg.mailboxStore, false);
      return (stored: false, wakeDispatched: false);
    }
  }

  static void _emitLegResult(
    _CallSignalingLeg leg,
    bool result, {
    String? wake,
  }) {
    try {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_SIGNALING_LEG_RESULT',
        details: <String, Object?>{
          'operation': leg.operation,
          'result': result,
          'wake': ?wake,
        },
      );
    } catch (_) {
      // Identifier-free diagnostics cannot change signaling behavior.
    }
  }

  static CallRouteClass? _routeClass(CallDirectRoute route) => switch (route) {
    CallDirectRoute.direct => CallRouteClass.direct,
    CallDirectRoute.circuitRelay => CallRouteClass.circuitRelay,
    CallDirectRoute.unknown => null,
  };
}

typedef _MailboxLegResult = ({bool stored, bool wakeDispatched});

/// Call-owned encrypted delivery material only. No signer key, raw context,
/// native resource, media owner, or coordinator event survives local cleanup.
final class _TerminalSignalRetry {
  _TerminalSignalRetry({
    required this.signal,
    required this.callHandle,
    required this.endpoint,
    required this.envelope,
    required this.authorize,
    required this.deadlineMs,
  }) : callKey = signal!.callId.value;

  final String callKey;
  CallSignal? signal;
  String? callHandle;
  ResolvedCallEndpoint? endpoint;
  String? envelope;
  Future<bool> Function()? authorize;
  final int deadlineMs;

  void clear() {
    signal = null;
    callHandle = null;
    endpoint = null;
    envelope = null;
    authorize = null;
  }

  int attempts = 0;
  Timer? retryTimer;
  Timer? expiryTimer;
}

/// Opaque, disposable resubmission of one already encrypted negotiation signal.
/// It contains no plaintext SDP/candidates, sender key or coordinator state.
/// The caller owns scheduling and the stricter canonical reconnect deadline.
final class CallSignalTransmissionRetry {
  CallSignalTransmissionRetry._(
    this._owner,
    this._key,
    this._deadlineMs,
    this._transmission, {
    bool replayable = false,
    bool protectedResult = false,
    bool terminalPriority = false,
  }) : _replayable = replayable,
       _protectedResult = protectedResult,
       _terminalPriority = terminalPriority;

  final CallSignalingService _owner;
  final String _key;
  final int _deadlineMs;
  final bool _replayable;
  final bool _protectedResult;
  final bool _terminalPriority;
  Future<CallDirectSendResult>? _pendingDirect;
  Future<_MailboxLegResult>? _pendingMailbox;
  _CallRetryTransmission? _transmission;
  Timer? _expiryTimer;
  Future<CallSignalTransportResult>? _inFlight;
  int _attempts = 0;

  Future<CallSignalTransportResult> retry({
    required Future<bool> Function() authorize,
    required bool Function() canApply,
  }) {
    final running = _inFlight;
    if (running != null) return running;
    late final Future<CallSignalTransportResult> work;
    work = _owner
        ._retryTransmission(this, authorize: authorize, canApply: canApply)
        .whenComplete(() {
          if (identical(_inFlight, work)) _inFlight = null;
        });
    _inFlight = work;
    return work;
  }

  bool get isAvailable => _owner._transmissionRetryIsCurrent(this);

  void close() => _owner._closeTransmissionRetry(this);

  @override
  String toString() => 'CallSignalTransmissionRetry';
}

final class _CallRetryTransmission {
  const _CallRetryTransmission({
    required this.messageId,
    required this.createdAtMs,
    required this.expiresAtMs,
    required this.callHandle,
    required this.endpoint,
    required this.envelope,
  });
  final String messageId;
  final int createdAtMs;
  final int expiresAtMs;
  final String callHandle;
  final ResolvedCallEndpoint endpoint;
  final String envelope;
}
