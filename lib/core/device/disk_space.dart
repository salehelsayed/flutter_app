import 'package:flutter/services.dart';

typedef DiskSpacePlatformInvoker =
    Future<Object?> Function(String method, Object? arguments);

class DiskSpaceChannel {
  static const channelName = 'mknoon/disk_space';
  static const _channel = MethodChannel(channelName);

  final DiskSpacePlatformInvoker invoker;

  DiskSpaceChannel({DiskSpacePlatformInvoker? invoker})
    : invoker = invoker ?? _invokeMethod;

  static Future<Object?> _invokeMethod(String method, Object? arguments) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }

  Future<int> getAvailableBytes(String path) async {
    final result = await invoker('getAvailableBytes', {'path': path});
    final bytes = switch (result) {
      int value => value,
      num value => value.toInt(),
      _ => throw StateError('disk space channel returned no byte count'),
    };
    if (bytes < 0) {
      throw StateError('disk space channel returned a negative byte count');
    }
    return bytes;
  }
}
