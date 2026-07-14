import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

const String kPrivateMediaProtectionMethodChannel =
    'mknoon/private_media_protection';
const String kPrivateMediaProtectionEventChannel =
    'mknoon/private_media_protection/events';

typedef PrivateMediaProtectionInvoke =
    Future<Object?> Function(String method, Map<String, Object?>? arguments);

enum PrivateMediaProtectionEvent {
  screenshot,
  captureStarted,
  captureStopped,
  inactive,
  background,
  foreground,
  channelFailure,
}

enum PrivateMediaProtectionDebugEvent {
  screenshot,
  captureStarted,
  captureStopped,
  inactive,
  background,
  foreground,
}

class PrivateMediaProtectionOwner {
  PrivateMediaProtectionOwner._(this._token);

  final String _token;
  bool _exited = false;

  @override
  String toString() => 'PrivateMediaProtectionOwner(redacted)';
}

/// Route-scoped Dart owner for the native screenshot/capture protection.
///
/// The opaque owner value crosses only `enter` and `exit`. It is deliberately
/// absent from events, results, errors, diagnostics, and this object's string
/// representation.
class PrivateMediaProtectionCoordinator {
  PrivateMediaProtectionCoordinator({
    required PrivateMediaProtectionInvoke invokeMethod,
    required Stream<Object?> nativeEvents,
  }) : _invokeMethod = invokeMethod {
    _nativeSubscription = nativeEvents.listen(
      _handleNativeEvent,
      onError: (_, _) => _failClosedChannel(),
      onDone: _failClosedChannel,
      cancelOnError: false,
    );
  }

  factory PrivateMediaProtectionCoordinator.platform() {
    const methodChannel = MethodChannel(kPrivateMediaProtectionMethodChannel);
    const eventChannel = EventChannel(kPrivateMediaProtectionEventChannel);
    return PrivateMediaProtectionCoordinator(
      invokeMethod: (method, arguments) =>
          methodChannel.invokeMethod<Object?>(method, arguments),
      nativeEvents: eventChannel.receiveBroadcastStream().cast<Object?>(),
    );
  }

  static PrivateMediaProtectionCoordinator? _sharedPlatformInstance;

  /// One process-wide native channel subscription. Multiple retained
  /// conversations may own route grants, but EventChannel has only one native
  /// sink; sharing prevents a later conversation from stealing that sink.
  static PrivateMediaProtectionCoordinator sharedPlatform() =>
      _sharedPlatformInstance ??= PrivateMediaProtectionCoordinator.platform();

  final PrivateMediaProtectionInvoke _invokeMethod;
  final _eventController =
      StreamController<PrivateMediaProtectionEvent>.broadcast(sync: true);
  final Set<PrivateMediaProtectionOwner> _owners = {};
  final Queue<Future<void> Function()> _ownershipOperations = Queue();
  StreamSubscription<Object?>? _nativeSubscription;
  bool _ownershipOperationActive = false;
  int _pendingOperationCount = 0;
  Completer<void>? _pendingOperationsDrained;
  PrivateMediaProtectionEvent? _latchedCriticalEvent;
  bool _channelFailed = false;
  bool _disposing = false;
  bool _disposed = false;
  Future<void>? _disposeOperation;

  Stream<PrivateMediaProtectionEvent> get events => _eventController.stream;

  PrivateMediaProtectionEvent? get latchedCriticalEvent =>
      _latchedCriticalEvent;

  /// True while native ownership is unresolved or the channel has failed.
  bool get coverActive =>
      _pendingOperationCount > 0 ||
      _channelFailed ||
      _latchedCriticalEvent != null ||
      _disposing ||
      _disposed;

  Future<PrivateMediaProtectionOwner?> enter() {
    if (_disposing || _disposed || _channelFailed) {
      return Future<PrivateMediaProtectionOwner?>.value(null);
    }
    _beginOperation();
    final owner = PrivateMediaProtectionOwner._(_newOwnerToken());
    return _serializeOwnershipOperation(
      () => _enterOwner(owner),
    ).whenComplete(_endOperation);
  }

  Future<PrivateMediaProtectionOwner?> _enterOwner(
    PrivateMediaProtectionOwner owner,
  ) async {
    if (_disposing ||
        _disposed ||
        _channelFailed ||
        _latchedCriticalEvent != null) {
      return null;
    }
    try {
      final result = await _invokeMethod('enter', <String, Object?>{
        'ownerToken': owner._token,
      });
      if (!_isExactProtectionResult(result, expectedProtectionActive: true)) {
        await _balanceUnpublishedOwner(owner);
        _failClosedChannel();
        return null;
      }
      if (_disposing ||
          _disposed ||
          _channelFailed ||
          _latchedCriticalEvent != null) {
        // A late successful native enter must never outlive a concurrent Dart
        // dispose or a pre-route protection incident. Balance the exact
        // unpublished owner before returning.
        await _balanceUnpublishedOwner(owner);
        return null;
      }
      _owners.add(owner);
      return owner;
    } on MissingPluginException {
      await _balanceUnpublishedOwner(owner);
      _failClosedChannel();
      return null;
    } on PlatformException {
      await _balanceUnpublishedOwner(owner);
      _failClosedChannel();
      return null;
    } catch (_) {
      await _balanceUnpublishedOwner(owner);
      _failClosedChannel();
      return null;
    }
  }

  Future<bool> exit(PrivateMediaProtectionOwner owner) {
    if (_disposing || _disposed) return Future<bool>.value(false);
    return _exitOwner(owner);
  }

  Future<bool> _exitOwner(PrivateMediaProtectionOwner owner) {
    _beginOperation();
    return _serializeOwnershipOperation(
      () => _exitPublishedOwner(owner),
    ).whenComplete(_endOperation);
  }

  Future<bool> _exitPublishedOwner(PrivateMediaProtectionOwner owner) async {
    if (owner._exited || !_owners.contains(owner)) return false;
    owner._exited = true;
    _owners.remove(owner);
    final expectedProtectionActive = _owners.isNotEmpty;
    try {
      final result = await _invokeMethod('exit', <String, Object?>{
        'ownerToken': owner._token,
      });
      final ok = _isExactProtectionResult(
        result,
        expectedProtectionActive: expectedProtectionActive,
      );
      if (!ok) {
        _failClosedChannel();
      }
      return ok;
    } on MissingPluginException {
      _failClosedChannel();
      return false;
    } on PlatformException {
      _failClosedChannel();
      return false;
    } catch (_) {
      _failClosedChannel();
      return false;
    }
  }

  Future<Map<String, Object?>> debugGetState() async {
    if (_disposed) return const {};
    try {
      final result = await _invokeMethod('debugGetState', null);
      if (result is! Map) return const {};
      const allowed = <String>{
        'secureApplied',
        'coverVisible',
        'captureActive',
        'activeOwnerCount',
      };
      final state = <String, Object?>{};
      for (final entry in result.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || !allowed.contains(key)) return const {};
        if (value is! bool && value is! int) return const {};
        state[key] = value;
      }
      return state;
    } catch (_) {
      return const {};
    }
  }

  Future<bool> debugInjectEvent(PrivateMediaProtectionDebugEvent event) async {
    if (_disposed) return false;
    try {
      final result = await _invokeMethod('debugInjectEvent', <String, Object?>{
        'event': event.name,
      });
      return _isExactAck(result);
    } catch (_) {
      return false;
    }
  }

  void _handleNativeEvent(Object? raw) {
    if (_disposed || raw is! Map || raw.length != 1) {
      _failClosedChannel();
      return;
    }
    final name = raw['event'];
    if (name is! String) {
      _failClosedChannel();
      return;
    }
    final event = switch (name) {
      'screenshot' => PrivateMediaProtectionEvent.screenshot,
      'captureStarted' => PrivateMediaProtectionEvent.captureStarted,
      'captureStopped' => PrivateMediaProtectionEvent.captureStopped,
      'inactive' => PrivateMediaProtectionEvent.inactive,
      'background' => PrivateMediaProtectionEvent.background,
      'foreground' => PrivateMediaProtectionEvent.foreground,
      _ => null,
    };
    if (event == null) {
      _failClosedChannel();
      return;
    }
    if (event != PrivateMediaProtectionEvent.captureStopped &&
        event != PrivateMediaProtectionEvent.foreground) {
      _latchedCriticalEvent ??= event;
    }
    _eventController.add(event);
  }

  void _failClosedChannel() {
    if (_disposed || _channelFailed) return;
    _channelFailed = true;
    _latchedCriticalEvent = PrivateMediaProtectionEvent.channelFailure;
    _eventController.add(PrivateMediaProtectionEvent.channelFailure);
  }

  Future<bool> _balanceUnpublishedOwner(
    PrivateMediaProtectionOwner owner,
  ) async {
    if (owner._exited) return false;
    owner._exited = true;
    // Every native ownership mutation runs through one transaction queue, so
    // the published Dart set is the exact remaining native-owner truth at this
    // invocation boundary. This includes balancing late or failed enters.
    final expectedProtectionActive = _owners.isNotEmpty;
    try {
      final result = await _invokeMethod('exit', <String, Object?>{
        'ownerToken': owner._token,
      });
      final balanced = _isExactProtectionResult(
        result,
        expectedProtectionActive: expectedProtectionActive,
      );
      if (!balanced) {
        _failClosedChannel();
        return false;
      }
      return true;
    } catch (_) {
      _failClosedChannel();
      return false;
    }
  }

  void _clearRecoverableLatchWhenUnowned() {
    if (_owners.isNotEmpty ||
        _channelFailed ||
        _latchedCriticalEvent == PrivateMediaProtectionEvent.channelFailure) {
      return;
    }
    _latchedCriticalEvent = null;
  }

  bool _isExactProtectionResult(
    Object? result, {
    required bool expectedProtectionActive,
  }) {
    if (result is! Map ||
        result.length != 2 ||
        result.keys.toSet().difference({'ok', 'protectionActive'}).isNotEmpty ||
        result['ok'] != true) {
      return false;
    }
    final protectionActive = result['protectionActive'];
    return protectionActive is bool &&
        protectionActive == expectedProtectionActive;
  }

  bool _isExactAck(Object? result) =>
      result is Map &&
      result.length == 1 &&
      result.keys.single == 'ok' &&
      result['ok'] == true;

  Future<T> _serializeOwnershipOperation<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _ownershipOperations.add(() async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        _ownershipOperationActive = false;
        _startNextOwnershipOperation();
      }
    });
    _startNextOwnershipOperation();
    return result.future;
  }

  void _startNextOwnershipOperation() {
    if (_ownershipOperationActive || _ownershipOperations.isEmpty) return;
    _ownershipOperationActive = true;
    final operation = _ownershipOperations.removeFirst();
    unawaited(operation());
  }

  void _beginOperation() {
    _pendingOperationCount++;
    _pendingOperationsDrained ??= Completer<void>();
  }

  void _endOperation() {
    if (_pendingOperationCount == 0) return;
    _pendingOperationCount--;
    if (_pendingOperationCount == 0) {
      // Keep recoverable incidents sticky until every enter/exit that was
      // pending during the incident has settled. This prevents a queued enter
      // from publishing after an earlier balance clears the latch.
      _clearRecoverableLatchWhenUnowned();
      final drained = _pendingOperationsDrained;
      _pendingOperationsDrained = null;
      if (drained != null && !drained.isCompleted) drained.complete();
    }
  }

  Future<void> _waitForPendingOperations() async {
    while (_pendingOperationCount > 0) {
      final drained = _pendingOperationsDrained;
      if (drained == null) return;
      await drained.future;
    }
  }

  String _newOwnerToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> dispose() => _disposeOperation ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposing = true;
    await _waitForPendingOperations();
    for (final owner in List<PrivateMediaProtectionOwner>.of(_owners)) {
      await _exitOwner(owner);
    }
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
    _disposed = true;
    _disposing = false;
    _latchedCriticalEvent ??= PrivateMediaProtectionEvent.channelFailure;
    await _eventController.close();
  }

  @override
  String toString() =>
      'PrivateMediaProtectionCoordinator(activeOwners: ${_owners.length}, '
      'covered: $coverActive)';
}
