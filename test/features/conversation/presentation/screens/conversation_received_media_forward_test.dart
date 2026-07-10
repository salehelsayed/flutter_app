import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/build_received_media_forward.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_screen.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_wired.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/repositories/fake_media_attachment_repository.dart';
import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  late Directory tempDir;
  late File sourceFile;
  late ConversationMessage message;
  late FakeMediaAttachmentRepository mediaRepo;

  setUp(() {
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
    tempDir = Directory.systemTemp.createTempSync('conversation_forward_ui_');
    sourceFile = File('${tempDir.path}/source.jpg')..writeAsBytesSync([1]);
    final attachment = MediaAttachment(
      id: 'attachment-1',
      messageId: 'message-1',
      mime: 'image/jpeg',
      size: 1,
      mediaType: 'image',
      localPath: sourceFile.path,
      downloadStatus: 'done',
      createdAt: '2026-07-10T10:00:00.000Z',
      ownerLane: MediaOwnerLane.direct,
    );
    message = ConversationMessage(
      id: 'message-1',
      contactPeerId: 'contact-1',
      senderPeerId: 'contact-1',
      text: 'editable source caption',
      timestamp: '2026-07-10T10:00:00.000Z',
      status: 'delivered',
      isIncoming: true,
      createdAt: '2026-07-10T10:00:00.000Z',
      media: [attachment],
    );
    mediaRepo = FakeMediaAttachmentRepository()..seed([attachment]);
  });

  tearDown(() {
    UploadWakeLockController.debugReset();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpFrames(WidgetTester tester, {int count = 8}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget app({
    required Locale locale,
    required DirectReceivedMediaForwardHandler onForward,
    GlobalKey<NavigatorState>? navigatorKey,
    List<ConversationMessage>? screenMessages,
  }) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ConversationScreen(
          contactPeerId: 'contact-1',
          contactUsername: 'Alice',
          connectionDate: 'July 10, 2026',
          ownPeerId: 'self',
          messages: screenMessages ?? [message],
          initialLoadDone: true,
          onSend: (_) {},
          onBack: () {},
          onForwardMedia: onForward,
        ),
      ),
    );
  }

  testWidgets(
    'forward action launches existing picker with editable source caption',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      var tokenCounter = 0;
      String? launchedCurrentAttachmentId;
      await tester.pumpWidget(
        app(
          locale: const Locale('en'),
          navigatorKey: navigatorKey,
          onForward: (messageId, {currentAttachmentId}) async {
            launchedCurrentAttachmentId = currentAttachmentId;
            final draft = await BuildReceivedMediaForward(
              mediaAttachmentRepository: mediaRepo,
              operationTokenFactory: () => 'operation-${++tokenCounter}',
              resolveStoredPath: (path) => path,
              fileExists: (path) => File(path).existsSync(),
            ).build(parent: message, currentAttachmentId: currentAttachmentId);
            final intent = draft.draft!.shareIntent;
            final caption = TextEditingController(text: intent.text);
            await navigatorKey.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => ShareTargetPickerScreen(
                  sharedText: intent.text,
                  sharedFilePaths: intent.filePaths,
                  captionController: caption,
                  contacts: const [],
                  groups: const [],
                  onToggleContact: (_) {},
                  onToggleGroup: (_) {},
                ),
              ),
            );
            caption.dispose();
            return true;
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.longPress(find.text('editable source caption'));
      await pumpFrames(tester);
      await tester.tap(find.byKey(MessageContextOverlay.forwardActionKey));
      await pumpFrames(tester);

      expect(find.byType(ShareTargetPickerScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('share-preview-image')), findsOneWidget);
      expect(launchedCurrentAttachmentId, isNull);
      final captionField = find.byKey(const ValueKey('share-caption-field'));
      expect(
        tester.widget<TextField>(captionField).controller!.text,
        'editable source caption',
      );
      await tester.enterText(captionField, 'edited caption');
      expect(
        tester.widget<TextField>(captionField).controller!.text,
        'edited caption',
      );
      await tester.enterText(captionField, '');
      expect(tester.widget<TextField>(captionField).controller!.text, isEmpty);
      expect(message.text, 'editable source caption');
    },
  );

  testWidgets(
    'production-wired forward opens picker and delivers to a writable group',
    (tester) async {
      final identities = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'my-peer-id-12345',
            mlKemPublicKey: 'my-mlkem-public',
            mlKemSecretKey: 'my-mlkem-secret',
          ),
        );
      final contacts = InMemoryContactRepository();
      const contact = ContactModel(
        peerId: 'contact-1',
        publicKey: 'contact-public-key',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'contact-signature',
        scannedAt: '2026-07-10T09:00:00.000Z',
        mlKemPublicKey: 'contact-mlkem-public-key',
      );
      await contacts.addContact(contact);
      final messages = InMemoryMessageRepository();
      await messages.saveMessage(message);
      final attachments = InMemoryMediaAttachmentRepository();
      await attachments.saveAttachment(
        message.media.single,
        owner: MediaOwnerLane.direct,
      );
      final groups = InMemoryGroupRepository();
      final groupMessages = InMemoryGroupMessageRepository();
      final group = GroupModel(
        id: 'forward-group',
        name: 'Forward Writers',
        type: GroupType.chat,
        topicName: 'topic-forward-group',
        createdAt: DateTime.parse('2026-07-10T09:00:00.000Z'),
        createdBy: 'my-peer-id-12345',
        myRole: GroupRole.admin,
      );
      await groups.saveGroup(group);
      final joinedAt = DateTime.parse('2026-07-10T09:00:00.000Z');
      await groups.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'my-peer-id-12345',
          username: 'Me',
          role: MemberRole.admin,
          publicKey: 'my-public-key',
          mlKemPublicKey: 'my-mlkem-public',
          joinedAt: joinedAt,
        ),
      );
      await groups.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'peer-writer',
          username: 'Writer',
          role: MemberRole.writer,
          publicKey: 'writer-public-key',
          mlKemPublicKey: 'writer-mlkem-public-key',
          joinedAt: joinedAt.add(const Duration(seconds: 1)),
        ),
      );
      await groups.saveKey(
        GroupKeyInfo(
          groupId: group.id,
          keyGeneration: 1,
          encryptedKey: 'forward-group-key',
          createdAt: joinedAt,
        ),
      );
      final bridge = _ProductionGroupForwardBridge();
      final p2p = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-12345',
        ),
      );
      final listener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messages,
        contactRepo: contacts,
        bridge: bridge,
      );
      addTearDown(listener.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConversationWired(
            contact: contact,
            identityRepo: identities,
            messageRepo: messages,
            chatMessageListener: listener,
            p2pService: p2p,
            bridge: bridge,
            contactRepo: contacts,
            mediaAttachmentRepo: attachments,
            mediaFileManager: FakeMediaFileManager(),
            imageProcessor: _testImageProcessor(),
            initialMessages: [message],
            forwardGroupRepository: groups,
            forwardGroupMessageRepository: groupMessages,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.longPress(find.text('editable source caption'));
      await pumpFrames(tester);
      await tester.tap(find.byKey(MessageContextOverlay.forwardActionKey));
      await pumpFrames(tester, count: 16);

      expect(find.byType(ShareTargetPickerScreen), findsOneWidget);
      expect(find.byKey(ValueKey('share-group-${group.id}')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('share-group-${group.id}')));
      await pumpFrames(tester);
      final sendGesture = tester.widget<GestureDetector>(
        find
            .ancestor(
              of: find.text('Send'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      await tester.runAsync(() async {
        sendGesture.onTap!();
        for (var i = 0; i < 80; i++) {
          if ((await groupMessages.getMessagesPage(group.id)).isNotEmpty) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pump();

      final delivered = await groupMessages.getMessagesPage(group.id);
      expect(delivered, hasLength(1));
      expect(delivered.single.text, 'editable source caption');
      expect(bridge.commandLog, contains('group:publish'));
      final groupAttachments = await attachments.getAttachmentsForMessage(
        delivered.single.id,
        owner: MediaOwnerLane.group,
      );
      expect(groupAttachments, hasLength(1));
      expect(groupAttachments.single.ownerLane, MediaOwnerLane.group);
    },
  );

  testWidgets('forward flow is localized RTL-safe and semantics-labelled', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final locale in const [Locale('de'), Locale('ar')]) {
      final localizedMessage = message.copyWith(isForwarded: true);
      await tester.pumpWidget(
        app(
          locale: locale,
          onForward: (_, {currentAttachmentId}) async => true,
          screenMessages: [localizedMessage],
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final conversationContext = tester.element(
        find.byType(ConversationScreen),
      );
      final l10n = AppLocalizations.of(conversationContext)!;
      expect(find.text(l10n.conversation_forwarded_marker), findsOneWidget);
      expect(
        Directionality.of(conversationContext),
        locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
      await tester.longPress(find.text('editable source caption'));
      await pumpFrames(tester);
      expect(
        find.byKey(MessageContextOverlay.forwardActionKey),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(MessageContextOverlay.forwardActionKey),
          matching: find.text(l10n.media_viewer_action_forward),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(l10n.media_viewer_action_forward),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(MessageContextOverlay.backdropKey));
      await pumpFrames(tester);

      final pickerContacts = [
        const ContactModel(
          peerId: 'partial-success',
          publicKey: 'success-key',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Success',
          signature: 'success-signature',
          scannedAt: '2026-07-10T09:00:00.000Z',
        ),
        const ContactModel(
          peerId: 'partial-failure',
          publicKey: 'failure-key',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Failure',
          signature: 'failure-signature',
          scannedAt: '2026-07-10T09:00:00.000Z',
        ),
      ];
      final pickerIdentity = FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity());
      final pickerContactRepo = InMemoryContactRepository();
      for (final contact in pickerContacts) {
        await pickerContactRepo.addContact(contact);
      }
      final pickerMessages = InMemoryMessageRepository();
      final pickerMedia = InMemoryMediaAttachmentRepository();
      final pickerListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: pickerMessages,
        contactRepo: pickerContactRepo,
      );
      addTearDown(pickerListener.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ShareTargetPickerWired(
            shareIntent: ShareIntent(
              type: ShareIntentType.mixed,
              text: 'editable source caption',
              filePaths: [sourceFile.path],
              forwardProvenance: const ForwardProvenance(
                operationDedupKey: 'localized-operation',
              ),
            ),
            identityRepo: pickerIdentity,
            contactRepository: pickerContactRepo,
            messageRepository: pickerMessages,
            mediaAttachmentRepository: pickerMedia,
            chatMessageListener: pickerListener,
            bridge: FakeBridge(),
            p2pService: FakeP2PService(),
            mediaFileManager: FakeMediaFileManager(),
            imageProcessor: _testImageProcessor(),
            batchShareCoordinator: const _PartialForwardCoordinator(),
          ),
        ),
      );
      await pumpFrames(tester, count: 12);
      final pickerContext = tester.element(
        find.byType(ShareTargetPickerScreen),
      );
      final pickerL10n = AppLocalizations.of(pickerContext)!;
      expect(find.byKey(const ValueKey('share-caption-label')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('share-caption-label')))
            .data,
        pickerL10n.share_caption,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('share-caption-field')),
            )
            .controller!
            .text,
        'editable source caption',
      );
      await tester.tap(
        find.byKey(const ValueKey('share-contact-partial-success')),
      );
      await tester.tap(
        find.byKey(const ValueKey('share-contact-partial-failure')),
      );
      await pumpFrames(tester);
      expect(find.text(pickerL10n.share_title_count(2)), findsOneWidget);
      final localizedSendGesture = tester.widget<GestureDetector>(
        find
            .ancestor(
              of: find.text(pickerL10n.share_send),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      localizedSendGesture.onTap!();
      await pumpFrames(tester, count: 12);
      final partialSummary =
          '${pickerL10n.share_summary_sent(pickerL10n.share_target_count(1))}, '
          '${pickerL10n.share_summary_failed(pickerL10n.share_target_count(1))}.';
      final expectedSummary =
          '${partialSummary[0].toUpperCase()}${partialSummary.substring(1)}';
      expect(find.text(expectedSummary), findsOneWidget);
      expect(
        find.byKey(const ValueKey('share-inline-feedback')),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    }
    semanticsHandle.dispose();
  });
}

class _PartialForwardCoordinator implements ShareBatchDeliveryCoordinator {
  const _PartialForwardCoordinator();

  @override
  Future<ShareBatchDeliveryResult> deliver({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
    ShareBatchDeliveryProgressCallback? onProgress,
  }) async {
    expectSync(
      shareIntent.forwardProvenance?.operationDedupKey,
      'localized-operation',
    );
    expectSync(targets, hasLength(2));
    return ShareBatchDeliveryResult(
      results: targets
          .map(
            (target) => ShareBatchTargetResult(
              target: target,
              status: target.requireContact.peerId == 'partial-success'
                  ? ShareBatchTargetStatus.sent
                  : ShareBatchTargetStatus.failed,
              detail: target.requireContact.peerId == 'partial-success'
                  ? 'Sent.'
                  : 'Failed.',
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<ShareBatchDeliveryResult> deliverGroupMediaForward({
    required GroupMediaForwardRequest request,
    String? caption,
    required List<ShareTargetSelection> targets,
  }) {
    throw UnimplementedError(
      '1:1 received-media forwarding never dispatches a group-origin request',
    );
  }
}

ImageProcessor _testImageProcessor() => ImageProcessor(
  compressFile:
      ({
        required path,
        required quality,
        required keepExif,
        minWidth = 1920,
        minHeight = 1080,
      }) async => null,
  compressVideo: ({required path, required compress, onProgress}) async =>
      VideoProcessResult(path: path),
);

class _ProductionGroupForwardBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final command = parsed['cmd'] as String?;
    if (command != null) commandLog.add(command);
    switch (command) {
      case 'bg:begin':
        return 'forward-background-task';
      case 'bg:end':
        return '';
      case 'group.encrypt':
        final payload = parsed['payload'] as Map<String, dynamic>;
        return jsonEncode({
          'ok': true,
          'ciphertext': payload['plaintext'],
          'nonce': 'forward-group-nonce',
        });
      case 'payload.sign':
        return jsonEncode({'ok': true, 'signature': 'forward-signature'});
      case 'group:publish':
        return jsonEncode({
          'ok': true,
          'messageId': 'forward-group-message',
          'topicPeers': 1,
        });
      case 'group:inboxStore':
        return jsonEncode({'ok': true});
      default:
        return super.send(message);
    }
  }
}
