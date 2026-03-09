import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_media_picker.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

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
  final Stream<ReactionChange>? _externalReactionStream;

  FakeGroupMessageListener(
    this._externalStream, {
    Stream<ReactionChange>? reactionStream,
  }) : _externalReactionStream = reactionStream,
       super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

  @override
  Stream<GroupMessage> get groupMessageStream => _externalStream;

  @override
  Stream<ReactionChange> get groupReactionChangeStream =>
      _externalReactionStream ?? super.groupReactionChangeStream;
}

class _NoOpGroupRepo implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoOpMsgRepo implements GroupMessageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A bridge that gates group:publish behind a [Completer] so tests can
/// verify optimistic display before the network responds.
class _GatedPublishBridge extends FakeBridge {
  final Completer<void> publishGate = Completer<void>();

  _GatedPublishBridge() {
    responses['group:publish'] = {'ok': true, 'messageId': 'msg-published'};
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      await publishGate.future;
    }

    return super.send(message);
  }
}

class CountingGroupMessageRepository extends InMemoryGroupMessageRepository {
  int getMessagesPageCalls = 0;
  int getMessageCalls = 0;

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    getMessagesPageCalls++;
    return super.getMessagesPage(groupId, limit: limit, offset: offset);
  }

  @override
  Future<GroupMessage?> getMessage(String id) async {
    getMessageCalls++;
    return super.getMessage(id);
  }
}

class SlowInitialPageGroupMessageRepository
    extends CountingGroupMessageRepository {
  final Completer<void> firstPageGate = Completer<void>();

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    await firstPageGate.future;
    return super.getMessagesPage(groupId, limit: limit, offset: offset);
  }
}

class CountingMediaAttachmentRepository
    extends InMemoryMediaAttachmentRepository {
  int getAttachmentsForMessagesCalls = 0;
  int getAttachmentsForMessageCalls = 0;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId,
  ) async {
    getAttachmentsForMessageCalls++;
    return super.getAttachmentsForMessage(messageId);
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async {
    getAttachmentsForMessagesCalls++;
    return super.getAttachmentsForMessages(messageIds);
  }
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
}) => GroupMessage(
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
    late CountingGroupMessageRepository msgRepo;
    late CountingMediaAttachmentRepository mediaAttachmentRepo;
    late InMemoryContactRepository contactRepo;
    late FakeBridge bridge;
    late FakeIdentityRepository identityRepo;
    late FakeP2PService p2pService;
    late StreamController<GroupMessage> messageStreamController;

    setUp(() {
      groupRepo = InMemoryGroupRepository();
      msgRepo = CountingGroupMessageRepository();
      mediaAttachmentRepo = CountingMediaAttachmentRepository();
      contactRepo = InMemoryContactRepository();
      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': true, 'messageId': 'msg-published'},
        },
      );
      identityRepo = FakeIdentityRepository(identity: testIdentity);
      p2pService = FakeP2PService();
      messageStreamController = StreamController<GroupMessage>.broadcast();
    });

    tearDown(() {
      messageStreamController.close();
    });

    Widget buildWidget({
      GroupModel? group,
      CountingMediaAttachmentRepository? mediaRepo,
      ImageProcessor? imageProcessor,
      FakeAudioRecorderService? audioRecorderService,
      MediaPicker? mediaPicker,
      List<File>? initialAttachments,
      String? initialText,
      ReactionRepository? reactionRepo,
      StreamController<ReactionChange>? reactionStreamController,
    }) {
      final g = group ?? makeChatGroup();
      return MaterialApp(
        home: GroupConversationWired(
          group: g,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupMessageListener: FakeGroupMessageListener(
            messageStreamController.stream,
            reactionStream: reactionStreamController?.stream,
          ),
          bridge: bridge,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          mediaAttachmentRepo: mediaRepo,
          imageProcessor: imageProcessor,
          audioRecorderService: audioRecorderService,
          mediaPicker: mediaPicker,
          initialAttachments: initialAttachments,
          initialText: initialText,
          reactionRepo: reactionRepo,
        ),
      );
    }

    testWidgets('prefills shared text into the group composer', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(
        buildWidget(group: group, initialText: 'Shared group text'),
      );
      await pumpFrames(tester);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'Shared group text');
    });

    testWidgets('loads and displays messages on init', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
      await msgRepo.saveMessage(makeMessage(id: 'msg-2', text: 'World'));
      await msgRepo.saveMessage(makeMessage(id: 'msg-3', text: 'How are you?'));

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('World'), findsOneWidget);
      expect(find.text('How are you?'), findsOneWidget);
    });

    testWidgets('sending a message calls bridge and refreshes', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);
      expect(msgRepo.getMessagesPageCalls, 1);

      // Type a message
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'Test message');
      await pumpFrames(tester);

      // Tap send button (the arrow_upward_rounded icon inside ComposeArea)
      final sendButton = find.byIcon(Icons.arrow_upward_rounded);
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await pumpFrames(tester, count: 20);

      // Verify bridge received group:publish command
      expect(bridge.commandLog, contains('group:publish'));
      expect(msgRepo.getMessagesPageCalls, 1);

      // The sent message should appear in the list
      expect(find.text('Test message'), findsOneWidget);
    });

    testWidgets(
      'incoming message stream upserts without full message/media reloads',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(id: 'msg-initial', text: 'Initial'),
        );

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpFrames(tester);

        expect(find.text('Initial'), findsOneWidget);
        expect(msgRepo.getMessagesPageCalls, 1);
        expect(mediaAttachmentRepo.getAttachmentsForMessagesCalls, 1);
        final initialGetMessageCalls = msgRepo.getMessageCalls;
        final initialSingleMessageMediaCalls =
            mediaAttachmentRepo.getAttachmentsForMessageCalls;

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
        expect(msgRepo.getMessagesPageCalls, 1);
        expect(msgRepo.getMessageCalls, greaterThan(initialGetMessageCalls));
        expect(mediaAttachmentRepo.getAttachmentsForMessagesCalls, 1);
        expect(
          mediaAttachmentRepo.getAttachmentsForMessageCalls,
          initialSingleMessageMediaCalls + 1,
        );
      },
    );

    testWidgets('shows loading shell until the initial group page resolves', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      final slowRepo = SlowInitialPageGroupMessageRepository();
      await slowRepo.saveMessage(
        makeMessage(id: 'msg-delayed', text: 'Loaded after delay'),
      );
      msgRepo = slowRepo;

      await tester.pumpWidget(
        buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('group-loading-shell')), findsOneWidget);
      expect(find.text('Loaded after delay'), findsNothing);

      slowRepo.firstPageGate.complete();
      await pumpFrames(tester, count: 20);

      expect(find.byKey(const ValueKey('group-loading-shell')), findsNothing);
      expect(find.text('Loaded after delay'), findsOneWidget);
    });

    testWidgets(
      'incoming message preserves scroll offset when reading older messages',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final start = DateTime.utc(2026, 2, 1, 10);
        for (var index = 0; index < 40; index++) {
          await msgRepo.saveMessage(
            GroupMessage(
              id: 'msg-$index',
              groupId: group.id,
              senderPeerId: 'peer-alice',
              senderUsername: 'Alice',
              text: 'Message $index',
              timestamp: start.add(Duration(minutes: index)),
              createdAt: start.add(Duration(minutes: index)),
            ),
          );
        }

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpFrames(tester, count: 20);

        final listFinder = find.byKey(const ValueKey('group-messages'));
        expect(listFinder, findsOneWidget);

        final controller = tester.widget<ListView>(listFinder).controller!;
        expect(controller.hasClients, isTrue);

        controller.jumpTo(240);
        await pumpFrames(tester, count: 4);

        final offsetBefore = controller.offset;
        expect(offsetBefore, greaterThan(32));

        final incoming = GroupMessage(
          id: 'msg-late',
          groupId: group.id,
          senderPeerId: 'peer-bob',
          senderUsername: 'Bob',
          text: 'Newest while reading history',
          timestamp: start.add(const Duration(minutes: 60)),
          createdAt: start.add(const Duration(minutes: 60)),
        );
        await msgRepo.saveMessage(incoming);

        messageStreamController.add(incoming);
        await pumpFrames(tester, count: 20);

        expect(controller.offset, closeTo(offsetBefore, 1.0));
        expect(msgRepo.getMessagesPageCalls, 1);
        expect(mediaAttachmentRepo.getAttachmentsForMessagesCalls, 1);
      },
    );

    testWidgets(
      'recording ticks update composer without rebuilding header or message list',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-rec-1', text: 'Hello'));
        final recorder = FakeAudioRecorderService()..fakeDurationMs = 100;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            audioRecorderService: recorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        final headerFinder = find.byKey(const ValueKey('group-header'));
        final listFinder = find.byKey(const ValueKey('group-messages'));
        final headerElement = tester.element(headerFinder);
        final listElement = tester.element(listFinder);
        final initialPageLoads = msgRepo.getMessagesPageCalls;
        final initialBatchMediaLoads =
            mediaAttachmentRepo.getAttachmentsForMessagesCalls;

        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.mic_rounded)),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();

        recorder.emitDuration(const Duration(seconds: 2));
        recorder.emitAmplitude(0.5);
        await tester.pump();

        expect(find.text('Slide to cancel'), findsOneWidget);
        expect(find.text('0:02'), findsOneWidget);
        expect(identical(headerElement, tester.element(headerFinder)), isTrue);
        expect(identical(listElement, tester.element(listFinder)), isTrue);
        expect(msgRepo.getMessagesPageCalls, initialPageLoads);
        expect(
          mediaAttachmentRepo.getAttachmentsForMessagesCalls,
          initialBatchMediaLoads,
        );

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets(
      'video processing progress updates composer without rebuilding header or message list',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(id: 'msg-video-1', text: 'Hello'),
        );

        final mediaPicker = FakeMediaPicker()
          ..videoResult = XFile('/tmp/group-video.mp4');
        final resultCompleter = Completer<VideoProcessResult>();
        void Function(double progress)? progressCallback;
        final imageProcessor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async => null,
          compressVideo:
              ({
                required path,
                required compress,
                void Function(double)? onProgress,
              }) async {
                progressCallback = onProgress;
                return resultCompleter.future;
              },
        );

        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            imageProcessor: imageProcessor,
            mediaPicker: mediaPicker,
          ),
        );
        await pumpFrames(tester, count: 20);

        final headerFinder = find.byKey(const ValueKey('group-header'));
        final listFinder = find.byKey(const ValueKey('group-messages'));
        final headerElement = tester.element(headerFinder);
        final listElement = tester.element(listFinder);
        final initialPageLoads = msgRepo.getMessagesPageCalls;
        final initialBatchMediaLoads =
            mediaAttachmentRepo.getAttachmentsForMessagesCalls;

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Record Video'))
            .onTap!();
        await tester.pump();

        expect(progressCallback, isNotNull);

        progressCallback!(35);
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('35%'), findsOneWidget);
        expect(identical(headerElement, tester.element(headerFinder)), isTrue);
        expect(identical(listElement, tester.element(listFinder)), isTrue);
        expect(msgRepo.getMessagesPageCalls, initialPageLoads);
        expect(
          mediaAttachmentRepo.getAttachmentsForMessagesCalls,
          initialBatchMediaLoads,
        );

        progressCallback!(80);
        await tester.pump();
        expect(find.text('80%'), findsOneWidget);

        resultCompleter.complete(
          VideoProcessResult(path: '/tmp/processed-group-video.mp4'),
        );
        await tester.pump();
      },
    );

    testWidgets('video processing failure clears composer processing state', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(makeMessage(id: 'msg-video-fail', text: 'Hi'));

      final mediaPicker = FakeMediaPicker()
        ..videoResult = XFile('/tmp/group-video.mp4');
      final resultCompleter = Completer<VideoProcessResult>();
      void Function(double progress)? progressCallback;
      final imageProcessor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => null,
        compressVideo:
            ({
              required path,
              required compress,
              void Function(double)? onProgress,
            }) async {
              progressCallback = onProgress;
              return resultCompleter.future;
            },
      );

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: mediaAttachmentRepo,
          imageProcessor: imageProcessor,
          mediaPicker: mediaPicker,
        ),
      );
      await pumpFrames(tester, count: 20);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Record Video'))
          .onTap!();
      await tester.pump();

      progressCallback!(40);
      await tester.pump();
      expect(find.text('40%'), findsOneWidget);

      resultCompleter.completeError(StateError('group video failed'));
      await tester.pump();

      expect(find.byType(AttachmentPreviewStrip), findsNothing);
      expect(find.text('40%'), findsNothing);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Record Video'), findsOneWidget);
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

    testWidgets('non-admin in announcement group cannot write', (tester) async {
      final group = makeAnnouncementGroup(role: GroupRole.member);
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

    testWidgets('sets tracker active on init', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      final tracker = ActiveConversationTracker();

      await tester.pumpWidget(
        MaterialApp(
          home: GroupConversationWired(
            group: group,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupMessageListener: FakeGroupMessageListener(
              messageStreamController.stream,
            ),
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            groupConversationTracker: tracker,
          ),
        ),
      );
      await pumpFrames(tester);

      expect(tracker.isViewing('group:${group.id}'), isTrue);
    });

    testWidgets('clears tracker on dispose', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      final tracker = ActiveConversationTracker();

      await tester.pumpWidget(
        MaterialApp(
          home: GroupConversationWired(
            group: group,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupMessageListener: FakeGroupMessageListener(
              messageStreamController.stream,
            ),
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            groupConversationTracker: tracker,
          ),
        ),
      );
      await pumpFrames(tester);

      expect(tracker.isViewing('group:${group.id}'), isTrue);

      // Replace the widget to trigger dispose
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await pumpFrames(tester);

      expect(tracker.isViewing('group:${group.id}'), isFalse);
    });

    testWidgets('accepts empty initialAttachments without error', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: CountingMediaAttachmentRepository(),
          initialAttachments: [],
        ),
      );
      await pumpFrames(tester);

      expect(find.byType(GroupConversationWired), findsOneWidget);
      // No AttachmentPreviewStrip when list is empty
      expect(find.byType(AttachmentPreviewStrip), findsNothing);
    });

    testWidgets(
      'sent text message appears immediately before bridge responds',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        // Use a gated bridge that blocks group:publish until we release it
        final gatedBridge = _GatedPublishBridge();
        bridge = gatedBridge;

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        // Type and send
        await tester.enterText(find.byType(TextField), 'Optimistic hello');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        // Pump a few frames — bridge is still gated
        await pumpFrames(tester, count: 5);

        // Message should be visible optimistically
        expect(find.text('Optimistic hello'), findsOneWidget);

        // Status should be 'sending' (single check icon)
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);

        // Release the bridge
        gatedBridge.publishGate.complete();
        await pumpFrames(tester, count: 20);

        // Message still visible, status updated to 'sent'
        expect(find.text('Optimistic hello'), findsOneWidget);
      },
    );

    testWidgets('optimistic message is saved to DB before network ops', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      final gatedBridge = _GatedPublishBridge();
      bridge = gatedBridge;

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextField), 'DB before net');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 5);

      // Message should be in the DB with status 'sending'
      final messages = await msgRepo.getMessagesPage(group.id);
      expect(messages.length, 1);
      expect(messages.first.text, 'DB before net');
      expect(messages.first.status, 'sending');

      // Bridge hasn't been called for publish yet? Actually it was called
      // but is blocked on the completer. The key point: DB was saved first.

      gatedBridge.publishGate.complete();
      await pumpFrames(tester, count: 20);

      // After publish completes, status should be 'sent'
      final updated = await msgRepo.getMessagesPage(group.id);
      expect(updated.first.status, 'sent');
    });

    testWidgets('failed publish shows message with failed status', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      // Bridge returns failure for publish
      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
        },
      );

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextField), 'Will fail');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 20);

      // Message should still be visible
      expect(find.text('Will fail'), findsOneWidget);

      // Status should be 'failed' (error icon)
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Voice message tests
    //
    // NOTE: uploadMedia() uses real File I/O (File.length()) which does not
    // complete inside Flutter's FakeAsync zone. Full upload→publish flow is
    // tested at the use case level in send_group_message_use_case_test.dart.
    // These tests verify the optimistic UI pattern added in _onRecordStop.
    // -----------------------------------------------------------------------

    testWidgets(
      'voice record stop creates optimistic message with sending status',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3000
          ..fakeSizeBytes = 48000;

        final gatedBridge = _GatedPublishBridge();
        bridge = gatedBridge;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            audioRecorderService: recorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        // Long-press mic to start recording, single pump for _onRecordStart
        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.mic_rounded)),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();

        // Release to stop recording
        await gesture.up();
        // _onRecordStop has several awaits (cancel subs, recorder.stop) that
        // need the real event loop to resolve. Use runAsync to let them settle.
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await pumpFrames(tester, count: 10);

        // Optimistic message should be persisted to DB with 'sending' status
        // and empty text (voice-only message).
        final messages = await msgRepo.getMessagesPage(group.id);
        expect(messages.length, 1);
        expect(messages.first.status, 'sending');
        expect(messages.first.text, '');
        expect(messages.first.isIncoming, false);
        expect(messages.first.senderPeerId, testIdentity.peerId);

        gatedBridge.publishGate.complete();
        await pumpFrames(tester, count: 20);
      },
    );

    // Full upload→publish e2e is tested at the use case level:
    // - send_group_message_use_case_test: 'sends message with empty text and media'
    // - Go bridge_test: TestGroupPublish_MediaOnly_AcceptsEmptyText
    // (The wired-level e2e test is not feasible because uploadMedia's File I/O
    // does not resolve in Flutter's FakeAsync zone.)

    testWidgets('announcement admin sees mic button for voice recording', (
      tester,
    ) async {
      final group = makeAnnouncementGroup(role: GroupRole.admin);
      await groupRepo.saveGroup(group);
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 3000
        ..fakeSizeBytes = 48000;

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: mediaAttachmentRepo,
          audioRecorderService: recorder,
        ),
      );
      await pumpFrames(tester, count: 20);

      // Mic button should be visible for admin in announcement group
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

      // Start recording to verify the long press callback works
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_rounded)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump();

      // Recording overlay should appear
      expect(find.text('Slide to cancel'), findsOneWidget);

      await gesture.up();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await pumpFrames(tester, count: 10);

      // Optimistic message saved to DB
      final messages = await msgRepo.getMessagesPage(group.id);
      expect(messages.length, 1);
      expect(messages.first.text, '');
      expect(messages.first.senderPeerId, testIdentity.peerId);
    });

    // -----------------------------------------------------------------------
    // Reaction integration tests
    // -----------------------------------------------------------------------

    testWidgets(
      'loads persisted reactions on init when reactionRepo is provided',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        final reactionRepo = FakeReactionRepository();
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-1',
            messageId: 'msg-1',
            emoji: '\u{1F44D}',
            senderPeerId: 'peer-alice',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildWidget(group: group, reactionRepo: reactionRepo),
        );
        await pumpFrames(tester);

        // The reaction emoji should be visible in the UI
        expect(find.text('\u{1F44D}'), findsOneWidget);
      },
    );

    testWidgets('reaction UI is disabled when reactionRepo is null', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      // Long-press a message — should NOT show reaction bar
      await tester.longPress(find.text('Hello'));
      await pumpFrames(tester);

      // No reaction bar emojis visible (the preset emojis like thumbs up etc.)
      expect(find.text('\u{1F44D}'), findsNothing);
    });

    testWidgets('incoming reaction change stream updates UI state', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

      final reactionRepo = FakeReactionRepository();
      final reactionStreamController =
          StreamController<ReactionChange>.broadcast();

      await tester.pumpWidget(
        buildWidget(
          group: group,
          reactionRepo: reactionRepo,
          reactionStreamController: reactionStreamController,
        ),
      );
      await pumpFrames(tester);

      // No reactions initially
      expect(find.text('\u{1F44D}'), findsNothing);

      // Emit an incoming reaction change
      reactionStreamController.add(
        ReactionChange.upsert(
          MessageReaction(
            id: 'rxn-incoming',
            messageId: 'msg-1',
            emoji: '\u{1F44D}',
            senderPeerId: 'peer-bob',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ),
      );
      await pumpFrames(tester);

      // Reaction should now be visible
      expect(find.text('\u{1F44D}'), findsOneWidget);

      // Clean up
      await reactionStreamController.close();
    });
  });
}
