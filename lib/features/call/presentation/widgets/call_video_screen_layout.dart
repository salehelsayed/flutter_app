import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
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
    this.videoViews,
    this.preAnswer = false,
  });

  final Widget profile;
  final Widget audioControls;
  final CallVideoPresentation presentation;
  final ValueChanged<CallVideoIntent> onIntent;
  final double topPadding;
  final bool showVideoControls;
  final Widget? videoViews;
  final bool preAnswer;

  @override
  Widget build(BuildContext context) {
    final labels = CallVideoLocalizations(AppLocalizations.of(context)!);
    if (preAnswer) return _buildEntry(context, labels);
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
            if (videoViews != null) ...[
              videoViews!,
              const SizedBox(height: 16),
            ],
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

  Widget _buildEntry(BuildContext context, CallVideoLocalizations labels) {
    final controls = !showVideoControls
        ? audioControls
        : CallVideoControls(
            presentation: presentation,
            audioControls: audioControls,
            onIntent: onIntent,
            preAnswer: true,
            controlsLabel: labels.controlsLabel,
            statusLabel: labels.statusLabel,
            localCameraLabel: labels.localCameraLabel,
            remoteCameraLabel: labels.remoteCameraLabel,
            actionLabel: labels.actionLabel,
          );
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.dark,
        extensions: [
          ...Theme.of(context).extensions.values
              .where((e) => e is! BackgroundReadableColors),
          BackgroundReadableColors.dark,
        ],
      ),
      child: CosmicBackground(
        paused: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              key: const ValueKey('call-video-scroll'),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 104, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        profile,
                        const SizedBox(height: 32),
                        const Spacer(),
                        controls,
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
