import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
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

PendingGroupInvite makePendingInvite({
  String groupId = 'grp-abc123',
  String groupName = 'Book Club',
  DateTime? receivedAt,
}) {
  final payload = GroupInvitePayload(
    id: 'invite-$groupId',
    groupId: groupId,
    groupKey: 'base64-key',
    keyEpoch: 1,
    groupConfig: {
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
      ],
      'createdBy': '12D3KooWAlice',
      'createdAt': '2026-03-02T00:00:00.000Z',
    },
    senderPeerId: '12D3KooWAlice',
    senderUsername: 'Alice',
    timestamp: '2026-03-02T12:00:00.000Z',
  );

  return PendingGroupInvite.fromPayload(
    payload,
    receivedAt: receivedAt ?? DateTime.utc(2026, 4, 5, 12),
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

    Widget buildWidget() {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GroupListWired(
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
      'accepting a pending invite joins the group and removes the row',
      (tester) async {
        final invite = makePendingInvite();
        await pendingInviteRepo.savePendingInvite(invite);
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            {
              'from': '12D3KooWAlice',
              'message': jsonEncode({
                'groupId': invite.groupId,
                'messageId': 'offline-msg-1',
                'senderId': '12D3KooWAlice',
                'senderUsername': 'Alice',
                'keyEpoch': 1,
                'text': 'Welcome back',
                'timestamp': '2026-03-02T13:00:00.000Z',
              }),
            },
          ],
          'cursor': '',
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
        expect(find.text('Book Club'), findsOneWidget);
        expect(find.text('Joined Book Club'), findsOneWidget);
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

    testWidgets('loading clears on error', (tester) async {
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

      // No spinner stuck — empty state shown instead
      expect(find.byKey(const ValueKey('group-loading-row-0')), findsNothing);
      expect(find.text('No groups yet'), findsOneWidget);
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
  @override
  Future<List<GroupModel>> getActiveGroups() async {
    throw Exception('Simulated group loading error');
  }
}
