import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/notifications/notification_request_observation.dart';

/// Narrow controls on the production foreground-push callback. This class owns
/// no listener, repository, visibility policy, or notification implementation.
final class ForegroundGroupPushControl {
  Future<void> Function(RemoteMessage)? _handlePush;
  String? _failedDrainGroup;
  int _drainAttempts = 0;
  bool _injecting = false;
  bool _disposed = false;
  Map<String, Object?>? _lastResult;
  final List<NotificationRequestObservation> _requests = [];

  bool get isBound => _handlePush != null && !_disposed;

  void bind(Future<void> Function(RemoteMessage) handlePush) {
    if (_disposed || _handlePush != null) {
      throw StateError('foreground push binding is not available');
    }
    _handlePush = handlePush;
  }

  void observeNotification(NotificationRequestObservation request) {
    if (_disposed) return;
    if (_requests.length >= 256) {
      // Loss of observation cannot be interpreted as a successful assertion.
      _observationOverflow = true;
      return;
    }
    _requests.add(request);
  }

  bool _observationOverflow = false;

  List<Map<String, Object?>> snapshotNotifications() {
    if (_observationOverflow) {
      throw StateError('notification observation overflow');
    }
    return _requests.map((value) => value.toJson()).toList(growable: false);
  }

  void beforeGroupDrain(String groupId) {
    if (!_injecting) return;
    _drainAttempts += 1;
    if (_failedDrainGroup == groupId) {
      throw StateError('controlled missing-group drain failure');
    }
  }

  void observePushResult({
    required String result,
    required bool fallbackShown,
  }) {
    if (!_injecting) return;
    _lastResult = {'result': result, 'fallbackShown': fallbackShown};
  }

  Future<Map<String, Object?>> inject({
    required String groupId,
    required String messageId,
    bool failMissingGroupDrain = false,
  }) async {
    final handler = _handlePush;
    if (!isBound || handler == null || _injecting) {
      throw StateError('production foreground push is not available');
    }
    _injecting = true;
    _failedDrainGroup = failMissingGroupDrain ? groupId : null;
    _drainAttempts = 0;
    _lastResult = null;
    try {
      await handler(
        RemoteMessage(
          messageId: messageId,
          data: {
            'type': 'group_message',
            'groupId': groupId,
            'message_id': messageId,
          },
        ),
      );
      final result = _lastResult;
      if (result == null) {
        throw StateError(
          'production push did not complete fallback evaluation',
        );
      }
      return {...result, 'drainAttempts': _drainAttempts};
    } finally {
      _injecting = false;
      _failedDrainGroup = null;
    }
  }

  void dispose() {
    _disposed = true;
    _handlePush = null;
    _failedDrainGroup = null;
    _requests.clear();
  }
}
