import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
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
  Widget build(BuildContext context) {
    if (!presentation.isVisible) return audioControls;
    final colors = context.backgroundReadableColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          identifier: 'call_video_controls',
          container: true,
          explicitChildNodes: true,
          label: controlsLabel,
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _state(
                  'call_video_status',
                  statusLabel(presentation.status),
                  colors.textPrimary,
                  primary: true,
                ),
                const SizedBox(height: 6),
                _state(
                  'call_video_local_camera',
                  localCameraLabel(presentation.localCamera),
                  colors.textSecondary,
                ),
                _state(
                  'call_video_remote_camera',
                  remoteCameraLabel(presentation.remoteCamera),
                  colors.textSecondary,
                ),
                if (presentation.actions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in presentation.actions)
                        _button(action, constraints.maxWidth, colors),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Optional video never owns audio availability or its callbacks.
        audioControls,
      ],
    );
  }

  Widget _state(
    String identifier,
    String text,
    Color color, {
    bool primary = false,
  }) => Semantics(
    key: ValueKey(identifier),
    identifier: identifier,
    container: true,
    liveRegion: true,
    label: text,
    excludeSemantics: true,
    child: Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: primary ? 14 : 12,
        fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
  );

  Widget _button(
    CallVideoAction action,
    double maxWidth,
    BackgroundReadableColors colors,
  ) {
    final enabled = presentation.isAvailable(action);
    final label = actionLabel(action);
    final cameraAction =
        action == CallVideoAction.turnCameraOn ||
        action == CallVideoAction.turnCameraOff;
    void emit() {
      final intent = presentation.intentFor(action);
      if (intent != null) onIntent(intent);
    }

    return Semantics(
      key: ValueKey(action.identifier),
      identifier: action.identifier,
      container: true,
      button: true,
      enabled: enabled,
      toggled: cameraAction
          ? presentation.localCamera == CallCameraState.on
          : null,
      label: cameraAction
          ? '$label. ${localCameraLabel(presentation.localCamera)}'
          : label,
      onTap: enabled ? emit : null,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 48,
          minHeight: 48,
          maxWidth: maxWidth,
        ),
        child: OutlinedButton(
          onPressed: enabled ? emit : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            foregroundColor: colors.iconPrimary,
            disabledForegroundColor: colors.disabledForeground,
            backgroundColor: colors.surfaceRaised,
            disabledBackgroundColor: colors.disabledSurface,
            side: BorderSide(color: colors.inputBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon(action), size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled
                        ? colors.textPrimary
                        : colors.disabledForeground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _icon(CallVideoAction action) => switch (action) {
    CallVideoAction.requestVideo => Icons.video_call_outlined,
    CallVideoAction.acceptUpgrade => Icons.check_circle_outline,
    CallVideoAction.declineUpgrade => Icons.call_outlined,
    CallVideoAction.cancelUpgrade => Icons.close,
    CallVideoAction.turnCameraOn => Icons.videocam_outlined,
    CallVideoAction.turnCameraOff => Icons.videocam_off_outlined,
    CallVideoAction.switchCamera => Icons.cameraswitch_outlined,
    CallVideoAction.useAudioOnly => Icons.call_outlined,
  };
}
