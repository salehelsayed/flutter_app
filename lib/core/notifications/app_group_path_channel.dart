import 'package:flutter/services.dart';

typedef AppGroupPathPlatformInvoker =
    Future<Object?> Function(String method, Object? arguments);

/// 04-P0 / SI-5: exposes the iOS shared app-group container path to Dart so the
/// [RecentRemoteNotificationGate] can read the out-of-process NSE's cross-process
/// dedupe markers. There is no pure-Dart accessor for the app-group container,
/// so this hops to native (mirrors `DiskSpaceChannel`).
///
/// Returns null off-iOS / when the channel is unavailable (`MissingPluginException`)
/// or the container can't be resolved (`PlatformException`), in which case the
/// gate keeps its app-support-only behavior.
class AppGroupPathChannel {
  static const channelName = 'mknoon/app_group_path';
  static const _channel = MethodChannel(channelName);

  final AppGroupPathPlatformInvoker invoker;

  AppGroupPathChannel({AppGroupPathPlatformInvoker? invoker})
    : invoker = invoker ?? _invokeMethod;

  static Future<Object?> _invokeMethod(String method, Object? arguments) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }

  Future<String?> containerPath() async {
    try {
      final result = await invoker('appGroupContainerPath', null);
      if (result is String && result.trim().isNotEmpty) {
        return result;
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
