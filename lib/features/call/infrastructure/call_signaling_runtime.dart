import 'dart:async';

import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../application/call_coordinator.dart';
import '../application/call_network_gate.dart';
import '../application/handle_incoming_call_signal.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import 'call_mailbox_client.dart';

typedef HandleCallSignalFrame =
    Future<IncomingCallSignalOutcome> Function(IncomingCallSignalFrame frame);

typedef PeekCallSignalFrame =
    Future<IncomingCallSignalPeek?> Function(IncomingCallSignalFrame frame);

/// Owns only call signaling resources: one dedicated router subscription, a
/// serial inbound lane, and call-mailbox resume drains. It never owns or tears
/// down the shared router, P2P service, bridge, or chat lifecycle.
final class CallSignalingRuntime {
  CallSignalingRuntime({
    required Stream<ChatMessage> directCallSignalStream,
    required CallMailboxClient mailboxClient,
    required HandleCallSignalFrame handleIncoming,
    PeekCallSignalFrame? peekIncoming,
    required CallCoordinator coordinator,
    required CallNetworkEffectsAllowed networkEffectsAllowed,
    this.maxMailboxPagesPerDrain = 8,
    this.maxPendingOperations = 64,
  }) : _directCallSignalStream = directCallSignalStream,
       _mailboxClient = mailboxClient,
       _handleIncoming = handleIncoming,
       _peekIncoming = peekIncoming,
       _coordinator = coordinator,
       _networkEffectsAllowed = networkEffectsAllowed {
    if (maxMailboxPagesPerDrain < 1 || maxMailboxPagesPerDrain > 32) {
      throw ArgumentError.value(
        maxMailboxPagesPerDrain,
        'maxMailboxPagesPerDrain',
      );
    }
    if (maxPendingOperations < 1 || maxPendingOperations > 64) {
      throw ArgumentError.value(maxPendingOperations, 'maxPendingOperations');
    }
  }

  final Stream<ChatMessage> _directCallSignalStream;
  final CallMailboxClient _mailboxClient;
  final HandleCallSignalFrame _handleIncoming;
  final PeekCallSignalFrame? _peekIncoming;
  final CallCoordinator _coordinator;
  final CallNetworkEffectsAllowed _networkEffectsAllowed;
  final int maxMailboxPagesPerDrain;
  final int maxPendingOperations;

  StreamSubscription<ChatMessage>? _directSubscription;
  Future<bool>? _startInFlight;
  Future<void> _serialTail = Future<void>.value();
  int _pendingOperations = 0;
  bool _disposed = false;
  bool _shuttingDown = false;

  bool get isStarted => _directSubscription != null && !_disposed;
  bool get isDisposed => _disposed;

  /// Starts the dedicated direct-call listener.
  ///
  /// Returns true only when the listener was already active or this attempt
  /// installed it. A denied/throwing network gate, disposal race, or stream
  /// subscription failure returns false so callers cannot advertise call
  /// capability without an inbound listener.
  Future<bool> start() {
    if (_disposed || _shuttingDown) return Future<bool>.value(false);
    if (isStarted) return Future<bool>.value(true);
    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;
    final attempt = _startInternal();
    _startInFlight = attempt;
    return attempt.whenComplete(() {
      if (identical(_startInFlight, attempt)) _startInFlight = null;
    });
  }

  Future<bool> _startInternal() async {
    if (!await _networkEffectsAreAllowed() || _disposed || _shuttingDown) {
      return false;
    }
    if (isStarted) return true;
    try {
      _directSubscription = _directCallSignalStream.listen(
        (message) => unawaited(_enqueue(() => _handleDirect(message))),
        onError: (_, _) {
          // The shared router owns stream recovery. Call runtime diagnostics
          // are intentionally coarse and this lane waits for later events.
        },
      );
    } catch (_) {
      _directSubscription = null;
      return false;
    }
    // A fresh foreground launch does not receive an initial resumed callback.
    // Drain once after listener installation so invites retained across an
    // unclean process death are not stranded until a later lifecycle cycle.
    await _enqueue(_drainMailbox);
    return isStarted;
  }

  /// Runs the call-specific mailbox drain independently of chat resume work.
  Future<void> onResume() async {
    if (_disposed) return;
    if (!await start() || !await _networkEffectsAreAllowed()) {
      return;
    }
    await _enqueue(_drainMailbox);
  }

  Future<void> _handleDirect(ChatMessage message) async {
    if (_disposed ||
        !message.isIncoming ||
        !await _networkEffectsAreAllowed()) {
      return;
    }
    await _handleIncoming(
      IncomingCallSignalFrame(
        envelopeJson: message.content,
        authenticatedTransportPeerId: message.from,
        route: _directRoute(message.transport),
      ),
    );
  }

  Future<void> _drainMailbox() async {
    for (
      var pageIndex = 0;
      pageIndex < maxMailboxPagesPerDrain && !_disposed;
      pageIndex++
    ) {
      late final CallMailboxRetrieveResult page;
      try {
        page = await _mailboxClient.retrieve();
      } catch (_) {
        return;
      }
      final superseded = await _supersededInvites(page.events);
      for (var index = 0; index < page.events.length; index++) {
        final event = page.events[index];
        if (_disposed) return;
        late final IncomingCallSignalOutcome outcome;
        try {
          outcome = await _handleIncoming(
            _frameFor(event, terminalFollows: superseded.contains(index)),
          );
        } catch (_) {
          // Transient application/authority failure retains mailbox custody.
          return;
        }
        if (outcome == IncomingCallSignalOutcome.deferred) {
          return;
        }
        try {
          final acked = await _mailboxClient.ack(
            callHandle: event.callHandle,
            messageIds: <String>[event.messageId],
          );
          if (acked != 1) return;
        } catch (_) {
          // Custody remains at the call mailbox and will replay on next resume.
          return;
        }
      }
      if (!page.hasMore) return;
    }
  }

  IncomingCallSignalFrame _frameFor(
    CallMailboxEvent event, {
    bool terminalFollows = false,
  }) => IncomingCallSignalFrame(
    envelopeJson: event.envelopeJson,
    authenticatedTransportPeerId: event.authenticatedSenderDevicePeerId,
    route: CallRouteClass.ephemeralMailbox,
    expectedCallHandle: event.callHandle,
    expectedMessageId: event.messageId,
    expectedExpiresAtMs: event.expiresAtMs,
    expectedRecipientDevicePeerId: event.recipientDevicePeerId,
    terminalFollows: terminalFollows,
  );

  /// Indexes of invites in [events] whose call also has a terminal signal in
  /// the same page. Peeking never consumes an event. A peek that fails leaves
  /// its event unmarked, which at worst rings for a call the next frame ends.
  Future<Set<int>> _supersededInvites(List<CallMailboxEvent> events) async {
    final peek = _peekIncoming;
    if (peek == null || events.length < 2) return const <int>{};
    final peeks = <IncomingCallSignalPeek?>[];
    for (final event in events) {
      if (_disposed) return const <int>{};
      IncomingCallSignalPeek? result;
      try {
        result = await peek(_frameFor(event));
      } catch (_) {
        result = null;
      }
      peeks.add(result);
    }
    final endedCalls = <CallId>{
      for (final peek in peeks)
        if (peek != null && peek.isTerminal) peek.callId,
    };
    final superseded = <int>{};
    for (var index = 0; index < peeks.length; index++) {
      final peek = peeks[index];
      if (peek != null && peek.isInvite && endedCalls.contains(peek.callId)) {
        superseded.add(index);
      }
    }
    return superseded;
  }

  Future<void> settle() => _serialTail;

  Future<void> _enqueue(Future<void> Function() operation) {
    if (_disposed || _pendingOperations >= maxPendingOperations) {
      return Future<void>.value();
    }
    _pendingOperations++;
    final scheduled = _serialTail.then<void>((_) => operation());
    final guarded = scheduled.catchError((_) {
      // Fail closed without logging event payloads or transport identities.
    });
    final completion = guarded.whenComplete(() => _pendingOperations--);
    _serialTail = completion;
    return completion;
  }

  Future<void> shutdown() async {
    if (_disposed || _shuttingDown) return;
    _shuttingDown = true;
    try {
      await _startInFlight;
      _disposed = true;
      await _directSubscription?.cancel();
      _directSubscription = null;
      try {
        await _serialTail;
      } catch (_) {
        // Coordinator shutdown must still terminalize an active call.
      }
      await _coordinator.dispose();
    } finally {
      _disposed = true;
      _shuttingDown = false;
    }
  }

  Future<void> dispose() => shutdown();

  Future<bool> _networkEffectsAreAllowed() async {
    try {
      return await callNetworkEffectsAreAllowed(_networkEffectsAllowed);
    } catch (_) {
      return false;
    }
  }

  static CallRouteClass _directRoute(String? transport) {
    final normalized = transport?.toLowerCase() ?? '';
    if (normalized.contains('relay') || normalized.contains('circuit')) {
      return CallRouteClass.circuitRelay;
    }
    return CallRouteClass.direct;
  }
}
