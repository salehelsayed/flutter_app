import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/features/conversation/application/build_received_media_forward.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const ownPeerId = 'direct-forward-own-peer';
  const sourcePeerId = 'direct-forward-source-peer';
  const destinationGroupIds = [
    'direct-forward-destination-group-one',
    'direct-forward-destination-group-two',
  ];
  const destinationPeerIds = [
    'direct-forward-group-peer-one',
    'direct-forward-group-peer-two',
  ];
  const timestamp = '2026-07-14T12:00:00.000Z';

  final cases =
      <
        ({
          String label,
          String fixturePath,
          String extension,
          String mime,
          String mediaType,
          int? durationMs,
        })
      >[
        (
          label: 'image',
          fixturePath:
              'integration_test/fixtures/received_media_egress_fixture.jpg',
          extension: 'jpg',
          mime: 'image/jpeg',
          mediaType: 'image',
          durationMs: null,
        ),
        (
          label: 'video',
          fixturePath:
              'integration_test/fixtures/received_media_egress_fixture.mp4',
          extension: 'mp4',
          mime: 'video/mp4',
          mediaType: 'video',
          durationMs: 1240,
        ),
      ];

  for (final mediaCase in cases) {
    test('direct received ${mediaCase.label} reroots a stale iOS path and '
        'projects fresh retry-stable copies to two groups', () async {
      final fixture = File(mediaCase.fixturePath);
      expect(
        fixture.existsSync(),
        isTrue,
        reason: 'the preservation test uses a real checked-in fixture',
      );

      final previousProbeDelays = debugGroupMediaUploadPostCommitProbeDelays;
      final documentsDir = Directory.systemTemp.createTempSync(
        'direct_to_group_ios_${mediaCase.label}_',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        pathProviderChannel,
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? documentsDir.path
            : null,
      );
      MediaFileManager.cacheDocumentsDir(documentsDir.path);
      debugGroupMediaUploadPostCommitProbeDelays = const [];
      addTearDown(() {
        messenger.setMockMethodCallHandler(pathProviderChannel, null);
        debugGroupMediaUploadPostCommitProbeDelays = previousProbeDelays;
        MediaFileManager.debugResetDocumentsDirCache();
        if (documentsDir.existsSync()) {
          documentsDir.deleteSync(recursive: true);
        }
      });

      final sourceAttachmentId = 'direct-source-${mediaCase.label}-attachment';
      final sourceMessageId = 'direct-source-${mediaCase.label}-message';
      final sourceRelativePath = path.join(
        'media',
        sourcePeerId,
        '$sourceAttachmentId.${mediaCase.extension}',
      );
      final currentCanonicalSource = File(
        path.join(documentsDir.path, sourceRelativePath),
      );
      currentCanonicalSource.parent.createSync(recursive: true);
      fixture.copySync(currentCanonicalSource.path);
      final sourcePlaintext = currentCanonicalSource.readAsBytesSync();
      final sourcePlaintextHash = sha256.convert(sourcePlaintext).toString();
      final sourceRelayCiphertext = <int>[
        ...sourcePlaintext,
        ...List<int>.filled(16, 0x5a),
      ];
      final sourceRelayCiphertextHash = sha256
          .convert(sourceRelayCiphertext)
          .toString();
      expect(sourceRelayCiphertextHash, isNot(sourcePlaintextHash));

      final staleStoredPath =
          '/var/mobile/Containers/Data/Application/'
          'STALE-IOS-CONTAINER/Documents/$sourceRelativePath';
      final sourceAttachment = MediaAttachment(
        id: sourceAttachmentId,
        messageId: sourceMessageId,
        mime: mediaCase.mime,
        size: sourcePlaintext.length,
        mediaType: mediaCase.mediaType,
        durationMs: mediaCase.durationMs,
        localPath: staleStoredPath,
        downloadStatus: 'done',
        createdAt: timestamp,
        contentHash: sourceRelayCiphertextHash,
        encryptionKeyBase64: 'source-relay-key',
        encryptionNonce: 'source-relay-nonce',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ownerLane: MediaOwnerLane.direct,
      );
      final sourceMessage = ConversationMessage(
        id: sourceMessageId,
        contactPeerId: sourcePeerId,
        senderPeerId: sourcePeerId,
        text: '${mediaCase.label} source caption',
        timestamp: timestamp,
        status: 'delivered',
        isIncoming: true,
        createdAt: timestamp,
        media: [sourceAttachment],
      );

      final directMessages = InMemoryMessageRepository();
      final mediaRepository = InMemoryMediaAttachmentRepository();
      await directMessages.saveMessage(sourceMessage);
      await mediaRepository.saveAttachment(
        sourceAttachment,
        owner: MediaOwnerLane.direct,
      );

      final operationKey = 'direct-to-group-${mediaCase.label}-operation';
      final draftResult = await BuildReceivedMediaForward(
        loadParentMessage: directMessages.getMessage,
        mediaAttachmentRepository: mediaRepository,
        operationTokenFactory: () => operationKey,
      ).build(parent: sourceMessage, currentAttachmentId: sourceAttachmentId);
      expect(draftResult.denial, isNull);
      final shareIntent = draftResult.draft!.shareIntent;
      expect(shareIntent.filePaths, [currentCanonicalSource.path]);
      expect(
        File(shareIntent.filePaths.single).readAsBytesSync(),
        sourcePlaintext,
      );
      expect(shareIntent.forwardProvenance?.operationDedupKey, operationKey);

      final identityRepository = FakeIdentityRepository()
        ..seed(
          IdentityModel(
            peerId: ownPeerId,
            publicKey: 'direct-forward-own-public-key',
            privateKey: 'direct-forward-own-private-key',
            mnemonic12:
                'one two three four five six seven eight nine ten eleven twelve',
            username: 'Me',
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        );
      final groupRepository = InMemoryGroupRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      final groups = <GroupModel>[];
      for (var index = 0; index < destinationGroupIds.length; index++) {
        final group = GroupModel(
          id: destinationGroupIds[index],
          name: 'Forward destination ${index + 1}',
          type: GroupType.chat,
          topicName: 'topic-${destinationGroupIds[index]}',
          createdAt: DateTime.parse(timestamp),
          createdBy: ownPeerId,
          myRole: GroupRole.admin,
        );
        groups.add(group);
        await groupRepository.saveGroup(group);
        await groupRepository.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: ownPeerId,
            username: 'Me',
            role: MemberRole.admin,
            publicKey: 'direct-forward-own-public-key',
            joinedAt: DateTime.parse(timestamp),
          ),
        );
        await groupRepository.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: destinationPeerIds[index],
            username: 'Writer ${index + 1}',
            role: MemberRole.writer,
            publicKey: 'direct-forward-group-public-key-${index + 1}',
            joinedAt: DateTime.parse(
              timestamp,
            ).add(Duration(seconds: index + 1)),
          ),
        );
        await groupRepository.saveKey(
          GroupKeyInfo(
            groupId: group.id,
            keyGeneration: 1,
            encryptedKey: 'direct-forward-group-key-${index + 1}',
            createdAt: DateTime.parse(timestamp),
          ),
        );
      }

      final bridge = _CiphertextCapturingGroupBridge();
      final mediaFileManager = MediaFileManager();
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: directMessages,
        mediaAttachmentRepository: mediaRepository,
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        bridge: bridge,
        p2pService: FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: ownPeerId),
        ),
        mediaFileManager: mediaFileManager,
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
              ({required path, required compress, onProgress}) async =>
                  VideoProcessResult(
                    path: path,
                    width: mediaCase.mediaType == 'video' ? 31 : null,
                    height: mediaCase.mediaType == 'video' ? 64 : null,
                    durationMs: mediaCase.durationMs,
                  ),
        ),
        qualityPreference: ImageQualityPreference.original,
        videoQualityPreference: ImageQualityPreference.original,
      );

      final targets = groups
          .map(ShareTargetSelection.group)
          .toList(growable: false);
      final expectedOperationKeys = {
        for (final group in groups)
          group.id: groupForwardProvenanceForGroup(
            base: shareIntent.forwardProvenance!,
            groupId: group.id,
          ).operationDedupKey,
      };
      expect(expectedOperationKeys.values.toSet(), hasLength(groups.length));
      expect(expectedOperationKeys.values, isNot(contains(operationKey)));

      final delivery = await coordinator.deliver(
        shareIntent: shareIntent,
        targets: targets,
      );

      expect(
        delivery.failureCount,
        0,
        reason: delivery.results.map((result) => result.detail).join('; '),
      );
      expect(delivery.sentCount, groups.length);
      expect(
        bridge.commandLog,
        containsAllInOrder([
          'blob:keygen',
          'blob:encrypt',
          'media:upload',
          'group.encrypt',
          'payload.sign',
          'group:sendReliable',
        ]),
      );
      expect(bridge.uploadPayloads, hasLength(groups.length));
      expect(bridge.reliablePayloads, hasLength(groups.length));

      final firstMessageIds = <String>{};
      final projectedAttachmentIds = <String>{};
      final projectedKeys = <String>{};
      final projectedNonces = <String>{};
      final projectedHashes = <String>{};
      for (var index = 0; index < groups.length; index++) {
        final group = groups[index];
        final expectedOperationKey = expectedOperationKeys[group.id]!;
        final groupMessages = await groupMessageRepository.getMessagesPage(
          group.id,
        );
        expect(groupMessages, hasLength(1));
        final projectedMessage = groupMessages.single;
        firstMessageIds.add(projectedMessage.id);
        expect(projectedMessage.id, expectedOperationKey);
        expect(projectedMessage.logicalDeliveryId, expectedOperationKey);
        expect(projectedMessage.senderPeerId, ownPeerId);
        expect(projectedMessage.isIncoming, isFalse);
        expect(projectedMessage.isForwarded, isTrue);
        expect(projectedMessage.status, 'sent');

        final groupAttachments = await mediaRepository.getAttachmentsForMessage(
          projectedMessage.id,
          owner: MediaOwnerLane.group,
        );
        expect(groupAttachments, hasLength(1));
        final projectedAttachment = groupAttachments.single;
        projectedAttachmentIds.add(projectedAttachment.id);
        projectedKeys.add(projectedAttachment.encryptionKeyBase64!);
        projectedNonces.add(projectedAttachment.encryptionNonce!);
        projectedHashes.add(projectedAttachment.contentHash!);
        expect(projectedAttachment.ownerLane, MediaOwnerLane.group);
        expect(projectedAttachment.id, isNot(sourceAttachment.id));
        expect(projectedAttachment.messageId, projectedMessage.id);
        expect(projectedAttachment.mime, mediaCase.mime);
        expect(projectedAttachment.mediaType, mediaCase.mediaType);
        expect(projectedAttachment.size, sourcePlaintext.length);
        expect(projectedAttachment.durationMs, mediaCase.durationMs);
        expect(
          projectedAttachment.encryptionScheme,
          kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        expect(
          projectedAttachment.encryptionKeyBase64,
          isNot(sourceAttachment.encryptionKeyBase64),
        );
        expect(
          projectedAttachment.encryptionNonce,
          isNot(sourceAttachment.encryptionNonce),
        );
        expect(
          projectedAttachment.contentHash,
          isNot(sourceAttachment.contentHash),
        );

        final uploadPayload = bridge.uploadPayloads.singleWhere(
          (payload) => payload['to'] == group.id,
        );
        expect(uploadPayload['id'], projectedAttachment.id);
        final uploadedCiphertext =
            bridge.uploadedCiphertextByBlobId[projectedAttachment.id]!;
        final uploadedCiphertextHash = sha256
            .convert(uploadedCiphertext)
            .toString();
        expect(uploadedCiphertext.length, sourcePlaintext.length + 16);
        expect(uploadedCiphertext, isNot(sourcePlaintext));
        expect(projectedAttachment.contentHash, uploadedCiphertextHash);
        expect(projectedAttachment.contentHash, isNot(sourcePlaintextHash));
        expect(
          uploadPayload['filePath'],
          endsWith('.enc'),
          reason: 'the relay upload must receive ciphertext, not plaintext',
        );
        expect(uploadPayload['mime'], mediaCase.mime);
        expect((uploadPayload['allowedPeers'] as List).toSet(), {
          ownPeerId,
          destinationPeerIds[index],
        });

        final storedGroupPath = projectedAttachment.localPath!;
        expect(storedGroupPath, startsWith('media/${group.id}/'));
        final canonicalGroupCopy = File(
          await mediaFileManager.resolveStoredPath(storedGroupPath),
        );
        expect(canonicalGroupCopy.existsSync(), isTrue);
        expect(canonicalGroupCopy.readAsBytesSync(), sourcePlaintext);
        expect(
          canonicalGroupCopy.path,
          startsWith(path.join(documentsDir.path, 'media', group.id)),
        );

        final reliablePayload = bridge.reliablePayloads.singleWhere(
          (payload) => payload['groupId'] == group.id,
        );
        expect(reliablePayload['messageId'], expectedOperationKey);
        expect(reliablePayload['logicalDeliveryId'], expectedOperationKey);
        final wireMedia = (reliablePayload['media'] as List)
            .cast<Map<String, dynamic>>()
            .single;
        expect(wireMedia['id'], projectedAttachment.id);
        expect(wireMedia['contentHash'], uploadedCiphertextHash);
        expect(
          wireMedia['encryptionKeyBase64'],
          projectedAttachment.encryptionKeyBase64,
        );
        expect(
          wireMedia['encryptionNonce'],
          projectedAttachment.encryptionNonce,
        );
        expect(wireMedia.containsKey('ownerLane'), isFalse);
        expect(wireMedia.containsKey('localPath'), isFalse);
      }
      expect(firstMessageIds, hasLength(groups.length));
      expect(projectedAttachmentIds, hasLength(groups.length));
      expect(projectedKeys, hasLength(groups.length));
      expect(projectedNonces, hasLength(groups.length));
      expect(projectedHashes, hasLength(groups.length));

      final retry = await coordinator.deliver(
        shareIntent: shareIntent,
        targets: targets,
      );
      expect(
        retry.failureCount,
        0,
        reason: retry.results.map((result) => result.detail).join('; '),
      );
      expect(retry.sentCount, groups.length);
      expect(bridge.uploadPayloads, hasLength(groups.length));
      expect(bridge.reliablePayloads, hasLength(groups.length));
      for (final group in groups) {
        final messages = await groupMessageRepository.getMessagesPage(group.id);
        expect(messages, hasLength(1));
        expect(messages.single.id, expectedOperationKeys[group.id]);
        expect(firstMessageIds, contains(messages.single.id));
        expect(
          await mediaRepository.getAttachmentsForMessage(
            messages.single.id,
            owner: MediaOwnerLane.group,
          ),
          hasLength(1),
        );
      }

      final retainedSource = (await mediaRepository.getAttachmentsForMessage(
        sourceMessage.id,
        owner: MediaOwnerLane.direct,
      )).single;
      expect(retainedSource.localPath, staleStoredPath);
      expect(currentCanonicalSource.readAsBytesSync(), sourcePlaintext);
    });
  }
}

class _CiphertextCapturingGroupBridge extends FakeBridge {
  int _encryptionCount = 0;
  final List<Map<String, dynamic>> uploadPayloads = [];
  final Map<String, List<int>> uploadedCiphertextByBlobId = {};
  final List<Map<String, dynamic>> reliablePayloads = [];

  void _record(String rawMessage, String command) {
    sendCallCount++;
    lastSentMessage = rawMessage;
    sentMessages.add(rawMessage);
    lastCommand = command;
    commandLog.add(command);
  }

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final command = request['cmd'] as String?;
    switch (command) {
      case 'blob:encrypt':
        _record(message, command!);
        _encryptionCount++;
        final payload = request['payload'] as Map<String, dynamic>;
        final source = File(payload['filePath'] as String);
        final encrypted = File('${source.path}.enc');
        final tagByte = 0xc0 + _encryptionCount;
        encrypted.writeAsBytesSync([
          ...source.readAsBytesSync(),
          ...List<int>.filled(16, tagByte),
        ]);
        return jsonEncode({
          'ok': true,
          'encryptedPath': encrypted.path,
          'nonce': 'fresh-forward-nonce-$_encryptionCount',
        });
      case 'media:upload':
        _record(message, command!);
        final uploadPayload = Map<String, dynamic>.from(
          request['payload'] as Map<String, dynamic>,
        );
        uploadPayloads.add(uploadPayload);
        uploadedCiphertextByBlobId[uploadPayload['id'] as String] = File(
          uploadPayload['filePath'] as String,
        ).readAsBytesSync();
        return jsonEncode({'ok': true, 'id': uploadPayload['id']});
      case 'group:sendReliable':
        _record(message, command!);
        final reliablePayload = Map<String, dynamic>.from(
          request['payload'] as Map<String, dynamic>,
        );
        reliablePayloads.add(reliablePayload);
        final recipients =
            (reliablePayload['recipientPeerIds'] as List?) ?? const <Object>[];
        return jsonEncode({
          'ok': true,
          'publishSucceeded': true,
          'inboxStored': true,
          'topicPeerCount': recipients.length,
          'connectedTopicPeerCount': recipients.length,
          'expectedRecipientCount': recipients.length,
          'recipientPeerIds': recipients,
          'deliveryMode': 'live_and_inbox',
        });
      default:
        return super.send(message);
    }
  }
}
