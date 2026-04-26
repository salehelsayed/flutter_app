import 'dart:convert';

bool isUnsafeLegacyOutboundEnvelope(String wireEnvelope) {
  try {
    final decoded = jsonDecode(wireEnvelope);
    if (decoded is! Map<String, dynamic>) {
      return false;
    }

    final type = decoded['type'];
    if (type != 'chat_message' && type != 'message_deletion') {
      return false;
    }

    final version = decoded['version'];
    return version == null || version == '1';
  } catch (_) {
    return false;
  }
}
