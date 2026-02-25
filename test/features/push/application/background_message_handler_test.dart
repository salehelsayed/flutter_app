import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';

void main() {
  setUp(() {
    flowEventLoggingEnabled = false;
  });

  group('firebaseMessagingBackgroundHandler', () {
    test('completes without error for valid RemoteMessage', () async {
      const message = RemoteMessage(
        messageId: 'msg-123',
        data: {'type': 'inbox', 'peerId': '12D3KooW...'},
      );

      // Should not throw
      await firebaseMessagingBackgroundHandler(message);
    });

    test('handles RemoteMessage with null messageId', () async {
      const message = RemoteMessage(
        data: {'type': 'inbox'},
      );

      await firebaseMessagingBackgroundHandler(message);
    });

    test('handles RemoteMessage with empty data map', () async {
      const message = RemoteMessage(
        messageId: 'msg-456',
      );

      await firebaseMessagingBackgroundHandler(message);
    });
  });
}
