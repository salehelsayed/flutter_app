import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/group_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/group_media_blob_custody.dart';
import 'package:flutter_app/features/groups/application/prepared_group_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';

import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e.dart';
import 'package:flutter_app/core/debug/group_media_reliability_authority_target.dart';
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
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
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

/// Debug fixture observation around the unchanged strict native upload leaf.
/// The response and thrown error remain owned by the canonical coordinator.
Future<Map<String, dynamic>> callGroupMediaReliabilityObservedUpload({
  required Bridge bridge,
  required String custodyBlobId,
  required String recipientPeerId,
  required String ciphertextPath,
  required String contentHash,
  required int ciphertextSize,
  required void Function(bool? responseOk, String? errorCode) onResponse,
}) async {
  final response = await callStrictGroupMediaBlobUpload(
    bridge: bridge,
    custodyBlobId: custodyBlobId,
    recipientPeerId: recipientPeerId,
    ciphertextPath: ciphertextPath,
    contentHash: contentHash,
    ciphertextSize: ciphertextSize,
  );
  try {
    final ok = response['ok'];
    onResponse(
      ok is bool ? ok : null,
      ok == false
          ? groupMediaReliabilityClosedUploadErrorCode(response['errorCode'])
          : null,
    );
  } on Object {
    // Diagnostic failure cannot change the native response or cause a retry.
  }
  return response;
}

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

/// Read-only observation through the same admission resolver as production.
/// A strict result therefore includes verified, reconciled, current-epoch
/// authority; this fixture never manufactures a genesis or replaces a resolver.
Future<Map<String, Object?>> probeGroupMediaReliabilityAuthority({
  required String groupId,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository,
  bool requireSettled = false,
  GroupMediaReliabilityAuthorityTarget? expectedAuthority,
  Duration settleTimeout = const Duration(seconds: 30),
}) async {
  if (expectedAuthority != null &&
      (!requireSettled || !expectedAuthority.isForGroup(groupId))) {
    throw const FormatException('group-media authority target rejected');
  }
  final elapsed = Stopwatch()..start();
  void requireWithinDeadline() {
    if (elapsed.elapsed >= settleTimeout) {
      throw const GroupMediaReliabilitySenderFailure('authority_settlement');
    }
  }

  do {
    final identity = await identityRepository.loadIdentity();
    requireWithinDeadline();
    final transport = p2pService.currentState.peerId?.trim();
    final key = await groupRepository.getLatestKey(groupId);
    requireWithinDeadline();
    final members = await groupRepository.getMembers(groupId);
    requireWithinDeadline();
    if (identity == null ||
        transport == null ||
        transport.isEmpty ||
        key == null ||
        key.keyGeneration <= 0 ||
        members.length != 2) {
      throw const GroupMediaReliabilitySenderFailure('authority_admission');
    }
    final admission = await prepareGroupContentAuthoringAdmission(
      groupRepo: groupRepository,
      groupId: groupId,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderDeviceId: transport,
      senderTransportPeerId: transport,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepository,
    );
    requireWithinDeadline();
    final snapshot = admission.snapshot;
    final authority = snapshot?.context.authorityVersion;
    if (!requireSettled ||
        (admission.kind == GroupContentAuthoringResolutionKind.strict &&
            snapshot != null &&
            authority != null &&
            snapshot.recipientPeerIds.length == 1)) {
      final exactMembers = snapshot?.members ?? members;
      final sortedMembers = exactMembers.toList()
        ..sort((a, b) => a.peerId.compareTo(b.peerId));
      final roles = sortedMembers.map((member) {
        final devices = member.devices.toList()
          ..sort((a, b) => a.deviceId.compareTo(b.deviceId));
        return <String, Object?>{
          'account': member.peerId,
          'role': member.role.toValue(),
          'devices': devices.map((device) => device.toJson()).toList(),
        };
      }).toList();
      String digest(String value) =>
          sha256.convert(utf8.encode(value)).toString();
      final observation = <String, Object?>{
        'schema': 'mknoon.group-media-authority.v1',
        'groupIdSha256': digest(groupId),
        'accountPeerIdSha256': digest(identity.peerId),
        'transportPeerIdSha256': digest(transport),
        'memberRolesSha256': digest(jsonEncode(roles)),
        'keyEpoch': snapshot?.key.keyGeneration ?? key.keyGeneration,
        'admission': admission.kind.name,
        'authoritySha256': authority == null
            ? null
            : digest(
                jsonEncode([
                  authority.eventId,
                  authority.eventAt.toUtc().toIso8601String(),
                  authority.keyEpoch,
                ]),
              ),
        'authorityEventAt': authority?.eventAt.toUtc().toIso8601String(),
        'recipientTransportSha256':
            snapshot?.recipientPeerIds.map(digest).toList() ?? <String>[],
      };
      if (expectedAuthority == null ||
          expectedAuthority.matchesObservation(observation)) {
        return observation;
      }
    }
    if (elapsed.elapsed >= settleTimeout) break;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  } while (true);
  throw const GroupMediaReliabilitySenderFailure('authority_settlement');
}

/// A genuine creator key refresh establishes protected authority for this
/// disposable distinct-device group, preserving its membership and roles.
Future<Map<String, Object?>> refreshGroupMediaReliabilitySenderAuthority({
  required String groupId,
  required String receiverAccountPeerId,
  required String receiverTransportPeerId,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository,
}) async {
  final identity = await identityRepository.loadIdentity();
  final transport = await _waitForLocalTransportPeerId(p2pService);
  final members = await _waitForReceiverTransportRoster(
    groupRepository: groupRepository,
    p2pService: p2pService,
    groupId: groupId,
    receiverAccountPeerId: receiverAccountPeerId,
    receiverTransportPeerId: receiverTransportPeerId,
  );
  if (identity == null ||
      transport == null ||
      !hasProtectedGroupAuthorityAdapter ||
      !groupMediaReliabilityAuthorityMatches(
        mode: GroupMediaReliabilityAuthorityMode.distinctAccountAndTransport,
        localAccountPeerId: identity.peerId,
        localTransportPeerId: transport,
        remoteAccountPeerId: receiverAccountPeerId,
        remoteTransportPeerId: receiverTransportPeerId,
        allowedPeers: groupMediaAllowedPeersForMembers(members),
      )) {
    throw const GroupMediaReliabilitySenderFailure('authority_rotation');
  }
  final before = await probeGroupMediaReliabilityAuthority(
    groupId: groupId,
    p2pService: p2pService,
    identityRepository: identityRepository,
    groupRepository: groupRepository,
    inviteDeliveryAttemptRepository: inviteDeliveryAttemptRepository,
  );
  // The baseline probe can await a roster/authority read. Never combine a new
  // account's receipt with signing material captured before that await.
  final currentIdentity = await identityRepository.loadIdentity();
  final currentTransport = p2pService.currentState.peerId?.trim();
  String digest(String value) => sha256.convert(utf8.encode(value)).toString();
  if (currentIdentity != identity ||
      currentTransport != transport ||
      before['accountPeerIdSha256'] != digest(identity.peerId) ||
      before['transportPeerIdSha256'] != digest(transport)) {
    throw const GroupMediaReliabilitySenderFailure('authority_rotation');
  }
  final rotation = await rotateAndDistributeGroupKey(
    bridge: bridge,
    groupRepo: groupRepository,
    groupId: groupId,
    selfPeerId: identity.peerId,
    senderPublicKey: identity.publicKey,
    senderPrivateKey: identity.privateKey,
    senderUsername: identity.username,
    sourceDeviceId: transport,
    sendP2PMessage: p2pService.sendMessage,
    storeP2PMessageInInbox: (peerId, message) =>
        p2pService.storeInInbox(peerId, message),
  );
  if (!rotation.rotated ||
      !rotation.fullyDistributed ||
      rotation.distributedDeviceCount != 1 ||
      rotation.key!.keyGeneration != (before['keyEpoch']! as int) + 1) {
    throw const GroupMediaReliabilitySenderFailure('authority_rotation');
  }
  final after = await probeGroupMediaReliabilityAuthority(
    groupId: groupId,
    p2pService: p2pService,
    identityRepository: identityRepository,
    groupRepository: groupRepository,
    inviteDeliveryAttemptRepository: inviteDeliveryAttemptRepository,
    requireSettled: true,
  );
  if (before['memberRolesSha256'] != after['memberRolesSha256'] ||
      before['accountPeerIdSha256'] != after['accountPeerIdSha256'] ||
      before['transportPeerIdSha256'] != after['transportPeerIdSha256'] ||
      after['keyEpoch'] != rotation.key!.keyGeneration) {
    throw const GroupMediaReliabilitySenderFailure('authority_membership');
  }
  return <String, Object?>{
    'before': before,
    'after': after,
    'previousEpoch': before['keyEpoch'],
    'currentEpoch': after['keyEpoch'],
    'distributedDeviceCount': rotation.distributedDeviceCount,
    'deferredPeerCount': rotation.deferredPeerIds.length,
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

  final admission = await prepareGroupContentAuthoringAdmission(
    groupRepo: groupRepository,
    groupId: groupId,
    senderPeerId: identity.peerId,
    senderPublicKey: identity.publicKey,
    senderDeviceId: senderTransport,
    senderTransportPeerId: senderTransport,
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepository,
  );
  final strict = admission.kind == GroupContentAuthoringResolutionKind.strict;
  if (!strict &&
      !(admission.kind ==
              GroupContentAuthoringResolutionKind.legacyUninitialized &&
          authorityMode ==
              GroupMediaReliabilityAuthorityMode.accountBoundLegacy)) {
    throw const GroupMediaReliabilitySenderFailure('authority_admission');
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
  final strictCustody = <String, Object?>{};
  final transientSources = <File>[];
  final uploadLease = mediaUploadInFlightTracker.tryClaimAll(
    attachmentIds.values,
    source: MediaUploadTriggerSource.foreground,
  );
  if (uploadLease == null) {
    throw StateError('group-media fixture attachment lease was denied');
  }
  var senderStage = 'fixture_material';
  String? senderKind;
  try {
    for (final spec in specs) {
      senderKind = spec.kind;
      senderStage = 'fixture_material';
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
        status: strict ? GroupMessage.statusQueuedOffline : 'sending',
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

      if (strict) {
        // The canonical producer owns staging and publication. Keep the source
        // outside pending_uploads so fixture cleanup cannot erase its local copy.
        final ownedPath = await mediaFileManager.localPathForAttachment(
          contactPeerId: groupId,
          blobId: attachmentId,
          mime: spec.mime,
        );
        await File(ownedPath).parent.create(recursive: true);
        if (ownedPath != durableAbsolutePath) {
          await File(durableAbsolutePath).copy(ownedPath);
        }
        senderStage = 'strict_preparation';
        bool? uploadResponseOk;
        String? uploadErrorCode;
        final prepared =
            await PreparedGroupMediaBlobCustodyCoordinator(
              artifactStore: GroupMediaBlobArtifactStore(),
              strictUpload:
                  ({
                    required bridge,
                    required custodyBlobId,
                    required recipientPeerId,
                    required ciphertextPath,
                    required contentHash,
                    required ciphertextSize,
                  }) => callGroupMediaReliabilityObservedUpload(
                    bridge: bridge,
                    custodyBlobId: custodyBlobId,
                    recipientPeerId: recipientPeerId,
                    ciphertextPath: ciphertextPath,
                    contentHash: contentHash,
                    ciphertextSize: ciphertextSize,
                    onResponse: (ok, code) {
                      uploadResponseOk = ok;
                      uploadErrorCode = code;
                    },
                  ),
            ).prepareAndUploadFresh(
              bridge: bridge,
              groupRepository: groupRepository,
              mediaAttachmentRepository: mediaAttachmentRepository,
              identityPeerId: identity.peerId,
              senderPublicKey: identity.publicKey,
              senderDeviceId: senderTransport,
              senderTransportPeerId: senderTransport,
              parent: expectedParent,
              sources: [
                PreparedGroupMediaBlobSource(
                  attachment: expectedAttachment.copyWith(
                    localPath: mediaFileManager.relativePathForAttachment(
                      contactPeerId: groupId,
                      blobId: attachmentId,
                      mime: spec.mime,
                    ),
                  ),
                  plaintextPath: ownedPath,
                ),
              ],
              inviteDeliveryAttemptRepository: inviteDeliveryAttemptRepository,
            );
        if (!prepared.isComplete) {
          throw GroupMediaReliabilitySenderFailure(
            'strict_preparation',
            kind: spec.kind,
            preparationState: prepared.state.name,
            preparationHasDurableAuthority: prepared.hasDurableAuthority,
            preparationUploadResponseOk: uploadResponseOk,
            preparationUploadErrorCode: uploadErrorCode,
          );
        }
        senderStage = 'strict_custody_join';
        final manifest = prepared.preparedManifest!.manifest;
        final commitment = manifest.attachments.single;
        final attachment = prepared.attachments.single;
        final fingerprint = computeGroupMediaBlobCustodyFingerprint(
          groupId: groupId,
          messageId: messageId,
          attachmentId: attachmentId,
          custodyBlobId: commitment.custodyBlobId,
          contentHash: commitment.ciphertextSha256,
          ciphertextSize: commitment.ciphertextSize,
          recipientPeerIds: manifest.recipientPeerIds,
        );
        final rows =
            await (mediaAttachmentRepository as GroupMediaBlobCustodyRepository)
                .loadGroupMediaBlobCustodyForMessage(
                  groupId: groupId,
                  messageId: messageId,
                );
        final exact = rows
            .where((row) => row.attachmentId == attachmentId)
            .toList();
        if (manifest.groupId != groupId ||
            manifest.messageId != messageId ||
            commitment.attachmentId != attachmentId ||
            commitment.custodyBlobId !=
                deterministicGroupMediaCustodyBlobId(
                  groupId: groupId,
                  messageId: messageId,
                  attachmentId: attachmentId,
                ) ||
            manifest.recipientPeerIds.length != 1 ||
            manifest.recipientPeerIds.single != receiverTransportPeerId ||
            attachment.groupMediaBlobCustodyFingerprint != fingerprint ||
            exact.length != 1 ||
            exact.single.recipientPeerId != receiverTransportPeerId ||
            exact.single.state != DirectMediaBlobCustodyState.outgoingStored ||
            exact.single.custodyBlobId != commitment.custodyBlobId ||
            exact.single.contentHash != commitment.ciphertextSha256 ||
            exact.single.ciphertextSize != commitment.ciphertextSize ||
            exact.single.expiresAtMs != commitment.targets.single.expiresAtMs) {
          throw GroupMediaReliabilitySenderFailure(
            'strict_custody_join',
            kind: spec.kind,
          );
        }
        strictCustody[spec.kind] = <String, Object?>{
          'manifest_sha256': manifest.fingerprintSha256,
          'custody_fingerprint': fingerprint,
          'custody_blob_id_sha256': sha256
              .convert(utf8.encode(commitment.custodyBlobId))
              .toString(),
          'ciphertext_sha256': commitment.ciphertextSha256,
          'ciphertext_size': commitment.ciphertextSize,
          'recipient_count': 1,
          'recipient_transport_sha256': sha256
              .convert(utf8.encode(receiverTransportPeerId))
              .toString(),
          'expires_at_ms': commitment.targets.single.expiresAtMs,
        };
        // Stored custody is observed before canonical content completion,
        // which legitimately moves the rows into cleanup or retires them.
        senderStage = 'strict_publication';
        final (sent, message) = await sendGroupMessage(
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
          timestamp: prepared.parent!.timestamp,
          mediaAttachments: prepared.attachments,
          mediaAttachmentRepo: mediaAttachmentRepository,
          inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepository,
          preparedGroupMediaManifest: prepared.preparedManifest,
        );
        final terminal = await groupMessageRepository.getMessage(messageId);
        final durable =
            (await mediaAttachmentRepository.getAttachmentsForMessage(
              messageId,
              owner: MediaOwnerLane.group,
            )).where((a) => a.id == attachmentId).toList();
        if (sent != SendGroupMessageResult.success ||
            message?.id != messageId ||
            terminal?.id != messageId ||
            terminal?.groupId != groupId ||
            terminal?.senderPeerId != identity.peerId ||
            terminal?.isIncoming != false ||
            terminal?.status != 'sent' ||
            terminal?.inboxStored != true ||
            terminal?.inboxRetryPayload != null ||
            terminal?.wireEnvelope != null ||
            durable.length != 1 ||
            durable.single.messageId != messageId ||
            durable.single.ownerLane != MediaOwnerLane.group ||
            durable.single.downloadStatus != 'upload_pending' ||
            durable.single.contentHash != commitment.ciphertextSha256 ||
            durable.single.groupMediaBlobCustodyFingerprint != fingerprint) {
          throw GroupMediaReliabilitySenderFailure(
            'strict_publication',
            kind: spec.kind,
          );
        }
        uploads[spec.kind] = 1;
        publications[spec.kind] = 1;
        await mediaFileManager.deletePendingUploadDir(messageId);
        continue;
      }

      // The exact parent exists before the shared production leaf persists and
      // SQL-default-reloads the attachment. The process-wide lease above owns
      // every supplied blob ID before either row becomes visible.
      await groupMessageRepository.saveMessage(expectedParent);
      senderStage = 'legacy_upload';
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

      senderStage = 'legacy_publication';
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
  } on GroupMediaReliabilitySenderFailure {
    rethrow;
  } on Object {
    throw GroupMediaReliabilitySenderFailure(senderStage, kind: senderKind);
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
    if (strict) 'strictMediaCustody': strictCustody,
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
    if (exact.length != 1 ||
        exact.single.messageId != messageId ||
        exact.single.ownerLane != MediaOwnerLane.group) {
      throw StateError('group-media $role $kind row did not settle exactly');
    }
    final attachment = exact.single;
    Map<String, Object?>? publication;
    if (role == 'sender' &&
        attachment.groupMediaBlobCustodyFingerprint != null) {
      final parents = await database.rawQuery(
        'SELECT id, group_id, sender_peer_id, is_incoming, status, '
        'inbox_stored, wire_envelope, inbox_retry_payload '
        'FROM group_messages WHERE id = ?',
        <Object?>[messageId],
      );
      final parent = parents.length == 1 ? parents.single : null;
      final group = parent?['group_id'];
      final sender = parent?['sender_peer_id'];
      final digest = RegExp(r'^[0-9a-f]{64}$');
      if (attachment.downloadStatus != 'upload_pending' ||
          !digest.hasMatch(attachment.groupMediaBlobCustodyFingerprint!) ||
          attachment.contentHash == null ||
          !digest.hasMatch(attachment.contentHash!) ||
          parent?['id'] != messageId ||
          group is! String ||
          group.trim().isEmpty ||
          sender is! String ||
          sender.trim().isEmpty ||
          parent?['is_incoming'] != 0 ||
          parent?['status'] != 'sent' ||
          parent?['inbox_stored'] != 1 ||
          parent?['wire_envelope'] != null ||
          parent?['inbox_retry_payload'] != null) {
        throw StateError(
          'group-media strict sender SQL publication is incomplete',
        );
      }
      String scoped(String value) =>
          sha256.convert(utf8.encode('$runId\u0000$value')).toString();
      publication = <String, Object?>{
        'message_id': parent!['id'],
        'group_sha256': scoped(group),
        'sender_account_sha256': scoped(sender),
        'attachment_content_sha256': attachment.contentHash,
        'status': parent['status'],
        'inbox_stored': parent['inbox_stored'] == 1,
        'is_incoming': parent['is_incoming'] == 1,
        'wire_envelope_present': parent['wire_envelope'] != null,
        'retry_payload_present': parent['inbox_retry_payload'] != null,
      };
    } else if (attachment.downloadStatus != 'done') {
      throw StateError('group-media $role $kind row did not settle exactly');
    }
    rows.add(<String, Object?>{
      'run_id': runId,
      'media_kind': kind,
      'message_id': attachment.messageId,
      'blob_id': attachment.id,
      'status': attachment.downloadStatus,
      'upload_retry_count': attachment.uploadRetryCount ?? 0,
      'download_retry_count': attachment.downloadRetryCount ?? 0,
      'custody_fingerprint': ?attachment.groupMediaBlobCustodyFingerprint,
      'strict_publication': ?publication,
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
