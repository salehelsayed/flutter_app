import 'package:flutter_app/features/conversation/application/outbound_envelope_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isUnsafeLegacyOutboundEnvelope', () {
    test('flags v1 and versionless 1:1 chat and deletion envelopes', () {
      expect(
        isUnsafeLegacyOutboundEnvelope(
          '{"type":"chat_message","version":"1","payload":{}}',
        ),
        isTrue,
      );
      expect(
        isUnsafeLegacyOutboundEnvelope('{"type":"chat_message","payload":{}}'),
        isTrue,
      );
      expect(
        isUnsafeLegacyOutboundEnvelope(
          '{"type":"message_deletion","version":"1","payload":{}}',
        ),
        isTrue,
      );
      expect(
        isUnsafeLegacyOutboundEnvelope(
          '{"type":"message_deletion","payload":{}}',
        ),
        isTrue,
      );
    });

    test('allows v2, unrelated, malformed, and non-object envelopes', () {
      expect(
        isUnsafeLegacyOutboundEnvelope(
          '{"type":"chat_message","version":"2","encrypted":{}}',
        ),
        isFalse,
      );
      expect(
        isUnsafeLegacyOutboundEnvelope(
          '{"type":"message_deletion","version":"2","encrypted":{}}',
        ),
        isFalse,
      );
      expect(
        isUnsafeLegacyOutboundEnvelope(
          '{"type":"contact_request","version":"1","payload":{}}',
        ),
        isFalse,
      );
      expect(isUnsafeLegacyOutboundEnvelope('{not json'), isFalse);
      expect(isUnsafeLegacyOutboundEnvelope('[]'), isFalse);
      expect(isUnsafeLegacyOutboundEnvelope(''), isFalse);
    });
  });
}
