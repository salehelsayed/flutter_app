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

            if (useCompactLandscape) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildProfile(
                        colors,
                        formattedDuration,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(child: widget.controls),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
              child: Column(
                children: [
                  const Spacer(),
                  _buildProfile(colors, formattedDuration),
                  const Spacer(),
                  widget.controls,
                ],
              ),
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
          ...Theme.of(context).extensions.values
              .where((extension) => extension is! BackgroundReadableColors),
          BackgroundReadableColors.dark,
        ],
      ),
      child: CosmicBackground(paused: true, child: surface),
    );
  }

  Widget _buildVideoStage(CallVideoPresentation video, String? duration) {
    final l10n = AppLocalizations.of(context)!;
    final labels = CallVideoLocalizations(l10n);
    final onVideoIntent = widget.onVideoIntent;
    // The owner supplies video pixels. This composition never starts a camera
    // and the static backdrop does not compete with a call for animation time.
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.dark,
        extensions: [
          ...Theme.of(context).extensions.values
              .where((extension) => extension is! BackgroundReadableColors),
          BackgroundReadableColors.dark,
        ],
      ),
      child: CosmicBackground(
        paused: true,
        child: Stack(
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
                child: _withCameraFeedback(
                  CallVideoControls(
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
                  ),
                ),
              ),
            ),
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
  }) {
    final l10n = AppLocalizations.of(context)!;
    final status = _status(l10n);
    // The overlay hosts this screen outside any route scope: explicit child
    // nodes keep the name, the status and the duration separate elements.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(peerId: widget.contactPeerId, size: compact ? 88 : 112),
          SizedBox(height: compact ? 12 : 24),
          Semantics(
            container: true,
            child: Text(
              widget.contactUsername,
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
              style: TextStyle(
                color: widget.state == CallState.connected
                    ? colors.connectedHeading
                    : colors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (formattedDuration != null) ...[
            SizedBox(height: compact ? 6 : 8),
            Semantics(
              container: true,
              child: Text(
                formattedDuration,
                semanticsLabel: l10n.call_duration(formattedDuration),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          if (widget.upgradeNotice != null) ...[
            const SizedBox(height: 16),
            widget.upgradeNotice!,
          ],
        ],
      ),
    );
  }

  String _status(AppLocalizations l10n) => switch (widget.state) {
    CallState.reconnecting => l10n.call_status_reconnecting,
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
