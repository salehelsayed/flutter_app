import 'dart:async';

import 'package:flutter/services.dart';

import '../application/call_ringback_coordinator.dart';
import '../domain/call_id.dart';

/// Seam for tests; production uses the real method channel.
typedef CallRingbackInvokeMethod =
    Future<Object?> Function(String method, Object? arguments);

/// Dart → native ringback channel. Each platform owns one tone player behind
/// it and binds the tone to the Dart call id, which travels as the call handle
/// both platforms already resolve. Nothing else crosses this channel.
final class MethodChannelCallRingbackPort implements CallRingbackPort {
  MethodChannelCallRingbackPort({CallRingbackInvokeMethod? invokeMethod})
    : _invokeMethod = invokeMethod ?? _channelInvoke;

  static const String channelName = 'mknoon/call_ringback';
  static const String startMethod = 'start';
  static const String stopMethod = 'stop';
  static const int protocolVersion = 1;
  static const MethodChannel _channel = MethodChannel(channelName);

  static Future<Object?> _channelInvoke(String method, Object? arguments) =>
      _channel.invokeMethod<Object?>(method, arguments);

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
