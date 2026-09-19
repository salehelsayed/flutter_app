import 'package:flutter/services.dart';

/// An identity-free hint to the existing canonical foreground call runtime.
/// Only the authenticated mailbox drain can admit or present an incoming call.
final class AndroidCallWakeChannel {
  AndroidCallWakeChannel({
    required Future<void> Function() onCallWake,
    MethodChannel? channel,
  }) : _onCallWake = onCallWake,
       _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'mknoon/android_call_wake';
  static const wakeMethod = 'callWake';
  final Future<void> Function() _onCallWake;
  final MethodChannel _channel;

  Future<void> install() async {
    _channel.setMethodCallHandler(_handle);
    try {
      // Native coalesces a push received before this handler was installed.
      await _channel.invokeMethod<void>('ready');
    } catch (_) {
      // Headless admission and the next lifecycle drain remain available.
    }
  }

  void dispose() => _channel.setMethodCallHandler(null);

  Future<Object?> _handle(MethodCall call) async {
    if (call.method != wakeMethod) {
      throw MissingPluginException('unsupported call wake method');
    }
    if (call.arguments != null) return false;
    try {
      await _onCallWake();
      return true;
    } catch (_) {
      return false;
    }
  }
}
