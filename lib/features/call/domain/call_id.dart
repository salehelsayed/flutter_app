/// A canonical RFC 4122 UUID-v4 used as the stable identity of one call.
final class CallId implements Comparable<CallId> {
  CallId._(this.value);

  static final RegExp _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  final String value;

  factory CallId.parse(String value) {
    if (!_uuidV4.hasMatch(value)) {
      throw FormatException('call id must be a canonical UUID-v4');
    }
    return CallId._(value);
  }

  static CallId? tryParse(String value) {
    if (!_uuidV4.hasMatch(value)) return null;
    return CallId._(value);
  }

  @override
  int compareTo(CallId other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is CallId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  /// Call IDs are intentionally absent from default diagnostics.
  @override
  String toString() => 'CallId(redacted)';
}
