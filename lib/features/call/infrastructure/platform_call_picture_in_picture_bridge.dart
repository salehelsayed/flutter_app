import 'package:flutter/services.dart';

import '../application/call_picture_in_picture.dart';

final class PlatformCallPictureInPictureBridge
    implements CallPictureInPictureBridge {
  PlatformCallPictureInPictureBridge({
    this.videoEnabled = false,
    MethodChannel channel = const MethodChannel(methodChannelName),
    EventChannel events = const EventChannel(eventChannelName),
  });

  static const methodChannelName = 'mknoon/call_pip';
  static const eventChannelName = 'mknoon/call_pip/events';
  final bool videoEnabled;

  @override
  Stream<CallPipEvent> get events => const Stream.empty();
  @override
  Future<CallPipAvailability> availability(CallPipIdentity identity) async =>
      CallPipAvailability.unavailable;
  @override
  Future<bool> arm(
    CallPipIdentity identity,
    CallPipSource source, {
    required bool muted,
    required bool cameraOn,
    required bool cameraEnabled,
  }) async => false;
  @override
  Future<bool> enter(CallPipIdentity identity) async => false;
  @override
  Future<bool> update(
    CallPipIdentity identity, {
    required bool muted,
    required bool cameraOn,
    required bool cameraEnabled,
  }) async => false;
  @override
  Future<bool> disarm(CallPipIdentity identity, String reason) async => true;
  @override
  Future<void> close() async {}
}
