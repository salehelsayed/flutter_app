import 'dart:collection';
import 'dart:convert';

/// Model representing the QR code payload for identity sharing.
///
/// The payload contains:
/// - [pk]: Base64-encoded public key
/// - [ns]: Namespace (same as peerID)
/// - [rv]: Rendezvous point multiaddr
/// - [ts]: ISO-8601 timestamp of generation
/// - [sig]: Base64-encoded Ed25519 signature
class QRPayloadModel {
  /// Base64-encoded public key
  final String pk;

  /// Namespace identifier (same as peerID)
  final String ns;

  /// Rendezvous point address (multiaddr format)
  final String rv;

  /// ISO-8601 UTC timestamp of QR generation
  final String ts;

  /// Base64-encoded Ed25519 signature
  final String sig;

  const QRPayloadModel({
    required this.pk,
    required this.ns,
    required this.rv,
    required this.ts,
    required this.sig,
  });

  /// Creates a QRPayloadModel from a JSON map.
  factory QRPayloadModel.fromJson(Map<String, dynamic> json) {
    return QRPayloadModel(
      pk: json['pk'] as String,
      ns: json['ns'] as String,
      rv: json['rv'] as String,
      ts: json['ts'] as String,
      sig: json['sig'] as String,
    );
  }

  /// Converts the model to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'pk': pk,
      'ns': ns,
      'rv': rv,
      'ts': ts,
      'sig': sig,
    };
  }

  /// Converts to canonical JSON string with sorted keys.
  /// This is the string that should be encoded in the QR code.
  String toJsonString() {
    final sorted = SplayTreeMap<String, dynamic>.from(toJson());
    return jsonEncode(sorted);
  }

  /// Builds an unsigned payload map (without signature).
  /// Used for creating the data to be signed.
  ///
  /// Keys are sorted alphabetically to ensure canonical JSON.
  static Map<String, dynamic> buildUnsignedPayload({
    required String pk,
    required String ns,
    required String rv,
    required String ts,
  }) {
    return SplayTreeMap<String, dynamic>.from({
      'ns': ns,
      'pk': pk,
      'rv': rv,
      'ts': ts,
    });
  }

  /// Converts unsigned payload to canonical JSON string for signing.
  static String unsignedPayloadToJsonString(Map<String, dynamic> payload) {
    final sorted = SplayTreeMap<String, dynamic>.from(payload);
    return jsonEncode(sorted);
  }

  @override
  String toString() {
    return 'QRPayloadModel(pk: ${pk.substring(0, 10)}..., ns: ${ns.substring(0, 10)}..., rv: $rv, ts: $ts, sig: ${sig.substring(0, 10)}...)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QRPayloadModel &&
        other.pk == pk &&
        other.ns == ns &&
        other.rv == rv &&
        other.ts == ts &&
        other.sig == sig;
  }

  @override
  int get hashCode {
    return Object.hash(pk, ns, rv, ts, sig);
  }
}
