import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import '../../features/conversation/application/retry_failed_messages_use_case_test.dart'
    show makeIdentity, makeContact, makeFailedMessage;
import '../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../bridge/fake_bridge.dart';
import 'fake_p2p_service.dart';

void main() {
  test('BL-12 key arrival sends waiting message once without reconnect', () async {
    final keys = StreamController<void>.broadcast();
    final messages = FakeMessageRepository();
    final contacts = FakeContactRepository();
    final identity = FakeIdentityRepository()..seed(makeIdentity());
    final bridge = FakeBridge();
    final service = FakeP2PService(
      initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      discoverPeerResult: const DiscoveredPeer(
        id: 'peer-target', addresses: ['/ip4/127.0.0.1/tcp/4001'],
      ),
    );
    final pending = makeFailedMessage(id: 'waiting-for-key');
    messages.seed([pending]);
    contacts.seed([makeContact(mlKemPublicKey: null)]);
    final retrier = PendingMessageRetrier(
      p2pService: service, messageRepo: messages, identityRepo: identity,
      contactRepo: contacts, bridge: bridge, contactKeyUpdatedSignal: keys.stream,
      retryDebounce: const Duration(hours: 1),
      periodicRetryInterval: const Duration(hours: 1),
    );
    addTearDown(() async {
      retrier.dispose();
      service.dispose();
      await keys.close();
    });
    retrier.start();
    keys.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await messages.getMessage(pending.id))!.status, 'failed');
    expect(service.sendMessageWithReplyCallCount, 0);
    contacts.seed([makeContact()]);
    keys.add(null);
    keys.add(null);
    // No state edge or app resume. Bound the event-driven recovery to one second.
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while ((await messages.getMessage(pending.id))!.status == 'failed' &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final recovered = (await messages.getMessage(pending.id))!;
    expect(recovered.status, anyOf('sent', 'delivered', 'inboxed'));
    expect(recovered.id, pending.id);
    expect(recovered.text, pending.text);
    expect(recovered.timestamp, pending.timestamp);
    keys.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bridge.commandLog.where((c) => c == 'message.encrypt'), hasLength(1));
    expect(service.sendMessageWithReplyCallCount, 1);
  });
}
