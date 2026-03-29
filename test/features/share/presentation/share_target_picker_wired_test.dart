import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_wired.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  final activeContact = _makeContact('peer-alice', 'Alice');
  final archivedContact = _makeContact('peer-bob', 'Bob');

  Widget buildWidget({
    required InMemoryContactRepository contactRepository,
    required InMemoryGroupRepository groupRepository,
    required InMemoryMessageRepository messageRepository,
    required InMemoryMediaAttachmentRepository mediaAttachmentRepository,
    required FakeIdentityRepository identityRepository,
    required ChatMessageListener chatMessageListener,
    required InMemoryGroupMessageRepository groupMessageRepository,
    required GroupMessageListener groupMessageListener,
    required ShareIntent shareIntent,
    ImageProcessor? imageProcessor,
    ImageQualityPreference qualityPreference =
        ImageQualityPreference.compressed,
    ImageQualityPreference videoQualityPreference =
        ImageQualityPreference.compressed,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ShareTargetPickerWired(
        shareIntent: shareIntent,
        identityRepo: identityRepository,
        contactRepository: contactRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        chatMessageListener: chatMessageListener,
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor:
            imageProcessor ??
            ImageProcessor(
              compressFile:
                  ({
                    required path,
                    required quality,
                    required keepExif,
                    minWidth = 1920,
                    minHeight = 1080,
                  }) async => null,
              compressVideo:
                  ({required path, required compress, onProgress}) async =>
                      null,
            ),
        qualityPreference: qualityPreference,
        videoQualityPreference: videoQualityPreference,
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
      ),
    );
  }

  Future<void> pumpPicker(
    WidgetTester tester, {
    required InMemoryContactRepository contactRepository,
    required InMemoryGroupRepository groupRepository,
    required InMemoryMessageRepository messageRepository,
    required InMemoryMediaAttachmentRepository mediaAttachmentRepository,
    required FakeIdentityRepository identityRepository,
    required ChatMessageListener chatMessageListener,
    required InMemoryGroupMessageRepository groupMessageRepository,
    required GroupMessageListener groupMessageListener,
    required ShareIntent shareIntent,
    ImageProcessor? imageProcessor,
    ImageQualityPreference qualityPreference =
        ImageQualityPreference.compressed,
    ImageQualityPreference videoQualityPreference =
        ImageQualityPreference.compressed,
  }) async {
    await tester.pumpWidget(
      buildWidget(
        contactRepository: contactRepository,
        groupRepository: groupRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        identityRepository: identityRepository,
        chatMessageListener: chatMessageListener,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        shareIntent: shareIntent,
        imageProcessor: imageProcessor,
        qualityPreference: qualityPreference,
        videoQualityPreference: videoQualityPreference,
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapAndAwaitRoute(
    WidgetTester tester, {
    required Finder tapTarget,
    required Finder routeTarget,
    int maxFrames = 30,
  }) async {
    await tester.tap(tapTarget);
    Object? exception;
    for (var i = 0; i < maxFrames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      exception ??= tester.takeException();
      if (routeTarget.evaluate().isNotEmpty) {
        return;
      }
    }
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    fail(
      'Route target did not appear within ${maxFrames * 50}ms'
      '; canPop=${navigator.canPop()}'
      '${exception != null ? '; pending exception: $exception' : ''}',
    );
  }

  testWidgets(
    '2j, 2q, 2r, 2s: loads only active contacts and writable groups',
    (tester) async {
      final contactRepository = InMemoryContactRepository();
      final groupRepository = InMemoryGroupRepository();
      final messageRepository = InMemoryMessageRepository();
      final mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
      final identityRepository = FakeIdentityRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      identityRepository.seed(_makeIdentity());
      final chatMessageListener = ChatMessageListener(
        chatMessageStream: const Stream<ChatMessage>.empty(),
        messageRepo: messageRepository,
        contactRepo: contactRepository,
      );
      final groupMessageListener = GroupMessageListener(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
      );

      contactRepository.addTestContact(activeContact);
      contactRepository.addTestContact(archivedContact);
      await contactRepository.archiveContact(archivedContact.peerId);

      await groupRepository.saveGroup(
        _makeGroup('chat-group', 'Friends', GroupType.chat, GroupRole.member),
      );
      await groupRepository.saveGroup(
        _makeGroup(
          'announce-member',
          'Announcements',
          GroupType.announcement,
          GroupRole.member,
        ),
      );
      await groupRepository.saveGroup(
        _makeGroup(
          'announce-admin',
          'Admin Announcements',
          GroupType.announcement,
          GroupRole.admin,
        ),
      );
      await groupRepository.saveGroup(
        _makeGroup(
          'archived-group',
          'Archived Group',
          GroupType.chat,
          GroupRole.admin,
        ).copyWith(
          isArchived: true,
          archivedAt: DateTime.parse('2026-03-09T08:00:00.000Z'),
        ),
      );

      await pumpPicker(
        tester,
        contactRepository: contactRepository,
        groupRepository: groupRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        identityRepository: identityRepository,
        chatMessageListener: chatMessageListener,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'Shared hello',
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Friends'), findsOneWidget);
      expect(find.text('Admin Announcements'), findsOneWidget);
      expect(find.text('Announcements'), findsNothing);
      expect(find.text('Archived Group'), findsNothing);
    },
  );

  testWidgets(
    '2k and 2m: selecting a contact navigates to ConversationWired with shared files and text',
    (tester) async {
      final contactRepository = InMemoryContactRepository();
      final groupRepository = InMemoryGroupRepository();
      final messageRepository = InMemoryMessageRepository();
      final mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
      final identityRepository = FakeIdentityRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      identityRepository.seed(_makeIdentity());
      final chatMessageListener = ChatMessageListener(
        chatMessageStream: const Stream<ChatMessage>.empty(),
        messageRepo: messageRepository,
        contactRepo: contactRepository,
      );
      final groupMessageListener = GroupMessageListener(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'share_picker_image_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final sourceImage = File('${tempDir.path}/shared.jpg')
        ..writeAsStringSync('image');

      contactRepository.addTestContact(activeContact);
      final processor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async {
              final processed = File('$path.processed.jpg')
                ..writeAsStringSync('12');
              return XFile(processed.path);
            },
        compressVideo: ({required path, required compress, onProgress}) async =>
            null,
      );

      await pumpPicker(
        tester,
        contactRepository: contactRepository,
        groupRepository: groupRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        identityRepository: identityRepository,
        chatMessageListener: chatMessageListener,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        shareIntent: ShareIntent(
          type: ShareIntentType.mixed,
          text: 'Shared hello',
          filePaths: [sourceImage.path],
        ),
        imageProcessor: processor,
      );

      await tapAndAwaitRoute(
        tester,
        tapTarget: find.byKey(ValueKey('share-contact-${activeContact.peerId}')),
        routeTarget: find.byType(ConversationWired, skipOffstage: false),
      );

      final conversation = tester.widget<ConversationWired>(
        find.byType(ConversationWired, skipOffstage: false),
      );
      expect(conversation.initialText, 'Shared hello');
      expect(conversation.initialAttachments, isNotNull);
      expect(conversation.initialAttachments, hasLength(1));
      expect(conversation.initialPendingMedia, isNotNull);
      expect(conversation.initialPendingMedia, hasLength(1));
      expect(
        conversation.initialAttachments!.first.path,
        '${sourceImage.path}.processed.jpg',
      );
      expect(
        conversation.initialPendingMedia!.first.file.path,
        '${sourceImage.path}.processed.jpg',
      );
      expect(conversation.initialPendingMedia!.first.budgetBytes, 2);
    },
  );

  testWidgets(
    '2l and 2n: selecting a group navigates to GroupConversationWired with shared files and URL text',
    (tester) async {
      final contactRepository = InMemoryContactRepository();
      final groupRepository = InMemoryGroupRepository();
      final messageRepository = InMemoryMessageRepository();
      final mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
      final identityRepository = FakeIdentityRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      identityRepository.seed(_makeIdentity());
      final chatMessageListener = ChatMessageListener(
        chatMessageStream: const Stream<ChatMessage>.empty(),
        messageRepo: messageRepository,
        contactRepo: contactRepository,
      );
      final groupMessageListener = GroupMessageListener(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'share_picker_video_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final sourceVideo = File('${tempDir.path}/shared.mp4')
        ..writeAsStringSync('video');
      final group = _makeGroup(
        'group-1',
        'Writers',
        GroupType.chat,
        GroupRole.admin,
      );
      await groupRepository.saveGroup(group);
      final processor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => null,
        compressVideo: ({required path, required compress, onProgress}) async {
          final processed = File('$path.processed.mp4')
            ..writeAsStringSync('1234');
          return VideoProcessResult(path: processed.path);
        },
      );

      await pumpPicker(
        tester,
        contactRepository: contactRepository,
        groupRepository: groupRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        identityRepository: identityRepository,
        chatMessageListener: chatMessageListener,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        shareIntent: ShareIntent(
          type: ShareIntentType.mixed,
          text: 'https://mknoon.app/share',
          filePaths: [sourceVideo.path],
        ),
        imageProcessor: processor,
      );

      await tapAndAwaitRoute(
        tester,
        tapTarget: find.byKey(ValueKey('share-group-${group.id}')),
        routeTarget: find.byType(GroupConversationWired, skipOffstage: false),
      );

      final conversation = tester.widget<GroupConversationWired>(
        find.byType(GroupConversationWired, skipOffstage: false),
      );
      expect(conversation.initialText, 'https://mknoon.app/share');
      expect(conversation.initialAttachments, isNotNull);
      expect(conversation.initialAttachments, hasLength(1));
      expect(conversation.initialPendingMedia, isNotNull);
      expect(conversation.initialPendingMedia, hasLength(1));
      expect(
        conversation.initialAttachments!.first.path,
        '${sourceVideo.path}.processed.mp4',
      );
      expect(
        conversation.initialPendingMedia!.first.file.path,
        '${sourceVideo.path}.processed.mp4',
      );
      expect(conversation.initialPendingMedia!.first.budgetBytes, 4);
    },
  );

  testWidgets(
    '2o: shared images are processed via ImageProcessor on target selection',
    (tester) async {
      final contactRepository = InMemoryContactRepository();
      final groupRepository = InMemoryGroupRepository();
      final messageRepository = InMemoryMessageRepository();
      final mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
      final identityRepository = FakeIdentityRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      identityRepository.seed(_makeIdentity());
      final chatMessageListener = ChatMessageListener(
        chatMessageStream: const Stream<ChatMessage>.empty(),
        messageRepo: messageRepository,
        contactRepo: contactRepository,
      );
      final groupMessageListener = GroupMessageListener(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'share_picker_process_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final sourceImage = File('${tempDir.path}/shared.jpg')
        ..writeAsStringSync('image');
      final processedPaths = <String>[];

      contactRepository.addTestContact(activeContact);
      final processor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async {
              processedPaths.add(path);
              return XFile('$path.processed.jpg');
            },
        compressVideo: ({required path, required compress, onProgress}) async =>
            null,
      );

      await pumpPicker(
        tester,
        contactRepository: contactRepository,
        groupRepository: groupRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        identityRepository: identityRepository,
        chatMessageListener: chatMessageListener,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: [sourceImage.path],
        ),
        imageProcessor: processor,
      );

      await tapAndAwaitRoute(
        tester,
        tapTarget: find.byKey(ValueKey('share-contact-${activeContact.peerId}')),
        routeTarget: find.byType(ConversationWired, skipOffstage: false),
      );

      expect(processedPaths, [sourceImage.path]);
    },
  );

  testWidgets(
    'share target selection preserves raw budget bytes for original-quality media',
    (tester) async {
      final contactRepository = InMemoryContactRepository();
      final groupRepository = InMemoryGroupRepository();
      final messageRepository = InMemoryMessageRepository();
      final mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
      final identityRepository = FakeIdentityRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      identityRepository.seed(_makeIdentity());
      final chatMessageListener = ChatMessageListener(
        chatMessageStream: const Stream<ChatMessage>.empty(),
        messageRepo: messageRepository,
        contactRepo: contactRepository,
      );
      final groupMessageListener = GroupMessageListener(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'share_picker_original_budget_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final sourceImage = File('${tempDir.path}/shared.jpg')
        ..writeAsStringSync('1234567890');

      contactRepository.addTestContact(activeContact);
      final processor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async {
              final processed = File('$path.processed.jpg')
                ..writeAsStringSync('12');
              return XFile(processed.path);
            },
        compressVideo: ({required path, required compress, onProgress}) async =>
            null,
      );

      await pumpPicker(
        tester,
        contactRepository: contactRepository,
        groupRepository: groupRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        identityRepository: identityRepository,
        chatMessageListener: chatMessageListener,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: [sourceImage.path],
        ),
        imageProcessor: processor,
        qualityPreference: ImageQualityPreference.original,
      );

      await tapAndAwaitRoute(
        tester,
        tapTarget: find.byKey(ValueKey('share-contact-${activeContact.peerId}')),
        routeTarget: find.byType(ConversationWired, skipOffstage: false),
      );

      final conversation = tester.widget<ConversationWired>(
        find.byType(ConversationWired, skipOffstage: false),
      );
      expect(conversation.initialPendingMedia, isNotNull);
      expect(conversation.initialPendingMedia, hasLength(1));
      expect(
        conversation.initialPendingMedia!.first.file.path,
        '${sourceImage.path}.processed.jpg',
      );
      expect(conversation.initialPendingMedia!.first.budgetBytes, 10);
    },
  );

  testWidgets('2p: cancel pops back to the previous screen', (tester) async {
    final contactRepository = InMemoryContactRepository();
    final groupRepository = InMemoryGroupRepository();
    final messageRepository = InMemoryMessageRepository();
    final mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
    final identityRepository = FakeIdentityRepository();
    final groupMessageRepository = InMemoryGroupMessageRepository();
    identityRepository.seed(_makeIdentity());
    final chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
    );
    final groupMessageListener = GroupMessageListener(
      groupRepo: groupRepository,
      msgRepo: groupMessageRepository,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('launcher'),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ShareTargetPickerWired(
                          shareIntent: const ShareIntent(
                            type: ShareIntentType.text,
                            text: 'Shared hello',
                          ),
                          identityRepo: identityRepository,
                          contactRepository: contactRepository,
                          messageRepository: messageRepository,
                          mediaAttachmentRepository: mediaAttachmentRepository,
                          chatMessageListener: chatMessageListener,
                          bridge: FakeBridge(),
                          p2pService: FakeP2PService(),
                          mediaFileManager: FakeMediaFileManager(),
                          imageProcessor: ImageProcessor(
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
                                  onProgress,
                                }) async => null,
                          ),
                          groupRepository: groupRepository,
                          groupMessageRepository: groupMessageRepository,
                          groupMessageListener: groupMessageListener,
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Share with...'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('launcher'), findsOneWidget);
    expect(find.text('Share with...'), findsNothing);
  });

  testWidgets('shows loading indicator before targets finish loading', (
    tester,
  ) async {
    final contactRepository = _SlowContactRepository();
    final groupRepository = InMemoryGroupRepository();
    final messageRepository = InMemoryMessageRepository();
    final mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
    final identityRepository = FakeIdentityRepository();
    final groupMessageRepository = InMemoryGroupMessageRepository();
    identityRepository.seed(_makeIdentity());
    contactRepository.addTestContact(activeContact);

    final chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
    );
    final groupMessageListener = GroupMessageListener(
      groupRepo: groupRepository,
      msgRepo: groupMessageRepository,
    );

    await tester.pumpWidget(
      buildWidget(
        contactRepository: contactRepository,
        groupRepository: groupRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        identityRepository: identityRepository,
        chatMessageListener: chatMessageListener,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'Shared hello',
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Alice'), findsNothing);

    contactRepository.release();
    await tester.pump();
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'loading indicator replaced by empty state when no contacts exist',
    (tester) async {
      final contactRepository = InMemoryContactRepository();
      final groupRepository = InMemoryGroupRepository();
      final messageRepository = InMemoryMessageRepository();
      final mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
      final identityRepository = FakeIdentityRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      identityRepository.seed(_makeIdentity());

      final chatMessageListener = ChatMessageListener(
        chatMessageStream: const Stream<ChatMessage>.empty(),
        messageRepo: messageRepository,
        contactRepo: contactRepository,
      );
      final groupMessageListener = GroupMessageListener(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
      );

      await tester.pumpWidget(
        buildWidget(
          contactRepository: contactRepository,
          groupRepository: groupRepository,
          messageRepository: messageRepository,
          mediaAttachmentRepository: mediaAttachmentRepository,
          identityRepository: identityRepository,
          chatMessageListener: chatMessageListener,
          groupMessageRepository: groupMessageRepository,
          groupMessageListener: groupMessageListener,
          shareIntent: const ShareIntent(
            type: ShareIntentType.text,
            text: 'Shared hello',
          ),
        ),
      );

      // Initially shows loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Pump to allow _loadTargets to complete
      await tester.pump();
      await tester.pump();

      // Empty state shown, no spinner
      expect(find.text('No contacts or groups yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('loading indicator clears on error', (tester) async {
    final contactRepository = _ThrowingContactRepository();
    final groupRepository = InMemoryGroupRepository();
    final messageRepository = InMemoryMessageRepository();
    final mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
    final identityRepository = FakeIdentityRepository();
    final groupMessageRepository = InMemoryGroupMessageRepository();
    identityRepository.seed(_makeIdentity());

    final chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
    );
    final groupMessageListener = GroupMessageListener(
      groupRepo: groupRepository,
      msgRepo: groupMessageRepository,
    );

    await tester.pumpWidget(
      buildWidget(
        contactRepository: contactRepository,
        groupRepository: groupRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        identityRepository: identityRepository,
        chatMessageListener: chatMessageListener,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'Shared hello',
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    // No spinner stuck — empty state shown instead
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No contacts or groups yet'), findsOneWidget);
  });
}

ContactModel _makeContact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-09T08:00:00.000Z',
  );
}

GroupModel _makeGroup(String id, String name, GroupType type, GroupRole role) {
  return GroupModel(
    id: id,
    name: name,
    type: type,
    topicName: 'topic-$id',
    createdAt: DateTime.parse('2026-03-09T08:00:00.000Z'),
    createdBy: 'me',
    myRole: role,
  );
}

IdentityModel _makeIdentity() {
  return IdentityModel(
    peerId: 'me',
    publicKey: 'my-public-key',
    privateKey: 'my-private-key',
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    username: 'Me',
    createdAt: '2026-03-09T08:00:00.000Z',
    updatedAt: '2026-03-09T08:00:00.000Z',
  );
}

class _SlowContactRepository extends InMemoryContactRepository {
  final Completer<void> _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<List<ContactModel>> getActiveContacts() async {
    await _gate.future;
    return super.getActiveContacts();
  }
}

class _ThrowingContactRepository extends InMemoryContactRepository {
  @override
  Future<List<ContactModel>> getActiveContacts() async {
    throw Exception('Simulated contact loading error');
  }
}
