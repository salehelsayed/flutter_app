import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

import '../application/call_audio_controller.dart';
import '../application/foreground_call_capability.dart';
import '../domain/call_engine.dart';
import '../domain/call_end_reason.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';
import 'screens/active_call_screen.dart';
import 'screens/incoming_call_screen.dart';
import 'screens/outgoing_call_screen.dart';
import 'widgets/call_controls.dart';

typedef ContactDisplayNameLoader =
    Future<String?> Function(String contactPeerId);

/// Root-owned foreground call surface layered above the retained app navigator.
///
/// This widget projects canonical state only. It does not push or pop routes,
/// create reducer events, own a call state machine, or optimistically update
/// audio controls.
final class ForegroundCallOverlay extends StatefulWidget {
  const ForegroundCallOverlay({
    super.key,
    required this.capability,
    required this.loadContactDisplayName,
    required this.child,
    this.now,
  });

  final ForegroundCallCapability? capability;
  final ContactDisplayNameLoader loadContactDisplayName;
  final Widget child;
  final DateTime Function()? now;

  @override
  State<ForegroundCallOverlay> createState() => _ForegroundCallOverlayState();
}

class _ForegroundCallOverlayState extends State<ForegroundCallOverlay> {
  static const Duration _terminalNoticeDuration = Duration(seconds: 6);
  static const String _unknownContactName = 'Unknown contact';
  static const String _speakerUnavailableMessage =
      'Speaker is unavailable for the current audio route';
  static const String _muteUnavailableMessage =
      'Microphone controls are unavailable until audio is ready';

  StreamSubscription<ForegroundCallProjection?>? _subscription;
  ForegroundCallProjection? _projection;
  CallId? _nameCallId;
  String? _namePeerId;
  String _contactDisplayName = _unknownContactName;
  int _capabilityGeneration = 0;
  int _nameGeneration = 0;
  Timer? _terminalNoticeTimer;
  CallId? _terminalNoticeCallId;
  bool _terminalNoticeVisible = false;

  @override
  void initState() {
    super.initState();
    _bindCapability(notify: false);
  }

  @override
  void didUpdateWidget(covariant ForegroundCallOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.capability, widget.capability)) {
      _bindCapability(notify: false);
      return;
    }
    if (!identical(
      oldWidget.loadContactDisplayName,
      widget.loadContactDisplayName,
    )) {
      _nameCallId = null;
      _namePeerId = null;
      _applyProjection(_projection, notify: false);
    }
  }

  @override
  void dispose() {
    _capabilityGeneration += 1;
    _nameGeneration += 1;
    unawaited(_subscription?.cancel());
    _terminalNoticeTimer?.cancel();
    super.dispose();
  }

  void _bindCapability({required bool notify}) {
    final generation = ++_capabilityGeneration;
    unawaited(_subscription?.cancel());
    _subscription = null;

    final capability = widget.capability;
    ForegroundCallProjection? current;
    if (capability != null) {
      try {
        current = capability.current;
      } catch (_) {
        current = null;
      }
    }
    _applyProjection(current, notify: notify);

    if (capability == null) return;
    try {
      _subscription = capability.changes.listen(
        (projection) {
          if (generation != _capabilityGeneration || !mounted) return;
          _applyProjection(projection, notify: true);
        },
        onError: (Object _) {
          if (generation != _capabilityGeneration || !mounted) return;
          _applyProjection(null, notify: true);
        },
        onDone: () {
          if (generation != _capabilityGeneration || !mounted) return;
          _applyProjection(null, notify: true);
        },
      );
    } catch (_) {
      _applyProjection(null, notify: notify);
    }
  }

  void _applyProjection(
    ForegroundCallProjection? projection, {
    required bool notify,
  }) {
    CallId? lookupCallId;
    String? lookupPeerId;
    late int lookupGeneration;
    CallId? terminalNoticeToSchedule;

    void update() {
      _projection = projection;
      final session = projection?.session;
      final surfaceKind = _surfaceKind(session);
      final terminalCallId = surfaceKind == _ForegroundCallSurface.terminal
          ? session?.callId
          : null;
      if (terminalCallId != _terminalNoticeCallId) {
        _terminalNoticeTimer?.cancel();
        _terminalNoticeTimer = null;
        _terminalNoticeCallId = terminalCallId;
        _terminalNoticeVisible = terminalCallId != null;
        terminalNoticeToSchedule = terminalCallId;
      }

      if (surfaceKind == _ForegroundCallSurface.hidden ||
          surfaceKind == _ForegroundCallSurface.terminal) {
        _nameGeneration += 1;
        _nameCallId = null;
        _namePeerId = null;
        _contactDisplayName = _unknownContactName;
        return;
      }

      final callId = session?.callId;
      final peerId = session?.contactPeerId;
      if (callId == null || peerId == null) return;
      if (_nameCallId == callId && _namePeerId == peerId) return;

      _nameCallId = callId;
      _namePeerId = peerId;
      _contactDisplayName = _unknownContactName;
      lookupCallId = callId;
      lookupPeerId = peerId;
      lookupGeneration = ++_nameGeneration;
    }

    if (notify) {
      setState(update);
    } else {
      update();
    }

    final terminalCallId = terminalNoticeToSchedule;
    if (terminalCallId != null) {
      _terminalNoticeTimer = Timer(
        _terminalNoticeDuration,
        () => _dismissTerminalNotice(callId: terminalCallId),
      );
    }

    final callId = lookupCallId;
    final peerId = lookupPeerId;
    if (callId != null && peerId != null) {
      unawaited(_loadContactName(callId, peerId, lookupGeneration));
    }
  }

  Future<void> _loadContactName(
    CallId callId,
    String peerId,
    int generation,
  ) async {
    String? loadedName;
    try {
      loadedName = await widget.loadContactDisplayName(peerId);
    } catch (_) {
      loadedName = null;
    }
    if (!mounted ||
        generation != _nameGeneration ||
        _nameCallId != callId ||
        _namePeerId != peerId) {
      return;
    }

    final normalizedName = loadedName?.trim();
    setState(() {
      _contactDisplayName = normalizedName == null || normalizedName.isEmpty
          ? _unknownContactName
          : normalizedName;
    });
  }

  @override
  Widget build(BuildContext context) {
    final projection = _projection;
    final session = projection?.session;
    final surfaceKind = _surfaceKind(session);
    final callId = session?.callId;
    final peerId = session?.contactPeerId;

    Widget? surface;
    if (projection != null &&
        surfaceKind != _ForegroundCallSurface.hidden &&
        callId != null &&
        peerId != null) {
      surface = switch (surfaceKind) {
        _ForegroundCallSurface.incoming => IncomingCallScreen(
          contactPeerId: peerId,
          contactUsername: _contactDisplayName,
          state: session!.state,
          onAnswer: () => _runAction(() => widget.capability?.answer(callId)),
          onDecline: () => _runAction(() => widget.capability?.decline(callId)),
        ),
        _ForegroundCallSurface.outgoing => OutgoingCallScreen(
          contactPeerId: peerId,
          contactUsername: _contactDisplayName,
          state: session!.state,
          onCancel: () => _runAction(() => widget.capability?.cancel(callId)),
        ),
        _ForegroundCallSurface.active => ActiveCallScreen(
          contactPeerId: peerId,
          contactUsername: _contactDisplayName,
          state: session!.state,
          connectedAt: session.connectedAt,
          now: widget.now ?? DateTime.now,
          controls: _buildControls(callId, projection.audio),
        ),
        _ForegroundCallSurface.terminal =>
          _terminalNoticeVisible
              ? _TerminalCallNotice(
                  message: _terminalMessage(session!.endReason),
                  onDismiss: _dismissTerminalNotice,
                )
              : null,
        _ForegroundCallSurface.hidden => null,
      };
    }

    // A software keyboard reports itself as the bottom view inset; keep the
    // controls above it while it is still (dis)appearing.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // While a call surface is visible it owns the screen: release any
        // keyboard focus held underneath (the conversation composer) and block
        // refocus so the keyboard can never cover the call controls.
        ExcludeFocus(excluding: surface != null, child: widget.child),
        if (surface != null)
          Positioned.fill(
            key: ValueKey<CallId?>(callId),
            child: Padding(
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: Overlay.wrap(
                child: Material(
                  type: MaterialType.transparency,
                  child: surface,
                ),
              ),
            ),
          ),
      ],
    );
  }

  CallControls _buildControls(CallId callId, CallAudioControlState audio) {
    final speakerOn = audio.selectedRoute == CallAudioOutputRoute.speaker;
    final speakerAvailable =
        audio.active &&
        audio.supportedRoutes.contains(CallAudioOutputRoute.speaker);
    return CallControls(
      isMuted: audio.muted,
      isMuteAvailable: audio.active,
      isSpeakerOn: speakerOn,
      isSpeakerAvailable: speakerAvailable,
      selectedRoute: audio.selectedRoute,
      audioStatusMessage: _audioStatusMessage(audio.failure),
      muteUnavailableMessage: _muteUnavailableMessage,
      speakerUnavailableMessage: _speakerUnavailableMessage,
      onMute: () =>
          _runAction(() => widget.capability?.setMuted(callId, !audio.muted)),
      onSpeaker: () => _runAction(
        () => widget.capability?.setSpeakerEnabled(callId, !speakerOn),
        unavailableMessage: 'That audio output is unavailable',
        failedMessage: 'Audio output could not be changed',
      ),
      onEnd: () => _runAction(() => widget.capability?.end(callId)),
    );
  }

  void _runAction(
    Future<ForegroundCallActionResult>? Function() operation, {
    String? unavailableMessage,
    String? failedMessage,
  }) {
    unawaited(
      _handleActionResult(
        operation,
        unavailableMessage: unavailableMessage,
        failedMessage: failedMessage,
      ),
    );
  }

  Future<void> _handleActionResult(
    Future<ForegroundCallActionResult>? Function() operation, {
    String? unavailableMessage,
    String? failedMessage,
  }) async {
    ForegroundCallActionStatus status;
    try {
      status =
          (await operation())?.status ?? ForegroundCallActionStatus.unavailable;
    } catch (_) {
      status = ForegroundCallActionStatus.failed;
    }
    if (!mounted) return;
    final message = switch (status) {
      ForegroundCallActionStatus.applied => null,
      ForegroundCallActionStatus.unavailable => unavailableMessage,
      ForegroundCallActionStatus.failed => failedMessage,
    };
    if (message != null) _showActionFeedback(message);
  }

  void _showActionFeedback(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _dismissTerminalNotice({CallId? callId}) {
    if (callId != null && callId != _terminalNoticeCallId) return;
    _terminalNoticeTimer?.cancel();
    _terminalNoticeTimer = null;
    if (!mounted || !_terminalNoticeVisible) return;
    setState(() => _terminalNoticeVisible = false);
  }
}

enum _ForegroundCallSurface { hidden, incoming, outgoing, active, terminal }

_ForegroundCallSurface _surfaceKind(CallSessionSnapshot? session) {
  if (session == null || session.isIdle) {
    return _ForegroundCallSurface.hidden;
  }
  if (session.direction == CallDirection.incoming &&
      !session.incomingValidated) {
    return _ForegroundCallSurface.hidden;
  }
  if (session.isTerminal) return _ForegroundCallSurface.terminal;

  return switch (session.state) {
    CallState.incomingValidating
        when session.direction == CallDirection.incoming =>
      _ForegroundCallSurface.incoming,
    CallState.preparing || CallState.inviting
        when session.direction == CallDirection.outgoing =>
      _ForegroundCallSurface.outgoing,
    CallState.ringing => switch (session.direction) {
      CallDirection.incoming => _ForegroundCallSurface.incoming,
      CallDirection.outgoing => _ForegroundCallSurface.outgoing,
      null => _ForegroundCallSurface.hidden,
    },
    CallState.accepted ||
    CallState.negotiating ||
    CallState.connected ||
    CallState.reconnecting ||
    CallState.ending => _ForegroundCallSurface.active,
    CallState.idle || CallState.ended => _ForegroundCallSurface.hidden,
    _ => _ForegroundCallSurface.hidden,
  };
}

String _terminalMessage(CallEndReason? reason) => switch (reason) {
  CallEndReason.permissionDenied =>
    'Microphone permission is needed to make calls.',
  CallEndReason.unsupported => 'Voice calling is unavailable on this device.',
  CallEndReason.busy => 'The contact is on another call.',
  CallEndReason.declined => 'Call declined.',
  CallEndReason.noAnswer => 'No answer.',
  CallEndReason.signalingFailed => 'Call could not connect.',
  CallEndReason.mediaFailed => 'Call audio could not start.',
  CallEndReason.reconnectFailed => 'Call could not reconnect.',
  CallEndReason.expired => 'The call expired.',
  CallEndReason.policyRejected => 'Voice calling is unavailable.',
  CallEndReason.callerCancelled ||
  CallEndReason.remoteHangup ||
  CallEndReason.localHangup ||
  CallEndReason.appShutdown ||
  null => 'Call ended.',
};

String? _audioStatusMessage(CallAudioFailure failure) => switch (failure) {
  CallAudioFailure.none => null,
  CallAudioFailure.unsupportedRoute => 'That audio output is unavailable',
  CallAudioFailure.controlFailed => 'Audio controls could not be updated',
  CallAudioFailure.notActive ||
  CallAudioFailure.notLocallyAccepted ||
  CallAudioFailure.closed =>
    'Audio controls are unavailable until call audio is ready',
  CallAudioFailure.permissionDenied =>
    'Microphone permission is needed to make calls',
  CallAudioFailure.invalidConfiguration ||
  CallAudioFailure.permissionFailed ||
  CallAudioFailure.mediaConflict ||
  CallAudioFailure.audioSessionFailed ||
  CallAudioFailure.engineFailed ||
  CallAudioFailure.interruptionFailed ||
  CallAudioFailure.cleanupFailed => 'Call audio is unavailable right now',
};

class _TerminalCallNotice extends StatelessWidget {
  const _TerminalCallNotice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    return ColoredBox(
      key: const ValueKey('foreground-call-terminal-notice'),
      color: colors.surfaceBase,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.call_end_rounded,
                size: 64,
                color: colors.iconSecondary,
              ),
              const SizedBox(height: 24),
              Text(
                'Call ended',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                label: message,
                excludeSemantics: true,
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 16),
                ),
              ),
              const SizedBox(height: 28),
              Tooltip(
                message: 'Dismiss call status',
                child: FilledButton(
                  onPressed: onDismiss,
                  child: const Text('Dismiss'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
