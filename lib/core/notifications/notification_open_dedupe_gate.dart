import 'dart:collection';

import 'package:flutter_app/core/notifications/notification_route_target.dart';

class NotificationOpenDedupeGate {
  final int maxEntries;
  final Duration inFlightTtl;
  final Duration completedTtl;
  final DateTime Function() _now;
  final Queue<String> _order = Queue<String>();
  final Map<String, _DedupeEntry> _entries = <String, _DedupeEntry>{};

  NotificationOpenDedupeGate({
    this.maxEntries = 64,
    this.inFlightTtl = const Duration(minutes: 2),
    this.completedTtl = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  bool tryBegin(Map<String, dynamic> data) {
    final key = dedupeKeyFor(data);
    if (key == null) {
      return true;
    }

    _pruneExpired();
    if (_entries.containsKey(key)) {
      return false;
    }

    _entries[key] = _DedupeEntry.inFlight(_now());
    _remember(key);
    return true;
  }

  void finish(Map<String, dynamic> data, {required bool success}) {
    final key = dedupeKeyFor(data);
    if (key == null) {
      return;
    }

    if (success) {
      _entries[key] = _DedupeEntry.completed(_now());
      _remember(key);
    } else {
      _remove(key);
    }
  }

  bool shouldRoute(Map<String, dynamic> data) {
    final shouldRoute = tryBegin(data);
    if (shouldRoute) {
      finish(data, success: true);
    }
    return shouldRoute;
  }

  static String? dedupeKeyFor(Map<String, dynamic> data) {
    final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);
    final routeMessageId =
        NotificationRouteTarget.messageIdFromRemoteMessageData(data) ??
        routeTarget?.messageId;
    if (routeTarget != null && routeMessageId != null) {
      return 'route:${_routeIdentity(routeTarget)}:message:$routeMessageId';
    }

    if (routeMessageId != null) {
      final type =
          _trimToNull(data['type']) ??
          _trimToNull(data['payloadType']) ??
          _trimToNull(data['kind']) ??
          'remote';
      return 'route:$type:$routeMessageId';
    }

    final fcmMessageId = _trimToNull(data['gcm.message_id']);
    if (fcmMessageId != null) {
      return 'fcm:$fcmMessageId';
    }

    return null;
  }

  void _pruneExpired() {
    final referenceTime = _now();
    final expiredKeys = <String>[];
    for (final entry in _entries.entries) {
      final ttl = entry.value.state == _DedupeState.inFlight
          ? inFlightTtl
          : completedTtl;
      if (entry.value.isExpired(referenceTime, ttl)) {
        expiredKeys.add(entry.key);
      }
    }
    for (final key in expiredKeys) {
      _remove(key);
    }
  }

  void _remember(String key) {
    _order.remove(key);
    _order.addLast(key);
    while (_order.length > maxEntries) {
      _entries.remove(_order.removeFirst());
    }
  }

  void _remove(String key) {
    _entries.remove(key);
    _order.remove(key);
  }

  static String _routeIdentity(NotificationRouteTarget routeTarget) {
    return switch (routeTarget.kind) {
      NotificationRouteTargetKind.conversation =>
        'conversation:${routeTarget.peerId ?? ''}',
      NotificationRouteTargetKind.contactRequest =>
        'contact_request:${routeTarget.peerId ?? ''}',
      NotificationRouteTargetKind.group => 'group:${routeTarget.groupId ?? ''}',
      NotificationRouteTargetKind.intros => 'intros',
      NotificationRouteTargetKind.post => 'post:${routeTarget.postId ?? ''}',
      NotificationRouteTargetKind.postComment =>
        'post_comment:${routeTarget.postId ?? ''}:${routeTarget.commentId ?? ''}',
    };
  }

  static String? _trimToNull(Object? value) {
    final trimmed = value?.toString().trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

enum _DedupeState { inFlight, completed }

class _DedupeEntry {
  final _DedupeState state;
  final DateTime createdAt;

  const _DedupeEntry._({required this.state, required this.createdAt});

  factory _DedupeEntry.inFlight(DateTime createdAt) {
    return _DedupeEntry._(state: _DedupeState.inFlight, createdAt: createdAt);
  }

  factory _DedupeEntry.completed(DateTime createdAt) {
    return _DedupeEntry._(state: _DedupeState.completed, createdAt: createdAt);
  }

  bool isExpired(DateTime now, Duration ttl) {
    return now.difference(createdAt) >= ttl;
  }
}
