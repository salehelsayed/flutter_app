import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

class _FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;
  _FakeIdentityRepository({this.identity});

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

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

class _FakeGroupMessageListener extends GroupMessageListener {
  final Stream<GroupMessage> _stream;
  _FakeGroupMessageListener(this._stream)
    : super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

  @override
  Stream<GroupMessage> get groupMessageStream => _stream;

  @override
  Stream<ReactionChange> get groupReactionChangeStream =>
      const Stream<ReactionChange>.empty();

  @override
  Stream<String> get groupRemovedStream => const Stream<String>.empty();
}

final _testIdentity = IdentityModel(
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

GroupModel _makeChatGroup() => GroupModel(
  id: 'group-1',
  name: 'Test Group',
  type: GroupType.chat,
  topicName: 'topic-1',
  description: 'A test group',
  createdAt: DateTime.now().toUtc(),
  createdBy: 'peer-admin',
  myRole: GroupRole.admin,
);

GroupMessage _makeMessage({
  required String id,
  required String text,
  String senderPeerId = 'peer-admin',
  String senderUsername = 'Admin',
  String status = 'sent',
  bool isIncoming = false,
  DateTime? timestamp,
}) => GroupMessage(
  id: id,
  groupId: 'group-1',
  senderPeerId: senderPeerId,
  senderUsername: senderUsername,
  text: text,
  timestamp: timestamp ?? DateTime.utc(2026, 2, 9, 15, 30),
  createdAt: timestamp ?? DateTime.utc(2026, 2, 9, 15, 30),
  isIncoming: isIncoming,
  status: status,
);

void main() {
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late InMemoryMediaAttachmentRepository mediaRepo;
  late InMemoryContactRepository contactRepo;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late _FakeIdentityRepository identityRepo;
  late StreamController<GroupMessage> streamController;

  setUp(() async {
    GroupConversationWired.debugGroupDisplayItemsBuildCount = 0;
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    mediaRepo = InMemoryMediaAttachmentRepository();
    contactRepo = InMemoryContactRepository();
    bridge = FakeBridge();
    p2pService = FakeP2PService();
    identityRepo = _FakeIdentityRepository(identity: _testIdentity);
    streamController = StreamController<GroupMessage>.broadcast();

    final group = _makeChatGroup();
    await groupRepo.saveGroup(group);
    await groupRepo.saveMember(
      GroupMember(
        groupId: group.id,
        peerId: _testIdentity.peerId,
        username: _testIdentity.username,
        role: MemberRole.admin,
        publicKey: _testIdentity.publicKey,
        mlKemPublicKey: _testIdentity.mlKemPublicKey,
        joinedAt: DateTime.utc(2026, 5, 1, 10),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: group.id,
        peerId: 'peer-bob',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-peer-bob',
        mlKemPublicKey: 'mlkem-peer-bob',
        joinedAt: DateTime.utc(2026, 5, 1, 10, 1),
      ),
    );
  });

  tearDown(() => streamController.close());

  Widget buildWidget({Locale locale = const Locale('en')}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupConversationWired(
        group: _makeChatGroup(),
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: _FakeGroupMessageListener(streamController.stream),
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        mediaAttachmentRepo: mediaRepo,
      ),
    );
  }

  Future<void> pumpFrames(WidgetTester tester, {int count = 12}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // TC-159-05 — group display-items are memoized on the WIRED State; the memo
  // reuses across an unrelated rebuild, and recomputes on a status flip and a
  // locale change.
  testWidgets(
    'TC-159-05 group display-items memoized on the wired State (status + locale key)',
    (tester) async {
      await msgRepo.saveMessage(_makeMessage(id: 'g1', text: 'Hello group'));

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);
      expect(find.text('Hello group'), findsOneWidget);

      // Reuse across an unrelated rebuild (same `_messages`, same locale).
      final before = GroupConversationWired.debugGroupDisplayItemsBuildCount;
      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);
      expect(
        GroupConversationWired.debugGroupDisplayItemsBuildCount,
        before,
        reason: 'an identical-input wired rebuild must reuse the memoized list',
      );

      // A status flip (delivered) reallocates `_messages` → recompute + update.
      final flipped = _makeMessage(
        id: 'g1',
        text: 'Hello group',
        status: 'delivered',
      );
      await msgRepo.saveMessage(flipped);
      streamController.add(flipped);
      await pumpFrames(tester);
      expect(
        GroupConversationWired.debugGroupDisplayItemsBuildCount,
        greaterThan(before),
        reason: 'a status flip changes `_messages` → must recompute',
      );
      final card = tester.widget<LetterCard>(
        find.descendant(
          of: find.byKey(const ValueKey('grp-msg-g1')),
          matching: find.byType(LetterCard),
        ),
      );
      expect(card.status, 'delivered');

      // A locale change recomputes day-separator labels (locale is in the key).
      final afterFlip =
          GroupConversationWired.debugGroupDisplayItemsBuildCount;
      final enLabel = tester
          .widget<DateSeparator>(find.byType(DateSeparator))
          .label;
      await tester.pumpWidget(buildWidget(locale: const Locale('ar')));
      await pumpFrames(tester);
      expect(
        GroupConversationWired.debugGroupDisplayItemsBuildCount,
        greaterThan(afterFlip),
        reason: 'a locale switch must invalidate the wired memo',
      );
      final arLabel = tester
          .widget<DateSeparator>(find.byType(DateSeparator))
          .label;
      expect(arLabel, isNot(enLabel));
    },
  );
}
