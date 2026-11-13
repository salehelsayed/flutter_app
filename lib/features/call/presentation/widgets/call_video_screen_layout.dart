import 'package:flutter/material.dart';
import 'package:flutter_app/features/call/presentation/call_video_localizations.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_video_controls.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Scrolls the optional video surface without taking ownership of audio state.
class CallVideoScreenLayout extends StatelessWidget {
  const CallVideoScreenLayout({
    super.key,
    required this.profile,
    required this.audioControls,
    required this.presentation,
    required this.onIntent,
    this.topPadding = 16,
    this.showVideoControls = true,
  });

  final Widget profile;
  final Widget audioControls;
  final CallVideoPresentation presentation;
  final ValueChanged<CallVideoIntent> onIntent;
  final double topPadding;
  final bool showVideoControls;

  @override
  Widget build(BuildContext context) {
    final labels = CallVideoLocalizations(AppLocalizations.of(context)!);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
      child: SingleChildScrollView(
        key: const ValueKey('call-video-scroll'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            profile,
            const SizedBox(height: 16),
            if (!showVideoControls)
              audioControls
            else
              CallVideoControls(
                presentation: presentation,
                audioControls: audioControls,
                onIntent: (intent) {
                  // A retained callback from a minimized/replaced surface is
                  // invalid even if the canonical call token still matches.
                  if (context.mounted) onIntent(intent);
                },
                controlsLabel: labels.controlsLabel,
                statusLabel: labels.statusLabel,
                localCameraLabel: labels.localCameraLabel,
                remoteCameraLabel: labels.remoteCameraLabel,
                actionLabel: labels.actionLabel,
              ),
          ],
        ),
      ),
    );
  }
}
