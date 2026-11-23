import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/presentation/call_video_localizations.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_video_controls.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_controls.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_video_screen_layout.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Foreground active-call presentation driven by the canonical reducer state.
///
/// The local timer only schedules repaints. It does not own or transition call
/// state, and duration remains anchored to [connectedAt].
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    required this.state,
    required this.connectedAt,
    required this.now,
    required this.controls,
    this.weakConnection = false,
    this.videoPresentation,
    this.onVideoIntent,
    this.videoViews,
    this.cameraFeedback,
    this.upgradeNotice,
  });

  final String contactPeerId;
  final String contactUsername;
  final CallState state;
  final DateTime? connectedAt;
  final DateTime Function() now;
  final CallControls controls;
  final bool weakConnection;
  final CallVideoPresentation? videoPresentation;
  final ValueChanged<CallVideoIntent>? onVideoIntent;
  final Widget? videoViews;
  final Widget? cameraFeedback;
  final Widget? upgradeNotice;

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  Timer? _ticker;

  bool get _showsDuration =>
      widget.connectedAt != null &&
      (widget.state == CallState.connected ||
          widget.state == CallState.reconnecting);

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ActiveCallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectedAt != widget.connectedAt ||
        oldWidget.state != widget.state ||
        oldWidget.now != widget.now) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = _showsDuration
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final formattedDuration = _showsDuration ? _formattedDuration : null;
    final video = widget.videoPresentation;
    if (video != null &&
        video.isVisible &&
        video.acceptedMedia != null &&
        video.agreedMedia == CallMediaKind.video &&
        widget.onVideoIntent != null) {
      return _buildVideoStage(video, formattedDuration);
    }

    final showUpgradeStage =
        video != null &&
        video.isVisible &&
        video.acceptedMedia != null &&
        video.agreedMedia == CallMediaKind.audio &&
        widget.onVideoIntent != null &&
        (video.status == CallVideoStatus.incomingUpgrade ||
            video.status == CallVideoStatus.outgoingUpgrade ||
            video.status == CallVideoStatus.switchingToVideo);
    final colors = showUpgradeStage
        ? BackgroundReadableColors.dark
        : context.backgroundReadableColors;
    final surface = ColoredBox(
      color: showUpgradeStage ? Colors.transparent : colors.surfaceBase,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useCompactLandscape =
                constraints.maxWidth > constraints.maxHeight &&
                constraints.maxHeight < 600;

            final video = widget.videoPresentation;
            final onVideoIntent = widget.onVideoIntent;
            if (video != null && video.isVisible && onVideoIntent != null) {
              return CallVideoScreenLayout(
                peerDisplayName: widget.contactUsername,
                profile: _buildProfile(
                  colors,
                  formattedDuration,
                  compact: useCompactLandscape,
                ),
                audioControls: widget.controls,
                presentation: video,
                onIntent: onVideoIntent,
                videoViews: widget.videoViews,
                // Leave room for the root-owned minimize control.
                topPadding: 56,
              );
            }

            return buildCallProfileLayout(
              compact: useCompactLandscape,
              profile: _buildProfile(
                colors,
                formattedDuration,
                compact: useCompactLandscape,
              ),
              controls: widget.controls,
            );
          },
        ),
      ),
    );
    if (!showUpgradeStage) return surface;
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.dark,
        extensions: [
          ...Theme.of(context).extensions.values.where(
            (extension) => extension is! BackgroundReadableColors,
          ),
          BackgroundReadableColors.dark,
        ],
      ),
      child: CosmicBackground(paused: true, child: surface),
    );
  }

  Widget _buildVideoStage(CallVideoPresentation video, String? duration) {
    final reconnecting =
        widget.state == CallState.reconnecting || video.isReconnecting;
    if (reconnecting) video = _reconnectingPresentation(video);
    final l10n = AppLocalizations.of(context)!;
    final labels = CallVideoLocalizations(l10n);
    final onVideoIntent = widget.onVideoIntent;
    final controls = CallVideoControls(
      peerDisplayName: widget.contactUsername,
      presentation: video,
      audioControls: widget.controls,
      onIntent: (intent) {
        if (mounted) onVideoIntent?.call(intent);
      },
      controlsLabel: labels.controlsLabel,
      statusLabel: labels.statusLabel,
      localCameraLabel: labels.localCameraLabel,
      remoteCameraLabel: labels.remoteCameraLabel,
      actionLabel: labels.actionLabel,
    );
    // The owner supplies video pixels. This composition never starts a camera
    // and the static backdrop does not compete with a call for animation time.
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.dark,
        extensions: [
          ...Theme.of(context).extensions.values.where(
            (extension) => extension is! BackgroundReadableColors,
          ),
          BackgroundReadableColors.dark,
        ],
      ),
      child: CosmicBackground(
        paused: true,
        child: reconnecting
            ? _buildReconnectingVideo(duration, controls)
            : Stack(
                fit: StackFit.expand,
                children: [
                  if (video.remoteCamera != CallCameraState.on)
                    Align(
                      alignment: const Alignment(0, -0.18),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            UserAvatar(peerId: widget.contactPeerId, size: 132),
                            const SizedBox(height: 24),
                            Text(
                              labels.remoteCameraLabel(video.remoteCamera),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFC7CCD6),
                                fontSize: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (widget.videoViews != null) widget.videoViews!,
                  // Only the controls/identity consume safe-area padding. The
                  // background and current remote video occupy the entire call.
                  Positioned(
                    top: 0,
                    left: 72,
                    right: 72,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.contactUsername,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (widget.weakConnection &&
                                widget.state == CallState.connected) ...[
                              const SizedBox(height: 3),
                              Text(
                                _status(l10n),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFE4E6EB),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                            if (duration != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                duration,
                                semanticsLabel: l10n.call_duration(duration),
                                style: const TextStyle(
                                  color: Color(0xFFE4E6EB),
                                  fontSize: 16,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    top: widget.cameraFeedback == null ? null : 0,
                    bottom: 16,
                    child: SafeArea(
                      top: widget.cameraFeedback != null,
                      child: _withCameraFeedback(controls),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // A session reconnect can arrive before its video flags. Apply the existing
  // presentation gates conservatively without changing camera or media truth.
  CallVideoPresentation _reconnectingPresentation(
    CallVideoPresentation video,
  ) => CallVideoPresentation.project(
    videoEnabled: video.videoEnabled,
    wireVersion: video.wireVersion,
    requestedMedia: video.requestedMedia,
    acceptedMedia: video.acceptedMedia,
    agreedMedia: video.agreedMedia,
    localCamera: video.localCamera,
    remoteCamera: video.remoteCamera,
    isConnected: false,
    isReconnecting: true,
    switchingTo: video.switchingTo,
    videoActionPending: video.videoActionPending,
    incomingUpgradeId: video.incomingUpgradeId,
    outgoingUpgradeId: video.outgoingUpgradeId,
    mayRequestVideo: video.mayRequestVideo,
    mayTurnCameraOn: video.mayTurnCameraOn,
    maySwitchCamera: video.maySwitchCamera,
  );

  Widget _buildReconnectingVideo(String? duration, Widget controls) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Full-size control captions determine the remaining space.
                  // Compact only the call identity/fallback, never the actions.
                  final compact = constraints.maxHeight < 400;
                  final name = Text(
                    widget.contactUsername,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 16 : 20,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                  final elapsed = duration == null
                      ? null
                      : Text(
                          duration,
                          semanticsLabel: l10n.call_duration(duration),
                          style: TextStyle(
                            color: const Color(0xFFE4E6EB),
                            fontSize: compact ? 14 : 16,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        );
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Leave the root-owned minimize button unobstructed.
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 56),
                            child: compact
                                ? Row(
                                    children: [
                                      Expanded(child: name),
                                      if (elapsed != null) ...[
                                        const SizedBox(width: 8),
                                        elapsed,
                                      ],
                                    ],
                                  )
                                : Column(
                                    children: [
                                      name,
                                      if (elapsed != null) ...[
                                        const SizedBox(height: 3),
                                        elapsed,
                                      ],
                                    ],
                                  ),
                          ),
                          SizedBox(height: compact ? 8 : 24),
                          UserAvatar(
                            peerId: widget.contactPeerId,
                            size: compact ? 64 : 132,
                          ),
                          SizedBox(height: compact ? 8 : 16),
                          // Controls retain the single live-region announcement.
                          ExcludeSemantics(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xFF171A22),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: const Color(0xFF414651),
                                ),
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: compact ? 6 : 10,
                                ),
                                child: Text(
                                  l10n.call_video_status_reconnecting,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: compact ? 14 : 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (widget.cameraFeedback != null) ...[
                            const SizedBox(height: 12),
                            widget.cameraFeedback!,
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            controls,
          ],
        ),
      ),
    );
  }

  Widget _withCameraFeedback(Widget controls) {
    final feedback = widget.cameraFeedback;
    if (feedback == null) return controls;
    return SingleChildScrollView(
      reverse: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [feedback, const SizedBox(height: 12), controls],
      ),
    );
  }

  Widget _buildProfile(
    BackgroundReadableColors colors,
    String? formattedDuration, {
    bool compact = false,
  }) => CallProfile(
    contactPeerId: widget.contactPeerId,
    contactName: widget.contactUsername,
    status: _status(AppLocalizations.of(context)!),
    colors: colors,
    statusColor: widget.state == CallState.connected
        ? colors.connectedHeading
        : colors.textSecondary,
    duration: formattedDuration,
    trailing: widget.upgradeNotice,
    compact: compact,
  );

  String _status(AppLocalizations l10n) => switch (widget.state) {
    CallState.reconnecting => l10n.call_status_reconnecting,
    CallState.connected when widget.weakConnection =>
      '${l10n.call_status_connected} · ${l10n.call_status_weak_network}',
    CallState.connected => l10n.call_status_connected,
    CallState.ending || CallState.ended => l10n.call_status_ending,
    _ => l10n.call_status_connecting,
  };

  String get _formattedDuration {
    final connectedAt = widget.connectedAt;
    if (connectedAt == null) return '00:00';
    final difference = widget.now().toUtc().difference(connectedAt.toUtc());
    final elapsed = difference.isNegative ? Duration.zero : difference;
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours == 0
        ? '$minutes:$seconds'
        : '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
}

/// Shared profile and button placement for active and finished calls.
Widget buildCallProfileLayout({
  required bool compact,
  required Widget profile,
  required Widget controls,
}) {
  if (compact) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Expanded(child: profile),
          const SizedBox(width: 24),
          Expanded(child: controls),
        ],
      ),
    );
  }
  return Padding(
    padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
    child: Column(
      children: [const Spacer(), profile, const Spacer(), controls],
    ),
  );
}

class CallProfile extends StatelessWidget {
  const CallProfile({
    super.key,
    required this.contactPeerId,
    required this.contactName,
    required this.status,
    required this.colors,
    required this.statusColor,
    required this.compact,
    this.duration,
    this.trailing,
  });

  final String contactPeerId;
  final String contactName;
  final String status;
  final BackgroundReadableColors colors;
  final Color statusColor;
  final bool compact;
  final String? duration;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Explicit nodes keep the name, status and duration independently readable.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(peerId: contactPeerId, size: compact ? 88 : 112),
          SizedBox(height: compact ? 12 : 24),
          Semantics(
            container: true,
            child: Text(
              contactName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: compact ? 24 : 28,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(height: compact ? 6 : 10),
          Semantics(
            container: true,
            identifier: 'call_status',
            liveRegion: true,
            label: status,
            excludeSemantics: true,
            child: Text(
              status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: statusColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (duration case final value?) ...[
            SizedBox(height: compact ? 6 : 8),
            Semantics(
              container: true,
              child: Text(
                value,
                semanticsLabel: l10n.call_duration(value),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          if (trailing case final detail?) ...[
            const SizedBox(height: 16),
            detail,
          ],
        ],
      ),
    );
  }
}
