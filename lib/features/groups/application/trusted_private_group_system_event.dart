class TrustedPrivateMemberSystemEvent {
  const TrustedPrivateMemberSystemEvent({
    required this.systemType,
    required this.targetPeerId,
    this.targetUsername,
    required this.eventAt,
  });

  final String systemType;
  final String targetPeerId;
  final String? targetUsername;
  final DateTime eventAt;
}

class TrustedPrivateMessageDeleteSystemEvent {
  const TrustedPrivateMessageDeleteSystemEvent({
    required this.targetMessageId,
    required this.eventAt,
  });

  final String targetMessageId;
  final DateTime eventAt;
}

DateTime? trustedPrivateSystemEventAt(
  String? systemType,
  Map<String, dynamic> payload, {
  DateTime? fallback,
}) {
  final fieldNames = switch (systemType) {
    'member_banned' => const ['bannedAt', 'eventAt', 'timestamp'],
    'member_unbanned' => const ['unbannedAt', 'eventAt', 'timestamp'],
    'group_message_deleted' => const ['deletedAt', 'eventAt', 'timestamp'],
    _ => const ['eventAt', 'timestamp'],
  };
  for (final fieldName in fieldNames) {
    final value = _readString(payload, fieldName);
    final parsed = _parseUtc(value);
    if (parsed != null) {
      return parsed;
    }
  }
  return fallback?.toUtc();
}

TrustedPrivateMemberSystemEvent? parseTrustedPrivateMemberSystemEvent(
  Map<String, dynamic> payload, {
  required String systemType,
  DateTime? fallbackEventAt,
}) {
  if (systemType != 'member_banned' && systemType != 'member_unbanned') {
    return null;
  }
  final member = _stringMap(payload['member']);
  final targetPeerId =
      _readString(payload, 'targetPeerId') ??
      _readString(payload, 'memberPeerId') ??
      _readString(
        payload,
        systemType == 'member_banned' ? 'bannedPeerId' : 'unbannedPeerId',
      ) ??
      _readString(member, 'peerId');
  final eventAt = trustedPrivateSystemEventAt(
    systemType,
    payload,
    fallback: fallbackEventAt,
  );
  if (targetPeerId == null || targetPeerId.isEmpty || eventAt == null) {
    return null;
  }
  return TrustedPrivateMemberSystemEvent(
    systemType: systemType,
    targetPeerId: targetPeerId,
    targetUsername:
        _readString(payload, 'targetUsername') ??
        _readString(member, 'username'),
    eventAt: eventAt,
  );
}

TrustedPrivateMessageDeleteSystemEvent? parseTrustedPrivateMessageDeleteEvent(
  Map<String, dynamic> payload, {
  DateTime? fallbackEventAt,
}) {
  final targetMessageId =
      _readString(payload, 'targetMessageId') ??
      _readString(payload, 'deletedMessageId') ??
      _readString(payload, 'messageId');
  final eventAt = trustedPrivateSystemEventAt(
    'group_message_deleted',
    payload,
    fallback: fallbackEventAt,
  );
  if (targetMessageId == null || targetMessageId.isEmpty || eventAt == null) {
    return null;
  }
  return TrustedPrivateMessageDeleteSystemEvent(
    targetMessageId: targetMessageId,
    eventAt: eventAt,
  );
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) {
      result[key] = entry.value;
    }
  }
  return result;
}

String? _readString(Map<String, dynamic>? value, String key) {
  final raw = value?[key];
  if (raw is! String) {
    return null;
  }
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _parseUtc(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}
