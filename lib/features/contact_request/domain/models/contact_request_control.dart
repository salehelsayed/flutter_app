import 'dart:collection';

/// Signed operation marker carried as `cr` inside a v2 contact-request
/// payload (Task 12b).
///
/// Only a fresh, stored-authority-verified [ContactRequestControlKind.newRequest]
/// can earn one automatic [ContactRequestControlKind.repairReply]. A reply
/// never earns another reply. The marker is inside the Ed25519-signed
/// plaintext, so stripping or changing it breaks the signature; the unsigned
/// outer `intent` plays no part in that decision.
enum ContactRequestControlKind {
  newRequest('new_request'),
  repairReply('repair_reply');

  const ContactRequestControlKind(this.wireValue);

  final String wireValue;
}

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

const int _maxPeerIdLength = 128;

final class ContactRequestControl {
  const ContactRequestControl.newRequest({required this.id, required this.to})
    : kind = ContactRequestControlKind.newRequest,
      replyTo = null;

  const ContactRequestControl.repairReply({
    required this.id,
    required this.to,
    required String this.replyTo,
  }) : kind = ContactRequestControlKind.repairReply;

  static const int version = 1;

  final ContactRequestControlKind kind;

  /// Stable operation ID. On the wire the outer `msgId` must equal it.
  final String id;

  /// Recipient account peer ID.
  final String to;

  /// The signed request ID a [ContactRequestControlKind.repairReply] answers.
  final String? replyTo;

  bool get isNewRequest => kind == ContactRequestControlKind.newRequest;

  /// Deterministic nested form that is signed and reconstructed.
  SplayTreeMap<String, Object> toCanonicalMap() =>
      SplayTreeMap<String, Object>.from(<String, Object>{
        'v': version,
        'kind': kind.wireValue,
        'id': id,
        'to': to,
        'replyTo': ?replyTo,
      });

  /// Strictly parses a received `cr` value. Throws [FormatException] for a
  /// wrong type, an unknown version, kind or key, a malformed ID, or a reply
  /// without `replyTo`.
  static ContactRequestControl parse(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('cr must be an object');
    }
    const allowedKeys = <String>{'v', 'kind', 'id', 'to', 'replyTo'};
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) {
        throw const FormatException('cr has an unknown key');
      }
    }
    final v = raw['v'];
    if (v is! int || v != version) {
      throw const FormatException('cr version is unsupported');
    }
    final kindText = raw['kind'];
    final kind = ContactRequestControlKind.values
        .where((candidate) => candidate.wireValue == kindText)
        .firstOrNull;
    if (kind == null) {
      throw const FormatException('cr kind is unsupported');
    }
    final id = raw['id'];
    if (id is! String || !_uuidV4.hasMatch(id)) {
      throw const FormatException('cr id is malformed');
    }
    final to = raw['to'];
    if (to is! String || to.isEmpty || to.length > _maxPeerIdLength) {
      throw const FormatException('cr recipient is malformed');
    }
    final replyTo = raw['replyTo'];
    switch (kind) {
      case ContactRequestControlKind.newRequest:
        if (raw.containsKey('replyTo')) {
          throw const FormatException('cr request cannot carry replyTo');
        }
        return ContactRequestControl.newRequest(id: id, to: to);
      case ContactRequestControlKind.repairReply:
        if (replyTo is! String || !_uuidV4.hasMatch(replyTo)) {
          throw const FormatException('cr reply needs a valid replyTo');
        }
        return ContactRequestControl.repairReply(
          id: id,
          to: to,
          replyTo: replyTo,
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ContactRequestControl &&
      other.kind == kind &&
      other.id == id &&
      other.to == to &&
      other.replyTo == replyTo;

  @override
  int get hashCode => Object.hash(kind, id, to, replyTo);
}
