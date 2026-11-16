import 'package:flutter/material.dart';

/// Presentation-only classification supplied by the camera action owner.
enum CallCameraResultCardKind {
  permissionDenied,
  permissionRestricted,
  unavailable,
}

/// Camera feedback without permission, settings, or media ownership.
/// All visible copy is supplied by the approved localization binding.
class CallCameraResultCard extends StatelessWidget {
  const CallCameraResultCard({
    required this.kind,
    required this.title,
    required this.dismissLabel,
    required this.onDismiss,
    this.permissionExplanation,
    this.hearingExplanation,
    this.audioAudible = false,
    this.settingsLabel,
    this.onOpenSettings,
    super.key,
  });

  final CallCameraResultCardKind kind;
  final String title;
  final String dismissLabel;
  final VoidCallback onDismiss;
  final String? permissionExplanation;
  final String? hearingExplanation;
  final bool audioAudible;
  final String? settingsLabel;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final permission = kind == CallCameraResultCardKind.permissionDenied;
    final explanation = permission ? permissionExplanation : null;
    final hearing = permission && audioAudible ? hearingExplanation : null;
    final settings = permission ? onOpenSettings : null;
    const foreground = Color(0xfff5f6fa);
    const secondary = Color(0xffc4c6cc);
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Material(
            color: const Color(0xf2111621),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: const BorderSide(color: Color(0xff626774)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Color(0xff403729),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.videocam_off_outlined,
                            color: Color(0xffffbe51),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: foreground,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (explanation != null && explanation.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      explanation,
                      style: const TextStyle(color: secondary, fontSize: 16),
                    ),
                  ],
                  if (hearing != null && hearing.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      hearing,
                      style: const TextStyle(color: secondary, fontSize: 16),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('camera-result-dismiss'),
                        onPressed: onDismiss,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(112, 48),
                          foregroundColor: foreground,
                          side: const BorderSide(color: Color(0xff626774)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: Text(dismissLabel),
                      ),
                      if (settings != null && settingsLabel != null)
                        FilledButton(
                          key: const ValueKey('camera-result-settings'),
                          onPressed: settings,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(112, 48),
                            foregroundColor: const Color(0xff072512),
                            backgroundColor: const Color(0xff1abb60),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          child: Text(settingsLabel!),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
