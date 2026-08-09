import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:flutter_app/core/constants/media_constants.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_direct_media_custody_stage_result.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

class _DissolveOnForwardSnapshotRepository extends InMemoryGroupRepository {
  _DissolveOnForwardSnapshotRepository({required this.snapshotCall});

  final int snapshotCall;
  var _snapshotCalls = 0;

  @override
  Future<GroupForwardAuthorizationSnapshot?>
  loadGroupForwardAuthorizationSnapshot(String groupId) async {
    _snapshotCalls += 1;
    if (_snapshotCalls == snapshotCall) {
      final current = await super.getGroup(groupId);
      if (current != null) {
        await super.updateGroup(
          current.copyWith(
            isDissolved: true,
            dissolvedAt: DateTime.utc(2026, 7, 22, 13),
            dissolvedBy: 'peer-remote-admin',
          ),
        );
      }
    }
    return super.loadGroupForwardAuthorizationSnapshot(groupId);
  }
}

class _DissolveAfterFirstGroupUploadBridge extends PassthroughCryptoBridge {
  _DissolveAfterFirstGroupUploadBridge({
    required this.groupRepo,
    required this.groupId,
  });

  final InMemoryGroupRepository groupRepo;
  final String groupId;
  var _uploadCalls = 0;

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    final response = await super.send(message);
    if (decoded['cmd'] == 'media:upload' && ++_uploadCalls == 1) {
      unawaited(
        runGroupMembershipMutationLocked<void>(
          groupId: groupId,
          action: () async {
            final current = await groupRepo.getGroup(groupId);
            if (current != null) {
              await groupRepo.updateGroup(
                current.copyWith(
                  isDissolved: true,
                  dissolvedAt: DateTime.utc(2026, 7, 22, 13, 5),
                  dissolvedBy: 'peer-remote-admin',
                ),
              );
            }
          },
        ),
      );
    }
    return response;
  }
}

void main() {
  test('does nothing when no targets are selected', () async {
    final identityRepository = FakeIdentityRepository()..seed(_makeIdentity());
    var processCallCount = 0;
    var contactCallCount = 0;

    final coordinator = DefaultShareBatchDeliveryCoordinator(
      identityRepository: identityRepository,
      contactRepository: InMemoryContactRepository(),
      messageRepository: InMemoryMessageRepository(),
      mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
      groupRepository: InMemoryGroupRepository(),
      groupMessageRepository: InMemoryGroupMessageRepository(),
      bridge: FakeBridge(),
      p2pService: FakeP2PService(),
      mediaFileManager: FakeMediaFileManager(),
      imageProcessor: _imageProcessor(),
      processSharedMediaFn: (_) async {
        processCallCount++;
        return const ProcessedShareMediaBatch(processedMedia: []);
      },
      sendToContactFn:
          ({
            required identity,
            required shareIntent,
            required contact,
            required processedMedia,
            required uploadHooks,
          }) async {
            contactCallCount++;
            return ShareBatchTargetResult(
              target: ShareTargetSelection.contact(contact),
              status: ShareBatchTargetStatus.sent,
              detail: 'Sent.',
            );
          },
    );

    final result = await coordinator.deliver(
      shareIntent: const ShareIntent(type: ShareIntentType.text, text: 'hello'),
      targets: const [],
    );

    expect(result.results, isEmpty);
    expect(processCallCount, 0);
    expect(contactCallCount, 0);
  });

  test(
    'direct picker authority fails all targets before preprocessing or send after parent delete/private transition',
    () async {
      for (final transition in <String>['deleted', 'private']) {
        final messageRepository = InMemoryMessageRepository();
        final mediaRepository = InMemoryMediaAttachmentRepository();
        final messageId = 'direct-transition-$transition';
        final attachmentId = 'direct-transition-$transition-attachment';
        final parent = ConversationMessage(
          id: messageId,
          contactPeerId: 'direct-source-peer',
          senderPeerId: 'direct-source-peer',
          text: 'picker-era caption',
          timestamp: '2026-07-14T12:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-07-14T12:00:00.000Z',
          deletedAt: transition == 'deleted'
              ? '2026-07-14T12:01:00.000Z'
              : null,
          privateMediaPolicy: transition == 'private'
              ? const PrivateMediaPolicy.protected()
              : const PrivateMediaPolicy.ordinary(),
          privateMediaState: transition == 'private'
              ? PrivateMediaLifecycleState.available
              : PrivateMediaLifecycleState.none,
        );
        await messageRepository.saveMessage(parent);
        await mediaRepository.saveAttachment(
          MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 14,
            mediaType: 'image',
            localPath: 'media/direct-source-peer/$attachmentId.jpg',
            downloadStatus: 'done',
            createdAt: '2026-07-14T12:00:00.000Z',
            contentHash: List.filled(64, 'a').join(),
            encryptionKeyBase64: 'relay-key',
            encryptionNonce: 'relay-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ownerLane: MediaOwnerLane.direct,
          ),
          owner: MediaOwnerLane.direct,
        );
        var processCallCount = 0;
        var contactSendCount = 0;
        var groupSendCount = 0;
        final currentContact = _makeMlKemContact(
          'transition-contact',
          'Contact',
        );
        final contactRepository = InMemoryContactRepository()
          ..addTestContact(currentContact);
        final currentGroup = _makeGroup('transition-group', 'Group');
        final groupRepository = InMemoryGroupRepository();
        await groupRepository.saveGroup(currentGroup);
        await _seedGroupMembers(groupRepository, currentGroup.id);
        await _saveLatestGroupKey(groupRepository, currentGroup.id);
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
          contactRepository: contactRepository,
          messageRepository: messageRepository,
          mediaAttachmentRepository: mediaRepository,
          groupRepository: groupRepository,
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: FakeBridge(),
          p2pService: FakeP2PService(),
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (_) async {
            processCallCount++;
            return const ProcessedShareMediaBatch(processedMedia: []);
          },
          sendToContactFn:
              ({
                required identity,
                required shareIntent,
                required contact,
                required processedMedia,
                required uploadHooks,
              }) async {
                contactSendCount++;
                return ShareBatchTargetResult(
                  target: ShareTargetSelection.contact(contact),
                  status: ShareBatchTargetStatus.sent,
                  detail: 'must not send',
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
                groupSendCount++;
                return ShareBatchTargetResult(
                  target: ShareTargetSelection.group(group),
                  status: ShareBatchTargetStatus.sent,
                  detail: 'must not send',
                );
              },
        );

        final result = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: const ['/stale/picker/path.jpg'],
            forwardProvenance: ForwardProvenance(
              operationDedupKey: 'direct-operation-$transition',
            ),
            directForwardSourceAuthority: DirectForwardSourceAuthority(
              contactPeerId: parent.contactPeerId,
              messageId: messageId,
              attachmentIds: [attachmentId],
            ),
          ),
          targets: [
            ShareTargetSelection.contact(currentContact),
            ShareTargetSelection.group(currentGroup),
          ],
        );

        expect(result.failureCount, 2, reason: transition);
        expect(result.sentCount, 0, reason: transition);
        expect(processCallCount, 0, reason: transition);
        expect(contactSendCount, 0, reason: transition);
        expect(groupSendCount, 0, reason: transition);
      }
    },
  );

  test(
    'direct snapshot final parent authority rejects delete hidden private and terminal drift with zero delivery side effects',
    () async {
      final fixtureBytes = File(
        'integration_test/fixtures/received_media_egress_fixture.jpg',
      ).readAsBytesSync();
      for (final scenario in <String>[
        'deleted',
        'hidden',
        'private',
        'terminal',
      ]) {
        final snapshotRoot = Directory(
          path.join(
            FakeMediaFileManager.testRootPath,
            MediaFileManager.groupForwardSnapshotRootDirectoryName,
          ),
        );
        if (snapshotRoot.existsSync()) {
          snapshotRoot.deleteSync(recursive: true);
        }
        final messageId = 'final-parent-$scenario-message';
        final attachmentId = 'final-parent-$scenario-attachment';
        const sourcePeerId = 'final-parent-source-peer';
        final parent = ConversationMessage(
          id: messageId,
          contactPeerId: sourcePeerId,
          senderPeerId: sourcePeerId,
          text: 'source caption',
          timestamp: '2026-07-14T12:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-07-14T12:00:00.000Z',
        );
        final mutatedParent = switch (scenario) {
          'deleted' => parent.copyWith(deletedAt: '2026-07-14T12:01:00.000Z'),
          'hidden' => parent.copyWith(hiddenAt: '2026-07-14T12:01:00.000Z'),
          'private' => parent.copyWith(
            privateMediaPolicy: const PrivateMediaPolicy.protected(),
            privateMediaState: PrivateMediaLifecycleState.available,
          ),
          _ => parent.copyWith(
            privateMediaPolicy: const PrivateMediaPolicy.viewOnce(),
            privateMediaState: PrivateMediaLifecycleState.consumed,
          ),
        };
        final canonical = File(
          path.join(
            FakeMediaFileManager.testRootPath,
            'media',
            sourcePeerId,
            '$attachmentId.jpg',
          ),
        );
        canonical.parent.createSync(recursive: true);
        canonical.writeAsBytesSync(fixtureBytes);
        final messageRepository = InMemoryMessageRepository();
        await messageRepository.saveMessage(parent);
        final mediaRepository = _ExactRowAwaitMutationRepository();
        await mediaRepository.saveAttachment(
          MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: fixtureBytes.length,
            mediaType: 'image',
            localPath: path.join('media', sourcePeerId, '$attachmentId.jpg'),
            downloadStatus: 'done',
            createdAt: '2026-07-14T12:00:00.000Z',
            contentHash: List.filled(64, 'a').join(),
            encryptionKeyBase64: 'relay-key',
            encryptionNonce: 'relay-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ownerLane: MediaOwnerLane.direct,
          ),
          owner: MediaOwnerLane.direct,
        );
        mediaRepository.onExactRowAwait = (callCount) async {
          // Capture preflight consumes reads 1-2. Read 3 follows immutable
          // snapshot copy/signature validation and precedes final parent read.
          if (callCount != 3) return;
          await messageRepository.saveMessage(mutatedParent);
          await Future<void>.delayed(Duration.zero);
        };
        final contact = _makeMlKemContact(
          'final-parent-target-$scenario',
          'Target $scenario',
        );
        final contacts = InMemoryContactRepository()..addTestContact(contact);
        final bridge = FakeBridge();
        var processCalls = 0;
        var sendCalls = 0;
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
          contactRepository: contacts,
          messageRepository: messageRepository,
          mediaAttachmentRepository: mediaRepository,
          groupRepository: InMemoryGroupRepository(),
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: bridge,
          p2pService: FakeP2PService(),
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (_) async {
            processCalls++;
            return const ProcessedShareMediaBatch(processedMedia: []);
          },
          sendToContactFn:
              ({
                required identity,
                required shareIntent,
                required contact,
                required processedMedia,
                required uploadHooks,
              }) async {
                sendCalls++;
                return ShareBatchTargetResult(
                  target: ShareTargetSelection.contact(contact),
                  status: ShareBatchTargetStatus.sent,
                  detail: 'must not send',
                );
              },
        );

        final result = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: const ['/stale/picker/source.jpg'],
            forwardProvenance: ForwardProvenance(
              operationDedupKey: 'final-parent-$scenario-operation',
            ),
            directForwardSourceAuthority: DirectForwardSourceAuthority(
              contactPeerId: sourcePeerId,
              messageId: messageId,
              attachmentIds: [attachmentId],
            ),
          ),
          targets: [ShareTargetSelection.contact(contact)],
        );

        expect(result.failureCount, 1, reason: scenario);
        expect(result.sentCount, 0, reason: scenario);
        expect(mediaRepository.exactRowReadCount, 3, reason: scenario);
        expect(processCalls, 0, reason: scenario);
        expect(sendCalls, 0, reason: scenario);
        expect(bridge.sendCallCount, 0, reason: scenario);
        expect(
          snapshotRoot.existsSync() ? snapshotRoot.listSync() : const [],
          isEmpty,
          reason: '$scenario snapshot lease must be disposed',
        );
      }
    },
  );

  test(
    'internal forwards reject missing blocked archived and keyless contacts before preprocessing or send',
    () async {
      for (final scenario in <String>[
        'missing',
        'blocked',
        'archived',
        'missing-encryption-key',
      ]) {
        final stale = _makeMlKemContact(
          'current-contact-$scenario',
          'Stale $scenario',
        );
        final contacts = InMemoryContactRepository();
        final current = switch (scenario) {
          'blocked' => stale.copyWith(isBlocked: true),
          'archived' => stale.copyWith(isArchived: true),
          'missing-encryption-key' => _makeContact(
            stale.peerId,
            'Keyless current contact',
          ),
          _ => null,
        };
        if (current != null) contacts.addTestContact(current);
        final bridge = FakeBridge();
        var processCalls = 0;
        var contactSendCalls = 0;
        var groupSendCalls = 0;
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
          contactRepository: contacts,
          messageRepository: InMemoryMessageRepository(),
          mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
          groupRepository: InMemoryGroupRepository(),
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: bridge,
          p2pService: FakeP2PService(),
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (_) async {
            processCalls++;
            return const ProcessedShareMediaBatch(processedMedia: []);
          },
          sendToContactFn:
              ({
                required identity,
                required shareIntent,
                required contact,
                required processedMedia,
                required uploadHooks,
              }) async {
                contactSendCalls++;
                return ShareBatchTargetResult(
                  target: ShareTargetSelection.contact(contact),
                  status: ShareBatchTargetStatus.sent,
                  detail: 'must not send',
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
                groupSendCalls++;
                return ShareBatchTargetResult(
                  target: ShareTargetSelection.group(group),
                  status: ShareBatchTargetStatus.sent,
                  detail: 'must not send',
                );
              },
        );

        final result = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: const ['/stale/picker/source.jpg'],
            forwardProvenance: ForwardProvenance(
              operationDedupKey: 'contact-drift-$scenario',
            ),
          ),
          targets: [ShareTargetSelection.contact(stale)],
        );

        expect(result.failureCount, 1, reason: scenario);
        expect(result.sentCount, 0, reason: scenario);
        expect(processCalls, 0, reason: scenario);
        expect(contactSendCalls, 0, reason: scenario);
        expect(groupSendCalls, 0, reason: scenario);
        expect(bridge.sendCallCount, 0, reason: scenario);
      }
    },
  );

  test(
    'internal forwards reject missing archived dissolved and keyless groups before preprocessing or send',
    () async {
      for (final scenario in <String>[
        'missing',
        'archived',
        'dissolved',
        'missing-encryption-key',
      ]) {
        final stale = _makeGroup('current-group-$scenario', 'Stale $scenario');
        final groups = InMemoryGroupRepository();
        if (scenario != 'missing') {
          final current = switch (scenario) {
            'archived' => stale.copyWith(
              isArchived: true,
              archivedAt: DateTime.parse('2026-07-14T12:00:00.000Z'),
            ),
            'dissolved' => stale.copyWith(
              isDissolved: true,
              dissolvedAt: DateTime.parse('2026-07-14T12:00:00.000Z'),
            ),
            _ => stale,
          };
          await groups.saveGroup(current);
          await _seedGroupMembers(groups, current.id);
          if (scenario != 'missing-encryption-key') {
            await _saveLatestGroupKey(groups, current.id);
          }
        }
        final bridge = FakeBridge();
        var processCalls = 0;
        var contactSendCalls = 0;
        var groupSendCalls = 0;
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
          contactRepository: InMemoryContactRepository(),
          messageRepository: InMemoryMessageRepository(),
          mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
          groupRepository: groups,
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: bridge,
          p2pService: FakeP2PService(),
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (_) async {
            processCalls++;
            return const ProcessedShareMediaBatch(processedMedia: []);
          },
          sendToContactFn:
              ({
                required identity,
                required shareIntent,
                required contact,
                required processedMedia,
                required uploadHooks,
              }) async {
                contactSendCalls++;
                return ShareBatchTargetResult(
                  target: ShareTargetSelection.contact(contact),
                  status: ShareBatchTargetStatus.sent,
                  detail: 'must not send',
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
                groupSendCalls++;
                return ShareBatchTargetResult(
                  target: ShareTargetSelection.group(group),
                  status: ShareBatchTargetStatus.sent,
                  detail: 'must not send',
                );
              },
        );

        final result = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: const ['/stale/picker/source.jpg'],
            forwardProvenance: ForwardProvenance(
              operationDedupKey: 'group-drift-$scenario',
            ),
          ),
          targets: [ShareTargetSelection.group(stale)],
        );

        expect(result.failureCount, 1, reason: scenario);
        expect(result.sentCount, 0, reason: scenario);
        expect(processCalls, 0, reason: scenario);
        expect(contactSendCalls, 0, reason: scenario);
        expect(groupSendCalls, 0, reason: scenario);
        expect(bridge.sendCallCount, 0, reason: scenario);
      }
    },
  );

  test(
    'processes shared media once before fanout across target kinds',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final processedMedia = [
        PendingComposerMedia(file: File('/tmp/shared.jpg'), budgetBytes: 42),
      ];
      var processCallCount = 0;
      List<PendingComposerMedia>? contactMedia;
      List<PendingComposerMedia>? groupMedia;

      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (_) async {
          processCallCount++;
          return ProcessedShareMediaBatch(processedMedia: processedMedia);
        },
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
              required uploadHooks,
            }) async {
              contactMedia = processedMedia;
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
              groupMedia = processedMedia;
              return ShareBatchTargetResult(
                target: ShareTargetSelection.group(group),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
      );

      final contact = _makeContact('peer-alice', 'Alice');
      final group = _makeGroup('group-1', 'Writers');

      await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: const ['/tmp/shared.jpg'],
        ),
        targets: [
          ShareTargetSelection.contact(contact),
          ShareTargetSelection.group(group),
        ],
      );

      expect(processCallCount, 1);
      expect(identical(contactMedia, processedMedia), isTrue);
      expect(identical(groupMedia, processedMedia), isTrue);
    },
  );

  test(
    'external batch progress clamps cumulative bytes and rejects unrelated or late upload ids',
    () async {
      final progressEvents = StreamController<Map<String, dynamic>>.broadcast(
        sync: true,
      );
      addTearDown(progressEvents.close);
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final processedMedia = [
        PendingComposerMedia(file: File('/tmp/first.jpg'), budgetBytes: 100),
        PendingComposerMedia(file: File('/tmp/second.jpg'), budgetBytes: 200),
      ];
      final observed = <ShareBatchDeliveryProgress>[];

      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        mediaUploadProgressEvents: progressEvents.stream,
        processSharedMediaFn: (_) async =>
            ProcessedShareMediaBatch(processedMedia: processedMedia),
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
              required uploadHooks,
            }) async {
              uploadHooks.started(blobId: 'contact-1', budgetBytes: 100);
              progressEvents.add({'id': 'unrelated', 'sentBytes': 77});
              progressEvents.add({'id': 'contact-1', 'sentBytes': 116});
              uploadHooks.settled(succeeded: true);
              progressEvents.add({'id': 'contact-1', 'sentBytes': 100});

              uploadHooks.started(blobId: 'contact-2', budgetBytes: 200);
              uploadHooks.settled(succeeded: true);
              uploadHooks.sending();
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
              uploadHooks.started(blobId: 'group-1', budgetBytes: 100);
              progressEvents.add({'id': 'group-1', 'sentBytes': 40});
              uploadHooks.settled(succeeded: true);

              uploadHooks.started(blobId: 'group-2', budgetBytes: 200);
              progressEvents.add({'id': 'group-2', 'sentBytes': 216});
              uploadHooks.settled(succeeded: true);
              uploadHooks.sending();
              return ShareBatchTargetResult(
                target: ShareTargetSelection.group(group),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
      );

      await coordinator.deliver(
        shareIntent: const ShareIntent(
          type: ShareIntentType.files,
          filePaths: ['/tmp/first.jpg', '/tmp/second.jpg'],
        ),
        targets: [
          ShareTargetSelection.contact(
            _makeContact('progress-contact', 'Contact'),
          ),
          ShareTargetSelection.group(_makeGroup('progress-group', 'Group')),
        ],
        onProgress: observed.add,
      );

      expect(observed, isNotEmpty);
      expect(observed.last.sentBytes, 600);
      expect(observed.last.totalBytes, 600);
      expect(observed.last.phase, ShareBatchDeliveryPhase.sending);
      expect(
        observed.map((event) => event.sentBytes),
        orderedEquals([...observed.map((event) => event.sentBytes)]..sort()),
      );
      expect(
        observed.every(
          (event) =>
              event.sentBytes >= 0 && event.sentBytes <= event.totalBytes,
        ),
        isTrue,
      );
      expect(observed.any((event) => event.sentBytes == 77), isFalse);
      expect(observed.any((event) => event.sentBytes == 100), isTrue);

      final partialEvents = StreamController<Map<String, dynamic>>.broadcast(
        sync: true,
      );
      addTearDown(partialEvents.close);
      final partialObserved = <ShareBatchDeliveryProgress>[];
      final partialCoordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        mediaUploadProgressEvents: partialEvents.stream,
        processSharedMediaFn: (_) async =>
            ProcessedShareMediaBatch(processedMedia: [processedMedia.first]),
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
              required uploadHooks,
            }) async {
              uploadHooks.started(blobId: 'failed-blob', budgetBytes: 100);
              partialEvents.add({'id': 'failed-blob', 'sentBytes': 40});
              throw StateError('upload failed after partial progress');
            },
        sendToGroupFn:
            ({
              required identity,
              required shareIntent,
              required group,
              required processedMedia,
              required uploadHooks,
            }) async {
              uploadHooks.started(blobId: 'next-blob', budgetBytes: 100);
              partialEvents.add({'id': 'next-blob', 'sentBytes': 100});
              uploadHooks.settled(succeeded: true);
              uploadHooks.sending();
              return ShareBatchTargetResult(
                target: ShareTargetSelection.group(group),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
      );

      await partialCoordinator.deliver(
        shareIntent: const ShareIntent(
          type: ShareIntentType.files,
          filePaths: ['/tmp/first.jpg'],
        ),
        targets: [
          ShareTargetSelection.contact(
            _makeContact('partial-contact', 'Contact'),
          ),
          ShareTargetSelection.group(_makeGroup('partial-group', 'Group')),
        ],
        onProgress: partialObserved.add,
      );

      expect(partialObserved.last.sentBytes, 140);
      expect(partialObserved.last.totalBytes, 200);
      expect(
        partialObserved.map((event) => event.sentBytes),
        orderedEquals(
          [...partialObserved.map((event) => event.sentBytes)]..sort(),
        ),
      );
    },
  );

  test(
    'external batch progress uses the production media upload stream by default',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final observed = <ShareBatchDeliveryProgress>[];
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
          processedMedia: [
            PendingComposerMedia(
              file: File('/tmp/production-default.jpg'),
              budgetBytes: 50,
            ),
          ],
        ),
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
              required uploadHooks,
            }) async {
              uploadHooks.started(
                blobId: 'production-default-blob',
                budgetBytes: 50,
              );
              emitMediaUploadProgressEvent({
                'id': 'production-default-blob',
                'sentBytes': 25,
              });
              uploadHooks.settled(succeeded: true);
              uploadHooks.sending();
              return ShareBatchTargetResult(
                target: ShareTargetSelection.contact(contact),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
      );

      await coordinator.deliver(
        shareIntent: const ShareIntent(
          type: ShareIntentType.files,
          filePaths: ['/tmp/production-default.jpg'],
        ),
        targets: [
          ShareTargetSelection.contact(
            _makeContact('production-contact', 'Contact'),
          ),
        ],
        onProgress: observed.add,
      );

      expect(observed.any((event) => event.sentBytes == 25), isTrue);
      expect(observed.last.sentBytes, 50);
      expect(observed.last.phase, ShareBatchDeliveryPhase.sending);
    },
  );

  test('reports sent queued and failed results truthfully', () async {
    final identityRepository = FakeIdentityRepository()..seed(_makeIdentity());
    final coordinator = DefaultShareBatchDeliveryCoordinator(
      identityRepository: identityRepository,
      contactRepository: InMemoryContactRepository(),
      messageRepository: InMemoryMessageRepository(),
      mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
      groupRepository: InMemoryGroupRepository(),
      groupMessageRepository: InMemoryGroupMessageRepository(),
      bridge: FakeBridge(),
      p2pService: FakeP2PService(),
      mediaFileManager: FakeMediaFileManager(),
      imageProcessor: _imageProcessor(),
      processSharedMediaFn: (_) async =>
          const ProcessedShareMediaBatch(processedMedia: []),
      sendToContactFn:
          ({
            required identity,
            required shareIntent,
            required contact,
            required processedMedia,
            required uploadHooks,
          }) async {
            return ShareBatchTargetResult(
              target: ShareTargetSelection.contact(contact),
              status: contact.peerId == 'peer-alice'
                  ? ShareBatchTargetStatus.sent
                  : ShareBatchTargetStatus.failed,
              detail: contact.peerId == 'peer-alice'
                  ? 'Sent.'
                  : 'Share failed.',
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
            return ShareBatchTargetResult(
              target: ShareTargetSelection.group(group),
              status: ShareBatchTargetStatus.queued,
              detail: 'Saved for retry.',
            );
          },
    );

    final sentContact = _makeContact('peer-alice', 'Alice');
    final failedContact = _makeContact('peer-bob', 'Bob');
    final group = _makeGroup('group-1', 'Writers');

    final result = await coordinator.deliver(
      shareIntent: const ShareIntent(type: ShareIntentType.text, text: 'hello'),
      targets: [
        ShareTargetSelection.contact(sentContact),
        ShareTargetSelection.contact(failedContact),
        ShareTargetSelection.group(group),
      ],
    );

    expect(result.sentCount, 1);
    expect(result.queuedCount, 1);
    expect(result.failureCount, 1);
    expect(result.hasFailures, isTrue);
    expect(result.failedTargetKeys, {
      ShareTargetSelection.contact(failedContact).key,
    });
  });

  test(
    'mixed share skips oversized GIFs while keeping valid sibling media',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final tempDir = await Directory.systemTemp.createTemp(
        'share_batch_gif_mixed_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final oversizedGif = File('${tempDir.path}/too-big.gif');
      final oversizedGifHandle = oversizedGif.openSync(mode: FileMode.write);
      oversizedGifHandle.truncateSync(kMaxGifFileSize + 1);
      oversizedGifHandle.closeSync();
      final jpg = File('${tempDir.path}/valid.jpg')
        ..writeAsBytesSync([1, 2, 3]);

      List<PendingComposerMedia>? deliveredMedia;
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
              required uploadHooks,
            }) async {
              deliveredMedia = processedMedia;
              return ShareBatchTargetResult(
                target: ShareTargetSelection.contact(contact),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
      );

      final result = await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: [oversizedGif.path, jpg.path],
        ),
        targets: [
          ShareTargetSelection.contact(_makeContact('peer-alice', 'Alice')),
        ],
      );

      expect(result.skippedOversizedGifCount, 1);
      expect(
        result.skippedOversizedGifReason,
        'Some attachments were too large and were skipped.',
      );
      expect(deliveredMedia, isNotNull);
      expect(deliveredMedia, hasLength(1));
      expect(deliveredMedia!.single.file.path, jpg.path);
    },
  );

  test(
    'share-batch applies per-type size caps to non-GIF media (OQ-2)',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final tempDir = await Directory.systemTemp.createTemp(
        'share_batch_non_gif_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      // A non-decodable fake JPEG never compresses, so its final budget bytes
      // stay above the per-type image cap and it is skipped on FINAL bytes
      // (the per-type table now applies to non-GIF share media too).
      final oversizedJpg = File('${tempDir.path}/large-photo.jpg');
      final oversizedJpgHandle = oversizedJpg.openSync(mode: FileMode.write);
      oversizedJpgHandle.truncateSync(kGroupMediaImageLimitBytes + 1);
      oversizedJpgHandle.closeSync();
      final smallJpg = File('${tempDir.path}/ok.jpg')
        ..writeAsBytesSync([1, 2, 3]);

      List<PendingComposerMedia>? deliveredMedia;
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
              required uploadHooks,
            }) async {
              deliveredMedia = processedMedia;
              return ShareBatchTargetResult(
                target: ShareTargetSelection.contact(contact),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
      );

      final result = await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: [oversizedJpg.path, smallJpg.path],
        ),
        targets: [
          ShareTargetSelection.contact(_makeContact('peer-alice', 'Alice')),
        ],
      );

      // The over-cap image is skipped; the within-cap sibling is still delivered.
      expect(result.skippedOversizedGifCount, 1);
      expect(deliveredMedia, isNotNull);
      expect(deliveredMedia, hasLength(1));
      expect(deliveredMedia!.single.file.path, smallJpg.path);
    },
  );

  test(
    'text-only group share wraps publish in a background task and stays sent on durable success',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final groupRepository = InMemoryGroupRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      final bridge = _GroupShareBgBridge(
        publishMessageId: 'group-bg-sent',
        publishTopicPeers: 1,
        inboxStoreOk: true,
      );

      await groupRepository.saveGroup(_makeGroup('group-1', 'Writers'));
      await _seedGroupMembers(groupRepository, 'group-1');
      await _saveLatestGroupKey(groupRepository, 'group-1');

      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        bridge: bridge,
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
      );

      final result = await coordinator.deliver(
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'hello group',
        ),
        targets: [ShareTargetSelection.group(_makeGroup('group-1', 'Writers'))],
      );

      expect(result.sentCount, 1);
      expect(result.queuedCount, 0);
      expect(result.results.single.status, ShareBatchTargetStatus.sent);
      expect(result.results.single.detail, 'Sent.');
      _expectCommandOrder(bridge.commandLog, 'bg:begin', 'group:publish');
      _expectCommandOrder(
        bridge.commandLog,
        'group:publish',
        'group:inboxStore',
      );
      _expectCommandOrder(bridge.commandLog, 'group:inboxStore', 'bg:end');

      final saved = await groupMessageRepository.getMessagesPage('group-1');
      expect(saved, isNotEmpty);
      expect(saved.first.status, 'sent');
      expect(saved.first.inboxStored, isTrue);
    },
  );

  test(
    // 210b pin: an offline group share (publish-without-custody) reports the
    // honest queued outcome — never 'Share failed.' — and the durable row is
    // 'queued_offline' so the repush lane self-heals it on reconnect.
    'group share queued offline reports queued with the back-online copy',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final groupRepository = InMemoryGroupRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      final bridge = _GroupShareReliableNoCustodyBridge();

      await groupRepository.saveGroup(_makeGroup('group-3', 'Offline Writers'));
      await _seedGroupMembers(groupRepository, 'group-3');
      await _saveLatestGroupKey(groupRepository, 'group-3');

      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        bridge: bridge,
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
      );

      final result = await coordinator.deliver(
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'hello offline group',
        ),
        targets: [
          ShareTargetSelection.group(_makeGroup('group-3', 'Offline Writers')),
        ],
      );

      expect(result.queuedCount, 1);
      expect(result.results.single.status, ShareBatchTargetStatus.queued);
      expect(
        result.results.single.detail,
        "Stored — will send when you're back online.",
      );

      final saved = await groupMessageRepository.getMessagesPage('group-3');
      expect(saved, isNotEmpty);
      expect(saved.first.status, 'queued_offline');
      expect(saved.first.inboxRetryPayload, isNotNull);
    },
  );

  test(
    'group share treats live publish as sent while retaining inbox retry custody',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final groupRepository = InMemoryGroupRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      final bridge = _GroupShareBgBridge(
        publishMessageId: 'group-bg-pending',
        publishTopicPeers: 1,
        inboxStoreOk: false,
      );

      await groupRepository.saveGroup(_makeGroup('group-2', 'Pending Writers'));
      await _seedGroupMembers(groupRepository, 'group-2');
      await _saveLatestGroupKey(groupRepository, 'group-2');

      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        bridge: bridge,
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
      );

      final result = await coordinator.deliver(
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'pending group share',
        ),
        targets: [
          ShareTargetSelection.group(_makeGroup('group-2', 'Pending Writers')),
        ],
      );

      expect(result.sentCount, 1);
      expect(result.queuedCount, 0);
      expect(result.results.single.status, ShareBatchTargetStatus.sent);
      expect(result.results.single.detail, 'Sent.');
      _expectCommandOrder(bridge.commandLog, 'bg:begin', 'group:publish');
      _expectCommandOrder(
        bridge.commandLog,
        'group:publish',
        'group:inboxStore',
      );
      _expectCommandOrder(bridge.commandLog, 'group:inboxStore', 'bg:end');

      final saved = await groupMessageRepository.getMessagesPage('group-2');
      expect(saved, isNotEmpty);
      expect(saved.first.status, 'sent');
      expect(saved.first.inboxStored, isFalse);
      expect(saved.first.inboxRetryPayload, isNotNull);
    },
  );

  // --- 112 Phase 2.4: OS share-sheet sender (LAN-XOR-relay fix) ---
  // These exercise the REAL `_sendToContact` (no sendToContactFn stub).
  group('share media encryption', () {
    Map<String, dynamic> wireMediaAttachment(FakeP2PService p2pService) {
      final wire =
          p2pService.lastSendMessageContent ??
          p2pService.lastStoreInInboxMessage;
      expect(wire, isNotNull, reason: 'no outbound envelope was produced');
      final envelope = jsonDecode(wire!) as Map<String, dynamic>;
      final inner =
          jsonDecode(
                (envelope['encrypted'] as Map<String, dynamic>)['ciphertext']
                    as String,
              )
              as Map<String, dynamic>;
      final media = inner['media'] as List<dynamic>;
      return media.single as Map<String, dynamic>;
    }

    Future<
      ({
        ShareBatchDeliveryResult result,
        PassthroughCryptoBridge bridge,
        FakeP2PService p2pService,
      })
    >
    deliverOneImage({required FakeP2PService p2pService}) async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final contact = ContactModel(
        peerId: 'peer-share-enc',
        publicKey: 'pk-peer-share-enc',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'SharePeer',
        signature: 'sig-peer-share-enc',
        scannedAt: '2026-03-09T08:00:00.000Z',
        mlKemPublicKey: 'mlkem-peer-share-enc',
      );
      final contactRepository = InMemoryContactRepository();
      await contactRepository.addContact(contact);

      final sharedDir = Directory.systemTemp.createTempSync('share_enc_');
      addTearDown(() {
        if (sharedDir.existsSync()) {
          sharedDir.deleteSync(recursive: true);
        }
      });
      final sharedFile = File('${sharedDir.path}/shared.jpg')
        ..writeAsBytesSync(List<int>.filled(512, 0x7a));

      final bridge = PassthroughCryptoBridge();
      final messages = InMemoryMessageRepository();
      final media = _withDirectMediaCustodyAuthority(messages);
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: contactRepository,
        messageRepository: messages,
        mediaAttachmentRepository: media,
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
          processedMedia: [
            PendingComposerMedia(file: sharedFile, budgetBytes: 512),
          ],
        ),
      );

      final result = await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: [sharedFile.path],
        ),
        targets: [ShareTargetSelection.contact(contact)],
      );
      return (result: result, bridge: bridge, p2pService: p2pService);
    }

    test(
      'TC-348-01 external direct media follows production selector and publishes authority before network',
      () async {
        final previousPathProvider = PathProviderPlatform.instance;
        final documents = Directory.systemTemp.createTempSync(
          'external_share_348_docs_',
        );
        PathProviderPlatform.instance = _SharePathProvider(documents.path);
        addTearDown(() async {
          PathProviderPlatform.instance = previousPathProvider;
          if (documents.existsSync()) documents.deleteSync(recursive: true);
        });

        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        final identityRepository = FakeIdentityRepository()
          ..seed(_makeIdentity());
        final contact = ContactModel(
          peerId: 'peer-share-348-causal',
          publicKey: 'pk-peer-share-348-causal',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Share 348',
          signature: 'sig-peer-share-348-causal',
          scannedAt: '2026-08-08T12:00:00.000Z',
          mlKemPublicKey: 'mlkem-peer-share-348-causal',
        );
        final contacts = InMemoryContactRepository();
        await contacts.addContact(contact);
        final source = File('${documents.path}/external-share.jpg')
          ..writeAsBytesSync(List<int>.generate(256, (index) => index));
        final sourceBytes = source.readAsBytesSync();
        final fileManager = MediaFileManager();
        var firstNetworkObserved = false;
        var strictRequestObserved = false;
        var authorityCompleteAtFirstNetwork = false;
        var pendingCopyCompleteAtFirstNetwork = false;
        final bridge = _AuthorityObservingShareBridge(
          onFirstMediaUpload: (payload) async {
            if (firstNetworkObserved) return;
            firstNetworkObserved = true;
            strictRequestObserved = payload['custodyContract'] != null;
            final parentRows = await fixture.db.query(
              'messages',
              where: 'contact_peer_id = ? AND is_incoming = 0',
              whereArgs: <Object?>[contact.peerId],
            );
            if (parentRows.length != 1) return;
            final parent = ConversationMessage.fromMap(parentRows.single);
            final attachments = await fixture.repo.getAttachmentsForMessage(
              parent.id,
              owner: MediaOwnerLane.direct,
            );
            final custodyRows = await fixture.repo
                .loadDirectMediaBlobCustodyForMessage(parent.id);
            authorityCompleteAtFirstNetwork =
                parent.id == parent.dedupKey &&
                parent.timestamp == parent.createdAt &&
                parent.directMediaCustodyIntentId != null &&
                !parent.isForwarded &&
                attachments.isNotEmpty &&
                attachments.length == custodyRows.length &&
                custodyRows.every(
                  (row) =>
                      row.messageId == parent.id &&
                      row.state == DirectMediaBlobCustodyState.outgoingPrepared,
                );
            if (!authorityCompleteAtFirstNetwork) return;
            pendingCopyCompleteAtFirstNetwork = attachments.every((attachment) {
              final storedPath = attachment.localPath;
              if (storedPath == null ||
                  !storedPath.startsWith('pending_uploads/${parent.id}/')) {
                return false;
              }
              final absolute = path.join(documents.path, storedPath);
              final file = File(absolute);
              return file.existsSync() &&
                  _sameBytesForShare(file.readAsBytesSync(), sourceBytes);
            });
          },
        );
        final p2pService = _DirectMediaCustodyFakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer-id-12345',
          ),
        )..isConnectedToPeerResult = true;
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: identityRepository,
          contactRepository: contacts,
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          groupRepository: InMemoryGroupRepository(),
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: bridge,
          p2pService: p2pService,
          mediaFileManager: fileManager,
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
            processedMedia: <PendingComposerMedia>[
              PendingComposerMedia(
                file: source,
                budgetBytes: sourceBytes.length,
              ),
            ],
          ),
        );

        final result = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: <String>[source.path],
          ),
          targets: <ShareTargetSelection>[
            ShareTargetSelection.contact(contact),
          ],
        );

        expect(firstNetworkObserved, isTrue);
        if (kDirectMediaBlobCustodyClientEnabled) {
          expect(strictRequestObserved, isTrue);
          expect(authorityCompleteAtFirstNetwork, isTrue);
          expect(pendingCopyCompleteAtFirstNetwork, isTrue);
          expect(result.sentCount, 1);
        } else {
          expect(strictRequestObserved, isFalse);
          expect(authorityCompleteAtFirstNetwork, isFalse);
          expect(result.failureCount, 0);
        }
      },
    );

    test(
      'TC-348-04 external fanout preserves progress and authority truth',
      () async {
        final previousPathProvider = PathProviderPlatform.instance;
        final documents = Directory.systemTemp.createTempSync(
          'external_share_348_fanout_',
        );
        PathProviderPlatform.instance = _SharePathProvider(documents.path);
        mediaUploadInFlightTracker.clearAll();
        addTearDown(() async {
          mediaUploadInFlightTracker.clearAll();
          PathProviderPlatform.instance = previousPathProvider;
          if (documents.existsSync()) documents.deleteSync(recursive: true);
        });

        var freshStageCalls = 0;
        final fixture = await MediaRepositoryRealDbFixture.create(
          dbStageFreshOutgoingDirectMediaBlobGenerationAround: (stage) async {
            freshStageCalls++;
            if (freshStageCalls <= 2) {
              throw StateError('injected pre-commit fresh-stage refusal');
            }
            return stage();
          },
        );
        addTearDown(fixture.dispose);
        final failedContact = _makeMlKemContact(
          'peer-share-348-failed',
          'Failed',
        );
        final queuedContact = _makeMlKemContact(
          'peer-share-348-queued',
          'Queued',
        );
        final sentContact = _makeMlKemContact('peer-share-348-sent', 'Sent');
        final contacts = InMemoryContactRepository();
        await contacts.addContact(failedContact);
        await contacts.addContact(queuedContact);
        await contacts.addContact(sentContact);
        final source = File('${documents.path}/fanout-source.jpg')
          ..writeAsBytesSync(List<int>.generate(96, (index) => index));
        var processCalls = 0;
        final uploadRecipients = <String>[];
        final uploadAttachmentIds = <String>[];
        final authorityAtUpload = <String, bool>{};
        final bridge = _AuthorityObservingShareBridge(
          onFirstMediaUpload: (payload) async {
            final recipient = payload['to'] as String;
            final attachmentId = payload['id'] as String;
            uploadRecipients.add(recipient);
            uploadAttachmentIds.add(attachmentId);
            final row = await fixture.repo
                .loadDirectMediaBlobCustodyForAttachment(attachmentId);
            final parent = row == null
                ? null
                : await fixture.messageRepo.getMessage(row.messageId);
            final attachments = parent == null
                ? const <MediaAttachment>[]
                : await fixture.repo.getAttachmentsForMessage(
                    parent.id,
                    owner: MediaOwnerLane.direct,
                  );
            authorityAtUpload[recipient] =
                payload['custodyContract'] != null &&
                row != null &&
                parent != null &&
                parent.id == parent.dedupKey &&
                attachments.length == 1 &&
                attachments.single.id == attachmentId;
          },
        );
        final p2pService = _FanoutAuthorityP2PService(
          queuedPeerId: queuedContact.peerId,
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer-id-12345',
          ),
        )..isConnectedToPeerResult = false;
        final progress = <ShareBatchDeliveryProgress>[];
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
          contactRepository: contacts,
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          groupRepository: InMemoryGroupRepository(),
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: bridge,
          p2pService: p2pService,
          mediaFileManager: MediaFileManager(),
          imageProcessor: _imageProcessor(),
          directMediaBlobCustodyClientEnabled: true,
          processSharedMediaFn: (_) async {
            processCalls++;
            return ProcessedShareMediaBatch(
              processedMedia: <PendingComposerMedia>[
                PendingComposerMedia(
                  file: source,
                  budgetBytes: source.lengthSync(),
                ),
              ],
            );
          },
        );

        final result = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: <String>[source.path],
          ),
          targets: <ShareTargetSelection>[
            ShareTargetSelection.contact(failedContact),
            ShareTargetSelection.contact(queuedContact),
            ShareTargetSelection.contact(sentContact),
          ],
          onProgress: progress.add,
        );

        expect(processCalls, 1);
        expect(
          result.results.map((entry) => entry.status),
          <ShareBatchTargetStatus>[
            ShareBatchTargetStatus.failed,
            ShareBatchTargetStatus.queued,
            ShareBatchTargetStatus.sent,
          ],
        );
        expect(uploadRecipients, <String>[
          queuedContact.peerId,
          sentContact.peerId,
        ]);
        expect(uploadAttachmentIds.toSet(), hasLength(2));
        expect(authorityAtUpload, <String, bool>{
          queuedContact.peerId: true,
          sentContact.peerId: true,
        });

        Future<List<Map<String, Object?>>> parentsFor(String peerId) =>
            fixture.db.query(
              'messages',
              where: 'contact_peer_id = ? AND is_incoming = 0',
              whereArgs: <Object?>[peerId],
            );
        expect(await parentsFor(failedContact.peerId), isEmpty);
        final queuedParents = await parentsFor(queuedContact.peerId);
        final sentParents = await parentsFor(sentContact.peerId);
        expect(queuedParents, hasLength(1));
        expect(sentParents, hasLength(1));
        expect(queuedParents.single['id'], isNot(sentParents.single['id']));
        expect(
          await fixture.repo.loadDirectMediaBlobCustodyForMessage(
            queuedParents.single['id']! as String,
          ),
          hasLength(1),
          reason: 'post-authority envelope failure stays retry-owned',
        );

        expect(progress.map((entry) => entry.phase), <ShareBatchDeliveryPhase>[
          ShareBatchDeliveryPhase.uploading,
          ShareBatchDeliveryPhase.uploading,
          ShareBatchDeliveryPhase.uploading,
          ShareBatchDeliveryPhase.uploading,
          ShareBatchDeliveryPhase.sending,
          ShareBatchDeliveryPhase.uploading,
          ShareBatchDeliveryPhase.uploading,
          ShareBatchDeliveryPhase.sending,
        ]);
        expect(progress.map((entry) => entry.sentBytes), <int>[
          0,
          0,
          0,
          96,
          96,
          96,
          192,
          192,
        ]);
        expect(progress.map((entry) => entry.totalBytes).toSet(), <int>{288});
      },
    );

    test('TC-348-05 external strict adopter decision table is exact', () async {
      final previousPathProvider = PathProviderPlatform.instance;
      final root = Directory.systemTemp.createTempSync(
        'external_share_348_decision_',
      );
      mediaUploadInFlightTracker.clearAll();
      addTearDown(() async {
        mediaUploadInFlightTracker.clearAll();
        PathProviderPlatform.instance = previousPathProvider;
        if (root.existsSync()) root.deleteSync(recursive: true);
      });

      var scenarioIndex = 0;
      Future<
        ({
          MediaRepositoryRealDbFixture fixture,
          ShareBatchDeliveryResult result,
          List<Map<String, dynamic>> uploads,
        })
      >
      runScenario({
        required bool selector,
        bool wireFreshCapability = true,
        bool addCurrentContact = true,
        bool failFreshStage = false,
        bool internalForward = false,
      }) async {
        scenarioIndex++;
        final suffix = scenarioIndex.toString();
        final documents = Directory('${root.path}/scenario-$suffix')
          ..createSync(recursive: true);
        PathProviderPlatform.instance = _SharePathProvider(documents.path);
        var freshCalls = 0;
        final fixture = await MediaRepositoryRealDbFixture.create(
          databasePath: '${documents.path}/identity.sqlite',
          wireFreshOutgoingDirectMediaBlobGeneration: wireFreshCapability,
          dbStageFreshOutgoingDirectMediaBlobGenerationAround: failFreshStage
              ? (stage) async {
                  freshCalls++;
                  if (freshCalls <= 2) {
                    throw StateError('injected strict selection failure');
                  }
                  return stage();
                }
              : null,
        );
        addTearDown(fixture.dispose);
        final contact = _makeMlKemContact(
          'peer-share-348-decision-$suffix',
          'Decision $suffix',
        );
        final contacts = InMemoryContactRepository();
        if (addCurrentContact) await contacts.addContact(contact);
        final source = File('${documents.path}/decision.jpg')
          ..writeAsBytesSync(List<int>.generate(48, (index) => index));
        final uploads = <Map<String, dynamic>>[];
        final bridge = _AuthorityObservingShareBridge(
          onFirstMediaUpload: (payload) async {
            uploads.add(Map<String, dynamic>.from(payload));
          },
        );
        final p2pService = _DirectMediaCustodyFakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer-id-12345',
          ),
        )..isConnectedToPeerResult = false;
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
          contactRepository: contacts,
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          groupRepository: InMemoryGroupRepository(),
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: bridge,
          p2pService: p2pService,
          mediaFileManager: MediaFileManager(),
          imageProcessor: _imageProcessor(),
          directMediaBlobCustodyClientEnabled: selector,
          processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
            processedMedia: <PendingComposerMedia>[
              PendingComposerMedia(
                file: source,
                budgetBytes: source.lengthSync(),
              ),
            ],
          ),
        );
        final result = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: <String>[source.path],
            forwardProvenance: internalForward
                ? ForwardProvenance(operationDedupKey: 'tc348-forward-$suffix')
                : null,
          ),
          targets: <ShareTargetSelection>[
            ShareTargetSelection.contact(contact),
          ],
        );
        return (fixture: fixture, result: result, uploads: uploads);
      }

      Future<List<Map<String, Object?>>> v111Rows(
        MediaRepositoryRealDbFixture fixture,
      ) => fixture.db.query(kDirectMediaBlobCustodyTable);

      final selectorOff = await runScenario(selector: false);
      expect(selectorOff.result.failureCount, 0);
      expect(selectorOff.uploads, hasLength(1));
      expect(selectorOff.uploads.single['custodyContract'], isNull);
      expect(await v111Rows(selectorOff.fixture), isEmpty);

      final missingFresh = await runScenario(
        selector: true,
        wireFreshCapability: false,
      );
      expect(
        (missingFresh.fixture.repo as DirectMediaBlobCustodyRepository)
            .supportsDirectMediaBlobCustody,
        isTrue,
      );
      expect(
        (missingFresh.fixture.repo
                as FreshOutgoingDirectMediaBlobGenerationRepository)
            .supportsFreshOutgoingDirectMediaBlobGeneration,
        isFalse,
      );
      expect(missingFresh.uploads, hasLength(1));
      expect(missingFresh.uploads.single['custodyContract'], isNull);
      expect(await v111Rows(missingFresh.fixture), isEmpty);

      final suppliedFallback = await runScenario(
        selector: true,
        addCurrentContact: false,
      );
      expect(suppliedFallback.result.sentCount, 1);
      expect(suppliedFallback.uploads, hasLength(1));
      expect(
        suppliedFallback.uploads.single['custodyContract'],
        'ack_or_expiry_v1',
      );

      final strictFailure = await runScenario(
        selector: true,
        failFreshStage: true,
      );
      expect(strictFailure.result.failureCount, 1);
      expect(strictFailure.uploads, isEmpty);
      expect(await v111Rows(strictFailure.fixture), isEmpty);
      expect(
        await strictFailure.fixture.db.query('messages'),
        isEmpty,
        reason: 'strict selection never falls back to the legacy writer',
      );

      // 350: an internal forward is no longer excluded as a class. What is
      // excluded is provenance WITHOUT a reviewed entry's source gate — this
      // scenario reaches `deliver()` with bare provenance and no source
      // authority, so it must still stay on the legacy owner.
      final unGatedInternalForward = await runScenario(
        selector: true,
        internalForward: true,
      );
      expect(unGatedInternalForward.result.failureCount, 0);
      expect(unGatedInternalForward.uploads, hasLength(1));
      expect(
        unGatedInternalForward.uploads.single['custodyContract'],
        isNull,
        reason:
            'generic provenance is not source authorization; only a reviewed '
            'entry leg may supply the forward authorization token '
            '(TC-350-01a/04 own the authorized cases)',
      );
      expect(await v111Rows(unGatedInternalForward.fixture), isEmpty);
    });

    test(
      'TC-350-04 internal forward custody decision table varies one authority at a time',
      () async {
        final previousPathProvider = PathProviderPlatform.instance;
        final root = Directory.systemTemp.createTempSync(
          'internal_forward_350_decision_',
        );
        mediaUploadInFlightTracker.clearAll();
        addTearDown(() async {
          mediaUploadInFlightTracker.clearAll();
          PathProviderPlatform.instance = previousPathProvider;
          if (root.existsSync()) root.deleteSync(recursive: true);
        });

        final fixtureBytes = File(
          'integration_test/fixtures/received_media_egress_fixture.jpg',
        ).readAsBytesSync();
        var scenarioIndex = 0;

        /// Every scenario runs selector-on with COMPLETE runtime capability and
        /// production `_sendToContact`; exactly one authority is varied, so no
        /// negative can pass because support was accidentally absent.
        Future<
          ({
            MediaRepositoryRealDbFixture fixture,
            ShareBatchDeliveryResult result,
            List<Map<String, dynamic>> uploads,
            File sourceFile,
            String sourceMessageId,
            String sourceAttachmentId,
          })
        >
        runScenario({
          bool selector = true,
          bool sourceGated = true,
          bool hiddenSource = false,
          bool privateSource = false,
          bool textOnly = false,
          bool groupDestination = false,
          bool externalShare = false,
        }) async {
          scenarioIndex++;
          final documents = Directory('${root.path}/scenario-$scenarioIndex')
            ..createSync(recursive: true);
          PathProviderPlatform.instance = _SharePathProvider(documents.path);
          final fixture = await MediaRepositoryRealDbFixture.create(
            databasePath: '${documents.path}/identity.sqlite',
          );
          addTearDown(fixture.dispose);
          final fileManager = MediaFileManager();

          final sourcePeerId = 'peer-350-decision-source-$scenarioIndex';
          final sourceMessageId = 'msg-350-decision-$scenarioIndex';
          final sourceAttachmentId = 'att-350-decision-$scenarioIndex';
          var sourceParent = ConversationMessage(
            id: sourceMessageId,
            contactPeerId: sourcePeerId,
            senderPeerId: sourcePeerId,
            text: 'decision caption',
            timestamp: '2026-08-09T10:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-08-09T10:00:00.000Z',
          );
          if (hiddenSource) {
            sourceParent = sourceParent.copyWith(
              hiddenAt: '2026-08-09T10:01:00.000Z',
            );
          }
          if (privateSource) {
            sourceParent = sourceParent.copyWith(
              privateMediaPolicy: const PrivateMediaPolicy.protected(),
              privateMediaState: PrivateMediaLifecycleState.available,
            );
          }
          await fixture.messageRepo.saveMessage(sourceParent);
          final sourceFile = File(
            await fileManager.localPathForAttachment(
              contactPeerId: sourcePeerId,
              blobId: sourceAttachmentId,
              mime: 'image/jpeg',
            ),
          );
          sourceFile.parent.createSync(recursive: true);
          sourceFile.writeAsBytesSync(fixtureBytes);
          await fixture.repo.saveAttachment(
            MediaAttachment(
              id: sourceAttachmentId,
              messageId: sourceMessageId,
              mime: 'image/jpeg',
              size: fixtureBytes.length,
              mediaType: 'image',
              localPath: sourceFile.path,
              downloadStatus: 'done',
              createdAt: '2026-08-09T10:00:00.000Z',
              contentHash: List.filled(64, 'e').join(),
              encryptionKeyBase64: 'decision-source-key',
              encryptionNonce: 'decision-source-nonce',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              ownerLane: MediaOwnerLane.direct,
            ),
            owner: MediaOwnerLane.direct,
          );

          final contact = _makeMlKemContact(
            'peer-350-decision-target-$scenarioIndex',
            'Decision $scenarioIndex',
          );
          final contacts = InMemoryContactRepository();
          await contacts.addContact(contact);
          final groups = InMemoryGroupRepository();
          final group = _makeGroup(
            'group-350-decision-$scenarioIndex',
            'Decision Group',
          );
          await groups.saveGroup(group);
          await _seedGroupMembers(groups, group.id);
          await _saveLatestGroupKey(groups, group.id);

          final uploads = <Map<String, dynamic>>[];
          final bridge = _RecipientAuthorityObservingBridge(
            onMediaUpload: (payload) async =>
                uploads.add(Map<String, dynamic>.from(payload)),
          );
          final coordinator = DefaultShareBatchDeliveryCoordinator(
            identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
            contactRepository: contacts,
            messageRepository: fixture.messageRepo,
            mediaAttachmentRepository: fixture.repo,
            groupRepository: groups,
            groupMessageRepository: InMemoryGroupMessageRepository(),
            bridge: bridge,
            p2pService: _DirectMediaCustodyFakeP2PService(
              initialState: const NodeState(
                isStarted: true,
                peerId: 'my-peer-id-12345',
              ),
            )..isConnectedToPeerResult = false,
            mediaFileManager: fileManager,
            imageProcessor: _imageProcessor(),
            directMediaBlobCustodyClientEnabled: selector,
            // Varying ONE authority: `textOnly` removes the media itself while
            // the source gate, selector, and every capability stay identical.
            processSharedMediaFn: (intent) async => ProcessedShareMediaBatch(
              processedMedia: textOnly
                  ? const <PendingComposerMedia>[]
                  : intent.filePaths
                        .where((filePath) => File(filePath).existsSync())
                        .map(
                          (filePath) => PendingComposerMedia(
                            file: File(filePath),
                            budgetBytes: File(filePath).lengthSync(),
                          ),
                        )
                        .toList(growable: false),
            ),
          );

          final result = await coordinator.deliver(
            shareIntent: ShareIntent(
              type: ShareIntentType.mixed,
              text: 'decision caption',
              filePaths: <String>[sourceFile.path],
              forwardProvenance: externalShare
                  ? null
                  : ForwardProvenance(
                      operationDedupKey: 'tc350-decision-$scenarioIndex',
                    ),
              directForwardSourceAuthority: (externalShare || !sourceGated)
                  ? null
                  : DirectForwardSourceAuthority(
                      contactPeerId: sourcePeerId,
                      messageId: sourceMessageId,
                      attachmentIds: <String>[sourceAttachmentId],
                    ),
            ),
            targets: <ShareTargetSelection>[
              groupDestination
                  ? ShareTargetSelection.group(group)
                  : ShareTargetSelection.contact(contact),
            ],
          );
          return (
            fixture: fixture,
            result: result,
            uploads: uploads,
            sourceFile: sourceFile,
            sourceMessageId: sourceMessageId,
            sourceAttachmentId: sourceAttachmentId,
          );
        }

        Future<List<Map<String, Object?>>> v111Rows(
          MediaRepositoryRealDbFixture fixture,
        ) => fixture.db.query(kDirectMediaBlobCustodyTable);

        Future<void> expectSourcePreserved(
          ({
            MediaRepositoryRealDbFixture fixture,
            ShareBatchDeliveryResult result,
            List<Map<String, dynamic>> uploads,
            File sourceFile,
            String sourceMessageId,
            String sourceAttachmentId,
          })
          scenario,
        ) async {
          final row = await scenario.fixture.repo.getAttachmentById(
            scenario.sourceAttachmentId,
          );
          expect(row, isNotNull);
          expect(row!.localPath, scenario.sourceFile.path);
          expect(row.encryptionKeyBase64, 'decision-source-key');
          expect(row.encryptionNonce, 'decision-source-nonce');
          expect(scenario.sourceFile.readAsBytesSync(), fixtureBytes);
        }

        // POSITIVE control: one entry-authorized, source-gated ordinary media
        // forward to a current direct contact selects strict.
        final authorized = await runScenario();
        expect(authorized.result.failureCount, 0);
        expect(authorized.uploads, hasLength(1));
        expect(
          authorized.uploads.single['custodyContract'],
          'ack_or_expiry_v1',
        );
        expect(await v111Rows(authorized.fixture), hasLength(1));
        await expectSourcePreserved(authorized);

        // Selector off remains legacy with identical authority everywhere else.
        final selectorOff = await runScenario(selector: false);
        expect(selectorOff.result.failureCount, 0);
        expect(selectorOff.uploads, hasLength(1));
        expect(selectorOff.uploads.single['custodyContract'], isNull);
        expect(await v111Rows(selectorOff.fixture), isEmpty);
        await expectSourcePreserved(selectorOff);

        // Forged generic provenance with NO source gate stays legacy.
        final forgedProvenance = await runScenario(sourceGated: false);
        expect(forgedProvenance.result.failureCount, 0);
        expect(forgedProvenance.uploads, hasLength(1));
        expect(forgedProvenance.uploads.single['custodyContract'], isNull);
        expect(await v111Rows(forgedProvenance.fixture), isEmpty);
        await expectSourcePreserved(forgedProvenance);

        // A failed source gate is fail-closed with zero custody and network.
        for (final denied in <({String label, bool hidden, bool private})>[
          (label: 'hidden source parent', hidden: true, private: false),
          (label: 'private source parent', hidden: false, private: true),
        ]) {
          final scenario = await runScenario(
            hiddenSource: denied.hidden,
            privateSource: denied.private,
          );
          expect(scenario.result.failureCount, 1, reason: denied.label);
          expect(scenario.uploads, isEmpty, reason: denied.label);
          expect(
            await v111Rows(scenario.fixture),
            isEmpty,
            reason: denied.label,
          );
          expect(
            await scenario.fixture.db.query(
              'messages',
              where: 'is_incoming = 0',
            ),
            isEmpty,
            reason: denied.label,
          );
          await expectSourcePreserved(scenario);
        }

        // Text-only and group destinations retain their existing owners.
        final textOnly = await runScenario(textOnly: true);
        expect(await v111Rows(textOnly.fixture), isEmpty);
        expect(textOnly.uploads, isEmpty);
        await expectSourcePreserved(textOnly);

        final groupDestination = await runScenario(groupDestination: true);
        expect(await v111Rows(groupDestination.fixture), isEmpty);
        expect(
          groupDestination.uploads.every(
            (payload) => payload['custodyContract'] == null,
          ),
          isTrue,
        );
        await expectSourcePreserved(groupDestination);

        // Plan 348's marker-free external share remains the strict adopter.
        final external = await runScenario(externalShare: true);
        expect(external.result.failureCount, 0);
        expect(external.uploads, hasLength(1));
        expect(external.uploads.single['custodyContract'], 'ack_or_expiry_v1');
        expect(await v111Rows(external.fixture), hasLength(1));
      },
    );

    test(
      'TC-350-03a internal authority reread distinguishes precommit commit ambiguity and drift',
      () async {
        final previousPathProvider = PathProviderPlatform.instance;
        final root = Directory.systemTemp.createTempSync(
          'internal_forward_350_authority_',
        );
        mediaUploadInFlightTracker.clearAll();
        addTearDown(() async {
          mediaUploadInFlightTracker.clearAll();
          PathProviderPlatform.instance = previousPathProvider;
          if (root.existsSync()) root.deleteSync(recursive: true);
        });

        const forwardToken = 'tc350-authority-forward-token';
        var scenarioIndex = 0;

        /// One reviewed direct-library forward whose SQLite commit outcome is
        /// controlled: `precommit` never commits, `ambiguous` commits and then
        /// makes every wrapper call throw, and `drift` additionally mutates one
        /// exact parent field before throwing.
        Future<
          ({
            MediaRepositoryRealDbFixture fixture,
            ShareBatchDeliveryResult result,
            List<Map<String, dynamic>> uploads,
          })
        >
        runScenario(String mode) async {
          scenarioIndex++;
          final documents = Directory('${root.path}/scenario-$scenarioIndex')
            ..createSync(recursive: true);
          PathProviderPlatform.instance = _SharePathProvider(documents.path);
          late MediaRepositoryRealDbFixture fixture;
          final fixtureReady = <String>[];
          fixture = await MediaRepositoryRealDbFixture.create(
            databasePath: '${documents.path}/identity.sqlite',
            dbStageFreshOutgoingDirectMediaBlobGenerationAround: (stage) async {
              if (mode == 'precommit') {
                throw StateError('injected pre-commit staging failure');
              }
              final result = await stage();
              if (mode == 'drift' && fixtureReady.isEmpty) {
                fixtureReady.add('drifted');
                await fixture.db.update(
                  'messages',
                  <String, Object?>{'dedup_key': 'tc350-drifted-token'},
                  where: 'dedup_key = ?',
                  whereArgs: <Object?>[forwardToken],
                );
              }
              throw StateError('injected post-commit wrapper failure');
              // ignore: dead_code
              return result;
            },
          );
          addTearDown(fixture.dispose);
          final contact = _makeMlKemContact(
            'peer-350-authority-$scenarioIndex',
            'Authority $scenarioIndex',
          );
          final contacts = InMemoryContactRepository();
          await contacts.addContact(contact);
          final source = File('${documents.path}/forward.jpg')
            ..writeAsBytesSync(List<int>.generate(64, (index) => index));
          final uploads = <Map<String, dynamic>>[];
          final bridge = _RecipientAuthorityObservingBridge(
            onMediaUpload: (payload) async =>
                uploads.add(Map<String, dynamic>.from(payload)),
          );
          final coordinator = DefaultShareBatchDeliveryCoordinator(
            identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
            contactRepository: contacts,
            messageRepository: fixture.messageRepo,
            mediaAttachmentRepository: fixture.repo,
            groupRepository: InMemoryGroupRepository(),
            groupMessageRepository: InMemoryGroupMessageRepository(),
            bridge: bridge,
            p2pService: _DirectMediaCustodyFakeP2PService(
              initialState: const NodeState(
                isStarted: true,
                peerId: 'my-peer-id-12345',
              ),
            )..isConnectedToPeerResult = false,
            mediaFileManager: MediaFileManager(),
            imageProcessor: _imageProcessor(),
            directMediaBlobCustodyClientEnabled: true,
            processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
              processedMedia: <PendingComposerMedia>[
                PendingComposerMedia(
                  file: source,
                  budgetBytes: source.lengthSync(),
                ),
              ],
            ),
          );
          final result = await coordinator.deliverDirectMediaBatchForwardStrict(
            shareIntent: ShareIntent(
              type: ShareIntentType.files,
              filePaths: <String>[source.path],
              forwardProvenance: const ForwardProvenance(
                operationDedupKey: forwardToken,
              ),
            ),
            contacts: <ContactModel>[contact],
          );
          return (fixture: fixture, result: result, uploads: uploads);
        }

        // Pre-commit refusal is picker-owned failure with zero side effects.
        final precommit = await runScenario('precommit');
        expect(
          precommit.result.results.single.status,
          ShareBatchTargetStatus.failed,
        );
        expect(await precommit.fixture.db.query('messages'), isEmpty);
        expect(
          await precommit.fixture.db.query(kDirectMediaBlobCustodyTable),
          isEmpty,
        );
        expect(precommit.uploads, isEmpty);

        // An exact forwarded commit whose result and reconciliation are BOTH
        // ambiguous is resolved only by the share-level authority re-read.
        final ambiguous = await runScenario('ambiguous');
        expect(
          ambiguous.result.results.single.status,
          ShareBatchTargetStatus.queued,
        );
        final ambiguousParents = await ambiguous.fixture.db.query('messages');
        expect(ambiguousParents, hasLength(1));
        expect(ambiguousParents.single['dedup_key'], forwardToken);
        expect(ambiguousParents.single['is_forwarded'], 1);
        expect(
          await ambiguous.fixture.db.query(kDirectMediaBlobCustodyTable),
          hasLength(1),
        );
        expect(
          ambiguous.uploads,
          isEmpty,
          reason: 'the wrapper failed before any strict upload',
        );

        // One exact-field drift is NOT authority and never legacy-falls back.
        final drift = await runScenario('drift');
        expect(
          drift.result.results.single.status,
          ShareBatchTargetStatus.failed,
        );
        final driftedParents = await drift.fixture.db.query('messages');
        expect(driftedParents, hasLength(1));
        expect(driftedParents.single['dedup_key'], 'tc350-drifted-token');
        expect(
          drift.uploads,
          isEmpty,
          reason: 'strict selection never falls back to the legacy uploader',
        );
      },
    );

    test(
      'TC-350-03b postcommit progress observer cannot replace durable result',
      () async {
        final previousPathProvider = PathProviderPlatform.instance;
        final documents = Directory.systemTemp.createTempSync(
          'internal_forward_350_observer_',
        );
        PathProviderPlatform.instance = _SharePathProvider(documents.path);
        mediaUploadInFlightTracker.clearAll();
        addTearDown(() async {
          mediaUploadInFlightTracker.clearAll();
          PathProviderPlatform.instance = previousPathProvider;
          if (documents.existsSync()) documents.deleteSync(recursive: true);
        });

        final fixture = await MediaRepositoryRealDbFixture.create(
          databasePath: '${documents.path}/identity.sqlite',
        );
        addTearDown(fixture.dispose);
        final contact = _makeMlKemContact(
          'peer-350-observer-target',
          'Observer 350',
        );
        final contacts = InMemoryContactRepository();
        await contacts.addContact(contact);
        final source = File('${documents.path}/observer.jpg')
          ..writeAsBytesSync(List<int>.generate(64, (index) => index));
        final bridge = _RecipientAuthorityObservingBridge(
          onMediaUpload: (_) async {},
        );
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
          contactRepository: contacts,
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          groupRepository: InMemoryGroupRepository(),
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: bridge,
          p2pService: _DirectMediaCustodyFakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id-12345',
            ),
          )..isConnectedToPeerResult = false,
          mediaFileManager: MediaFileManager(),
          imageProcessor: _imageProcessor(),
          directMediaBlobCustodyClientEnabled: true,
          processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
            processedMedia: <PendingComposerMedia>[
              PendingComposerMedia(
                file: source,
                budgetBytes: source.lengthSync(),
              ),
            ],
          ),
        );

        var observerCalls = 0;
        final result = await coordinator.deliverDirectMediaBatchForwardStrict(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: <String>[source.path],
            forwardProvenance: const ForwardProvenance(
              operationDedupKey: 'tc350-observer-token',
            ),
          ),
          contacts: <ContactModel>[contact],
          onProgress: (_) {
            observerCalls++;
            throw StateError('injected progress observer failure');
          },
        );

        expect(observerCalls, greaterThan(0));
        expect(
          result.results.single.status,
          isNot(ShareBatchTargetStatus.failed),
          reason:
              'a throwing UI observer cannot turn a durable v111 target into '
              'picker-owned failure',
        );
        final parents = await fixture.db.query('messages');
        expect(parents, hasLength(1));
        expect(parents.single['is_forwarded'], 1);
        expect(parents.single['dedup_key'], 'tc350-observer-token');
        expect(
          await fixture.db.query(kDirectMediaBlobCustodyTable),
          hasLength(1),
        );
      },
    );

    test(
      'TC-350-01a source-gated received and group-origin forwards publish custody before network',
      () async {
        final previousPathProvider = PathProviderPlatform.instance;
        final documents = Directory.systemTemp.createTempSync(
          'internal_forward_350_causal_',
        );
        PathProviderPlatform.instance = _SharePathProvider(documents.path);
        mediaUploadInFlightTracker.clearAll();
        addTearDown(() async {
          mediaUploadInFlightTracker.clearAll();
          PathProviderPlatform.instance = previousPathProvider;
          if (documents.existsSync()) documents.deleteSync(recursive: true);
        });

        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        final fileManager = MediaFileManager();
        final sourceBytes = File(
          'integration_test/fixtures/received_media_egress_fixture.jpg',
        ).readAsBytesSync();

        // ---- Source A: received direct media held by its exact source gate.
        const receivedSourcePeerId = 'peer-350-received-source';
        const receivedSourceMessageId = 'msg-350-received-source';
        const receivedSourceAttachmentId = 'att-350-received-source';
        await fixture.messageRepo.saveMessage(
          ConversationMessage(
            id: receivedSourceMessageId,
            contactPeerId: receivedSourcePeerId,
            senderPeerId: receivedSourcePeerId,
            text: 'received caption',
            timestamp: '2026-08-09T09:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-08-09T09:00:00.000Z',
          ),
        );
        final receivedSourceFile = File(
          await fileManager.localPathForAttachment(
            contactPeerId: receivedSourcePeerId,
            blobId: receivedSourceAttachmentId,
            mime: 'image/jpeg',
          ),
        );
        receivedSourceFile.parent.createSync(recursive: true);
        receivedSourceFile.writeAsBytesSync(sourceBytes);
        await fixture.repo.saveAttachment(
          MediaAttachment(
            id: receivedSourceAttachmentId,
            messageId: receivedSourceMessageId,
            mime: 'image/jpeg',
            size: sourceBytes.length,
            mediaType: 'image',
            localPath: receivedSourceFile.path,
            downloadStatus: 'done',
            createdAt: '2026-08-09T09:00:00.000Z',
            contentHash: List.filled(64, 'b').join(),
            encryptionKeyBase64: 'received-source-key',
            encryptionNonce: 'received-source-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ownerLane: MediaOwnerLane.direct,
          ),
          owner: MediaOwnerLane.direct,
        );

        // ---- Source B: verified discussion media held by its group gate.
        const groupSourceId = 'group-350-source';
        const groupSourceMessageId = 'msg-350-group-source';
        const groupSourceAttachmentId = 'att-350-group-source';
        final groups = InMemoryGroupRepository();
        final groupMessages = InMemoryGroupMessageRepository();
        await groups.saveGroup(_makeGroup(groupSourceId, 'Source Group 350'));
        await _seedGroupMembers(groups, groupSourceId);
        await _saveLatestGroupKey(groups, groupSourceId);
        await groupMessages.saveMessage(
          GroupMessage(
            id: groupSourceMessageId,
            groupId: groupSourceId,
            senderPeerId: 'peer-350-group-sender',
            text: 'group caption',
            timestamp: DateTime.utc(2026, 8, 9, 9),
            isIncoming: true,
            createdAt: DateTime.utc(2026, 8, 9, 9),
          ),
        );
        final groupSourceFile = File(
          await fileManager.localPathForAttachment(
            contactPeerId: groupSourceId,
            blobId: groupSourceAttachmentId,
            mime: 'image/jpeg',
          ),
        );
        groupSourceFile.parent.createSync(recursive: true);
        groupSourceFile.writeAsBytesSync(sourceBytes);
        await fixture.repo.saveAttachment(
          MediaAttachment(
            id: groupSourceAttachmentId,
            messageId: groupSourceMessageId,
            mime: 'image/jpeg',
            size: sourceBytes.length,
            mediaType: 'image',
            localPath: groupSourceFile.path,
            downloadStatus: 'done',
            createdAt: '2026-08-09T09:00:00.000Z',
            contentHash: List.filled(64, 'c').join(),
            encryptionKeyBase64: 'group-source-key',
            encryptionNonce: 'group-source-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ownerLane: MediaOwnerLane.group,
          ),
          owner: MediaOwnerLane.group,
        );

        // ---- Destinations.
        final relayContact = _makeMlKemContact(
          'peer-350-relay-target',
          'Relay 350',
        );
        final lanContact = _makeMlKemContact('peer-350-lan-target', 'Lan 350');
        final groupForwardContact = _makeMlKemContact(
          'peer-350-group-target',
          'GroupFwd 350',
        );
        final contacts = InMemoryContactRepository();
        await contacts.addContact(relayContact);
        await contacts.addContact(lanContact);
        await contacts.addContact(groupForwardContact);

        final observedAtFirstNetwork = <String, _ForwardAuthoritySnapshot>{};
        Future<void> observe(
          String recipientPeerId, {
          bool strictRelayRequest = false,
          String? lanFilePath,
        }) async {
          if (observedAtFirstNetwork.containsKey(recipientPeerId)) return;
          final snapshot = await _readForwardAuthority(
            fixture,
            recipientPeerId,
          );
          // A LAN leg is strict only when it streams the exact v111 artifact
          // that already exists for this target.
          final lanStreamsCustodyArtifact =
              lanFilePath != null &&
              snapshot.ciphertextRelativePaths.any(
                (relative) =>
                    lanFilePath.replaceAll('\\', '/').endsWith(relative),
              );
          observedAtFirstNetwork[recipientPeerId] = snapshot.withStrict(
            strictRelayRequest || lanStreamsCustodyArtifact,
          );
        }

        final bridge = _RecipientAuthorityObservingBridge(
          onMediaUpload: (payload) async {
            final recipient = payload['to'] as String?;
            if (recipient != null) {
              await observe(
                recipient,
                strictRelayRequest: payload['custodyContract'] != null,
              );
            }
          },
        );
        final p2pService = _LanForPeerFakeP2PService(
          localPeerIds: <String>{lanContact.peerId},
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer-id-12345',
          ),
          onSendLocalMedia: (peerId, filePath) =>
              observe(peerId, lanFilePath: filePath),
        )..isConnectedToPeerResult = false;

        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
          contactRepository: contacts,
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          groupRepository: groups,
          groupMessageRepository: groupMessages,
          bridge: bridge,
          p2pService: p2pService,
          mediaFileManager: fileManager,
          imageProcessor: _imageProcessor(),
          directMediaBlobCustodyClientEnabled: true,
          processSharedMediaFn: (intent) async => ProcessedShareMediaBatch(
            processedMedia: intent.filePaths
                .map(
                  (filePath) => PendingComposerMedia(
                    file: File(filePath),
                    budgetBytes: File(filePath).lengthSync(),
                  ),
                )
                .toList(growable: false),
          ),
        );

        // ---- Case 1: received-direct forward fans out to a relay peer and a
        // LAN peer through the real capture lease.
        const receivedBaseToken = 'tc350-received-operation';
        final receivedResult = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.mixed,
            text: 'received caption',
            filePaths: const <String>['/stale/picker/path.jpg'],
            forwardProvenance: const ForwardProvenance(
              operationDedupKey: receivedBaseToken,
            ),
            directForwardSourceAuthority: DirectForwardSourceAuthority(
              contactPeerId: receivedSourcePeerId,
              messageId: receivedSourceMessageId,
              attachmentIds: const <String>[receivedSourceAttachmentId],
            ),
          ),
          targets: <ShareTargetSelection>[
            ShareTargetSelection.contact(relayContact),
            ShareTargetSelection.contact(lanContact),
          ],
        );
        expect(
          receivedResult.failureCount,
          0,
          reason: receivedResult.results.map((r) => r.detail).join('; '),
        );

        // ---- Case 2: verified discussion media forwarded to a contact.
        const groupBaseToken = 'tc350-group-operation';
        final groupResult = await coordinator.deliverGroupMediaForward(
          request: const GroupMediaForwardRequest(
            groupId: groupSourceId,
            messageId: groupSourceMessageId,
            attachmentId: groupSourceAttachmentId,
            initialCaption: 'group caption',
            provenance: ForwardProvenance(operationDedupKey: groupBaseToken),
          ),
          caption: 'group caption',
          targets: <ShareTargetSelection>[
            ShareTargetSelection.contact(groupForwardContact),
          ],
        );
        expect(
          groupResult.failureCount,
          0,
          reason: groupResult.results.map((r) => r.detail).join('; '),
        );

        // Every reviewed entry observed complete forwarded authority at its
        // FIRST network observation (LAN for the local peer, relay otherwise).
        for (final entry in <(String, String)>[
          (relayContact.peerId, receivedBaseToken),
          (lanContact.peerId, receivedBaseToken),
          (groupForwardContact.peerId, groupBaseToken),
        ]) {
          final recipientPeerId = entry.$1;
          final baseToken = entry.$2;
          final snapshot = observedAtFirstNetwork[recipientPeerId];
          expect(
            snapshot,
            isNotNull,
            reason: 'no network observation for $recipientPeerId',
          );
          expect(
            snapshot!.complete,
            isTrue,
            reason:
                'no complete parent/attachment/v110/v111 authority existed '
                'before the first network call for $recipientPeerId',
          );
          expect(snapshot.isForwarded, isTrue, reason: recipientPeerId);
          expect(
            snapshot.dedupKey,
            announcementForwardProvenanceForContact(
              base: ForwardProvenance(operationDedupKey: baseToken),
              contactPeerId: recipientPeerId,
            ).operationDedupKey,
            reason: 'generic and group-origin tokens stay contact-scoped',
          );
          expect(snapshot.strictRequestObserved, isTrue);
        }

        // Fan-out targets keep fresh, target-owned identities.
        final relaySnapshot = observedAtFirstNetwork[relayContact.peerId]!;
        final lanSnapshot = observedAtFirstNetwork[lanContact.peerId]!;
        expect(relaySnapshot.messageId, isNot(lanSnapshot.messageId));
        expect(
          relaySnapshot.attachmentIds.intersection(lanSnapshot.attachmentIds),
          isEmpty,
        );
        expect(relaySnapshot.dedupKey, isNot(lanSnapshot.dedupKey));

        // Source rows and files are untouched by the adopter.
        final receivedSourceAfter = await fixture.repo.getAttachmentById(
          receivedSourceAttachmentId,
        );
        expect(receivedSourceAfter?.localPath, receivedSourceFile.path);
        expect(receivedSourceFile.readAsBytesSync(), sourceBytes);
        expect(groupSourceFile.readAsBytesSync(), sourceBytes);

        // Strict success bound exactly one v108 media-custody envelope per
        // target, and the durable parent kept its exact forwarded identity.
        for (final recipientPeerId in <String>[
          relayContact.peerId,
          lanContact.peerId,
          groupForwardContact.peerId,
        ]) {
          final snapshot = observedAtFirstNetwork[recipientPeerId]!;
          expect(
            p2pService.mediaCustodyStoresByPeerId[recipientPeerId],
            hasLength(1),
            reason: recipientPeerId,
          );
          expect(
            p2pService.mediaCustodyStoresByPeerId[recipientPeerId]!.single,
            contains(snapshot.messageId!),
            reason: recipientPeerId,
          );
          final durable = await fixture.messageRepo.getMessage(
            snapshot.messageId!,
          );
          expect(durable, isNotNull, reason: recipientPeerId);
          expect(durable!.isForwarded, isTrue, reason: recipientPeerId);
          expect(durable.dedupKey, snapshot.dedupKey, reason: recipientPeerId);
        }
      },
    );

    test(
      'TC-345-05b fresh direct media share enters insert-fresh custody without preparation token',
      () async {
        final identityRepository = FakeIdentityRepository()
          ..seed(_makeIdentity());
        final contact = ContactModel(
          peerId: 'peer-share-fresh-custody',
          publicKey: 'pk-peer-share-fresh-custody',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Fresh custody',
          signature: 'sig-peer-share-fresh-custody',
          scannedAt: '2026-08-07T12:00:00.000Z',
          mlKemPublicKey: 'mlkem-peer-share-fresh-custody',
        );
        final contacts = InMemoryContactRepository();
        await contacts.addContact(contact);
        final messages = InMemoryMessageRepository();
        final media = InMemoryMediaAttachmentRepository();
        final p2pService = _DirectMediaCustodyFakeP2PService();
        final sharedDir = Directory.systemTemp.createTempSync(
          'share_fresh_custody_',
        );
        addTearDown(() {
          if (sharedDir.existsSync()) sharedDir.deleteSync(recursive: true);
        });
        final sharedFile = File('${sharedDir.path}/fresh.jpg')
          ..writeAsBytesSync(List<int>.filled(64, 0x45));
        var combinedStageCalls = 0;
        media.onStageOutgoingDirectMediaInboxCustody =
            ({
              required expected,
              required staged,
              required attachments,
              required kind,
              required recipientPeerId,
              required wireEnvelope,
            }) async {
              combinedStageCalls++;
              expect(expected, isNull);
              expect(kind, OutgoingOrdinaryAttemptKind.fresh);
              expect(staged.directMediaCustodyIntentId, isNull);
              expect(
                await messages.getMessage(staged.id),
                isNull,
                reason:
                    'external share has no prepared parent before final stage',
              );
              final parent = await messages.stageOutgoingOrdinaryAttempt(
                expected: null,
                staged: staged,
                kind: kind,
              );
              if (!parent.authorizesTransport) {
                return OutgoingDirectMediaCustodyStageResult(
                  outcome: parent.outcome,
                  message: parent.message,
                  custody: null,
                );
              }
              for (final attachment in attachments) {
                await media.saveAttachment(
                  attachment,
                  owner: MediaOwnerLane.direct,
                );
              }
              final committed = parent.message!.copyWith(media: attachments);
              await messages.saveMessage(committed);
              final custody = DirectInboxCustodyOutboxEntry(
                recipientPeerId: recipientPeerId,
                messageId: staged.id,
                incarnationId: 'cccccccccccccccccccccccccccccccc',
                wireEnvelope: wireEnvelope,
                retryCount: 0,
                lastAttemptAt: null,
                lastErrorCode: null,
                createdAt: committed.createdAt,
                updatedAt: committed.createdAt,
              );
              messages.directCustodyRows['$recipientPeerId\u0000${staged.id}'] =
                  custody;
              return OutgoingDirectMediaCustodyStageResult(
                outcome: parent.outcome,
                message: committed,
                custody: custody,
              );
            };
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: identityRepository,
          contactRepository: contacts,
          messageRepository: messages,
          mediaAttachmentRepository: media,
          groupRepository: InMemoryGroupRepository(),
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: PassthroughCryptoBridge(),
          p2pService: p2pService,
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
            processedMedia: <PendingComposerMedia>[
              PendingComposerMedia(file: sharedFile, budgetBytes: 64),
            ],
          ),
        );

        final result = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: <String>[sharedFile.path],
          ),
          targets: <ShareTargetSelection>[
            ShareTargetSelection.contact(contact),
          ],
        );

        expect(combinedStageCalls, 1);
        expect(result.results.single.status, ShareBatchTargetStatus.queued);
        expect(messages.directCustodyRows, hasLength(1));
        final committed = (await messages.getMessagesForContact(
          contact.peerId,
        )).single;
        expect(committed.directMediaCustodyIntentId, isNull);
        expect(
          await media.getAttachmentsForMessage(
            committed.id,
            owner: MediaOwnerLane.direct,
          ),
          hasLength(1),
        );
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'production contact leg remints identity and persists forward provenance per target',
      () async {
        final identityRepository = FakeIdentityRepository()
          ..seed(_makeIdentity());
        final contacts = InMemoryContactRepository();
        final first = ContactModel(
          peerId: 'peer-forward-one',
          publicKey: 'pk-forward-one',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'One',
          signature: 'sig-forward-one',
          scannedAt: '2026-07-10T08:00:00.000Z',
          mlKemPublicKey: 'mlkem-forward-one',
        );
        final second = ContactModel(
          peerId: 'peer-forward-two',
          publicKey: 'pk-forward-two',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Two',
          signature: 'sig-forward-two',
          scannedAt: '2026-07-10T08:00:00.000Z',
          mlKemPublicKey: 'mlkem-forward-two',
        );
        await contacts.addContact(first);
        await contacts.addContact(second);
        final dir = Directory.systemTemp.createTempSync('forward_contact_leg_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/source.jpg')
          ..writeAsBytesSync([1, 2, 3]);
        final messages = InMemoryMessageRepository();
        final media = _withDirectMediaCustodyAuthority(messages);
        const baseProvenance = ForwardProvenance(
          operationDedupKey: 'forward-operation-one',
        );
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: identityRepository,
          contactRepository: contacts,
          messageRepository: messages,
          mediaAttachmentRepository: media,
          groupRepository: InMemoryGroupRepository(),
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: PassthroughCryptoBridge(),
          p2pService: _DirectMediaCustodyFakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id-12345',
            ),
          ),
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
            processedMedia: [PendingComposerMedia(file: file, budgetBytes: 3)],
          ),
        );

        final result = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.mixed,
            text: 'editable caption',
            filePaths: [file.path],
            forwardProvenance: baseProvenance,
          ),
          targets: [
            ShareTargetSelection.contact(first),
            ShareTargetSelection.contact(second),
          ],
        );

        expect(result.failureCount, 0);
        final firstRows = await messages.getMessagesForContact(first.peerId);
        final secondRows = await messages.getMessagesForContact(second.peerId);
        expect(firstRows, hasLength(1));
        expect(secondRows, hasLength(1));
        expect(firstRows.single.id, isNot(secondRows.single.id));
        expect(firstRows.single.timestamp, isNot(secondRows.single.timestamp));
        final firstOperationKey = announcementForwardProvenanceForContact(
          base: baseProvenance,
          contactPeerId: first.peerId,
        ).operationDedupKey;
        final secondOperationKey = announcementForwardProvenanceForContact(
          base: baseProvenance,
          contactPeerId: second.peerId,
        ).operationDedupKey;
        expect(firstOperationKey, isNot(secondOperationKey));
        expect(firstRows.single.dedupKey, firstOperationKey);
        expect(secondRows.single.dedupKey, secondOperationKey);
        expect(firstRows.single.isForwarded, isTrue);
        expect(secondRows.single.isForwarded, isTrue);
        final firstMedia = await media.getAttachmentsForMessage(
          firstRows.single.id,
          owner: MediaOwnerLane.direct,
        );
        final secondMedia = await media.getAttachmentsForMessage(
          secondRows.single.id,
          owner: MediaOwnerLane.direct,
        );
        expect(firstMedia, hasLength(1));
        expect(secondMedia, hasLength(1));
        expect(firstMedia.single.id, isNot(secondMedia.single.id));
        expect(
          firstMedia.single.encryptionKeyBase64,
          isNot(secondMedia.single.encryptionKeyBase64),
        );

        final externalResult = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: [file.path],
          ),
          targets: [ShareTargetSelection.contact(first)],
        );
        expect(externalResult.failureCount, 0);
        final externalRow = (await messages.getMessagesForContact(
          first.peerId,
        )).singleWhere((row) => row.id != firstRows.single.id);
        expect(externalRow.isForwarded, isFalse);
        expect(externalRow.dedupKey, externalRow.id);
        expect(externalRow.dedupKey, isNot('forward-operation-one'));
      },
    );

    test(
      'multi-target media forward preprocesses once and encrypts/uploads separately per contact',
      () async {
        final identities = FakeIdentityRepository()..seed(_makeIdentity());
        final contacts = InMemoryContactRepository();
        final first = ContactModel(
          peerId: 'peer-crypto-one',
          publicKey: 'pk-one',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'One',
          signature: 'sig-one',
          scannedAt: '2026-07-10T08:00:00.000Z',
          mlKemPublicKey: 'mlkem-one',
        );
        final second = ContactModel(
          peerId: 'peer-crypto-two',
          publicKey: 'pk-two',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Two',
          signature: 'sig-two',
          scannedAt: '2026-07-10T08:00:00.000Z',
          mlKemPublicKey: 'mlkem-two',
        );
        await contacts.addContact(first);
        await contacts.addContact(second);
        final dir = Directory.systemTemp.createTempSync('forward_crypto_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/source.jpg')
          ..writeAsBytesSync([9, 8, 7]);
        final sourceBytes = file.readAsBytesSync();
        final messages = InMemoryMessageRepository();
        final media = _withDirectMediaCustodyAuthority(messages);
        const sourceAttachment = MediaAttachment(
          id: 'source-stored-blob',
          messageId: 'source-message',
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          localPath: '/source/library/source.jpg',
          downloadStatus: 'done',
          createdAt: '2026-07-10T07:59:00.000Z',
          encryptionKeyBase64: 'source-stored-key',
          encryptionNonce: 'source-stored-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.direct,
          isBookmarked: true,
          lastPlaybackPositionMs: 88,
        );
        await media.saveAttachment(
          sourceAttachment,
          owner: MediaOwnerLane.direct,
        );
        final sourceBefore = (await media.getAttachmentsForMessage(
          sourceAttachment.messageId,
          owner: MediaOwnerLane.direct,
        )).single;
        var preprocessCount = 0;
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: identities,
          contactRepository: contacts,
          messageRepository: messages,
          mediaAttachmentRepository: media,
          groupRepository: InMemoryGroupRepository(),
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: PassthroughCryptoBridge(),
          p2pService: _DirectMediaCustodyFakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id-12345',
            ),
          ),
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (_) async {
            preprocessCount++;
            return ProcessedShareMediaBatch(
              processedMedia: [
                PendingComposerMedia(file: file, budgetBytes: 3),
              ],
            );
          },
        );

        await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: [file.path],
            forwardProvenance: const ForwardProvenance(
              operationDedupKey: 'operation-crypto',
            ),
          ),
          targets: [
            ShareTargetSelection.contact(first),
            ShareTargetSelection.contact(second),
          ],
        );

        expect(preprocessCount, 1);
        final firstMessage = (await messages.getMessagesForContact(
          first.peerId,
        )).single;
        final secondMessage = (await messages.getMessagesForContact(
          second.peerId,
        )).single;
        final firstAttachment = (await media.getAttachmentsForMessage(
          firstMessage.id,
          owner: MediaOwnerLane.direct,
        )).single;
        final secondAttachment = (await media.getAttachmentsForMessage(
          secondMessage.id,
          owner: MediaOwnerLane.direct,
        )).single;
        expect(firstAttachment.id, isNot(secondAttachment.id));
        expect(
          firstAttachment.encryptionKeyBase64,
          isNot(secondAttachment.encryptionKeyBase64),
        );
        expect(
          firstAttachment.encryptionNonce,
          isNot(secondAttachment.encryptionNonce),
        );
        final sourceAfter = (await media.getAttachmentsForMessage(
          sourceAttachment.messageId,
          owner: MediaOwnerLane.direct,
        )).single;
        expect(sourceAfter.id, sourceBefore.id);
        expect(
          sourceAfter.encryptionKeyBase64,
          sourceBefore.encryptionKeyBase64,
        );
        expect(sourceAfter.encryptionNonce, sourceBefore.encryptionNonce);
        expect(sourceAfter.encryptionScheme, sourceBefore.encryptionScheme);
        expect(sourceAfter.localPath, sourceBefore.localPath);
        expect(sourceAfter.isBookmarked, sourceBefore.isBookmarked);
        expect(
          sourceAfter.lastPlaybackPositionMs,
          sourceBefore.lastPlaybackPositionMs,
        );
        expect(firstAttachment.id, isNot(sourceAttachment.id));
        expect(secondAttachment.id, isNot(sourceAttachment.id));
        expect(
          firstAttachment.encryptionKeyBase64,
          isNot(sourceAttachment.encryptionKeyBase64),
        );
        expect(
          secondAttachment.encryptionNonce,
          isNot(sourceAttachment.encryptionNonce),
        );
        expect(file.readAsBytesSync(), sourceBytes);
      },
    );

    test('share to a LAN peer still relay-uploads and the attachment carries '
        'encryption metadata', () async {
      final p2pService = _LanFakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-12345',
        ),
      )..sendLocalMediaResult = true;

      final outcome = await deliverOneImage(p2pService: p2pService);

      // The G5 gate passes — the share is not rejected.
      expect(
        outcome.result.results.single.status,
        isNot(ShareBatchTargetStatus.failed),
      );
      // LAN best-effort happened…
      expect(p2pService.sendLocalMediaCallCount, 1);
      // …but the relay upload was made anyway (the LAN-XOR-relay
      // `continue` is gone)…
      expect(
        outcome.bridge.commandLog,
        containsAllInOrder(['blob:keygen', 'blob:encrypt', 'media:upload']),
      );
      // …and the wire attachment carries the encryption metadata.
      final attachment = wireMediaAttachment(p2pService);
      expect(attachment['encryptionKeyBase64'], isNotNull);
      expect(attachment['encryptionNonce'], isNotNull);
      expect(attachment['encryptionScheme'], isNotNull);
      expect(attachment['contentHash'], isNotNull);
    });

    test('share LAN send streams the encrypted artifact, never the raw shared '
        'file', () async {
      final p2pService = _LanFakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-12345',
        ),
      )..sendLocalMediaResult = true;

      await deliverOneImage(p2pService: p2pService);

      expect(p2pService.sendLocalMediaCallCount, 1);
      // 112 Phase 4: the LAN leg streams the ciphertext artifact under an
      // enc-flagged opaque-mime offer — never the raw shared file.
      expect(
        p2pService.lastSendLocalMediaFilePath,
        isNot(endsWith('shared.jpg')),
      );
      expect(p2pService.lastSendLocalMediaFilePath, endsWith('.enc'));
      expect(p2pService.lastSendLocalMediaEnc, isTrue);
      expect(p2pService.lastSendLocalMediaMime, kOpaqueMediaTransportMime);
      expect(
        p2pService.lastSendLocalMediaEncScheme,
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
    });

    test('TC-347-08d external share remains legacy', () async {
      final p2pService = _DirectMediaCustodyFakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-12345',
        ),
      );

      final outcome = await deliverOneImage(p2pService: p2pService);

      expect(
        outcome.result.results.single.status,
        isNot(ShareBatchTargetStatus.failed),
      );
      expect(p2pService.sendLocalMediaCallCount, 0);
      expect(
        outcome.bridge.commandLog,
        containsAllInOrder(['blob:keygen', 'blob:encrypt', 'media:upload']),
      );
      final attachment = wireMediaAttachment(p2pService);
      expect(attachment['encryptionKeyBase64'], isNotNull);
      expect(attachment['encryptionNonce'], isNotNull);
      expect(attachment['encryptionScheme'], isNotNull);
      expect(attachment, isNot(contains('blobCustody')));
      final uploadRequest = outcome.bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .singleWhere((request) => request['cmd'] == 'media:upload');
      final uploadPayload = uploadRequest['payload'] as Map<String, dynamic>;
      expect(uploadPayload, isNot(contains('custodyKind')));
      expect(uploadPayload, isNot(contains('custodyContract')));
      expect(uploadPayload, isNot(contains('contentHash')));
    });
  });

  test(
    'GMF-03O existing group owner persistence remains local and collision safe',
    () async {
      final identities = FakeIdentityRepository()..seed(_makeIdentity());
      final groups = InMemoryGroupRepository();
      final groupMessages = InMemoryGroupMessageRepository();
      final media = InMemoryMediaAttachmentRepository();
      final group = _makeGroup('group-forward-owner', 'Forward Owners');
      await groups.saveGroup(group);
      await _seedGroupMembers(groups, group.id);
      await _saveLatestGroupKey(groups, group.id);
      const baseProvenance = ForwardProvenance(
        operationDedupKey: 'direct-only-provenance',
      );
      final targetOperationKey = groupForwardProvenanceForGroup(
        base: baseProvenance,
        groupId: group.id,
      ).operationDedupKey;
      final dir = Directory.systemTemp.createTempSync('forward_group_owner_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/source.jpg');
      File(
        'integration_test/fixtures/received_media_egress_fixture.jpg',
      ).copySync(file.path);
      final bridge = _GroupShareBgBridge(
        publishMessageId: targetOperationKey,
        publishTopicPeers: 1,
        inboxStoreOk: true,
      );
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identities,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: media,
        groupRepository: groups,
        groupMessageRepository: groupMessages,
        bridge: bridge,
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
          processedMedia: [
            PendingComposerMedia(file: file, budgetBytes: file.lengthSync()),
          ],
        ),
      );

      final result = await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.mixed,
          text: 'group caption',
          filePaths: [file.path],
          forwardProvenance: baseProvenance,
        ),
        targets: [ShareTargetSelection.group(group)],
      );

      expect(
        result.failureCount,
        0,
        reason: result.results.map((entry) => entry.detail).join('; '),
      );
      final saved = (await groupMessages.getMessagesPage(group.id)).first;
      expect(saved.id, targetOperationKey);
      expect(saved.logicalDeliveryId, targetOperationKey);
      expect(saved.text, 'group caption');
      final attachments = await media.getAttachmentsForMessage(
        saved.id,
        owner: MediaOwnerLane.group,
      );
      expect(attachments, hasLength(1));
      expect(attachments.single.ownerLane, MediaOwnerLane.group);

      // Strengthened: a same-parent-ID DIRECT collision row stays isolated —
      // the owner-scoped group load never returns it, the direct lane never
      // returns the group row, and neither replaces the other.
      final collision = MediaAttachment(
        id: 'direct-collision-att',
        messageId: saved.id,
        mime: 'image/jpeg',
        size: 3,
        mediaType: 'image',
        downloadStatus: 'done',
        createdAt: '2026-07-10T12:00:00.000Z',
        ownerLane: MediaOwnerLane.direct,
      );
      await media.saveAttachment(collision, owner: MediaOwnerLane.direct);
      final groupRows = await media.getAttachmentsForMessage(
        saved.id,
        owner: MediaOwnerLane.group,
      );
      expect(groupRows.map((row) => row.id), attachments.map((row) => row.id));
      expect(
        groupRows.every((row) => row.ownerLane == MediaOwnerLane.group),
        isTrue,
      );
      final directRows = await media.getAttachmentsForMessage(
        saved.id,
        owner: MediaOwnerLane.direct,
      );
      expect(directRows.map((row) => row.id), ['direct-collision-att']);

      // Local-only serialization: the published wire media maps carry no
      // owner/local state.
      final publishPayloads = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:publish')
          .map((message) => message['payload'] as Map<String, dynamic>)
          .toList(growable: false);
      expect(publishPayloads, hasLength(1));
      final wireMedia = (publishPayloads.single['media'] as List)
          .cast<Map<String, dynamic>>();
      for (final mediaMap in wireMedia) {
        expect(mediaMap.containsKey('ownerLane'), isFalse);
        expect(mediaMap.containsKey('owner'), isFalse);
        expect(mediaMap.containsKey('localPath'), isFalse);
      }
    },
  );

  test(
    'P269 external group share rejects dissolve between snapshot and first upload with zero external effects',
    () async {
      final groups = _DissolveOnForwardSnapshotRepository(snapshotCall: 2);
      final group = _makeGroup(
        'group-p269-share-before-first-dissolve',
        'Before first',
      );
      await groups.saveGroup(group);
      await _seedGroupMembers(groups, group.id);
      await _saveLatestGroupKey(groups, group.id);
      final groupMessages = InMemoryGroupMessageRepository();
      final dir = Directory.systemTemp.createTempSync(
        'p269_share_before_first_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = File('${dir.path}/one.jpg');
      File(
        'integration_test/fixtures/received_media_egress_fixture.jpg',
      ).copySync(source.path);
      final bridge = PassthroughCryptoBridge();
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: groups,
        groupMessageRepository: groupMessages,
        bridge: bridge,
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
          processedMedia: <PendingComposerMedia>[
            PendingComposerMedia(
              file: source,
              budgetBytes: source.lengthSync(),
            ),
          ],
        ),
      );

      final progressEvents = <ShareBatchDeliveryProgress>[];
      final result = await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: <String>[source.path],
        ),
        targets: <ShareTargetSelection>[ShareTargetSelection.group(group)],
        onProgress: progressEvents.add,
      );

      expect(result.failureCount, 1);
      expect(
        bridge.commandLog.where(
          (command) => const <String>{
            'blob:keygen',
            'blob:encrypt',
            'media:upload',
          }.contains(command),
        ),
        isEmpty,
      );
      expect(progressEvents, isEmpty);
      expect(
        bridge.commandLog.where((command) => command == 'group:publish'),
        isEmpty,
      );
      expect(await groupMessages.getMessagesPage(group.id), isEmpty);
      expect((await groups.getGroup(group.id))?.isDissolved, isTrue);
    },
  );

  test(
    'P269 external group share yields between upload leaves so dissolve blocks later upload and publish',
    () async {
      final groups = InMemoryGroupRepository();
      final group = _makeGroup(
        'group-p269-share-between-items-dissolve',
        'Between items',
      );
      await groups.saveGroup(group);
      await _seedGroupMembers(groups, group.id);
      await _saveLatestGroupKey(groups, group.id);
      final groupMessages = InMemoryGroupMessageRepository();
      final dir = Directory.systemTemp.createTempSync(
        'p269_share_between_items_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final first = File('${dir.path}/one.jpg');
      final second = File('${dir.path}/two.jpg');
      final fixture = File(
        'integration_test/fixtures/received_media_egress_fixture.jpg',
      );
      fixture.copySync(first.path);
      fixture.copySync(second.path);
      final bridge = _DissolveAfterFirstGroupUploadBridge(
        groupRepo: groups,
        groupId: group.id,
      );
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: groups,
        groupMessageRepository: groupMessages,
        bridge: bridge,
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
          processedMedia: <PendingComposerMedia>[
            PendingComposerMedia(file: first, budgetBytes: first.lengthSync()),
            PendingComposerMedia(
              file: second,
              budgetBytes: second.lengthSync(),
            ),
          ],
        ),
      );

      final result = await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: <String>[first.path, second.path],
        ),
        targets: <ShareTargetSelection>[ShareTargetSelection.group(group)],
      );

      expect(result.failureCount, 1);
      expect(
        bridge.commandLog.where((command) => command == 'media:upload'),
        hasLength(1),
      );
      expect(
        bridge.commandLog.where((command) => command == 'blob:keygen'),
        hasLength(1),
      );
      expect(
        bridge.commandLog.where((command) => command == 'blob:encrypt'),
        hasLength(1),
      );
      expect(
        bridge.commandLog.where((command) => command == 'group:publish'),
        isEmpty,
      );
      expect(await groupMessages.getMessagesPage(group.id), isEmpty);
      expect((await groups.getGroup(group.id))?.isDissolved, isTrue);
    },
  );

  test(
    'P269 external group media share uses active transport ACL and never account or device IDs',
    () async {
      final identities = FakeIdentityRepository()..seed(_makeIdentity());
      final groups = InMemoryGroupRepository();
      final groupMessages = InMemoryGroupMessageRepository();
      final media = InMemoryMediaAttachmentRepository();
      final group = _makeGroup('group-p269-external-share', 'P269 Share');
      await groups.saveGroup(group);
      await _saveLatestGroupKey(groups, group.id);
      final joinedAt = DateTime.utc(2026, 7, 22, 11, 30);
      await groups.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'my-peer-id-12345',
          username: 'Me',
          role: MemberRole.admin,
          publicKey: 'my-public-key',
          mlKemPublicKey: 'mlkem-public',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'transport-share-me-primary-p269',
              transportPeerId: 'transport-share-me-primary-p269',
              deviceSigningPublicKey: 'my-public-key',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'device-share-me-shared-p269',
              transportPeerId: 'transport-share-shared-p269',
              deviceSigningPublicKey: 'signing-share-me-shared-p269',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'device-share-me-revoked-p269',
              transportPeerId: 'transport-share-me-revoked-p269',
              deviceSigningPublicKey: 'signing-share-me-revoked-p269',
              status: GroupMemberDeviceStatus.revoked,
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'device-share-me-blank-p269',
              transportPeerId: ' ',
              deviceSigningPublicKey: 'signing-share-me-blank-p269',
            ),
          ],
          joinedAt: joinedAt,
        ),
      );
      await groups.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'account-share-writer-p269',
          username: 'Writer',
          role: MemberRole.writer,
          publicKey: 'account-key-share-writer-p269',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-share-writer-primary-p269',
              transportPeerId: 'transport-share-writer-primary-p269',
              deviceSigningPublicKey: 'signing-share-writer-primary-p269',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'device-share-writer-shared-p269',
              transportPeerId: 'transport-share-shared-p269',
              deviceSigningPublicKey: 'signing-share-writer-shared-p269',
            ),
          ],
          joinedAt: joinedAt.add(const Duration(seconds: 1)),
        ),
      );
      await groups.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'account-share-revoked-p269',
          username: 'Revoked',
          role: MemberRole.reader,
          publicKey: 'account-key-share-revoked-p269',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-share-only-revoked-p269',
              transportPeerId: 'transport-share-only-revoked-p269',
              deviceSigningPublicKey: 'signing-share-only-revoked-p269',
              status: GroupMemberDeviceStatus.revoked,
            ),
          ],
          joinedAt: joinedAt.add(const Duration(seconds: 2)),
        ),
      );

      final dir = Directory.systemTemp.createTempSync(
        'p269_external_group_share_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = File('${dir.path}/source.jpg');
      File(
        'integration_test/fixtures/received_media_egress_fixture.jpg',
      ).copySync(source.path);
      final bridge = _GroupShareBgBridge(
        publishMessageId: 'msg-p269-external-share',
        publishTopicPeers: 1,
        inboxStoreOk: true,
      );
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identities,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: media,
        groupRepository: groups,
        groupMessageRepository: groupMessages,
        bridge: bridge,
        p2pService: FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'transport-share-me-primary-p269',
          ),
        ),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
          processedMedia: <PendingComposerMedia>[
            PendingComposerMedia(
              file: source,
              budgetBytes: source.lengthSync(),
            ),
          ],
        ),
      );

      final result = await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.mixed,
          text: 'P269 external group share',
          filePaths: <String>[source.path],
        ),
        targets: <ShareTargetSelection>[ShareTargetSelection.group(group)],
      );
      expect(
        result.failureCount,
        0,
        reason: result.results.map((entry) => entry.detail).join('; '),
      );

      final uploadPayload = bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'media:upload')
          .map((message) => message['payload'] as Map<String, dynamic>)
          .last;
      final serializedAcl = (uploadPayload['allowedPeers'] as List<dynamic>)
          .cast<String>();
      expect(
        serializedAcl,
        unorderedEquals(const <String>[
          'transport-share-me-primary-p269',
          'transport-share-shared-p269',
          'transport-share-writer-primary-p269',
        ]),
      );
      expect(serializedAcl.toSet(), hasLength(serializedAcl.length));
      expect(serializedAcl, isNot(contains('')));
      for (final forbidden in const <String>[
        'my-peer-id-12345',
        'account-share-writer-p269',
        'account-share-revoked-p269',
        'device-share-me-shared-p269',
        'device-share-me-revoked-p269',
        'device-share-me-blank-p269',
        'device-share-writer-primary-p269',
        'device-share-writer-shared-p269',
        'device-share-only-revoked-p269',
        'transport-share-me-revoked-p269',
        'transport-share-only-revoked-p269',
      ]) {
        expect(serializedAcl, isNot(contains(forbidden)));
      }
    },
  );

  test(
    'GMF-03 group origin forward reencrypts independently and keeps provenance local',
    () async {
      final identities = FakeIdentityRepository()..seed(_makeIdentity());
      final contacts = InMemoryContactRepository();
      final groups = InMemoryGroupRepository();
      final groupMessages = InMemoryGroupMessageRepository();
      final directMessages = InMemoryMessageRepository();
      final media = _withDirectMediaCustodyAuthority(directMessages);
      final fileManager = FakeMediaFileManager();

      // Verified group SOURCE: incoming discussion media at its canonical
      // app-owned plaintext path. The relay hash intentionally belongs to a
      // different byte domain (ciphertext), plus sentinel source crypto/
      // identity values that must never reach any destination map.
      const srcGroupId = 'src-group-303';
      const srcMessageId = 'src-msg-303';
      const srcAttachmentId = 'src-att-303';
      const srcSenderPeerId = 'peer-source-sender-303';
      const srcKey = 'source-key-sentinel-303';
      const srcNonce = 'source-nonce-sentinel-303';
      await groups.saveGroup(_makeGroup(srcGroupId, 'Source Group'));
      await _seedGroupMembers(groups, srcGroupId);
      await _saveLatestGroupKey(groups, srcGroupId);
      await groupMessages.saveMessage(
        GroupMessage(
          id: srcMessageId,
          groupId: srcGroupId,
          senderPeerId: srcSenderPeerId,
          text: 'source caption',
          timestamp: DateTime.utc(2026, 7, 10, 12),
          isIncoming: true,
          createdAt: DateTime.utc(2026, 7, 10, 12),
        ),
      );
      final srcBytes = File(
        'integration_test/fixtures/received_media_egress_fixture.jpg',
      ).readAsBytesSync();
      final srcFile = File(
        await fileManager.localPathForAttachment(
          contactPeerId: srcGroupId,
          blobId: srcAttachmentId,
          mime: 'image/jpeg',
        ),
      );
      srcFile.writeAsBytesSync(srcBytes);
      addTearDown(() {
        if (srcFile.existsSync()) srcFile.deleteSync();
      });
      final srcStoredPath = srcFile.path;
      final plaintextHash = sha256.convert(srcBytes).toString();
      final srcHash = sha256.convert(<int>[...srcBytes, 0xa5]).toString();
      expect(srcHash, isNot(plaintextHash));
      await media.saveAttachment(
        MediaAttachment(
          id: srcAttachmentId,
          messageId: srcMessageId,
          mime: 'image/jpeg',
          size: srcBytes.length,
          mediaType: 'image',
          localPath: srcStoredPath,
          downloadStatus: 'done',
          createdAt: '2026-07-10T12:00:00.000Z',
          contentHash: srcHash,
          encryptionKeyBase64: srcKey,
          encryptionNonce: srcNonce,
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.group,
        ),
        owner: MediaOwnerLane.group,
      );

      // Destinations: one contact with a current encryption key and one
      // discussion group with its own current member set.
      final destContact = ContactModel(
        peerId: 'peer-dest-contact',
        publicKey: 'pk-peer-dest-contact',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'DestContact',
        signature: 'sig-peer-dest-contact',
        scannedAt: '2026-03-09T08:00:00.000Z',
        mlKemPublicKey: 'mlkem-peer-dest-contact',
      );
      await contacts.addContact(destContact);
      final destGroup = _makeGroup('dest-group-303', 'Destination Group');
      await groups.saveGroup(destGroup);
      await _seedGroupMembers(groups, destGroup.id);
      await _saveLatestGroupKey(groups, destGroup.id);

      final bridge = PassthroughCryptoBridge();
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'fwd-publish-303',
        'topicPeers': 1,
      };
      // Keep the durable retry payload alive on the saved row (a fully
      // successful send clears it): live publish succeeds, custody fails.
      bridge.responses['group:inboxStore'] = {'ok': false};
      final p2pService = _DirectMediaCustodyFakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-12345',
        ),
      );
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identities,
        contactRepository: contacts,
        messageRepository: directMessages,
        mediaAttachmentRepository: media,
        groupRepository: groups,
        groupMessageRepository: groupMessages,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: fileManager,
        imageProcessor: _imageProcessor(),
      );

      final result = await coordinator.deliverGroupMediaForward(
        request: GroupMediaForwardRequest(
          groupId: srcGroupId,
          messageId: srcMessageId,
          attachmentId: srcAttachmentId,
          initialCaption: 'source caption',
          provenance: const ForwardProvenance(operationDedupKey: 'fwd-op-303'),
        ),
        caption: 'edited caption',
        targets: [
          ShareTargetSelection.contact(destContact),
          ShareTargetSelection.group(destGroup),
        ],
      );

      expect(result.results, hasLength(2));
      expect(
        result.failureCount,
        0,
        reason: result.results.map((r) => r.detail).join('; '),
      );

      // Two INDEPENDENT uploads: fresh distinct blob ids, and neither reuses
      // the source attachment id.
      final uploadPayloads = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'media:upload')
          .map((message) => message['payload'] as Map<String, dynamic>)
          .toList(growable: false);
      expect(uploadPayloads, hasLength(2));
      final uploadIds = uploadPayloads
          .map((payload) => payload['id'] as String)
          .toSet();
      expect(uploadIds, hasLength(2));
      expect(uploadIds.contains(srcAttachmentId), isFalse);
      final contactUpload = uploadPayloads.firstWhere(
        (payload) => payload['to'] == 'peer-dest-contact',
      );
      final groupUpload = uploadPayloads.firstWhere(
        (payload) => payload['to'] == destGroup.id,
      );
      // The group upload is scoped to the destination group's CURRENT
      // members; the contact upload has no group access list at all.
      expect(((groupUpload['allowedPeers'] as List?) ?? const []).toSet(), {
        'my-peer-id-12345',
        'peer-writer',
      });
      expect(contactUpload['allowedPeers'], isNull);

      // Destination-side persisted rows carry FRESH crypto: two distinct new
      // keys/nonces, neither equal to the source sentinel values. (The fake
      // blob pipeline copies bytes, so contentHash equality is meaningless
      // here — key/nonce/blob identity carry the re-encryption claim.)
      final savedGroupMessage = (await groupMessages.getMessagesPage(
        destGroup.id,
      )).first;
      expect(savedGroupMessage.privateMediaPolicy.isOrdinary, isTrue);
      final groupAttachment = (await media.getAttachmentsForMessage(
        savedGroupMessage.id,
        owner: MediaOwnerLane.group,
      )).single;
      final contactAttachments = await media.getAttachmentsForMessage(
        (await directMessages.getMessagesForContact(
          'peer-dest-contact',
        )).first.id,
        owner: MediaOwnerLane.direct,
      );
      final contactAttachment = contactAttachments.single;
      expect(groupAttachment.ownerLane, MediaOwnerLane.group);
      expect(contactAttachment.ownerLane, MediaOwnerLane.direct);
      expect(groupAttachment.id, isNot(srcAttachmentId));
      expect(contactAttachment.id, isNot(srcAttachmentId));
      expect(groupAttachment.id, isNot(contactAttachment.id));
      expect(groupAttachment.encryptionKeyBase64, isNot(srcKey));
      expect(contactAttachment.encryptionKeyBase64, isNot(srcKey));
      expect(
        groupAttachment.encryptionKeyBase64,
        isNot(contactAttachment.encryptionKeyBase64),
      );
      expect(groupAttachment.encryptionNonce, isNot(srcNonce));
      expect(contactAttachment.encryptionNonce, isNot(srcNonce));

      // The forwarded marker rides every destination map; only the edited
      // caption and the newly minted media join normal routing fields.
      final publishPayload =
          bridge.sentMessages
                  .map((message) => jsonDecode(message) as Map<String, dynamic>)
                  .firstWhere(
                    (message) => message['cmd'] == 'group:publish',
                  )['payload']
              as Map<String, dynamic>;
      expect(publishPayload['text'], 'edited caption');
      expect(publishPayload['isForwarded'], isTrue);
      expect(savedGroupMessage.isForwarded, isTrue);
      final contactWire =
          p2pService.lastSendMessageContent ??
          p2pService.lastStoreInInboxMessage;
      expect(contactWire, isNotNull);
      final contactEnvelope = jsonDecode(contactWire!) as Map<String, dynamic>;
      final contactInner =
          jsonDecode(
                (contactEnvelope['encrypted']
                        as Map<String, dynamic>)['ciphertext']
                    as String,
              )
              as Map<String, dynamic>;
      expect(contactInner['isForwarded'], isTrue);
      expect(contactInner['text'], 'edited caption');

      // NO source provenance in any destination wire/replay/retry map: the
      // sentinel source identifiers and crypto values are absent everywhere.
      final destinationMaps = <String>[
        jsonEncode(publishPayload),
        contactWire,
        savedGroupMessage.wireEnvelope ?? '',
        savedGroupMessage.inboxRetryPayload ?? '',
      ].join('\n');
      for (final sentinel in [
        srcMessageId,
        srcAttachmentId,
        srcSenderPeerId,
        srcKey,
        srcNonce,
        srcGroupId,
      ]) {
        expect(
          destinationMaps.contains(sentinel),
          isFalse,
          reason: 'source sentinel "$sentinel" leaked into a destination map',
        );
      }
      // The retained durable retry map re-drives the marker too (the
      // passthrough crypto keeps the replay plaintext readable here; the full
      // wire/replay seam matrix is TC-236-07's job).
      expect(savedGroupMessage.inboxRetryPayload, isNotNull);
      final retryPayload =
          jsonDecode(savedGroupMessage.inboxRetryPayload!)
              as Map<String, dynamic>;
      final replayEnvelope =
          jsonDecode(retryPayload['message'] as String) as Map<String, dynamic>;
      final replayPlaintext =
          jsonDecode(replayEnvelope['ciphertext'] as String)
              as Map<String, dynamic>;
      expect(replayPlaintext['isForwarded'], isTrue);

      final availableGroupMaps =
          <({String boundary, Map<String, dynamic> payload})>[
            (boundary: 'group publish', payload: publishPayload),
            (boundary: 'group replay', payload: replayPlaintext),
          ];
      for (final raw in bridge.sentMessages) {
        final message = jsonDecode(raw) as Map<String, dynamic>;
        if (message['cmd'] != 'group:sendReliable') continue;
        final payload = (message['payload'] as Map).cast<String, dynamic>();
        if (payload['messageId'] == savedGroupMessage.id) {
          availableGroupMaps.add((
            boundary: 'group reliable',
            payload: payload,
          ));
        }
      }
      for (final entry in availableGroupMaps) {
        for (final key in GroupPrivateMediaPolicy.wireKeys) {
          expect(
            entry.payload,
            isNot(contains(key)),
            reason: '${entry.boundary} must omit ordinary policy key $key',
          );
        }
      }
    },
  );

  for (final fixture
      in <
        ({
          String label,
          String path,
          String mime,
          String mediaType,
          String suffix,
        })
      >[
        (
          label: 'JPEG',
          path: 'integration_test/fixtures/received_media_egress_fixture.jpg',
          mime: 'image/jpeg',
          mediaType: 'image',
          suffix: 'jpg',
        ),
        (
          label: 'MP4',
          path: 'integration_test/fixtures/received_media_egress_fixture.mp4',
          mime: 'video/mp4',
          mediaType: 'video',
          suffix: 'mp4',
        ),
      ]) {
    test(
      'GMF-03D ${fixture.label} group origin reaches two direct targets from one source processing pass',
      () async {
        final identities = FakeIdentityRepository()..seed(_makeIdentity());
        final contacts = InMemoryContactRepository();
        final groups = InMemoryGroupRepository();
        final groupMessages = InMemoryGroupMessageRepository();
        final directMessages = InMemoryMessageRepository();
        final media = _withDirectMediaCustodyAuthority(directMessages);
        final fileManager = FakeMediaFileManager();
        final cleanupPaths = <String>{};
        addTearDown(() {
          for (final cleanupPath in cleanupPaths) {
            final file = File(cleanupPath);
            if (file.existsSync()) file.deleteSync();
          }
        });

        final tag = fixture.suffix;
        final sourceGroupId = 'src-group-two-direct-$tag';
        final sourceMessageId = 'src-message-two-direct-$tag';
        final sourceAttachmentId = 'src-attachment-two-direct-$tag';
        await groups.saveGroup(
          _makeGroup(sourceGroupId, 'Two Direct Source ${fixture.label}'),
        );
        await groupMessages.saveMessage(
          GroupMessage(
            id: sourceMessageId,
            groupId: sourceGroupId,
            senderPeerId: 'peer-source-$tag',
            text: '${fixture.label} source caption',
            timestamp: DateTime.utc(2026, 7, 10, 12),
            isIncoming: true,
            createdAt: DateTime.utc(2026, 7, 10, 12),
          ),
        );

        final sourceBytes = File(fixture.path).readAsBytesSync();
        final sourceFile = File(
          await fileManager.localPathForAttachment(
            contactPeerId: sourceGroupId,
            blobId: sourceAttachmentId,
            mime: fixture.mime,
          ),
        );
        sourceFile.writeAsBytesSync(sourceBytes);
        cleanupPaths.add(sourceFile.path);
        final plaintextHash = sha256.convert(sourceBytes).toString();
        final relayCiphertextHash = sha256.convert(<int>[
          ...sourceBytes,
          0xa5,
        ]).toString();
        expect(relayCiphertextHash, isNot(plaintextHash));
        final sourceAttachment = MediaAttachment(
          id: sourceAttachmentId,
          messageId: sourceMessageId,
          mime: fixture.mime,
          size: sourceBytes.length,
          mediaType: fixture.mediaType,
          // Real iOS container UUIDs drift. The production resolver must
          // reroot this exact legacy group path onto the current trusted root
          // for both image and video forwarding.
          localPath:
              '/var/mobile/Containers/Data/Application/OLD-$tag/Documents/'
              'media/$sourceGroupId/$sourceAttachmentId.${fixture.suffix}',
          downloadStatus: 'done',
          createdAt: '2026-07-10T12:00:00.000Z',
          contentHash: relayCiphertextHash,
          encryptionKeyBase64: 'source-key-$tag',
          encryptionNonce: 'source-nonce-$tag',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.group,
        );
        await media.saveAttachment(
          sourceAttachment,
          owner: MediaOwnerLane.group,
        );
        final sourceBefore = (await media.getAttachmentsForMessage(
          sourceMessageId,
          owner: MediaOwnerLane.group,
        )).single;

        final first = _makeMlKemContact(
          'peer-two-direct-first-$tag',
          'First ${fixture.label}',
        );
        final second = _makeMlKemContact(
          'peer-two-direct-second-$tag',
          'Second ${fixture.label}',
        );
        await contacts.addContact(first);
        await contacts.addContact(second);

        final bridge = PassthroughCryptoBridge();
        final p2pService = _DirectMediaCustodyFakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer-id-12345',
          ),
        );
        var processCalls = 0;
        String? immutableSnapshotPath;
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: identities,
          contactRepository: contacts,
          messageRepository: directMessages,
          mediaAttachmentRepository: media,
          groupRepository: groups,
          groupMessageRepository: groupMessages,
          bridge: bridge,
          p2pService: p2pService,
          mediaFileManager: fileManager,
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (intent) async {
            processCalls++;
            immutableSnapshotPath = intent.filePaths.single;
            expect(immutableSnapshotPath, isNot(sourceFile.path));
            final snapshotFile = File(immutableSnapshotPath!);
            expect(snapshotFile.readAsBytesSync(), sourceBytes);
            return ProcessedShareMediaBatch(
              processedMedia: [
                PendingComposerMedia(
                  file: snapshotFile,
                  budgetBytes: sourceBytes.length,
                ),
              ],
            );
          },
        );

        final result = await coordinator.deliverGroupMediaForward(
          request: GroupMediaForwardRequest(
            groupId: sourceGroupId,
            messageId: sourceMessageId,
            attachmentId: sourceAttachmentId,
            initialCaption: '${fixture.label} source caption',
            provenance: ForwardProvenance(
              operationDedupKey: 'group-two-direct-$tag',
            ),
          ),
          caption: 'forwarded ${fixture.label}',
          targets: [
            ShareTargetSelection.contact(first),
            ShareTargetSelection.contact(second),
          ],
        );

        expect(processCalls, 1, reason: 'the group source is processed once');
        expect(immutableSnapshotPath, isNotNull);
        expect(
          File(immutableSnapshotPath!).existsSync(),
          isFalse,
          reason: 'the per-dispatch immutable snapshot is always disposed',
        );
        expect(result.results, hasLength(2));
        expect(
          result.failureCount,
          0,
          reason: result.results.map((entry) => entry.detail).join('; '),
        );

        final destinationAttachments = <MediaAttachment>[];
        for (final contact in [first, second]) {
          final messages = await directMessages.getMessagesForContact(
            contact.peerId,
          );
          expect(messages, hasLength(1));
          final attachment = (await media.getAttachmentsForMessage(
            messages.single.id,
            owner: MediaOwnerLane.direct,
          )).single;
          expect(attachment.ownerLane, MediaOwnerLane.direct);
          expect(attachment.mime, fixture.mime);
          expect(attachment.mediaType, fixture.mediaType);
          destinationAttachments.add(attachment);
          final destinationPath = await fileManager.resolveStoredPath(
            attachment.localPath!,
          );
          cleanupPaths.add(destinationPath);
          expect(File(destinationPath).readAsBytesSync(), sourceBytes);
        }

        expect(
          destinationAttachments.map((attachment) => attachment.id).toSet(),
          hasLength(2),
        );
        expect(
          destinationAttachments
              .map((attachment) => attachment.encryptionKeyBase64)
              .toSet(),
          hasLength(2),
        );
        expect(
          destinationAttachments
              .map((attachment) => attachment.encryptionNonce)
              .toSet(),
          hasLength(2),
        );
        for (final attachment in destinationAttachments) {
          expect(attachment.id, isNot(sourceAttachmentId));
          expect(
            attachment.encryptionKeyBase64,
            isNot(sourceAttachment.encryptionKeyBase64),
          );
          expect(
            attachment.encryptionNonce,
            isNot(sourceAttachment.encryptionNonce),
          );
        }

        final uploadIds = bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'media:upload')
            .map(
              (message) =>
                  (message['payload'] as Map<String, dynamic>)['id'] as String,
            )
            .toSet();
        expect(uploadIds, hasLength(2));
        expect(
          uploadIds,
          destinationAttachments.map((attachment) => attachment.id).toSet(),
        );

        final sourceAfter = (await media.getAttachmentsForMessage(
          sourceMessageId,
          owner: MediaOwnerLane.group,
        )).single;
        expect(sourceAfter.toMap(), sourceBefore.toMap());
        expect(sourceFile.readAsBytesSync(), sourceBytes);
        expect(
          await media.getAttachmentsForMessage(
            sourceMessageId,
            owner: MediaOwnerLane.direct,
          ),
          isEmpty,
        );
      },
    );
  }

  test(
    'GMF-03E target exceptions are isolated without aborting later forwards',
    () async {
      final identities = FakeIdentityRepository()..seed(_makeIdentity());
      final groups = InMemoryGroupRepository();
      final groupMessages = InMemoryGroupMessageRepository();
      final media = InMemoryMediaAttachmentRepository();
      final fileManager = FakeMediaFileManager();

      // Minimal verified source (same seeding as GMF-03).
      const srcGroupId = 'src-group-30e';
      const srcMessageId = 'src-msg-30e';
      const srcAttachmentId = 'src-att-30e';
      await groups.saveGroup(_makeGroup(srcGroupId, 'Source Group'));
      await _seedGroupMembers(groups, srcGroupId);
      await _saveLatestGroupKey(groups, srcGroupId);
      await groupMessages.saveMessage(
        GroupMessage(
          id: srcMessageId,
          groupId: srcGroupId,
          senderPeerId: 'peer-sender',
          text: 'caption',
          timestamp: DateTime.utc(2026, 7, 10, 12),
          isIncoming: true,
          createdAt: DateTime.utc(2026, 7, 10, 12),
        ),
      );
      final bytes = File(
        'integration_test/fixtures/received_media_egress_fixture.jpg',
      ).readAsBytesSync();
      final file = File(
        await fileManager.localPathForAttachment(
          contactPeerId: srcGroupId,
          blobId: srcAttachmentId,
          mime: 'image/jpeg',
        ),
      );
      file.writeAsBytesSync(bytes);
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      final plaintextHash = sha256.convert(bytes).toString();
      final relayCiphertextHash = sha256.convert(<int>[
        ...bytes,
        0xa5,
      ]).toString();
      expect(relayCiphertextHash, isNot(plaintextHash));
      await media.saveAttachment(
        MediaAttachment(
          id: srcAttachmentId,
          messageId: srcMessageId,
          mime: 'image/jpeg',
          size: bytes.length,
          mediaType: 'image',
          localPath: file.path,
          downloadStatus: 'done',
          createdAt: '2026-07-10T12:00:00.000Z',
          contentHash: relayCiphertextHash,
          encryptionKeyBase64: 'a2V5',
          encryptionNonce: 'bm9uY2U=',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.group,
        ),
        owner: MediaOwnerLane.group,
      );

      final contacts = InMemoryContactRepository();
      final throwingContact = _makeMlKemContact('peer-throw-1', 'ThrowFirst');
      final sentContact = _makeMlKemContact('peer-sent', 'SentSecond');
      await contacts.addContact(throwingContact);
      await contacts.addContact(sentContact);
      final throwingGroup = _makeGroup('group-throw', 'Throwing Group');
      await groups.saveGroup(throwingGroup);
      await _seedGroupMembers(groups, throwingGroup.id);
      await _saveLatestGroupKey(groups, throwingGroup.id);
      final queuedGroup = _makeGroup('group-queued', 'Queued Group');
      await groups.saveGroup(queuedGroup);
      await _seedGroupMembers(groups, queuedGroup.id);
      await _saveLatestGroupKey(groups, queuedGroup.id);

      final callOrder = <String>[];
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identities,
        contactRepository: contacts,
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: media,
        groupRepository: groups,
        groupMessageRepository: groupMessages,
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        mediaFileManager: fileManager,
        imageProcessor: _imageProcessor(),
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
              required uploadHooks,
            }) async {
              callOrder.add('contact:${contact.peerId}');
              if (contact.peerId == 'peer-throw-1') {
                throw StateError('first contact target exploded');
              }
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
              callOrder.add('group:${group.id}');
              if (group.id == 'group-throw') {
                throw StateError('middle group target exploded');
              }
              return ShareBatchTargetResult(
                target: ShareTargetSelection.group(group),
                status: ShareBatchTargetStatus.queued,
                detail: 'Saved for retry.',
              );
            },
      );

      final result = await coordinator.deliverGroupMediaForward(
        request: GroupMediaForwardRequest(
          groupId: srcGroupId,
          messageId: srcMessageId,
          attachmentId: srcAttachmentId,
          initialCaption: 'caption',
          provenance: const ForwardProvenance(operationDedupKey: 'fwd-op-30e'),
        ),
        caption: 'caption',
        targets: [
          ShareTargetSelection.contact(throwingContact),
          ShareTargetSelection.contact(sentContact),
          ShareTargetSelection.group(throwingGroup),
          ShareTargetSelection.group(queuedGroup),
        ],
      );

      // Complete ORDERED result list: one failure per thrown target, and
      // every later target still executed. Partial success stays truthful —
      // never collapsed to all-success.
      expect(result.results, hasLength(4));
      expect(result.results[0].status, ShareBatchTargetStatus.failed);
      expect(result.results[1].status, ShareBatchTargetStatus.sent);
      expect(result.results[2].status, ShareBatchTargetStatus.failed);
      expect(result.results[3].status, ShareBatchTargetStatus.queued);
      expect(callOrder, [
        'contact:peer-throw-1',
        'contact:peer-sent',
        'group:group-throw',
        'group:group-queued',
      ]);
      expect(result.sentCount, 1);
      expect(result.queuedCount, 1);
      expect(result.failureCount, 2);

      // The generic OS-share loop isolates exceptions the same way.
      final genericResult = await coordinator.deliver(
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'plain share',
        ),
        targets: [
          ShareTargetSelection.contact(throwingContact),
          ShareTargetSelection.contact(sentContact),
        ],
      );
      expect(genericResult.results, hasLength(2));
      expect(genericResult.results[0].status, ShareBatchTargetStatus.failed);
      expect(genericResult.results[1].status, ShareBatchTargetStatus.sent);
    },
  );

  test(
    'direct batch strict mode requires exactly one input and processed media item',
    () async {
      final contact = _makeMlKemContact('strict-contact-one', 'Strict One');

      Future<
        ({ShareBatchDeliveryResult result, int processCalls, int sendCalls})
      >
      run({
        required ShareIntent intent,
        required List<PendingComposerMedia> processedMedia,
      }) async {
        final contacts = InMemoryContactRepository()..addTestContact(contact);
        var processCalls = 0;
        var sendCalls = 0;
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
          contactRepository: contacts,
          messageRepository: InMemoryMessageRepository(),
          mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
          groupRepository: InMemoryGroupRepository(),
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: FakeBridge(),
          p2pService: FakeP2PService(),
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (_) async {
            processCalls++;
            return ProcessedShareMediaBatch(processedMedia: processedMedia);
          },
          sendToContactFn:
              ({
                required identity,
                required shareIntent,
                required contact,
                required processedMedia,
                required uploadHooks,
              }) async {
                sendCalls++;
                return ShareBatchTargetResult(
                  target: ShareTargetSelection.contact(contact),
                  status: ShareBatchTargetStatus.sent,
                  detail: 'Sent.',
                );
              },
        );
        final result = await coordinator.deliverDirectMediaBatchForwardStrict(
          shareIntent: intent,
          contacts: [contact],
        );
        return (
          result: result,
          processCalls: processCalls,
          sendCalls: sendCalls,
        );
      }

      final twoInputFiles = await run(
        intent: const ShareIntent(
          type: ShareIntentType.files,
          filePaths: ['/tmp/strict-a.jpg', '/tmp/strict-b.jpg'],
        ),
        processedMedia: [
          PendingComposerMedia(file: File('/tmp/strict-a.jpg'), budgetBytes: 3),
          PendingComposerMedia(file: File('/tmp/strict-b.jpg'), budgetBytes: 3),
        ],
      );
      expect(twoInputFiles.result.failureCount, 1);
      expect(twoInputFiles.sendCalls, 0);

      final noProcessedMedia = await run(
        intent: const ShareIntent(
          type: ShareIntentType.mixed,
          text: 'must not become caption-only',
          filePaths: ['/tmp/strict-source.jpg'],
        ),
        processedMedia: const [],
      );
      expect(noProcessedMedia.processCalls, 1);
      expect(noProcessedMedia.result.failureCount, 1);
      expect(noProcessedMedia.sendCalls, 0);

      final twoProcessedMedia = await run(
        intent: const ShareIntent(
          type: ShareIntentType.files,
          filePaths: ['/tmp/strict-source.jpg'],
        ),
        processedMedia: [
          PendingComposerMedia(
            file: File('/tmp/strict-processed-a.jpg'),
            budgetBytes: 3,
          ),
          PendingComposerMedia(
            file: File('/tmp/strict-processed-b.jpg'),
            budgetBytes: 3,
          ),
        ],
      );
      expect(twoProcessedMedia.processCalls, 1);
      expect(twoProcessedMedia.result.failureCount, 1);
      expect(twoProcessedMedia.sendCalls, 0);

      final exactlyOne = await run(
        intent: const ShareIntent(
          type: ShareIntentType.files,
          filePaths: ['/tmp/strict-source.jpg'],
        ),
        processedMedia: [
          PendingComposerMedia(
            file: File('/tmp/strict-source.jpg'),
            budgetBytes: 3,
          ),
        ],
      );
      expect(exactlyOne.processCalls, 1);
      expect(exactlyOne.result.sentCount, 1);
      expect(exactlyOne.sendCalls, 1);
    },
  );

  test(
    'direct batch strict mode fails vanished and oversized media without caption-only send',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'direct_batch_strict_media_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final missingPath = path.join(tempDir.path, 'vanished.jpg');
      final oversized = File(path.join(tempDir.path, 'oversized.jpg'));
      final handle = oversized.openSync(mode: FileMode.write);
      handle.truncateSync(kGroupMediaImageLimitBytes + 1);
      handle.closeSync();
      final contact = _makeMlKemContact('strict-contact-media', 'Strict Media');
      final contacts = InMemoryContactRepository()..addTestContact(contact);
      final messages = InMemoryMessageRepository();
      var sendCalls = 0;
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
        contactRepository: contacts,
        messageRepository: messages,
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
              required uploadHooks,
            }) async {
              sendCalls++;
              return ShareBatchTargetResult(
                target: ShareTargetSelection.contact(contact),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
      );

      for (final sourcePath in [missingPath, oversized.path]) {
        final result = await coordinator.deliverDirectMediaBatchForwardStrict(
          shareIntent: ShareIntent(
            type: ShareIntentType.mixed,
            text: 'caption must not escape alone',
            filePaths: [sourcePath],
          ),
          contacts: [contact],
        );
        expect(result.failureCount, 1, reason: sourcePath);
        expect(result.sentCount, 0, reason: sourcePath);
        expect(result.queuedCount, 0, reason: sourcePath);
      }
      expect(sendCalls, 0);
      expect(messages.count, 0);
    },
  );

  test(
    'direct batch strict mode performs a second exact active contact read and continues valid contacts',
    () async {
      final staleValid = _makeMlKemContact(
        'strict-contact-valid',
        'Stale Valid',
      );
      final currentValid = staleValid.copyWith(username: 'Current Valid');
      final staleMissing = _makeMlKemContact(
        'strict-contact-missing',
        'Stale Missing',
      );
      final staleMismatch = _makeMlKemContact(
        'strict-contact-mismatch',
        'Stale Mismatch',
      );
      final staleArchived = _makeMlKemContact(
        'strict-contact-archived',
        'Stale Archived',
      );
      final staleBlocked = _makeMlKemContact(
        'strict-contact-blocked',
        'Stale Blocked',
      );
      final staleThrowing = _makeMlKemContact(
        'strict-contact-throwing',
        'Stale Throwing',
      );
      final staleLater = _makeMlKemContact(
        'strict-contact-later',
        'Stale Later',
      );
      final currentLater = staleLater.copyWith(username: 'Current Later');
      final events = <String>[];
      final contacts = _StrictContactRepository(events: events)
        ..responses.addAll({
          staleValid.peerId: currentValid,
          staleMissing.peerId: null,
          staleMismatch.peerId: _makeMlKemContact(
            'strict-contact-replaced',
            'Replacement',
          ),
          staleArchived.peerId: staleArchived.copyWith(isArchived: true),
          staleBlocked.peerId: staleBlocked.copyWith(isBlocked: true),
          staleLater.peerId: currentLater,
        })
        ..throwingPeerIds.add(staleThrowing.peerId);
      final source = PendingComposerMedia(
        file: File('/tmp/strict-current-source.jpg'),
        budgetBytes: 3,
      );
      final sentContacts = <ContactModel>[];
      final sentForwardKeys = <String, String>{};
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
        contactRepository: contacts,
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (_) async =>
            ProcessedShareMediaBatch(processedMedia: [source]),
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
              required uploadHooks,
            }) async {
              events.add('send:${contact.peerId}');
              sentContacts.add(contact);
              sentForwardKeys[contact.peerId] =
                  shareIntent.forwardProvenance!.operationDedupKey;
              return ShareBatchTargetResult(
                target: ShareTargetSelection.contact(contact),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
      );
      final requested = [
        staleValid,
        staleMissing,
        staleMismatch,
        staleArchived,
        staleBlocked,
        staleThrowing,
        staleLater,
      ];

      final result = await coordinator.deliverDirectMediaBatchForwardStrict(
        shareIntent: const ShareIntent(
          type: ShareIntentType.files,
          filePaths: ['/tmp/strict-current-source.jpg'],
          forwardProvenance: ForwardProvenance(
            operationDedupKey: 'strict-contact-forward-operation',
          ),
        ),
        contacts: requested,
      );

      expect(result.results.map((entry) => entry.status), [
        ShareBatchTargetStatus.sent,
        ShareBatchTargetStatus.failed,
        ShareBatchTargetStatus.failed,
        ShareBatchTargetStatus.failed,
        ShareBatchTargetStatus.failed,
        ShareBatchTargetStatus.failed,
        ShareBatchTargetStatus.sent,
      ]);
      expect(
        contacts.getContactCalls,
        requested.map((contact) => contact.peerId),
      );
      expect(sentContacts.map((contact) => contact.username), [
        'Current Valid',
        'Current Later',
      ]);
      expect(sentForwardKeys, {
        currentValid.peerId: 'strict-contact-forward-operation',
        currentLater.peerId: 'strict-contact-forward-operation',
      });
      expect(events, [
        'read:${staleValid.peerId}',
        'send:${staleValid.peerId}',
        'read:${staleMissing.peerId}',
        'read:${staleMismatch.peerId}',
        'read:${staleArchived.peerId}',
        'read:${staleBlocked.peerId}',
        'read:${staleThrowing.peerId}',
        'read:${staleLater.peerId}',
        'send:${staleLater.peerId}',
      ]);
    },
  );

  test(
    'default direct delivery retains stale fallback unless strict mode is explicitly selected',
    () async {
      final stale = _makeMlKemContact(
        'strict-default-contact',
        'Stale Default',
      );
      final contacts = _StrictContactRepository()
        ..responses[stale.peerId] = null;
      final source = PendingComposerMedia(
        file: File('/tmp/default-preservation.jpg'),
        budgetBytes: 3,
      );
      var sendCalls = 0;
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
        contactRepository: contacts,
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (_) async =>
            ProcessedShareMediaBatch(processedMedia: [source]),
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
              required uploadHooks,
            }) async {
              sendCalls++;
              expect(contact, stale);
              return ShareBatchTargetResult(
                target: ShareTargetSelection.contact(contact),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
      );
      const intent = ShareIntent(
        type: ShareIntentType.files,
        filePaths: ['/tmp/default-preservation.jpg'],
      );

      final strict = await coordinator.deliverDirectMediaBatchForwardStrict(
        shareIntent: intent,
        contacts: [stale],
      );
      expect(strict.failureCount, 1);
      expect(sendCalls, 0);

      final ordinary = await coordinator.deliver(
        shareIntent: intent,
        targets: [ShareTargetSelection.contact(stale)],
      );
      expect(ordinary.sentCount, 1);
      expect(sendCalls, 1);
      expect(contacts.getContactCalls, [stale.peerId]);
    },
  );
}

class _StrictContactRepository extends InMemoryContactRepository {
  _StrictContactRepository({this.events});

  final List<String>? events;
  final Map<String, ContactModel?> responses = <String, ContactModel?>{};
  final Set<String> throwingPeerIds = <String>{};
  final List<String> getContactCalls = <String>[];

  @override
  Future<ContactModel?> getContact(String peerId) async {
    getContactCalls.add(peerId);
    events?.add('read:$peerId');
    if (throwingPeerIds.contains(peerId)) {
      throw StateError('strict contact lookup failed');
    }
    if (responses.containsKey(peerId)) {
      return responses[peerId];
    }
    return super.getContact(peerId);
  }
}

/// Upgrades legacy production-path share fixtures with the combined authority
/// now required for a fresh ordinary direct-media send.
InMemoryMediaAttachmentRepository _withDirectMediaCustodyAuthority(
  InMemoryMessageRepository messages,
) {
  final media = InMemoryMediaAttachmentRepository();
  media.onStageOutgoingDirectMediaInboxCustody =
      ({
        required expected,
        required staged,
        required attachments,
        required kind,
        required recipientPeerId,
        required wireEnvelope,
      }) async {
        final parent = await messages.stageOutgoingOrdinaryAttempt(
          expected: expected,
          staged: staged,
          kind: kind,
        );
        if (!parent.authorizesTransport) {
          return OutgoingDirectMediaCustodyStageResult(
            outcome: parent.outcome,
            message: parent.message,
            custody: null,
          );
        }
        for (final attachment in attachments) {
          await media.saveAttachment(attachment, owner: MediaOwnerLane.direct);
        }
        final committed = parent.message!.copyWith(media: attachments);
        await messages.saveMessage(committed);
        final incarnationId = sha256
            .convert(
              utf8.encode(
                '$recipientPeerId\u0000${staged.id}\u0000$wireEnvelope',
              ),
            )
            .toString()
            .substring(0, 32);
        final custody = DirectInboxCustodyOutboxEntry(
          recipientPeerId: recipientPeerId,
          messageId: staged.id,
          incarnationId: incarnationId,
          wireEnvelope: wireEnvelope,
          retryCount: 0,
          lastAttemptAt: null,
          lastErrorCode: null,
          createdAt: committed.createdAt,
          updatedAt: committed.createdAt,
        );
        messages.directCustodyRows['$recipientPeerId\u0000${staged.id}'] =
            custody;
        return OutgoingDirectMediaCustodyStageResult(
          outcome: parent.outcome,
          message: committed,
          custody: custody,
        );
      };
  return media;
}

class _ExactRowAwaitMutationRepository
    extends InMemoryMediaAttachmentRepository {
  Future<void> Function(int callCount)? onExactRowAwait;
  int exactRowReadCount = 0;

  @override
  Future<MediaAttachment?> getAttachmentById(String id) async {
    final row = await super.getAttachmentById(id);
    exactRowReadCount++;
    await onExactRowAwait?.call(exactRowReadCount);
    return row;
  }
}

class _DirectMediaCustodyFakeP2PService extends FakeP2PService
    implements AckOrExpiryInboxStore, MediaExpiryBoundedInboxStore {
  _DirectMediaCustodyFakeP2PService({super.initialState});

  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    final stored = await storeInInbox(toPeerId, message, timeoutMs: timeoutMs);
    return InboxStoreOutcome(
      status: stored ? InboxStoreStatus.stored : InboxStoreStatus.failed,
      errorCode: stored ? null : 'STORE_RETURNED_FALSE',
      storeStatus: stored ? 'stored' : null,
      custodyContract: stored ? ackOrExpiryInboxCustodyContract : null,
    );
  }

  @override
  Future<InboxStoreOutcome> storeInMediaExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) async {
    final stored = await storeInInbox(toPeerId, message, timeoutMs: timeoutMs);
    return InboxStoreOutcome(
      status: stored ? InboxStoreStatus.stored : InboxStoreStatus.failed,
      errorCode: stored ? null : 'STORE_RETURNED_FALSE',
      storeStatus: stored ? 'stored' : null,
      custodyContract: stored ? ackOrExpiryInboxCustodyContract : null,
      expiresAtMs: stored ? custodyExpiresAtOrBeforeMs : null,
    );
  }
}

class _FanoutAuthorityP2PService extends _DirectMediaCustodyFakeP2PService {
  _FanoutAuthorityP2PService({
    required this.queuedPeerId,
    required super.initialState,
  });

  final String queuedPeerId;

  @override
  Future<InboxStoreOutcome> storeInMediaExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) {
    if (toPeerId == queuedPeerId) {
      throw StateError('injected post-authority envelope-store failure');
    }
    return super.storeInMediaExpiryBoundedInboxDetailed(
      toPeerId,
      message,
      custodyExpiresAtOrBeforeMs: custodyExpiresAtOrBeforeMs,
      timeoutMs: timeoutMs,
    );
  }
}

class _SharePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _SharePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

class _AuthorityObservingShareBridge extends PassthroughCryptoBridge {
  _AuthorityObservingShareBridge({required this.onFirstMediaUpload});

  final Future<void> Function(Map<String, dynamic> payload) onFirstMediaUpload;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final command = request['cmd'] as String?;
    final payload = request['payload'] as Map<String, dynamic>?;
    if (command == 'media:upload' && payload != null) {
      await onFirstMediaUpload(payload);
    }
    final response = await super.send(message);
    if (command == 'media:upload' &&
        payload != null &&
        payload['custodyContract'] != null) {
      final decoded = jsonDecode(response) as Map<String, dynamic>;
      return jsonEncode(<String, dynamic>{
        ...decoded,
        'id': payload['id'],
        'storeStatus': 'stored',
        'custodyKind': payload['custodyKind'],
        'custodyContract': payload['custodyContract'],
        'contentHash': payload['contentHash'],
        'size': File(payload['filePath'] as String).lengthSync(),
        'mime': payload['mime'],
        'expiresAtMs': DateTime.now()
            .toUtc()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
        'custodyRelayPeerId': 'relay-348',
      });
    }
    return response;
  }
}

/// One durable-authority observation taken at a target's FIRST network call.
class _ForwardAuthoritySnapshot {
  const _ForwardAuthoritySnapshot({
    required this.complete,
    required this.dedupKey,
    required this.isForwarded,
    required this.messageId,
    required this.attachmentIds,
    required this.ciphertextRelativePaths,
    required this.strictRequestObserved,
  });

  final bool complete;
  final String? dedupKey;
  final bool isForwarded;
  final String? messageId;
  final Set<String> attachmentIds;
  final Set<String> ciphertextRelativePaths;
  final bool strictRequestObserved;

  _ForwardAuthoritySnapshot withStrict(bool strict) =>
      _ForwardAuthoritySnapshot(
        complete: complete,
        dedupKey: dedupKey,
        isForwarded: isForwarded,
        messageId: messageId,
        attachmentIds: attachmentIds,
        ciphertextRelativePaths: ciphertextRelativePaths,
        strictRequestObserved: strict,
      );
}

Future<_ForwardAuthoritySnapshot> _readForwardAuthority(
  MediaRepositoryRealDbFixture fixture,
  String recipientPeerId,
) async {
  final parentRows = await fixture.db.query(
    'messages',
    where: 'contact_peer_id = ? AND is_incoming = 0',
    whereArgs: <Object?>[recipientPeerId],
  );
  if (parentRows.length != 1) {
    return const _ForwardAuthoritySnapshot(
      complete: false,
      dedupKey: null,
      isForwarded: false,
      messageId: null,
      attachmentIds: <String>{},
      ciphertextRelativePaths: <String>{},
      strictRequestObserved: false,
    );
  }
  final parent = ConversationMessage.fromMap(parentRows.single);
  final attachments = await fixture.repo.getAttachmentsForMessage(
    parent.id,
    owner: MediaOwnerLane.direct,
  );
  final custodyRows = await fixture.repo.loadDirectMediaBlobCustodyForMessage(
    parent.id,
  );
  final complete =
      attachments.isNotEmpty &&
      attachments.length == custodyRows.length &&
      parent.directMediaCustodyIntentId != null &&
      parent.timestamp == parent.createdAt &&
      !parent.isIncoming &&
      attachments.every(
        (attachment) =>
            attachment.messageId == parent.id &&
            attachment.ownerLane == MediaOwnerLane.direct &&
            attachment.downloadStatus == 'upload_pending' &&
            attachment.encryptionNonce?.isNotEmpty == true,
      ) &&
      custodyRows.every(
        (row) =>
            row.messageId == parent.id &&
            row.recipientPeerId == recipientPeerId &&
            row.direction == DirectMediaBlobCustodyDirection.outgoing &&
            row.state == DirectMediaBlobCustodyState.outgoingPrepared,
      );
  return _ForwardAuthoritySnapshot(
    complete: complete,
    dedupKey: parent.dedupKey,
    isForwarded: parent.isForwarded,
    messageId: parent.id,
    attachmentIds: attachments.map((attachment) => attachment.id).toSet(),
    ciphertextRelativePaths: custodyRows
        .map((row) => row.ciphertextRelativePath)
        .whereType<String>()
        .toSet(),
    strictRequestObserved: false,
  );
}

/// Observes every `media:upload` and returns the strict stored response so a
/// strict-selected target can complete without a real relay.
class _RecipientAuthorityObservingBridge extends PassthroughCryptoBridge {
  _RecipientAuthorityObservingBridge({required this.onMediaUpload});

  final Future<void> Function(Map<String, dynamic> payload) onMediaUpload;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final command = request['cmd'] as String?;
    final payload = request['payload'] as Map<String, dynamic>?;
    if (command == 'media:upload' && payload != null) {
      await onMediaUpload(payload);
    }
    final response = await super.send(message);
    if (command == 'media:upload' &&
        payload != null &&
        payload['custodyContract'] != null) {
      final decoded = jsonDecode(response) as Map<String, dynamic>;
      return jsonEncode(<String, dynamic>{
        ...decoded,
        'id': payload['id'],
        'storeStatus': 'stored',
        'custodyKind': payload['custodyKind'],
        'custodyContract': payload['custodyContract'],
        'contentHash': payload['contentHash'],
        'size': File(payload['filePath'] as String).lengthSync(),
        'mime': payload['mime'],
        'expiresAtMs': DateTime.now()
            .toUtc()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
        'custodyRelayPeerId': 'relay-350',
      });
    }
    return response;
  }
}

/// LAN-local only for the named peers, so one target's FIRST network call is
/// `sendLocalMedia` while the others reach the relay first.
class _LanForPeerFakeP2PService extends _DirectMediaCustodyFakeP2PService {
  _LanForPeerFakeP2PService({
    required this.localPeerIds,
    required this.onSendLocalMedia,
    super.initialState,
  });

  final Set<String> localPeerIds;
  final Future<void> Function(String peerId, String filePath) onSendLocalMedia;

  /// Every strict media-expiry-bounded v108 envelope store, by recipient.
  final Map<String, List<String>> mediaCustodyStoresByPeerId = {};

  @override
  bool isLocalPeer(String peerId) => localPeerIds.contains(peerId);

  @override
  Future<InboxStoreOutcome> storeInMediaExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) {
    mediaCustodyStoresByPeerId
        .putIfAbsent(toPeerId, () => <String>[])
        .add(message);
    return super.storeInMediaExpiryBoundedInboxDetailed(
      toPeerId,
      message,
      custodyExpiresAtOrBeforeMs: custodyExpiresAtOrBeforeMs,
      timeoutMs: timeoutMs,
    );
  }

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
    bool enc = false,
    String? encScheme,
  }) async {
    await onSendLocalMedia(peerId, filePath);
    return super.sendLocalMedia(
      peerId: peerId,
      filePath: filePath,
      mime: mime,
      mediaId: mediaId,
      fromPeerId: fromPeerId,
      durationMs: durationMs,
      waveform: waveform,
      filename: filename,
      enc: enc,
      encScheme: encScheme,
    );
  }
}

bool _sameBytesForShare(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

class _LanFakeP2PService extends _DirectMediaCustodyFakeP2PService {
  _LanFakeP2PService({super.initialState});

  @override
  bool isLocalPeer(String peerId) => true;
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
        const VideoProcessResult(path: '/tmp/video.mp4'),
  );
}

ContactModel _makeMlKemContact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-09T08:00:00.000Z',
    mlKemPublicKey: 'mlkem-$peerId',
  );
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

GroupModel _makeGroup(String id, String name) {
  return GroupModel(
    id: id,
    name: name,
    type: GroupType.chat,
    topicName: 'topic-$id',
    createdAt: DateTime.parse('2026-03-09T08:00:00.000Z'),
    createdBy: 'me',
    myRole: GroupRole.admin,
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

Future<void> _saveLatestGroupKey(
  InMemoryGroupRepository groupRepository,
  String groupId,
) async {
  await groupRepository.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: 1,
      encryptedKey: 'test-group-key-1',
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

Future<void> _seedGroupMembers(
  InMemoryGroupRepository groupRepository,
  String groupId,
) async {
  final joinedAt = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
  await groupRepository.saveMember(
    GroupMember(
      groupId: groupId,
      peerId: 'my-peer-id-12345',
      username: 'Me',
      role: MemberRole.admin,
      publicKey: 'my-public-key',
      mlKemPublicKey: 'mlkem-public',
      joinedAt: joinedAt,
    ),
  );
  await groupRepository.saveMember(
    GroupMember(
      groupId: groupId,
      peerId: 'peer-writer',
      username: 'Writer',
      role: MemberRole.writer,
      publicKey: 'pk-peer-writer',
      mlKemPublicKey: 'mlkem-peer-writer',
      joinedAt: joinedAt.add(const Duration(seconds: 1)),
    ),
  );
}

/// 210b: the realistic offline-device reliable contract — publish "succeeds"
/// with zero live topic peers and no relay custody, so the use case returns
/// queuedOffline and persists a durable 'queued_offline' row.
class _GroupShareReliableNoCustodyBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'bg:begin') {
      commandLog.add(cmd!);
      return 'share-group-bg-task';
    }
    if (cmd == 'bg:end') {
      commandLog.add(cmd!);
      return '';
    }
    if (cmd == 'group:sendReliable') {
      commandLog.add(cmd!);
      return jsonEncode({
        'ok': true,
        'publishSucceeded': true,
        'inboxStored': false,
        'topicPeerCount': 0,
        'connectedTopicPeerCount': 0,
        'expectedRecipientCount': 2,
        'recipientPeerIds': ['peer-writer', 'peer-reader'],
        'deliveryMode': 'live_only',
      });
    }
    return super.send(message);
  }
}

class _GroupShareBgBridge extends FakeBridge {
  _GroupShareBgBridge({
    required this.publishMessageId,
    required this.publishTopicPeers,
    required this.inboxStoreOk,
  });

  final String publishMessageId;
  final int publishTopicPeers;
  final bool inboxStoreOk;

  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);

    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    lastCommand = cmd;
    if (cmd != null) {
      commandLog.add(cmd);
    }

    switch (cmd) {
      case 'bg:begin':
        return 'share-group-bg-task';
      case 'bg:end':
        return '';
      case 'group.encrypt':
        final payload = parsed['payload'] as Map<String, dynamic>;
        return jsonEncode({
          'ok': true,
          'ciphertext': payload['plaintext'],
          'nonce': 'share-group-fake-nonce',
        });
      case 'payload.sign':
        return jsonEncode({'ok': true, 'signature': 'share-group-signature'});
      case 'group:publish':
        return jsonEncode({
          'ok': true,
          'messageId': publishMessageId,
          'topicPeers': publishTopicPeers,
        });
      case 'group:inboxStore':
        return jsonEncode({'ok': inboxStoreOk});
      default:
        return super.send(message);
    }
  }
}

void _expectCommandOrder(List<String> commands, String earlier, String later) {
  expect(commands, contains(earlier));
  expect(commands, contains(later));
  expect(commands.indexOf(earlier), lessThan(commands.indexOf(later)));
}
