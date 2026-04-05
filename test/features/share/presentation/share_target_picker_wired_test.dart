import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
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
    ShareBatchDeliveryCoordinator? batchShareCoordinator,
    Future<void> Function()? preSendReady,
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
              ({required path, required compress, onProgress}) async => null,
        ),
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        batchShareCoordinator: batchShareCoordinator,
        preSendReady: preSendReady,
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
    ShareBatchDeliveryCoordinator? batchShareCoordinator,
    Future<void> Function()? preSendReady,
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
        batchShareCoordinator: batchShareCoordinator,
        preSendReady: preSendReady,
      ),
    );
    await tester.pump();
    await tester.pump();
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

  testWidgets('first tap selects a contact without navigating', (tester) async {
    final harness = _buildHarness();
    final coordinator = _RecordingBatchCoordinator(
      result: const ShareBatchDeliveryResult(results: []),
    );

    harness.contactRepository.addTestContact(activeContact);
    await pumpPicker(
      tester,
      contactRepository: harness.contactRepository,
      groupRepository: harness.groupRepository,
      messageRepository: harness.messageRepository,
      mediaAttachmentRepository: harness.mediaAttachmentRepository,
      identityRepository: harness.identityRepository,
      chatMessageListener: harness.chatMessageListener,
      groupMessageRepository: harness.groupMessageRepository,
      groupMessageListener: harness.groupMessageListener,
      shareIntent: const ShareIntent(
        type: ShareIntentType.text,
        text: 'Shared hello',
      ),
      batchShareCoordinator: coordinator,
    );

    await tester.tap(
      find.byKey(ValueKey('share-contact-${activeContact.peerId}')),
    );
    await tester.pump();

    expect(find.text('Share with (1)'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(coordinator.deliverCallCount, 0);
  });

  testWidgets(
    'send invokes the coordinator exactly once with selected targets',
    (tester) async {
      final harness = _buildHarness();
      final group = _makeGroup(
        'group-1',
        'Writers',
        GroupType.chat,
        GroupRole.admin,
      );
      final coordinator = _RecordingBatchCoordinator(
        result: const ShareBatchDeliveryResult(results: []),
      );

      harness.contactRepository.addTestContact(activeContact);
      await harness.groupRepository.saveGroup(group);

      await pumpPicker(
        tester,
        contactRepository: harness.contactRepository,
        groupRepository: harness.groupRepository,
        messageRepository: harness.messageRepository,
        mediaAttachmentRepository: harness.mediaAttachmentRepository,
        identityRepository: harness.identityRepository,
        chatMessageListener: harness.chatMessageListener,
        groupMessageRepository: harness.groupMessageRepository,
        groupMessageListener: harness.groupMessageListener,
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'Shared hello',
        ),
        batchShareCoordinator: coordinator,
      );

      await tester.tap(
        find.byKey(ValueKey('share-contact-${activeContact.peerId}')),
      );
      await tester.tap(find.byKey(ValueKey('share-group-${group.id}')));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pump();

      expect(coordinator.deliverCallCount, 1);
      expect(coordinator.lastShareIntent?.text, 'Shared hello');
      expect(coordinator.lastTargets.map((target) => target.key).toList(), [
        ShareTargetSelection.contact(activeContact).key,
        ShareTargetSelection.group(group).key,
      ]);
    },
  );

  testWidgets('send waits for runtime readiness before delivery', (
    tester,
  ) async {
    final harness = _buildHarness();
    final coordinator = _RecordingBatchCoordinator(
      result: const ShareBatchDeliveryResult(results: []),
    );
    final runtimeReady = Completer<void>();

    harness.contactRepository.addTestContact(activeContact);

    await pumpPicker(
      tester,
      contactRepository: harness.contactRepository,
      groupRepository: harness.groupRepository,
      messageRepository: harness.messageRepository,
      mediaAttachmentRepository: harness.mediaAttachmentRepository,
      identityRepository: harness.identityRepository,
      chatMessageListener: harness.chatMessageListener,
      groupMessageRepository: harness.groupMessageRepository,
      groupMessageListener: harness.groupMessageListener,
      shareIntent: const ShareIntent(
        type: ShareIntentType.text,
        text: 'Shared hello',
      ),
      batchShareCoordinator: coordinator,
      preSendReady: () => runtimeReady.future,
    );

    await tester.tap(
      find.byKey(ValueKey('share-contact-${activeContact.peerId}')),
    );
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(coordinator.deliverCallCount, 0);

    runtimeReady.complete();
    await tester.pump();
    await tester.pump();

    expect(coordinator.deliverCallCount, 1);
  });

  testWidgets('edited caption is sent from the recipient picker', (
    tester,
  ) async {
    final harness = _buildHarness();
    final coordinator = _RecordingBatchCoordinator(
      result: const ShareBatchDeliveryResult(results: []),
    );

    harness.contactRepository.addTestContact(activeContact);

    await pumpPicker(
      tester,
      contactRepository: harness.contactRepository,
      groupRepository: harness.groupRepository,
      messageRepository: harness.messageRepository,
      mediaAttachmentRepository: harness.mediaAttachmentRepository,
      identityRepository: harness.identityRepository,
      chatMessageListener: harness.chatMessageListener,
      groupMessageRepository: harness.groupMessageRepository,
      groupMessageListener: harness.groupMessageListener,
      shareIntent: const ShareIntent(
        type: ShareIntentType.mixed,
        text: 'Old caption',
        filePaths: ['/tmp/shared-photo.jpg'],
      ),
      batchShareCoordinator: coordinator,
    );

    await tester.enterText(
      find.byKey(const ValueKey('share-caption-field')),
      'New caption',
    );
    await tester.tap(
      find.byKey(ValueKey('share-contact-${activeContact.peerId}')),
    );
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(coordinator.deliverCallCount, 1);
    expect(coordinator.lastShareIntent?.text, 'New caption');
    expect(coordinator.lastShareIntent?.type, ShareIntentType.mixed);
    expect(coordinator.lastShareIntent?.filePaths, const [
      '/tmp/shared-photo.jpg',
    ]);
  });

  testWidgets('successful send dismisses the picker', (tester) async {
    final harness = _buildHarness();
    final coordinator = _RecordingBatchCoordinator(
      result: ShareBatchDeliveryResult(
        results: [
          ShareBatchTargetResult(
            target: ShareTargetSelection.contact(activeContact),
            status: ShareBatchTargetStatus.sent,
            detail: 'Sent.',
          ),
        ],
      ),
    );
    harness.contactRepository.addTestContact(activeContact);

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
                          identityRepo: harness.identityRepository,
                          contactRepository: harness.contactRepository,
                          messageRepository: harness.messageRepository,
                          mediaAttachmentRepository:
                              harness.mediaAttachmentRepository,
                          chatMessageListener: harness.chatMessageListener,
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
                          groupRepository: harness.groupRepository,
                          groupMessageRepository:
                              harness.groupMessageRepository,
                          groupMessageListener: harness.groupMessageListener,
                          batchShareCoordinator: coordinator,
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
    await pumpPickerFrames(tester);
    await tester.tap(
      find.byKey(ValueKey('share-contact-${activeContact.peerId}')),
    );
    await tester.pump();
    await tester.tap(find.text('Send'));
    await pumpPickerFrames(tester);

    expect(find.text('launcher'), findsOneWidget);
    expect(find.text('Share with...'), findsNothing);
  });

  testWidgets('partial failure keeps only failed targets selected', (
    tester,
  ) async {
    final harness = _buildHarness();
    final group = _makeGroup(
      'group-1',
      'Writers',
      GroupType.chat,
      GroupRole.admin,
    );
    final coordinator = _RecordingBatchCoordinator(
      result: ShareBatchDeliveryResult(
        results: [
          ShareBatchTargetResult(
            target: ShareTargetSelection.contact(activeContact),
            status: ShareBatchTargetStatus.sent,
            detail: 'Sent.',
          ),
          ShareBatchTargetResult(
            target: ShareTargetSelection.group(group),
            status: ShareBatchTargetStatus.failed,
            detail: 'Share failed.',
          ),
        ],
      ),
    );

    harness.contactRepository.addTestContact(activeContact);
    await harness.groupRepository.saveGroup(group);

    await pumpPicker(
      tester,
      contactRepository: harness.contactRepository,
      groupRepository: harness.groupRepository,
      messageRepository: harness.messageRepository,
      mediaAttachmentRepository: harness.mediaAttachmentRepository,
      identityRepository: harness.identityRepository,
      chatMessageListener: harness.chatMessageListener,
      groupMessageRepository: harness.groupMessageRepository,
      groupMessageListener: harness.groupMessageListener,
      shareIntent: const ShareIntent(
        type: ShareIntentType.text,
        text: 'Shared hello',
      ),
      batchShareCoordinator: coordinator,
    );

    await tester.tap(
      find.byKey(ValueKey('share-contact-${activeContact.peerId}')),
    );
    await tester.tap(find.byKey(ValueKey('share-group-${group.id}')));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(find.text('Share with (1)'), findsOneWidget);
    expect(find.text('Sent to 1 target, failed for 1 target.'), findsOneWidget);
  });

  testWidgets('2p: cancel pops back to the previous screen', (tester) async {
    final harness = _buildHarness();

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
                          identityRepo: harness.identityRepository,
                          contactRepository: harness.contactRepository,
                          messageRepository: harness.messageRepository,
                          mediaAttachmentRepository:
                              harness.mediaAttachmentRepository,
                          chatMessageListener: harness.chatMessageListener,
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
                          groupRepository: harness.groupRepository,
                          groupMessageRepository:
                              harness.groupMessageRepository,
                          groupMessageListener: harness.groupMessageListener,
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
    await pumpPickerFrames(tester);
    await tester.tap(find.byIcon(Icons.close));
    await pumpPickerFrames(tester);

    expect(find.text('launcher'), findsOneWidget);
    expect(find.text('Share with...'), findsNothing);
  });
}

_Harness _buildHarness() {
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

  return _Harness(
    contactRepository: contactRepository,
    groupRepository: groupRepository,
    messageRepository: messageRepository,
    mediaAttachmentRepository: mediaAttachmentRepository,
    identityRepository: identityRepository,
    groupMessageRepository: groupMessageRepository,
    chatMessageListener: chatMessageListener,
    groupMessageListener: groupMessageListener,
  );
}

class _Harness {
  final InMemoryContactRepository contactRepository;
  final InMemoryGroupRepository groupRepository;
  final InMemoryMessageRepository messageRepository;
  final InMemoryMediaAttachmentRepository mediaAttachmentRepository;
  final FakeIdentityRepository identityRepository;
  final InMemoryGroupMessageRepository groupMessageRepository;
  final ChatMessageListener chatMessageListener;
  final GroupMessageListener groupMessageListener;

  const _Harness({
    required this.contactRepository,
    required this.groupRepository,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.identityRepository,
    required this.groupMessageRepository,
    required this.chatMessageListener,
    required this.groupMessageListener,
  });
}

Future<void> pumpPickerFrames(WidgetTester tester, {int count = 20}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _RecordingBatchCoordinator implements ShareBatchDeliveryCoordinator {
  final ShareBatchDeliveryResult result;
  int deliverCallCount = 0;
  ShareIntent? lastShareIntent;
  List<ShareTargetSelection> lastTargets = const [];

  _RecordingBatchCoordinator({required this.result});

  @override
  Future<ShareBatchDeliveryResult> deliver({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
  }) async {
    deliverCallCount++;
    lastShareIntent = shareIntent;
    lastTargets = List<ShareTargetSelection>.from(targets);
    return result;
  }
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
    peerId: 'my-peer-id-12345',
    publicKey: 'my-public-key',
    privateKey: 'my-private-key',
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    mlKemPublicKey: 'mlkem-public',
    mlKemSecretKey: 'mlkem-secret',
    username: 'Me',
    createdAt: '2026-03-09T08:00:00.000Z',
    updatedAt: '2026-03-09T08:00:00.000Z',
  );
}
