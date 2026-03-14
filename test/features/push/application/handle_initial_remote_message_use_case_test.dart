import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/push/application/handle_initial_remote_message_use_case.dart';

void main() {
  group('handleInitialRemoteMessage', () {
    test('forwards the initial remote message when present', () async {
      const message = RemoteMessage(
        messageId: 'msg-123',
        data: {'type': 'inbox'},
      );
      RemoteMessage? forwardedMessage;

      await handleInitialRemoteMessage(
        getInitialMessage: () async => message,
        onMessageOpened: (value) {
          forwardedMessage = value;
        },
      );

      expect(forwardedMessage, same(message));
    });

    test('does nothing when there is no initial remote message', () async {
      var called = false;

      await handleInitialRemoteMessage(
        getInitialMessage: () async => null,
        onMessageOpened: (_) {
          called = true;
        },
      );

      expect(called, isFalse);
    });
  });
}
