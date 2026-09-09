import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../core/bridge/fake_bridge.dart';

/// F6-residue: `retryFailedMessages` must NOT conflate relay custody with
/// receiver delivery. On HEAD the two relay-custody outcomes flip a `'failed'`
/// row to terminal `'delivered'` and clear the wire envelope:
///   - `:269` store-success (RETRY_FAILED_MESSAGE_SUCCESS)
///   - `:246` already-inbox  (RETRY_FAILED_MESSAGE_ALREADY_INBOX)
/// Relay STORE success alone (no peer/receiver ack, no delivery receipt) is
/// custody, not delivery — the row must be `'inboxed'` (envelope retained) so
/// the custody sweep + DeliveryReceiptListener can flip it to `'delivered'` on
/// the receiver's confirmation. A false terminal `'delivered'` is uncorrectable
/// (`handle_delivery_receipt` idempotent-skips `'delivered'`).
IdentityModel _makeIdentity() => IdentityModel(
  peerId: 'my-peer-id',
  publicKey: 'my-pk',
  privateKey: 'my-sk',
  mnemonic12: 'a b c d e f g h i j k l',
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
);

const _safeV2Envelope =
    '{"type":"chat_message","version":"2","senderPeerId":"my-peer-id",'
    '"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}';

ConversationMessage _failedOutgoing({
  required String id,
  required String transport,
  required String wireEnvelope,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: 'peer-target',
    senderPeerId: 'my-peer-id',
    text: 'Hello',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    transport: transport,
    wireEnvelope: wireEnvelope,
  );
}

void main() {
  late FakeIdentityRepository identityRepo;
  late FakeMessageRepository messageRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;

  setUp(() {
    identityRepo = FakeIdentityRepository()..seed(_makeIdentity());
    messageRepo = FakeMessageRepository();
    contactRepo = FakeContactRepository();
    bridge = FakeBridge(
      initialResponses: {
        'message.encrypt': {
          'ok': true,
          'kem': 'fake-kem',
          'ciphertext': 'fake-ct',
          'nonce': 'fake-nonce',
        },
      },
    );
  });

  group('F6-residue: retryFailedMessages relay custody is inboxed, not delivered', () {
    test(
      'store-success of a direct row → inboxed (NOT delivered) and retains wire_envelope',
      () async {
        messageRepo.seed([
          _failedOutgoing(
            id: 'm1',
            transport: 'direct',
            wireEnvelope: _safeV2Envelope,
          ),
        ]);
        // storeInInbox returns true but performs NO peer ack / emits NO receipt.
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(retried, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        final row = await messageRepo.getMessage('m1');
        expect(row, isNotNull);
        // Relay store success is custody, not receiver delivery.
        expect(row!.status, 'inboxed');
        expect(row.transport, 'inbox');
        // Envelope retained so the custody sweep + receipt repair can run.
        expect(row.wireEnvelope, isNotNull);
        expect(row.wireEnvelope, isNotEmpty);
      },
    );

    test(
      'failed inbox-route row re-establishes custody and retains its envelope',
      () async {
        messageRepo.seed([
          _failedOutgoing(
            id: 'm2',
            transport: 'inbox',
            wireEnvelope: _safeV2Envelope,
          ),
        ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(retried, 1);
        // A failed row's route is not proof of relay custody.
        expect(p2pService.storeInInboxCallCount, 1);
        final row = await messageRepo.getMessage('m2');
        expect(row, isNotNull);
        expect(row!.status, 'inboxed');
        expect(row.wireEnvelope, _safeV2Envelope);
      },
    );
  });
}
