import 'dart:convert';

import 'package:background_push_crypto/background_push_crypto.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/debug/group_reaction_e2e_probe.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';

final class _MemoryKeyStore implements SecureKeyStore {
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

final class _SuccessfulCrypto extends BackgroundPushCrypto {
  const _SuccessfulCrypto();

  @override
  Future<Map<String, dynamic>> decryptGroup({
    required String groupKey,
    required String ciphertext,
    required String nonce,
  }) async => <String, dynamic>{'ok': true, 'errorCode': null};
}

void main() {
  late Database database;
  late _MemoryKeyStore keyStore;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(inMemoryDatabasePath);
    keyStore = _MemoryKeyStore();
    await database.execute(
      // `is_muted` mirrors production migration 050. The rest of the schema
      // stays deliberately partial so the canonical badge projection keeps
      // exercising its `available: false` branch.
      'CREATE TABLE groups ('
      'id TEXT PRIMARY KEY, name TEXT, type TEXT, my_role TEXT, '
      'is_muted INTEGER NOT NULL DEFAULT 0)',
    );
    await database.execute(
      'CREATE TABLE group_keys ('
      'group_id TEXT, key_generation INTEGER, encrypted_key TEXT)',
    );
    await database.execute(
      'CREATE TABLE group_messages ('
      'id TEXT PRIMARY KEY, group_id TEXT, text TEXT, is_incoming INTEGER, '
      'read_at TEXT, status TEXT)',
    );
    await database.execute(
      'CREATE TABLE message_reactions ('
      'id TEXT PRIMARY KEY, message_id TEXT, emoji TEXT)',
    );
    await database.execute(
      'CREATE TABLE group_reaction_replay_outbox ('
      'reaction_id TEXT PRIMARY KEY, group_id TEXT, message_id TEXT, '
      'action TEXT, inbox_retry_payload TEXT, delivery_status TEXT, '
      'created_at TEXT, last_error TEXT, updated_at TEXT)',
    );
  });

  tearDown(() => database.close());

  test('installed-app dispatcher recognizes only its two probe actions', () {
    expect(
      isGroupReactionE2EProbeAction(groupReactionE2EObserveAction),
      isTrue,
    );
    expect(
      isGroupReactionE2EProbeAction(groupReactionE2EExactAddRedriveAction),
      isTrue,
    );
    expect(
      isGroupReactionE2EProbeAction('connectivity_restore_observe'),
      isFalse,
    );
    expect(isGroupReactionE2EProbeAction(null), isFalse);
  });

  test('SQLCipher observer returns only redacted Plan 257 state', () async {
    keyStore.values['group-key-ref'] = 'raw-secret-group-key';
    await database.insert('groups', <String, Object?>{
      'id': 'raw-group-id',
      'name': 'Proof Group',
      'type': 'group',
      'my_role': 'member',
    });
    await database.insert('group_keys', <String, Object?>{
      'group_id': 'raw-group-id',
      'key_generation': 7,
      'encrypted_key': 'secure:group-key-ref',
    });
    await database.insert('group_messages', <String, Object?>{
      'id': 'raw-target-message-id',
      'group_id': 'raw-group-id',
      'text': 'SecretTargetMarker',
      'is_incoming': 0,
      'read_at': null,
      'status': 'sent',
    });
    await database.insert('message_reactions', <String, Object?>{
      'id': 'raw-reaction-state-id',
      'message_id': 'raw-target-message-id',
      'emoji': '👍',
    });

    final observation = await observeGroupReactionE2EState(
      database: database,
      secureKeyStore: keyStore,
      request: const GroupReactionE2EProbeRequest(
        scenario: 'android_group_reaction_notification',
        groupName: 'Proof Group',
        targetMarker: 'SecretTargetMarker',
      ),
    );

    expect(observation['schema'], 'mknoon.plan257.sqlcipher-observation.v1');
    expect(observation['groupRows'], 1);
    expect(observation['reactionRows'], 1);
    expect(observation['reactionMessageRows'], 0);
    expect(observation['reactionEmoji'], '👍');
    expect(observation['unreadCount'], 0);
    final encoded = jsonEncode(observation);
    expect(encoded, isNot(contains('raw-group-id')));
    expect(encoded, isNot(contains('raw-target-message-id')));
    expect(encoded, isNot(contains('raw-secret-group-key')));
    expect(encoded, isNot(contains('SecretTargetMarker')));
  });

  test(
    'installed-app action returns an exact nonce-bound observation',
    () async {
      await database.insert('groups', <String, Object?>{
        'id': 'raw-group-id',
        'name': 'TC257Group1',
        'type': 'chat',
        'my_role': 'member',
      });
      for (final marker in const <String>['TC257First1', 'TC257Second1']) {
        await database.insert('group_messages', <String, Object?>{
          'id': 'raw-$marker-id',
          'group_id': 'raw-group-id',
          'text': marker,
          'is_incoming': 1,
          'read_at': '2026-07-15T00:00:00.000Z',
          'status': 'received',
        });
      }

      final result = await runGroupReactionE2EProbeAction(
        database: database,
        secureKeyStore: keyStore,
        config: const <String, Object?>{
          'schema': groupReactionE2EProbeRequestSchema,
          'transport_action': groupReactionE2EObserveAction,
          'scenario': 'android_group_message_unread_lifecycle',
          'stepId':
              'plan257-group_reaction_sqlcipher_observe-runtime-contract-1',
          'runId': 'runtime-contract-1',
          'nonce': 'nonce-contract-1',
          'groupName': 'TC257Group1',
          'firstMarker': 'TC257First1',
          'secondMarker': 'TC257Second1',
          'targetMarker': '',
        },
      );

      expect(result, containsPair('schema', groupReactionE2EProbeResultSchema));
      expect(result, containsPair('runId', 'runtime-contract-1'));
      expect(result, containsPair('nonce', 'nonce-contract-1'));
      expect(result, containsPair('status', 'complete'));
      expect(result, containsPair('success', true));
      final observation = result['observation'] as Map<String, Object?>;
      expect(observation['scenario'], 'android_group_message_unread_lifecycle');
      expect(observation['groupRows'], 1);
      expect(observation['unreadCount'], 0);
      final encoded = jsonEncode(result);
      expect(encoded, isNot(contains('raw-group-id')));
      expect(encoded, isNot(contains('raw-TC257First1-id')));
    },
  );

  test(
    'combined iOS group journey returns the canonical collapse-request hash only',
    () async {
      await database.insert('groups', <String, Object?>{
        'id': 'raw-plan397-group-id',
        'name': 'Plan397Group',
        'type': 'group',
        'my_role': 'member',
      });
      await database.insert('group_messages', <String, Object?>{
        'id': 'raw-plan397-target-id',
        'group_id': 'raw-plan397-group-id',
        'text': 'Plan397Target',
        'is_incoming': 0,
        'read_at': null,
        'status': 'sent',
      });
      await database.insert('group_messages', <String, Object?>{
        'id': 'raw-plan397-message-id',
        'group_id': 'raw-plan397-group-id',
        'text': 'Plan397Message',
        'is_incoming': 1,
        'read_at': null,
        'status': 'received',
      });

      Map<String, Object?> request(String phase, String runId) =>
          <String, Object?>{
            'schema': groupReactionE2EProbeRequestSchema,
            'transport_action': groupReactionE2EObserveAction,
            'scenario': 'ios_chat_group_message_and_reaction_recipient',
            'runId': runId,
            'nonce': 'plan397-nonce-$phase',
            'stepId': 'plan257-$groupReactionE2EObserveAction-$runId',
            'phase': phase,
            'groupName': 'Plan397Group',
            'firstMarker': 'Plan397Message',
            'secondMarker': '',
            'targetMarker': 'Plan397Target',
          };

      final messageResult = await runGroupReactionE2EProbeAction(
        database: database,
        secureKeyStore: keyStore,
        config: request('message', 'plan397-message-phase'),
      );
      final messageObservation = Map<String, Object?>.from(
        messageResult['observation']! as Map,
      );
      expect(messageResult['phase'], 'message');
      expect(messageObservation['phase'], 'message');
      expect(messageObservation['reactionIdSha256'], isNull);
      final boundedCollapseIdentifier =
          'group-message:${sha256.convert(utf8.encode('raw-plan397-message-id')).toString().substring(0, 48)}';
      expect(
        messageObservation['expectedCollapseIdentifierSha256'],
        sha256.convert(utf8.encode(boundedCollapseIdentifier)).toString(),
        reason: 'TC-398-06 expected collapse',
      );
      expect(
        messageObservation.containsKey('expectedCollapseIdentifier'),
        isFalse,
      );
      expect(
        jsonEncode(messageObservation),
        isNot(contains(boundedCollapseIdentifier)),
      );
      expect(
        messageObservation['groupIdSha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      final messageMarkers = (messageObservation['markers']! as List)
          .cast<Map>()
          .map((value) => Map<String, Object?>.from(value))
          .toList(growable: false);
      expect(messageMarkers.map((value) => value['marker']).toSet(), <String>{
        'first',
        'target',
      });

      await database.insert('group_reaction_replay_outbox', <String, Object?>{
        'reaction_id': 'raw-plan397-reaction-id',
        'group_id': 'raw-plan397-group-id',
        'message_id': 'raw-plan397-target-id',
        'action': 'add',
        'inbox_retry_payload': 'opaque-and-untouched',
        'delivery_status': 'delivered',
        'created_at': '2026-08-22T20:00:00.000Z',
        'last_error': null,
        'updated_at': '2026-08-22T20:00:00.000Z',
      });
      await database.insert('message_reactions', <String, Object?>{
        'id': 'raw-plan397-reaction-state-id',
        'message_id': 'raw-plan397-target-id',
        'emoji': '👍',
      });
      final before = Map<String, Object?>.from(
        (await database.query('group_reaction_replay_outbox')).single,
      );

      final reactionResult = await runGroupReactionE2EProbeAction(
        database: database,
        secureKeyStore: keyStore,
        config: request('reaction', 'plan397-reaction-phase'),
      );
      final reactionObservation = Map<String, Object?>.from(
        reactionResult['observation']! as Map,
      );
      expect(reactionResult['phase'], 'reaction');
      expect(reactionObservation['phase'], 'reaction');
      expect(
        reactionObservation['reactionIdSha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        reactionObservation['groupIdSha256'],
        messageObservation['groupIdSha256'],
      );
      expect(
        (reactionObservation['markers']! as List),
        hasLength(messageMarkers.length),
      );
      final after = Map<String, Object?>.from(
        (await database.query('group_reaction_replay_outbox')).single,
      );
      expect(after, before);
      expect(
        jsonEncode(<Object?>[messageResult, reactionResult]),
        isNot(contains('raw-plan397-')),
      );
    },
  );

  test('installed-app action rejects cross-scenario marker shapes', () async {
    expect(
      () => runGroupReactionE2EProbeAction(
        database: database,
        secureKeyStore: keyStore,
        config: const <String, Object?>{
          'schema': groupReactionE2EProbeRequestSchema,
          'transport_action': groupReactionE2EExactAddRedriveAction,
          'scenario': 'android_group_message_unread_lifecycle',
          'stepId':
              'plan257-group_reaction_exact_add_redrive-runtime-contract-2',
          'runId': 'runtime-contract-2',
          'nonce': 'nonce-contract-2',
          'groupName': 'TC257Group2',
          'firstMarker': 'TC257First2',
          'secondMarker': 'TC257Second2',
          'targetMarker': '',
        },
      ),
      throwsA(isA<FormatException>()),
    );
  });

  // Plan 379 TC-379-04: the muted device lane's two ids must be allow-listed
  // (the probe's scenario allow-list is a registration surface) and must send
  // the REACTION marker shape — target only. The in-app marker gate keys off
  // the `_message_unread_lifecycle` suffix, which neither muted id carries.
  for (final scenario in const <String>[
    'android_group_muted_message_suppression',
    'android_group_muted_reaction_background_suppression',
  ]) {
    test('muted scenario $scenario is allow-listed for target-only '
        'markers', () async {
      await database.insert('groups', <String, Object?>{
        'id': 'raw-muted-group-id',
        'name': 'Plan379M-Fixture',
        'type': 'chat',
        'my_role': 'member',
        'is_muted': 1,
      });

      final result = await runGroupReactionE2EProbeAction(
        database: database,
        secureKeyStore: keyStore,
        config: <String, Object?>{
          'schema': groupReactionE2EProbeRequestSchema,
          'transport_action': groupReactionE2EObserveAction,
          'scenario': scenario,
          'stepId': 'plan257-$groupReactionE2EObserveAction-plan379-1',
          'runId': 'plan379-1',
          'nonce': 'nonce-plan379-1',
          'groupName': 'Plan379M-Fixture',
          'firstMarker': '',
          'secondMarker': '',
          'targetMarker': 'Plan379MutedMarker',
        },
      );

      expect(result, containsPair('success', true));
      final observation = result['observation']! as Map<String, Object?>;
      expect(observation['scenario'], scenario);
      expect(
        observation.containsKey('groupIsMuted'),
        isTrue,
        reason: 'the muted lane reads mute state from the probe observation',
      );
    });

    test('muted scenario $scenario rejects message-shaped markers', () async {
      expect(
        () => runGroupReactionE2EProbeAction(
          database: database,
          secureKeyStore: keyStore,
          config: <String, Object?>{
            'schema': groupReactionE2EProbeRequestSchema,
            'transport_action': groupReactionE2EObserveAction,
            'scenario': scenario,
            'stepId': 'plan257-$groupReactionE2EObserveAction-plan379-2',
            'runId': 'plan379-2',
            'nonce': 'nonce-plan379-2',
            'groupName': 'Plan379M-Fixture',
            'firstMarker': 'Plan379First',
            'secondMarker': 'Plan379Second',
            'targetMarker': '',
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });
  }

  test('an un-allow-listed scenario id is still rejected outright', () async {
    expect(
      () => runGroupReactionE2EProbeAction(
        database: database,
        secureKeyStore: keyStore,
        config: const <String, Object?>{
          'schema': groupReactionE2EProbeRequestSchema,
          'transport_action': groupReactionE2EObserveAction,
          'scenario': 'android_group_muted_not_registered',
          'stepId': 'plan257-group_reaction_sqlcipher_observe-plan379-3',
          'runId': 'plan379-3',
          'nonce': 'nonce-plan379-3',
          'groupName': 'Plan379M-Fixture',
          'firstMarker': '',
          'secondMarker': '',
          'targetMarker': 'Plan379MutedMarker',
        },
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Plan 257 runtime probe request rejected',
        ),
      ),
    );
  });

  test(
    'exact ADD redrive hashes evidence and mutates only retry status',
    () async {
      keyStore.values['group-key-ref'] = 'raw-secret-group-key';
      await database.insert('groups', <String, Object?>{
        'id': 'raw-group-id',
        'name': 'Proof Group',
        'type': 'group',
        'my_role': 'member',
      });
      await database.insert('group_keys', <String, Object?>{
        'group_id': 'raw-group-id',
        'key_generation': 7,
        'encrypted_key': 'secure:group-key-ref',
      });
      await database.insert('group_messages', <String, Object?>{
        'id': 'raw-target-message-id',
        'group_id': 'raw-group-id',
        'text': 'SecretTargetMarker',
        'is_incoming': 0,
        'read_at': null,
        'status': 'sent',
      });
      final envelope = <String, Object?>{
        'messageId': 'raw-reaction-state-id',
        'keyEpoch': 7,
        'ciphertext': 'raw-ciphertext',
        'nonce': 'raw-nonce',
        'signedPayload': 'raw-signed-payload',
        'signature': 'raw-signature',
        'notificationExtension': <String, Object?>{
          'transitionId': 'raw-transition-id',
          'targetMessageId': 'raw-target-message-id',
          'action': 'add',
          'signedPayload': 'raw-extension-payload',
          'signature': 'raw-extension-signature',
        },
      };
      final retryPayload = jsonEncode(<String, Object?>{
        'message': jsonEncode(envelope),
      });
      await database.insert('group_reaction_replay_outbox', <String, Object?>{
        'reaction_id': 'raw-transition-id',
        'group_id': 'raw-group-id',
        'message_id': 'raw-target-message-id',
        'action': 'add',
        'inbox_retry_payload': retryPayload,
        'delivery_status': 'delivered',
        'created_at': '2026-07-15T00:00:00.000Z',
        'last_error': null,
        'updated_at': '2026-07-15T00:00:00.000Z',
      });

      final observation = await prepareExactGroupReactionAddRedrive(
        database: database,
        secureKeyStore: keyStore,
        request: const GroupReactionE2EProbeRequest(
          scenario: 'android_group_reaction_notification',
          groupName: 'Proof Group',
          targetMarker: 'SecretTargetMarker',
        ),
        crypto: const _SuccessfulCrypto(),
      );

      expect(
        observation['schema'],
        'mknoon.plan257.duplicate-redrive-observation.v1',
      );
      expect(observation['prepared'], isTrue);
      expect(observation['notificationExtensionBound'], isTrue);
      expect(observation['storedEnvelopeDecryptOk'], isTrue);
      expect(observation['previousDeliveryStatus'], 'delivered');
      for (final key in const <String>[
        'transitionIdSha256',
        'transitionIdPrefixSha256',
        'reactionStateIdSha256',
        'targetMessageIdSha256',
        'inboxRetryPayloadSha256',
        'groupKeySha256',
      ]) {
        expect(observation[key], matches(RegExp(r'^[0-9a-f]{64}$')));
      }
      final encoded = jsonEncode(observation);
      for (final raw in const <String>[
        'raw-transition-id',
        'raw-target-message-id',
        'raw-reaction-state-id',
        'raw-secret-group-key',
        'raw-ciphertext',
        'raw-nonce',
        'raw-signature',
      ]) {
        expect(encoded, isNot(contains(raw)));
      }

      final stored = (await database.query(
        'group_reaction_replay_outbox',
      )).single;
      expect(stored['delivery_status'], 'failed');
      expect(stored['last_error'], 'plan257_exact_duplicate_redrive');
      expect(stored['inbox_retry_payload'], retryPayload);
    },
  );
}
