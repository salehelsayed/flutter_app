import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

enum GroupMediaIosProofReadiness {
  /// Sender/setup and foreground observation must prove a live inbound relay
  /// reservation plus successful send and inbox operations.
  fullRelayCustody,

  /// Signed identity export is local, but it still binds the live transport
  /// identity produced by the started node.
  identity,

  /// Fresh-process receiver recovery pulls already-durable inbox/media state.
  /// A successful inbox proof is the causal outgoing relay requirement; an
  /// inbound circuit reservation is unrelated to that recovery operation.
  receiveRecovery,
}

/// Applies the causal readiness axes for each physical-iOS proof operation.
///
/// Full sender/setup work requires both relay custody directions. Identity
/// export is local but binds a live transport, while fresh-process recovery
/// requires the successful inbox axis it actually consumes.
bool groupMediaIosProofEndpointReady(
  NodeState state, {
  GroupMediaIosProofReadiness requirement =
      GroupMediaIosProofReadiness.fullRelayCustody,
}) {
  final transportPeerId = state.peerId?.trim();
  if (!state.isStarted || transportPeerId == null || transportPeerId.isEmpty) {
    return false;
  }
  return switch (requirement) {
    GroupMediaIosProofReadiness.fullRelayCustody =>
      state.relayReady && state.usabilityReady,
    GroupMediaIosProofReadiness.identity => true,
    GroupMediaIosProofReadiness.receiveRecovery => state.inboxCapabilityReady,
  };
}

Future<Map<String, Object?>> setupGroupMediaIosBackgroundSender({
  required String receiverAccountPeerId,
  required String receiverTransportPeerId,
  required String groupName,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required ContactRepository contactRepository,
  required GroupRepository groupRepository,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository,
}) async {
  if (!RegExp(
    r'^P269-GROUP-[AB]-[A-Za-z0-9._:-]{1,128}$',
  ).hasMatch(groupName)) {
    throw const FormatException('physical-iOS group name rejected');
  }
  final identity = await identityRepository.loadIdentity();
  final receiver = await contactRepository.getContact(receiverAccountPeerId);
  final transport = p2pService.currentState.peerId?.trim();
  if (identity == null ||
      receiver == null ||
      receiver.mlKemPublicKey?.trim().isNotEmpty != true ||
      transport == null ||
      transport.isEmpty ||
      identity.peerId == transport ||
      receiverAccountPeerId == receiverTransportPeerId) {
    throw StateError(
      'physical-iOS sender lacks distinct account/transport authority',
    );
  }
  final result = await createGroupWithMembers(
    bridge: bridge,
    groupRepo: groupRepository,
    p2pService: p2pService,
    identity: identity,
    selectedContacts: [receiver],
    type: GroupType.chat,
    name: groupName,
    selectedContactDeviceBindings: <String, GroupMemberDeviceIdentity>{
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
  );
  if (result.membersAdded != 1 ||
      result.invitesSent != 1 ||
      result.membershipSyncRolledBack ||
      result.group.name != groupName) {
    throw StateError('physical-iOS group/invite setup did not settle');
  }
  return <String, Object?>{
    'groupId': result.group.id,
    'accountPeerId': identity.peerId,
    'transportPeerId': transport,
  };
}

String groupMediaIosBackgroundParentMarker(String runId, String phase) =>
    'P269-PARENT-${phase.toUpperCase()}-$runId';

/// Sends one real JPEG-backed ordinary group message for the physical-iOS
/// background proof. The marker is regular encrypted message text, so its one
/// visible Orbit preview remains causally bound to the exact media row.
Future<Map<String, Object?>> sendGroupMediaIosBackgroundFixture({
  required String runId,
  required String phase,
  required String groupId,
  required String messageId,
  required String attachmentId,
  required String marker,
  required String receiverAccountPeerId,
  required String receiverTransportPeerId,
  required Directory fixtureDirectory,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  required GroupMessageRepository groupMessageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required MediaFileManager mediaFileManager,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository,
}) async {
  if (!const <String>{'a', 'b'}.contains(phase) ||
      marker != 'P269-${phase.toUpperCase()}-$runId') {
    throw const FormatException('physical-iOS media marker tuple rejected');
  }
  final identity = await identityRepository.loadIdentity();
  final senderTransport = p2pService.currentState.peerId?.trim();
  if (identity == null ||
      senderTransport == null ||
      senderTransport.isEmpty ||
      identity.peerId == senderTransport ||
      receiverAccountPeerId == receiverTransportPeerId) {
    throw StateError('physical-iOS sender identity discriminator failed');
  }
  final members = await _waitForReceiverTransportRoster(
    groupRepository: groupRepository,
    p2pService: p2pService,
    groupId: groupId,
    receiverAccountPeerId: receiverAccountPeerId,
    receiverTransportPeerId: receiverTransportPeerId,
  );
  final allowedPeers = groupMediaAllowedPeersForMembers(members);
  if (!isExactGroupMediaIosBackgroundTransportAcl(
    allowedPeers: allowedPeers,
    senderAccountPeerId: identity.peerId,
    senderTransportPeerId: senderTransport,
    receiverAccountPeerId: receiverAccountPeerId,
    receiverTransportPeerId: receiverTransportPeerId,
  )) {
    throw StateError('physical-iOS media ACL is not the exact transport set');
  }

  await fixtureDirectory.create(recursive: true);
  final source = File('${fixtureDirectory.path}/$runId-$phase.jpeg');
  final parentMarker = groupMediaIosBackgroundParentMarker(runId, phase);
  try {
    final jpeg = await rootBundle.load(
      'integration_test/fixtures/received_media_egress_fixture.jpg',
    );
    await source.writeAsBytes(jpeg.buffer.asUint8List(), flush: true);
    final outcome = await uploadMedia(
      bridge: bridge,
      localFilePath: source.path,
      mime: 'image/jpeg',
      recipientPeerId: groupId,
      mediaFileManager: mediaFileManager,
      allowedPeers: allowedPeers,
      blobId: attachmentId,
      deleteSourceWhenDone: true,
    );
    final uploaded = outcome.attachmentOrNull;
    if (uploaded == null || uploaded.id != attachmentId) {
      throw StateError('physical-iOS JPEG upload failed');
    }
    final attachment = uploaded.copyWith(
      id: attachmentId,
      messageId: messageId,
      ownerLane: MediaOwnerLane.group,
      downloadStatus: 'done',
      uploadRetryCount: 0,
      downloadRetryCount: 0,
    );
    final sent = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepository,
      msgRepo: groupMessageRepository,
      groupId: groupId,
      text: parentMarker,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: identity.privateKey,
      senderUsername: identity.username,
      senderDeviceId: senderTransport,
      senderTransportPeerId: senderTransport,
      messageId: messageId,
      logicalDeliveryId: messageId,
      mediaAttachments: <MediaAttachment>[attachment],
      mediaAttachmentRepo: mediaAttachmentRepository,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepository,
    );
    if (sent.$1 != SendGroupMessageResult.success ||
        sent.$2?.id != messageId ||
        sent.$2?.text != parentMarker) {
      throw StateError('physical-iOS media publication failed');
    }
    return <String, Object?>{
      'messagePublished': true,
      'uploadCount': 1,
      'publicationCount': 1,
      'allowedPeerCount': 2,
      'parentMarkerSha256': _sha256(parentMarker),
      'accountPeerId': identity.peerId,
      'transportPeerId': senderTransport,
    };
  } finally {
    if (await source.exists()) await source.delete();
  }
}

@visibleForTesting
bool isExactGroupMediaIosBackgroundTransportAcl({
  required List<String> allowedPeers,
  required String senderAccountPeerId,
  required String senderTransportPeerId,
  required String receiverAccountPeerId,
  required String receiverTransportPeerId,
}) =>
    allowedPeers.length == 2 &&
    allowedPeers.toSet().length == 2 &&
    allowedPeers.toSet().containsAll(<String>{
      senderTransportPeerId,
      receiverTransportPeerId,
    }) &&
    !allowedPeers.contains(senderAccountPeerId) &&
    !allowedPeers.contains(receiverAccountPeerId);

/// Opens a second connection to the same production SQLCipher database and
/// returns only hash-bound facts about one media row. The raw key and paths
/// never leave this function.
Future<Map<String, Object?>> reopenGroupMediaIosBackgroundDatabase({
  required String runId,
  required String phase,
  required String messageId,
  required String attachmentId,
  required String expectedParentMarker,
  required Database liveDatabase,
  required SecureKeyStore secureKeyStore,
}) async {
  if (!const <String>{'a', 'b'}.contains(phase) ||
      expectedParentMarker !=
          groupMediaIosBackgroundParentMarker(runId, phase)) {
    throw const FormatException('physical-iOS database tuple rejected');
  }
  final stored = await secureKeyStore.read('db_encryption_key');
  if (stored == null) throw StateError('production SQLCipher key is absent');
  final keyRecord = parseCipherKeyRecord(stored);
  if (keyRecord.mode != CipherKeyMode.raw ||
      !isValid256BitHexKey(keyRecord.hex)) {
    throw StateError('production SQLCipher key mode is not raw');
  }
  Database? reopened;
  try {
    reopened = await openDatabase(
      liveDatabase.path,
      password: "x'${keyRecord.hex}'",
      singleInstance: false,
      readOnly: true,
    );
    if (identical(reopened, liveDatabase)) {
      throw StateError('production SQLCipher database did not reopen');
    }
    final cipherRows = await reopened.rawQuery('PRAGMA cipher_version');
    final versionRows = await reopened.rawQuery('PRAGMA user_version');
    final cipherVersion = cipherRows.single.values.single;
    final userVersion = versionRows.single.values.single;
    if (cipherVersion is! String ||
        cipherVersion.trim().isEmpty ||
        userVersion != 104) {
      throw StateError('reopened production SQLCipher facts rejected');
    }
    final concreteCipherVersion = RegExp(
      r'[0-9]+\.[0-9]+\.[0-9]+',
    ).firstMatch(cipherVersion)?.group(0);
    if (concreteCipherVersion == null) {
      throw StateError('reopened SQLCipher version is not concrete');
    }
    final rows = await reopened.rawQuery(
      'SELECT gm.id AS message_id, gm.text AS marker, '
      'ma.id AS attachment_id, ma.download_status, '
      'ma.download_retry_count '
      'FROM group_messages gm '
      'JOIN media_attachments ma ON ma.message_id = gm.id '
      'WHERE gm.id = ? AND ma.id = ? AND ma.owner_lane = ?',
      <Object?>[messageId, attachmentId, MediaOwnerLane.group.dbValue],
    );
    if (rows.length != 1 ||
        rows.single['marker'] != expectedParentMarker ||
        !const <String>{
          'downloading',
          'done',
        }.contains(rows.single['download_status'])) {
      throw StateError('reopened production SQLCipher media row rejected');
    }
    return <String, Object?>{
      'databaseReopened': true,
      'databasePathSha256': _sha256(liveDatabase.path),
      'cipherVersion': 'SQLCipher $concreteCipherVersion',
      'userVersion': userVersion,
      'rowCount': 1,
      'messageSha256': _sha256(messageId),
      'attachmentSha256': _sha256(attachmentId),
      'markerSha256': _sha256(expectedParentMarker),
      'durableStatus': rows.single['download_status'],
      'downloadRetryCount':
          (rows.single['download_retry_count'] as num?)?.toInt() ?? 0,
    };
  } finally {
    await reopened?.close();
  }
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
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError('physical-iOS receiver roster did not converge');
}

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();
