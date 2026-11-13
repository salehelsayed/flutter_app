import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/call_video_quality_environment.dart';

/// Reads the OS video quality inputs through one event channel.
///
/// The source is inert unless [videoEnabled] is true: [start] then does not
/// listen to the channel, so the platform registers no callback and reads no
/// state. Each native event is a complete snapshot map. A missing, unknown or
/// malformed field becomes unknown; a channel error becomes
/// [CallVideoQualityEnvironment.unknown] instead of a stream error.
final class PlatformCallVideoQualityEnvironmentSource
    implements CallVideoQualityEnvironmentSource {
  PlatformCallVideoQualityEnvironmentSource({
    this.videoEnabled = false,
    EventChannel channel = const EventChannel(eventChannelName),
  }) : _channel = channel;

  static const eventChannelName = 'mknoon/call_video_quality/events';

  final bool videoEnabled;
  final EventChannel _channel;
  final StreamController<CallVideoQualityEnvironment> _live =
      StreamController<CallVideoQualityEnvironment>.broadcast(sync: true);

  CallVideoQualityEnvironment _current = CallVideoQualityEnvironment.unknown;
  StreamSubscription<dynamic>? _subscription;
  bool _started = false;
  bool _closed = false;

  @override
  CallVideoQualityEnvironment get current => _current;

  @override
  Stream<CallVideoQualityEnvironment> get changes {
    return Stream<CallVideoQualityEnvironment>.multi((subscriber) {
      if (_closed) {
        subscriber.close();
        return;
      }
      subscriber.add(_current);
      final live = _live.stream.listen(
        subscriber.add,
        onDone: subscriber.close,
      );
      subscriber.onCancel = live.cancel;
    });
  }

  @override
  Future<void> start() async {
    if (!videoEnabled || _closed || _started) return;
    _started = true;
    _subscription = _channel.receiveBroadcastStream().listen(
      (Object? event) => _publish(parseSnapshot(event)),
      onError: (Object _) => _publish(CallVideoQualityEnvironment.unknown),
      cancelOnError: false,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _current = CallVideoQualityEnvironment.unknown;
    final subscription = _subscription;
    _subscription = null;
    await _live.close();
    await subscription?.cancel();
  }

  void _publish(CallVideoQualityEnvironment snapshot) {
    if (_closed) return;
    _current = snapshot;
    _live.add(snapshot);
  }

  /// Parses one native snapshot map. Anything not exactly typed is unknown.
  static CallVideoQualityEnvironment parseSnapshot(Object? event) {
    if (event is! Map) return CallVideoQualityEnvironment.unknown;
    return CallVideoQualityEnvironment(
      networkClass: _networkClass(event['networkClass']),
      lowDataMode: _flag(event['lowDataMode']),
      metered: _flag(event['metered']),
      thermalState: _thermalState(event['thermalState']),
    );
  }

  static bool? _flag(Object? value) => value is bool ? value : null;

  static CallVideoNetworkClass _networkClass(Object? value) {
    return switch (value) {
      'wifi' => CallVideoNetworkClass.wifi,
      'cellular' => CallVideoNetworkClass.cellular,
      'other' => CallVideoNetworkClass.other,
      _ => CallVideoNetworkClass.unknown,
    };
  }

  static CallVideoThermalState _thermalState(Object? value) {
    return switch (value) {
      'nominal' => CallVideoThermalState.nominal,
      'elevated' => CallVideoThermalState.elevated,
      'serious' => CallVideoThermalState.serious,
      'critical' => CallVideoThermalState.critical,
      _ => CallVideoThermalState.unknown,
    };
  }
}
