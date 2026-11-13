import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/call_video_localizations.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Displays one owner-projected slot. Native renderer/capture lifetime belongs
/// to the canonical media owner; this widget never attaches or retires one.
class CallVideoViewSurface extends StatelessWidget {
  const CallVideoViewSurface({
    super.key,
    required this.projection,
    required this.slot,
  });

  final ForegroundCallProjection projection;
  final CallVideoRendererSlot slot;

  @override
  Widget build(BuildContext context) {
    final video = projection.video;
    final session = projection.session;
    final active = switch (session.state) {
      CallState.accepted ||
      CallState.negotiating ||
      CallState.connected ||
      CallState.reconnecting => true,
      _ => false,
    };
    if (!active ||
        video == null ||
        !video.presentation.isVisible ||
        video.presentation.acceptedMedia == null ||
        video.presentation.agreedMedia != CallMediaKind.video) {
      return const SizedBox.shrink();
    }
    final local = slot == CallVideoRendererSlot.local;
    final media = video.presentation;
    final camera = local ? media.localCamera : media.remoteCamera;
    final view = local ? video.localView : video.remoteView;
    final showTexture =
        camera == CallCameraState.on &&
        media.isConnected &&
        !media.isReconnecting &&
        view != null &&
        view.textureId >= 0 &&
        view.width > 0 &&
        view.height > 0;
    final labels = CallVideoLocalizations(AppLocalizations.of(context)!);
    final label = local
        ? labels.localCameraLabel(camera)
        : labels.remoteCameraLabel(camera);
    final colors = context.backgroundReadableColors;
    return Semantics(
      key: ValueKey((
        session.callId,
        video.generation,
        slot,
        showTexture ? view.textureId : null,
        showTexture ? view.width : null,
        showTexture ? view.height : null,
      )),
      container: true,
      identifier: 'call_video_view_${slot.name}',
      label: label,
      image: showTexture,
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: colors.surfaceRaised,
            child: showTexture
                ? FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: view.width.toDouble(),
                      height: view.height.toDouble(),
                      child: Texture(textureId: view.textureId),
                    ),
                  )
                : Center(
                    child: Icon(
                      camera == CallCameraState.paused
                          ? Icons.pause_circle_outline
                          : camera == CallCameraState.off
                          ? Icons.videocam_off_outlined
                          : Icons.hourglass_empty,
                      size: 32,
                      color: colors.iconMuted,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
