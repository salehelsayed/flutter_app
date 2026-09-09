import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import '../domain/call_engine.dart';

typedef CallAudioOutputEnumerator =
    Future<List<CallAudioOutputRoute>> Function();
typedef CallAudioOutputSelector =
    Future<void> Function(CallAudioOutputRoute route);
typedef CallSpeakerphoneSetter = Future<void> Function(bool enabled);
typedef CallAudioDeviceChangeObserverInstaller =
    void Function(void Function() observer);
typedef CallAudioDeviceChangeObserverRemover = FutureOr<void> Function();

Duration _requirePositiveEnumerationTimeout(Duration timeout) {
  if (timeout.inMicroseconds <= 0) {
    throw ArgumentError.value(
      timeout,
      'enumerationTimeout',
      'must be positive',
    );
  }
  return timeout;
}

abstract interface class CallAudioRoutePort {
  CallAudioOutputRoute get selectedRoute;

  Future<List<CallAudioOutputRoute>> supportedOutputRoutes();

  Future<void> selectOutputRoute(CallAudioOutputRoute route);
}

/// Optional lifecycle implemented by route ports that own a platform observer.
abstract interface class CallAudioRouteObserverLifecycle {
  Future<void> close();
}

enum CallAudioRouteErrorCode { enumerationFailed, unsupported, selectionFailed }

/// Stable route failure with no platform identifier, label, or plugin error.
final class CallAudioRouteException implements Exception {
  const CallAudioRouteException(this.code);

  final CallAudioRouteErrorCode code;

  @override
  String toString() => 'CallAudioRouteException(${code.name})';
}

/// Maps platform audio outputs to the app's fixed, coarse route vocabulary.
final class CallAudioRouteAdapter
    implements
        CallAudioRoutePort,
        CallAudioOutputRouteChangeSource,
        CallAudioRouteObserverLifecycle {
  CallAudioRouteAdapter({
    required CallAudioOutputEnumerator enumerateOutputs,
    required CallAudioOutputSelector selectOutput,
    required CallSpeakerphoneSetter? setSpeakerphone,
    CallAudioDeviceChangeObserverInstaller? installDeviceChangeObserver,
    CallAudioDeviceChangeObserverRemover? removeDeviceChangeObserver,
    Duration enumerationTimeout = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _enumerateOutputs = enumerateOutputs,
       _selectOutput = selectOutput,
       _setSpeakerphone = setSpeakerphone,
       _clock = clock ?? DateTime.now,
       _enumerationTimeout = _requirePositiveEnumerationTimeout(
         enumerationTimeout,
       ),
       _removeDeviceChangeObserver = removeDeviceChangeObserver {
    installDeviceChangeObserver?.call(_onDeviceChange);
  }

  factory CallAudioRouteAdapter.flutterWebRtc() {
    final operations = _FlutterWebRtcAudioRouteOperations();
    final deviceChangeObserver = _FlutterWebRtcAudioDeviceChangeObserver();
    return CallAudioRouteAdapter(
      enumerateOutputs: operations.enumerate,
      selectOutput: operations.select,
      setSpeakerphone: webrtc.Helper.setSpeakerphoneOn,
      installDeviceChangeObserver: deviceChangeObserver.install,
      removeDeviceChangeObserver: deviceChangeObserver.remove,
    );
  }

  final CallAudioOutputEnumerator _enumerateOutputs;
  final CallAudioOutputSelector _selectOutput;
  final CallSpeakerphoneSetter? _setSpeakerphone;
  final Duration _enumerationTimeout;
  final CallAudioDeviceChangeObserverRemover? _removeDeviceChangeObserver;
  final StreamController<CallAudioOutputRoute> _outputRouteChanges =
      StreamController<CallAudioOutputRoute>.broadcast(sync: true);

  CallAudioOutputRoute _selectedRoute = CallAudioOutputRoute.systemDefault;
  Future<void>? _closeFuture;
  int _deviceChangeGeneration = 0;
  bool _closed = false;

  @override
  CallAudioOutputRoute get selectedRoute => _selectedRoute;

  @override
  Stream<CallAudioOutputRoute> get outputRouteChanges =>
      _outputRouteChanges.stream;

  @override
  Future<List<CallAudioOutputRoute>> supportedOutputRoutes() async {
    _ensureOpen(CallAudioRouteErrorCode.enumerationFailed);
    try {
      final platformRoutes = await _enumerateOutputs().timeout(
        _enumerationTimeout,
      );
      _ensureOpen(CallAudioRouteErrorCode.enumerationFailed);
      return _supportedRoutes(platformRoutes);
    } on TimeoutException {
      _ensureOpen(CallAudioRouteErrorCode.enumerationFailed);
      return _supportedRoutes(const <CallAudioOutputRoute>[]);
    } catch (_) {
      throw const CallAudioRouteException(
        CallAudioRouteErrorCode.enumerationFailed,
      );
    }
  }

  List<CallAudioOutputRoute> _supportedRoutes(
    Iterable<CallAudioOutputRoute> platformRoutes,
  ) {
    final supported = <CallAudioOutputRoute>{
      CallAudioOutputRoute.systemDefault,
      ...platformRoutes,
    };
    if (_setSpeakerphone != null) {
      supported.add(CallAudioOutputRoute.speaker);
    }
    return List<CallAudioOutputRoute>.unmodifiable(
      CallAudioOutputRoute.values.where(supported.contains),
    );
  }

  @override
  Future<void> selectOutputRoute(CallAudioOutputRoute route) async {
    _ensureOpen(CallAudioRouteErrorCode.selectionFailed);
    final supported = await supportedOutputRoutes();
    _ensureOpen(CallAudioRouteErrorCode.selectionFailed);
    if (!supported.contains(route)) {
      throw const CallAudioRouteException(CallAudioRouteErrorCode.unsupported);
    }

    final deviceChangeGeneration = _deviceChangeGeneration;
    try {
      switch (route) {
        case CallAudioOutputRoute.systemDefault:
          final setSpeakerphone = _setSpeakerphone;
          if (setSpeakerphone != null) await setSpeakerphone(false);
        case CallAudioOutputRoute.speaker:
          final setSpeakerphone = _setSpeakerphone;
          if (setSpeakerphone != null) {
            await setSpeakerphone(true);
          } else {
            await _selectOutput(route);
          }
        case CallAudioOutputRoute.earpiece:
        case CallAudioOutputRoute.wiredHeadset:
        case CallAudioOutputRoute.bluetooth:
          await _selectOutput(route);
      }
    } on CallAudioRouteException {
      rethrow;
    } catch (_) {
      throw const CallAudioRouteException(
        CallAudioRouteErrorCode.selectionFailed,
      );
    }
    _ensureOpen(CallAudioRouteErrorCode.selectionFailed);
    if (deviceChangeGeneration == _deviceChangeGeneration) {
      _selectedRoute = route;
    }
    // The platform reports the selection itself as a device change, on
    // Android before the method result and on iOS just after it. Treat a
    // change inside this window as caused by the selection.
    _selectedRoute = route;
    _selectionSettledAt = _clock();
  }

  void _ensureOpen(CallAudioRouteErrorCode code) {
    if (_closed) throw CallAudioRouteException(code);
  }

  final DateTime Function() _clock;
  DateTime? _selectionSettledAt;
  static const Duration _selectionEchoWindow = Duration(milliseconds: 750);

  void _onDeviceChange() {
    if (_closed) return;
    final settledAt = _selectionSettledAt;
    if (settledAt != null &&
        _clock().difference(settledAt) < _selectionEchoWindow) {
      return;
    }
    _deviceChangeGeneration++;
    _selectedRoute = CallAudioOutputRoute.systemDefault;
    if (!_outputRouteChanges.isClosed) {
      _outputRouteChanges.add(CallAudioOutputRoute.systemDefault);
    }
  }

  @override
  Future<void> close() => _closeFuture ??= _closeOnce();

  Future<void> _closeOnce() async {
    if (_closed) return;
    _closed = true;
    _selectedRoute = CallAudioOutputRoute.systemDefault;
    try {
      final removeObserver = _removeDeviceChangeObserver;
      if (removeObserver != null) {
        await Future<void>.sync(removeObserver);
      }
    } finally {
      await _outputRouteChanges.close();
    }
  }
}

final class _FlutterWebRtcAudioDeviceChangeObserver {
  Function(dynamic)? _callback;

  void install(void Function() onDeviceChange) {
    void callback(dynamic _) => onDeviceChange();
    _callback = callback;
    webrtc.navigator.mediaDevices.ondevicechange = callback;
  }

  void remove() {
    final callback = _callback;
    _callback = null;
    if (callback != null &&
        identical(webrtc.navigator.mediaDevices.ondevicechange, callback)) {
      webrtc.navigator.mediaDevices.ondevicechange = null;
    }
  }
}

final class _FlutterWebRtcAudioRouteOperations {
  final Map<CallAudioOutputRoute, String> _identifiers =
      <CallAudioOutputRoute, String>{};

  Future<List<CallAudioOutputRoute>> enumerate() async {
    final outputs = await webrtc.Helper.audiooutputs;
    _identifiers.clear();
    final routes = <CallAudioOutputRoute>{};
    for (final output in outputs) {
      final route = _classify('${output.label} ${output.deviceId}');
      if (route == null) continue;
      routes.add(route);
      _identifiers.putIfAbsent(route, () => output.deviceId);
    }
    return List<CallAudioOutputRoute>.unmodifiable(
      CallAudioOutputRoute.values.where(routes.contains),
    );
  }

  Future<void> select(CallAudioOutputRoute route) async {
    var identifier = _identifiers[route];
    if (identifier == null) {
      await enumerate();
      identifier = _identifiers[route];
    }
    if (identifier == null) {
      throw const CallAudioRouteException(CallAudioRouteErrorCode.unsupported);
    }
    await webrtc.Helper.selectAudioOutput(identifier);
  }

  static CallAudioOutputRoute? _classify(String value) {
    value = value.toLowerCase();
    if (value.contains('bluetooth') ||
        value.contains('a2dp') ||
        value.contains('sco')) {
      return CallAudioOutputRoute.bluetooth;
    }
    if (value.contains('wired') ||
        value.contains('headphone') ||
        value.contains('headset') ||
        value.contains('usb')) {
      return CallAudioOutputRoute.wiredHeadset;
    }
    if (value.contains('earpiece') || value.contains('receiver')) {
      return CallAudioOutputRoute.earpiece;
    }
    if (value.contains('speaker')) return CallAudioOutputRoute.speaker;
    if (value.contains('default')) return CallAudioOutputRoute.systemDefault;
    return null;
  }
}
