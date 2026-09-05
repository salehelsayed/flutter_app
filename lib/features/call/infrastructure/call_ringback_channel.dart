import 'dart:async';

import 'package:flutter/services.dart';

import '../application/call_ringback_coordinator.dart';
import '../domain/call_id.dart';
import 'android_call_lifecycle_adapter.dart';
import 'ios_call_lifecycle_adapter.dart';

/// Seam for tests; production uses the real method channel.
typedef CallRingbackInvokeMethod =
    Future<Object?> Function(String method, Object? arguments);

/// Dart → native ringback port. It rides the platform's native call lifecycle
/// bridge (the Swift and Kotlin bridges own the tone players and already
/// resolve the Dart call id, which travels as the call handle). A port on any
/// other channel reaches no native code, so the channel is pinned per platform.
final class MethodChannelCallRingbackPort implements CallRingbackPort {
  MethodChannelCallRingbackPort({
    required this.channelName,
    CallRingbackInvokeMethod? invokeMethod,
  }) : _invokeMethod = invokeMethod ?? _channelInvoke(channelName);

  factory MethodChannelCallRingbackPort.ios({
    CallRingbackInvokeMethod? invokeMethod,
  }) => MethodChannelCallRingbackPort(
    channelName: IosCallLifecycleAdapter.methodChannelName,
    invokeMethod: invokeMethod,
  );

  factory MethodChannelCallRingbackPort.android({
    CallRingbackInvokeMethod? invokeMethod,
  }) => MethodChannelCallRingbackPort(
    channelName: AndroidCallLifecycleAdapter.methodChannelName,
    invokeMethod: invokeMethod,
  );

  static const String startMethod = 'startRingback';
  static const String stopMethod = 'stopRingback';
  static const int protocolVersion = 1;

  static CallRingbackInvokeMethod _channelInvoke(String channelName) {
    final channel = MethodChannel(channelName);
    return (method, arguments) =>
        channel.invokeMethod<Object?>(method, arguments);
  }

  final String channelName;
  final CallRingbackInvokeMethod _invokeMethod;

  @override
  Future<bool> start(CallId callId) => _invoke(startMethod, callId);

  @override
  Future<bool> stop(CallId callId) => _invoke(stopMethod, callId);

  Future<bool> _invoke(String method, CallId callId) async {
    try {
      final result = await _invokeMethod(method, <String, Object?>{
        'version': protocolVersion,
        'callHandle': callId.value,
      });
      return result == true;
    } on MissingPluginException {
      // A platform without a native tone player: the call carries on silent.
      return false;
    }
  }
}
