import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/push/application/issue_wake_tokens_use_case.dart';
import 'package:flutter_app/features/push/domain/wake_token_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'contact add block unblock delete re-add reconciles projection and relay authorization',
    () async {
      final rows = <String, Map<String, Object?>>{};
      final projection = DirectReactionNotificationProjection(
        store: _MemorySecureKeyStore(),
      );
      final wakeStore = _MemoryWakeTokenStore();
      final registrations = <List<String>>[];
      var minted = 0;
      final issuer = IssueWakeTokensUseCase(
        wakeTokenStore: wakeStore,
        registerWakeTokens: (tokens) async {
          registrations.add(List<String>.from(tokens));
          return true;
        },
        mintToken: () => 'reaction-wake-${minted++}',
      );

      Future<void> reconcile() => issuer.issueForContacts(
        rows.values
            .where((row) => (row['is_blocked'] as num?)?.toInt() != 1)
            .map((row) => row['peer_id'] as String)
            .toList(growable: false),
      );

      Future<void> lastReconcile = Future<void>.value();
      final repository = ContactRepositoryImpl(
        dbLoadAllContacts: () async => rows.values.toList(),
        dbLoadContact: (peerId) async => rows[peerId],
        dbUpsertContact: (row) async {
          rows[row['peer_id'] as String] = Map<String, Object?>.from(row);
        },
        dbDeleteContact: (peerId) async => rows.remove(peerId),
        dbGetContactCount: () async => rows.length,
        dbContactExists: (peerId) async => rows.containsKey(peerId),
        dbArchiveContact: (_) async {},
        dbUnarchiveContact: (_) async {},
        dbLoadActiveContacts: () async => rows.values.toList(),
        dbLoadArchivedContacts: () async => const <Map<String, Object?>>[],
        dbBlockContact: (peerId) async => rows[peerId]?['is_blocked'] = 1,
        dbUnblockContact: (peerId) async => rows[peerId]?['is_blocked'] = 0,
        dbDismissIntroBanner: (_) async {},
        dbSetIntrosSentAt: (_, _) async {},
        directReactionProjection: projection,
        onPushEligibilityChanged: () {
          lastReconcile = reconcile();
        },
      );
      final alice = ContactModel(
        peerId: 'peer-alice-256',
        publicKey: 'public-key',
        rendezvous: '/dns4/relay.example/tcp/443',
        username: 'Alice Local',
        signature: 'signature',
        scannedAt: '2026-07-12T10:00:00.000Z',
      );
      await projection.replaceLocalIdentity(accountPeerId: 'peer-local');

      await repository.addContact(alice);
      await lastReconcile;
      expect(registrations.last, ['reaction-wake-0']);
      expect(await projection.readContacts(), contains(alice.peerId));

      await repository.blockContact(alice.peerId);
      await lastReconcile;
      expect(registrations.last, isEmpty);
      expect(wakeStore.tokens, isEmpty);
      expect(
        (await projection.readContacts())[alice.peerId]?['blocked'],
        isTrue,
      );

      await repository.unblockContact(alice.peerId);
      await lastReconcile;
      expect(registrations.last, ['reaction-wake-1']);
      expect(
        (await projection.readContacts())[alice.peerId]?['blocked'],
        isFalse,
      );

      await repository.deleteContact(alice.peerId);
      await lastReconcile;
      expect(registrations.last, isEmpty);
      expect(await projection.readContacts(), isNot(contains(alice.peerId)));

      await repository.addContact(alice.copyWith(username: 'Alice Re-added'));
      await lastReconcile;
      expect(registrations.last, ['reaction-wake-2']);
      expect(
        (await projection.readContacts())[alice.peerId]?['username'],
        'Alice Re-added',
      );
    },
  );
}

class _MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _MemoryWakeTokenStore implements WakeTokenStore {
  Map<String, String> tokens = <String, String>{};

  @override
  Future<void> clear() async => tokens.clear();

  @override
  Future<Map<String, String>> readTokens() async =>
      Map<String, String>.from(tokens);

  @override
  Future<void> writeTokens(Map<String, String> next) async {
    tokens = Map<String, String>.from(next);
  }
}
