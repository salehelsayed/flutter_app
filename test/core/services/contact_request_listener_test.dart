import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/contact_request_listener.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'fake_p2p_service.dart';

void main() {
  late FakeP2PService fakeP2PService;
  late IncomingMessageRouter router;
  late ContactRequestListener listener;

  ChatMessage makeContactRequestMessage({
    String from = 'peer-sender',
    String to = 'peer-me',
  }) {
    return ChatMessage(
      from: from,
      to: to,
      content: '{"type":"contact_request","version":"1","payload":{"ns":"$from","pk":"pk","rv":"/dns4/relay","un":"Alice","sig":"sig"}}',
      timestamp: '2026-01-01T00:00:00.000Z',
      isIncoming: true,
    );
  }

  setUp(() {
    fakeP2PService = FakeP2PService();
    router = IncomingMessageRouter(p2pService: fakeP2PService);
    router.start();
    listener = ContactRequestListener(router: router);
  });

  tearDown(() {
    listener.dispose();
    router.dispose();
    fakeP2PService.dispose();
  });

  group('ContactRequestListener', () {
    test('passes contact request messages to requests stream', () async {
      final msg = makeContactRequestMessage();

      final future = listener.requests.first.timeout(
        const Duration(seconds: 2),
      );

      fakeP2PService.emitMessage(msg);

      final received = await future;
      expect(received.from, 'peer-sender');
      expect(received.content, contains('contact_request'));
    });

    test('does not emit non-contact-request messages', () async {
      final chatMsg = ChatMessage(
        from: 'peer-a',
        to: 'peer-me',
        content: '{"type":"chat_message","version":"1","payload":{"text":"hello"}}',
        timestamp: '2026-01-01T00:00:00.000Z',
        isIncoming: true,
      );

      // Listen for any request events
      var gotRequest = false;
      final sub = listener.requests.listen((_) => gotRequest = true);

      fakeP2PService.emitMessage(chatMsg);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(gotRequest, isFalse);
      await sub.cancel();
    });

    test('handles multiple messages', () async {
      final msgs = <ChatMessage>[];
      final sub = listener.requests.listen(msgs.add);

      fakeP2PService.emitMessage(makeContactRequestMessage(from: 'peer-1'));
      fakeP2PService.emitMessage(makeContactRequestMessage(from: 'peer-2'));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(msgs.length, 2);
      expect(msgs[0].from, 'peer-1');
      expect(msgs[1].from, 'peer-2');
      await sub.cancel();
    });

    test('dispose closes request stream', () async {
      listener.dispose();

      // After dispose, the stream should be done
      final events = <ChatMessage>[];
      await listener.requests.listen(events.add).asFuture().catchError((_) {});
      expect(events, isEmpty);
    });

    test('ignores outgoing messages', () async {
      final outgoing = ChatMessage(
        from: 'peer-me',
        to: 'peer-other',
        content: '{"type":"contact_request","version":"1","payload":{}}',
        timestamp: '2026-01-01T00:00:00.000Z',
        isIncoming: false,
      );

      var gotRequest = false;
      final sub = listener.requests.listen((_) => gotRequest = true);

      fakeP2PService.emitMessage(outgoing);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(gotRequest, isFalse);
      await sub.cancel();
    });

    test('broadcast stream supports multiple listeners', () async {
      var count1 = 0;
      var count2 = 0;
      final sub1 = listener.requests.listen((_) => count1++);
      final sub2 = listener.requests.listen((_) => count2++);

      fakeP2PService.emitMessage(makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(count1, 1);
      expect(count2, 1);
      await sub1.cancel();
      await sub2.cancel();
    });
  });
}
