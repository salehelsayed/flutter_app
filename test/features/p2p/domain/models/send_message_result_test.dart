import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

void main() {
  group('SendMessageResult', () {
    group('acknowledged', () {
      test('true when explicit acked is true and reply is empty', () {
        const result = SendMessageResult(sent: true, acked: true, reply: '');
        expect(result.acknowledged, isTrue);
      });

      test('false when explicit acked is false even if reply is non-empty', () {
        const result = SendMessageResult(
          sent: true,
          acked: false,
          reply: 'legacy ack',
        );
        expect(result.acknowledged, isFalse);
      });

      test('true when sent is true and reply is non-empty', () {
        const result = SendMessageResult(sent: true, reply: 'ack');
        expect(result.acknowledged, isTrue);
      });

      test('false when sent is false', () {
        const result = SendMessageResult(sent: false, reply: 'ack');
        expect(result.acknowledged, isFalse);
      });

      test('false when reply is null', () {
        const result = SendMessageResult(sent: true, reply: null);
        expect(result.acknowledged, isFalse);
      });

      test('false when reply is empty string', () {
        const result = SendMessageResult(sent: true, reply: '');
        expect(result.acknowledged, isFalse);
      });
    });

    test('preserves additive transport field', () {
      const result = SendMessageResult(
        sent: true,
        acked: true,
        transport: 'relay',
      );
      expect(result.transport, 'relay');
    });
  });
}
