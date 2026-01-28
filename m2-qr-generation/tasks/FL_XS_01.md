# Task Prompt: FL_XS_01 - QRPayloadModel

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M2 – QR Code Generation

Canonical QR Payload Keys:
  - "pk": Base64-encoded public key
  - "ns": Namespace (same as peerID)
  - "rv": Rendezvous point multiaddr
  - "ts": ISO-8601 UTC timestamp
  - "sig": Base64-encoded Ed25519 signature

JSON Rules for QR Payload:
  1. Keys MUST be sorted alphabetically for canonical representation
  2. Alphabetical order: ns, pk, rv, sig, ts
  3. The unsigned payload (for signing) contains: ns, pk, rv, ts
  4. The signed payload (for QR code) contains all 5 fields
  5. Use dart:convert jsonEncode with SplayTreeMap for sorting
  6. All fields are strings - no nested objects
  7. No whitespace in JSON output (compact format)

QR Payload JSON Structure:
  {
    "ns": "12D3KooW...",
    "pk": "base64-string",
    "rv": "/dns4/mknoun.xyz/tcp/4001/wss/p2p/...",
    "sig": "base64-string",
    "ts": "2025-01-22T12:00:00.000Z"
  }
```

---

## Task Definition

```
[TASK FL_XS_01 – QRPayloadModel with JSON mapping]

Owner: Flutter

Goal:
  Create immutable QRPayloadModel class with JSON serialization.

What to implement:
  - class QRPayloadModel with fields:
      - String pk (public key, base64)
      - String ns (namespace, peerID)
      - String rv (rendezvous address)
      - String ts (timestamp, ISO-8601)
      - String sig (signature, base64)

  - factory QRPayloadModel.fromJson(Map<String, dynamic> json)
      - Parse JSON map into model instance
      - All fields are required strings

  - Map<String, dynamic> toJson()
      - Convert model to JSON map
      - Include all 5 fields

  - String toJsonString()
      - Convert to canonical JSON string
      - Keys MUST be sorted alphabetically
      - Uses SplayTreeMap for ordering
      - This is the string for the QR code

  - Static helper buildUnsignedPayload:
      static Map<String, dynamic> buildUnsignedPayload({
        required String pk,
        required String ns,
        required String rv,
        required String ts,
      })
      - Returns map with 4 fields (no sig)
      - Keys in alphabetical order: ns, pk, rv, ts

Inputs:
  - For fromJson: Map with keys "pk", "ns", "rv", "ts", "sig"
  - For buildUnsignedPayload: individual field values

Outputs:
  - QRPayloadModel instance
  - toJson() returns Map<String, dynamic>
  - toJsonString() returns canonical JSON string (for QR code)
  - buildUnsignedPayload() returns Map ready for signing

Flow_events:
  - None (pure data class)

Constraints:
  - Immutable (all fields final)
  - No business logic
  - No database logic
  - Keys in toJsonString must be sorted alphabetically
  - Must use SplayTreeMap from dart:collection

Deliverable:
  - File: lib/features/qr_code/domain/models/qr_payload_model.dart
```

---

## Output Requirements

1. **File:** `lib/features/qr_code/domain/models/qr_payload_model.dart`

2. **Must include:**
   - Immutable class with all 5 fields (pk, ns, rv, ts, sig)
   - fromJson factory constructor
   - toJson method
   - toJsonString method (canonical, sorted keys)
   - buildUnsignedPayload static helper
   - unsignedPayloadToJsonString static helper
   - Proper imports (dart:convert, dart:collection)
   - Documentation comments

3. **Implementation:**

```dart
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
    // Sort keys alphabetically for canonical representation
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
    // Return with keys in alphabetical order: ns, pk, rv, ts
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
```

---

## Usage Examples

```dart
// Creating a model from JSON
final json = {
  'pk': 'SGVsbG8gV29ybGQ=',
  'ns': '12D3KooWAbcdef...',
  'rv': '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g',
  'ts': '2025-01-22T12:00:00.000Z',
  'sig': 'U2lnbmF0dXJl...',
};
final model = QRPayloadModel.fromJson(json);

// Getting the QR string (canonical, sorted keys)
final qrString = model.toJsonString();
// Result: {"ns":"12D3KooWAbcdef...","pk":"SGVsbG8gV29ybGQ=","rv":"/dns4/...","sig":"U2lnbmF0dXJl...","ts":"2025-01-22T12:00:00.000Z"}

// Building unsigned payload for signing
final unsigned = QRPayloadModel.buildUnsignedPayload(
  pk: 'SGVsbG8gV29ybGQ=',
  ns: '12D3KooWAbcdef...',
  rv: '/dns4/mknoun.xyz/...',
  ts: DateTime.now().toUtc().toIso8601String(),
);
final dataToSign = QRPayloadModel.unsignedPayloadToJsonString(unsigned);
// Sign dataToSign, then create full model with signature
```

---

## Verification Steps

After implementation, verify the model compiles and passes static analysis:

1. **Flutter analyze verification:**
   ```bash
   flutter analyze lib/features/qr_code/domain/models/qr_payload_model.dart
   ```

   Expected output: No issues found.

2. **Verify canonical JSON output:**
   ```dart
   // Keys should be in order: ns, pk, rv, sig, ts
   final model = QRPayloadModel(
     pk: 'pk_value',
     ns: 'ns_value',
     rv: 'rv_value',
     ts: 'ts_value',
     sig: 'sig_value',
   );
   print(model.toJsonString());
   // Should print: {"ns":"ns_value","pk":"pk_value","rv":"rv_value","sig":"sig_value","ts":"ts_value"}
   ```

---

## Begin Implementation

Output the complete Dart file with the QRPayloadModel class.
