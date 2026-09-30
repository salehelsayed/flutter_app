import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar_painter.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../application/foreground_call_capability.dart';
import '../application/locked_call_presentation.dart';
import '../domain/call_engine.dart';
import '../domain/call_state.dart';

/// Generates the same contact avatar without a frame callback. A cold locked
/// activity must be able to publish identity even while Flutter is covered.
final class LockedCallProjection {
  LockedCallProjection({
    Future<Uint8List?> Function(String peerId, bool light)? avatarRenderer,
  }) : _avatarRenderer = avatarRenderer ?? renderAvatar;

  final Future<Uint8List?> Function(String peerId, bool light) _avatarRenderer;
  int _generation = 0;
  String? _avatarPeer;
  bool? _avatarLight;
  Uint8List? _avatar;
  Future<Uint8List?>? _avatarLoading;

  void dispose() => _generation++;

  Future<void> update({
    required ForegroundCallCapability? capability,
    required ForegroundCallProjection? projection,
    required String? displayName,
    required bool light,
    required AppLocalizations l10n,
  }) async {
    final generation = ++_generation;
    if (capability is! LockedCallPresentationPort) return;
    final presentationPort = capability as LockedCallPresentationPort;
    final session = projection?.session;
    final callId = session?.callId;
    final peerId = session?.contactPeerId;
    if (session == null ||
        callId == null ||
        peerId == null ||
        session.isTerminal ||
        displayName == null ||
        displayName.isEmpty) {
      return;
    }
    if (_avatarPeer != peerId || _avatarLight != light) {
      _avatar = null;
      _avatarPeer = peerId;
      _avatarLight = light;
      _avatarLoading = _avatarRenderer(peerId, light);
    }
    final audio = projection!.audio;
    final route = switch (audio.selectedRoute) {
      CallAudioOutputRoute.systemDefault =>
        l10n.call_audio_route_system_default,
      CallAudioOutputRoute.earpiece => l10n.call_audio_route_earpiece,
      CallAudioOutputRoute.speaker => l10n.call_speaker,
      CallAudioOutputRoute.wiredHeadset => l10n.call_audio_route_wired_headset,
      CallAudioOutputRoute.bluetooth => l10n.call_audio_route_bluetooth,
    };
    Future<void> publish(Uint8List? avatar) async {
      if (generation != _generation) return;
      try {
        await presentationPort.updateLockedPresentation(
          callId,
          LockedCallPresentation(
            displayName: displayName.length > 128
                ? displayName.substring(0, 128)
                : displayName,
            avatarPng: avatar,
            state: session.state == CallState.incomingValidating
                ? 'preparing'
                : session.state.name,
            connectedAtMs: session.connectedAt?.millisecondsSinceEpoch,
            light: light,
            muted: audio.muted,
            muteAvailable: audio.active,
            speakerOn: audio.selectedRoute == CallAudioOutputRoute.speaker,
            speakerAvailable:
                audio.active &&
                audio.supportedRoutes.contains(CallAudioOutputRoute.speaker),
            routeLabel: l10n.call_audio_output(route),
          ),
        );
      } catch (_) {
        /* A display update must not affect call authority. */
      }
    }

    // The ringing notification needs the contact name before avatar rendering
    // completes. Image decoding can be delayed behind a covered Flutter view.
    await publish(_avatar);
    final avatar = await _avatarLoading;
    if (generation != _generation || avatar == null) return;
    _avatar = avatar;
    await publish(avatar);
  }

  /// Shared foreground/headless raster path; it never awaits a Flutter frame.
  /// Headless engines supply their documents directory because widget-isolate
  /// globals are not initialized by a background admission run.
  static Future<Uint8List?> renderAvatar(
    String peerId,
    bool light, {
    String? documentsDirectory,
  }) async {
    ui.PictureRecorder? recorder;
    ui.Picture? picture;
    ui.Image? photo;
    ui.Image? image;
    try {
      final docs = documentsDirectory ?? UserAvatar.documentsDir;
      if (docs != null) {
        // A corrupt/oversized local photo uses the same generated fallback as
        // UserAvatar. Bound the read before decoding in a headless engine.
        try {
          final file = File('$docs/media/avatars/$peerId.jpg');
          if (await file.exists()) {
            const maximumPhotoBytes = 8 * 1024 * 1024;
            final handle = await file.open();
            late final Uint8List bytes;
            try {
              bytes = await handle.read(maximumPhotoBytes + 1);
            } finally {
              await handle.close();
            }
            if (bytes.length <= maximumPhotoBytes) {
              photo = await _decodePhoto(bytes);
            }
          }
        } catch (_) {
          // Display-only decoding never changes call admission or ownership.
        }
      }
      recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(3);
      if (photo == null) {
        RingAvatarPainter(
          data: RingAvatarGenerator.generate(peerId, 112),
        ).paint(canvas, const Size.square(112));
      } else {
        canvas.drawCircle(
          const Offset(56, 56),
          56,
          Paint()
            ..color = light ? const Color(0xFFFAF8F3) : const Color(0xFF16181E),
        );
        canvas.save();
        canvas.clipPath(Path()..addOval(const Rect.fromLTWH(2, 2, 108, 108)));
        paintImage(
          canvas: canvas,
          rect: const Rect.fromLTWH(2, 2, 108, 108),
          image: photo,
          fit: BoxFit.cover,
        );
        canvas.restore();
        canvas.drawCircle(
          const Offset(56, 56),
          55,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = light ? const Color(0xFFB3ACBD) : const Color(0x59FFFFFF),
        );
      }
      picture = recorder.endRecording();
      image = await picture.toImage(336, 336);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      photo?.dispose();
      picture?.dispose();
      if (recorder?.isRecording ?? false) {
        recorder!.endRecording().dispose();
      }
    }
  }

  static Future<ui.Image> _decodePhoto(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      // Match UserAvatar's aspect-preserving fit: bound both decoded axes,
      // without enlarging small photos. Canvas cover-crops the result later.
      final longestSide = width > height ? width : height;
      final scale = longestSide > 336 ? 336 / longestSide : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: (width * scale).round().clamp(1, 336),
        targetHeight: (height * scale).round().clamp(1, 336),
      );
      return (await codec.getNextFrame()).image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
