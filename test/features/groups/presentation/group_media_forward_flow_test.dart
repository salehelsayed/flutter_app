import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/announcement_media_forward_request.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_wired.dart';
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

// 236 TC-236-02/04/12: the forward-mode share picker narrows destinations to
// contacts and writable DISCUSSION groups, reloads every selected destination
// from its repository immediately before its upload (a missing/ineligible
// target is a failed result, never stale-picker fallback), seeds an editable
// caption from the source without ever mutating the source, and never offers
// or accepts a QA/non-admin announcement destination.

const _localPeerId = 'my-peer-id-12345';
const _srcGroupId = 'src-group';
const _srcMessageId = 'src-msg-1';
const _relayCiphertextHash =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

void main() {
  late InMemoryContactRepository contactRepository;
  late InMemoryGroupRepository groupRepository;
  late InMemoryMessageRepository messageRepository;
  late InMemoryGroupMessageRepository groupMessageRepository;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepository;
  late FakeIdentityRepository identityRepository;
  late FakeMediaFileManager fileManager;
  late ChatMessageListener chatMessageListener;
  late GroupMessageListener groupMessageListener;
  // Per-test canonical source lane. The production gate constructs this exact
  // group/attachment path from independently trusted app-owned authority.
  late Directory sourceDir;

  // Delivery observation: the REAL coordinator with send-lane spies. The
  // strict per-target revalidation runs in production code before either spy.
  late List<ContactModel> contactSends;
  late List<GroupModel> groupSends;
  late List<ShareIntent> contactSendIntents;
  late List<ShareIntent> groupSendIntents;
  late List<ShareIntent> processedIntents;
  late Completer<void> pickerForwardCompletion;

  setUp(() {
    contactRepository = InMemoryContactRepository();
    groupRepository = InMemoryGroupRepository();
    messageRepository = InMemoryMessageRepository();
    groupMessageRepository = InMemoryGroupMessageRepository();
    mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
    identityRepository = FakeIdentityRepository()..seed(_makeIdentity());
    fileManager = FakeMediaFileManager();
    sourceDir = Directory(
      p.join(FakeMediaFileManager.testRootPath, 'media', _srcGroupId),
    );
    if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
    sourceDir.createSync(recursive: true);
    chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
    );
    groupMessageListener = GroupMessageListener(
      groupRepo: groupRepository,
      msgRepo: groupMessageRepository,
    );
    contactSends = [];
    groupSends = [];
    contactSendIntents = [];
    groupSendIntents = [];
    processedIntents = [];
  });

  tearDown(() {
    if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
  });

  DefaultShareBatchDeliveryCoordinator buildCoordinator() {
    return DefaultShareBatchDeliveryCoordinator(
      identityRepository: identityRepository,
      contactRepository: contactRepository,
      messageRepository: messageRepository,
      mediaAttachmentRepository: mediaAttachmentRepository,
      groupRepository: groupRepository,
      groupMessageRepository: groupMessageRepository,
      bridge: FakeBridge(),
      p2pService: FakeP2PService(),
      mediaFileManager: fileManager,
      imageProcessor: _imageProcessor(),
      processSharedMediaFn: (intent) async {
        processedIntents.add(intent);
        final source = File(intent.filePaths.single);
        return ProcessedShareMediaBatch(
          processedMedia: [
            PendingComposerMedia(
              file: source,
              budgetBytes: source.lengthSync(),
            ),
          ],
        );
      },
      sendToContactFn:
          ({
            required identity,
            required shareIntent,
            required contact,
            required processedMedia,
            required uploadHooks,
          }) async {
            contactSends.add(contact);
            contactSendIntents.add(shareIntent);
            return ShareBatchTargetResult(
              target: ShareTargetSelection.contact(contact),
              status: ShareBatchTargetStatus.sent,
              detail: 'Sent.',
            );
          },
      sendToGroupFn:
          ({
            required identity,
            required shareIntent,
            required group,
            required processedMedia,
            required uploadHooks,
          }) async {
            groupSends.add(group);
            groupSendIntents.add(shareIntent);
            return ShareBatchTargetResult(
              target: ShareTargetSelection.group(group),
              status: ShareBatchTargetStatus.sent,
              detail: 'Sent.',
            );
          },
    );
  }

  /// Seeds the forward SOURCE: an incoming group parent message with one
  /// (or more) verified group-owned attachments backed by local plaintext.
  /// The stored hash deliberately represents a different relay-ciphertext
  /// byte domain and must never be compared to these local bytes.
  Future<List<String>> seedForwardSource({
    List<String> attachmentIds = const ['src-att-1'],
    String caption = 'original caption',
    GroupType sourceType = GroupType.chat,
  }) async {
    await _saveWritableGroup(
      groupRepository,
      _makeGroup(_srcGroupId, 'Source Group', sourceType, GroupRole.member),
      memberRole: sourceType == GroupType.announcement
          ? MemberRole.reader
          : null,
    );
    await groupMessageRepository.saveMessage(
      GroupMessage(
        id: _srcMessageId,
        groupId: _srcGroupId,
        senderPeerId: 'peer-sender',
        text: caption,
        timestamp: DateTime.utc(2026, 7, 10, 12),
        isIncoming: true,
        createdAt: DateTime.utc(2026, 7, 10, 12),
      ),
    );
    final resolvedPaths = <String>[];
    for (final (index, attachmentId) in attachmentIds.indexed) {
      final bytes = <int>[
        0xff,
        0xd8,
        0xff,
        0xe0,
        ...List<int>.generate(60 + index, (i) => (i * 7 + index) % 251),
      ];
      final file = File(p.join(sourceDir.path, '$attachmentId.jpg'));
      file.writeAsBytesSync(bytes);
      await mediaAttachmentRepository.saveAttachment(
        MediaAttachment(
          id: attachmentId,
          messageId: _srcMessageId,
          mime: 'image/jpeg',
          size: bytes.length,
          mediaType: 'image',
          localPath: file.path,
          downloadStatus: 'done',
          createdAt: '2026-07-10T12:00:00.000Z',
          contentHash: _relayCiphertextHash,
          encryptionKeyBase64: 'a2V5',
          encryptionNonce: 'bm9uY2U=',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.group,
        ),
        owner: MediaOwnerLane.group,
      );
      resolvedPaths.add(file.path);
    }
    return resolvedPaths;
  }

  GroupMediaForwardRequest forwardRequest({
    String attachmentId = 'src-att-1',
    String initialCaption = 'original caption',
    bool announcement = false,
  }) {
    const provenance = ForwardProvenance(operationDedupKey: 'op-flow-1');
    return announcement
        ? AnnouncementMediaForwardRequest(
            groupId: _srcGroupId,
            messageId: _srcMessageId,
            attachmentId: attachmentId,
            initialCaption: initialCaption,
            provenance: provenance,
          )
        : GroupMediaForwardRequest(
            groupId: _srcGroupId,
            messageId: _srcMessageId,
            attachmentId: attachmentId,
            initialCaption: initialCaption,
            provenance: provenance,
          );
  }

  Future<void> pumpPicker(
    WidgetTester tester, {
    GroupMediaForwardRequest? request,
    ShareIntent? shareIntent,
  }) async {
    final coordinator = buildCoordinator();
    if (request != null) {
      pickerForwardCompletion = Completer<void>();
    }
    final observedCoordinator = request == null
        ? coordinator
        : _ForwardCompletionCoordinator(
            delegate: coordinator,
            runRealAsync: (body) async {
              final result = await tester.runAsync(body);
              return result!;
            },
            onComplete: () {
              if (!pickerForwardCompletion.isCompleted) {
                pickerForwardCompletion.complete();
              }
            },
          );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ShareTargetPickerWired(
          // A fresh key per pump: re-pumping the same widget type would
          // otherwise REUSE the previous State and skip _loadTargets.
          key: UniqueKey(),
          shareIntent:
              shareIntent ??
              ShareIntent(
                type: ShareIntentType.mixed,
                text: request?.initialCaption,
              ),
          identityRepo: identityRepository,
          contactRepository: contactRepository,
          messageRepository: messageRepository,
          mediaAttachmentRepository: mediaAttachmentRepository,
          chatMessageListener: chatMessageListener,
          bridge: FakeBridge(),
          p2pService: FakeP2PService(),
          mediaFileManager: fileManager,
          imageProcessor: _imageProcessor(),
          groupRepository: groupRepository,
          groupMessageRepository: groupMessageRepository,
          groupMessageListener: groupMessageListener,
          batchShareCoordinator: observedCoordinator,
          groupMediaForwardRequest: request,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> tapSendAndSettle(WidgetTester tester) async {
    await tester.tap(find.text('Send'));
    await tester.pump();
    await pickerForwardCompletion.future.timeout(const Duration(seconds: 5));
    await tester.pump();
  }

  Future<void> seedDestinations() async {
    contactRepository.addTestContact(_makeContact('peer-alice', 'Alice'));
    contactRepository.addTestContact(_makeContact('peer-bob', 'Bob'));
    contactRepository.addTestContact(_makeContact('peer-carol', 'Carol'));
    await _saveWritableGroup(
      groupRepository,
      _makeGroup('dest-chat', 'Friends', GroupType.chat, GroupRole.member),
    );
    await _saveWritableGroup(
      groupRepository,
      _makeGroup(
        'ann-admin',
        'Admin Announcements',
        GroupType.announcement,
        GroupRole.admin,
      ),
    );
    await _saveWritableGroup(
      groupRepository,
      _makeGroup(
        'ann-member',
        'Announcements',
        GroupType.announcement,
        GroupRole.member,
      ),
    );
    await _saveWritableGroup(
      groupRepository,
      _makeGroup('qa-group', 'QA Corner', GroupType.qa, GroupRole.member),
    );
    await _saveWritableGroup(
      groupRepository,
      _makeGroup(
        'archived-chat',
        'Archived Group',
        GroupType.chat,
        GroupRole.member,
      ).copyWith(
        isArchived: true,
        archivedAt: DateTime.parse('2026-03-09T08:00:00.000Z'),
      ),
    );
    await _saveWritableGroup(
      groupRepository,
      _makeGroup(
        'dissolved-chat',
        'Dissolved Group',
        GroupType.chat,
        GroupRole.member,
      ).copyWith(
        isDissolved: true,
        dissolvedAt: DateTime.parse('2026-03-09T08:00:00.000Z'),
      ),
    );
  }

  testWidgets(
    'GMF-02 picker filters and revalidates current forwarding destinations before upload',
    (tester) async {
      await seedForwardSource();
      await seedDestinations();

      await pumpPicker(tester, request: forwardRequest());

      // Discussion-source destination filter: contacts and writable
      // discussion groups only. Announcement, QA, archived, and dissolved
      // groups remain excluded.
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
      expect(find.text('Friends'), findsOneWidget);
      expect(find.text('Admin Announcements'), findsNothing);
      expect(find.text('Announcements'), findsNothing);
      expect(find.text('QA Corner'), findsNothing);
      expect(find.text('Archived Group'), findsNothing);
      expect(find.text('Dissolved Group'), findsNothing);

      // Select three contacts and the discussion group.
      await tester.tap(find.text('Alice'));
      await tester.tap(find.text('Bob'));
      await tester.tap(find.text('Carol'));
      await tester.tap(find.text('Friends'));
      await tester.pump();

      // Mutations AFTER the picker loaded, BEFORE Send: Bob disappears, Carol
      // loses her encryption key, and Friends is renamed. Dispatch must see
      // the CURRENT repository state — never the stale picker objects.
      await contactRepository.deleteContact('peer-bob');
      contactRepository.addTestContact(
        _makeContact('peer-carol', 'Carol', mlKemPublicKey: null),
      );
      final renamed = (await groupRepository.getGroup(
        'dest-chat',
      ))!.copyWith(name: 'Renamed Friends');
      await groupRepository.saveGroup(renamed);

      await tapSendAndSettle(tester);

      // Exactly one contact delivery (Alice) — the missing contact and the
      // keyless contact failed BEFORE any send/upload attempt.
      expect(contactSends.map((c) => c.peerId), ['peer-alice']);
      // The group delivery received the RELOADED group, not the stale picker
      // object.
      expect(groupSends.map((g) => g.name), ['Renamed Friends']);
      // The verified source was processed exactly once for the whole batch.
      expect(processedIntents, hasLength(1));
      expect(
        processedIntents.single.forwardProvenance?.operationDedupKey,
        'op-flow-1',
      );

      // Coordinator-direct rows: current group existence/type/lifecycle/key/
      // membership all fail BEFORE upload with a typed failed result.
      final coordinator = buildCoordinator();
      final staleChat = _makeGroup(
        'dest-chat-2',
        'Second Friends',
        GroupType.chat,
        GroupRole.member,
      );

      Future<ShareBatchTargetResult> forwardTo(GroupModel target) async {
        late ShareBatchDeliveryResult result;
        await tester.runAsync(() async {
          result = await coordinator.deliverGroupMediaForward(
            request: forwardRequest(),
            caption: 'edited caption',
            targets: [ShareTargetSelection.group(target)],
          );
        });
        return result.results.single;
      }

      final groupSendsBefore = groupSends.length;

      // Missing group.
      expect(
        (await forwardTo(staleChat)).status,
        ShareBatchTargetStatus.failed,
        reason: 'a deleted destination group fails, never picker fallback',
      );

      // Type changed to QA, which is never a forwarding destination.
      await _saveWritableGroup(
        groupRepository,
        _makeGroup(
          'dest-chat-2',
          'Second Friends',
          GroupType.qa,
          GroupRole.admin,
        ),
      );
      expect(
        (await forwardTo(staleChat)).status,
        ShareBatchTargetStatus.failed,
      );

      // Dissolved current copy.
      await groupRepository.saveGroup(
        _makeGroup(
          'dest-chat-2',
          'Second Friends',
          GroupType.chat,
          GroupRole.member,
        ).copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.parse('2026-03-09T08:00:00.000Z'),
        ),
      );
      expect(
        (await forwardTo(staleChat)).status,
        ShareBatchTargetStatus.failed,
      );

      // Membership revoked (group present, key present, self not a member).
      await groupRepository.saveGroup(
        _makeGroup(
          'dest-chat-3',
          'Third Friends',
          GroupType.chat,
          GroupRole.member,
        ),
      );
      await _saveGroupKey(groupRepository, 'dest-chat-3');
      final unjoined = _makeGroup(
        'dest-chat-3',
        'Third Friends',
        GroupType.chat,
        GroupRole.member,
      );
      expect((await forwardTo(unjoined)).status, ShareBatchTargetStatus.failed);

      // Missing current group key.
      await groupRepository.saveGroup(
        _makeGroup(
          'dest-chat-4',
          'Fourth Friends',
          GroupType.chat,
          GroupRole.member,
        ),
      );
      await groupRepository.saveMember(
        _makeGroupMember(groupId: 'dest-chat-4', peerId: _localPeerId),
      );
      final keyless = _makeGroup(
        'dest-chat-4',
        'Fourth Friends',
        GroupType.chat,
        GroupRole.member,
      );
      expect((await forwardTo(keyless)).status, ShareBatchTargetStatus.failed);

      expect(
        groupSends.length,
        groupSendsBefore,
        reason: 'no ineligible destination ever reached the send/upload lane',
      );
    },
  );

  testWidgets(
    'GMF-04 editable caption and selected item are forwarded without source mutation',
    (tester) async {
      // Multi-attachment source: the request targets ONLY the second item.
      final resolvedPaths = await seedForwardSource(
        attachmentIds: ['src-att-1', 'src-att-2'],
      );
      final selectedPath = resolvedPaths[1];
      final originalBytes = <String, List<int>>{
        for (final path in resolvedPaths) path: File(path).readAsBytesSync(),
      };
      contactRepository.addTestContact(_makeContact('peer-alice', 'Alice'));
      await _saveWritableGroup(
        groupRepository,
        _makeGroup('dest-chat', 'Friends', GroupType.chat, GroupRole.member),
      );

      await pumpPicker(
        tester,
        request: forwardRequest(attachmentId: 'src-att-2'),
      );

      // The caption field seeds from the source caption.
      expect(find.text('original caption'), findsOneWidget);

      await tester.tap(find.text('Alice'));
      await tester.tap(find.text('Friends'));
      await tester.pump();
      await tester.enterText(find.text('original caption'), 'edited caption');
      await tapSendAndSettle(tester);

      // Only the viewer-selected attachment is read for delivery.
      expect(processedIntents, hasLength(1));
      expect(processedIntents.single.filePaths.single, isNot(selectedPath));
      // Every new target message uses the EDITED caption.
      expect(contactSendIntents.single.text, 'edited caption');
      expect(groupSendIntents.single.text, 'edited caption');

      // The source is untouched: parent text, both rows, and both files.
      final parent = await groupMessageRepository.getMessage(_srcMessageId);
      expect(parent!.text, 'original caption');
      final rows = await mediaAttachmentRepository.getAttachmentsForMessage(
        _srcMessageId,
        owner: MediaOwnerLane.group,
      );
      expect(rows.map((row) => row.id).toSet(), {'src-att-1', 'src-att-2'});
      for (final path in resolvedPaths) {
        expect(
          File(path).readAsBytesSync(),
          originalBytes[path],
          reason: 'forwarding never rewrites source media files',
        );
      }

      // A CLEARED caption yields captionless destination messages — the
      // picker maps an empty caption field to null (_composedCaption), and
      // the dispatch then omits text entirely. The source caption survives.
      contactSendIntents.clear();
      processedIntents.clear();
      late ShareBatchDeliveryResult cleared;
      await tester.runAsync(() async {
        cleared = await buildCoordinator().deliverGroupMediaForward(
          request: forwardRequest(attachmentId: 'src-att-2'),
          caption: null,
          targets: [
            ShareTargetSelection.contact(_makeContact('peer-alice', 'Alice')),
          ],
        );
      });
      expect(cleared.results.single.status, ShareBatchTargetStatus.sent);
      expect(contactSendIntents.single.text, isNull);
      expect(
        (await groupMessageRepository.getMessage(_srcMessageId))!.text,
        'original caption',
      );
    },
  );

  testWidgets(
    'GMF-02A picker keeps discussion and announcement forward target lanes distinct',
    (tester) async {
      await seedForwardSource();
      await seedDestinations();

      await pumpPicker(tester, request: forwardRequest());
      expect(find.text('Friends'), findsOneWidget);
      expect(find.text('Admin Announcements'), findsNothing);

      await seedForwardSource(sourceType: GroupType.announcement);
      await pumpPicker(tester, request: forwardRequest(announcement: true));
      expect(find.text('Friends'), findsOneWidget);
      expect(find.text('Admin Announcements'), findsOneWidget);
      expect(
        find.text('Source Group'),
        findsNothing,
        reason: 'the source announcement can never be its own destination',
      );
    },
  );

  testWidgets(
    'GMF-12 announcement forwarding allows admin destinations and preserves authoring rules',
    (tester) async {
      await seedForwardSource(sourceType: GroupType.announcement);
      await seedDestinations();

      // Plan 240 widens Forward mode to admin-writable announcement targets.
      await pumpPicker(tester, request: forwardRequest(announcement: true));
      expect(find.text('Admin Announcements'), findsOneWidget);
      expect(find.text('QA Corner'), findsNothing);
      expect(find.text('Friends'), findsOneWidget);

      // Control — ordinary OS share still offers the same admin target.
      await pumpPicker(
        tester,
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'Shared hello',
        ),
      );
      expect(find.text('Admin Announcements'), findsOneWidget);

      // Coordinator-direct also accepts the current admin announcement target.
      final coordinator = buildCoordinator();
      late ShareBatchDeliveryResult result;
      await tester.runAsync(() async {
        result = await coordinator.deliverGroupMediaForward(
          request: forwardRequest(announcement: true),
          caption: null,
          targets: [
            ShareTargetSelection.group(
              _makeGroup(
                'ann-admin',
                'Admin Announcements',
                GroupType.announcement,
                GroupRole.admin,
              ),
            ),
          ],
        );
      });
      expect(result.results.single.status, ShareBatchTargetStatus.sent);
      expect(groupSends.single.id, 'ann-admin');
    },
  );
}

class _ForwardCompletionCoordinator implements ShareBatchDeliveryCoordinator {
  const _ForwardCompletionCoordinator({
    required this.delegate,
    required this.runRealAsync,
    required this.onComplete,
  });

  final ShareBatchDeliveryCoordinator delegate;
  final Future<ShareBatchDeliveryResult> Function(
    Future<ShareBatchDeliveryResult> Function() body,
  )
  runRealAsync;
  final void Function() onComplete;

  @override
  Future<ShareBatchDeliveryResult> deliver({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
    ShareBatchDeliveryProgressCallback? onProgress,
  }) {
    return delegate.deliver(
      shareIntent: shareIntent,
      targets: targets,
      onProgress: onProgress,
    );
  }

  @override
  Future<ShareBatchDeliveryResult> deliverGroupMediaForward({
    required GroupMediaForwardRequest request,
    String? caption,
    required List<ShareTargetSelection> targets,
  }) {
    return runRealAsync(() async {
      try {
        return await delegate.deliverGroupMediaForward(
          request: request,
          caption: caption,
          targets: targets,
        );
      } finally {
        onComplete();
      }
    });
  }
}

ContactModel _makeContact(
  String peerId,
  String username, {
  String? mlKemPublicKey = 'mlkem-key',
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-09T08:00:00.000Z',
    mlKemPublicKey: mlKemPublicKey,
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
    peerId: _localPeerId,
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

GroupMember _makeGroupMember({
  required String groupId,
  required String peerId,
  MemberRole role = MemberRole.writer,
}) {
  return GroupMember(
    groupId: groupId,
    peerId: peerId,
    username: peerId == _localPeerId ? 'Me' : 'Other',
    role: role,
    joinedAt: DateTime.parse('2026-03-09T08:00:00.000Z'),
  );
}

Future<void> _saveGroupKey(
  InMemoryGroupRepository repository,
  String groupId,
) async {
  await repository.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: 1,
      encryptedKey: 'test-group-key-$groupId',
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

Future<void> _saveWritableGroup(
  InMemoryGroupRepository repository,
  GroupModel group, {
  String peerId = _localPeerId,
  MemberRole? memberRole,
}) async {
  await repository.saveGroup(group);
  await repository.saveMember(
    _makeGroupMember(
      groupId: group.id,
      peerId: peerId,
      role:
          memberRole ??
          (group.myRole == GroupRole.admin
              ? MemberRole.admin
              : MemberRole.writer),
    ),
  );
  await _saveGroupKey(repository, group.id);
}

ImageProcessor _imageProcessor() {
  return ImageProcessor(
    compressFile:
        ({
          required path,
          required quality,
          required keepExif,
          minWidth = 1920,
          minHeight = 1080,
        }) async => null,
    compressVideo: ({required path, required compress, onProgress}) async =>
        null,
  );
}
