import 'dart:collection';

class NotificationOpenDedupeGate {
  final int maxEntries;
  final Queue<String> _order = Queue<String>();
  final Set<String> _seen = <String>{};

  NotificationOpenDedupeGate({this.maxEntries = 64});

  bool shouldRoute(Map<String, dynamic> data) {
    final key = dedupeKeyFor(data);
    if (key == null) {
      return true;
    }
    if (_seen.contains(key)) {
      return false;
    }

    _seen.add(key);
    _order.addLast(key);
    while (_order.length > maxEntries) {
      _seen.remove(_order.removeFirst());
    }
    return true;
  }

  static String? dedupeKeyFor(Map<String, dynamic> data) {
    final messageId =
        _trimToNull(data['message_id']) ??
        _trimToNull(data['messageId']) ??
        _trimToNull(data['id']) ??
        _trimToNull(data['msgId']);
    if (messageId != null) {
      final type = _trimToNull(data['type']) ?? 'remote';
      return 'route:$type:$messageId';
    }

    final fcmMessageId = _trimToNull(data['gcm.message_id']);
    if (fcmMessageId != null) {
      return 'fcm:$fcmMessageId';
    }

    return null;
  }

  static String? _trimToNull(Object? value) {
    final trimmed = value?.toString().trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
