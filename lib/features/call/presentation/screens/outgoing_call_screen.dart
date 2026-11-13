import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_video_screen_layout.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Foreground-only outgoing call presentation.
///
/// [state] projects the canonical reducer, or `preparing` while the conversation
/// owns cancellable preflight. Ringing requires authenticated remote alerting.
class OutgoingCallScreen extends StatelessWidget {
  const OutgoingCallScreen({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    required this.state,
    required this.onCancel,
    this.videoPresentation,
    this.onVideoIntent,
  });

  final String contactPeerId;
  final String contactUsername;
  final CallState state;
  final VoidCallback onCancel;
  final CallVideoPresentation? videoPresentation;
  final ValueChanged<CallVideoIntent>? onVideoIntent;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final status = _status(l10n);

    final video = videoPresentation;
    final onVideo = onVideoIntent;
    final hasVideo = video != null && video.isVisible && onVideo != null;
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
    final audioControls = Semantics(
      container: true,
      identifier: 'call_cancel',
      button: true,
      // Same announcement the IconButton alone had: its tooltip.
      tooltip: l10n.call_cancel,
      onTap: onCancel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.call_cancel,
            onPressed: onCancel,
            icon: const Icon(Icons.call_end_rounded),
            color: Colors.white,
            iconSize: 30,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFE5484D),
              fixedSize: const Size.square(68),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.btn_cancel,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
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
              // explicit child nodes, iOS read the name, the status and the
              // Cancel caption as one element.
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

  String _status(AppLocalizations l10n) => switch (state) {
    CallState.preparing || CallState.inviting => l10n.call_status_calling,
    CallState.ringing => l10n.call_status_ringing,
    CallState.connected => l10n.call_status_connected,
    CallState.reconnecting => l10n.call_status_reconnecting,
    CallState.ending || CallState.ended => l10n.call_status_ending,
    _ => l10n.call_status_connecting,
  };
}
