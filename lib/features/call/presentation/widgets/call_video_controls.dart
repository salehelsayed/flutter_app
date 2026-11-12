import 'package:flutter/material.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';

/// Optional video presentation alongside independently owned audio controls.
/// All product and accessibility wording is supplied by the binding owner.
class CallVideoControls extends StatelessWidget {
  const CallVideoControls({
    super.key,
    required this.presentation,
    required this.audioControls,
    required this.onIntent,
    required this.controlsLabel,
    required this.statusLabel,
    required this.localCameraLabel,
    required this.remoteCameraLabel,
    required this.actionLabel,
  });

  final CallVideoPresentation presentation;
  final Widget audioControls;
  final ValueChanged<CallVideoIntent> onIntent;
  final String controlsLabel;
  final String Function(CallVideoStatus) statusLabel;
  final String Function(CallCameraState) localCameraLabel;
  final String Function(CallCameraState) remoteCameraLabel;
  final String Function(CallVideoAction) actionLabel;

  @override
  Widget build(BuildContext context) => audioControls;
}
