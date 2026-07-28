import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/groups/application/group_exit_diagnostic_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../core/bridge/fake_bridge.dart';
import '../core/services/fake_p2p_service.dart';
import '../features/conversation/domain/repositories/fake_reaction_repository.dart';
import '../features/identity/domain/repositories/fake_identity_repository.dart';
import '../shared/fakes/fake_audio_recorder_service.dart';
import '../shared/fakes/fake_media_file_manager.dart';
import '../shared/fakes/fake_mic_permission_gateway.dart';
import '../shared/fakes/in_memory_contact_repository.dart';
import '../shared/fakes/in_memory_group_message_repository.dart';
import '../shared/fakes/in_memory_group_repository.dart';
import '../shared/fakes/in_memory_media_attachment_repository.dart';
import '../shared/fakes/in_memory_message_repository.dart';

const _directPeerId = 'peer-direct-budget';
const _directMessageId = 'direct-budget-message';
const _directAttachmentId = 'direct-budget-attachment';
const _groupId = 'group-budget';
const _groupMessageId = 'group-budget-message';
const _groupAttachmentId = 'group-budget-attachment';
const _selfPeerId = 'peer-self-budget';
const _reactionSenderPeerId = 'peer-reaction-budget';

final class _WiredRootRebuildRecorder {
  RebuildDirtyWidgetCallback? _previous;

  int direct = 0;
  int group = 0;

  void install() {
    _previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      _previous?.call(element, builtOnce);
      if (!builtOnce) return;
      if (element.widget is ConversationWired) {
        direct++;
      } else if (element.widget is GroupConversationWired) {
        group++;
      }
    };
  }

  void reset() {
    direct = 0;
    group = 0;
  }

  void restore() {
    debugOnRebuildDirtyWidget = _previous;
    _previous = null;
  }
}

final class _ControlledReactionListener extends ReactionListener {
  _ControlledReactionListener({
    required InMemoryMessageRepository messageRepo,
    required FakeReactionRepository reactionRepo,
    required InMemoryContactRepository contactRepo,
    required FakeBridge bridge,
  }) : super(
         reactionStream: const Stream<ChatMessage>.empty(),
         messageRepo: messageRepo,
         reactionRepo: reactionRepo,
         contactRepo: contactRepo,
         bridge: bridge,
         getOwnMlKemSecretKey: () async => null,
       );

  final _changes = StreamController<ReactionChange>.broadcast();

  @override
  Stream<ReactionChange> get incomingReactionChangeStream => _changes.stream;

  void emit(ReactionChange change) => _changes.add(change);

  Future<void> closeForTest() async {
    super.dispose();
    await _changes.close();
  }
}

final class _ControlledGroupMessageListener extends GroupMessageListener {
  _ControlledGroupMessageListener({
    required InMemoryGroupRepository groupRepo,
    required InMemoryGroupMessageRepository messageRepo,
  }) : super(groupRepo: groupRepo, msgRepo: messageRepo);

  final _messages = StreamController<GroupMessage>.broadcast();
  final _reactions = StreamController<ReactionChange>.broadcast();
  final _removals = StreamController<String>.broadcast();

  @override
  Stream<GroupMessage> get groupMessageStream => _messages.stream;

  @override
  Stream<ReactionChange> get groupReactionChangeStream => _reactions.stream;

  @override
  Stream<String> get groupRemovedStream => _removals.stream;

  void emitReaction(ReactionChange change) => _reactions.add(change);

  Future<void> closeForTest() async {
    super.dispose();
    await Future.wait<void>([
      _messages.close(),
      _reactions.close(),
      _removals.close(),
    ]);
  }
}

final class _DirectFixture {
  _DirectFixture._({
    required this.contact,
    required this.message,
    required this.reactionListener,
    required this.reactionRepository,
    required this.chatMessageListener,
    required this.identityRepository,
    required this.messageRepository,
    required this.contactRepository,
    required this.bridge,
    required this.p2pService,
    required this.recorder,
  });

  final ContactModel contact;
  final ConversationMessage message;
  final _ControlledReactionListener reactionListener;
  final FakeReactionRepository reactionRepository;
  final ChatMessageListener chatMessageListener;
  final FakeIdentityRepository identityRepository;
  final InMemoryMessageRepository messageRepository;
  final InMemoryContactRepository contactRepository;
  final FakeBridge bridge;
  final FakeP2PService p2pService;
  final FakeAudioRecorderService recorder;

  static Future<_DirectFixture> create() async {
    final now = DateTime.utc(2026, 7, 28, 10).toIso8601String();
    final contact = ContactModel(
      peerId: _directPeerId,
      publicKey: 'direct-public-key',
      rendezvous: '/dns4/relay.invalid/tcp/443/p2p/relay',
      username: 'Direct peer',
      signature: 'direct-signature',
      scannedAt: now,
      introsBannerDismissed: true,
    );
    final identity = IdentityModel(
      peerId: _selfPeerId,
      publicKey: 'self-public-key',
      privateKey: 'self-private-key',
      mnemonic12:
          'one two three four five six seven eight nine ten eleven twelve',
      mlKemPublicKey: 'self-ml-kem-public-key',
      mlKemSecretKey: 'self-ml-kem-secret-key',
      username: 'Self',
      createdAt: now,
      updatedAt: now,
    );
    final attachment = MediaAttachment(
      id: _directAttachmentId,
      messageId: _directMessageId,
      mime: 'image/jpeg',
      size: 100,
      mediaType: 'image',
      downloadStatus: 'upload_pending',
      createdAt: now,
    );
    final message = ConversationMessage(
      id: _directMessageId,
      contactPeerId: contact.peerId,
      senderPeerId: identity.peerId,
      text: '',
      timestamp: now,
      status: 'sending',
      isIncoming: false,
      createdAt: now,
      media: [attachment],
    );
    final identityRepository = FakeIdentityRepository()..seed(identity);
    final messageRepository = InMemoryMessageRepository();
    await messageRepository.saveMessage(message);
    final contactRepository = InMemoryContactRepository()
      ..addTestContact(contact);
    final bridge = FakeBridge();
    final reactionRepository = FakeReactionRepository();
    final reactionListener = _ControlledReactionListener(
      messageRepo: messageRepository,
      reactionRepo: reactionRepository,
      contactRepo: contactRepository,
      bridge: bridge,
    );
    final chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
    );
    final p2pService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: _selfPeerId,
        relayState: 'online',
        sendCapabilityReady: true,
        inboxCapabilityReady: true,
      ),
    );
    return _DirectFixture._(
      contact: contact,
      message: message,
      reactionListener: reactionListener,
      reactionRepository: reactionRepository,
      chatMessageListener: chatMessageListener,
      identityRepository: identityRepository,
      messageRepository: messageRepository,
      contactRepository: contactRepository,
      bridge: bridge,
      p2pService: p2pService,
      recorder: FakeAudioRecorderService()..fakeDurationMs = 100,
    );
  }

  Widget get widget => _localizedApp(
    ConversationWired(
      contact: contact,
      identityRepo: identityRepository,
      messageRepo: messageRepository,
      chatMessageListener: chatMessageListener,
      p2pService: p2pService,
      bridge: bridge,
      initialMessages: [message],
      contactRepo: contactRepository,
      mediaFileManager: FakeMediaFileManager(),
      audioRecorderService: recorder,
      micPermissionGateway: FakeMicPermissionGateway(),
      reactionRepo: reactionRepository,
      reactionListener: reactionListener,
    ),
  );

  Future<void> dispose() async {
    chatMessageListener.dispose();
    await reactionListener.closeForTest();
    p2pService.dispose();
    await recorder.dispose();
  }
}

final class _GroupFixture {
  _GroupFixture._({
    required this.group,
    required this.message,
    required this.reactionListener,
    required this.reactionRepository,
    required this.identityRepository,
    required this.groupRepository,
    required this.messageRepository,
    required this.mediaRepository,
    required this.contactRepository,
    required this.bridge,
    required this.p2pService,
    required this.recorder,
  });

  final GroupModel group;
  final GroupMessage message;
  final _ControlledGroupMessageListener reactionListener;
  final FakeReactionRepository reactionRepository;
  final FakeIdentityRepository identityRepository;
  final InMemoryGroupRepository groupRepository;
  final InMemoryGroupMessageRepository messageRepository;
  final InMemoryMediaAttachmentRepository mediaRepository;
  final InMemoryContactRepository contactRepository;
  final FakeBridge bridge;
  final FakeP2PService p2pService;
  final FakeAudioRecorderService recorder;

  static Future<_GroupFixture> create() async {
    final now = DateTime.utc(2026, 7, 28, 10);
    final identity = IdentityModel(
      peerId: _selfPeerId,
      publicKey: 'self-public-key',
      privateKey: 'self-private-key',
      mnemonic12:
          'one two three four five six seven eight nine ten eleven twelve',
      mlKemPublicKey: 'self-ml-kem-public-key',
      mlKemSecretKey: 'self-ml-kem-secret-key',
      username: 'Self',
      createdAt: now.toIso8601String(),
      updatedAt: now.toIso8601String(),
    );
    final group = GroupModel(
      id: _groupId,
      name: 'Budget group',
      type: GroupType.chat,
      topicName: 'budget-topic',
      createdAt: now,
      createdBy: identity.peerId,
      myRole: GroupRole.admin,
    );
    final attachment = MediaAttachment(
      id: _groupAttachmentId,
      messageId: _groupMessageId,
      mime: 'image/jpeg',
      size: 100,
      mediaType: 'image',
      downloadStatus: 'upload_pending',
      createdAt: now.toIso8601String(),
      ownerLane: MediaOwnerLane.group,
    );
    final message = GroupMessage(
      id: _groupMessageId,
      groupId: group.id,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      text: '',
      timestamp: now,
      status: 'sending',
      isIncoming: false,
      createdAt: now,
      media: [attachment],
    );

    final groupRepository = InMemoryGroupRepository();
    await groupRepository.saveGroup(group);
    await groupRepository.saveMember(
      GroupMember(
        groupId: group.id,
        peerId: identity.peerId,
        username: identity.username,
        role: MemberRole.admin,
        publicKey: identity.publicKey,
        mlKemPublicKey: identity.mlKemPublicKey,
        joinedAt: now,
      ),
    );
    await groupRepository.saveMember(
      GroupMember(
        groupId: group.id,
        peerId: _reactionSenderPeerId,
        username: 'Reaction peer',
        role: MemberRole.writer,
        publicKey: 'reaction-public-key',
        mlKemPublicKey: 'reaction-ml-kem-public-key',
        joinedAt: now.add(const Duration(minutes: 1)),
      ),
    );
    await groupRepository.saveKey(
      GroupKeyInfo(
        groupId: group.id,
        keyGeneration: 1,
        encryptedKey: 'group-key',
        createdAt: now,
      ),
    );
    final messageRepository = InMemoryGroupMessageRepository();
    await messageRepository.saveMessage(message);
    final mediaRepository = InMemoryMediaAttachmentRepository();
    await mediaRepository.saveAttachment(
      attachment,
      owner: MediaOwnerLane.group,
    );
    final contactRepository = InMemoryContactRepository()
      ..addTestContact(
        ContactModel(
          peerId: _reactionSenderPeerId,
          publicKey: 'reaction-public-key',
          rendezvous: '/dns4/relay.invalid/tcp/443/p2p/relay',
          username: 'Reaction peer',
          signature: 'reaction-signature',
          scannedAt: now.toIso8601String(),
          mlKemPublicKey: 'reaction-ml-kem-public-key',
        ),
      );
    final identityRepository = FakeIdentityRepository()..seed(identity);
    final reactionRepository = FakeReactionRepository();
    final reactionListener = _ControlledGroupMessageListener(
      groupRepo: groupRepository,
      messageRepo: messageRepository,
    );
    final p2pService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: _selfPeerId,
        relayState: 'online',
        sendCapabilityReady: true,
        inboxCapabilityReady: true,
      ),
    );
    return _GroupFixture._(
      group: group,
      message: message,
      reactionListener: reactionListener,
      reactionRepository: reactionRepository,
      identityRepository: identityRepository,
      groupRepository: groupRepository,
      messageRepository: messageRepository,
      mediaRepository: mediaRepository,
      contactRepository: contactRepository,
      bridge: FakeBridge(),
      p2pService: p2pService,
      recorder: FakeAudioRecorderService()..fakeDurationMs = 100,
    );
  }

  Widget get widget => _localizedApp(
    GroupConversationWired(
      group: group,
      groupRepo: groupRepository,
      msgRepo: messageRepository,
      groupMessageListener: reactionListener,
      bridge: bridge,
      identityRepo: identityRepository,
      contactRepo: contactRepository,
      p2pService: p2pService,
      mediaAttachmentRepo: mediaRepository,
      mediaFileManager: FakeMediaFileManager(),
      audioRecorderService: recorder,
      micPermissionGateway: FakeMicPermissionGateway(),
      reactionRepo: reactionRepository,
    ),
  );

  Future<void> dispose() async {
    await reactionListener.closeForTest();
    p2pService.dispose();
    await recorder.dispose();
  }
}

Widget _localizedApp(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

MessageReaction _reactionFor(String messageId, {String id = 'reaction-1'}) {
  const timestamp = '2026-07-28T10:02:00.000Z';
  return MessageReaction(
    id: id,
    messageId: messageId,
    emoji: '👍',
    senderPeerId: _reactionSenderPeerId,
    timestamp: timestamp,
    createdAt: timestamp,
  );
}

void _emitUpload({
  required String attachmentId,
  required String scopeId,
  required int sentBytes,
}) {
  emitMediaUploadProgressEvent({
    'id': attachmentId,
    'sentBytes': sentBytes,
    'totalBytes': 100,
    'toPeerId': scopeId,
  });
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 4}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _mount(
  WidgetTester tester,
  Widget widget,
  _WiredRootRebuildRecorder rebuilds,
) async {
  await tester.pumpWidget(widget);
  await _pumpFrames(tester, count: 20);
  rebuilds.reset();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void _expectNoWiredRootRebuilds(
  _WiredRootRebuildRecorder rebuilds, {
  required String reason,
}) {
  expect(rebuilds.direct, 0, reason: '$reason (direct root)');
  expect(rebuilds.group, 0, reason: '$reason (group root)');
}

void main() {
  late _WiredRootRebuildRecorder rebuilds;

  setUp(() {
    rebuilds = _WiredRootRebuildRecorder()..install();
    groupRecoveryGate.resetForTest();
    setGroupExitIntentAccessSinks(
      forGroup: (_) async => null,
      all: () async => const <GroupExitIntent>[],
    );
    setGroupExitIntentActionSinks();
    setGroupExitDiagnosticAccessSink();
  });

  tearDown(() {
    rebuilds.restore();
    groupRecoveryGate.resetForTest();
    setGroupExitIntentAccessSinks();
    setGroupExitIntentActionSinks();
    setGroupExitDiagnosticAccessSink();
  });

  testWidgets(
    'semantic no-ops and irrelevant events rebuild neither Wired root',
    (tester) async {
      final direct = await _DirectFixture.create();
      try {
        await _mount(tester, direct.widget, rebuilds);
        final reaction = _reactionFor(direct.message.id);

        _emitUpload(
          attachmentId: _directAttachmentId,
          scopeId: direct.contact.peerId,
          sentBytes: 60,
        );
        direct.reactionListener.emit(ReactionChange.upsert(reaction));
        await _pumpFrames(tester);
        expect(
          tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messageUploadProgress[direct.message.id]
              ?.percent,
          60,
        );
        expect(
          tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .reactions[direct.message.id]
              ?.single
              .emoji,
          '👍',
        );

        rebuilds.reset();
        _emitUpload(
          attachmentId: _directAttachmentId,
          scopeId: 'wrong-direct-scope',
          sentBytes: 80,
        );
        _emitUpload(
          attachmentId: 'unknown-direct-attachment',
          scopeId: direct.contact.peerId,
          sentBytes: 80,
        );
        _emitUpload(
          attachmentId: _directAttachmentId,
          scopeId: direct.contact.peerId,
          sentBytes: 40,
        );
        direct.reactionListener.emit(ReactionChange.upsert(reaction));
        direct.reactionListener.emit(
          ReactionChange.removed(
            messageId: direct.message.id,
            senderPeerId: 'absent-direct-reaction-sender',
          ),
        );
        await _pumpFrames(tester);
        _expectNoWiredRootRebuilds(
          rebuilds,
          reason: 'direct semantic no-ops and rejected upload events',
        );

        await _unmount(tester);
        rebuilds.reset();
        _emitUpload(
          attachmentId: _directAttachmentId,
          scopeId: direct.contact.peerId,
          sentBytes: 90,
        );
        direct.reactionListener.emit(
          ReactionChange.upsert(
            _reactionFor(direct.message.id, id: 'late-direct-reaction'),
          ),
        );
        await _pumpFrames(tester);
        _expectNoWiredRootRebuilds(
          rebuilds,
          reason: 'late direct events after disposal',
        );
      } finally {
        await _unmount(tester);
        await direct.dispose();
      }

      final group = await _GroupFixture.create();
      try {
        await _mount(tester, group.widget, rebuilds);
        final reaction = _reactionFor(group.message.id);

        _emitUpload(
          attachmentId: _groupAttachmentId,
          scopeId: group.group.id,
          sentBytes: 60,
        );
        group.reactionListener.emitReaction(ReactionChange.upsert(reaction));
        await _pumpFrames(tester);
        expect(
          tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .messageUploadProgress[group.message.id]
              ?.percent,
          60,
        );
        expect(
          tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .reactions[group.message.id]
              ?.single
              .emoji,
          '👍',
        );

        rebuilds.reset();
        _emitUpload(
          attachmentId: _groupAttachmentId,
          scopeId: 'wrong-group-scope',
          sentBytes: 80,
        );
        _emitUpload(
          attachmentId: 'unknown-group-attachment',
          scopeId: group.group.id,
          sentBytes: 80,
        );
        _emitUpload(
          attachmentId: _groupAttachmentId,
          scopeId: group.group.id,
          sentBytes: 40,
        );
        group.reactionListener.emitReaction(ReactionChange.upsert(reaction));
        group.reactionListener.emitReaction(
          ReactionChange.removed(
            messageId: group.message.id,
            senderPeerId: 'absent-group-reaction-sender',
          ),
        );
        await _pumpFrames(tester);
        _expectNoWiredRootRebuilds(
          rebuilds,
          reason: 'group semantic no-ops and rejected upload events',
        );

        await _unmount(tester);
        rebuilds.reset();
        _emitUpload(
          attachmentId: _groupAttachmentId,
          scopeId: group.group.id,
          sentBytes: 90,
        );
        group.reactionListener.emitReaction(
          ReactionChange.upsert(
            _reactionFor(group.message.id, id: 'late-group-reaction'),
          ),
        );
        await _pumpFrames(tester);
        _expectNoWiredRootRebuilds(
          rebuilds,
          reason: 'late group events after disposal',
        );
      } finally {
        await _unmount(tester);
        await group.dispose();
      }
    },
  );

  testWidgets(
    'accepted upload and reaction events rebuild each Wired root at most once',
    (tester) async {
      final direct = await _DirectFixture.create();
      try {
        await _mount(tester, direct.widget, rebuilds);

        _emitUpload(
          attachmentId: _directAttachmentId,
          scopeId: direct.contact.peerId,
          sentBytes: 60,
        );
        await _pumpFrames(tester);
        expect(
          tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messageUploadProgress[direct.message.id]
              ?.percent,
          60,
          reason: 'accepted direct upload reached the real screen projection',
        );
        expect(
          rebuilds.direct,
          lessThanOrEqualTo(1),
          reason: 'one direct upload event has one root invalidation budget',
        );
        expect(rebuilds.group, 0);

        rebuilds.reset();
        direct.reactionListener.emit(
          ReactionChange.upsert(_reactionFor(direct.message.id)),
        );
        await _pumpFrames(tester);
        expect(
          tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .reactions[direct.message.id]
              ?.single
              .emoji,
          '👍',
          reason: 'accepted direct reaction reached the real screen projection',
        );
        expect(
          rebuilds.direct,
          lessThanOrEqualTo(1),
          reason: 'one direct reaction event has one root invalidation budget',
        );
        expect(rebuilds.group, 0);
      } finally {
        await _unmount(tester);
        await direct.dispose();
      }

      final group = await _GroupFixture.create();
      try {
        await _mount(tester, group.widget, rebuilds);

        _emitUpload(
          attachmentId: _groupAttachmentId,
          scopeId: group.group.id,
          sentBytes: 60,
        );
        await _pumpFrames(tester);
        expect(
          tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .messageUploadProgress[group.message.id]
              ?.percent,
          60,
          reason: 'accepted group upload reached the real screen projection',
        );
        expect(rebuilds.direct, 0);
        expect(
          rebuilds.group,
          lessThanOrEqualTo(1),
          reason: 'one group upload event has one root invalidation budget',
        );

        rebuilds.reset();
        group.reactionListener.emitReaction(
          ReactionChange.upsert(_reactionFor(group.message.id)),
        );
        await _pumpFrames(tester);
        expect(
          tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .reactions[group.message.id]
              ?.single
              .emoji,
          '👍',
          reason: 'accepted group reaction reached the real screen projection',
        );
        expect(rebuilds.direct, 0);
        expect(
          rebuilds.group,
          lessThanOrEqualTo(1),
          reason: 'one group reaction event has one root invalidation budget',
        );
      } finally {
        await _unmount(tester);
        await group.dispose();
      }
    },
  );

  testWidgets(
    'voice ticks update composer without rebuilding either Wired root',
    (tester) async {
      final direct = await _DirectFixture.create();
      try {
        await _mount(tester, direct.widget, rebuilds);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.mic_rounded)),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();
        expect(direct.recorder.startCallCount, 1);

        rebuilds.reset();
        direct.recorder.emitDuration(const Duration(seconds: 1));
        direct.recorder.emitAmplitude(0.3);
        await _pumpFrames(tester);
        expect(find.text('0:01'), findsOneWidget);
        _expectNoWiredRootRebuilds(
          rebuilds,
          reason: 'direct duration and amplitude ticks stay composer-local',
        );

        await gesture.up();
        await _pumpFrames(tester);
      } finally {
        await _unmount(tester);
        await direct.dispose();
      }

      final group = await _GroupFixture.create();
      try {
        await _mount(tester, group.widget, rebuilds);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.mic_rounded)),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();
        expect(group.recorder.startCallCount, 1);

        rebuilds.reset();
        group.recorder.emitDuration(const Duration(seconds: 2));
        group.recorder.emitAmplitude(0.5);
        await _pumpFrames(tester);
        expect(find.text('0:02'), findsOneWidget);
        _expectNoWiredRootRebuilds(
          rebuilds,
          reason: 'group duration and amplitude ticks stay composer-local',
        );

        await gesture.up();
        await _pumpFrames(tester);
      } finally {
        await _unmount(tester);
        await group.dispose();
      }
    },
  );
}
