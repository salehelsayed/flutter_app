import 'dart:io';

import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/foreground_group_media_upload.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

typedef GroupMediaReliabilityConfigBuilder =
    Map<String, dynamic> Function(GroupModel group, List<GroupMember> members);

Future<Map<String, Object?>> setupGroupMediaReliabilitySender({
  required String receiverAccountPeerId,
  required String receiverTransportPeerId,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required ContactRepository contactRepository,
  required GroupRepository groupRepository,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository,
  AppendGroupEventLogEntry? appendGroupEventLogEntry,
  GroupMediaReliabilityAuthorityMode authorityMode =
      GroupMediaReliabilityAuthorityMode.distinctAccountAndTransport,
}) async {
  final identity = await identityRepository.loadIdentity();
  final receiver = await contactRepository.getContact(receiverAccountPeerId);
  final transport = await _waitForLocalTransportPeerId(p2pService);
  if (identity == null ||
      receiver == null ||
      receiver.mlKemPublicKey == null ||
      receiver.mlKemPublicKey!.trim().isEmpty ||
      transport == null ||
      transport.isEmpty ||
      identity.peerId == receiverAccountPeerId ||
      !groupMediaReliabilityIdentityMatches(
        mode: authorityMode,
        accountPeerId: identity.peerId,
        transportPeerId: transport,
      ) ||
      !groupMediaReliabilityIdentityMatches(
        mode: authorityMode,
        accountPeerId: receiverAccountPeerId,
        transportPeerId: receiverTransportPeerId,
      )) {
    throw StateError(
      'group-media sender lacks configured account/transport authority',
    );
  }
  final result = await createGroupWithMembers(
    bridge: bridge,
    groupRepo: groupRepository,
    p2pService: p2pService,
    identity: identity,
    selectedContacts: [receiver],
    type: GroupType.chat,
    name: 'P269 ${DateTime.now().toUtc().microsecondsSinceEpoch}',
    selectedContactDeviceBindings:
        authorityMode == GroupMediaReliabilityAuthorityMode.accountBoundLegacy
        ? const <String, GroupMemberDeviceIdentity>{}
        : <String, GroupMemberDeviceIdentity>{
            receiverAccountPeerId: GroupMemberDeviceIdentity(
              deviceId: receiverTransportPeerId,
              transportPeerId: receiverTransportPeerId,
              deviceSigningPublicKey: receiver.publicKey,
              mlKemPublicKey: receiver.mlKemPublicKey,
              keyPackageId: defaultGroupWelcomeKeyPackageIdForDevice(
                receiverTransportPeerId,
              ),
              keyPackagePublicMaterial: receiver.mlKemPublicKey,
            ),
          },
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepository,
    appendGroupEventLogEntry: appendGroupEventLogEntry,
  );
  if (result.membersAdded != 1 ||
      result.invitesSent != 1 ||
      result.membershipSyncRolledBack) {
    throw StateError('group-media sender group/invite setup did not settle');
  }
  return <String, Object?>{
    'groupId': result.group.id,
    'accountPeerId': identity.peerId,
    'transportPeerId': transport,
  };
}

Future<Map<String, Object?>> sendGroupMediaReliabilityFixtures({
  required String runId,
  required String groupId,
  required Map<String, String> messageIds,
  required Map<String, String> attachmentIds,
  required String receiverAccountPeerId,
  required String receiverTransportPeerId,
  required Directory fixtureDirectory,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  required GroupMediaReliabilityConfigBuilder groupConfigBuilder,
  required GroupMessageRepository groupMessageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required MediaFileManager mediaFileManager,
  required AudioRecorderService audioRecorderService,
  GroupMediaReliabilityAuthorityMode authorityMode =
      GroupMediaReliabilityAuthorityMode.distinctAccountAndTransport,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository,
}) => _sendGroupMediaReliabilityFixturesForKinds(
  runId: runId,
  groupId: groupId,
  messageIds: messageIds,
  attachmentIds: attachmentIds,
  fixtureKinds: const <String>{'jpeg', 'mp4', 'voice'},
  receiverAccountPeerId: receiverAccountPeerId,
  receiverTransportPeerId: receiverTransportPeerId,
  fixtureDirectory: fixtureDirectory,
  bridge: bridge,
  p2pService: p2pService,
  identityRepository: identityRepository,
  groupRepository: groupRepository,
  groupConfigBuilder: groupConfigBuilder,
  groupMessageRepository: groupMessageRepository,
  mediaAttachmentRepository: mediaAttachmentRepository,
  mediaFileManager: mediaFileManager,
  audioRecorderService: audioRecorderService,
  authorityMode: authorityMode,
  inviteDeliveryAttemptRepository: inviteDeliveryAttemptRepository,
);

/// Publishes the one fixed JPEG fixture used by Plan 393's killed-recipient
/// group-message proof. This deliberately exposes no caller-selected media
/// kind; the established three-kind reliability fixture remains unchanged.
Future<Map<String, Object?>> sendGroupKilledIncomingJpegReliabilityFixture({
  required String runId,
  required String groupId,
  required String messageId,
  required String attachmentId,
  required String receiverAccountPeerId,
  required String receiverTransportPeerId,
  required Directory fixtureDirectory,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  required GroupMediaReliabilityConfigBuilder groupConfigBuilder,
  required GroupMessageRepository groupMessageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required MediaFileManager mediaFileManager,
  required AudioRecorderService audioRecorderService,
  GroupMediaReliabilityAuthorityMode authorityMode =
      GroupMediaReliabilityAuthorityMode.distinctAccountAndTransport,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository,
}) => _sendGroupMediaReliabilityFixturesForKinds(
  runId: runId,
  groupId: groupId,
  messageIds: <String, String>{'jpeg': messageId},
  attachmentIds: <String, String>{'jpeg': attachmentId},
  fixtureKinds: const <String>{'jpeg'},
  receiverAccountPeerId: receiverAccountPeerId,
  receiverTransportPeerId: receiverTransportPeerId,
  fixtureDirectory: fixtureDirectory,
  bridge: bridge,
  p2pService: p2pService,
  identityRepository: identityRepository,
  groupRepository: groupRepository,
  groupConfigBuilder: groupConfigBuilder,
  groupMessageRepository: groupMessageRepository,
  mediaAttachmentRepository: mediaAttachmentRepository,
  mediaFileManager: mediaFileManager,
  audioRecorderService: audioRecorderService,
  authorityMode: authorityMode,
  inviteDeliveryAttemptRepository: inviteDeliveryAttemptRepository,
);

Future<Map<String, Object?>> _sendGroupMediaReliabilityFixturesForKinds({
  required String runId,
  required String groupId,
  required Map<String, String> messageIds,
  required Map<String, String> attachmentIds,
  required Set<String> fixtureKinds,
  required String receiverAccountPeerId,
  required String receiverTransportPeerId,
  required Directory fixtureDirectory,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  required GroupMediaReliabilityConfigBuilder groupConfigBuilder,
  required GroupMessageRepository groupMessageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required MediaFileManager mediaFileManager,
  required AudioRecorderService audioRecorderService,
  required GroupMediaReliabilityAuthorityMode authorityMode,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository,
}) async {
  final identity = await identityRepository.loadIdentity();
  final senderTransport = await _waitForLocalTransportPeerId(p2pService);
  if (identity == null || senderTransport == null || senderTransport.isEmpty) {
    throw StateError('group-media send identity discriminator failed');
  }

  final members = await _waitForReceiverTransportRoster(
    groupRepository: groupRepository,
    p2pService: p2pService,
    groupId: groupId,
    receiverAccountPeerId: receiverAccountPeerId,
    receiverTransportPeerId: receiverTransportPeerId,
  );
  final allowedPeers = groupMediaAllowedPeersForMembers(members);
  if (!groupMediaReliabilityAuthorityMatches(
    mode: authorityMode,
    localAccountPeerId: identity.peerId,
    localTransportPeerId: senderTransport,
    remoteAccountPeerId: receiverAccountPeerId,
    remoteTransportPeerId: receiverTransportPeerId,
    allowedPeers: allowedPeers,
  )) {
    throw StateError('group-media authority policy rejected');
  }

  // App startup can still be rejoining older groups after SQL and transport
  // identity have converged. The native reliable-send path requires this
  // exact target to be present in its in-memory topic/config/key maps, so make
  // the established production join call an explicit fixture precondition.
  await _ensureExactGroupTopicJoined(
    bridge: bridge,
    groupRepository: groupRepository,
    groupId: groupId,
    members: members,
    groupConfigBuilder: groupConfigBuilder,
  );

  await fixtureDirectory.create(recursive: true);
  final allSpecs = <({String kind, String mime, String? asset})>[
    (
      kind: 'mp4',
      mime: 'video/mp4',
      asset: 'integration_test/fixtures/received_media_egress_fixture.mp4',
    ),
    (kind: 'voice', mime: 'audio/mp4', asset: null),
    // The process-death target is intentionally last. The sender endpoint can
    // therefore prove every upload/publication settled before the host starts
    // observing the receiver's JPEG post-claim/pre-commit barrier.
    (
      kind: 'jpeg',
      mime: 'image/jpeg',
      asset: 'integration_test/fixtures/received_media_egress_fixture.jpg',
    ),
  ];
  final specs = allSpecs
      .where((spec) => fixtureKinds.contains(spec.kind))
      .toList(growable: false);
  if (fixtureKinds.isEmpty ||
      specs.length != fixtureKinds.length ||
      messageIds.keys.toSet().length != fixtureKinds.length ||
      attachmentIds.keys.toSet().length != fixtureKinds.length ||
      !messageIds.keys.toSet().containsAll(fixtureKinds) ||
      !attachmentIds.keys.toSet().containsAll(fixtureKinds) ||
      messageIds.values.toSet().length != fixtureKinds.length ||
      attachmentIds.values.toSet().length != fixtureKinds.length) {
    throw StateError('group-media fixture IDs are incomplete or reused');
  }

  final uploads = <String, int>{};
  final publications = <String, int>{};
  final transientSources = <File>[];
  final uploadLease = mediaUploadInFlightTracker.tryClaimAll(
    attachmentIds.values,
    source: MediaUploadTriggerSource.foreground,
  );
  if (uploadLease == null) {
    throw StateError('group-media fixture attachment lease was denied');
  }
  try {
    for (final spec in specs) {
      final messageId = messageIds[spec.kind]!;
      final attachmentId = attachmentIds[spec.kind]!;
      late final File source;
      int? durationMs;
      List<double>? waveform;
      if (spec.asset case final asset?) {
        final bytes = await rootBundle.load(asset);
        source = File('${fixtureDirectory.path}/$runId-${spec.kind}.bin');
        await source.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      } else {
        if (!await audioRecorderService.hasPermission()) {
          throw StateError('group-media voice fixture lacks RECORD_AUDIO');
        }
        await audioRecorderService.start(outputPath: '');
        await Future<void>.delayed(const Duration(milliseconds: 1700));
        final recording = await audioRecorderService.stop();
        if (recording == null ||
            recording.mime != 'audio/mp4' ||
            recording.durationMs < 1500 ||
            recording.sizeBytes <= 12) {
          throw StateError('group-media voice fixture recording is invalid');
        }
        source = File(recording.filePath);
        final header = await source
            .openRead(0, 12)
            .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
        if (header.length < 12 ||
            String.fromCharCodes(header.sublist(4, 8)) != 'ftyp') {
          throw StateError('group-media voice fixture is not AAC/M4A');
        }
        durationMs = recording.durationMs;
        waveform = const <double>[0.15, 0.5, 0.85, 0.35];
      }
      transientSources.add(source);
      final sourceSize = await source.length();
      final mimeValidation = await GroupMediaMimePolicy.validateFile(
        path: source.path,
        mime: spec.mime,
        mediaType: GroupMediaMimePolicy.mediaTypeForMime(spec.mime),
      );
      final sizeValidation = GroupMediaSizePolicy.validateSize(
        sizeBytes: sourceSize,
        mime: spec.mime,
      );
      if (!mimeValidation.isValid || !sizeValidation.isValid) {
        throw StateError('group-media ${spec.kind} fixture policy rejected');
      }

      final durableRelativePath = await mediaFileManager.copyToDurableStorage(
        sourceFilePath: source.path,
        messageId: messageId,
        attachmentId: attachmentId,
        mime: spec.mime,
      );
      final durableAbsolutePath = await mediaFileManager.resolveStoredPath(
        durableRelativePath,
      );
      final contentHash = await GroupMediaIntegrityPolicy.computeFileSha256Hex(
        durableAbsolutePath,
      );
      final now = DateTime.now().toUtc();
      final expectedParent = GroupMessage(
        id: messageId,
        groupId: groupId,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        text: '',
        timestamp: now,
        status: 'sending',
        isIncoming: false,
        createdAt: now,
      );
      final expectedAttachment = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: spec.mime,
        size: sourceSize,
        mediaType: MediaAttachment.mediaTypeFromMime(spec.mime),
        durationMs: durationMs,
        localPath: durableRelativePath,
        waveform: waveform,
        downloadStatus: 'upload_pending',
        createdAt: now.toIso8601String(),
        uploadRetryCount: 0,
        downloadRetryCount: 0,
        contentHash: contentHash,
        ownerLane: MediaOwnerLane.group,
      );

      // The exact parent exists before the shared production leaf persists and
      // SQL-default-reloads the attachment. The process-wide lease above owns
      // every supplied blob ID before either row becomes visible.
      await groupMessageRepository.saveMessage(expectedParent);
      final completed = await runForegroundGroupUploadLeaf(
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        expectedParent: expectedParent,
        expectedAttachment: expectedAttachment,
        senderPeerId: identity.peerId,
        inviteDeliveryAttemptRepository: inviteDeliveryAttemptRepository,
        upload: (currentAllowedPeers) {
          if (!groupMediaReliabilityAuthorityMatches(
            mode: authorityMode,
            localAccountPeerId: identity.peerId,
            localTransportPeerId: senderTransport,
            remoteAccountPeerId: receiverAccountPeerId,
            remoteTransportPeerId: receiverTransportPeerId,
            allowedPeers: currentAllowedPeers,
          )) {
            throw StateError('group-media authority policy rejected');
          }
          return uploadMedia(
            bridge: bridge,
            localFilePath: durableAbsolutePath,
            mime: spec.mime,
            recipientPeerId: groupId,
            mediaFileManager: mediaFileManager,
            durationMs: durationMs,
            waveform: waveform,
            allowedPeers: currentAllowedPeers,
            blobId: attachmentId,
          );
        },
        buildCompleted: (uploaded) async {
          final absoluteOwnedPath = await mediaFileManager
              .localPathForAttachment(
                contactPeerId: groupId,
                blobId: attachmentId,
                mime: spec.mime,
              );
          if (absoluteOwnedPath != durableAbsolutePath) {
            final target = File(absoluteOwnedPath);
            await target.parent.create(recursive: true);
            await File(durableAbsolutePath).copy(absoluteOwnedPath);
          }
          return uploaded.copyWith(
            id: attachmentId,
            messageId: messageId,
            mime: spec.mime,
            size: uploaded.size > 0 ? uploaded.size : sourceSize,
            mediaType: MediaAttachment.mediaTypeFromMime(spec.mime),
            durationMs: durationMs ?? uploaded.durationMs,
            localPath: mediaFileManager.relativePathForAttachment(
              contactPeerId: groupId,
              blobId: attachmentId,
              mime: spec.mime,
            ),
            waveform: waveform ?? uploaded.waveform,
            downloadStatus: 'done',
            uploadRetryCount: expectedAttachment.uploadRetryCount,
            downloadRetryCount: expectedAttachment.downloadRetryCount,
            contentHash: uploaded.contentHash ?? contentHash,
            ownerLane: MediaOwnerLane.group,
          );
        },
      );
      final attachment = completed?.completedAttachment;
      if (attachment == null ||
          completed!.outcome is! UploadMediaSucceeded ||
          attachment.id != attachmentId ||
          attachment.messageId != messageId ||
          attachment.downloadStatus != 'done') {
        throw StateError(
          'group-media ${spec.kind} foreground completion failed',
        );
      }
      uploads[spec.kind] = (uploads[spec.kind] ?? 0) + 1;

      final result = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        groupId: groupId,
        text: '',
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        senderDeviceId: senderTransport,
        senderTransportPeerId: senderTransport,
        messageId: messageId,
        logicalDeliveryId: messageId,
        timestamp: now,
        mediaAttachments: <MediaAttachment>[attachment],
        mediaAttachmentRepo: mediaAttachmentRepository,
        inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepository,
      );
      if (result.$2?.id != messageId ||
          !const <SendGroupMessageResult>{
            SendGroupMessageResult.success,
            SendGroupMessageResult.successNoPeers,
          }.contains(result.$1)) {
        final disposition = groupMediaReliabilityPublicationDisposition(
          result: result.$1,
          message: result.$2,
          expectedMessageId: messageId,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MEDIA_RELIABILITY_PUBLICATION_REJECTED',
          details: {'disposition': disposition},
        );
        // The endpoint host polls its result file and immediately begins
        // cleanup. Keep this debug-only failure path alive for one logcat
        // collection interval so the causal GROUP_SEND_MSG_TIMING event and
        // this closed-domain disposition are retained before process stop.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        throw StateError(
          'group-media ${spec.kind} $disposition publication failed',
        );
      }
      publications[spec.kind] = (publications[spec.kind] ?? 0) + 1;
      try {
        await mediaFileManager.deletePendingUploadDir(messageId);
      } catch (_) {}
    }
  } finally {
    if (audioRecorderService.isRecording) {
      await audioRecorderService.cancel();
    }
    for (final source in transientSources) {
      if (await source.exists()) await source.delete();
    }
    if (await fixtureDirectory.exists()) {
      for (final entry in fixtureDirectory.listSync().whereType<File>()) {
        if (entry.path.contains('$runId-')) await entry.delete();
      }
    }
    mediaUploadInFlightTracker.release(uploadLease);
  }
  return <String, Object?>{
    'accountPeerId': identity.peerId,
    'transportPeerId': senderTransport,
    'receiverAccountPeerId': receiverAccountPeerId,
    'receiverTransportPeerId': receiverTransportPeerId,
    'allowedPeers': allowedPeers,
    'uploadsPerBlob': uploads,
    'publicationsPerMessage': publications,
  };
}

String groupMediaReliabilityPublicationDisposition({
  required SendGroupMessageResult result,
  required GroupMessage? message,
  required String expectedMessageId,
}) {
  if (result != SendGroupMessageResult.error) return result.name;
  if (message == null) return 'error_no_message';
  if (message.id != expectedMessageId) return 'error_wrong_message';
  return switch (message.status) {
    'sending' => 'error_sending',
    'failed' => 'error_failed',
    'pending' => 'error_pending',
    GroupMessage.statusQueuedOffline => 'error_queued_offline',
    'sent' => 'error_sent',
    _ => 'error_other',
  };
}

Future<String?> _waitForLocalTransportPeerId(P2PService p2pService) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    final peerId = p2pService.currentState.peerId?.trim();
    if (peerId != null && peerId.isNotEmpty) return peerId;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final peerId = p2pService.currentState.peerId?.trim();
  return peerId == null || peerId.isEmpty ? null : peerId;
}

Future<void> _ensureExactGroupTopicJoined({
  required Bridge bridge,
  required GroupRepository groupRepository,
  required String groupId,
  required List<GroupMember> members,
  required GroupMediaReliabilityConfigBuilder groupConfigBuilder,
}) async {
  final group = await groupRepository.getGroup(groupId);
  final key = await groupRepository.getLatestKey(groupId);
  if (group == null || key == null) {
    throw StateError('group-media exact topic lacks persisted authority');
  }
  await callGroupJoinWithConfig(
    bridge,
    groupId: groupId,
    groupConfig: groupConfigBuilder(group, members),
    groupKey: key.encryptedKey,
    keyEpoch: key.keyGeneration,
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_MEDIA_RELIABILITY_EXACT_TOPIC_READY',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'keyEpoch': key.keyGeneration,
    },
  );
}

Future<Map<String, Object?>> probeGroupMediaReliabilityRoleDatabase({
  required String role,
  required String runId,
  required String transportPeerId,
  required Map<String, String> messageIds,
  required Map<String, String> attachmentIds,
  required Database database,
  required MediaAttachmentRepository mediaAttachmentRepository,
}) async {
  final cipherRows = await database.rawQuery('PRAGMA cipher_version');
  final userVersionRows = await database.rawQuery('PRAGMA user_version');
  final cipherVersion = cipherRows.single.values.single;
  final userVersion = userVersionRows.single.values.single;
  if (cipherVersion is! String ||
      cipherVersion.trim().isEmpty ||
      transportPeerId.trim().isEmpty ||
      userVersion != currentIdentityDatabaseVersion) {
    throw StateError('group-media role SQLCipher facts rejected');
  }
  final rows = <Map<String, Object?>>[];
  if (messageIds.isEmpty && attachmentIds.isEmpty) {
    return <String, Object?>{
      'role_db_path': '$role/group-media.sqlite',
      'database_path_sha256': groupMediaReliabilityDatabasePathFingerprint(
        runId: runId,
        transportPeerId: transportPeerId,
        databasePath: database.path,
      ),
      'cipher_version': cipherVersion,
      'user_version': userVersion,
      'rows': rows,
    };
  }
  if (messageIds.keys.toSet().length != 3 ||
      attachmentIds.keys.toSet().length != 3) {
    throw StateError('group-media role SQLCipher tuple is incomplete');
  }
  for (final kind in const <String>['jpeg', 'mp4', 'voice']) {
    final messageId = messageIds[kind]!;
    final exact = (await mediaAttachmentRepository.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    )).where((attachment) => attachment.id == attachmentIds[kind]).toList();
    if (exact.length != 1 || exact.single.downloadStatus != 'done') {
      throw StateError('group-media $role $kind row did not settle exactly');
    }
    final attachment = exact.single;
    rows.add(<String, Object?>{
      'run_id': runId,
      'media_kind': kind,
      'message_id': attachment.messageId,
      'blob_id': attachment.id,
      'status': attachment.downloadStatus,
      'upload_retry_count': attachment.uploadRetryCount ?? 0,
      'download_retry_count': attachment.downloadRetryCount ?? 0,
    });
  }
  return <String, Object?>{
    'role_db_path': '$role/group-media.sqlite',
    'database_path_sha256': groupMediaReliabilityDatabasePathFingerprint(
      runId: runId,
      transportPeerId: transportPeerId,
      databasePath: database.path,
    ),
    'cipher_version': cipherVersion,
    'user_version': userVersion,
    'rows': rows,
  };
}

Future<List<GroupMember>> _waitForReceiverTransportRoster({
  required GroupRepository groupRepository,
  required P2PService p2pService,
  required String groupId,
  required String receiverAccountPeerId,
  required String receiverTransportPeerId,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final members = await groupRepository.getMembers(groupId);
    final receiver = members
        .where((member) => member.peerId == receiverAccountPeerId)
        .toList();
    if (receiver.length == 1 &&
        receiver.single.activeDevicesWithLegacyFallback().any(
          (device) => device.transportPeerId == receiverTransportPeerId,
        )) {
      return members;
    }
    await p2pService.performImmediateHealthCheck();
    await p2pService.drainOfflineInbox();
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError('receiver active transport roster did not converge');
}
