import 'dart:convert';

import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'direct reaction projection covers contact and authored-target lifecycle',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = DirectReactionNotificationProjection(
        store: store,
        maxAuthoredTargets: 2,
      );
      await projection.replaceLocalIdentity(accountPeerId: 'peer-local');
      final alice = _contact(username: 'Alice');

      await projection.upsertContact(alice);
      expect(
        await projection.readContacts(),
        containsPair(alice.peerId, <String, Object?>{
          'username': 'Alice',
          'blocked': false,
          'archived': false,
          'authorizedTransportPeerIds': <String>[],
        }),
      );

      await projection.upsertContact(alice.copyWith(username: 'Alice Local'));
      await projection.setContactBlocked(
        peerId: alice.peerId,
        username: 'Alice Local',
        blocked: true,
      );
      expect((await projection.readContacts())[alice.peerId], <String, Object?>{
        'username': 'Alice Local',
        'blocked': true,
        'archived': false,
        'authorizedTransportPeerIds': <String>[],
      });

      await projection.upsertContact(
        alice.copyWith(username: 'Alice Local', isArchived: true),
      );
      expect((await projection.readContacts())[alice.peerId], <String, Object?>{
        'username': 'Alice Local',
        'blocked': false,
        'archived': true,
        'authorizedTransportPeerIds': <String>[],
      });

      await projection.setContactBlocked(
        peerId: alice.peerId,
        username: 'Alice Local',
        blocked: false,
        archived: true,
      );
      await projection.removeContact(alice.peerId);
      expect(await projection.readContacts(), isNot(contains(alice.peerId)));
      await projection.upsertContact(alice);

      await projection.upsertAuthoredTarget(
        _message(id: 'out-1', timestamp: '2026-07-12T10:00:00.000Z'),
      );
      await projection.upsertAuthoredTarget(
        _message(id: 'incoming', isIncoming: true),
      );
      expect(
        await projection.readAuthoredTargets(),
        contains(
          predicate<Map<String, String>>(
            (row) =>
                row['id'] == 'out-1' &&
                row['peerId'] == alice.peerId &&
                row['timestamp'] == '2026-07-12T10:00:00.000Z',
          ),
        ),
      );
      expect(
        await projection.readAuthoredTargets(),
        isNot(
          contains(
            predicate<Map<String, String>>((row) => row['id'] == 'incoming'),
          ),
        ),
      );

      await projection.upsertAuthoredTarget(
        _message(id: 'out-2', timestamp: '2026-07-12T11:00:00.000Z'),
      );
      await projection.upsertAuthoredTarget(
        _message(id: 'out-3', timestamp: '2026-07-12T12:00:00.000Z'),
      );
      expect(
        (await projection.readAuthoredTargets()).map((row) => row['id']),
        <String?>['out-3', 'out-2'],
      );

      await projection.removeAuthoredTarget('out-2');
      expect(
        (await projection.readAuthoredTargets()).map((row) => row['id']),
        <String?>['out-3'],
      );
      await projection.removeAuthoredTargetsForContact(alice.peerId);
      expect(await projection.readAuthoredTargets(), isEmpty);
    },
  );

  test(
    'launch backfill replaces stale state and failed writes are recoverable',
    () async {
      final store = _MemorySecureKeyStore()
        ..values[sharedDirectReactionContactsKey] = jsonEncode(
          <String, Object?>{
            'version': 1,
            'contacts': <String, Object?>{
              'stale-peer': <String, Object?>{
                'username': 'Stale',
                'blocked': false,
              },
            },
          },
        );
      final projection = DirectReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(accountPeerId: 'peer-local');
      store.failWrites = true;
      await projection.upsertContact(_contact(username: 'Ignored Write'));
      store.failWrites = false;

      final current = _contact(username: 'Current');
      await projection.replaceContacts(<ContactModel>[current]);
      await projection.replaceAuthoredTargets(<ConversationMessage>[
        _message(id: 'current-target'),
        _message(id: 'incoming-target', isIncoming: true),
      ]);

      expect(await projection.readContacts(), hasLength(1));
      expect(await projection.readContacts(), contains(current.peerId));
      expect(
        (await projection.readAuthoredTargets()).map((row) => row['id']),
        <String?>['current-target'],
      );
      expect(await projection.readLocalAccountPeerId(), 'peer-local');
    },
  );

  test(
    'account replacement clears both prior documents before new backfill',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = DirectReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(accountPeerId: 'peer-old');
      await projection.upsertContact(_contact(username: 'Old Alice'));
      await projection.upsertAuthoredTarget(_message(id: 'old-target'));

      expect(await projection.readContacts(), isNotEmpty);
      expect(await projection.readAuthoredTargets(), isNotEmpty);
      expect(await projection.readLocalAccountPeerId(), 'peer-old');
      await projection.replaceLocalIdentity(accountPeerId: 'peer-old');
      expect(await projection.readContacts(), isNotEmpty);
      expect(await projection.readAuthoredTargets(), isNotEmpty);

      await projection.replaceLocalIdentity(accountPeerId: 'peer-new');
      expect(await projection.readLocalAccountPeerId(), 'peer-new');
      expect(await projection.readContacts(), isEmpty);
      expect(await projection.readAuthoredTargets(), isEmpty);
      for (final key in <String>[
        sharedDirectReactionContactsKey,
        sharedDirectReactionAuthoredTargetsKey,
      ]) {
        final document = jsonDecode(store.values[key]!) as Map<String, dynamic>;
        expect(document['localAccountPeerId'], 'peer-new');
      }

      await projection.clearForLogout();
      expect(store.values, isNot(contains(sharedDirectReactionContactsKey)));
      expect(
        store.values,
        isNot(contains(sharedDirectReactionAuthoredTargetsKey)),
      );
    },
  );

  test('failed eligibility write invalidates prior direct documents', () async {
    final store = _MemorySecureKeyStore();
    final projection = DirectReactionNotificationProjection(store: store);
    await projection.replaceLocalIdentity(accountPeerId: 'peer-local');
    final contact = _contact(username: 'Eligible Alice');
    await projection.upsertContact(contact);
    await projection.upsertAuthoredTarget(_message(id: 'eligible-target'));

    store.failNextWriteKeys.add(sharedDirectReactionContactsKey);
    await projection.setContactBlocked(
      peerId: contact.peerId,
      username: contact.username,
      blocked: true,
    );

    expect(store.values, isNot(contains(sharedDirectReactionContactsKey)));
    expect(
      store.values,
      isNot(contains(sharedDirectReactionAuthoredTargetsKey)),
    );
    expect(await projection.readLocalAccountPeerId(), isNull);
  });

  test(
    'SIMS fixture mutation is exact-generation and never invalidates siblings',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = DirectReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(accountPeerId: 'peer-local');
      final existing = _contact(username: 'Existing');
      await projection.upsertContact(existing);
      await projection.upsertAuthoredTarget(_message(id: 'existing-target'));
      final digest = 'a' * 64;

      expect(
        await projection.insertSimsFixtureContactIfAbsent(
          peerId: 'peer-sims',
          username: 'Encrypted fixture title',
          fixtureDigest: digest,
        ),
        isTrue,
      );
      expect(
        await projection.insertSimsFixtureContactIfAbsent(
          peerId: 'peer-sims',
          username: 'Encrypted fixture title',
          fixtureDigest: digest,
        ),
        isFalse,
      );
      expect((await projection.readContacts())['peer-sims'], <String, Object?>{
        'username': 'Encrypted fixture title',
        'blocked': false,
        'archived': false,
        'authorizedTransportPeerIds': <String>[],
        'simsFixtureDigest': digest,
      });
      await projection.replaceContacts(<ContactModel>[
        existing,
        ContactModel(
          peerId: 'peer-sims',
          publicKey: 'mknoon-sims-projection-only',
          rendezvous: '/mknoon/sims/projection-only',
          username: 'Encrypted fixture title',
          signature: 'mknoon-sims-ios:$digest',
          scannedAt: '1970-01-01T00:00:00.000Z',
        ),
      ]);
      expect(
        (await projection.readContacts())['peer-sims']?['simsFixtureDigest'],
        digest,
        reason: 'launch-time backfill must preserve the exact fixture marker',
      );

      store.failNextWriteKeys.add(sharedDirectReactionContactsKey);
      await expectLater(
        projection.insertSimsFixtureContactIfAbsent(
          peerId: 'peer-write-failure',
          username: 'Failure fixture',
          fixtureDigest: 'b' * 64,
        ),
        throwsStateError,
      );
      expect(await projection.readContacts(), contains(existing.peerId));
      expect(
        (await projection.readAuthoredTargets()).map((row) => row['id']),
        contains('existing-target'),
      );

      await projection.upsertContact(
        ContactModel(
          peerId: 'peer-sims',
          publicKey: 'real-key',
          rendezvous: '/dns4/real.example/tcp/443',
          username: 'Real replacement',
          signature: 'real-signature',
          scannedAt: '2026-07-12T12:00:00.000Z',
        ),
      );
      expect(
        await projection.removeSimsFixtureContactIfExact(
          peerId: 'peer-sims',
          username: 'Encrypted fixture title',
          fixtureDigest: digest,
        ),
        isFalse,
      );
      expect(
        (await projection.readContacts())['peer-sims']?['username'],
        'Real replacement',
      );
    },
  );
}

ContactModel _contact({required String username}) => ContactModel(
  peerId: 'peer-alice',
  publicKey: 'public-key',
  rendezvous: '/dns4/relay.example/tcp/443',
  username: username,
  signature: 'signature',
  scannedAt: '2026-07-12T09:00:00.000Z',
);

ConversationMessage _message({
  required String id,
  String timestamp = '2026-07-12T10:00:00.000Z',
  bool isIncoming = false,
}) => ConversationMessage(
  id: id,
  contactPeerId: 'peer-alice',
  senderPeerId: isIncoming ? 'peer-alice' : 'peer-local',
  text: 'fixture',
  timestamp: timestamp,
  status: 'sent',
  isIncoming: isIncoming,
  createdAt: timestamp,
);

class _MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = <String, String>{};
  bool failWrites = false;
  final Set<String> failNextWriteKeys = <String>{};

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> delete(String key) async {
    if (failWrites) throw StateError('injected projection failure');
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites || failNextWriteKeys.remove(key)) {
      throw StateError('injected projection failure');
    }
    values[key] = value;
  }
}
