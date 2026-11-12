import 'call_id.dart';

/// Authenticated envelope metadata shared by the two strict wire parsers.
/// Event payloads and their version-specific vocabulary remain in each parser.
abstract interface class CallWireSignal {
  String get wireSchema;
  String get eventWireName;
  CallId get callId;
  String get messageId;
  String get senderAccountPeerId;
  String get senderDevicePeerId;
  String get recipientAccountPeerId;
  String get recipientDevicePeerId;
  int get senderSequence;
  int get iceGeneration;
  int get createdAtMs;
  int get expiresAtMs;
  Map<String, Object?> get payload;
  Map<String, Object?> toMap();
}
