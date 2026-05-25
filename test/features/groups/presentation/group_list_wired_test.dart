import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
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

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
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
    });

    tearDown(() {
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
        expect(find.text('Book Club'), findsAtLeastNWidgets(1));
        expect(find.text('Joined Book Club'), findsOneWidget);
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
        expect(find.text('Joined Package Room'), findsOneWidget);

        final tombstone = await pendingInviteRepo.getWelcomeKeyPackageTombstone(
          packageId: defaultGroupWelcomeKeyPackageIdForDevice(localDeviceId)!,
          recipientDeviceId: localDeviceId,
          groupId: invite.groupId,
        );
        expect(tombstone, isNotNull);
        expect(tombstone!.inviteId, invite.inviteId);
      },
    );

    testWidgets(
      'bridgeError accept keeps the joined group and shows recovery warning',
      (tester) async {
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
        expect(await groupRepo.getGroup(invite.groupId), isNotNull);
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsOneWidget,
        );
        expect(find.text('Book Club'), findsAtLeastNWidgets(1));
        expect(
          find.text('Joined Book Club, but recovery is still catching up'),
          findsOneWidget,
        );
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));

        final latestMessage = await msgRepo.getLatestMessage(invite.groupId);
        expect(latestMessage, isNotNull);
        expect(latestMessage!.text, 'Admin joined the group');
      },
    );

    testWidgets(
      'accept clears spinner when inbox catch-up reports more cursor pages',
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
        expect(find.text('Joined Cursor Room'), findsOneWidget);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxRetrieveCursor'),
          hasLength(1),
        );
      },
    );

    testWidgets(
      'repair-pending accept keeps the invite row and shows key-material warning',
      (tester) async {
        final invite = makePendingInvite(overrideGroupKey: '');
        await pendingInviteRepo.savePendingInvite(invite);

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
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsOneWidget,
        );
        expect(find.text('Invite needs fresh key material'), findsOneWidget);
        expect(bridge.commandLog, isNot(contains('group:join')));
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
        expect(find.text('Invite needs fresh key material'), findsOneWidget);
        expect(bridge.commandLog, contains('group:join'));
        expect(bridge.commandLog, isNot(contains('group:inboxRetrieveCursor')));
      },
    );

    testWidgets('declining a pending invite removes the row without joining', (
      tester,
    ) async {
      final invite = makePendingInvite(
        groupId: 'grp-decline',
        groupName: 'Decline Me',
      );
      await pendingInviteRepo.savePendingInvite(invite);

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      await tester.tap(
        find.byKey(ValueKey('pending-group-invite-decline-${invite.groupId}')),
      );
      await pumpFrames(tester, count: 20);

      expect(await pendingInviteRepo.getPendingInvite(invite.groupId), isNull);
      expect(await groupRepo.getGroup(invite.groupId), isNull);
      expect(
        find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
        findsNothing,
      );
      expect(find.text('Invite declined'), findsOneWidget);
    });

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
