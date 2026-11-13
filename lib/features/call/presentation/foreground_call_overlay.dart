import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../application/call_audio_controller.dart';
import '../application/foreground_call_capability.dart';
import '../domain/call_engine.dart';
import '../domain/call_end_reason.dart';
import '../domain/call_id.dart';
import '../domain/call_media.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';
import 'call_video_presentation.dart';
import 'foreground_call_back_guard.dart';
import 'locked_call_projection.dart';
import 'screens/active_call_screen.dart';
import 'screens/incoming_call_screen.dart';
import 'screens/outgoing_call_screen.dart';
import 'widgets/call_controls.dart';
import 'widgets/call_audio_output_picker.dart';
import 'widgets/call_return_bar.dart';

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
    this.onAttached,
    this.backGuard,
    this.micPermission,
  });

  final ForegroundCallCapability? capability;
  final ContactDisplayNameLoader loadContactDisplayName;
  final Widget child;
  final DateTime Function()? now;

  /// The canonical projection subscription is installed. A hidden Android
  /// activity may attach this host without ever receiving a rendered frame.
  final VoidCallback? onAttached;

  /// Told whether a live call surface owns the screen, so the system Back
  /// action sends the app to the background instead of popping the hidden
  /// routes or finishing the activity under the call.
  final ForegroundCallBackGuard? backGuard;

  /// Tells a microphone denial the system will no longer prompt for apart
  /// from one the next call can still ask about.
  final MicPermissionGateway? micPermission;

  @override
  State<ForegroundCallOverlay> createState() => ForegroundCallOverlayState();
}

class ForegroundCallOverlayState extends State<ForegroundCallOverlay> {
  static const Duration _terminalNoticeDuration = Duration(seconds: 6);
  static const String _unknownContactName = 'Unknown contact';

  StreamSubscription<ForegroundCallProjection?>? _subscription;
  ForegroundCallProjection? _projection;
  CallId? _nameCallId;
  String? _namePeerId;
  String _contactDisplayName = _unknownContactName;
  bool _nameLoaded = false;
  int _capabilityGeneration = 0;
  int _nameGeneration = 0;
  Timer? _terminalNoticeTimer;
  CallId? _terminalNoticeCallId;
  bool _terminalNoticeVisible = false;
  CallId? _micBlockedCallId;
  bool _navigatorCanHandlePop = false;
  bool? _publishedOwnsBack;
  CallId? _minimizedCallId;
  Offset? _pictureInPictureOffset;
  CallId? _pickerCallId;
  final _lockedProjection = LockedCallProjection();
  bool _lockedLight = false;
  AppLocalizations? _lockedL10n;

  final _feedbackMessengerKey = GlobalKey<ScaffoldMessengerState>();

  /// The call owns the modal surface; route snackbars are underneath it.
  /// Minimized/hidden calls use the retained route's ordinary messenger.
  void showFeedback(String message) {
    if (!mounted) return;
    // A refusal or minimize can remove the call surface on the next build.
    // Its messenger key still exists until that frame commits; resolve the
    // target afterward so the message survives on the retained route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger =
          _feedbackMessengerKey.currentState ??
          ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    });
    // A steady no-call refusal need not otherwise schedule a new frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lockedLight = context.backgroundReadableColors.isLightSurface;
    _lockedL10n = AppLocalizations.of(context);
    _publishLockedProjection();
  }

  void _publishLockedProjection() {
    final l10n = _lockedL10n;
    if (l10n == null) return;
    unawaited(
      _lockedProjection.update(
        capability: widget.capability,
        projection: _projection,
        displayName: _nameLoaded ? _contactDisplayName : null,
        light: _lockedLight,
        l10n: l10n,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _bindCapability(notify: false);
    scheduleMicrotask(() {
      if (mounted) widget.onAttached?.call();
    });
  }

  @override
  void didUpdateWidget(covariant ForegroundCallOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.backGuard, widget.backGuard)) {
      oldWidget.backGuard?.surfaceOwnsBack = false;
    }
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
    _lockedProjection.dispose();
    widget.backGuard?.surfaceOwnsBack = false;
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
    CallId? micCheckCallId;

    void update() {
      _projection = projection;
      final session = projection?.session;
      final surfaceKind = _surfaceKind(session);
      final wasMinimized =
          _minimizedCallId != null && _minimizedCallId == session?.callId;
      if (surfaceKind != _ForegroundCallSurface.active ||
          _minimizedCallId != session?.callId) {
        _minimizedCallId = null;
      }
      if (surfaceKind != _ForegroundCallSurface.active ||
          _pickerCallId != session?.callId ||
          projection?.audio.active != true) {
        _pickerCallId = null;
      }
      final terminalCallId = surfaceKind == _ForegroundCallSurface.terminal
          ? session?.callId
          : null;
      if (terminalCallId != _terminalNoticeCallId) {
        _terminalNoticeTimer?.cancel();
        _terminalNoticeTimer = null;
        _terminalNoticeCallId = terminalCallId;
        _terminalNoticeVisible = terminalCallId != null && !wasMinimized;
        terminalNoticeToSchedule = terminalCallId;
        _micBlockedCallId = null;
        if (terminalCallId != null &&
            session?.endReason == CallEndReason.permissionDenied) {
          micCheckCallId = terminalCallId;
        }
      }

      // The end notice of the call that was just on screen keeps its name.
      if (surfaceKind == _ForegroundCallSurface.terminal &&
          _nameCallId != null &&
          _nameCallId == session?.callId) {
        return;
      }
      if (surfaceKind == _ForegroundCallSurface.hidden ||
          surfaceKind == _ForegroundCallSurface.terminal) {
        _nameGeneration += 1;
        _nameCallId = null;
        _namePeerId = null;
        _contactDisplayName = _unknownContactName;
        _nameLoaded = false;
        return;
      }

      final callId = session?.callId;
      final peerId = session?.contactPeerId;
      if (callId == null || peerId == null) return;
      if (_nameCallId == callId && _namePeerId == peerId) return;

      _nameCallId = callId;
      _namePeerId = peerId;
      _contactDisplayName = _unknownContactName;
      _nameLoaded = false;
      lookupCallId = callId;
      lookupPeerId = peerId;
      lookupGeneration = ++_nameGeneration;
    }

    if (notify) {
      setState(update);
    } else {
      update();
    }

    _publishLockedProjection();

    final micCallId = micCheckCallId;
    if (micCallId != null) unawaited(_checkMicBlocked(micCallId));

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
      _nameLoaded =
          normalizedName != null &&
          normalizedName.isNotEmpty &&
          normalizedName != peerId;
      _contactDisplayName = _nameLoaded ? normalizedName! : _unknownContactName;
    });
    _publishLockedProjection();
  }

  @override
  Widget build(BuildContext context) {
    final projection = _projection;
    final session = projection?.session;
    final surfaceKind = _surfaceKind(session);
    final callId = session?.callId;
    final peerId = session?.contactPeerId;
    final capability = widget.capability;
    final minimized =
        surfaceKind == _ForegroundCallSurface.active &&
        callId != null &&
        _minimizedCallId == callId;

    Widget? surface;
    ForegroundCallVideoProjection? pictureInPictureVideo;
    if (projection != null &&
        surfaceKind != _ForegroundCallSurface.hidden &&
        callId != null &&
        peerId != null) {
      final video = _visibleVideo(projection, capability);
      pictureInPictureVideo = _pictureInPictureVideo(projection, capability);
      final capabilityGeneration = _capabilityGeneration;
      final ValueChanged<CallVideoIntent>? onVideoIntent = video == null
          ? null
          : (intent) => _runVideoIntent(
              capability: capability!,
              capabilityGeneration: capabilityGeneration,
              callId: callId,
              generation: video.generation,
              intent: intent,
            );
      surface = switch (surfaceKind) {
        _ForegroundCallSurface.incoming => IncomingCallScreen(
          contactPeerId: peerId,
          contactUsername: _contactDisplayName == _unknownContactName
              ? AppLocalizations.of(context)!.call_unknown_contact
              : _contactDisplayName,
          state: session!.state,
          onAnswer: () => _runAction(() => widget.capability?.answer(callId)),
          onDecline: () => _runAction(() => widget.capability?.decline(callId)),
          videoPresentation: video?.presentation,
          onVideoIntent: onVideoIntent,
        ),
        _ForegroundCallSurface.outgoing => OutgoingCallScreen(
          contactPeerId: peerId,
          contactUsername: _contactDisplayName == _unknownContactName
              ? AppLocalizations.of(context)!.call_unknown_contact
              : _contactDisplayName,
          state: session!.state,
          onCancel: () => _runAction(() => widget.capability?.cancel(callId)),
          videoPresentation: video?.presentation,
          onVideoIntent: onVideoIntent,
        ),
        _ForegroundCallSurface.active => ActiveCallScreen(
          contactPeerId: peerId,
          contactUsername: _contactDisplayName == _unknownContactName
              ? AppLocalizations.of(context)!.call_unknown_contact
              : _contactDisplayName,
          state: session!.state,
          connectedAt: session.connectedAt,
          now: widget.now ?? DateTime.now,
          controls: _buildControls(
            callId,
            projection.audio,
            constrainLabels: video != null,
          ),
          videoPresentation: video?.presentation,
          onVideoIntent: onVideoIntent,
        ),
        _ForegroundCallSurface.terminal =>
          _terminalNoticeVisible
              ? _TerminalCallNotice(
                  message: _micBlockedCallId == session!.callId
                      ? AppLocalizations.of(
                          context,
                        )!.call_end_permission_settings
                      : _terminalMessage(
                          session,
                          AppLocalizations.of(context)!,
                          _contactDisplayName == _unknownContactName
                              ? AppLocalizations.of(
                                  context,
                                )!.call_unknown_contact
                              : _contactDisplayName,
                        ),
                  onDismiss: _dismissTerminalNotice,
                  onOpenSettings: _micBlockedCallId == session.callId
                      ? _openMicSettings
                      : null,
                )
              : null,
        _ForegroundCallSurface.hidden => null,
      };
    }

    final modal = surface != null && !minimized;
    // Minimized calls let the navigator pop normally. At its root, background
    // the task instead of destroying the activity and its live call runtime.
    final backGuard = widget.backGuard;
    final ownsBack =
        backGuard != null &&
        ((modal && surfaceKind != _ForegroundCallSurface.terminal) ||
            (minimized && !_navigatorCanHandlePop));
    backGuard?.surfaceOwnsBack = ownsBack;
    _publishFrameworkHandlesBack(ownsBack);

    // A software keyboard reports itself as the bottom view inset; keep the
    // controls above it while it is still (dis)appearing.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // While a call surface is visible it owns the screen: release any
        // keyboard focus held underneath (the conversation composer) and block
        // refocus so the keyboard can never cover the call controls.
        TickerMode(
          // The retained route can contain continuously animated ambient
          // backgrounds. A call owns the screen; freeze those animations until
          // it hides, while preserving navigation and non-animation state.
          enabled: !modal,
          child: ExcludeFocus(
            excluding: modal,
            child: NotificationListener<NavigationNotification>(
              // While a call owns Back, the hidden navigator's answer must not
              // reach the engine. At its root route it reports that it cannot
              // pop, and on Android 13+ FlutterActivity then unregisters its
              // back callback, so the system Back closes the task and ends
              // the call (beta 2026-09-25). The call surface reports that the
              // framework handles Back instead. The navigator's last value is
              // replayed when the call surface hides.
              onNotification: (notification) {
                final changed =
                    _navigatorCanHandlePop != notification.canHandlePop;
                _navigatorCanHandlePop = notification.canHandlePop;
                if (changed && _minimizedCallId != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                }
                return _publishedOwnsBack == true;
              },
              child: Padding(
                padding: EdgeInsets.only(
                  top: minimized ? MediaQuery.paddingOf(context).top + 56 : 0,
                ),
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: minimized,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
        if (minimized && session != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: CallReturnBar(
                name: _contactDisplayName == _unknownContactName
                    ? AppLocalizations.of(context)!.call_unknown_contact
                    : _contactDisplayName,
                state: session.state,
                connectedAt: session.connectedAt,
                muted: projection!.audio.muted,
                now: widget.now ?? DateTime.now,
                onReturn: () => setState(() => _minimizedCallId = null),
              ),
            ),
          ),
        if (minimized && pictureInPictureVideo != null)
          _buildPictureInPicture(
            capability: capability!,
            capabilityGeneration: _capabilityGeneration,
            callId: callId,
            video: pictureInPictureVideo,
            keyboardInset: keyboardInset,
          ),
        if (modal)
          Positioned.fill(
            key: ValueKey<CallId?>(callId),
            child: BlockSemantics(
              // This screen is modal to accessibility as well as touch/focus.
              // Keep the retained route painted, but remove its actions and
              // private history from the platform semantics tree.
              child: Padding(
                padding: EdgeInsets.only(bottom: keyboardInset),
                child: Overlay.wrap(
                  child: ScaffoldMessenger(
                    key: _feedbackMessengerKey,
                    child: Scaffold(
                      // The call screens' own fill is translucent in dark
                      // mode; an open private photo must not show through.
                      backgroundColor: context
                          .backgroundReadableColors
                          .surfaceBase
                          .withAlpha(255),
                      resizeToAvoidBottomInset: false,
                      body: Stack(
                        fit: StackFit.expand,
                        children: [
                          ExcludeFocus(
                            excluding: _pickerCallId != null,
                            child: surface,
                          ),
                          if (surfaceKind == _ForegroundCallSurface.active &&
                              _pickerCallId == null)
                            Positioned(
                              top: MediaQuery.paddingOf(context).top,
                              right: 8,
                              child: IconButton(
                                key: const ValueKey('call-minimize'),
                                tooltip: AppLocalizations.of(
                                  context,
                                )!.call_minimize,
                                onPressed: () => setState(() {
                                  _pickerCallId = null;
                                  _minimizedCallId = callId;
                                  _pictureInPictureOffset = null;
                                }),
                                icon: const Icon(Icons.keyboard_arrow_down),
                              ),
                            ),
                          if (_pickerCallId == callId &&
                              widget.capability
                                  is ForegroundCallAudioPickerCapability)
                            CallAudioOutputPicker(
                              key: ValueKey(
                                'call-output-picker-${callId!.value}',
                              ),
                              callId: callId,
                              capability:
                                  widget.capability
                                      as ForegroundCallAudioPickerCapability,
                              onClose: () =>
                                  setState(() => _pickerCallId = null),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  ForegroundCallVideoProjection? _pictureInPictureVideo(
    ForegroundCallProjection projection,
    ForegroundCallCapability? capability,
  ) {
    if (_surfaceKind(projection.session) != _ForegroundCallSurface.active ||
        projection.session.state == CallState.ending) {
      return null;
    }
    final video = _visibleVideo(projection, capability);
    if (video == null ||
        video.presentation.acceptedMedia == null ||
        video.presentation.agreedMedia != CallMediaKind.video) {
      return null;
    }
    return video;
  }

  bool _ownsPictureInPicture({
    required ForegroundCallCapability capability,
    required int capabilityGeneration,
    required CallId callId,
    required int generation,
  }) {
    if (!mounted ||
        !identical(capability, widget.capability) ||
        capabilityGeneration != _capabilityGeneration ||
        _minimizedCallId != callId) {
      return false;
    }
    try {
      final current = capability.current;
      return current != null &&
          current.session.callId == callId &&
          _pictureInPictureVideo(current, capability)?.generation == generation;
    } catch (_) {
      return false;
    }
  }

  Widget _buildPictureInPicture({
    required ForegroundCallCapability capability,
    required int capabilityGeneration,
    required CallId callId,
    required ForegroundCallVideoProjection video,
    required double keyboardInset,
  }) {
    bool isCurrent() => _ownsPictureInPicture(
      capability: capability,
      capabilityGeneration: capabilityGeneration,
      callId: callId,
      generation: video.generation,
    );
    void restore() {
      if (!isCurrent()) return;
      setState(() => _minimizedCallId = null);
    }

    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          // Keep the existing return bar and the keyboard unobstructed.
          padding: EdgeInsets.only(top: 56, bottom: keyboardInset),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 24)
                  .clamp(0.0, 180.0)
                  .toDouble();
              final height = (constraints.maxHeight - 24)
                  .clamp(0.0, width * 9 / 16 + 48)
                  .toDouble();
              if (width < 96 || height < 48) return const SizedBox.shrink();
              final maxX = constraints.maxWidth - width;
              final maxY = constraints.maxHeight - height;
              final requested =
                  _pictureInPictureOffset ??
                  Offset(
                    Directionality.of(context) == TextDirection.rtl
                        ? 12
                        : maxX - 12,
                    maxY - 12,
                  );
              final position = Offset(
                requested.dx.clamp(0.0, maxX).toDouble(),
                requested.dy.clamp(0.0, maxY).toDouble(),
              );
              return Stack(
                children: [
                  Positioned(
                    left: position.dx,
                    top: position.dy,
                    width: width,
                    height: height,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        if (!isCurrent()) return;
                        // A resize can clamp the visible tile before the next
                        // gesture; apply its delta from that visible position.
                        final stored = _pictureInPictureOffset ?? position;
                        final previous = Offset(
                          stored.dx.clamp(0.0, maxX).toDouble(),
                          stored.dy.clamp(0.0, maxY).toDouble(),
                        );
                        setState(() {
                          _pictureInPictureOffset = Offset(
                            (previous.dx + details.delta.dx)
                                .clamp(0.0, maxX)
                                .toDouble(),
                            (previous.dy + details.delta.dy)
                                .clamp(0.0, maxY)
                                .toDouble(),
                          );
                        });
                      },
                      child: _CallPictureInPictureTile(
                        ownerIdentity: (
                          callId.value,
                          capabilityGeneration,
                          video.generation,
                        ),
                        video: video,
                        onReturn: restore,
                        onEnd: () => _runAction(() {
                          if (!isCurrent()) return null;
                          return capability.end(callId);
                        }),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _publishFrameworkHandlesBack(bool ownsBack) {
    if (widget.backGuard == null) return;
    if (_publishedOwnsBack == ownsBack) return;
    final wasOwned = _publishedOwnsBack == true;
    _publishedOwnsBack = ownsBack;
    if (!ownsBack && !wasOwned) return;
    // Bubbles to WidgetsApp, which forwards it to the engine as
    // SystemNavigator.setFrameworkHandlesBack. Posted after the frame, like
    // the navigator's own notifications. While a call owns Back this keeps
    // Flutter's Android back callback registered, so Back reaches
    // ForegroundCallBackGuard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _publishedOwnsBack != ownsBack) return;
      NavigationNotification(
        canHandlePop: ownsBack || _navigatorCanHandlePop,
      ).dispatch(context);
    });
  }

  CallControls _buildControls(
    CallId callId,
    CallAudioControlState audio, {
    bool constrainLabels = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final speakerOn = audio.selectedRoute == CallAudioOutputRoute.speaker;
    final speakerAvailable =
        audio.active &&
        audio.supportedRoutes.contains(CallAudioOutputRoute.speaker);
    return CallControls(
      constrainLabels: constrainLabels,
      isMuted: audio.muted,
      isMuteAvailable: audio.active,
      isSpeakerOn: speakerOn,
      isSpeakerAvailable: speakerAvailable,
      selectedRoute: audio.selectedRoute,
      audioStatusMessage: _audioStatusMessage(
        audio.failure,
        AppLocalizations.of(context)!,
      ),
      muteUnavailableMessage: l10n.call_mute_unavailable,
      speakerUnavailableMessage: l10n.call_speaker_unavailable,
      onMute: () =>
          _runAction(() => widget.capability?.setMuted(callId, !audio.muted)),
      onSpeaker: () => _runAction(
        () => widget.capability?.setSpeakerEnabled(callId, !speakerOn),
        unavailableMessage: l10n.call_audio_output_unavailable,
        failedMessage: l10n.call_audio_output_failed,
      ),
      onChooseAudioOutput:
          audio.active &&
              widget.capability is ForegroundCallAudioPickerCapability
          ? () => setState(() => _pickerCallId = callId)
          : null,
      onEnd: () => _runAction(() => widget.capability?.end(callId)),
    );
  }

  ForegroundCallVideoProjection? _visibleVideo(
    ForegroundCallProjection projection,
    ForegroundCallCapability? capability,
  ) {
    final session = projection.session;
    final video = projection.video;
    if (capability is! ForegroundCallVideoCapability ||
        session.isIdle ||
        session.isTerminal ||
        session.state == CallState.incomingValidating ||
        video == null ||
        !video.presentation.isVisible) {
      return null;
    }
    return video;
  }

  void _runVideoIntent({
    required ForegroundCallCapability capability,
    required int capabilityGeneration,
    required CallId callId,
    required int generation,
    required CallVideoIntent intent,
  }) {
    _runAction(() {
      if (!mounted ||
          !identical(capability, widget.capability) ||
          capabilityGeneration != _capabilityGeneration ||
          _minimizedCallId == callId ||
          _pickerCallId == callId ||
          capability is! ForegroundCallVideoCapability) {
        return null;
      }
      // Re-read the owner immediately before dispatch, including updates that
      // have not reached the presentation stream yet. The root revalidates
      // these tokens atomically before performing any media effect.
      final current = capability.current;
      if (current == null || current.session.callId != callId) return null;
      final video = _visibleVideo(current, capability);
      if (video == null || video.generation != generation) return null;
      final available = video.presentation.intentFor(intent.action);
      if (available == null || available.upgradeId != intent.upgradeId) {
        return null;
      }
      return (capability as ForegroundCallVideoCapability).applyVideoIntent(
        callId,
        generation: generation,
        intent: intent,
      );
    });
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

  Future<void> _checkMicBlocked(CallId callId) async {
    final gateway = widget.micPermission;
    if (gateway == null) return;
    final MicPermissionStatus status;
    try {
      status = await gateway.status();
    } catch (_) {
      return;
    }
    if (!mounted ||
        status != MicPermissionStatus.permanentlyDenied ||
        _terminalNoticeCallId != callId) {
      return;
    }
    setState(() => _micBlockedCallId = callId);
  }

  void _openMicSettings() {
    final gateway = widget.micPermission;
    if (gateway == null) return;
    unawaited(gateway.openAppSettings().catchError((Object _) => false));
  }

  void _dismissTerminalNotice({CallId? callId}) {
    if (callId != null && callId != _terminalNoticeCallId) return;
    _terminalNoticeTimer?.cancel();
    _terminalNoticeTimer = null;
    if (!mounted || !_terminalNoticeVisible) return;
    setState(() => _terminalNoticeVisible = false);
  }
}

/// Displays owner-issued metadata in the minimized call surface.
class _CallPictureInPictureTile extends StatelessWidget {
  const _CallPictureInPictureTile({
    required this.ownerIdentity,
    required this.video,
    required this.onReturn,
    required this.onEnd,
  });

  final Object ownerIdentity;
  final ForegroundCallVideoProjection video;
  final VoidCallback onReturn;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.backgroundReadableColors;
    final presentation = video.presentation;
    final view = video.remoteView;
    final label = presentation.isReconnecting
        ? l10n.call_video_status_reconnecting
        : switch (presentation.remoteCamera) {
            CallCameraState.on => l10n.call_video_remote_camera_on,
            CallCameraState.off => l10n.call_video_remote_camera_off,
            CallCameraState.paused => l10n.call_video_remote_camera_paused,
          };
    Widget frame = Icon(
      presentation.remoteCamera == CallCameraState.off
          ? Icons.videocam_off_outlined
          : Icons.videocam_outlined,
      color: Colors.white,
    );
    if (presentation.isConnected &&
        !presentation.isReconnecting &&
        presentation.remoteCamera == CallCameraState.on &&
        view != null &&
        view.textureId >= 0 &&
        view.width > 0 &&
        view.height > 0) {
      frame = FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: view.width.toDouble(),
          height: view.height.toDouble(),
          child: Texture(
            key: ValueKey((
              ownerIdentity,
              view.textureId,
              view.width,
              view.height,
            )),
            textureId: view.textureId,
          ),
        ),
      );
    }
    return Material(
      key: const ValueKey('call-pip-tile'),
      color: colors.surfaceRaised,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Semantics(
              key: const ValueKey('call-pip-view'),
              container: true,
              button: true,
              label: '${l10n.call_return}, $label',
              onTap: onReturn,
              excludeSemantics: true,
              child: InkWell(
                onTap: onReturn,
                child: SizedBox.expand(
                  child: ColoredBox(color: Colors.black, child: frame),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  key: const ValueKey('call-pip-restore'),
                  tooltip: l10n.call_return,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onReturn,
                  icon: Icon(Icons.open_in_full, color: colors.textPrimary),
                ),
                IconButton(
                  key: const ValueKey('call-pip-end'),
                  tooltip: l10n.call_end,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onEnd,
                  icon: Icon(
                    Icons.call_end_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

String _terminalMessage(
  CallSessionSnapshot session,
  AppLocalizations l10n,
  String contactName,
) => switch (session.endReason) {
  CallEndReason.permissionDenied => l10n.call_end_permission,
  CallEndReason.remotePermissionDenied => l10n.call_end_remote_microphone_off(
    contactName,
  ),
  CallEndReason.unsupported => l10n.call_end_unsupported,
  CallEndReason.busy => l10n.call_end_busy,
  CallEndReason.declined => l10n.call_end_declined,
  CallEndReason.noAnswer =>
    session.direction == CallDirection.outgoing &&
            session.ringingAt == null &&
            session.acceptedAt == null
        ? l10n.call_end_signaling_failed
        : l10n.call_end_no_answer,
  CallEndReason.signalingFailed => l10n.call_end_signaling_failed,
  CallEndReason.mediaFailed =>
    session.connectedAt == null
        ? l10n.call_end_audio_start_failed
        : l10n.call_end_audio_interrupted,
  CallEndReason.reconnectFailed => l10n.call_end_reconnect_failed,
  CallEndReason.expired => l10n.call_end_expired,
  CallEndReason.policyRejected => l10n.call_end_unavailable,
  CallEndReason.callerCancelled ||
  CallEndReason.remoteHangup ||
  CallEndReason.localHangup ||
  CallEndReason.appShutdown ||
  null => l10n.call_end_ended,
};

String? _audioStatusMessage(CallAudioFailure failure, AppLocalizations l10n) =>
    switch (failure) {
      CallAudioFailure.none => null,
      CallAudioFailure.unsupportedRoute => l10n.call_audio_output_unavailable,
      CallAudioFailure.controlFailed => l10n.call_audio_controls_failed,
      CallAudioFailure.notActive ||
      CallAudioFailure.notLocallyAccepted ||
      CallAudioFailure.closed => l10n.call_audio_controls_not_ready,
      CallAudioFailure.permissionDenied => l10n.call_audio_permission,
      CallAudioFailure.invalidConfiguration ||
      CallAudioFailure.permissionFailed ||
      CallAudioFailure.mediaConflict ||
      CallAudioFailure.audioSessionFailed ||
      CallAudioFailure.engineFailed ||
      CallAudioFailure.interruptionFailed ||
      CallAudioFailure.cleanupFailed => l10n.call_audio_unavailable,
    };

class _TerminalCallNotice extends StatelessWidget {
  const _TerminalCallNotice({
    required this.message,
    required this.onDismiss,
    this.onOpenSettings,
  });

  final String message;
  final VoidCallback onDismiss;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
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
                l10n.call_ended,
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
              if (onOpenSettings != null) ...[
                FilledButton(
                  key: const ValueKey('foreground-call-open-settings'),
                  onPressed: onOpenSettings,
                  child: Text(l10n.compose_open_settings),
                ),
                const SizedBox(height: 12),
              ],
              Tooltip(
                message: l10n.call_dismiss_status,
                child: FilledButton(
                  onPressed: onDismiss,
                  child: Text(l10n.pinned_dismiss),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
