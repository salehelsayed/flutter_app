import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
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

// --- Fake listener with externally-controlled stream ---

/// A fake GroupMessageListener whose [groupMessageStream] is controlled
/// by an external StreamController.
class FakeGroupMessageListener extends GroupMessageListener {
  final Stream<GroupMessage> _externalStream;

  FakeGroupMessageListener(this._externalStream)
      : super(
          groupRepo: _NoOpGroupRepo(),
          msgRepo: _NoOpMsgRepo(),
        );

  @override
  Stream<GroupMessage> get groupMessageStream => _externalStream;
}

class _NoOpGroupRepo implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoOpMsgRepo implements GroupMessageRepository {
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

GroupModel makeChatGroup({GroupRole role = GroupRole.admin}) => GroupModel(
      id: 'group-1',
      name: 'Test Group',
      type: GroupType.chat,
      topicName: 'topic-1',
      description: 'A test group',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: role,
    );

GroupModel makeAnnouncementGroup({GroupRole role = GroupRole.admin}) =>
    GroupModel(
      id: 'group-1',
      name: 'Announce Group',
      type: GroupType.announcement,
      topicName: 'topic-1',
      description: 'Announcement',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: role,
    );

GroupMessage makeMessage({
  required String id,
  required String text,
  String groupId = 'group-1',
  bool isIncoming = true,
  String senderPeerId = 'peer-alice',
  String senderUsername = 'Alice',
}) =>
    GroupMessage(
      id: id,
      groupId: groupId,
      senderPeerId: senderPeerId,
      senderUsername: senderUsername,
      text: text,
      timestamp: DateTime.now().toUtc(),
      isIncoming: isIncoming,
      createdAt: DateTime.now().toUtc(),
    );

// --- Helpers ---

/// Pump enough frames for async operations to complete.
/// AmbientBackground has an infinite animation, so pumpAndSettle will timeout.
Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('GroupConversationWired', () {
    late InMemoryGroupRepository groupRepo;
    late InMemoryGroupMessageRepository msgRepo;
    late InMemoryContactRepository contactRepo;
    late FakeBridge bridge;
    late FakeIdentityRepository identityRepo;
    late FakeP2PService p2pService;
    late StreamController<GroupMessage> messageStreamController;

    setUp(() {
      groupRepo = InMemoryGroupRepository();
      msgRepo = InMemoryGroupMessageRepository();
      contactRepo = InMemoryContactRepository();
      bridge = FakeBridge(initialResponses: {
        'group:publish': {'ok': true, 'messageId': 'msg-published'},
      });
      identityRepo = FakeIdentityRepository(identity: testIdentity);
      p2pService = FakeP2PService();
      messageStreamController = StreamController<GroupMessage>.broadcast();
    });

    tearDown(() {
      messageStreamController.close();
    });

    Widget buildWidget({GroupModel? group}) {
      final g = group ?? makeChatGroup();
      return MaterialApp(
        home: GroupConversationWired(
          group: g,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupMessageListener:
              FakeGroupMessageListener(messageStreamController.stream),
          bridge: bridge,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
        ),
      );
    }

    testWidgets('loads and displays messages on init', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
      await msgRepo.saveMessage(makeMessage(id: 'msg-2', text: 'World'));
      await msgRepo.saveMessage(
          makeMessage(id: 'msg-3', text: 'How are you?'));

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('World'), findsOneWidget);
      expect(find.text('How are you?'), findsOneWidget);
    });

    testWidgets('sending a message calls bridge and refreshes',
        (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      // Type a message
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'Test message');
      await pumpFrames(tester);

      // Tap send button (the arrow_upward icon inside the compose area)
      final sendButton = find.byIcon(Icons.arrow_upward);
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await pumpFrames(tester, count: 20);

      // Verify bridge received group:publish command
      expect(bridge.commandLog, contains('group:publish'));

      // The sent message should appear in the list
      expect(find.text('Test message'), findsOneWidget);
    });

    testWidgets('incoming message stream triggers refresh', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      // Initially no messages
      expect(find.text('No messages yet'), findsOneWidget);

      // Add a message to the repo (simulating the listener handler saving it)
      final incomingMsg = makeMessage(
        id: 'msg-incoming',
        text: 'Incoming hello',
        groupId: 'group-1',
      );
      await msgRepo.saveMessage(incomingMsg);

      // Emit on the listener stream with matching groupId
      messageStreamController.add(incomingMsg);
      await pumpFrames(tester, count: 20);

      // The message should now appear
      expect(find.text('Incoming hello'), findsOneWidget);
    });

    testWidgets('info button navigates to group info', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      // Tap the info icon
      final infoButton = find.byIcon(Icons.info_outline);
      expect(infoButton, findsOneWidget);
      await tester.tap(infoButton);
      await pumpFrames(tester, count: 20);

      // GroupInfoScreen should appear (inside GroupInfoWired)
      expect(find.byType(GroupInfoScreen), findsOneWidget);
    });

    testWidgets('non-admin in announcement group cannot write',
        (tester) async {
      final group =
          makeAnnouncementGroup(role: GroupRole.member);
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      // The compose area should show the read-only message instead of a text field
      expect(
        find.text('Only admins can send messages in this group'),
        findsOneWidget,
      );

      // TextField should not be present (canWrite=false hides it)
      expect(find.byType(TextField), findsNothing);
    });
  });
}
