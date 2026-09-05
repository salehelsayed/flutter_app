import 'dart:async';

import 'package:flutter/services.dart';

/// Native → Dart call-wake channel. AppDelegate invokes [wakeMethod] once per
/// accepted PushKit VoIP push; the Dart side drains the ephemeral call mailbox
/// so a call CallKit already presented exists on the Dart side before the
/// user answers from the lock screen. Nothing else crosses this channel.
final class IosCallWakeChannel {
  IosCallWakeChannel({
    required Future<void> Function() onCallWake,
    MethodChannel? channel,
  }) : _onCallWake = onCallWake,
       _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'mknoon/ios_call_wake';
  static const String wakeMethod = 'callWake';

  final Future<void> Function() _onCallWake;
  final MethodChannel _channel;

  void install() {
    _channel.setMethodCallHandler(_handle);
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }

  Future<Object?> _handle(MethodCall call) async {
    if (call.method != wakeMethod) {
      throw MissingPluginException('unsupported call wake method');
    }
    try {
      await _onCallWake();
      return true;
    } catch (_) {
      // The drain is best effort; the next resume drains again.
      return false;
    }
  }
}
