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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
