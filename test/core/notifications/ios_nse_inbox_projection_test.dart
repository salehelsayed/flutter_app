import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/group_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/ios_nse_inbox_projection.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../secure_storage/fake_secure_key_store.dart';

const _binding =
    'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _accountPeer = '12D3KooWAccountPeer';
const _transportPeer = '12D3KooWTransportPeer';
const _relayA = '/dns4/relay-a.example/tcp/4001/p2p/12D3KooWRelayA';
const _relayB = '/dns4/relay-b.example/udp/4002/p2p/12D3KooWRelayB';

String get _privateKey => base64Encode(List<int>.generate(64, (i) => i));

void main() {
  test(
    'TC-373-02 exact physical transport projection gates paired iOS capability',
    () async {
      final store = _OrderedSecureKeyStore();
      final projection = IosNseInboxTransportProjection(store: store);

      final first = await projection.publishAndReadBack(
        opaqueBinding: _binding,
        logicalAccountPeerId: _accountPeer,
        transportPeerId: _transportPeer,
        transportPrivateKeyBase64: _privateKey,
        relayMultiaddrs: const <String>[_relayB, _relayA, _relayB],
      );
      expect(first.relayMultiaddrs, <String>[_relayB, _relayA]);
      expect(first.transportPrivateKeyBase64, _privateKey);
      expect(first.projectionRevision, 1);
      expect(
        await projection.isBindingQualified(
          opaqueBinding: _binding,
          logicalAccountPeerId: _accountPeer,
          transportPeerId: _transportPeer,
          relayMultiaddrs: const <String>[_relayB, _relayA, _relayB],
        ),
        isTrue,
      );
      expect(
        await projection.isBindingQualified(
          opaqueBinding: _binding,
          logicalAccountPeerId: _accountPeer,
          transportPeerId: _transportPeer,
          relayMultiaddrs: const <String>[_relayA, _relayB],
        ),
        isFalse,
        reason: 'effective relay failover order is an authority fact',
      );

      final readiness = OpaqueWakePlatformConsumerReadiness(
        admissionEnabled: true,
        readIosConsumer: () => projection.isBindingQualified(
          opaqueBinding: _binding,
          logicalAccountPeerId: _accountPeer,
          transportPeerId: _transportPeer,
          relayMultiaddrs: const <String>[_relayB, _relayA],
        ),
      );
      expect(await readiness.isReadyFor('ios'), isTrue);
      expect(await readiness.isReadyFor('android'), isFalse);
      expect(await readiness.isReadyFor('unknown'), isFalse);
      expect(
        await OpaqueWakePlatformConsumerReadiness(
          admissionEnabled: false,
          readIosConsumer: () async => true,
        ).isReadyFor('ios'),
        isFalse,
      );

      // A changed effective relay generation retires/readbacks before write.
      store.events.clear();
      final second = await projection.publishAndReadBack(
        opaqueBinding: _binding,
        logicalAccountPeerId: _accountPeer,
        transportPeerId: _transportPeer,
        transportPrivateKeyBase64: _privateKey,
        relayMultiaddrs: const <String>[_relayA],
      );
      expect(second.projectionRevision, 2);
      expect(
        store.events.indexOf('delete:$sharedIosNseInboxTransportKey'),
        lessThan(store.events.indexOf('write:$sharedIosNseInboxTransportKey')),
      );

      // Native-incompatible bytes never qualify: exact 64-byte key, bounded
      // whitespace/control-free peers, and duplicate-free stored relays.
      await expectLater(
        projection.publishAndReadBack(
          opaqueBinding: _binding,
          logicalAccountPeerId: '$_accountPeer\u00a0',
          transportPeerId: _transportPeer,
          transportPrivateKeyBase64: _privateKey,
          relayMultiaddrs: const <String>[_relayA],
        ),
        throwsArgumentError,
      );
      await expectLater(
        projection.publishAndReadBack(
          opaqueBinding: _binding,
          logicalAccountPeerId: _accountPeer,
          transportPeerId: _transportPeer,
          transportPrivateKeyBase64: base64Encode(List<int>.filled(32, 1)),
          relayMultiaddrs: const <String>[_relayA],
        ),
        throwsFormatException,
      );
      final duplicatedWire = second.toJson();
      duplicatedWire['relayMultiaddrs'] = <String>[_relayA, _relayA];
      await store.write(
        sharedIosNseInboxTransportKey,
        jsonEncode(duplicatedWire),
      );
      expect(await projection.read(), isNull);
      expect(
        await projection.isBindingQualified(
          opaqueBinding: _binding,
          logicalAccountPeerId: _accountPeer,
          transportPeerId: _transportPeer,
        ),
        isFalse,
      );
    },
  );

  test(
    'TC-373-02c committed direct and group authority mutations retire before exact republish',
    () async {
      // Android/default-off construction has no projection callbacks and an
      // identity save remains zero-work/non-throwing.
      var defaultOffCommits = 0;
      final defaultOff = IdentityRepositoryImpl(
        dbLoadIdentityRow: () async => null,
        dbUpsertIdentityRow: (_) async => defaultOffCommits += 1,
        secureKeyStore: FakeSecureKeyStore(),
      );
      await defaultOff.saveIdentity(_identity);
      expect(defaultOffCommits, 1);

      // Save and uncached-load retire first and refresh exactly once from the
      // committed identity. A post-commit refresh failure leaves the physical
      // projection absent and does not pretend the mutation rolled back.
      final transportStore = FakeSecureKeyStore();
      final transportProjection = IosNseInboxTransportProjection(
        store: transportStore,
      );
      await _seedTransport(transportProjection);
      var committedSaves = 0;
      final failingSave = IdentityRepositoryImpl(
        dbLoadIdentityRow: () async => null,
        dbUpsertIdentityRow: (_) async => committedSaves += 1,
        secureKeyStore: FakeSecureKeyStore(),
        retireIosNseInboxTransport: transportProjection.retireAndReadBack,
        refreshIosNseInboxTransport: (_) async {
          throw StateError('post-commit refresh failed');
        },
      );
      await expectLater(failingSave.saveIdentity(_identity), throwsStateError);
      expect(committedSaves, 1);
      expect(await transportStore.read(sharedIosNseInboxTransportKey), isNull);

      final loadSecrets = FakeSecureKeyStore();
      await loadSecrets.write('identity_private_key', _identity.privateKey);
      await loadSecrets.write('identity_mnemonic12', _identity.mnemonic12);
      var loadRefreshes = 0;
      final loading = IdentityRepositoryImpl(
        dbLoadIdentityRow: () async => _identityRow,
        dbUpsertIdentityRow: (_) async {},
        secureKeyStore: loadSecrets,
        retireIosNseInboxTransport: transportProjection.retireAndReadBack,
        refreshIosNseInboxTransport: (identity) async {
          loadRefreshes += 1;
          expect(identity.peerId, _accountPeer);
          await _seedTransport(transportProjection);
        },
      );
      expect((await loading.loadIdentity())?.peerId, _accountPeer);
      expect(loadRefreshes, 1);
      expect(await transportProjection.read(), isNotNull);

      // Real direct repository ordering: orphan/changed authority retires,
      // SQL commits, committed trust reloads, then exact replacement occurs.
      final directOrder = <String>[];
      final directProjection = _DirectAuthorityProjection(directOrder);
      final directRepo = _contactRepository(
        projection: directProjection,
        onCommit: () => directOrder.add('sql'),
        loadAuthority: () async {
          directOrder.add('load-committed');
          return const <String>[_transportPeer];
        },
      );
      await directRepo.addContact(_contact);
      expect(directOrder, <String>[
        'retire',
        'sql',
        'display',
        'load-committed',
        'replace:$_transportPeer',
      ]);

      directOrder.clear();
      directProjection.failRetire = true;
      var forbiddenDirectCommit = 0;
      final blockedDirect = _contactRepository(
        projection: directProjection,
        onCommit: () => forbiddenDirectCommit += 1,
        loadAuthority: () async => const <String>[_transportPeer],
      );
      await expectLater(blockedDirect.addContact(_contact), throwsStateError);
      expect(forbiddenDirectCommit, 0);

      // A configured group projection without the committed-authority loader
      // is a composition error and must abort before SQL.
      final groupOrder = <String>[];
      final groupProjection = _GroupAuthorityProjection(groupOrder);
      var forbiddenGroupCommit = 0;
      await expectLater(
        runCommittedGroupSenderAuthorityHandoff<void>(
          groupId: 'group-1',
          projection: groupProjection,
          loadCommittedAuthority: null,
          commitMutation: () async => forbiddenGroupCommit += 1,
        ),
        throwsStateError,
      );
      expect(forbiddenGroupCommit, 0);
      expect(groupOrder, isEmpty);

      await runCommittedGroupSenderAuthorityHandoff<void>(
        groupId: 'group-1',
        projection: groupProjection,
        loadCommittedAuthority: (_) async {
          groupOrder.add('load-committed');
          return null;
        },
        commitMutation: () async => groupOrder.add('sql'),
      );
      expect(groupOrder, <String>[
        'retire',
        'sql',
        'load-committed',
        'replace',
      ]);

      // Account-migration/binding and linked-role writes share the same hard
      // pre-retire failure rule: no mutation is attempted after failed delete.
      final failingStore = _FailingDeleteSecureKeyStore();
      await failingStore.write(sharedIosNseInboxTransportKey, 'stale');
      final failingProjection = IosNseInboxTransportProjection(
        store: failingStore,
      );
      var bindingMutations = 0;
      await expectLater(
        runWithRetiredIosNseTransportAuthority<void>(
          projection: failingProjection,
          mutateAuthority: () async => bindingMutations += 1,
        ),
        throwsStateError,
      );
      expect(bindingMutations, 0);

      final linkedStore = FakeSecureKeyStore();
      final linkedAuthority = LinkedInstallationAuthority(
        secureKeyStore: linkedStore,
        retireIosNseInboxTransport: () async {
          throw StateError('shared Keychain unavailable');
        },
      );
      await expectLater(
        linkedAuthority.markExpectedLinkedRole(),
        throwsStateError,
      );
      expect(await linkedStore.read(linkedInstallationRoleStorageKey), isNull);
    },
  );

  test(
    'TC-373-07 one default-off projection and native adapter own fixed wakes',
    () async {
      var forbiddenDefaultOffRead = 0;
      final defaultOff = OpaqueWakePlatformConsumerReadiness(
        admissionEnabled: false,
        readIosConsumer: () async {
          forbiddenDefaultOffRead += 1;
          return true;
        },
      );
      expect(await defaultOff.isReadyFor('ios'), isFalse);
      expect(forbiddenDefaultOffRead, 0);

      final fixture =
          jsonDecode(
                File(
                  'test/shared/fixtures/ios_nse_mailbox_v1.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(fixture.keys.toSet(), <String>{
        'schemaVersion',
        'cryptoMaterial',
        'transportProjection',
        'directContactsProjection',
        'directAuthoredTargetsProjection',
        'groupContextsProjection',
        'groupAuthoredTargetsProjection',
        'groupLatestStatesProjection',
        'relayOrder',
        'rows',
      });
      expect(fixture['schemaVersion'], 1);
      final transport = IosNseInboxTransportSnapshot.tryParse(
        jsonEncode(fixture['transportProjection']),
      );
      expect(transport, isNotNull);
      expect(transport!.relayMultiaddrs, fixture['relayOrder']);
      expect(base64Decode(transport.transportPrivateKeyBase64), hasLength(64));

      final cryptoMaterial = fixture['cryptoMaterial']! as Map<String, dynamic>;
      expect(cryptoMaterial.keys.toSet(), <String>{
        'identity_ml_kem_secret_key',
        'group_key:group-chat:7',
        'group_key:group-muted:7',
      });
      expect(
        base64Decode(cryptoMaterial['identity_ml_kem_secret_key']! as String),
        hasLength(2400),
      );
      for (final key in const <String>[
        'group_key:group-chat:7',
        'group_key:group-muted:7',
      ]) {
        expect(base64Decode(cryptoMaterial[key]! as String), hasLength(32));
      }

      final directContacts =
          fixture['directContactsProjection']! as Map<String, dynamic>;
      final directAuthoredTargets =
          fixture['directAuthoredTargetsProjection']! as Map<String, dynamic>;
      expect(directAuthoredTargets.keys.toSet(), <String>{
        'version',
        'localAccountPeerId',
        'targets',
      });
      expect(directAuthoredTargets['version'], 1);
      expect(
        directAuthoredTargets['localAccountPeerId'],
        transport.logicalAccountPeerId,
      );
      expect(
        directAuthoredTargets['localAccountPeerId'],
        directContacts['localAccountPeerId'],
      );
      final directTargets = <String, Map<String, dynamic>>{};
      final directTargetRows =
          (directAuthoredTargets['targets']! as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(directTargetRows.length, lessThanOrEqualTo(256));
      for (final target in directTargetRows) {
        expect(target.keys.toSet(), <String>{'id', 'peerId', 'timestamp'});
        expect(directTargets, isNot(contains(target['id'])));
        expect(isNativeCompatibleIosNsePeerId(target['peerId']), isTrue);
        expect(DateTime.parse(target['timestamp']! as String).isUtc, isTrue);
        directTargets[target['id']! as String] = target;
      }
      expect(directTargets.keys, <String>{
        'direct-target',
        'direct-target-legacy',
      });

      final groupContexts =
          fixture['groupContextsProjection']! as Map<String, dynamic>;
      final groupAuthoredTargets =
          fixture['groupAuthoredTargetsProjection']! as Map<String, dynamic>;
      final groupLatestStates =
          fixture['groupLatestStatesProjection']! as Map<String, dynamic>;
      for (final projection in <Map<String, dynamic>>[
        groupAuthoredTargets,
        groupLatestStates,
      ]) {
        expect(projection['version'], 1);
        expect(
          projection['localAccountPeerId'],
          transport.logicalAccountPeerId,
        );
        expect(
          projection['localAccountPeerId'],
          groupContexts['localAccountPeerId'],
        );
      }
      expect(groupAuthoredTargets.keys.toSet(), <String>{
        'version',
        'localAccountPeerId',
        'targets',
      });
      expect(groupLatestStates.keys.toSet(), <String>{
        'version',
        'localAccountPeerId',
        'states',
      });
      final groupTargets = <String, Map<String, dynamic>>{};
      final groupTargetRows =
          (groupAuthoredTargets['targets']! as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(groupTargetRows.length, lessThanOrEqualTo(256));
      for (final target in groupTargetRows) {
        expect(target.keys.toSet(), <String>{
          'id',
          'groupId',
          'keyEpoch',
          'timestamp',
        });
        expect(groupTargets, isNot(contains(target['id'])));
        expect(target['groupId'], 'group-chat');
        expect(target['keyEpoch'], 7);
        expect(DateTime.parse(target['timestamp']! as String).isUtc, isTrue);
        groupTargets[target['id']! as String] = target;
      }
      expect(groupTargets.keys, <String>{
        'group-target-message',
        'group-target-message-remove',
      });
      final groupStates = <String, Map<String, dynamic>>{};
      final groupStateRows = (groupLatestStates['states']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(groupStateRows.length, lessThanOrEqualTo(1024));
      for (final state in groupStateRows) {
        expect(state.keys.toSet(), <String>{
          'groupId',
          'targetMessageId',
          'reactorPeerId',
          'timestamp',
          if (state['removedAt'] != null) 'removedAt',
        });
        final targetId = state['targetMessageId']! as String;
        final target = groupTargets[targetId];
        expect(target, isNotNull);
        expect(state['groupId'], target!['groupId']);
        expect(isNativeCompatibleIosNsePeerId(state['reactorPeerId']), isTrue);
        final timestamp = DateTime.parse(state['timestamp']! as String);
        expect(timestamp.isUtc, isTrue);
        expect(
          timestamp.isBefore(DateTime.parse(target['timestamp']! as String)),
          isFalse,
        );
        if (state['removedAt'] != null) {
          final removedAt = DateTime.parse(state['removedAt']! as String);
          expect(removedAt.isUtc, isTrue);
          expect(removedAt.isBefore(timestamp), isFalse);
        }
        final stateKey = '$targetId\u0000${state['reactorPeerId']}';
        expect(groupStates, isNot(contains(stateKey)));
        groupStates[stateKey] = state;
      }
      expect(groupStates, hasLength(2));

      final rows = (fixture['rows']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(rows, hasLength(31));
      expect(rows.map((row) => row['id']).toSet(), hasLength(31));
      expect(
        rows.where((row) => row['classification'] == 'accepted'),
        hasLength(14),
      );
      expect(
        rows.where((row) => row['classification'] == 'rejected'),
        hasLength(6),
      );
      expect(
        rows.where((row) => row['classification'] == 'invalid'),
        hasLength(11),
      );
      for (final row in rows) {
        final classification = row['classification'];
        expect(row.keys.toSet(), <String>{
          'id',
          'classification',
          'kind',
          'rawEnvelope',
          if (classification == 'accepted') 'expected',
        });
        final page = row['rawEnvelope']! as Map<String, dynamic>;
        final messages = (page['messages']! as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(messages, hasLength(1));
        expect(messages.single['timestamp'], isA<int>());
        expect(messages.single['timestamp']! as int, isNonNegative);
      }
      for (final row in rows.where(
        (row) => row['classification'] == 'accepted',
      )) {
        final page = row['rawEnvelope']! as Map<String, dynamic>;
        expect(page.keys.toSet(), <String>{
          'ok',
          'messages',
          'hasMore',
          'custodyContract',
        });
        expect(page['ok'], isTrue);
        expect(page['hasMore'], isFalse);
        expect(page['custodyContract'], 'ack_or_expiry_v1');
        expect(page['messages'], hasLength(1));

        final retrieved =
            (page['messages']! as List<dynamic>).single as Map<String, dynamic>;
        final envelope =
            jsonDecode(retrieved['message']! as String) as Map<String, dynamic>;
        final expected = row['expected']! as Map<String, dynamic>;
        final producerKind = NotificationCompletedOutcomeProducerKind.tryParse(
          expected['producerKind']! as String,
        );
        expect(producerKind, isNotNull, reason: row['id']! as String);
        final isGroup = switch (producerKind!) {
          NotificationCompletedOutcomeProducerKind.groupMessage ||
          NotificationCompletedOutcomeProducerKind.groupReaction => true,
          _ => false,
        };
        final eventKey = switch (producerKind) {
          NotificationCompletedOutcomeProducerKind.directMessage =>
            envelope['id'],
          NotificationCompletedOutcomeProducerKind.directReaction =>
            envelope['eventId'],
          NotificationCompletedOutcomeProducerKind.groupMessage ||
          NotificationCompletedOutcomeProducerKind.groupReaction =>
            envelope['contentEventId'],
        };
        expect(eventKey, isA<String>(), reason: row['id']! as String);
        expect(expected['recoveryEventId'], eventKey);
        expect(
          expected['eventCorrelation'],
          tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: transport.transportPeerId,
            producerKind: producerKind,
            eventKey: eventKey! as String,
          ),
          reason: row['id']! as String,
        );
        final conversationKey = expected['conversationKey']! as String;
        final conversationIdentity = AppVisibilityConversationIdentity.tryParse(
          lane: isGroup
              ? AppVisibilityConversationLane.group
              : AppVisibilityConversationLane.direct,
          value: conversationKey,
        );
        expect(conversationIdentity, isNotNull, reason: row['id']! as String);
        expect(expected['conversationDigest'], conversationIdentity!.digest);
        expect(
          expected['stableNotificationId'],
          deterministicConversationNotificationId(conversationKey),
        );
        expect(expected['stableNotificationId'], greaterThan(0));
        expect(expected['contentKind'], switch (producerKind) {
          NotificationCompletedOutcomeProducerKind.directMessage ||
          NotificationCompletedOutcomeProducerKind.groupMessage => 'message',
          NotificationCompletedOutcomeProducerKind.directReaction ||
          NotificationCompletedOutcomeProducerKind.groupReaction => 'reaction',
        });
        expect(expected['policy'], anyOf('eligible', 'suppressedPolicy'));

        final expectedKeys = <String>{
          'eventCorrelation',
          'conversationDigest',
          'conversationKey',
          'stableNotificationId',
          'recoveryEventId',
          'producerKind',
          'contentKind',
          'policy',
          if (producerKind ==
              NotificationCompletedOutcomeProducerKind.groupMessage)
            'logicalDeliveryId',
          if (row['id'] == 'accepted-group-message-voice-descriptor')
            'previewBody',
        };
        expect(expected.keys.toSet(), expectedKeys);
        if (producerKind ==
            NotificationCompletedOutcomeProducerKind.groupMessage) {
          expect(expected['logicalDeliveryId'], eventKey);
        }

        if (isGroup) {
          expect(base64Decode(envelope['nonce']! as String), hasLength(12));
          expect(
            base64Encode(base64Decode(envelope['ciphertext']! as String)),
            envelope['ciphertext'],
          );
        } else {
          final encrypted = envelope['encrypted']! as Map<String, dynamic>;
          expect(base64Decode(encrypted['kem']! as String), hasLength(1088));
          expect(base64Decode(encrypted['nonce']! as String), hasLength(12));
          expect(
            base64Encode(base64Decode(encrypted['ciphertext']! as String)),
            encrypted['ciphertext'],
          );
        }

        if (producerKind ==
            NotificationCompletedOutcomeProducerKind.directReaction) {
          final targetId = envelope['targetMessageId']! as String;
          final projectedTarget = directTargets[targetId];
          expect(projectedTarget, isNotNull, reason: row['id']! as String);
          final senderTransport = envelope['senderPeerId']! as String;
          final projectedContact =
              (directContacts['contacts']!
                      as Map<String, dynamic>)[projectedTarget!['peerId']]
                  as Map<String, dynamic>?;
          expect(projectedContact, isNotNull, reason: row['id']! as String);
          expect(
            projectedContact!['authorizedTransportPeerIds'],
            contains(senderTransport),
            reason: row['id']! as String,
          );
        }

        if (producerKind ==
            NotificationCompletedOutcomeProducerKind.groupReaction) {
          final extension =
              envelope['notificationExtension']! as Map<String, dynamic>;
          final targetId = extension['targetMessageId']! as String;
          final reactorPeerId = extension['reactorPeerId']! as String;
          expect(
            reactorPeerId,
            '12D3KooWQxi1FKxPHbvCYRauKZqYA26ztjvwDMsWMxE9ZNFNsKV4',
            reason: row['id']! as String,
          );
          final projectedTarget = groupTargets[targetId];
          expect(projectedTarget, isNotNull, reason: row['id']! as String);
          expect(projectedTarget!['groupId'], envelope['groupId']);
          final state = groupStates['$targetId\u0000$reactorPeerId'];
          expect(state, isNotNull, reason: row['id']! as String);
          final action = extension['action']! as String;
          final transitionId = buildGroupReactionTransitionId(
            groupId: envelope['groupId']! as String,
            messageId: targetId,
            logicalActorPeerId: reactorPeerId,
            action: action,
            emoji: '👍',
            timestamp: DateTime.parse(state!['timestamp']! as String),
          );
          final stateId = deterministicGroupReactionStateId(
            groupId: envelope['groupId']! as String,
            messageId: targetId,
            logicalActorPeerId: reactorPeerId,
          );
          expect(extension['transitionId'], transitionId);
          expect(envelope['messageId'], transitionId);
          expect(envelope['contentEventId'], transitionId);
          expect(expected['recoveryEventId'], transitionId);
          expect(
            transitionId.split(':')[1],
            stateId.substring('group-reaction-state-'.length),
          );
          if (extension['action'] == 'add') {
            expect(state, isNot(contains('removedAt')));
          } else {
            expect(extension['action'], 'remove');
            expect(state['removedAt'], isNotNull);
          }
        }

        if (row['id'] == 'accepted-group-message-voice-descriptor') {
          expect(row['kind'], 'group_voice_descriptor');
          expect(expected['previewBody'], 'Group Sender: Voice message');
          final manifest = envelope['mediaManifest']! as String;
          expect(
            sha256.convert(utf8.encode(manifest)).toString(),
            envelope['mediaManifestHash'],
          );
          final decodedManifest = jsonDecode(manifest) as Map<String, dynamic>;
          expect(decodedManifest.keys.toSet(), <String>{
            'schema',
            'groupId',
            'messageId',
            'custodyKind',
            'custodyContract',
            'recipientPeerIds',
            'attachments',
          });
          final attachment =
              (decodedManifest['attachments']! as List<dynamic>).single
                  as Map<String, dynamic>;
          expect(attachment['mediaType'], 'audio');
          expect(attachment['mime'], 'audio/ogg');
          expect(attachment, isNot(contains('blob')));
          final incumbentManifest = ProtectedGroupMediaManifest.decode(
            manifest,
          );
          expect(incumbentManifest.encode(), manifest);
          expect(incumbentManifest.attachments.single.mediaType, 'audio');
        }
      }

      final production = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      expect(
        production,
        contains(
          'final iosNseTransportAdmissionActive =\n'
          '        iosNseInboxTransportProjection != null &&\n'
          '        kWakeOutcomeCoordinatorAdmissionEnabled &&\n'
          '        !kIsWeb &&\n'
          '        Platform.isIOS;',
        ),
      );
      expect(
        production,
        contains('await iosNseInboxTransportProjection.retireAndReadBack();'),
      );

      final notificationService = File(
        'ios/NotificationService/NotificationService.swift',
      ).readAsStringSync();
      expect(
        _occurrences(
          notificationService,
          'private lazy var mailboxWakeCoordinator = '
          'NseMailboxWakeCoordinator(',
        ),
        1,
      );
      expect(
        notificationService,
        allOf(
          contains('candidateAdapter: NseInboxCandidateAdapter('),
          contains('IosLocalNotificationFinalEffect('),
          contains(
            'if NseMailboxWakeClassifier.isExactFixedWake('
            'request.content.userInfo) {',
          ),
        ),
      );
      final nativeCoordinator = File(
        'ios/NotificationService/NseMailboxWakeCoordinator.swift',
      ).readAsStringSync();
      expect(
        _occurrences(
          nativeCoordinator,
          'BridgeNSEInboxRetrievePending(requestJSON)',
        ),
        1,
      );
      expect(
        nativeCoordinator,
        isNot(
          anyOf(
            contains('BridgeInitialize('),
            contains('BridgeStartNode('),
            contains('GroupInboxRetrieve('),
          ),
        ),
      );
      final goAdapter = File(
        'go-mknoon/bridge/nse_inbox.go',
      ).readAsStringSync();
      expect(
        _occurrences(
          goAdapter,
          'func NSEInboxRetrievePending(paramsJSON string)',
        ),
        1,
      );
      expect(
        goAdapter,
        allOf(
          contains('node.NSEInboxRetrievePendingOneShot('),
          isNot(contains('BridgeInitialize(')),
          isNot(contains('BridgeStartNode(')),
        ),
      );
    },
  );
}

int _occurrences(String source, String needle) =>
    needle.allMatches(source).length;

Future<void> _seedTransport(IosNseInboxTransportProjection projection) async {
  await projection.publishAndReadBack(
    opaqueBinding: _binding,
    logicalAccountPeerId: _accountPeer,
    transportPeerId: _transportPeer,
    transportPrivateKeyBase64: _privateKey,
    relayMultiaddrs: const <String>[_relayA],
  );
}

final _identity = IdentityModel(
  peerId: _accountPeer,
  publicKey: 'account-public-key',
  privateKey: 'account-private-key',
  mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
  username: 'Alice',
  createdAt: '2026-08-16T00:00:00.000Z',
  updatedAt: '2026-08-16T00:00:00.000Z',
);

final Map<String, Object?> _identityRow = <String, Object?>{
  'peer_id': _identity.peerId,
  'public_key': _identity.publicKey,
  'private_key': null,
  'mnemonic12': null,
  'ml_kem_public_key': null,
  'ml_kem_secret_key': null,
  'username': _identity.username,
  'avatar_blob': null,
  'avatar_version': null,
  'created_at': _identity.createdAt,
  'updated_at': _identity.updatedAt,
};

const _contact = ContactModel(
  peerId: '12D3KooWContactPeer',
  publicKey: 'contact-public-key',
  rendezvous: _relayA,
  username: 'Bob',
  signature: 'signature',
  scannedAt: '2026-08-16T00:00:00.000Z',
);

ContactRepositoryImpl _contactRepository({
  required DirectReactionNotificationProjection projection,
  required void Function() onCommit,
  required Future<List<String>> Function() loadAuthority,
}) => ContactRepositoryImpl(
  dbLoadAllContacts: () async => const <Map<String, Object?>>[],
  dbLoadContact: (_) async => null,
  dbUpsertContact: (_) async => onCommit(),
  dbDeleteContact: (_) async {},
  dbGetContactCount: () async => 0,
  dbContactExists: (_) async => false,
  dbArchiveContact: (_) async {},
  dbUnarchiveContact: (_) async {},
  dbLoadActiveContacts: () async => const <Map<String, Object?>>[],
  dbLoadArchivedContacts: () async => const <Map<String, Object?>>[],
  dbBlockContact: (_) async {},
  dbUnblockContact: (_) async {},
  dbDismissIntroBanner: (_) async {},
  dbSetIntrosSentAt: (_, _) async {},
  directReactionProjection: projection,
  loadDirectNotificationAuthorizedTransports: (_) => loadAuthority(),
);

final class _OrderedSecureKeyStore extends FakeSecureKeyStore {
  final List<String> events = <String>[];

  @override
  Future<String?> read(String key) async {
    events.add('read:$key');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    events.add('write:$key');
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    events.add('delete:$key');
    await super.delete(key);
  }
}

final class _FailingDeleteSecureKeyStore extends FakeSecureKeyStore {
  @override
  Future<void> delete(String key) async {
    throw StateError('delete failed');
  }
}

final class _DirectAuthorityProjection
    extends DirectReactionNotificationProjection {
  _DirectAuthorityProjection(this.order) : super(store: FakeSecureKeyStore());

  final List<String> order;
  bool failRetire = false;

  @override
  Future<void> retireContactTransportAuthority(String peerId) async {
    order.add('retire');
    if (failRetire) throw StateError('retirement failed');
  }

  @override
  Future<void> upsertContact(ContactModel contact) async {
    order.add('display');
  }

  @override
  Future<void> replaceContactTransportAuthority({
    required String peerId,
    required Iterable<String> authorizedTransportPeerIds,
  }) async {
    order.add('replace:${authorizedTransportPeerIds.join(',')}');
  }
}

final class _GroupAuthorityProjection
    extends GroupReactionNotificationProjection {
  _GroupAuthorityProjection(this.order) : super(store: FakeSecureKeyStore());

  final List<String> order;

  @override
  Future<void> retireGroupSenderAuthority(String groupId) async {
    order.add('retire');
  }

  @override
  Future<void> replaceGroupSenderAuthority(
    String groupId,
    GroupNotificationSenderAuthority? authority,
  ) async {
    order.add('replace');
  }
}
