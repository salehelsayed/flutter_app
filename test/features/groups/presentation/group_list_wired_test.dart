import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

// --- FakeIdentityRepository ---

class FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;
  FakeIdentityRepository({this.identity});

  /// Counts every `loadIdentity` call. `_onAcceptPendingInvite` loads the
  /// identity EXACTLY ONCE per entry (before the recovery-retry wrapper, which
  /// re-attempts without reloading), so this is a clean per-accept-pass counter
  /// — used by TC-02 to prove the `_processingInviteIds` guard collapses a
  /// rapid double-tap into a single fresh accept pass.
  int loadIdentityCallCount = 0;

  @override
  Future<IdentityModel?> loadIdentity() async {
    loadIdentityCallCount++;
    return identity;
  }

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

/// Identity repo whose [loadIdentity] always throws — used to drive a throwing
/// deferred decline commit (153 TC-7).
class _ThrowingIdentityRepository extends FakeIdentityRepository {
  @override
  Future<IdentityModel?> loadIdentity() async {
    throw StateError('identity load failed (test injection)');
  }
}

/// Identity repo whose [loadIdentity] resolves slowly — used to hold the
/// deferred decline commit in-flight so the Undo affordance's hide timing is
/// observable (153 review P2).
class _SlowIdentityRepository extends FakeIdentityRepository {
  _SlowIdentityRepository({super.identity});

  @override
  Future<IdentityModel?> loadIdentity() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    return identity;
  }
}

// --- Fake listeners with externally-controlled streams ---

/// A fake GroupMessageListener whose [groupMessageStream] is controlled
/// by an external StreamController passed in the constructor.
class FakeGroupMessageListener extends GroupMessageListener {
  final Stream<GroupMessage> _externalStream;

  FakeGroupMessageListener(this._externalStream)
    : super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

  @override
  Stream<GroupMessage> get groupMessageStream => _externalStream;
}

/// A fake GroupInviteListener whose [groupJoinedStream] is controlled
/// by an external StreamController passed in the constructor.
class FakeGroupInviteListener extends GroupInviteListener {
  final Stream<GroupModel> _joinedStream;
  final Stream<PendingGroupInvite> _pendingStream;
  int waitForIdleCallCount = 0;

  FakeGroupInviteListener({
    required Stream<GroupModel> joinedStream,
    required Stream<PendingGroupInvite> pendingStream,
    required InMemoryPendingGroupInviteRepository pendingInviteRepo,
  }) : _joinedStream = joinedStream,
       _pendingStream = pendingStream,
       super(
         groupInviteStream: const Stream.empty(),
         groupRepo: _NoOpGroupRepo(),
         pendingInviteRepo: pendingInviteRepo,
         contactRepo: InMemoryContactRepository(),
         bridge: FakeBridge(),
         getOwnMlKemSecretKey: () async => null,
       );

  @override
  Stream<GroupModel> get groupJoinedStream => _joinedStream;

  @override
  Stream<PendingGroupInvite> get pendingInviteStream => _pendingStream;

  @override
  Future<void> waitForIdle() async {
    waitForIdleCallCount++;
  }
}

// Minimal no-op implementations only needed for the fake listener super calls.
class _NoOpGroupRepo implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoOpMsgRepo implements GroupMessageRepository {
  @override
  Future<int> transitionSendingToFailed() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// --- Test data ---

final testIdentity = IdentityModel(
  peerId: 'peer-admin',
  publicKey: 'pk-admin',
  privateKey: 'sk-admin',
  mnemonic12:
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  mlKemPublicKey: 'mlkem-pk-admin',
  username: 'Admin',
  createdAt: DateTime.now().toUtc().toIso8601String(),
  updatedAt: DateTime.now().toUtc().toIso8601String(),
);

const aliceContact = ContactModel(
  peerId: '12D3KooWAlice',
  publicKey: 'alicePubKey64',
  rendezvous: '/ip4/0.0.0.0',
  username: 'Alice',
  signature: 'sig',
  scannedAt: '2026-01-01T00:00:00Z',
  mlKemPublicKey: 'aliceMlKem64',
);

GroupModel makeGroup({required String id, required String name}) => GroupModel(
  id: id,
  name: name,
  type: GroupType.chat,
  topicName: 'topic-$id',
  description: 'Desc for $name',
  createdAt: DateTime.now().toUtc(),
  createdBy: 'peer-admin',
  myRole: GroupRole.admin,
);

GroupMessage makeMessage({
  required String id,
  required String groupId,
  required String text,
  bool isIncoming = true,
  DateTime? readAt,
}) => GroupMessage(
  id: id,
  groupId: groupId,
  senderPeerId: isIncoming ? 'peer-alice' : 'peer-admin',
  senderUsername: isIncoming ? 'Alice' : 'Admin',
  text: text,
  timestamp: DateTime.now().toUtc(),
  isIncoming: isIncoming,
  readAt: readAt,
  createdAt: DateTime.now().toUtc(),
);

GroupInviteMembershipFreshnessProof makeInviteFreshnessProof({
  required String inviteId,
  required String groupId,
  required String? recipientPeerId,
  required Map<String, dynamic> groupConfig,
  required DateTime issuedAt,
  String? recipientDeviceId,
  String? recipientTransportPeerId,
  String? recipientMlKemPublicKey,
  String? recipientKeyPackageId,
  String? recipientKeyPackagePublicMaterial,
}) {
  final stateHash = buildGroupConfigStateHash(
    groupId: groupId,
    groupConfig: groupConfig,
  );
  return GroupInviteMembershipFreshnessProof(
    inviteId: inviteId,
    groupId: groupId,
    recipientPeerId: recipientPeerId,
    recipientDeviceId: recipientDeviceId,
    recipientTransportPeerId: recipientTransportPeerId,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    recipientKeyPackageId: recipientKeyPackageId,
    recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
    inviterPeerId: '12D3KooWAlice',
    inviterPublicKey: 'alicePubKey64',
    keyEpoch: 1,
    groupConfigStateHash: stateHash,
    membershipWatermark: stateHash,
    issuedAt: issuedAt.toUtc(),
    expiresAt: issuedAt.toUtc().add(groupInviteMembershipFreshnessTtl),
    inviterMemberSnapshot: const {
      'peerId': '12D3KooWAlice',
      'username': 'Alice',
      'role': 'admin',
      'publicKey': 'alicePubKey64',
      'mlKemPublicKey': 'aliceMlKem64',
    },
  );
}

Future<Map<String, dynamic>> makeSignedReplayInboxMessage({
  required FakeBridge bridge,
  required InMemoryGroupRepository groupRepo,
  required String groupId,
  required String payloadType,
  required Map<String, dynamic> plaintextPayload,
  required String messageId,
}) async {
  final envelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    payloadType: payloadType,
    plaintext: jsonEncode(plaintextPayload),
    messageId: messageId,
    senderPeerId: '12D3KooWAlice',
    senderPublicKey: 'alicePubKey64',
    senderPrivateKey: 'alicePrivateKey64',
    keyInfo: GroupKeyInfo(
      groupId: groupId,
      keyGeneration: 1,
      encryptedKey: 'base64-key',
      createdAt: DateTime.utc(2026, 3, 2),
    ),
  );
  return {'from': '12D3KooWAlice', 'message': envelope};
}

Future<Map<String, dynamic>> makeSignedMetadataReplayInboxMessage({
  required FakeBridge bridge,
  required InMemoryGroupRepository groupRepo,
  required String groupId,
  required DateTime updatedAt,
  required String name,
  required String description,
  required String messageId,
}) async {
  final groupConfig = <String, dynamic>{
    'name': name,
    'groupType': 'chat',
    'description': description,
    'members': [
      {
        'peerId': '12D3KooWAlice',
        'username': 'Alice',
        'role': 'admin',
        'publicKey': 'alicePubKey64',
        'mlKemPublicKey': 'aliceMlKem64',
      },
      {
        'peerId': testIdentity.peerId,
        'username': testIdentity.username,
        'role': 'writer',
        'publicKey': testIdentity.publicKey,
        'mlKemPublicKey': testIdentity.mlKemPublicKey,
      },
    ],
    'createdBy': '12D3KooWAlice',
    'createdAt': DateTime.utc(2026, 3, 2).toIso8601String(),
    'metadataUpdatedAt': updatedAt.toUtc().toIso8601String(),
    groupConfigVersionField: updatedAt.toUtc().toIso8601String(),
  };
  groupConfig[groupConfigStateHashField] = buildGroupConfigStateHash(
    groupId: groupId,
    groupConfig: groupConfig,
  );
  final actorPayload = buildGroupMetadataActorEventPayload(
    groupId: groupId,
    updatedAt: updatedAt,
    actorPeerId: '12D3KooWAlice',
    actorUsername: 'Alice',
    actorPublicKey: 'alicePubKey64',
    groupConfig: groupConfig,
  );
  final canonicalPayload = canonicalizeGroupMetadataActorEventPayload(
    actorPayload,
  );
  final signResponse = await callSignPayload(
    bridge: bridge,
    dataToSign: canonicalPayload,
    privateKey: 'alicePrivateKey64',
  );
  final sysText = jsonEncode({
    '__sys': 'group_metadata_updated',
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'groupConfig': groupConfig,
    groupMetadataActorEventEnvelopeField:
        buildSignedGroupMetadataActorEventEnvelope(
          signedPayload: canonicalPayload,
          signature: signResponse['signature'] as String,
        ),
  });
  return makeSignedReplayInboxMessage(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintextPayload: {
      'groupId': groupId,
      'messageId': messageId,
      'senderId': '12D3KooWAlice',
      'senderUsername': 'Alice',
      'keyEpoch': 1,
      'text': sysText,
      'timestamp': updatedAt.toUtc().toIso8601String(),
    },
    messageId: messageId,
  );
}

PendingGroupInvite makePendingInvite({
  String groupId = 'grp-abc123',
  String groupName = 'Book Club',
  DateTime? receivedAt,
  String? overrideGroupKey,
  String? recipientDeviceId,
}) {
  final effectiveReceivedAt = (receivedAt ?? DateTime.now().toUtc()).toUtc();
  final createdAt = effectiveReceivedAt.subtract(const Duration(hours: 6));
  final inviteTimestamp = createdAt.add(const Duration(minutes: 5));
  final packageId = recipientDeviceId == null
      ? null
      : defaultGroupWelcomeKeyPackageIdForDevice(recipientDeviceId);
  final packageMaterial = recipientDeviceId == null
      ? null
      : testIdentity.mlKemPublicKey;
  final welcomeKeyPackage =
      recipientDeviceId != null && packageId != null && packageMaterial != null
      ? GroupWelcomeKeyPackage.create(
          packageId: packageId,
          publicMaterial: packageMaterial,
          recipientPeerId: testIdentity.peerId,
          recipientDeviceId: recipientDeviceId,
          recipientTransportPeerId: recipientDeviceId,
          recipientMlKemPublicKey: testIdentity.mlKemPublicKey!,
          inviteId: 'invite-$groupId',
          groupId: groupId,
          keyEpoch: 1,
          issuedAt: inviteTimestamp,
          expiresAt: effectiveReceivedAt.add(pendingGroupInviteTtl),
        )
      : null;
  final Map<String, dynamic> groupConfig = {
    'name': groupName,
    'groupType': 'chat',
    'description': 'Invite description',
    'members': [
      {
        'peerId': '12D3KooWAlice',
        'username': 'Alice',
        'role': 'admin',
        'publicKey': 'alicePubKey64',
        'mlKemPublicKey': 'aliceMlKem64',
      },
      {
        'peerId': testIdentity.peerId,
        'username': testIdentity.username,
        'role': 'writer',
        'publicKey': testIdentity.publicKey,
        'mlKemPublicKey': testIdentity.mlKemPublicKey,
        if (recipientDeviceId != null)
          'devices': [
            {
              'deviceId': recipientDeviceId,
              'transportPeerId': recipientDeviceId,
              'deviceSigningPublicKey': testIdentity.publicKey,
              'mlKemPublicKey': testIdentity.mlKemPublicKey,
              'keyPackageId': packageId,
              'keyPackagePublicMaterial': packageMaterial,
              'status': 'active',
            },
          ],
      },
    ],
    'createdBy': '12D3KooWAlice',
    'createdAt': createdAt.toIso8601String(),
  };
  final payload = GroupInvitePayload(
    id: 'invite-$groupId',
    groupId: groupId,
    groupKey: overrideGroupKey ?? 'base64-key',
    keyEpoch: 1,
    groupConfig: groupConfig,
    senderPeerId: '12D3KooWAlice',
    senderUsername: 'Alice',
    timestamp: inviteTimestamp.toIso8601String(),
    recipientPeerId: testIdentity.peerId,
    recipientDeviceId: recipientDeviceId,
    recipientTransportPeerId: recipientDeviceId,
    recipientMlKemPublicKey: recipientDeviceId == null
        ? null
        : testIdentity.mlKemPublicKey,
    recipientKeyPackageId: packageId,
    recipientKeyPackagePublicMaterial: packageMaterial,
    welcomeKeyPackage: welcomeKeyPackage,
    invitePolicy: GroupInvitePolicy(
      expiresAt: effectiveReceivedAt.add(pendingGroupInviteTtl),
      allowedDevices: [recipientDeviceId ?? testIdentity.peerId],
      assignedRole: 'writer',
      canInviteOthers: false,
      joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
      keyEpoch: 1,
      welcomeKeyPackageId: welcomeKeyPackage?.packageId,
      welcomeKeyPackagePublicMaterialHash:
          welcomeKeyPackage?.publicMaterialHash,
      welcomeKeyPackageExpiresAt: welcomeKeyPackage?.expiresAt,
    ),
    membershipFreshnessProof: makeInviteFreshnessProof(
      inviteId: 'invite-$groupId',
      groupId: groupId,
      recipientPeerId: testIdentity.peerId,
      recipientDeviceId: recipientDeviceId,
      recipientTransportPeerId: recipientDeviceId,
      recipientMlKemPublicKey: recipientDeviceId == null
          ? null
          : testIdentity.mlKemPublicKey,
      recipientKeyPackageId: packageId,
      recipientKeyPackagePublicMaterial: packageMaterial,
      groupConfig: groupConfig,
      issuedAt: inviteTimestamp,
    ),
  ).withInviteSignature(signature: 'signed-invite-by-alice');

  return PendingGroupInvite.fromPayload(
    payload,
    receivedAt: effectiveReceivedAt,
  );
}

// --- Helpers ---

/// Pump enough frames for async operations to complete.
/// AmbientBackground has an infinite animation, so pumpAndSettle will timeout.
Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pump in small steps until [condition] holds (bounded — never a busy
/// pumpAndSettle that would hang on AmbientBackground's infinite animation).
/// Used by the shape-b recovery tests to settle the navigation WHILE the
/// default-duration snackbar is still visible, instead of pumping past a
/// hard-coded long snackbar window.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxFrames = 120,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('GroupListWired', () {
    late InMemoryGroupRepository groupRepo;
    late InMemoryGroupMessageRepository msgRepo;
    late InMemoryContactRepository contactRepo;
    late FakeBridge bridge;
    late FakeIdentityRepository identityRepo;
    late FakeP2PService p2pService;
    late InMemoryPendingGroupInviteRepository pendingInviteRepo;
    late FakeGroupInviteListener groupInviteListener;
    late StreamController<GroupMessage> messageStreamController;
    late StreamController<GroupModel> inviteStreamController;
    late StreamController<PendingGroupInvite> pendingInviteStreamController;
    late List<Map<String, dynamic>> flowEvents;

    setUp(() {
      groupRepo = InMemoryGroupRepository();
      msgRepo = InMemoryGroupMessageRepository();
      contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(aliceContact);
      bridge = FakeBridge();
      identityRepo = FakeIdentityRepository(identity: testIdentity);
      p2pService = FakeP2PService();
      pendingInviteRepo = InMemoryPendingGroupInviteRepository();
      messageStreamController = StreamController<GroupMessage>.broadcast();
      inviteStreamController = StreamController<GroupModel>.broadcast();
      pendingInviteStreamController =
          StreamController<PendingGroupInvite>.broadcast();
      groupInviteListener = FakeGroupInviteListener(
        joinedStream: inviteStreamController.stream,
        pendingStream: pendingInviteStreamController.stream,
        pendingInviteRepo: pendingInviteRepo,
      );
      // 153: capture flow events so decline COMMITTED/UNDONE are observable.
      flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
    });

    tearDown(() {
      debugSetFlowEventSink(null);
      messageStreamController.close();
      inviteStreamController.close();
      pendingInviteStreamController.close();
    });

    Widget buildWidget({
      GroupMessageListener? groupMessageListener,
      FakeReactionRepository? reactionRepo,
    }) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GroupListWired(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupMessageListener:
              groupMessageListener ??
              FakeGroupMessageListener(messageStreamController.stream),
          bridge: bridge,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          groupInviteListener: groupInviteListener,
          reactionRepo: reactionRepo,
        ),
      );
    }

    testWidgets('loads and displays active groups on init', (tester) async {
      final g1 = makeGroup(id: 'g-1', name: 'Alpha Group');
      final g2 = makeGroup(id: 'g-2', name: 'Beta Group');
      await groupRepo.saveGroup(g1);
      await groupRepo.saveGroup(g2);

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      expect(find.text('Alpha Group'), findsOneWidget);
      expect(find.text('Beta Group'), findsOneWidget);
    });

    testWidgets(
      'G2: "Retry now" on a stuck group force-eligibles it and triggers a '
      'rejoin pass (collapsing a future backoff window)',
      (tester) async {
        final group = makeGroup(id: 'g-1', name: 'Stuck Group');
        await groupRepo.saveGroup(group);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'g-1',
            keyGeneration: 1,
            encryptedKey: 'key-base64',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        // Stuck: 11 failures, backoff a day out (would otherwise be deferred).
        final future = DateTime.now().toUtc().add(const Duration(days: 1));
        for (var i = 0; i < 11; i++) {
          await groupRepo.recordGroupRejoinFailure('g-1', nextEligibleAt: future);
        }

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        expect(find.text("Couldn't join — retry"), findsOneWidget);
        // No rejoin attempted on init (the screen only displays the badge).
        expect(bridge.commandLog, isNot(contains('group:join')));

        await tester.tap(find.byKey(const ValueKey('group-stuck-retry-g-1')));
        await pumpFrames(tester, count: 20);

        // forceGroupRejoinEligible collapsed the future backoff so the rejoin
        // pass attempted — and, succeeding, cleared the stuck row.
        expect(bridge.commandLog, contains('group:join'));
        expect(
          (await groupRepo.loadGroupRejoinStates()).containsKey('g-1'),
          isFalse,
        );
      },
    );

    testWidgets(
      'G2: "Leave" on a stuck group leaves it (group torn down, never silent)',
      (tester) async {
        final group = makeGroup(id: 'g-1', name: 'Stuck Group');
        await groupRepo.saveGroup(group);
        final future = DateTime.now().toUtc().add(const Duration(days: 1));
        for (var i = 0; i < 11; i++) {
          await groupRepo.recordGroupRejoinFailure('g-1', nextEligibleAt: future);
        }

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        expect(
          find.byKey(const ValueKey('group-stuck-leave-g-1')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('group-stuck-leave-g-1')));
        await pumpFrames(tester, count: 20);

        expect(bridge.commandLog, contains('group:leave'));
        expect(await groupRepo.getGroup('g-1'), isNull);
      },
    );

    testWidgets('reloads renamed group metadata after a message refresh', (
      tester,
    ) async {
      final group = makeGroup(id: 'g-1', name: 'Alpha Group');
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      expect(find.text('Alpha Group'), findsOneWidget);

      await groupRepo.updateGroup(
        group.copyWith(
          name: 'Renamed Group',
          description: 'Updated description',
        ),
      );
      messageStreamController.add(
        makeMessage(id: 'meta-1', groupId: 'g-1', text: 'metadata updated'),
      );
      await pumpFrames(tester, count: 20);

      expect(find.text('Renamed Group'), findsOneWidget);
    });

    testWidgets('shows loading placeholders before groups resolve', (
      tester,
    ) async {
      final slowGroupRepo = _SlowGroupRepository();
      final g1 = makeGroup(id: 'g-1', name: 'Alpha Group');
      await slowGroupRepo.saveGroup(g1);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupListWired(
            groupRepo: slowGroupRepo,
            msgRepo: msgRepo,
            groupMessageListener: FakeGroupMessageListener(
              messageStreamController.stream,
            ),
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            groupInviteListener: groupInviteListener,
          ),
        ),
      );

      expect(find.byKey(const ValueKey('group-loading-row-0')), findsOneWidget);
      expect(find.text('Alpha Group'), findsNothing);

      slowGroupRepo.release();
      await pumpFrames(tester);

      expect(find.text('Alpha Group'), findsOneWidget);
      expect(find.byKey(const ValueKey('group-loading-row-0')), findsNothing);
    });

    testWidgets('refreshes group list when groupMessageListener emits', (
      tester,
    ) async {
      final g1 = makeGroup(id: 'g-1', name: 'Alpha Group');
      await groupRepo.saveGroup(g1);

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      // Initially only Alpha
      expect(find.text('Alpha Group'), findsOneWidget);
      expect(find.text('Gamma Group'), findsNothing);

      // Add a new group to the repo (simulating background save)
      final g3 = makeGroup(id: 'g-3', name: 'Gamma Group');
      await groupRepo.saveGroup(g3);

      // Emit on the message listener stream to trigger refresh
      messageStreamController.add(
        makeMessage(
          id: 'msg-new',
          groupId: 'g-3',
          text: 'Hello from new group',
        ),
      );
      await pumpFrames(tester, count: 20);

      // Gamma Group should now appear
      expect(find.text('Gamma Group'), findsOneWidget);
    });

    testWidgets('refreshes group list when groupInviteListener emits', (
      tester,
    ) async {
      final g1 = makeGroup(id: 'g-1', name: 'Alpha Group');
      await groupRepo.saveGroup(g1);

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      expect(find.text('Alpha Group'), findsOneWidget);
      expect(find.text('Invited Group'), findsNothing);

      // Add the group to the repo (simulating the invite handler saving it)
      final gInvited = makeGroup(id: 'g-inv', name: 'Invited Group');
      await groupRepo.saveGroup(gInvited);

      // Emit on the invite listener stream
      inviteStreamController.add(gInvited);
      await pumpFrames(tester, count: 20);

      expect(find.text('Invited Group'), findsOneWidget);
    });

    testWidgets('loads pending invites on init', (tester) async {
      final invite = makePendingInvite();
      await pendingInviteRepo.savePendingInvite(invite);

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      expect(
        find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
        findsOneWidget,
      );
      expect(find.text('Book Club'), findsOneWidget);
      expect(find.text('Invited by Alice'), findsOneWidget);
    });

    testWidgets(
      'B2: hides a pending invite whose group is already joined, keeps a non-joined one',
      (tester) async {
        // Already-joined group → its invite is a materialized orphan: hide it.
        await groupRepo.saveGroup(
          makeGroup(id: 'grp-joined', name: 'Joined Group'),
        );
        await pendingInviteRepo.savePendingInvite(
          makePendingInvite(groupId: 'grp-joined', groupName: 'Joined Group'),
        );
        // Not-yet-joined invite → still rendered.
        await pendingInviteRepo.savePendingInvite(
          makePendingInvite(groupId: 'grp-fresh', groupName: 'Fresh Invite'),
        );

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        expect(
          find.byKey(const ValueKey('pending-group-invite-grp-joined')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('pending-group-invite-grp-fresh')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'B2 negative guard: an expired but not-joined invite still renders (dismiss affordance preserved)',
      (tester) async {
        // Card-expired (receivedAt + 7d in the past) but its group is NOT
        // joined, so the materialized filter must NOT strip it — the user can
        // still Decline/dismiss it.
        final expiredInvite = makePendingInvite(
          groupId: 'grp-expired',
          groupName: 'Expired Invite',
          receivedAt: DateTime.now().toUtc().subtract(const Duration(days: 8)),
        );
        await pendingInviteRepo.savePendingInvite(expiredInvite);

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        expect(
          find.byKey(const ValueKey('pending-group-invite-grp-expired')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'E: a half-materialized group (rejoin row, attempt < cap) shows the "Joining…" badge',
      (tester) async {
        await groupRepo.saveGroup(
          makeGroup(id: 'grp-joining', name: 'Joining Group'),
        );
        await groupRepo.recordGroupRejoinFailure(
          'grp-joining',
          nextEligibleAt: DateTime.now().toUtc().add(const Duration(seconds: 30)),
        );

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        expect(find.text('Joining…'), findsOneWidget);
        expect(find.text("Couldn't join — retry"), findsNothing);
      },
    );

    testWidgets(
      'E: a group that has hit the rejoin attempt cap shows the "Couldn\'t join — retry" badge and is NOT removed',
      (tester) async {
        await groupRepo.saveGroup(
          makeGroup(id: 'grp-stuck', name: 'Stuck Group'),
        );
        for (var i = 0; i < 10; i++) {
          await groupRepo.recordGroupRejoinFailure(
            'grp-stuck',
            nextEligibleAt: DateTime.now().toUtc(),
          );
        }

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        expect(find.text("Couldn't join — retry"), findsOneWidget);
        // Give-up must never hard-delete the group (it holds the key).
        expect(await groupRepo.getGroup('grp-stuck'), isNotNull);
      },
    );

    testWidgets(
      'refreshes pending invite list when pending invite stream emits',
      (tester) async {
        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        expect(find.text('Writers'), findsNothing);

        final invite = makePendingInvite(
          groupId: 'grp-new',
          groupName: 'Writers',
        );
        await pendingInviteRepo.savePendingInvite(invite);
        pendingInviteStreamController.add(invite);
        await pumpFrames(tester, count: 20);

        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsOneWidget,
        );
        expect(find.text('Writers'), findsOneWidget);
      },
    );

    testWidgets(
      'GL-005 renders only persisted groups and valid pending invites, not public preview stream events',
      (tester) async {
        final activeGroup = makeGroup(id: 'g-active', name: 'Active Private');
        await groupRepo.saveGroup(activeGroup);

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        expect(find.text('Active Private'), findsOneWidget);
        expect(find.text('Public Catalog Group'), findsNothing);
        expect(find.text('Public Preview Invite'), findsNothing);

        inviteStreamController.add(
          makeGroup(id: 'g-public-preview', name: 'Public Catalog Group'),
        );
        pendingInviteStreamController.add(
          makePendingInvite(
            groupId: 'grp-public-preview',
            groupName: 'Public Preview Invite',
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.text('Active Private'), findsOneWidget);
        expect(find.text('Public Catalog Group'), findsNothing);
        expect(find.text('Public Preview Invite'), findsNothing);
        expect(
          find.byKey(const ValueKey('pending-group-invite-grp-public-preview')),
          findsNothing,
        );

        final validInvite = makePendingInvite(
          groupId: 'grp-valid-private',
          groupName: 'Valid Private Invite',
        );
        await pendingInviteRepo.savePendingInvite(validInvite);
        pendingInviteStreamController.add(validInvite);
        await pumpFrames(tester, count: 20);

        expect(find.text('Active Private'), findsOneWidget);
        expect(find.text('Valid Private Invite'), findsOneWidget);
        expect(
          find.byKey(ValueKey('pending-group-invite-${validInvite.groupId}')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'accepting a pending invite joins the group and removes the row',
      (tester) async {
        final backlogTimestamp = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 5))
            .toIso8601String();
        final reactionTimestamp = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 4))
            .toIso8601String();
        final invite = makePendingInvite();
        final reactionRepo = FakeReactionRepository();
        final replayListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => testIdentity.peerId,
          reactionRepo: reactionRepo,
        );
        addTearDown(replayListener.dispose);
        await pendingInviteRepo.savePendingInvite(invite);
        final offlineMessage = await makeSignedReplayInboxMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: invite.groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintextPayload: {
            'groupId': invite.groupId,
            'messageId': 'offline-msg-1',
            'senderId': '12D3KooWAlice',
            'senderUsername': 'Alice',
            'keyEpoch': 1,
            'text': 'Welcome back',
            'timestamp': backlogTimestamp,
          },
          messageId: 'offline-msg-1',
        );
        final offlineReaction = await makeSignedReplayInboxMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: invite.groupId,
          payloadType: groupOfflineReplayPayloadTypeReaction,
          plaintextPayload: {
            'id': 'invite-reaction-1',
            'messageId': 'offline-msg-1',
            'emoji': '👍',
            'action': 'add',
            'senderPeerId': '12D3KooWAlice',
            'timestamp': reactionTimestamp,
          },
          messageId: 'invite-reaction-1',
        );
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [offlineMessage, offlineReaction],
          'cursor': '',
        };

        await tester.pumpWidget(
          buildWidget(
            groupMessageListener: replayListener,
            reactionRepo: reactionRepo,
          ),
        );
        await pumpFrames(tester);

        final acceptFinder = find.byKey(
          ValueKey('pending-group-invite-accept-${invite.groupId}'),
        );
        expect(tester.widget<FilledButton>(acceptFinder).onPressed, isNotNull);
        await tester.tap(
          acceptFinder,
        );
        await pumpFrames(tester, count: 30);

        // B1: a successful accept auto-opens the group conversation.
        expect(find.byType(GroupConversationScreen), findsOneWidget);

        expect(p2pService.drainOfflineInboxCallCount, 1);
        expect(groupInviteListener.waitForIdleCallCount, 1);
        expect(bridge.commandLog, contains('group:join'));
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNull,
        );
        expect(await groupRepo.getGroup(invite.groupId), isNotNull);
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsNothing,
        );
        expect(find.text('Book Club'), findsAtLeastNWidgets(1));
        // 208: a navigating accept shows NO confirmation snackbar.
        expect(find.byType(SnackBar), findsNothing);
        expect(await msgRepo.getMessage('offline-msg-1'), isNotNull);

        final reactions = await reactionRepo.getReactionsForMessage(
          'offline-msg-1',
        );
        expect(reactions, hasLength(1));
        expect(reactions.single.senderPeerId, '12D3KooWAlice');
        expect(reactions.single.emoji, '👍');
      },
    );

    testWidgets(
      'A2: accepting a freshness-stale (card-valid) invite shows the ask-resend prompt, not the invalid string',
      (tester) async {
        // The card TTL is anchored at receivedAt (+7d); the membership
        // freshness proof is anchored ~6h earlier. Choosing receivedAt ~6d21h
        // ago leaves the card valid (~3h) while the proof is ~3h stale, so the
        // real acceptPendingGroupInvite returns expiredFreshness (not expired,
        // not invalidPayload).
        final invite = makePendingInvite(
          receivedAt: DateTime.now().toUtc().subtract(
            const Duration(days: 6, hours: 21),
          ),
        );
        await pendingInviteRepo.savePendingInvite(invite);

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        final acceptFinder = find.byKey(
          ValueKey('pending-group-invite-accept-${invite.groupId}'),
        );
        // Card is not expired, so accept stays enabled.
        expect(tester.widget<FilledButton>(acceptFinder).onPressed, isNotNull);
        await tester.tap(acceptFinder);
        await pumpFrames(tester, count: 30);

        expect(
          find.text(
            'This invite has expired. Ask the group admin to send a fresh one.',
          ),
          findsOneWidget,
        );
        expect(find.text('Invite is no longer valid'), findsNothing);
        expect(await groupRepo.getGroup(invite.groupId), isNull);
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNull,
        );
      },
    );

    testWidgets(
      'accept retries rollback until latest metadata is recovered',
      (tester) async {
        final invite = makePendingInvite(
          groupId: 'grp-stale-retry',
          groupName: 'test 2',
        );
        await pendingInviteRepo.savePendingInvite(invite);
        final replayListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => testIdentity.peerId,
        );
        addTearDown(replayListener.dispose);

        final latestMetadataAt = DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 5));
        final latestMetadata = await makeSignedMetadataReplayInboxMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: invite.groupId,
          updatedAt: latestMetadataAt,
          name: 'test 3',
          description: '333',
          messageId: 'metadata-after-rollback',
        );
        bridge.responseSequences['group:inboxRetrieveCursor'] = [
          for (var i = 0; i < 4; i++)
            {
              'ok': false,
              'errorCode': 'RELAY_UNAVAILABLE',
              'errorMessage': 'relay unavailable',
            },
          {
            'ok': true,
            'messages': [latestMetadata],
            'cursor': '',
          },
        ];

        await tester.pumpWidget(
          buildWidget(groupMessageListener: replayListener),
        );
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(ValueKey('pending-group-invite-accept-${invite.groupId}')),
        );
        await pumpFrames(tester, count: 90);

        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNull,
        );
        final group = await groupRepo.getGroup(invite.groupId);
        expect(group, isNotNull);
        expect(group!.name, 'test 3');
        expect(group.description, '333');
        expect(group.lastMetadataEventAt, latestMetadataAt);
        expect(p2pService.drainOfflineInboxCallCount, 2);
        expect(groupInviteListener.waitForIdleCallCount, 2);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:join'),
          hasLength(2),
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxRetrieveCursor'),
          hasLength(5),
        );
        // 208: a navigating accept shows NO confirmation snackbar.
        expect(find.byType(SnackBar), findsNothing);
        expect(
          find.text('Invite accepted, but recovery is still catching up'),
          findsNothing,
        );
        expect(find.text('Failed to accept invite'), findsNothing);
      },
    );

    testWidgets(
      'EK011 accepts a key-package-bound pending invite through wired local package id',
      (tester) async {
        const localDeviceId = 'peer-admin-device-1';
        p2pService.emitState(
          const NodeState(peerId: localDeviceId, isStarted: true),
        );
        final invite = makePendingInvite(
          groupId: 'grp-package-accept',
          groupName: 'Package Room',
          recipientDeviceId: localDeviceId,
        );
        await pendingInviteRepo.savePendingInvite(invite);

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(ValueKey('pending-group-invite-accept-${invite.groupId}')),
        );
        await pumpFrames(tester, count: 30);

        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNull,
        );
        expect(await groupRepo.getGroup(invite.groupId), isNotNull);
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsNothing,
        );
        expect(find.text('Package Room'), findsOneWidget);
        // 208: a navigating accept shows NO confirmation snackbar.
        expect(find.byType(SnackBar), findsNothing);

        final tombstone = await pendingInviteRepo.getWelcomeKeyPackageTombstone(
          packageId: defaultGroupWelcomeKeyPackageIdForDevice(localDeviceId)!,
          recipientDeviceId: localDeviceId,
          groupId: invite.groupId,
        );
        expect(tombstone, isNotNull);
        expect(tombstone!.inviteId, invite.inviteId);
      },
    );

    // TC-03 (plan 150; reversed by 208) — the shape-b path
    // `(bridgeError, group != null)` at use-case :562-566. It NAVIGATES into
    // the materialized group and (per 208) surfaces NO snackbar — the former
    // navigate-time `group_invite_joined_recovery` confirmation toast is
    // removed. It must still take the success-like path, never the generic
    // "Failed to accept invite".
    testWidgets(
      'TC-03 bridgeError with materialized group navigates and reports '
      'join-with-recovery (not failure)',
      (tester) async {
        // 106 contract: an INLINE invite carries the full group config + key,
        // so a relay-side join/drain failure still materializes the group
        // locally and CONSUMES the invite — background recovery finishes the
        // drain later. The success-like `(bridgeError, group)` shape.
        final invite = makePendingInvite();
        await pendingInviteRepo.savePendingInvite(invite);
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'JOIN_FAILED',
        };
        bridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'PUBLISH_FAILED',
        };
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
        };

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(ValueKey('pending-group-invite-accept-${invite.groupId}')),
        );
        // Shape-b (group != null) does NOT enter the 5×500ms recovery loop
        // (the loop guard requires group == null), so the switch fires early —
        // right after the use-case's own ≤4×250ms inbox drains. Pump only
        // enough to settle that attempt + the navigation, so the assertions
        // below run WHILE the default-duration recovery snackbar is still
        // visible (NOT relying on a hard-coded long snackbar window).
        await pumpUntil(
          tester,
          () => find.byType(GroupConversationScreen).evaluate().isNotEmpty,
        );

        // Invite consumed + group materialized (parity with the old sentinel).
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNull,
        );
        expect(await groupRepo.getGroup(invite.groupId), isNotNull);
        expect(await groupRepo.getLatestKey(invite.groupId), isNotNull);
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsNothing,
        );

        // NEW (TC-03 / INV-3): shape-b NAVIGATES into the conversation — the
        // cleanest discriminator that `_onGroupTap` fired.
        expect(find.byType(GroupConversationScreen), findsOneWidget);

        // 208: the shape-b (join-with-recovery) navigating accept shows NO
        // snackbar — the recovery confirmation toast is intentionally removed.
        // The card is consumed/gone, so nothing renders inline either.
        expect(find.byType(SnackBar), findsNothing);
        // Still the success-like path — never the generic failure copy.
        expect(find.text('Failed to accept invite'), findsNothing);

        // Drain any remaining in-flight timers (snackbar auto-dismiss, the
        // backgrounded GroupConversationWired's own startup work) so there is
        // no "A Timer is still pending after the widget tree was disposed"
        // teardown error.
        await pumpFrames(tester, count: 220);
      },
    );

    // TC-02 (plan 150) — a keep-pending bridgeError (shape a: group == null,
    // invite still present) exposes an inline Retry that re-enters
    // `_onAcceptPendingInvite` THROUGH the `_processingInviteIds` guard. A
    // key-package-bound invite rolls back to retryable on a join failure (the
    // EK011 companion shape), keeping the live card + invite.
    testWidgets(
      'TC-02 bridgeError keep-pending accept shows an inline Retry that '
      're-runs accept through the guard',
      (tester) async {
        const localDeviceId = 'peer-admin-device-1';
        p2pService.emitState(
          const NodeState(peerId: localDeviceId, isStarted: true),
        );
        final invite = makePendingInvite(
          groupId: 'grp-retryable',
          groupName: 'Retry Room',
          recipientDeviceId: localDeviceId,
        );
        await pendingInviteRepo.savePendingInvite(invite);
        // Join fails for a key-package-bound invite → rollback → retryable
        // shape-a (group == null, invite kept).
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'JOIN_FAILED',
        };
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
        };

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(ValueKey('pending-group-invite-accept-${invite.groupId}')),
        );
        // The recovery-retry wrapper runs up to 5×500ms re-attempts; pump past
        // the FULL loop so the outcome settles on the stable keep-pending
        // shape-a `(bridgeError, null)` (a shorter pump catches an in-flight
        // attempt mid-materialization where the group is transiently persisted).
        await pumpFrames(tester, count: 220);

        // Invite KEPT (rollback returned without committing).
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNotNull,
        );
        expect(await groupRepo.getGroup(invite.groupId), isNull);
        // Live card still present.
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsOneWidget,
        );
        // RED on HEAD: there is no inline Retry control today (generic snackbar
        // path), so this key finds nothing.
        final retryFinder = find.byKey(
          ValueKey('pending-group-invite-retry-${invite.groupId}'),
        );
        expect(retryFinder, findsOneWidget);
        // No generic failure snackbar on the keep-pending path.
        expect(find.text('Failed to accept invite'), findsNothing);

        // INV-2 guard lock (strengthened from a single-tap greaterThan, which a
        // guard bypass survived — M3). `loadIdentity` is called EXACTLY ONCE per
        // `_onAcceptPendingInvite` entry (the recovery-retry wrapper re-attempts
        // without reloading), so it is a clean per-accept-pass counter.
        //
        // A RAPID DOUBLE tap of Retry WITHOUT pumping to settle between the two
        // taps: `_onAcceptPendingInvite` adds the id to `_processingInviteIds`
        // SYNCHRONOUSLY (before its first await), so the second tap — dispatched
        // in the same frame, before any await yields — hits the contains-check
        // and returns. With the guard intact: double-tap == exactly ONE fresh
        // accept pass (+1 loadIdentity). With a guard bypass: double-tap == TWO
        // passes (+2). The EQUALITY (not greaterThan) is what re-reds M3.
        final passesBeforeRetry = identityRepo.loadIdentityCallCount;
        await tester.tap(retryFinder);
        await tester.tap(retryFinder, warnIfMissed: false);
        await tester.pump();
        // Drain the re-entered accept's preserved 5×500ms recovery loop + the
        // use-case's own 250ms inbox-drain timers (parity with the 220-frame
        // first-accept above) so no raw timer is pending at teardown.
        await pumpFrames(tester, count: 220);
        final passesAfterRetry = identityRepo.loadIdentityCallCount;
        expect(
          passesAfterRetry - passesBeforeRetry,
          1,
          reason:
              'inline Retry must re-run accept EXACTLY ONCE for a rapid '
              'double-tap — the second concurrent tap hits the '
              '_processingInviteIds guard and arms no fresh pass',
        );
        // The single re-run still armed a fresh accept (sanity: not zero) — a
        // real join attempt went out on the re-entered pass.
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:join'),
          isNotEmpty,
        );
      },
    );

    testWidgets(
      'accept drains all inbox cursor pages before clearing spinner',
      (tester) async {
        final invite = makePendingInvite(
          groupId: 'grp-cursor-pending',
          groupName: 'Cursor Room',
        );
        await pendingInviteRepo.savePendingInvite(invite);
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': const [],
          'cursor': 'repeat-cursor',
        };

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(ValueKey('pending-group-invite-accept-${invite.groupId}')),
        );
        await pumpFrames(tester, count: 30);

        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNull,
        );
        expect(await groupRepo.getGroup(invite.groupId), isNotNull);
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsNothing,
        );
        expect(find.text('Cursor Room'), findsOneWidget);
        // 208: a navigating accept shows NO confirmation snackbar.
        expect(find.byType(SnackBar), findsNothing);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxRetrieveCursor'),
          hasLength(2),
        );
      },
    );

    // TC-04 (plan 150) — rewrite of the prior repairPending test (was
    // ":1250 repair-pending accept keeps the invite row and shows key-material
    // warning", which asserted the TRANSIENT `group_invite_needs_key`
    // snackbar). repairPending KEEPS the invite, so the live card renders an
    // inline "Waiting for key" state instead of a snackbar.
    testWidgets(
      'TC-04 repair-pending accept shows an inline "Waiting for key" row and '
      'no snackbar',
      (tester) async {
        final invite = makePendingInvite(overrideGroupKey: '');
        await pendingInviteRepo.savePendingInvite(invite);

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(ValueKey('pending-group-invite-accept-${invite.groupId}')),
        );
        await pumpFrames(tester, count: 30);

        // Invite KEPT + group not joined (unchanged from the old sentinel).
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNotNull,
        );
        expect(await groupRepo.getGroup(invite.groupId), isNull);
        // Live card still present (unchanged from old :1270).
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsOneWidget,
        );
        // NEW (TC-04 / INV-4): inline "Waiting for key" rendered INSIDE the
        // live card (RED on HEAD: no inline state, only a snackbar).
        expect(
          find.descendant(
            of: find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
            matching: find.text('Waiting for key'),
          ),
          findsOneWidget,
        );
        // The transient `group_invite_needs_key` snackbar copy is GONE.
        expect(find.text('Invite needs fresh key material'), findsNothing);
        // And there is no snackbar at all for this non-navigating outcome.
        expect(find.byType(SnackBar), findsNothing);
        // repairPending must NOT navigate (preserve :1278/:1311 intent).
        expect(find.byType(GroupConversationScreen), findsNothing);
        // group:join still not called (preserved from old :1274).
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    // TC-09 (plan 150) — derived `_inviteRowOutcomes` is in-memory and cleared
    // on `_loadGroups`; after a resume a repairPending invite re-renders from
    // the repo as a plain idle accept/decline card (no stale "Waiting for
    // key", no ghost row). The invite itself stays KEPT.
    testWidgets(
      'TC-09 repairPending row reverts to idle accept card after resume '
      '(lifecycle)',
      (tester) async {
        final invite = makePendingInvite(overrideGroupKey: '');
        await pendingInviteRepo.savePendingInvite(invite);

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(ValueKey('pending-group-invite-accept-${invite.groupId}')),
        );
        await pumpFrames(tester, count: 30);

        // Precondition: TC-04 state is present.
        expect(
          find.descendant(
            of: find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
            matching: find.text('Waiting for key'),
          ),
          findsOneWidget,
        );

        // Simulate a resume: the lifecycle observer re-runs `_loadGroups`,
        // which clears the derived row outcomes.
        WidgetsBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        // The resume `_loadGroups` is UNawaited (fire-and-forget), so a fixed
        // pump count can race the reload. Pump-until the row has reverted to
        // the plain idle card (bounded): the accept key is present AND the
        // stale "Waiting for key" inline state has been cleared by the reload.
        // (The accept key alone is not a sufficient settle signal — it stays
        // visible on the kept repairPending card even while "Waiting for key"
        // still shows.)
        await pumpUntil(
          tester,
          () =>
              find
                  .byKey(
                    ValueKey(
                      'pending-group-invite-accept-${invite.groupId}',
                    ),
                  )
                  .evaluate()
                  .isNotEmpty &&
              find.text('Waiting for key').evaluate().isEmpty,
        );

        // The invite is still KEPT in the repo.
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNotNull,
        );
        // Back to a plain idle accept/decline card.
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            ValueKey('pending-group-invite-accept-${invite.groupId}'),
          ),
          findsOneWidget,
        );
        // No stale "Waiting for key" state, no terminal ghost row.
        expect(find.text('Waiting for key'), findsNothing);
        expect(
          find.byKey(
            ValueKey('pending-group-invite-outcome-${invite.groupId}'),
          ),
          findsNothing,
        );
      },
    );

    // TC-01 (plan 150) — data-driven over terminal results. Every terminal arm
    // `deletePendingInvite`s in the use-case and `_loadGroups()` runs BEFORE
    // the switch, so the live `pending-group-invite-<id>` card is GONE after
    // the tap (Root Cause C1). The reason therefore renders on an
    // outcome-driven GHOST row keyed `pending-group-invite-outcome-<id>`, never
    // on the deleted card, and with NO snackbar.
    //
    // Driven over the cleanly-reachable terminal subset — terminals whose
    // accept stays ENABLED on the card (invite is NOT card-expired and its
    // group is NOT pre-joined, so the card is tappable) AND that the use-case
    // resolves to the terminal arm purely from repo/device state, no brittle
    // payload corruption. That is: revoked, alreadyUsed, wrongIdentity,
    // expiredFreshness. All four share the SAME ghost-row code path, so the
    // contract is fully exercised.
    //
    // PRUNED terminals (NOT a tappable enabled-accept path; covered by the
    // use-case's own tests instead):
    //   • notFound — the use-case returns notFound ONLY when the invite is
    //     ABSENT at accept time (use-case :162 getPendingInvite == null). An
    //     absent invite means there is no PendingGroupInviteCard to tap, so
    //     notFound is unreachable through an enabled-accept UI tap. (Verified:
    //     deleting the invite before the tap removes the accept key and
    //     `tester.tap` errors on a missing widget, not the ghost-row contract.)
    //   • duplicateGroup — requires a same-id group to already exist locally
    //     (materialize :848 returns duplicateGroup only when getGroup != null &
    //     self is an active member; the retry path :627-629 needs the same
    //     pre-saved group). But `_loadGroups`' B2 filter
    //     (visibleInvites = pendingInvites.where(!joinedGroupIds.contains(id)))
    //     HIDES the invite card whenever a group with that id is already
    //     joined → there is no card to tap. duplicateGroup is therefore not
    //     reachable via an enabled accept tap and is pruned.
    //   • expired (hard-expiry) — the card DISABLES accept when
    //     invite.isExpiredAt(now) (pending_group_invite_card :140 gates
    //     onPressed on isExpired), so an expired invite has no tappable accept.
    //     The freshness-stale arm (expiredFreshness) is the reachable sibling
    //     (card stays enabled because expiry checks expiresAt only, while the
    //     freshness proof ages out independently) and is covered below.
    //   • invalidPayload — every invalidPayload seam is either card-hidden
    //     (stale-against-local needs a pre-saved same-id group → B2 filter) or
    //     requires brittle signature/payload corruption; use-case-covered, not
    //     reproduced at the wired tier.
    final terminalCases = <Map<String, dynamic>>[
      {
        'label': 'revoked',
        'groupId': 'grp-term-revoked',
        'reason': 'Invite was revoked',
        'arrange': (InMemoryPendingGroupInviteRepository repo,
            PendingGroupInvite inv) async {
          final now = DateTime.now().toUtc();
          await repo.saveRevokedInvite(
            GroupInviteRevocation(
              inviteId: inv.inviteId,
              groupId: inv.groupId,
              revokedAt: now.subtract(const Duration(minutes: 1)),
              expiresAt: now.add(const Duration(days: 7)),
            ),
          );
        },
      },
      {
        'label': 'alreadyUsed',
        'groupId': 'grp-term-used',
        'reason': 'Invite already used',
        'arrange': (InMemoryPendingGroupInviteRepository repo,
            PendingGroupInvite inv) async {
          final now = DateTime.now().toUtc();
          await repo.saveConsumedInvite(
            GroupInviteConsumption(
              inviteId: inv.inviteId,
              groupId: inv.groupId,
              consumedAt: now.subtract(const Duration(minutes: 1)),
              expiresAt: now.add(const Duration(days: 7)),
            ),
          );
        },
      },
      {
        'label': 'wrongIdentity',
        'groupId': 'grp-term-wrong',
        'reason': 'Invite is for another identity',
        // The invite is device-bound to `invite-device-A`, but the local node
        // identity is a DIFFERENT device (`peer-admin-device-B`, emitted
        // below). The handler passes ownDeviceId = currentState.peerId, so
        // isBoundToRecipientDevice fails on the device mismatch → wrongIdentity
        // (use-case :331). The card is NOT expired → accept stays enabled.
        'recipientDeviceId': 'invite-device-A',
        'localDeviceId': 'peer-admin-device-B',
        'arrange': (InMemoryPendingGroupInviteRepository repo,
            PendingGroupInvite inv) async {},
      },
      {
        'label': 'expiredFreshness',
        'groupId': 'grp-abc123',
        'reason':
            'This invite has expired. Ask the group admin to send a fresh one.',
        // The A2 seam: receivedAt ~6d21h ago leaves the card valid (accept
        // enabled) while the freshness proof has aged out → expiredFreshness.
        'receivedAtDaysHours': const Duration(days: 6, hours: 21),
        'arrange': (InMemoryPendingGroupInviteRepository repo,
            PendingGroupInvite inv) async {},
      },
    ];

    for (final tc in terminalCases) {
      final label = tc['label'] as String;
      testWidgets(
        'TC-01 terminal accept outcome shows an inline reason GHOST row and '
        'no snackbar ($label)',
        (tester) async {
          final groupId = tc['groupId'] as String;
          final receivedAt = tc.containsKey('receivedAtDaysHours')
              ? DateTime.now()
                  .toUtc()
                  .subtract(tc['receivedAtDaysHours'] as Duration)
              : null;
          final invite = makePendingInvite(
            groupId: groupId,
            groupName: 'Terminal $label',
            receivedAt: receivedAt,
            recipientDeviceId: tc['recipientDeviceId'] as String?,
          );
          await pendingInviteRepo.savePendingInvite(invite);
          if (tc.containsKey('localDeviceId')) {
            // Bring up a local node whose device id deliberately mismatches the
            // invite's bound recipient device (drives wrongIdentity).
            p2pService.emitState(
              NodeState(
                peerId: tc['localDeviceId'] as String,
                isStarted: true,
              ),
            );
          }
          await (tc['arrange'] as Future<void> Function(
            InMemoryPendingGroupInviteRepository,
            PendingGroupInvite,
          ))(pendingInviteRepo, invite);

          await tester.pumpWidget(buildWidget());
          await pumpFrames(tester);

          await tester.tap(
            find.byKey(
              ValueKey('pending-group-invite-accept-$groupId'),
            ),
          );
          await pumpFrames(tester, count: 30);

          // C1: the live card is GONE (the use-case deleted the invite and
          // `_loadGroups` removed it before the switch ran).
          expect(
            find.byKey(ValueKey('pending-group-invite-$groupId')),
            findsNothing,
          );
          // The reason renders on the GHOST row (RED on HEAD: no such row).
          final ghostKey = ValueKey('pending-group-invite-outcome-$groupId');
          expect(find.byKey(ghostKey), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(ghostKey),
              matching: find.text(tc['reason'] as String),
            ),
            findsOneWidget,
          );
          // Distinct-event discriminator: inline ghost row, NOT a toast.
          expect(find.byType(SnackBar), findsNothing);
        },
      );
    }

    // TC-05 (plan 150; note 208) — scoped no-snackbar lock over the
    // NON-navigating outcomes: a representative terminal (notFound) +
    // repairPending + a keep-pending bridgeError each leave NO SnackBar. Since
    // 208 the navigating outcomes (success / joinedRecovery) ALSO show no
    // snackbar (locked by TC-08 / TC-03); this lock stays scoped to the
    // non-navigating rows.
    testWidgets(
      'TC-05 no accept snackbar for any non-navigating outcome (lock)',
      (tester) async {
        // (a) terminal: revoked — a tap-reachable terminal (the card stays
        // enabled because the invite is not card-expired; the revocation makes
        // the use-case return `revoked`). Using `notFound` here is NOT viable:
        // notFound requires the invite to be ABSENT at tap time, which removes
        // the accept key and makes `tester.tap` error instead of exercising the
        // no-snackbar lock.
        final terminal = makePendingInvite(
          groupId: 'grp-lock-term',
          groupName: 'Lock Terminal',
        );
        await pendingInviteRepo.savePendingInvite(terminal);
        final revokeNow = DateTime.now().toUtc();
        await pendingInviteRepo.saveRevokedInvite(
          GroupInviteRevocation(
            inviteId: terminal.inviteId,
            groupId: terminal.groupId,
            revokedAt: revokeNow.subtract(const Duration(minutes: 1)),
            expiresAt: revokeNow.add(const Duration(days: 7)),
          ),
        );

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(
            ValueKey('pending-group-invite-accept-${terminal.groupId}'),
          ),
        );
        await pumpFrames(tester, count: 30);
        expect(find.byType(SnackBar), findsNothing);
        // Positive render so an all-empty tree cannot satisfy the lock: the
        // terminal leg actually produced its ghost row.
        expect(
          find.byKey(
            ValueKey('pending-group-invite-outcome-${terminal.groupId}'),
          ),
          findsOneWidget,
        );

        // (b) repairPending.
        final repair = makePendingInvite(
          groupId: 'grp-lock-repair',
          groupName: 'Lock Repair',
          overrideGroupKey: '',
        );
        await pendingInviteRepo.savePendingInvite(repair);
        pendingInviteStreamController.add(repair);
        await pumpFrames(tester, count: 20);
        await tester.tap(
          find.byKey(
            ValueKey('pending-group-invite-accept-${repair.groupId}'),
          ),
        );
        await pumpFrames(tester, count: 30);
        expect(find.byType(SnackBar), findsNothing);
        // Positive render: the repairPending leg actually showed its inline
        // "Waiting for key" state on the kept card.
        expect(
          find.descendant(
            of: find.byKey(ValueKey('pending-group-invite-${repair.groupId}')),
            matching: find.text('Waiting for key'),
          ),
          findsOneWidget,
        );

        // (c) keep-pending bridgeError (key-package-bound rollback → retryable).
        const localDeviceId = 'peer-admin-device-1';
        p2pService.emitState(
          const NodeState(peerId: localDeviceId, isStarted: true),
        );
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'JOIN_FAILED',
        };
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
        };
        final retryable = makePendingInvite(
          groupId: 'grp-lock-retry',
          groupName: 'Lock Retry',
          recipientDeviceId: localDeviceId,
        );
        await pendingInviteRepo.savePendingInvite(retryable);
        pendingInviteStreamController.add(retryable);
        await pumpFrames(tester, count: 20);
        await tester.tap(
          find.byKey(
            ValueKey('pending-group-invite-accept-${retryable.groupId}'),
          ),
        );
        // Keep-pending bridgeError runs the preserved 5×500ms recovery loop
        // (each pass re-invokes the use-case's 250ms inbox-drain retry). Pump
        // past the full loop so no raw use-case drain timer is pending at
        // teardown; the no-snackbar assertion is unchanged.
        await pumpFrames(tester, count: 220);
        expect(find.byType(SnackBar), findsNothing);
        // Positive render: the keep-pending bridgeError leg actually exposed its
        // inline Retry control on the kept card.
        expect(
          find.byKey(
            ValueKey('pending-group-invite-retry-${retryable.groupId}'),
          ),
          findsOneWidget,
        );
      },
    );

    // TC-06 (plan 150) — stuck-rejoin Retry drops the redundant
    // `group_joining_in_progress` ("Joining…") snackbar; the inline badge keeps
    // updating and the rejoin pass still runs. Mirrors the stuck setup of the
    // ":791 … attempt cap … badge" sentinel.
    testWidgets(
      'TC-06 stuck-rejoin Retry updates the inline badge without a snackbar',
      (tester) async {
        final group = makeGroup(id: 'g-1', name: 'Stuck Group');
        await groupRepo.saveGroup(group);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'g-1',
            keyGeneration: 1,
            encryptedKey: 'key-base64',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        final future = DateTime.now().toUtc().add(const Duration(days: 1));
        for (var i = 0; i < 11; i++) {
          await groupRepo.recordGroupRejoinFailure(
            'g-1',
            nextEligibleAt: future,
          );
        }

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        // Inline badge present (sentinel parity with :807).
        expect(find.text("Couldn't join — retry"), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('group-stuck-retry-g-1')));
        await pumpFrames(tester, count: 20);

        // RED on HEAD: `_onRetryStuckRejoin` shows the "Joining…" snackbar.
        expect(find.byType(SnackBar), findsNothing);
        // The rejoin pass still ran (force-eligible + rejoin → group:join).
        expect(bridge.commandLog, contains('group:join'));
      },
    );

    // TC-08 (plan 150; reversed by 208) — preservation: a success accept
    // removes the row and NAVIGATES, and (per 208) shows NO snackbar. Guards
    // the switch rewrite against dropping the navigate arm. Mirrors
    // EK011/cursor.
    testWidgets(
      'TC-08 success accept still navigates and removes the row (preservation)',
      (tester) async {
        const localDeviceId = 'peer-admin-device-1';
        p2pService.emitState(
          const NodeState(peerId: localDeviceId, isStarted: true),
        );
        final invite = makePendingInvite(
          groupId: 'grp-success-preserve',
          groupName: 'Preserve Room',
          recipientDeviceId: localDeviceId,
        );
        await pendingInviteRepo.savePendingInvite(invite);

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(ValueKey('pending-group-invite-accept-${invite.groupId}')),
        );
        await pumpFrames(tester, count: 30);

        // Row removed + group joined + navigated.
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNull,
        );
        expect(await groupRepo.getGroup(invite.groupId), isNotNull);
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsNothing,
        );
        expect(find.byType(GroupConversationScreen), findsOneWidget);
        // 208: a navigating accept shows NO confirmation snackbar.
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets(
      'IJ014 repairable join-material failure keeps pending invite visible',
      (tester) async {
        final invite = makePendingInvite();
        await pendingInviteRepo.savePendingInvite(invite);
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'WELCOME_DECRYPT_FAILED',
          'errorMessage': 'undecryptable welcome key material',
        };

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(ValueKey('pending-group-invite-accept-${invite.groupId}')),
        );
        await pumpFrames(tester, count: 30);

        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNotNull,
        );
        expect(await groupRepo.getGroup(invite.groupId), isNull);
        expect(await groupRepo.getLatestKey(invite.groupId), isNull);
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsOneWidget,
        );
        // TC-04 alignment: repairPending renders the inline "Waiting for key"
        // state inside the live card, not the transient snackbar copy.
        expect(
          find.descendant(
            of: find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
            matching: find.text('Waiting for key'),
          ),
          findsOneWidget,
        );
        expect(find.text('Invite needs fresh key material'), findsNothing);
        expect(bridge.commandLog, contains('group:join'));
        expect(bridge.commandLog, isNot(contains('group:inboxRetrieveCursor')));
        // B1 anti-regression: a non-success accept must NOT open a conversation.
        expect(find.byType(GroupConversationScreen), findsNothing);
      },
    );

    testWidgets(
      'declining optimistically hides the row but keeps the invite until the '
      'undo window elapses',
      (tester) async {
        final invite = makePendingInvite(
          groupId: 'grp-decline',
          groupName: 'Decline Me',
        );
        await pendingInviteRepo.savePendingInvite(invite);
        // 153: node up so the irreversible decline-ack actually reaches the
        // wire on commit. With a STOPPED node it short-circuits at
        // GROUP_INVITE_DECLINE_ACK_SEND_NODE_NOT_RUNNING and never calls
        // sendMessage, which would make the sendMessageCallCount assertions
        // below (and in the undo test) vacuous.
        p2pService.emitState(
          const NodeState(peerId: 'peer-local-decliner', isStarted: true),
        );

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(
            ValueKey('pending-group-invite-decline-${invite.groupId}'),
          ),
        );
        await pumpFrames(tester, count: 20); // 1000ms, well inside the 4s window

        // Optimistic: the row hides instantly and an Undo affordance shows,
        // but the local invite is NOT yet deleted (the commit is deferred).
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsNothing,
        );
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNotNull,
        );
        expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);

        // Past the 4s undo window (+1s margin) → the deferred commit fires.
        await tester.pump(const Duration(seconds: 5));
        await pumpFrames(tester, count: 10);

        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNull,
        );
        expect(await groupRepo.getGroup(invite.groupId), isNull);
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsNothing,
        );
        expect(find.text('Invite declined'), findsWidgets);
        expect(
          flowEvents
              .where((e) => e['event'] == 'GROUP_INVITE_DECLINE_COMMITTED')
              .length,
          1,
        );
        // 153: the decline-ack — the single irreversible side-effect — went on
        // the wire exactly once on commit (non-vacuous: the node is started, so
        // the send is not short-circuited at NODE_NOT_RUNNING).
        expect(
          flowEvents.any(
            (e) => e['event'] == 'GROUP_INVITE_DECLINE_ACK_SEND_START',
          ),
          isTrue,
        );
        expect(p2pService.sendMessageCallCount, 1);
      },
    );

    testWidgets(
      'undo cancels the decline — invite re-surfaces, ack never sent, never '
      'committed',
      (tester) async {
        final invite = makePendingInvite(
          groupId: 'grp-undo',
          groupName: 'Undo Me',
        );
        await pendingInviteRepo.savePendingInvite(invite);
        // 153: node up so a REAL commit WOULD put the decline-ack on the wire —
        // this is what makes the "ack never sent" assertions below meaningful
        // (with a stopped node they would pass even if the commit had fired).
        p2pService.emitState(
          const NodeState(peerId: 'peer-local-decliner', isStarted: true),
        );

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(
            ValueKey('pending-group-invite-decline-${invite.groupId}'),
          ),
        );
        await pumpFrames(tester, count: 10); // inside the window

        // Tap Undo before the window elapses.
        await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
        await pumpFrames(tester, count: 10);

        // The invite re-surfaces immediately.
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNotNull,
        );
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsOneWidget,
        );

        // Past the window: the commit must NOT fire — the invite stays.
        await tester.pump(const Duration(seconds: 5));
        await pumpFrames(tester, count: 10);

        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNotNull,
        );
        // The irreversible decline-ack was never put on the wire AND the ack
        // path never even started — proving the deferred commit was averted,
        // not merely short-circuited (node is running, so a real commit would
        // have emitted ACK_SEND_START and incremented sendMessageCallCount).
        expect(p2pService.sendMessageCallCount, 0);
        expect(
          flowEvents.any(
            (e) => e['event'] == 'GROUP_INVITE_DECLINE_ACK_SEND_START',
          ),
          isFalse,
        );
        expect(
          flowEvents.any(
            (e) =>
                e['event'] == 'GROUP_INVITE_DECLINE_UNDONE' &&
                (e['details'] as Map)['surface'] == 'group_list',
          ),
          isTrue,
        );
        expect(
          flowEvents.any(
            (e) => e['event'] == 'GROUP_INVITE_DECLINE_COMMITTED',
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      're-entrant load does not re-surface a hidden row; double-tap commits '
      'exactly once',
      (tester) async {
        final inviteA = makePendingInvite(
          groupId: 'grp-A',
          groupName: 'Group A',
        );
        final inviteB = makePendingInvite(
          groupId: 'grp-B',
          groupName: 'Group B',
        );
        await pendingInviteRepo.savePendingInvite(inviteA);
        await pendingInviteRepo.savePendingInvite(inviteB);

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        // Decline A twice in the same frame (double-tap), then force a
        // re-entrant reload via the pending-invite stream.
        final declineA = find.byKey(
          ValueKey('pending-group-invite-decline-${inviteA.groupId}'),
        );
        await tester.tap(declineA);
        await tester.tap(declineA, warnIfMissed: false);
        pendingInviteStreamController.add(inviteA);
        await pumpFrames(tester, count: 20); // inside the window

        // A is hidden and stays hidden through the reactive reload; B untouched.
        expect(
          find.byKey(ValueKey('pending-group-invite-${inviteA.groupId}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('pending-group-invite-${inviteB.groupId}')),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 5));
        await pumpFrames(tester, count: 10);

        // Exactly one commit despite the double-tap + re-entrant reload.
        expect(
          flowEvents
              .where((e) => e['event'] == 'GROUP_INVITE_DECLINE_COMMITTED')
              .length,
          1,
        );
        expect(
          await pendingInviteRepo.getPendingInvite(inviteA.groupId),
          isNull,
        );
        // B was never declined.
        expect(
          await pendingInviteRepo.getPendingInvite(inviteB.groupId),
          isNotNull,
        );
        expect(
          find.byKey(ValueKey('pending-group-invite-${inviteB.groupId}')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'disposing during the undo window cancels the pending commit (invite '
      'kept, no stray commit)',
      (tester) async {
        final invite = makePendingInvite(
          groupId: 'grp-dispose',
          groupName: 'Dispose Me',
        );
        await pendingInviteRepo.savePendingInvite(invite);

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(
            ValueKey('pending-group-invite-decline-${invite.groupId}'),
          ),
        );
        await pumpFrames(tester, count: 10); // inside the window

        // Dispose the screen before the window elapses.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
        await pumpFrames(tester, count: 5);

        // No setState-after-dispose crash, no commit, invite preserved.
        expect(tester.takeException(), isNull);
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNotNull,
        );
        expect(
          flowEvents.any(
            (e) => e['event'] == 'GROUP_INVITE_DECLINE_COMMITTED',
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      'a throwing commit releases the processing-id and re-surfaces the invite '
      '(finally cleanup)',
      (tester) async {
        // The deferred commit loads identity for the decline-ack; make that
        // throw so the commit fails AFTER the optimistic hide.
        identityRepo = _ThrowingIdentityRepository();
        final invite = makePendingInvite(
          groupId: 'grp-throw',
          groupName: 'Throw Me',
        );
        await pendingInviteRepo.savePendingInvite(invite);

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(
            ValueKey('pending-group-invite-decline-${invite.groupId}'),
          ),
        );
        await pumpFrames(tester, count: 10);

        // Fire the deferred commit, which throws.
        await tester.pump(const Duration(seconds: 5));
        await pumpFrames(tester, count: 10);

        // The invite re-surfaces, a failure snackbar shows, and the row is NOT
        // permanently stuck — declining it again is accepted.
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNotNull,
        );
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsOneWidget,
        );
        expect(find.text('Failed to decline invite'), findsWidgets);

        // Second decline of the same row is honoured (processing-id released).
        await tester.tap(
          find.byKey(
            ValueKey('pending-group-invite-decline-${invite.groupId}'),
          ),
        );
        await pumpFrames(tester, count: 10);
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a stale Undo tapped after the screen is gone is a safe no-op '
      '(no setState-after-dispose crash, no commit) [review P1]',
      (tester) async {
        final invite = makePendingInvite(groupId: 'grp-stale-undo');
        await pendingInviteRepo.savePendingInvite(invite);

        // Host GroupListWired under a toggle so it can be removed SYNCHRONOUSLY
        // (no route transition) while the app-level ScaffoldMessenger — and the
        // decline snackbar's Undo action — survives.
        final showScreen = ValueNotifier<bool>(true);
        addTearDown(showScreen.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ValueListenableBuilder<bool>(
              valueListenable: showScreen,
              builder: (_, show, _) => show
                  ? GroupListWired(
                      groupRepo: groupRepo,
                      msgRepo: msgRepo,
                      groupMessageListener: FakeGroupMessageListener(
                        messageStreamController.stream,
                      ),
                      bridge: bridge,
                      identityRepo: identityRepo,
                      contactRepo: contactRepo,
                      p2pService: p2pService,
                      groupInviteListener: groupInviteListener,
                    )
                  : const Scaffold(body: SizedBox()),
            ),
          ),
        );
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(
            ValueKey('pending-group-invite-decline-${invite.groupId}'),
          ),
        );
        await pumpFrames(tester, count: 10);
        expect(find.widgetWithText(SnackBarAction, 'Undo'), findsWidgets);

        // Tear GroupListWired down mid-window (synchronous dispose → its commit
        // timer is cancelled) while the snackbar's Undo lingers.
        showScreen.value = false;
        await pumpFrames(tester, count: 3);

        // Tapping the now-stale Undo must NOT crash (no setState after dispose)
        // and must NOT commit/undo.
        final undo = find.widgetWithText(SnackBarAction, 'Undo');
        if (undo.evaluate().isNotEmpty) {
          await tester.tap(undo.first, warnIfMissed: false);
          await pumpFrames(tester, count: 5);
        }
        await tester.pump(const Duration(seconds: 5));
        await pumpFrames(tester, count: 5);

        expect(tester.takeException(), isNull);
        // The deferred commit was cancelled by dispose → invite kept; nothing
        // committed.
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNotNull,
        );
        expect(
          flowEvents.any(
            (e) => e['event'] == 'GROUP_INVITE_DECLINE_COMMITTED',
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      'the Undo affordance disappears the moment the deferred commit starts '
      '(no stale no-op Undo during a slow commit) [review P2]',
      (tester) async {
        // A slow identity load holds the commit in-flight after the timer fires.
        identityRepo = _SlowIdentityRepository(identity: testIdentity);
        final invite = makePendingInvite(groupId: 'grp-slow-commit');
        await pendingInviteRepo.savePendingInvite(invite);

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(
            ValueKey('pending-group-invite-decline-${invite.groupId}'),
          ),
        );
        await pumpFrames(tester, count: 10);
        expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);

        // Advance past the 4s window so the commit fires; the use-case is slow
        // (2s) so the commit is still in-flight here. The Undo must already be
        // gone (the snackbar is dismissed the moment the commit fires) — a stale
        // no-op Undo must not linger during the commit. pumpFrames(10)=500ms is
        // enough for the dismiss animation but well short of the 2s commit.
        await tester.pump(const Duration(seconds: 4));
        await pumpFrames(tester, count: 10);
        expect(find.widgetWithText(SnackBarAction, 'Undo'), findsNothing);

        // Let the slow commit finish; the invite is then deleted.
        await tester.pump(const Duration(seconds: 3));
        await pumpFrames(tester, count: 5);
        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNull,
        );
      },
    );

    testWidgets('tapping group navigates to conversation', (tester) async {
      final g1 = makeGroup(id: 'g-1', name: 'Alpha Group');
      await groupRepo.saveGroup(g1);

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      // Tap the group card
      await tester.tap(find.text('Alpha Group'));
      await pumpFrames(tester, count: 20);

      // GroupConversationScreen should appear (inside GroupConversationWired)
      expect(find.byType(GroupConversationScreen), findsOneWidget);
    });

    testWidgets('shows unread counts', (tester) async {
      final g1 = makeGroup(id: 'g-1', name: 'Alpha Group');
      await groupRepo.saveGroup(g1);

      // Save 3 unread incoming messages (readAt = null)
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-1',
          groupId: 'g-1',
          text: 'Hello 1',
          isIncoming: true,
        ),
      );
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-2',
          groupId: 'g-1',
          text: 'Hello 2',
          isIncoming: true,
        ),
      );
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-3',
          groupId: 'g-1',
          text: 'Hello 3',
          isIncoming: true,
        ),
      );

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      // The unread badge should show "3"
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('loading skeleton replaced by empty state when no groups', (
      tester,
    ) async {
      // groupRepo is empty (no groups saved)
      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      expect(find.text('No groups yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('group-loading-row-0')), findsNothing);
    });

    testWidgets('load failure shows retryable error instead of empty state', (
      tester,
    ) async {
      final errorGroupRepo = _ThrowingGroupRepository();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupListWired(
            groupRepo: errorGroupRepo,
            msgRepo: msgRepo,
            groupMessageListener: FakeGroupMessageListener(
              messageStreamController.stream,
            ),
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            groupInviteListener: groupInviteListener,
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.byKey(const ValueKey('group-loading-row-0')), findsNothing);
      expect(find.text("Couldn't load groups"), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      expect(find.text('No groups yet'), findsNothing);

      expect(errorGroupRepo.getActiveGroupsCalls, 1);
      errorGroupRepo.holdNextFailure();
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();

      expect(find.byKey(const ValueKey('group-loading-row-0')), findsOneWidget);
      expect(errorGroupRepo.getActiveGroupsCalls, 2);

      errorGroupRepo.releaseNextFailure();
      await pumpFrames(tester);

      expect(find.text("Couldn't load groups"), findsOneWidget);
    });
  });
}

class _SlowGroupRepository extends InMemoryGroupRepository {
  final Completer<void> _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<List<GroupModel>> getActiveGroups() async {
    await _gate.future;
    return super.getActiveGroups();
  }
}

class _ThrowingGroupRepository extends InMemoryGroupRepository {
  int getActiveGroupsCalls = 0;
  Completer<void>? _nextFailureGate;

  void holdNextFailure() {
    _nextFailureGate = Completer<void>();
  }

  void releaseNextFailure() {
    final failureGate = _nextFailureGate;
    if (failureGate != null && !failureGate.isCompleted) {
      failureGate.complete();
    }
  }

  @override
  Future<List<GroupModel>> getActiveGroups() async {
    getActiveGroupsCalls += 1;
    final failureGate = _nextFailureGate;
    if (failureGate != null) {
      await failureGate.future;
      if (identical(_nextFailureGate, failureGate)) {
        _nextFailureGate = null;
      }
    }
    throw Exception('Simulated group loading error');
  }
}
