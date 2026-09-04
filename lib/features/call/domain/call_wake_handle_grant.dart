import 'dart:collection';

/// A call-only capability issued to one recipient device.
///
/// This object is deliberately separate from ordinary wake tokens. Its exact
/// canonical map is signed inside a v2-encrypted contact-request payload.
final class CallWakeHandleGrant {
  factory CallWakeHandleGrant({
    required String handle,
    required String recipientDevicePeerId,
    required int deviceKeyEpoch,
    required int generation,
    required int issuedAtMs,
    required int expiresAtMs,
  }) {
    _validate(
      handle: handle,
      recipientDevicePeerId: recipientDevicePeerId,
      deviceKeyEpoch: deviceKeyEpoch,
      generation: generation,
      issuedAtMs: issuedAtMs,
      expiresAtMs: expiresAtMs,
    );
    return CallWakeHandleGrant._(
      handle: handle,
      recipientDevicePeerId: recipientDevicePeerId,
      deviceKeyEpoch: deviceKeyEpoch,
      generation: generation,
      issuedAtMs: issuedAtMs,
      expiresAtMs: expiresAtMs,
    );
  }

  const CallWakeHandleGrant._({
    required this.handle,
    required this.recipientDevicePeerId,
    required this.deviceKeyEpoch,
    required this.generation,
    required this.issuedAtMs,
    required this.expiresAtMs,
  }) : version = currentVersion;

  factory CallWakeHandleGrant.fromCanonicalMap(Object? value) {
    try {
      if (value is! Map) throw const FormatException();
      final map = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String || map.containsKey(key)) {
          throw const FormatException();
        }
        map[key] = entry.value;
      }
      if (map.keys.toSet().difference(_canonicalKeys).isNotEmpty ||
          _canonicalKeys.difference(map.keys.toSet()).isNotEmpty ||
          map['version'] != currentVersion ||
          map['handle'] is! String ||
          map['recipientDevicePeerId'] is! String ||
          map['deviceKeyEpoch'] is! int ||
          map['generation'] is! int ||
          map['issuedAtMs'] is! int ||
          map['expiresAtMs'] is! int) {
        throw const FormatException();
      }
      return CallWakeHandleGrant(
        handle: map['handle']! as String,
        recipientDevicePeerId: map['recipientDevicePeerId']! as String,
        deviceKeyEpoch: map['deviceKeyEpoch']! as int,
        generation: map['generation']! as int,
        issuedAtMs: map['issuedAtMs']! as int,
        expiresAtMs: map['expiresAtMs']! as int,
      );
    } on FormatException {
      throw const FormatException('invalid call wake handle grant');
    } on ArgumentError {
      throw const FormatException('invalid call wake handle grant');
    }
  }

  static const int currentVersion = 1;
  static const int maxSafeInteger = 9007199254740991;

  final int version;
  final String handle;
  final String recipientDevicePeerId;
  final int deviceKeyEpoch;
  final int generation;
  final int issuedAtMs;
  final int expiresAtMs;

  /// Returns the exact signed wire representation with deterministic key order.
  Map<String, Object> toCanonicalMap() => Map<String, Object>.unmodifiable(
    SplayTreeMap<String, Object>.from(<String, Object>{
      'version': version,
      'handle': handle,
      'recipientDevicePeerId': recipientDevicePeerId,
      'deviceKeyEpoch': deviceKeyEpoch,
      'generation': generation,
      'issuedAtMs': issuedAtMs,
      'expiresAtMs': expiresAtMs,
    }),
  );

  /// The grant is valid on the half-open interval [issuedAtMs, expiresAtMs).
  bool isValidAt(int nowMs) => issuedAtMs <= nowMs && nowMs < expiresAtMs;

  /// Anti-rollback ordering is independent of wall-clock timestamps and of
  /// [deviceKeyEpoch], which is an equality witness derived from key material,
  /// not an ordered counter. Issuers persist and monotonically increment the
  /// dedicated generation across handle and device-key rotations.
  bool isStrictlyNewerThan(CallWakeHandleGrant prior) =>
      generation > prior.generation;

  static bool hasValidPeerIdGrammar(String value) =>
      value.isNotEmpty && value.length <= 255 && _peerIdPattern.hasMatch(value);

  static void _validate({
    required String handle,
    required String recipientDevicePeerId,
    required int deviceKeyEpoch,
    required int generation,
    required int issuedAtMs,
    required int expiresAtMs,
  }) {
    if (!_handlePattern.hasMatch(handle) ||
        !hasValidPeerIdGrammar(recipientDevicePeerId) ||
        !_isPositiveSafeInteger(deviceKeyEpoch) ||
        !_isPositiveSafeInteger(generation) ||
        !_isPositiveSafeInteger(issuedAtMs) ||
        !_isPositiveSafeInteger(expiresAtMs) ||
        expiresAtMs <= issuedAtMs) {
      throw ArgumentError('invalid call wake handle grant');
    }
  }

  static bool _isPositiveSafeInteger(int value) =>
      value > 0 && value <= maxSafeInteger;

  static const Set<String> _canonicalKeys = <String>{
    'version',
    'handle',
    'recipientDevicePeerId',
    'deviceKeyEpoch',
    'generation',
    'issuedAtMs',
    'expiresAtMs',
  };
  static final RegExp _handlePattern = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _peerIdPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,254}$',
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallWakeHandleGrant &&
          version == other.version &&
          handle == other.handle &&
          recipientDevicePeerId == other.recipientDevicePeerId &&
          deviceKeyEpoch == other.deviceKeyEpoch &&
          generation == other.generation &&
          issuedAtMs == other.issuedAtMs &&
          expiresAtMs == other.expiresAtMs;

  @override
  int get hashCode => Object.hash(
    version,
    handle,
    recipientDevicePeerId,
    deviceKeyEpoch,
    generation,
    issuedAtMs,
    expiresAtMs,
  );

  @override
  String toString() =>
      'CallWakeHandleGrant(version: $version, deviceKeyEpoch: '
      '$deviceKeyEpoch, generation: $generation)';
}
