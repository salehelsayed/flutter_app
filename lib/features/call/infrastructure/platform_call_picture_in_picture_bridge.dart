import 'dart:async';

import 'package:flutter/services.dart';

import '../application/call_picture_in_picture.dart';
import '../domain/call_id.dart';

final class PlatformCallPictureInPictureBridge
    implements CallPictureInPictureBridge {
  PlatformCallPictureInPictureBridge({
    this.videoEnabled = false,
    MethodChannel channel = const MethodChannel(methodChannelName),
    EventChannel events = const EventChannel(eventChannelName),
  }) : _channel = channel,
       _events = events;

  static const methodChannelName = 'mknoon/call_pip';
  static const eventChannelName = 'mknoon/call_pip/events';
  final bool videoEnabled;
  final MethodChannel _channel;
  final EventChannel _events;
  final _changes = StreamController<CallPipEvent>.broadcast(sync: true);
  StreamSubscription<dynamic>? _subscription;
  bool _closed = false;

  Map<String, Object> _identity(CallPipIdentity id) => {
    'version': 1,
    'instanceId': id.instanceId,
    'callId': id.callId.value,
    'leaseId': id.leaseId,
  };

  @override
  Stream<CallPipEvent> get events {
    if (videoEnabled && !_closed && _subscription == null) {
      _subscription = _events.receiveBroadcastStream().listen(
        _receive,
        onError: (Object error) {
          if (!_closed) _changes.addError(error);
        },
        onDone: () {
          if (!_closed) _changes.addError(StateError('PiP events closed'));
        },
      );
    }
    return _changes.stream;
  }

  void _receive(dynamic value) {
    if (_closed ||
        value is! Map ||
        value['version'] is! int ||
        value['version'] != 1) {
      return;
    }
    final call = value['callId'];
    final instance = value['instanceId'];
    final lease = value['leaseId'];
    final sequence = value['seq'];
    if (call is! String ||
        instance is! String ||
        CallId.tryParse(instance) == null ||
        lease is! int ||
        lease <= 0 ||
        sequence is! int ||
        sequence <= 0) {
      return;
    }
    final callId = CallId.tryParse(call);
    if (callId == null) return;
    CallPipEventType type;
    String? detail;
    switch (value['type']) {
      case 'entered':
        type = CallPipEventType.entered;
      case 'exited':
        type = CallPipEventType.exited;
        if (!const [
          'restored',
          'closed',
          'disarmed',
          'failed',
        ].contains(value['reason'])) {
          return;
        }
        detail = value['reason'] as String;
      case 'action':
        type = CallPipEventType.action;
        if (!const ['mute', 'camera', 'end'].contains(value['kind'])) return;
        detail = value['kind'] as String;
      case 'failed':
        type = CallPipEventType.failed;
        if (!const [
          'enterRejected',
          'trackLost',
          'rendererError',
        ].contains(value['code'])) {
          return;
        }
        detail = value['code'] as String;
      case 'blocked':
        type = CallPipEventType.blocked;
        if (!const ['locked', 'userDisabled'].contains(value['reason'])) return;
        detail = value['reason'] as String;
      default:
        return;
    }
    _changes.add(
      CallPipEvent(
        identity: CallPipIdentity(callId, lease, instanceId: instance),
        sequence: sequence,
        type: type,
        detail: detail,
      ),
    );
  }

  Future<Object?> _invoke(String method, Map<String, Object> args) async {
    if (!videoEnabled || (_closed && method != 'disarm')) return null;
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CallPipAvailability> availability(CallPipIdentity identity) async {
    final result = await _invoke('availability', _identity(identity));
    if (result is! Map ||
        result['supported'] is! bool ||
        result['cameraInPip'] is! bool ||
        result['reason'] is! String) {
      return CallPipAvailability.unavailable;
    }
    final supported = result['supported'] as bool;
    return CallPipAvailability(
      supported: supported,
      cameraInPip: supported && result['cameraInPip'] == true,
    );
  }

  @override
  Future<bool> arm(
    CallPipIdentity identity,
    CallPipSource source, {
    required bool muted,
    required bool cameraOn,
    required bool cameraEnabled,
  }) async {
    final result = await _invoke('arm', {
      ..._identity(identity),
      'negotiationId': source.negotiation.negotiationId,
      'mediaRevision': source.negotiation.mediaRevision,
      'rendererEpoch': source.rendererEpoch,
      'peerConnectionId': source.peerConnectionId,
      'remoteTrackId': source.remoteTrackId,
      'muted': muted,
      'cameraOn': cameraOn,
      'cameraEnabled': cameraEnabled,
    });
    return result is Map &&
        result['armed'] == true &&
        result['reason'] is String;
  }

  @override
  Future<bool> enter(CallPipIdentity identity) async =>
      await _invoke('enter', _identity(identity)) == true;
  @override
  Future<bool> update(
    CallPipIdentity identity, {
    required bool muted,
    required bool cameraOn,
    required bool cameraEnabled,
  }) async =>
      await _invoke('update', {
        ..._identity(identity),
        'muted': muted,
        'cameraOn': cameraOn,
        'cameraEnabled': cameraEnabled,
      }) ==
      true;
  @override
  Future<bool> disarm(CallPipIdentity identity, String reason) async =>
      await _invoke('disarm', {..._identity(identity), 'reason': reason}) ==
      true;
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    await _changes.close();
  }
}
