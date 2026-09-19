import 'dart:typed_data';

import '../domain/call_id.dart';

/// Ephemeral display-only projection. Never persisted, logged, or used for call
/// admission; the native adapter binds it to an already authenticated call.
final class LockedCallPresentation {
  const LockedCallPresentation({
    required this.displayName,
    required this.avatarPng,
    required this.state,
    required this.connectedAtMs,
    required this.light,
    required this.muted,
    required this.muteAvailable,
    required this.speakerOn,
    required this.speakerAvailable,
    required this.routeLabel,
  });

  final String displayName;
  final Uint8List? avatarPng;
  final String state;
  final int? connectedAtMs;
  final bool light;
  final bool muted;
  final bool muteAvailable;
  final bool speakerOn;
  final bool speakerAvailable;
  final String routeLabel;

  Map<String, Object?> toMap() => <String, Object?>{
    'displayName': displayName,
    'avatarPng': avatarPng,
    'state': state,
    'connectedAtMs': connectedAtMs,
    'light': light,
    'muted': muted,
    'muteAvailable': muteAvailable,
    'speakerOn': speakerOn,
    'speakerAvailable': speakerAvailable,
    'routeLabel': routeLabel,
  };
}

abstract interface class LockedCallPresentationPort {
  Future<void> updateLockedPresentation(
    CallId callId,
    LockedCallPresentation presentation,
  );
}
