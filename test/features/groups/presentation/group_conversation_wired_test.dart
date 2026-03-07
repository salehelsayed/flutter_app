import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
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
    : super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

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
    }) {
      final g = group ?? makeChatGroup();
      return MaterialApp(
        home: GroupConversationWired(
          group: g,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupMessageListener: FakeGroupMessageListener(
            messageStreamController.stream,
          ),
          bridge: bridge,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          mediaAttachmentRepo: mediaRepo,
          imageProcessor: imageProcessor,
          audioRecorderService: audioRecorderService,
          mediaPicker: mediaPicker,
        ),
      );
    }

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
  });
}
