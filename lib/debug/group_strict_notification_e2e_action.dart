import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/debug/group_strict_notification_e2e.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

Future<Map<String, Object?>> runGroupStrictNotificationE2EAction({
  required Map<String, dynamic> config,
  required Database database,
  required Bridge bridge,
  required P2PService p2pService,
  required AckOrExpiryInboxStore inboxStore,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
}) async {
  final request = GroupStrictNotificationE2ERequest.fromConfig(config);
  final group = await _exactGroup(groupRepository, request.groupName);
  final identity = await identityRepository.loadIdentity();
  final transportPeerId = p2pService.currentState.peerId?.trim();
  if (identity == null ||
      transportPeerId == null ||
      transportPeerId.isEmpty ||
      transportPeerId != identity.peerId) {
    throw StateError('strict fixture requires an ordinary primary transport');
  }

  final base = <String, Object?>{
    'schema': groupStrictNotificationResultSchema,
    'transport_action': groupStrictNotificationE2EAction,
    'scenario': groupStrictNotificationScenario,
    'stepId': request.stepId,
    'phase': request.phase,
    'runId': request.runId,
    'nonce': request.nonce,
    'status': 'complete',
    'success': true,
  };

  switch (request.phase) {
    case groupStrictNotificationAuthorPhase:
      final key = await groupRepository.getLatestKey(group.id);
      final self = await groupRepository.getMember(group.id, identity.peerId);
      if (key == null || self == null || key.keyGeneration <= 0) {
        throw StateError('strict fixture group authority is incomplete');
      }
      final now = DateTime.now().toUtc();
      final currentDevice =
          self.findDeviceByTransportPeerId(
            transportPeerId,
            allowLegacyFallback: true,
          ) ??
          self.legacyDeviceIdentity;
      if (currentDevice == null ||
          currentDevice.deviceSigningPublicKey != identity.publicKey) {
        throw StateError('strict fixture current device is not authoritative');
      }
      final scope = sha256
          .convert(utf8.encode('${request.runId}:${identity.peerId}'))
          .toString()
          .substring(0, 24);
      final revokedDevice = GroupMemberDeviceIdentity(
        deviceId: 'plan393-revoked-$scope',
        transportPeerId: 'plan393-revoked-transport-$scope',
        deviceSigningPublicKey: identity.publicKey,
        mlKemPublicKey: identity.mlKemPublicKey,
        status: GroupMemberDeviceStatus.revoked,
        revokedAt: now,
      );
      final devices = <GroupMemberDeviceIdentity>[
        if (self.devices.isEmpty) currentDevice else ...self.devices,
        if (!self.devices.any(
          (device) => device.deviceId == revokedDevice.deviceId,
        ))
          revokedDevice,
      ];
      final updatedSelf = self.copyWith(devices: devices);
      await groupRepository.saveMember(updatedSelf);
      final members = (await groupRepository.getMembers(group.id))
          .map(
            (member) => member.peerId == identity.peerId ? updatedSelf : member,
          )
          .toList(growable: false);
      final eventId = 'plan393-strict-genesis-$scope';
      var proof = AuthenticatedGroupAuthorityProof(
        eventId: eventId,
        groupId: group.id,
        eventAt: now,
        keyEpoch: key.keyGeneration,
        control: 'bootstrap_genesis',
        actorAccountPeerId: identity.peerId,
        actorAccountPublicKey: identity.publicKey,
        senderTransportPeerId: transportPeerId,
        senderTransportPublicKey: identity.publicKey,
        authorityData: <String, Object?>{
          'group': group.toMap(),
          'members': members.map((member) => member.toMap()).toList(),
          'fixture': 'plan393_revoked_device_genesis',
        },
        signature: '',
      );
      final signed = await callSignPayload(
        bridge: bridge,
        dataToSign: proof.canonicalSignedPayload(),
        privateKey: identity.privateKey,
      );
      final signature = signed['signature'] as String?;
      if (signed['ok'] != true || signature == null || signature.isEmpty) {
        throw StateError('strict fixture authority signing failed');
      }
      proof = proof.withSignature(signature);
      await _appendGenesis(database, proof);
      _installStrictFixtureAuthoringResolver(
        proof: proof,
        p2pService: p2pService,
        inboxStore: inboxStore,
        identityRepository: identityRepository,
        groupRepository: groupRepository,
      );
      final digest = _proofDigest(proof);
      return <String, Object?>{
        ...base,
        'observation': <String, Object?>{
          'authorityDigest': digest,
          'authorityEventAt': fixedGroupAuthorityUtc(proof.eventAt),
          'authorityEventIdSha256': sha256
              .convert(utf8.encode(proof.eventId))
              .toString(),
          'keyEpoch': proof.keyEpoch,
          'revokedHistoricalDevice': true,
          'strictAuthoringActivated': true,
          'authorityTransfer': <String, Object?>{
            'schema': groupStrictNotificationTransferSchema,
            'runId': request.runId,
            'proof': proof.toMap(),
          },
        },
      };
    case groupStrictNotificationInstallPhase:
      final transfer = request.authorityTransfer!;
      if (transfer['runId'] != request.runId) {
        throw const FormatException('strict authority run binding rejected');
      }
      final proof =
          parseGroupStrictAuthorityTransfer<AuthenticatedGroupAuthorityProof>(
            transfer,
            parseProof: AuthenticatedGroupAuthorityProof.tryParse,
          );
      if (proof.groupId != group.id ||
          proof.keyEpoch !=
              (await groupRepository.getLatestKey(group.id))?.keyGeneration ||
          !proof.eventId.startsWith('plan393-strict-genesis-') ||
          proof.authorityData['fixture'] != 'plan393_revoked_device_genesis') {
        throw StateError('strict fixture authority transfer is not current');
      }
      final verified = await callVerifyPayload(
        bridge: bridge,
        publicKey: proof.actorAccountPublicKey,
        data: proof.canonicalSignedPayload(),
        signature: proof.signature,
      );
      if (!verified) {
        throw StateError('strict fixture authority signature rejected');
      }
      final snapshotGroup = _groupFromProof(proof);
      final members = _membersFromProof(proof);
      final actor = members
          .where((member) => member.peerId == proof.actorAccountPeerId)
          .toList(growable: false);
      if (snapshotGroup.id != group.id ||
          actor.length != 1 ||
          actor.single.publicKey != proof.actorAccountPublicKey ||
          !actor.single.hasInitializedDeviceAuthority ||
          actor.single.activeDevices.any(
            (device) => device.transportPeerId.startsWith('plan393-revoked-'),
          )) {
        throw StateError('strict fixture authority snapshot rejected');
      }
      await groupRepository.saveGroup(snapshotGroup);
      for (final member in members) {
        await groupRepository.saveMember(member);
      }
      await _appendGenesis(database, proof);
      _installStrictFixtureAuthoringResolver(
        proof: proof,
        p2pService: p2pService,
        inboxStore: inboxStore,
        identityRepository: identityRepository,
        groupRepository: groupRepository,
      );
      return <String, Object?>{
        ...base,
        'observation': <String, Object?>{
          'authorityDigest': _proofDigest(proof),
          'authorityEventAt': fixedGroupAuthorityUtc(proof.eventAt),
          'authorityEventIdSha256': sha256
              .convert(utf8.encode(proof.eventId))
              .toString(),
          'keyEpoch': proof.keyEpoch,
          'installed': true,
          'strictAuthoringActivated': true,
        },
      };
  }
  throw StateError('unreachable strict authority phase');
}

/// Activates the already-authenticated strict authority only inside the
/// disposable Plan-393 E2E process.
///
/// The shared `android.production_fcm` profile deliberately retains its exact
/// production defines, where new linked/multi-device authoring is default-off.
/// The device fixture nevertheless needs to author strict rows after it has
/// constructed and verified the signed authority above. Installing the
/// repository-scoped resolver here keeps that test authority out of normal
/// bootstrap and fails closed if the current identity, transport, group, key,
/// or active device no longer matches the verified proof.
void _installStrictFixtureAuthoringResolver({
  required AuthenticatedGroupAuthorityProof proof,
  required P2PService p2pService,
  required AckOrExpiryInboxStore inboxStore,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
}) {
  setGroupContentAuthoringResolver(groupRepository, ({
    required String groupId,
    required String senderPeerId,
    required String senderPublicKey,
    String? senderDeviceId,
    String? senderTransportPeerId,
  }) async {
    // `actorAccountPeerId` identifies the member who signed this authority
    // transition; it is not an author allow-list. The authenticated snapshot
    // covers every member/device below, so a different active member remains
    // eligible when its local identity and unique transport binding match.
    if (groupId != proof.groupId) {
      return const (
        kind: GroupContentAuthoringResolutionKind.refuse,
        context: null,
      );
    }
    final identity = await identityRepository.loadIdentity();
    final transportPeerId = p2pService.currentState.peerId?.trim();
    final key = await groupRepository.getLatestKey(groupId);
    final member = await groupRepository.getMember(groupId, senderPeerId);
    if (identity == null ||
        identity.peerId != senderPeerId ||
        identity.publicKey != senderPublicKey ||
        transportPeerId == null ||
        transportPeerId.isEmpty ||
        key?.keyGeneration != proof.keyEpoch ||
        member == null) {
      return const (
        kind: GroupContentAuthoringResolutionKind.refuse,
        context: null,
      );
    }
    final devices = member.activeDevices
        .where(
          (device) =>
              device.transportPeerId == transportPeerId &&
              device.deviceSigningPublicKey == senderPublicKey,
        )
        .toList(growable: false);
    if (devices.length != 1 ||
        (senderDeviceId?.trim().isNotEmpty == true &&
            senderDeviceId!.trim() != devices.single.deviceId) ||
        (senderTransportPeerId?.trim().isNotEmpty == true &&
            senderTransportPeerId!.trim() != transportPeerId)) {
      return const (
        kind: GroupContentAuthoringResolutionKind.refuse,
        context: null,
      );
    }
    final device = devices.single;
    return (
      kind: GroupContentAuthoringResolutionKind.strict,
      context: GroupContentAuthoringContext(
        directLinkedDeviceSelector: const DirectLinkedDeviceSelector.enabled(),
        multiDeviceSyncEnabled: true,
        authorityVersion: GroupContentAuthorityVersion(
          eventAt: proof.eventAt,
          eventId: proof.eventId,
          keyEpoch: proof.keyEpoch,
        ),
        inboxStore: inboxStore,
        authoringDeviceId: device.deviceId,
        authoringTransportPeerId: device.transportPeerId,
        authoringPublicKey: device.deviceSigningPublicKey,
      ),
    );
  });
}

Future<GroupModel> _exactGroup(
  GroupRepository repository,
  String groupName,
) async {
  final matches = (await repository.getAllGroups())
      .where((group) => group.name == groupName && !group.isDissolved)
      .toList(growable: false);
  if (matches.length != 1) {
    throw StateError('strict fixture exact group did not settle');
  }
  return matches.single;
}

GroupModel _groupFromProof(AuthenticatedGroupAuthorityProof proof) {
  final raw = proof.authorityData['group'];
  if (raw is! Map) throw const FormatException('strict group snapshot missing');
  return GroupModel.fromMap(Map<String, dynamic>.from(raw));
}

List<GroupMember> _membersFromProof(AuthenticatedGroupAuthorityProof proof) {
  final raw = proof.authorityData['members'];
  if (raw is! List || raw.isEmpty) {
    throw const FormatException('strict member snapshot missing');
  }
  return raw
      .whereType<Map>()
      .map((row) => GroupMember.fromMap(Map<String, dynamic>.from(row)))
      .toList(growable: false);
}

Future<void> _appendGenesis(
  Database database,
  AuthenticatedGroupAuthorityProof proof,
) async {
  await dbAppendGroupEventLogEntry(
    database,
    groupId: proof.groupId,
    eventType: AuthenticatedGroupAuthorityPhase.genesis.eventType,
    sourcePeerId: proof.actorAccountPeerId,
    sourceEventId: authenticatedGroupAuthoritySourceEventId(
      AuthenticatedGroupAuthorityPhase.genesis,
      proof.eventId,
    ),
    sourceTimestamp: fixedGroupAuthorityUtc(proof.eventAt),
    payload: authenticatedGroupAuthorityFactPayload(proof),
  );
}

String _proofDigest(AuthenticatedGroupAuthorityProof proof) => sha256
    .convert(
      utf8.encode('${proof.canonicalSignedPayload()}\n${proof.signature}'),
    )
    .toString();
