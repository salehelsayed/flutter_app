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
    this.fill = false,
    this.portrait = false,
    this.emptyRemote = false,
  });

  final ForegroundCallProjection projection;
  final CallVideoRendererSlot slot;
  final bool fill;
  final bool portrait;
  final bool emptyRemote;

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
      child: _frame(
        showTexture: showTexture,
        view: view,
        camera: camera,
        local: local,
        labels: labels,
        colors: colors,
      ),
    );
  }

  Widget _frame({
    required bool showTexture,
    required CallVideoView? view,
    required CallCameraState camera,
    required bool local,
    required CallVideoLocalizations labels,
    required BackgroundReadableColors colors,
  }) {
    Widget content = showTexture
        ? FittedBox(
            fit: fill || portrait ? BoxFit.cover : BoxFit.contain,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: view!.width.toDouble(),
              height: view.height.toDouble(),
              child: Texture(textureId: view.textureId),
            ),
          )
        : emptyRemote && !local && camera != CallCameraState.on
        ? const SizedBox.expand()
        : ColoredBox(
            color: colors.surfaceRaised,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    camera == CallCameraState.paused
                        ? Icons.pause_circle_outline
                        : camera == CallCameraState.off
                        ? Icons.videocam_off_outlined
                        : Icons.hourglass_empty,
                    size: 28,
                    color: colors.iconMuted,
                  ),
                  if (portrait) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        camera == CallCameraState.off
                            ? labels.cameraOffCaption
                            : labels.localCameraLabel(camera),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
    if (fill && showTexture) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          content,
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x44000000),
                    Colors.transparent,
                    Color(0x99000000),
                  ],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (!fill) {
      content = Container(
        foregroundDecoration: portrait
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              )
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(portrait ? 18 : 12),
          child: content,
        ),
      );
    }
    return fill || portrait
        ? SizedBox.expand(child: content)
        : AspectRatio(aspectRatio: 16 / 9, child: content);
  }
}
