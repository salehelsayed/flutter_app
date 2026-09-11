import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/debug/group_media_reliability_e2e.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e_main_actions.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import '../../shared/fakes/in_memory_pending_group_invite_repository.dart';
import '../../shared/fakes/in_memory_group_message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';
import '../../shared/fakes/in_memory_group_repository.dart';
import '../../shared/fakes/in_memory_contact_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';

void main() {
  test(
    'P269 ordinary-primary setup uses signed creation and exact uninitialized member roster',
    () async {
      final identity = FakeIdentityRepository.makeIdentity(
        peerId: 'account-author',
        mlKemPublicKey: 'mlkem-author',
      );
      final identities = FakeIdentityRepository()..seed(identity);
      final contacts = InMemoryContactRepository()
        ..addTestContact(
          ContactModel(
            peerId: 'account-receiver',
            publicKey: 'pk-receiver',
            mlKemPublicKey: 'mlkem-receiver',
            rendezvous: '/dns4/relay.invalid/tcp/443',
            username: 'Receiver',
            signature: 'signed-contact',
            scannedAt: DateTime.utc(2026, 9, 11).toIso8601String(),
          ),
        );
      final bridge = PassthroughCryptoBridge();
      bridge.responses['group:create'] = <String, dynamic>{
        'ok': true,
        'groupId': 'group-primary-proof',
        'topicName': 'topic-primary-proof',
        'groupKey': 'group-key',
        'keyEpoch': 1,
      };
      final p2p = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'account-author',
        ),
      );
      final groups = InMemoryGroupRepository();
      final events = <({String type, Map<String, Object?> payload})>[];
      final result = await setupGroupMediaReliabilitySender(
        receiverAccountPeerId: 'account-receiver',
        receiverTransportPeerId: 'account-receiver',
        bridge: bridge,
        p2pService: p2p,
        identityRepository: identities,
        contactRepository: contacts,
        groupRepository: groups,
        authorityMode: GroupMediaReliabilityAuthorityMode.accountBoundLegacy,
        appendGroupEventLogEntry:
            ({
              required groupId,
              required eventType,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required payload,
              createdAt,
            }) async {
              events.add((type: eventType, payload: payload));
              return <String, Object?>{};
            },
      );
      final members = await groups.getMembers(result['groupId']! as String);
      expect(members.map((member) => member.peerId).toSet(), <String>{
        'account-author',
        'account-receiver',
      });
      expect(
        members.every(
          (member) =>
              !member.hasInitializedDeviceAuthority && member.devices.isEmpty,
        ),
        isTrue,
      );
      expect(events.single.type, 'group_created');
      expect(events.single.payload['signature'], isNotEmpty);
      expect(
        (events.single.payload['signedPayload']! as Map)['createdBy'],
        'account-author',
      );
      expect(p2p.lastSendMessagePeerId, 'account-receiver');
      expect(bridge.commandLog, contains('message.encrypt'));
      final encrypted = bridge.sentMessages
          .map((text) => jsonDecode(text) as Map)
          .lastWhere((message) => message['cmd'] == 'message.encrypt');
      final invite = GroupInvitePayload.fromInnerJson(
        (encrypted['payload']! as Map)['plaintext']! as String,
      );
      expect(invite, isNotNull);
      expect(invite!.hasDeviceBoundRecipient, isFalse);
      expect(
        invite.isBoundToRecipientDevice(ownPeerId: 'account-receiver'),
        isTrue,
      );
      expect(
        invite.isBoundToRecipientDevice(ownPeerId: 'other-account'),
        isFalse,
      );
      expect(invite.invitePolicy.allowedDevices, <String>['account-receiver']);
      final receiverGroups = InMemoryGroupRepository();
      final pending = InMemoryPendingGroupInviteRepository();
      await pending.savePendingInvite(
        PendingGroupInvite.fromPayload(
          invite,
          receivedAt: DateTime.now().toUtc(),
        ),
      );
      final accepted = await acceptPendingGroupInvite(
        pendingInviteRepo: pending,
        groupRepo: receiverGroups,
        contactRepo: contacts,
        msgRepo: InMemoryGroupMessageRepository(),
        bridge: bridge,
        groupId: invite.groupId,
        senderPeerId: 'account-receiver',
        senderPublicKey: 'pk-receiver',
        senderPrivateKey: 'sk-receiver',
        senderUsername: 'Receiver',
        ownMlKemPublicKey: 'mlkem-receiver',
        ownKeyPackagePublicMaterial: 'mlkem-receiver',
      );
      expect(accepted.$1, AcceptPendingGroupInviteResult.success);
      final acceptedMembers = await receiverGroups.getMembers(invite.groupId);
      expect(acceptedMembers.map((member) => member.peerId).toSet(), <String>{
        'account-author',
        'account-receiver',
      });
      expect(
        acceptedMembers.every(
          (member) =>
              member.devices.isEmpty && !member.hasInitializedDeviceAuthority,
        ),
        isTrue,
      );
      expect(await receiverGroups.getLatestKey(invite.groupId), isNotNull);
      expect(await pending.getPendingInvite(invite.groupId), isNull);

      expect(result['transportPeerId'], identity.peerId);
      final publishes = bridge.sentMessages
          .map((text) => jsonDecode(text) as Map)
          .where((message) => message['cmd'] == 'group:publish');
      expect(publishes, isNotEmpty);
    },
  );

  test(
    'P269 ordinary-primary mode cannot accept distinct or malformed transports',
    () {
      for (final transport in <String>[
        'other-transport',
        '',
        ' account-author',
      ]) {
        expect(
          groupMediaReliabilityIdentityMatches(
            mode: GroupMediaReliabilityAuthorityMode.accountBoundLegacy,
            accountPeerId: 'account-author',
            transportPeerId: transport,
          ),
          isFalse,
        );
      }
      expect(
        () => parseGroupMediaReliabilityAuthorityMode('unknown'),
        throwsFormatException,
      );
    },
  );

  test('group role database probe accepts the exact current schema', () async {
    for (final role in <String>['sender', 'receiver']) {
      final database = _RoleProbeDatabase(currentIdentityDatabaseVersion);
      final result = await probeGroupMediaReliabilityRoleDatabase(
        role: role,
        runId: 'schema-proof-run',
        transportPeerId: '$role-transport',
        messageIds: const {},
        attachmentIds: const {},
        database: database,
        mediaAttachmentRepository: _UnusedRoleMediaRepository(),
      );
      expect(result['user_version'], currentIdentityDatabaseVersion);
      expect(result['cipher_version'], 'SQLCipher fixture');
      expect(result['role_db_path'], '$role/group-media.sqlite');
      expect(result['rows'], isEmpty);
      expect(
        result['database_path_sha256'],
        groupMediaReliabilityDatabasePathFingerprint(
          runId: 'schema-proof-run',
          transportPeerId: '$role-transport',
          databasePath: database.path,
        ),
      );
      expect(database.queries, [
        'PRAGMA cipher_version',
        'PRAGMA user_version',
      ]);
    }
  });

  test(
    'group role database probe rejects obsolete and future schemas',
    () async {
      for (final version in <int>[104, currentIdentityDatabaseVersion + 1]) {
        await expectLater(
          probeGroupMediaReliabilityRoleDatabase(
            role: 'sender',
            runId: 'schema-proof-run',
            transportPeerId: 'sender-transport',
            messageIds: const {},
            attachmentIds: const {},
            database: _RoleProbeDatabase(version),
            mediaAttachmentRepository: _UnusedRoleMediaRepository(),
          ),
          throwsStateError,
        );
      }
    },
  );

  test('current schema cannot bypass cipher and transport evidence', () async {
    for (final missingCipher in <bool>[true, false]) {
      await expectLater(
        probeGroupMediaReliabilityRoleDatabase(
          role: 'sender',
          runId: 'schema-proof-run',
          transportPeerId: missingCipher ? 'sender-transport' : '',
          messageIds: const {},
          attachmentIds: const {},
          database: _RoleProbeDatabase(
            currentIdentityDatabaseVersion,
            cipherVersion: missingCipher ? '' : 'SQLCipher fixture',
          ),
          mediaAttachmentRepository: _UnusedRoleMediaRepository(),
        ),
        throwsStateError,
      );
    }
  });

  group('group-media fixture authority policy', () {
    test('Plan 330 account-bound mode accepts only exact legacy authority', () {
      expect(
        groupMediaReliabilityAuthorityMatches(
          mode: GroupMediaReliabilityAuthorityMode.accountBoundLegacy,
          localAccountPeerId: 'account-author',
          localTransportPeerId: 'account-author',
          remoteAccountPeerId: 'account-reactor',
          remoteTransportPeerId: 'account-reactor',
          allowedPeers: const <String>['account-author', 'account-reactor'],
        ),
        isTrue,
      );
    });

    test(
      'Plan 330 account-bound mode rejects mixed and distinct authority',
      () {
        for (final authority
            in const <
              ({
                String localTransport,
                String remoteTransport,
                List<String> allowedPeers,
              })
            >[
              (
                localTransport: 'transport-author',
                remoteTransport: 'account-reactor',
                allowedPeers: <String>['transport-author', 'account-reactor'],
              ),
              (
                localTransport: 'account-author',
                remoteTransport: 'transport-reactor',
                allowedPeers: <String>['account-author', 'transport-reactor'],
              ),
              (
                localTransport: 'transport-author',
                remoteTransport: 'transport-reactor',
                allowedPeers: <String>['transport-author', 'transport-reactor'],
              ),
              (
                localTransport: '',
                remoteTransport: 'account-reactor',
                allowedPeers: <String>['account-reactor'],
              ),
            ]) {
          expect(
            groupMediaReliabilityAuthorityMatches(
              mode: GroupMediaReliabilityAuthorityMode.accountBoundLegacy,
              localAccountPeerId: 'account-author',
              localTransportPeerId: authority.localTransport,
              remoteAccountPeerId: 'account-reactor',
              remoteTransportPeerId: authority.remoteTransport,
              allowedPeers: authority.allowedPeers,
            ),
            isFalse,
          );
        }
      },
    );

    test('P269 distinct mode remains strict and rejects legacy equality', () {
      expect(
        groupMediaReliabilityAuthorityMatches(
          mode: GroupMediaReliabilityAuthorityMode.distinctAccountAndTransport,
          localAccountPeerId: 'account-author',
          localTransportPeerId: 'transport-author',
          remoteAccountPeerId: 'account-reactor',
          remoteTransportPeerId: 'transport-reactor',
          allowedPeers: const <String>['transport-author', 'transport-reactor'],
        ),
        isTrue,
      );
      expect(
        groupMediaReliabilityAuthorityMatches(
          mode: GroupMediaReliabilityAuthorityMode.distinctAccountAndTransport,
          localAccountPeerId: 'account-author',
          localTransportPeerId: 'account-author',
          remoteAccountPeerId: 'account-reactor',
          remoteTransportPeerId: 'account-reactor',
          allowedPeers: const <String>['account-author', 'account-reactor'],
        ),
        isFalse,
      );
    });
  });

  test('P269 database fingerprint distinguishes same-path Android roles', () {
    const runId = 'p269-db-fingerprint-run';
    const sharedAndroidPath = '/data/user/0/com.mknoon.app/databases/app.db';
    final sender = groupMediaReliabilityDatabasePathFingerprint(
      runId: runId,
      transportPeerId: 'sender-transport',
      databasePath: sharedAndroidPath,
    );

    expect(
      groupMediaReliabilityDatabasePathFingerprint(
        runId: runId,
        transportPeerId: ' sender-transport ',
        databasePath: sharedAndroidPath,
      ),
      sender,
      reason: 'the same role must be stable across a process restart',
    );
    expect(
      groupMediaReliabilityDatabasePathFingerprint(
        runId: runId,
        transportPeerId: 'receiver-transport',
        databasePath: sharedAndroidPath,
      ),
      isNot(sender),
      reason: 'two devices can expose the same textual Android database path',
    );
    expect(
      groupMediaReliabilityDatabasePathFingerprint(
        runId: runId,
        transportPeerId: 'sender-transport',
        databasePath: '$sharedAndroidPath.relocated',
      ),
      isNot(sender),
      reason: 'a changed physical database path must also change custody',
    );
  });

  test('P269 endpoint failures expose only stable redacted codes', () {
    final command = _command(
      phase: groupMediaReliabilitySenderSetupPhase,
      role: 'sender',
    );
    const cases = <String, String>{
      'group-media disposable identity authority did not settle':
          'identity_authority',
      'group-media sender lacks distinct account/transport authority':
          'sender_authority',
      'group-media sender group/invite setup did not settle':
          'sender_group_invite_settle',
      'group-media role SQLCipher facts rejected': 'role_sqlcipher_facts',
    };

    for (final entry in cases.entries) {
      final receipt = groupMediaReliabilityE2EFailureReceipt(
        config: command,
        error: StateError(entry.key),
      );
      expect(receipt['errorCode'], entry.value);
      expect(receipt.values, isNot(contains(entry.key)));
    }

    const sensitiveDetail =
        'peer-secret-material private-key-token relay-address';
    final unknown = groupMediaReliabilityE2EFailureReceipt(
      config: command,
      error: StateError(sensitiveDetail),
    );
    expect(unknown['errorCode'], 'unexpected_error');
    expect(unknown.values, isNot(contains(sensitiveDetail)));
    expect(
      unknown.keys,
      isNot(containsAll(<String>['message', 'stackTrace', 'peerId', 'relay'])),
    );
  });

  test(
    'P269 Android endpoint exports exact selected authority mode and identities',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-identity-endpoint-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final controller = GroupMediaReliabilityE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 269,
      );
      String? setupAccount;
      String? setupTransport;

      var mode = GroupMediaReliabilityAuthorityMode.distinctAccountAndTransport;
      Future<Map<String, Object?>> invoke(Map<String, dynamic> config) =>
          runGroupMediaReliabilityE2EAction(
            config: config,
            controller: controller,
            authorityModeName: mode.name,
            loadAttachment: (_) async => null,
            probeIdentity: (role) async => <String, Object?>{
              'accountPeerId': '$role-account',
              'transportPeerId':
                  mode == GroupMediaReliabilityAuthorityMode.accountBoundLegacy
                  ? '$role-account'
                  : '$role-transport',
            },
            setupSender: (account, transport) async {
              setupAccount = account;
              setupTransport = transport;
              return const <String, Object?>{'groupId': 'group-id'};
            },
            acceptReceiver: (_) async => null,
            sendMedia: (_, _, _, _, _) async => const <String, Object?>{},
            probeRole: (role, _, _) async => <String, Object?>{'role': role},
            retryUploads: () async => 0,
            retryDownloads: () async => 0,
            installedProfileId: groupMediaReliabilityE2EBuildProfile,
          );

      final identity = await invoke(
        _command(phase: groupMediaReliabilityIdentityPhase, role: 'receiver'),
      );
      expect(identity['accountPeerId'], 'receiver-account');
      expect(identity['transportPeerId'], 'receiver-transport');
      expect(identity['authorityMode'], 'distinctAccountAndTransport');
      mode = GroupMediaReliabilityAuthorityMode.accountBoundLegacy;
      final ordinaryIdentity = await invoke(
        _command(phase: groupMediaReliabilityIdentityPhase, role: 'receiver'),
      );
      expect(ordinaryIdentity['authorityMode'], 'accountBoundLegacy');
      expect(
        ordinaryIdentity['accountPeerId'],
        ordinaryIdentity['transportPeerId'],
      );

      await invoke(
        _command(phase: groupMediaReliabilitySenderSetupPhase, role: 'sender'),
      );
      expect(setupAccount, 'receiver-account');
      expect(setupTransport, 'receiver-transport');
    },
  );

  test(
    'P269 durable JPEG barrier records downloading before fresh-process attempt two',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-group-media-barrier-',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });

      final firstProcess = GroupMediaReliabilityE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 101,
      );
      await firstProcess.arm(
        const GroupMediaReliabilityBarrierRequest(
          runId: 'p269-run',
          groupId: 'group-id',
          jpegMessageId: 'message-jpeg',
          jpegAttachmentId: 'blob-jpeg',
          mediaMessageIds: <String, String>{
            'jpeg': 'message-jpeg',
            'mp4': 'message-mp4',
            'voice': 'message-voice',
          },
          mediaAttachmentIds: <String, String>{
            'jpeg': 'blob-jpeg',
            'mp4': 'blob-mp4',
            'voice': 'blob-voice',
          },
        ),
      );

      final firstJpeg = _attachment(
        id: 'blob-jpeg',
        messageId: 'message-jpeg',
        mime: 'image/jpeg',
      );
      await firstProcess.onAutomaticDownloadAttemptStarted(
        attachment: firstJpeg,
      );
      final blocked = firstProcess.onPostClaimPreCommit(
        attachment: firstJpeg,
        loadCurrentAttachment: (_) async => _attachment(
          id: 'blob-jpeg',
          messageId: 'message-jpeg',
          mime: 'image/jpeg',
          status: 'downloading',
        ),
      );
      final reached = await firstProcess.waitForBarrierReached();
      expect(reached.priorStatus, 'downloading');
      expect(reached.attempt, 1);
      expect(reached.processId, 101);
      expect(firstProcess.holdsAutomaticRecovery, isTrue);

      // Model Android force-stop: the first future never receives a host
      // release. A newly constructed controller reads only durable state.
      final secondProcess = GroupMediaReliabilityE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 202,
      );
      final prior = await secondProcess.releaseRecoveryAfterPriorStatus(
        loadCurrentAttachment: (_) async => _attachment(
          id: 'blob-jpeg',
          messageId: 'message-jpeg',
          mime: 'image/jpeg',
          status: 'downloading',
        ),
      );
      expect(prior.priorStatus, 'downloading');
      expect(prior.previousProcessId, 101);
      expect(prior.currentProcessId, 202);
      expect(secondProcess.holdsAutomaticRecovery, isFalse);

      final secondJpeg = _attachment(
        id: 'blob-jpeg',
        messageId: 'message-jpeg',
        mime: 'image/jpeg',
      );
      await secondProcess.onAutomaticDownloadAttemptStarted(
        attachment: secondJpeg,
      );
      // A fresh invocation is attempt two even if production repairs from the
      // complete encrypted companion and never needs this post-relay hook.
      expect(await secondProcess.loadAttemptCounts(), <String, int>{
        'jpeg': 2,
        'mp4': 0,
        'voice': 0,
      });
      await secondProcess.onPostClaimPreCommit(
        attachment: secondJpeg,
        loadCurrentAttachment: (_) async => _attachment(
          id: 'blob-jpeg',
          messageId: 'message-jpeg',
          mime: 'image/jpeg',
          status: 'downloading',
        ),
      );
      final mp4 = _attachment(
        id: 'blob-mp4',
        messageId: 'message-mp4',
        mime: 'video/mp4',
      );
      await secondProcess.onAutomaticDownloadAttemptStarted(attachment: mp4);
      await secondProcess.onPostClaimPreCommit(
        attachment: mp4,
        loadCurrentAttachment: (_) async => _attachment(
          id: 'blob-mp4',
          messageId: 'message-mp4',
          mime: 'video/mp4',
          status: 'downloading',
        ),
      );
      final voice = _attachment(
        id: 'blob-voice',
        messageId: 'message-voice',
        mime: 'audio/mp4',
      );
      await secondProcess.onAutomaticDownloadAttemptStarted(attachment: voice);
      await secondProcess.onPostClaimPreCommit(
        attachment: voice,
        loadCurrentAttachment: (_) async => _attachment(
          id: 'blob-voice',
          messageId: 'message-voice',
          mime: 'audio/mp4',
          status: 'downloading',
        ),
      );

      expect(await secondProcess.loadAttemptCounts(), <String, int>{
        'jpeg': 2,
        'mp4': 1,
        'voice': 1,
      });
      expect(blocked, doesNotComplete);
    },
  );

  test(
    'P269 fresh-process endpoint reads prior status then drives the same gated retry callbacks twice',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-group-media-endpoint-',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      final first = GroupMediaReliabilityE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 301,
      );
      await first.arm(
        const GroupMediaReliabilityBarrierRequest(
          runId: 'p269-endpoint',
          groupId: 'group-id',
          jpegMessageId: 'message-jpeg',
          jpegAttachmentId: 'blob-jpeg',
          mediaMessageIds: <String, String>{
            'jpeg': 'message-jpeg',
            'mp4': 'message-mp4',
            'voice': 'message-voice',
          },
          mediaAttachmentIds: <String, String>{
            'jpeg': 'blob-jpeg',
            'mp4': 'blob-mp4',
            'voice': 'blob-voice',
          },
        ),
      );
      unawaited(() async {
        final jpeg = _attachment(
          id: 'blob-jpeg',
          messageId: 'message-jpeg',
          mime: 'image/jpeg',
        );
        await first.onAutomaticDownloadAttemptStarted(attachment: jpeg);
        await first.onPostClaimPreCommit(
          attachment: jpeg,
          loadCurrentAttachment: (_) async => _attachment(
            id: 'blob-jpeg',
            messageId: 'message-jpeg',
            mime: 'image/jpeg',
            status: 'downloading',
          ),
        );
      }());
      await first.waitForBarrierReached();

      final second = GroupMediaReliabilityE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 302,
      );
      final uploadReturns = <int>[0, 0];
      final downloadReturns = <int>[1, 0];
      var uploadCalls = 0;
      var downloadCalls = 0;
      final result = await runGroupMediaReliabilityE2EAction(
        config: _command(
          phase: groupMediaReliabilityReceiverRecoverPhase,
          role: 'receiver',
        ),
        controller: second,
        loadAttachment: (_) async => _attachment(
          id: 'blob-jpeg',
          messageId: 'message-jpeg',
          mime: 'image/jpeg',
          status: 'downloading',
        ),
        probeIdentity: (_) async => throw StateError('wrong phase'),
        setupSender: (_, _) async => throw StateError('wrong phase'),
        acceptReceiver: (_) async => throw StateError('wrong phase'),
        sendMedia: (_, _, _, _, _) async => throw StateError('wrong phase'),
        probeRole: (role, _, _) async => <String, Object?>{
          'role': role,
          'reopened': true,
        },
        retryUploads: () async => uploadReturns[uploadCalls++],
        retryDownloads: () async => downloadReturns[downloadCalls++],
        installedProfileId: groupMediaReliabilityE2EBuildProfile,
      );

      expect(result['priorStatus'], 'downloading');
      expect(result['previousProcessId'], 301);
      expect(result['currentProcessId'], 302);
      expect(result['firstUploadWork'], 0);
      expect(result['firstDownloadWork'], 1);
      expect(result['secondUploadWork'], 0);
      expect(result['secondDownloadWork'], 0);
      expect(uploadCalls, 2);
      expect(downloadCalls, 2);
    },
  );

  test(
    'P269 polling an old snapshot cannot erase a serialized copy-on-write barrier',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-group-media-state-interleave-',
      );
      final barrierReplacePaused = Completer<void>();
      final allowBarrierReplace = Completer<void>();
      final pollObservedOldSnapshot = Completer<void>();
      var isBarrierReplacePaused = false;
      var didPauseBarrierReplace = false;
      Future<void>? postClaim;

      late final GroupMediaReliabilityE2EController first;
      first = GroupMediaReliabilityE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 401,
        beforeAtomicStateReplace: (barrierReached) async {
          if (!barrierReached || didPauseBarrierReplace) return;
          didPauseBarrierReplace = true;
          isBarrierReplacePaused = true;
          barrierReplacePaused.complete();
          await allowBarrierReplace.future;
          isBarrierReplacePaused = false;
        },
        onStateSnapshotRead: (barrierReached) {
          if (isBarrierReplacePaused &&
              !barrierReached &&
              !pollObservedOldSnapshot.isCompleted) {
            pollObservedOldSnapshot.complete();
          }
        },
      );
      addTearDown(() async {
        if (!allowBarrierReplace.isCompleted) allowBarrierReplace.complete();
        first.releaseFirstBarrierForTest();
        if (postClaim != null) await postClaim;
        if (directory.existsSync()) await directory.delete(recursive: true);
      });

      await first.arm(
        const GroupMediaReliabilityBarrierRequest(
          runId: 'p269-interleave',
          groupId: 'group-id',
          jpegMessageId: 'message-jpeg',
          jpegAttachmentId: 'blob-jpeg',
          mediaMessageIds: <String, String>{
            'jpeg': 'message-jpeg',
            'mp4': 'message-mp4',
            'voice': 'message-voice',
          },
          mediaAttachmentIds: <String, String>{
            'jpeg': 'blob-jpeg',
            'mp4': 'blob-mp4',
            'voice': 'blob-voice',
          },
        ),
      );
      final jpeg = _attachment(
        id: 'blob-jpeg',
        messageId: 'message-jpeg',
        mime: 'image/jpeg',
      );
      await first.onAutomaticDownloadAttemptStarted(attachment: jpeg);
      postClaim = first.onPostClaimPreCommit(
        attachment: jpeg,
        loadCurrentAttachment: (_) async => _attachment(
          id: 'blob-jpeg',
          messageId: 'message-jpeg',
          mime: 'image/jpeg',
          status: 'downloading',
        ),
      );
      await barrierReplacePaused.future;

      final barrierPoll = first.waitForBarrierReached(
        timeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 1),
      );
      await pollObservedOldSnapshot.future.timeout(const Duration(seconds: 1));

      // Queue a second mutation behind the paused barrier transaction. Its
      // copy must start from the committed barrier version, never the old
      // snapshot just observed by the poller.
      final queuedMp4Attempt = first.onAutomaticDownloadAttemptStarted(
        attachment: _attachment(
          id: 'blob-mp4',
          messageId: 'message-mp4',
          mime: 'video/mp4',
        ),
      );
      allowBarrierReplace.complete();

      final reached = await barrierPoll;
      await queuedMp4Attempt;
      expect(reached.priorStatus, 'downloading');
      expect(reached.attempt, 1);
      expect(reached.processId, 401);
      expect(await first.loadAttemptCounts(), <String, int>{
        'jpeg': 1,
        'mp4': 1,
        'voice': 0,
      });

      final fresh = GroupMediaReliabilityE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 402,
      );
      final prior = await fresh.releaseRecoveryAfterPriorStatus(
        loadCurrentAttachment: (_) async => _attachment(
          id: 'blob-jpeg',
          messageId: 'message-jpeg',
          mime: 'image/jpeg',
          status: 'downloading',
        ),
      );
      expect(prior.previousProcessId, 401);
      expect(prior.currentProcessId, 402);

      first.releaseFirstBarrierForTest();
      await postClaim;
      expect(
        directory.listSync().where((entry) => entry.path.contains('.pending-')),
        isEmpty,
      );
      postClaim = null;
    },
  );

  test(
    'P269 receiver render phase delegates the exact post-settlement group tuple',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-group-media-render-',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      final first = GroupMediaReliabilityE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 908,
      );
      await first.arm(
        const GroupMediaReliabilityBarrierRequest(
          runId: 'p269-endpoint',
          groupId: 'group-id',
          jpegMessageId: 'message-jpeg',
          jpegAttachmentId: 'blob-jpeg',
          mediaMessageIds: <String, String>{
            'jpeg': 'message-jpeg',
            'mp4': 'message-mp4',
            'voice': 'message-voice',
          },
          mediaAttachmentIds: <String, String>{
            'jpeg': 'blob-jpeg',
            'mp4': 'blob-mp4',
            'voice': 'blob-voice',
          },
        ),
      );
      final jpeg = _attachment(
        id: 'blob-jpeg',
        messageId: 'message-jpeg',
        mime: 'image/jpeg',
      );
      await first.onAutomaticDownloadAttemptStarted(attachment: jpeg);
      final blocked = first.onPostClaimPreCommit(
        attachment: jpeg,
        loadCurrentAttachment: (_) async => _attachment(
          id: 'blob-jpeg',
          messageId: 'message-jpeg',
          mime: 'image/jpeg',
          status: 'downloading',
        ),
      );
      await first.waitForBarrierReached();
      final controller = GroupMediaReliabilityE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 909,
      );
      await controller.releaseRecoveryAfterPriorStatus(
        loadCurrentAttachment: (_) async => _attachment(
          id: 'blob-jpeg',
          messageId: 'message-jpeg',
          mime: 'image/jpeg',
          status: 'downloading',
        ),
      );
      addTearDown(() async {
        first.releaseFirstBarrierForTest();
        await blocked;
      });
      String? renderedGroupId;
      Map<String, String>? renderedMessages;
      Map<String, String>? renderedAttachments;

      Future<Map<String, Object?>> invoke(Map<String, dynamic> config) =>
          runGroupMediaReliabilityE2EAction(
            config: config,
            controller: controller,
            loadAttachment: (_) async => throw StateError('wrong phase'),
            probeIdentity: (_) async => throw StateError('wrong phase'),
            setupSender: (_, _) async => throw StateError('wrong phase'),
            acceptReceiver: (_) async => throw StateError('wrong phase'),
            sendMedia: (_, _, _, _, _) async => throw StateError('wrong phase'),
            probeRole: (_, _, _) async => throw StateError('wrong phase'),
            retryUploads: () async => throw StateError('wrong phase'),
            retryDownloads: () async => throw StateError('wrong phase'),
            renderReceiver: (groupId, messageIds, attachmentIds) async {
              renderedGroupId = groupId;
              renderedMessages = messageIds;
              renderedAttachments = attachmentIds;
              return <String, Object?>{'renderProbeArmed': true};
            },
            installedProfileId: groupMediaReliabilityE2EBuildProfile,
          );
      final command = _command(
        phase: groupMediaReliabilityReceiverRenderPhase,
        role: 'receiver',
      );
      await expectLater(invoke(command), throwsStateError);

      for (final attachment in <MediaAttachment>[
        jpeg,
        _attachment(
          id: 'blob-mp4',
          messageId: 'message-mp4',
          mime: 'video/mp4',
        ),
        _attachment(
          id: 'blob-voice',
          messageId: 'message-voice',
          mime: 'audio/mp4',
        ),
      ]) {
        await controller.onAutomaticDownloadAttemptStarted(
          attachment: attachment,
        );
        await controller.onPostClaimPreCommit(
          attachment: attachment,
          loadCurrentAttachment: (_) async =>
              attachment.copyWith(downloadStatus: 'downloading'),
        );
      }

      final wrongCommand = _command(
        phase: groupMediaReliabilityReceiverRenderPhase,
        role: 'receiver',
      );
      (wrongCommand['attachmentIds']! as Map<String, String>)['voice'] =
          'blob-other';
      await expectLater(invoke(wrongCommand), throwsStateError);
      final result = await invoke(command);

      expect(renderedGroupId, 'group-id');
      expect(renderedMessages, <String, String>{
        'jpeg': 'message-jpeg',
        'mp4': 'message-mp4',
        'voice': 'message-voice',
      });
      expect(renderedAttachments, <String, String>{
        'jpeg': 'blob-jpeg',
        'mp4': 'blob-mp4',
        'voice': 'blob-voice',
      });
      expect(result['renderProbeArmed'], isTrue);
      expect(result['processId'], 909);
    },
  );
}

Map<String, dynamic> _command({required String phase, required String role}) =>
    <String, dynamic>{
      'schema': groupMediaReliabilityE2ECommandSchema,
      'transport_action': groupMediaReliabilityE2EAction,
      'scenario': 'group_media_foreground_retry_acl_roundtrip',
      'stepId': 'group-media-$phase-p269-endpoint',
      'phase': phase,
      'role': role,
      'runId': 'p269-endpoint',
      'nonce': 'nonce',
      'groupId': 'group-id',
      'receiverAccountPeerId': 'receiver-account',
      'receiverTransportPeerId': 'receiver-transport',
      'messageIds': <String, String>{
        'jpeg': 'message-jpeg',
        'mp4': 'message-mp4',
        'voice': 'message-voice',
      },
      'attachmentIds': <String, String>{
        'jpeg': 'blob-jpeg',
        'mp4': 'blob-mp4',
        'voice': 'blob-voice',
      },
    };

MediaAttachment _attachment({
  required String id,
  required String messageId,
  required String mime,
  String status = 'pending',
}) => MediaAttachment(
  id: id,
  messageId: messageId,
  mediaType: mime.startsWith('image/')
      ? 'image'
      : mime.startsWith('video/')
      ? 'video'
      : 'audio',
  mime: mime,
  size: 32,
  createdAt: DateTime.utc(2026, 7, 22).toIso8601String(),
  downloadStatus: status,
  encryptionKeyBase64: 'key',
  encryptionNonce: 'nonce',
  encryptionScheme: 'blob_aes_gcm_v1',
  contentHash: List<String>.filled(64, 'a').join(),
);

final class _RoleProbeDatabase extends Fake implements Database {
  _RoleProbeDatabase(
    this.userVersion, {
    this.cipherVersion = 'SQLCipher fixture',
  });

  final int userVersion;
  final String cipherVersion;
  final List<String> queries = [];

  @override
  String get path => '/synthetic/role-database.sqlite';

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    queries.add(sql);
    return switch (sql) {
      'PRAGMA cipher_version' => [
        {'cipher_version': cipherVersion},
      ],
      'PRAGMA user_version' => [
        {'user_version': userVersion},
      ],
      _ => throw StateError('Unexpected role database query'),
    };
  }
}

final class _UnusedRoleMediaRepository extends Fake
    implements MediaAttachmentRepository {}
