import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retrier.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const interestPeer = 'interest-recipient';
const interestJournalKey = 'contact_request_retry_journal_v1';
const approvedInterestHints = {
  'en': 'Still waiting. Ask them to scan your code again.',
  'de':
      'Noch nicht verbunden. Bitte dein Gegenüber, deinen Code erneut zu scannen.',
  'ar': 'لم يكتمل الاتصال بعد. يمكن للطرف الآخر مسح رمزك مجددًا.',
};

class InterestRetryFixture {
  InterestRetryFixture() {
    contacts.seed([contact]);
    identities.seed(identity);
    bridge.responses['payload.sign'] = {'ok': true, 'signature': 'signature'};
    bridge.responses['contactrequest.encrypt'] = {
      'ok': true,
      'ephemeralPublicKey': 'ephemeral-key',
      'ciphertext': 'ciphertext',
      'nonce': 'nonce',
    };
  }

  DateTime now = DateTime.utc(2026, 11, 13);
  late final ContactModel contact = ContactModel(
    peerId: interestPeer,
    publicKey: 'recipient-key',
    rendezvous: '/p2p-circuit/relay',
    username: 'Alice',
    signature: 'qr-signature',
    scannedAt: now.subtract(const Duration(days: 8)).toIso8601String(),
  );
  final identity = IdentityModel(
    peerId: 'sender-account',
    publicKey: 'sender-public',
    privateKey: 'sender-private',
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    mlKemPublicKey: 'sender-mlkem',
    mlKemSecretKey: 'sender-mlkem-secret',
    createdAt: '2026-11-12T00:00:00Z',
    updatedAt: '2026-11-12T00:00:00Z',
  );
  final contacts = FakeContactRepository();
  final identities = FakeIdentityRepository();
  FakeSecureKeyStore store = FakeSecureKeyStore();
  final bridge = FakeBridge();
  final transport = FakeP2PService(
    initialState: const NodeState(
      isStarted: true,
      peerId: 'sender-account',
      circuitAddresses: ['/p2p-circuit/relay'],
    ),
  )..storeInInboxResult = true;
  ContactRelationshipState? consent;

  Future<ContactRelationshipConsent?> readConsent(String peerId) async =>
      consent == null
      ? null
      : ContactRelationshipConsent(
          state: consent!,
          revision: 1,
          updatedAtMs: now.millisecondsSinceEpoch,
        );

  Future<int> retry({String? interest}) => withClock(
    Clock(() => now),
    () => retryIncompleteKeyExchanges(
      contactRepo: contacts,
      identityRepo: identities,
      p2pService: transport,
      bridge: bridge,
      secureKeyStore: store,
      readConsent: readConsent,
      interestPeerId: interest,
    ),
  );

  KeyExchangeRetrier retrier({Future<void> Function()? beforeRetry}) =>
      KeyExchangeRetrier(
        p2pService: transport,
        contactRepo: contacts,
        identityRepo: identities,
        bridge: bridge,
        secureKeyStore: store,
        readConsent: readConsent,
        beforeRetry: beforeRetry,
      );

  Map<String, dynamic> get wire =>
      jsonDecode(transport.lastStoreInInboxMessage!) as Map<String, dynamic>;

  Future<Map<String, dynamic>> entry() async =>
      ((jsonDecode((await store.read(interestJournalKey))!) as Map)['entries']
                  as List)
              .single
          as Map<String, dynamic>;

  void dispose() => transport.dispose();
}
