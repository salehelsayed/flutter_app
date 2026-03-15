import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/publish_post_presence_update_use_case.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';

ContactModel _contact(
  String peerId,
  String username, {
  bool blocked = false,
  bool archived = false,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    isBlocked: blocked,
    isArchived: archived,
  );
}

void main() {
  test(
    'publishes active presence to direct friends with inbox fallback',
    () async {
      final network = FakeP2PNetwork();
      final aliceService = FakeP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      final caraService = FakeP2PService(peerId: 'peer-cara', network: network);
      caraService.setOnline(false);

      final contacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-bob', 'Bob'))
        ..addTestContact(_contact('peer-cara', 'Cara'))
        ..addTestContact(_contact('peer-blocked', 'Blocked', blocked: true))
        ..addTestContact(_contact('peer-archived', 'Archived', archived: true));

      final bobMessageFuture = bobService.messageStream.first;

      await publishPostPresenceUpdate(
        p2pService: aliceService,
        contactRepo: contacts,
        status: 'active',
        capturedAt: '2026-03-15T10:10:00.000Z',
        latE3: 52520,
        lngE3: 13405,
        accuracyM: 120,
        now: () => DateTime.parse('2026-03-15T10:10:00.000Z'),
      );

      final bobMessage = await bobMessageFuture;
      final bobEnvelope =
          jsonDecode(bobMessage.content) as Map<String, dynamic>;
      final bobPayload = bobEnvelope['payload'] as Map<String, dynamic>;
      expect(bobEnvelope['type'], 'post_presence_update');
      expect(bobPayload['status'], 'active');
      expect(bobPayload['lat_e3'], 52520);
      expect(bobPayload['lng_e3'], 13405);
      expect(bobPayload['accuracy_m'], 120);

      final caraInbox = network.retrieveInbox('peer-cara');
      expect(caraInbox, hasLength(1));
      final caraEnvelope =
          jsonDecode(caraInbox.single['message'] as String)
              as Map<String, dynamic>;
      final caraPayload = caraEnvelope['payload'] as Map<String, dynamic>;
      expect(caraPayload['status'], 'active');
      expect(network.inboxCount('peer-blocked'), 0);
      expect(network.inboxCount('peer-archived'), 0);
    },
  );

  test('publishes inactive reasons through the same fanout path', () async {
    final network = FakeP2PNetwork();
    final aliceService = FakeP2PService(peerId: 'peer-alice', network: network);
    final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
    final contacts = InMemoryContactRepository()
      ..addTestContact(_contact('peer-bob', 'Bob'));

    final bobMessageFuture = bobService.messageStream.first;

    await publishPostPresenceUpdate(
      p2pService: aliceService,
      contactRepo: contacts,
      status: 'inactive',
      capturedAt: '2026-03-15T10:12:00.000Z',
      reason: 'services_disabled',
      now: () => DateTime.parse('2026-03-15T10:12:00.000Z'),
    );

    final bobMessage = await bobMessageFuture;
    final envelope = jsonDecode(bobMessage.content) as Map<String, dynamic>;
    final payload = envelope['payload'] as Map<String, dynamic>;
    expect(payload['status'], 'inactive');
    expect(payload['reason'], 'services_disabled');
  });
}
