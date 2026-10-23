import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/fake_p2p_service_integration.dart';

void main() {
  test('post_retract reaches its own stream and never the unknown stream', () async {
    final service = FakeP2PService(peerId: 'self', network: FakeP2PNetwork());
    final router = IncomingMessageRouter(p2pService: service)..start();
    addTearDown(() {
      router.dispose();
      service.dispose();
    });
    final retracts = <ChatMessage>[];
    final unknown = <ChatMessage>[];
    router.postRetractStream.listen(retracts.add);
    router.unknownMessageStream.listen(unknown.add);

    final message = ChatMessage(
      from: 'peer-bob',
      to: 'self',
      content: jsonEncode(<String, Object?>{
        'type': 'post_retract',
        'version': '1',
        'event_id': 'evt-retract-1',
        'created_at': '2026-10-23T11:00:00.000Z',
        'payload': <String, Object?>{
          'post_id': 'post-1',
          'post_created_at': '2026-10-23T09:00:00.000Z',
        },
      }),
      timestamp: '2026-10-23T11:00:00.000Z',
      isIncoming: true,
    );
    service.injectIncomingMessage(message);
    await Future<void>.delayed(Duration.zero);

    expect(retracts.map((routed) => routed.content), [message.content]);
    expect(unknown, isEmpty);
  });
}
