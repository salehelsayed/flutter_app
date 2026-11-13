import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_video_screen_layout.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Foreground-only incoming call presentation.
///
/// Answer and decline are available only for the canonical validated ringing
/// state. Incoming validation itself never captures audio or exposes controls.
class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    required this.state,
    required this.onAnswer,
    this.onAcceptVideo,
    this.onUseAudioOnly,
    this.mediaChoiceInFlight = false,
    required this.onDecline,
    this.videoPresentation,
    this.onVideoIntent,
  });

  final String contactPeerId;
  final String contactUsername;
  final CallState state;
  final VoidCallback onAnswer;
  final VoidCallback? onAcceptVideo;
  final VoidCallback? onUseAudioOnly;
  final bool mediaChoiceInFlight;
  final VoidCallback onDecline;
  final CallVideoPresentation? videoPresentation;
  final ValueChanged<CallVideoIntent>? onVideoIntent;

  bool get _canRespond => state == CallState.ringing;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final status = _canRespond
        ? l10n.call_status_incoming
        : l10n.call_status_checking_incoming;

    final video = videoPresentation;
    final onVideo = onVideoIntent;
    final hasVideo = video != null && video.isVisible && onVideo != null;
    Widget fitAction(Widget action) =>
        hasVideo ? Expanded(child: action) : action;
    final profile = <Widget>[
      UserAvatar(peerId: contactPeerId, size: 112),
      const SizedBox(height: 24),
      Semantics(
        container: true,
        child: Text(
          contactUsername,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: 10),
      Semantics(
        container: true,
        identifier: 'call_status',
        liveRegion: true,
        label: status,
        excludeSemantics: true,
        child: Text(
          status,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ];
    final audioControls = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        fitAction(
          _IncomingAction(
            identifier: 'call_decline',
            tooltip: _canRespond
                ? l10n.contact_request_decline
                : l10n.call_decline_unavailable,
            label: l10n.contact_request_decline,
            icon: Icons.call_end_rounded,
            backgroundColor: const Color(0xFFE5484D),
            enabled: _canRespond,
            onPressed: onDecline,
            constrainLabel: hasVideo,
          ),
        ),
        fitAction(
          _IncomingAction(
            identifier: 'call_answer',
            tooltip: _canRespond
                ? l10n.call_answer
                : l10n.call_answer_unavailable,
            label: l10n.call_answer,
            icon: Icons.call_rounded,
            backgroundColor: colors.accent,
            enabled: _canRespond,
            onPressed: onAnswer,
            constrainLabel: hasVideo,
          ),
        ),
      ],
    );
    final videoLayout = hasVideo
        ? CallVideoScreenLayout(
            profile: Semantics(
              container: true,
              explicitChildNodes: true,
              child: Column(mainAxisSize: MainAxisSize.min, children: profile),
            ),
            audioControls: audioControls,
            presentation: video,
            onIntent: onVideo,
          )
        : null;

    return ColoredBox(
      color: colors.surfaceBase,
      child: SafeArea(
        child:
            videoLayout ??
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
              // The overlay hosts this screen outside any route scope. Without
              // explicit child nodes, the name, the status and the action
              // captions merge into one accessibility element.
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: Column(
                  children: [
                    const Spacer(),
                    ...profile,
                    const Spacer(),
                    audioControls,
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

class _IncomingAction extends StatelessWidget {
  const _IncomingAction({
    required this.identifier,
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.enabled,
    required this.onPressed,
    this.constrainLabel = false,
  });

  final String identifier;
  final String tooltip;
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final bool enabled;
  final VoidCallback onPressed;
  final bool constrainLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    // One accessibility element per action: the button and its caption.
    return Semantics(
      container: true,
      identifier: identifier,
      button: true,
      enabled: enabled,
      // Same announcement the IconButton alone had: its tooltip.
      tooltip: tooltip,
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: tooltip,
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon),
            color: Colors.white,
            disabledColor: colors.disabledForeground,
            iconSize: 30,
            style: IconButton.styleFrom(
              backgroundColor: enabled
                  ? backgroundColor
                  : colors.disabledSurface,
              fixedSize: const Size.square(68),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: constrainLabel ? 2 : null,
            overflow: constrainLabel ? TextOverflow.ellipsis : null,
            textAlign: constrainLabel ? TextAlign.center : null,
            style: TextStyle(
              color: enabled ? colors.textSecondary : colors.disabledForeground,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
