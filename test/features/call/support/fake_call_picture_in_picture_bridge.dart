import 'dart:async';

import 'package:flutter_app/features/call/application/call_picture_in_picture.dart';

final class FakeCallPictureInPictureBridge
    implements CallPictureInPictureBridge {
  late final controller = StreamController<CallPipEvent>.broadcast(
    sync: true,
    onListen: () => listens++,
  );
  int listens = 0;
  int availabilityCalls = 0;
  int closes = 0;
  bool supported = true;
  bool cameraInPip = false;
  bool armResult = true;
  bool enterResult = true;
  bool disarmResult = true;
  Completer<bool>? pendingArm;
  final arms = <CallPipIdentity>[];
  final sources = <CallPipSource>[];
  final enters = <CallPipIdentity>[];
  final updates = <({CallPipIdentity identity, bool muted, bool cameraOn})>[];
  final disarms = <CallPipIdentity>[];

  @override
  Stream<CallPipEvent> get events => controller.stream;
  @override
  Future<CallPipAvailability> availability(CallPipIdentity identity) async {
    availabilityCalls++;
    return CallPipAvailability(supported: supported, cameraInPip: cameraInPip);
  }

  @override
  Future<bool> arm(
    CallPipIdentity identity,
    CallPipSource source, {
    required bool muted,
    required bool cameraOn,
    required bool cameraEnabled,
  }) async {
    arms.add(identity);
    sources.add(source);
    return await pendingArm?.future ?? armResult;
  }

  @override
  Future<bool> enter(CallPipIdentity identity) async {
    enters.add(identity);
    return enterResult;
  }

  @override
  Future<bool> update(
    CallPipIdentity identity, {
    required bool muted,
    required bool cameraOn,
    required bool cameraEnabled,
  }) async {
    updates.add((identity: identity, muted: muted, cameraOn: cameraOn));
    return true;
  }

  @override
  Future<bool> disarm(CallPipIdentity identity, String reason) async {
    disarms.add(identity);
    return disarmResult;
  }

  void emit(
    CallPipIdentity identity,
    int sequence,
    CallPipEventType type, [
    String? detail,
  ]) => controller.add(
    CallPipEvent(
      identity: identity,
      sequence: sequence,
      type: type,
      detail: detail,
    ),
  );

  @override
  Future<void> close() async {
    closes++;
    await controller.close();
  }
}
