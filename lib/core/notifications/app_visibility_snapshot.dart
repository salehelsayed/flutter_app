import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Schema and timing bounds shared by the Dart, Swift, and Kotlin projections.
const int appVisibilitySnapshotSchemaVersion = 1;
const int appVisibilityFreshnessWindowMs = 90000;
const int appVisibilityHeartbeatIntervalMs = 60000;
const Duration appVisibilityFreshnessWindow = Duration(
  milliseconds: appVisibilityFreshnessWindowMs,
);
const Duration appVisibilityHeartbeatInterval = Duration(
  milliseconds: appVisibilityHeartbeatIntervalMs,
);
const int appVisibilityMaxSignedInt64 = 0x7fffffffffffffff;
const String appVisibilityDigestDomain = 'mknoon/app-visibility/v1';

final RegExp _lowercaseSha256 = RegExp(r'^[0-9a-f]{64}$');

enum AppVisibilityLifecycle {
  foregroundActive('FOREGROUND_ACTIVE'),
  inactive('INACTIVE'),
  background('BACKGROUND');

  const AppVisibilityLifecycle(this.wireValue);

  final String wireValue;

  static AppVisibilityLifecycle? tryParse(Object? value) {
    for (final lifecycle in values) {
      if (lifecycle.wireValue == value) return lifecycle;
    }
    return null;
  }
}

enum AppVisibilityConversationLane {
  direct('direct', 0x01),
  group('group', 0x02);

  const AppVisibilityConversationLane(this.wireValue, this.laneByte);

  final String wireValue;
  final int laneByte;

  static AppVisibilityConversationLane? tryParse(Object? value) {
    for (final lane in values) {
      if (lane.wireValue == value) return lane;
    }
    return null;
  }
}

/// Process-local route identity and its persistence-safe digest.
///
/// The normalized identifier is never sent to native storage. Platform calls
/// receive only [digest]. Keeping the lane in this value also prevents a direct
/// identifier from being confused with the reserved `group:` route grammar.
final class AppVisibilityConversationIdentity {
  AppVisibilityConversationIdentity._({
    required this.lane,
    required this.normalizedId,
    required Uint8List preimage,
  }) : preimage = List<int>.unmodifiable(preimage),
       digest = sha256.convert(preimage).toString();

  final AppVisibilityConversationLane lane;
  final String normalizedId;
  final List<int> preimage;
  final String digest;

  /// Compatibility spelling used by presentation owners.
  String get normalizedValue => normalizedId;

  static AppVisibilityConversationIdentity? tryParse({
    required AppVisibilityConversationLane lane,
    required String value,
  }) {
    final normalized = _normalizeConversationId(lane: lane, value: value);
    if (normalized == null) return null;
    final idBytes = _strictUtf8(normalized);
    if (idBytes == null || idBytes.length > 0xffffffff) return null;

    final domainBytes = utf8.encode(appVisibilityDigestDomain);
    final byteLength = idBytes.length;
    final preimage = Uint8List(domainBytes.length + 1 + 1 + 4 + byteLength);
    var offset = 0;
    preimage.setRange(offset, offset + domainBytes.length, domainBytes);
    offset += domainBytes.length;
    preimage[offset++] = 0;
    preimage[offset++] = lane.laneByte;
    preimage[offset++] = (byteLength >> 24) & 0xff;
    preimage[offset++] = (byteLength >> 16) & 0xff;
    preimage[offset++] = (byteLength >> 8) & 0xff;
    preimage[offset++] = byteLength & 0xff;
    preimage.setRange(offset, offset + byteLength, idBytes);
    return AppVisibilityConversationIdentity._(
      lane: lane,
      normalizedId: normalized,
      preimage: preimage,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppVisibilityConversationIdentity &&
      other.lane == lane &&
      other.normalizedId == normalizedId;

  @override
  int get hashCode => Object.hash(lane, normalizedId);
}

/// One complete v1 visibility record as persisted by the native owner.
final class AppVisibilitySnapshotV1 {
  const AppVisibilitySnapshotV1({
    required this.schemaVersion,
    required this.revision,
    required this.lifecycleGeneration,
    required this.lifecycle,
    required this.visibleConversationDigest,
    required this.updatedMonotonicMs,
    required this.bootSession,
  });

  final int schemaVersion;
  final int revision;
  final int lifecycleGeneration;
  final AppVisibilityLifecycle lifecycle;
  final String? visibleConversationDigest;
  final int updatedMonotonicMs;
  final String bootSession;

  bool get isValid =>
      schemaVersion == appVisibilitySnapshotSchemaVersion &&
      isPositiveAppVisibilityInt64(revision) &&
      isPositiveAppVisibilityInt64(lifecycleGeneration) &&
      isNonnegativeAppVisibilityInt64(updatedMonotonicMs) &&
      isCanonicalAppVisibilityBootSession(bootSession) &&
      (visibleConversationDigest == null ||
          isCanonicalAppVisibilityDigest(visibleConversationDigest));

  Map<String, Object?> toJson() {
    if (!isValid) {
      throw const FormatException('invalid app visibility snapshot v1');
    }
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'revision': revision,
      'lifecycleGeneration': lifecycleGeneration,
      'lifecycle': lifecycle.wireValue,
      'visibleConversationDigest': visibleConversationDigest,
      'updatedMonotonicMs': updatedMonotonicMs,
      'bootSession': bootSession,
    };
  }
}

/// Strict v1 JSON/platform codec. Unsupported or malformed state is never
/// coerced into an eligible record.
abstract final class AppVisibilitySnapshotCodec {
  static const Set<String> _keys = <String>{
    'schemaVersion',
    'revision',
    'lifecycleGeneration',
    'lifecycle',
    'visibleConversationDigest',
    'updatedMonotonicMs',
    'bootSession',
  };

  static AppVisibilitySnapshotV1? tryDecode(String encoded) {
    try {
      return tryDecodePlatform(jsonDecode(encoded));
    } on FormatException {
      return null;
    }
  }

  static AppVisibilitySnapshotV1? tryDecodePlatform(Object? value) {
    final map = _exactStringMap(value, _keys);
    if (map == null) return null;
    final lifecycle = AppVisibilityLifecycle.tryParse(map['lifecycle']);
    final digest = map['visibleConversationDigest'];
    if (map['schemaVersion'] is! int ||
        map['revision'] is! int ||
        map['lifecycleGeneration'] is! int ||
        map['updatedMonotonicMs'] is! int ||
        map['bootSession'] is! String ||
        lifecycle == null ||
        (digest != null && digest is! String)) {
      return null;
    }
    final snapshot = AppVisibilitySnapshotV1(
      schemaVersion: map['schemaVersion']! as int,
      revision: map['revision']! as int,
      lifecycleGeneration: map['lifecycleGeneration']! as int,
      lifecycle: lifecycle,
      visibleConversationDigest: digest as String?,
      updatedMonotonicMs: map['updatedMonotonicMs']! as int,
      bootSession: map['bootSession']! as String,
    );
    return snapshot.isValid ? snapshot : null;
  }

  static String encode(AppVisibilitySnapshotV1 snapshot) =>
      jsonEncode(snapshot.toJson());
}

/// Pure fail-notify predicate shared with the native conformance vectors.
bool maySuppressAppVisibilityNotification({
  required AppVisibilitySnapshotV1? snapshot,
  required int? currentMonotonicMs,
  required String? currentBootSession,
  required String? expectedConversationDigest,
}) {
  if (snapshot == null ||
      !snapshot.isValid ||
      !isNonnegativeAppVisibilityInt64(currentMonotonicMs) ||
      !isCanonicalAppVisibilityBootSession(currentBootSession) ||
      !isCanonicalAppVisibilityDigest(expectedConversationDigest) ||
      snapshot.lifecycle != AppVisibilityLifecycle.foregroundActive ||
      snapshot.bootSession != currentBootSession ||
      snapshot.visibleConversationDigest == null ||
      snapshot.visibleConversationDigest != expectedConversationDigest) {
    return false;
  }
  final ageMs = currentMonotonicMs! - snapshot.updatedMonotonicMs;
  return ageMs >= 0 && ageMs < appVisibilityFreshnessWindowMs;
}

/// Whether a native read is a current foreground generation on which Dart may
/// issue a route/heartbeat compare-and-set. A visible digest is not required.
bool isCurrentForegroundAppVisibilitySnapshot({
  required AppVisibilitySnapshotV1? snapshot,
  required int? currentMonotonicMs,
  required String? currentBootSession,
}) {
  if (snapshot == null ||
      !snapshot.isValid ||
      !isNonnegativeAppVisibilityInt64(currentMonotonicMs) ||
      !isCanonicalAppVisibilityBootSession(currentBootSession) ||
      snapshot.lifecycle != AppVisibilityLifecycle.foregroundActive ||
      snapshot.bootSession != currentBootSession) {
    return false;
  }
  final ageMs = currentMonotonicMs! - snapshot.updatedMonotonicMs;
  return ageMs >= 0 && ageMs < appVisibilityFreshnessWindowMs;
}

String? _normalizeConversationId({
  required AppVisibilityConversationLane lane,
  required String value,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || !_isSafeText(trimmed)) return null;
  if (lane == AppVisibilityConversationLane.direct) {
    return trimmed.startsWith('group:') ? null : trimmed;
  }

  const groupPrefix = 'group:';
  const messageMarker = '|message:';
  if (!trimmed.startsWith(groupPrefix)) return null;
  final markerIndex = trimmed.indexOf(messageMarker);
  final groupOwner = markerIndex < 0
      ? trimmed
      : trimmed.substring(0, markerIndex);
  final groupId = groupOwner.substring(groupPrefix.length);
  if (groupId.isEmpty ||
      groupId.trim() != groupId ||
      groupId.contains('|') ||
      groupId.contains(':') ||
      !_isSafeText(groupId)) {
    return null;
  }
  if (markerIndex >= 0) {
    if (trimmed.lastIndexOf(messageMarker) != markerIndex) return null;
    final messageId = trimmed.substring(markerIndex + messageMarker.length);
    if (messageId.isEmpty ||
        messageId.trim() != messageId ||
        messageId.contains('|') ||
        !_isSafeText(messageId)) {
      return null;
    }
  } else if (trimmed.contains('|')) {
    return null;
  }
  return '$groupPrefix$groupId';
}

List<int>? _strictUtf8(String value) {
  final codeUnits = value.codeUnits;
  for (var index = 0; index < codeUnits.length; index++) {
    final codeUnit = codeUnits[index];
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      if (++index >= codeUnits.length) return null;
      final trailing = codeUnits[index];
      if (trailing < 0xdc00 || trailing > 0xdfff) return null;
    } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      return null;
    }
  }
  try {
    return utf8.encode(value);
  } on FormatException {
    return null;
  }
}

bool _isSafeText(String value) {
  if (_strictUtf8(value) == null) return false;
  for (final rune in value.runes) {
    if (rune < 0x20 || (rune >= 0x7f && rune <= 0x9f)) return false;
  }
  return true;
}

bool isCanonicalAppVisibilityBootSession(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value != 'unavailable' &&
    value.trim() == value &&
    _isSafeText(value);

bool isCanonicalAppVisibilityDigest(Object? value) =>
    value is String && _lowercaseSha256.hasMatch(value);

bool isPositiveAppVisibilityInt64(Object? value) =>
    value is int && value > 0 && value <= appVisibilityMaxSignedInt64;

bool isNonnegativeAppVisibilityInt64(Object? value) =>
    value is int && value >= 0 && value <= appVisibilityMaxSignedInt64;

Map<String, Object?>? _exactStringMap(Object? value, Set<String> expectedKeys) {
  if (value is! Map || value.length != expectedKeys.length) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String || !expectedKeys.contains(entry.key)) return null;
    result[entry.key! as String] = entry.value;
  }
  return result.length == expectedKeys.length ? result : null;
}
