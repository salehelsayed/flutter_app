import 'dart:convert';

import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/linked_group_bootstrap_service.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/protected_group_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_sibling_device_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

const protectedGroupAuthorityPurpose = 'protected_group_authority_v1';
const protectedGroupAuthorityVersion = 1;
const protectedGroupAuthoritySigningDomain =
    'mknoon/protected-group-authority/v1';
const protectedGroupAuthorityLifetime = Duration(days: 30);

enum ProtectedGroupAuthorityControl {
  deviceAnnounce('device_announce'),
  memberAdd('member_added'),
  memberConfig('group_config_updated'),
  memberRole('member_role_updated'),
  memberRemove('member_removed'),
  groupDissolve('group_dissolved'),
  groupKeyUpdate('group_key_update');

  const ProtectedGroupAuthorityControl(this.wireValue);
  final String wireValue;

  static ProtectedGroupAuthorityControl? fromWire(String value) {
    for (final candidate in values) {
      if (candidate.wireValue == value) return candidate;
    }
    return null;
  }
}

enum ProtectedGroupAuthorityHandleResult {
  applied,
  duplicate,
  terminalRejected,
  retryable,
  prerequisiteWaiting,
}

enum ProtectedGroupAuthorityApplyResult {
  applied,
  duplicate,
  rejected,
  retryable,
}

class ProtectedGroupAuthorityPreparation {
  const ProtectedGroupAuthorityPreparation({
    required this.groupId,
    required this.rows,
    this.authorityProof,
    this.control,
    this.replayData,
  });

  final String groupId;
  final List<GroupPendingBroadcast> rows;
  final AuthenticatedGroupAuthorityProof? authorityProof;
  final ProtectedGroupAuthorityControl? control;
  final Map<String, dynamic>? replayData;
  bool get hasRecipients => rows.isNotEmpty;
  bool get hasAuthenticatedAuthority =>
      authorityProof != null && control != null && replayData != null;
}

class ProtectedGroupAuthorityPrepareRequest {
  const ProtectedGroupAuthorityPrepareRequest({
    required this.groupId,
    required this.transitionId,
    required this.control,
    required this.replayData,
    required this.actorAccountPeerId,
    required this.actorAccountPublicKey,
    required this.actorAccountPrivateKey,
    required this.senderDevice,
    required this.frozenRecipients,
    this.deliveryRecipients,
    this.deliveryReplayDataByTransportPeerId,
    this.sharedAuthorityProof,
    this.resumePreparedSurvivors = false,
  });

  final String groupId;
  final String transitionId;
  final ProtectedGroupAuthorityControl control;
  final Map<String, dynamic> replayData;
  final String actorAccountPeerId;
  final String actorAccountPublicKey;
  final String actorAccountPrivateKey;
  final GroupMemberDeviceIdentity senderDevice;
  final List<GroupMemberDeviceIdentity> frozenRecipients;
  final List<GroupMemberDeviceIdentity>? deliveryRecipients;
  final Map<String, Map<String, dynamic>>? deliveryReplayDataByTransportPeerId;
  final AuthenticatedGroupAuthorityProof? sharedAuthorityProof;
  final bool resumePreparedSurvivors;
}

typedef PrepareProtectedGroupAuthority =
    Future<ProtectedGroupAuthorityPreparation?> Function(
      ProtectedGroupAuthorityPrepareRequest request,
    );
typedef ActivateProtectedGroupAuthority =
    Future<bool> Function(
      ProtectedGroupAuthorityPreparation preparation, {
      required bool requireAllCustody,
    });
typedef CancelProtectedGroupAuthority =
    Future<bool> Function(ProtectedGroupAuthorityPreparation preparation);

PrepareProtectedGroupAuthority? _prepareProtectedAuthority;
ActivateProtectedGroupAuthority? _activateProtectedAuthority;
CancelProtectedGroupAuthority? _cancelProtectedAuthority;

bool get hasProtectedGroupAuthorityAdapter =>
    _prepareProtectedAuthority != null &&
    _activateProtectedAuthority != null &&
    _cancelProtectedAuthority != null;

void setProtectedGroupAuthorityAdapter({
  PrepareProtectedGroupAuthority? prepare,
  ActivateProtectedGroupAuthority? activate,
  CancelProtectedGroupAuthority? cancel,
}) {
  _prepareProtectedAuthority = prepare;
  _activateProtectedAuthority = activate;
  _cancelProtectedAuthority = cancel;
}

Future<bool> cancelProtectedGroupAuthority(
  ProtectedGroupAuthorityPreparation? preparation,
) async {
  if (preparation == null || !preparation.hasRecipients) return true;
  final cancel = _cancelProtectedAuthority;
  if (cancel == null) return false;
  return cancel(preparation);
}

Future<ProtectedGroupAuthorityPreparation?> prepareProtectedGroupAuthority(
  ProtectedGroupAuthorityPrepareRequest request,
) async {
  final prepare = _prepareProtectedAuthority;
  if (prepare == null) return null;
  return prepare(request);
}

Future<bool> activateProtectedGroupAuthority(
  ProtectedGroupAuthorityPreparation? preparation, {
  required bool requireAllCustody,
}) async {
  if (preparation == null) return true;
  if (!preparation.hasRecipients && !preparation.hasAuthenticatedAuthority) {
    return true;
  }
  final activate = _activateProtectedAuthority;
  if (activate == null) return false;
  return activate(preparation, requireAllCustody: requireAllCustody);
}

GroupMemberDeviceIdentity? resolveProtectedGroupSenderDevice({
  required GroupMember actor,
  required String senderPublicKey,
  String? senderDeviceId,
  String? senderTransportPeerId,
}) {
  final deviceId = senderDeviceId?.trim();
  final transportPeerId = senderTransportPeerId?.trim();
  final publicKey = senderPublicKey.trim();
  for (final device in actor.activeDevicesWithLegacyFallback()) {
    final matchesDevice =
        deviceId == null || deviceId.isEmpty || device.deviceId == deviceId;
    final matchesTransport =
        transportPeerId == null ||
        transportPeerId.isEmpty ||
        device.transportPeerId == transportPeerId;
    if (matchesDevice &&
        matchesTransport &&
        device.deviceSigningPublicKey == publicKey) {
      return device;
    }
  }
  return null;
}

List<GroupMemberDeviceIdentity> freezeProtectedGroupPhysicalRecipients(
  Iterable<GroupMember> members,
) => members
    .expand((member) => member.activeDevicesWithLegacyFallback())
    .where((device) => device.isActive)
    .toList(growable: false);

/// Whether this group has crossed the Plan-363 physical-device authority
/// boundary. An all-legacy roster keeps the incumbent group transport byte-for-
/// byte; once a distinct physical device is persisted, protected recovery is
/// state-owned and remains eligible even if feature selectors later roll back.
bool hasProtectedGroupPhysicalAuthority(Iterable<GroupMember> members) {
  for (final member in members) {
    for (final device in member.devices) {
      if (device.deviceId != member.peerId ||
          device.transportPeerId != member.peerId) {
        return true;
      }
    }
  }
  return false;
}

typedef ApplyProtectedGroupAuthorityReplay =
    Future<ProtectedGroupAuthorityApplyResult> Function(
      ProtectedGroupAuthorityControl control,
      Map<String, dynamic> replayData,
    );

class ProtectedGroupAuthorityPayload {
  const ProtectedGroupAuthorityPayload({
    required this.transitionId,
    required this.groupId,
    required this.issuedAt,
    required this.expiresAt,
    required this.actorAccountPeerId,
    required this.actorAccountPublicKey,
    required this.senderTransportPeerId,
    required this.senderTransportPublicKey,
    required this.recipientTransportPeerId,
    required this.frozenRecipientPeerIds,
    required this.control,
    required this.replayData,
    required this.authorityProof,
    required this.signature,
  });

  final String transitionId;
  final String groupId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String actorAccountPeerId;
  final String actorAccountPublicKey;
  final String senderTransportPeerId;
  final String senderTransportPublicKey;
  final String recipientTransportPeerId;
  final List<String> frozenRecipientPeerIds;
  final ProtectedGroupAuthorityControl control;
  final Map<String, dynamic> replayData;
  final AuthenticatedGroupAuthorityProof authorityProof;
  final String signature;

  Map<String, Object?> unsignedBody() => <String, Object?>{
    'purpose': protectedGroupAuthorityPurpose,
    'version': protectedGroupAuthorityVersion,
    'transitionId': transitionId,
    'groupId': groupId,
    'issuedAt': issuedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'actorAccountPeerId': actorAccountPeerId,
    'actorAccountPublicKey': actorAccountPublicKey,
    'senderTransportPeerId': senderTransportPeerId,
    'senderTransportPublicKey': senderTransportPublicKey,
    'recipientTransportPeerId': recipientTransportPeerId,
    'frozenRecipientPeerIds': frozenRecipientPeerIds.toList()..sort(),
    'control': control.wireValue,
    'replayData': replayData,
    'authorityProof': authorityProof.toMap(),
  };

  String canonicalSignedPayload() =>
      '$protectedGroupAuthoritySigningDomain\n'
      '${canonicalLinkedGroupAuthorityJson(unsignedBody())}';

  String toInnerJson() => jsonEncode(<String, Object?>{
    'body': unsignedBody(),
    'signature': signature,
  });

  ProtectedGroupAuthorityPayload withSignature(String value) =>
      ProtectedGroupAuthorityPayload(
        transitionId: transitionId,
        groupId: groupId,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        actorAccountPeerId: actorAccountPeerId,
        actorAccountPublicKey: actorAccountPublicKey,
        senderTransportPeerId: senderTransportPeerId,
        senderTransportPublicKey: senderTransportPublicKey,
        recipientTransportPeerId: recipientTransportPeerId,
        frozenRecipientPeerIds: frozenRecipientPeerIds,
        control: control,
        replayData: replayData,
        authorityProof: authorityProof,
        signature: value,
      );

  static ProtectedGroupAuthorityPayload? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 2 ||
          !decoded.containsKey('body') ||
          !decoded.containsKey('signature')) {
        return null;
      }
      final signature = _strict(decoded['signature']);
      final body = decoded['body'];
      if (signature == null ||
          body is! Map<String, dynamic> ||
          !_exactKeys(body, _authorityBodyKeys) ||
          body['purpose'] != protectedGroupAuthorityPurpose ||
          body['version'] != protectedGroupAuthorityVersion) {
        return null;
      }
      final transitionId = _strict(body['transitionId']);
      final groupId = _strict(body['groupId']);
      final actorPeerId = _strict(body['actorAccountPeerId']);
      final actorPublicKey = _strict(body['actorAccountPublicKey']);
      final senderPeerId = _strict(body['senderTransportPeerId']);
      final senderPublicKey = _strict(body['senderTransportPublicKey']);
      final recipientPeerId = _strict(body['recipientTransportPeerId']);
      final controlRaw = _strict(body['control']);
      final control = controlRaw == null
          ? null
          : ProtectedGroupAuthorityControl.fromWire(controlRaw);
      final issuedAt = _utc(body['issuedAt']);
      final expiresAt = _utc(body['expiresAt']);
      final frozenRaw = body['frozenRecipientPeerIds'];
      final replayRaw = body['replayData'];
      final authorityProof = AuthenticatedGroupAuthorityProof.tryParse(
        body['authorityProof'],
      );
      if (transitionId == null ||
          groupId == null ||
          actorPeerId == null ||
          actorPublicKey == null ||
          senderPeerId == null ||
          senderPublicKey == null ||
          recipientPeerId == null ||
          control == null ||
          issuedAt == null ||
          expiresAt == null ||
          !expiresAt.isAfter(issuedAt) ||
          expiresAt.difference(issuedAt) > protectedGroupAuthorityLifetime ||
          frozenRaw is! List ||
          frozenRaw.isEmpty ||
          replayRaw is! Map<String, dynamic> ||
          authorityProof == null) {
        return null;
      }
      final frozen = <String>[];
      for (final value in frozenRaw) {
        final peerId = _strict(value);
        if (peerId == null || frozen.contains(peerId)) return null;
        frozen.add(peerId);
      }
      final sorted = frozen.toList()..sort();
      if (!_sameStrings(frozen, sorted) || !frozen.contains(recipientPeerId)) {
        return null;
      }
      return ProtectedGroupAuthorityPayload(
        transitionId: transitionId,
        groupId: groupId,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        actorAccountPeerId: actorPeerId,
        actorAccountPublicKey: actorPublicKey,
        senderTransportPeerId: senderPeerId,
        senderTransportPublicKey: senderPublicKey,
        recipientTransportPeerId: recipientPeerId,
        frozenRecipientPeerIds: frozen,
        control: control,
        replayData: Map<String, dynamic>.from(replayRaw),
        authorityProof: authorityProof,
        signature: signature,
      );
    } catch (_) {
      return null;
    }
  }
}

const _authorityBodyKeys = <String>{
  'purpose',
  'version',
  'transitionId',
  'groupId',
  'issuedAt',
  'expiresAt',
  'actorAccountPeerId',
  'actorAccountPublicKey',
  'senderTransportPeerId',
  'senderTransportPublicKey',
  'recipientTransportPeerId',
  'frozenRecipientPeerIds',
  'control',
  'replayData',
  'authorityProof',
};

/// Builds one immutable target-qualified row per frozen physical recipient.
/// Callers persist the returned rows before committing their local transition.
Future<ProtectedGroupAuthorityPreparation> buildProtectedGroupAuthorityRows({
  required String groupId,
  required String transitionId,
  required ProtectedGroupAuthorityControl control,
  required Map<String, dynamic> replayData,
  required int keyEpoch,
  required String actorAccountPeerId,
  required String actorAccountPublicKey,
  required String actorAccountPrivateKey,
  required GroupMemberDeviceIdentity senderDevice,
  required List<GroupMemberDeviceIdentity> frozenRecipients,
  List<GroupMemberDeviceIdentity>? deliveryRecipients,
  Map<String, Map<String, dynamic>>? deliveryReplayDataByTransportPeerId,
  AuthenticatedGroupAuthorityProof? sharedAuthorityProof,
  required LinkedGroupSign callSign,
  required LinkedGroupEncrypt callEncrypt,
  DateTime Function()? now,
}) async {
  final frozen = frozenRecipients
      .where(
        (device) =>
            device.isActive &&
            device.transportPeerId != senderDevice.transportPeerId &&
            device.mlKemPublicKey?.trim().isNotEmpty == true,
      )
      .toList(growable: false);
  final acl = frozen.map((device) => device.transportPeerId).toSet().toList()
    ..sort();
  final deliveryPeerIds = deliveryRecipients
      ?.where((device) => device.isActive)
      .map((device) => device.transportPeerId)
      .toSet();
  final recipients = deliveryPeerIds == null
      ? frozen
      : frozen
            .where((device) => deliveryPeerIds.contains(device.transportPeerId))
            .toList(growable: false);
  if (groupId.trim().isEmpty ||
      transitionId.trim().isEmpty ||
      actorAccountPeerId.trim().isEmpty ||
      actorAccountPublicKey.trim().isEmpty ||
      actorAccountPrivateKey.trim().isEmpty ||
      senderDevice.transportPeerId.trim().isEmpty ||
      senderDevice.deviceSigningPublicKey.trim().isEmpty ||
      keyEpoch <= 0) {
    return ProtectedGroupAuthorityPreparation(
      groupId: groupId,
      rows: const <GroupPendingBroadcast>[],
    );
  }
  if (deliveryPeerIds != null && recipients.length != deliveryPeerIds.length) {
    return ProtectedGroupAuthorityPreparation(
      groupId: groupId,
      rows: const <GroupPendingBroadcast>[],
    );
  }
  final deliveryReplayData = deliveryReplayDataByTransportPeerId;
  if (deliveryReplayData != null &&
      (deliveryReplayData.length != recipients.length ||
          !deliveryReplayData.keys.toSet().containsAll(
            recipients.map((recipient) => recipient.transportPeerId),
          ))) {
    return ProtectedGroupAuthorityPreparation(
      groupId: groupId,
      rows: const <GroupPendingBroadcast>[],
    );
  }
  final instant = (now ?? DateTime.now)().toUtc();
  final eventAt = _utc(replayData['timestamp']);
  if (eventAt == null) {
    return ProtectedGroupAuthorityPreparation(
      groupId: groupId,
      rows: const <GroupPendingBroadcast>[],
    );
  }
  final unsignedAuthorityProof = AuthenticatedGroupAuthorityProof(
    eventId: transitionId,
    groupId: groupId,
    eventAt: eventAt,
    keyEpoch: keyEpoch,
    control: control.wireValue,
    actorAccountPeerId: actorAccountPeerId,
    actorAccountPublicKey: actorAccountPublicKey,
    senderTransportPeerId: senderDevice.transportPeerId,
    senderTransportPublicKey: senderDevice.deviceSigningPublicKey,
    authorityData: secretFreeProtectedAuthorityData(
      control: control.wireValue,
      replayData: replayData,
      frozenRecipientPeerIds: acl,
    ),
    signature: '',
  );
  late final AuthenticatedGroupAuthorityProof authorityProof;
  if (sharedAuthorityProof != null) {
    if (_strict(sharedAuthorityProof.signature) == null ||
        !sharedAuthorityProof.sameUnsigned(unsignedAuthorityProof)) {
      return ProtectedGroupAuthorityPreparation(
        groupId: groupId,
        rows: const <GroupPendingBroadcast>[],
      );
    }
    authorityProof = sharedAuthorityProof;
  } else {
    final proofSign = await callSign(
      unsignedAuthorityProof.canonicalSignedPayload(),
      actorAccountPrivateKey,
    );
    final proofSignature = _strict(proofSign['signature']);
    if (proofSign['ok'] != true || proofSignature == null) {
      return ProtectedGroupAuthorityPreparation(
        groupId: groupId,
        rows: const <GroupPendingBroadcast>[],
      );
    }
    authorityProof = unsignedAuthorityProof.withSignature(proofSignature);
  }
  final rows = <GroupPendingBroadcast>[];
  for (final recipient in recipients) {
    final recipientKey = recipient.mlKemPublicKey!.trim();
    final recipientReplayData =
        deliveryReplayData?[recipient.transportPeerId] ?? replayData;
    if (canonicalLinkedGroupAuthorityJson(
          secretFreeProtectedAuthorityData(
            control: control.wireValue,
            replayData: recipientReplayData,
            frozenRecipientPeerIds: acl,
          ),
        ) !=
        canonicalLinkedGroupAuthorityJson(authorityProof.authorityData)) {
      return ProtectedGroupAuthorityPreparation(
        groupId: groupId,
        rows: const <GroupPendingBroadcast>[],
      );
    }
    var payload = ProtectedGroupAuthorityPayload(
      transitionId: transitionId,
      groupId: groupId,
      issuedAt: instant,
      expiresAt: instant.add(protectedGroupAuthorityLifetime),
      actorAccountPeerId: actorAccountPeerId,
      actorAccountPublicKey: actorAccountPublicKey,
      senderTransportPeerId: senderDevice.transportPeerId,
      senderTransportPublicKey: senderDevice.deviceSigningPublicKey,
      recipientTransportPeerId: recipient.transportPeerId,
      frozenRecipientPeerIds: acl,
      control: control,
      replayData: recipientReplayData,
      authorityProof: authorityProof,
      signature: '',
    );
    final signed = await callSign(
      payload.canonicalSignedPayload(),
      actorAccountPrivateKey,
    );
    final signature = _strict(signed['signature']);
    if (signed['ok'] != true || signature == null) {
      return ProtectedGroupAuthorityPreparation(
        groupId: groupId,
        rows: const <GroupPendingBroadcast>[],
      );
    }
    payload = payload.withSignature(signature);
    final encrypted = await callEncrypt(
      recipientMlKemPublicKey: recipientKey,
      plaintext: payload.toInnerJson(),
    );
    final kem = _strict(encrypted['kem']);
    final ciphertext = _strict(encrypted['ciphertext']);
    final nonce = _strict(encrypted['nonce']);
    if (encrypted['ok'] != true ||
        kem == null ||
        ciphertext == null ||
        nonce == null) {
      return ProtectedGroupAuthorityPreparation(
        groupId: groupId,
        rows: const <GroupPendingBroadcast>[],
      );
    }
    final deliveryId = protectedGroupAuthorityDeliveryId(
      control.wireValue,
      transitionId,
      recipient.transportPeerId,
    );
    if (deliveryId.length > protectedGroupLogicalIdMaxLength ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(deliveryId)) {
      return ProtectedGroupAuthorityPreparation(
        groupId: groupId,
        rows: const <GroupPendingBroadcast>[],
      );
    }
    final outer = ProtectedGroupEnvelope(
      type: protectedGroupAuthorityEnvelopeType,
      id: deliveryId,
      senderPeerId: senderDevice.transportPeerId,
      recipientPeerId: recipient.transportPeerId,
      kem: kem,
      ciphertext: ciphertext,
      nonce: nonce,
    ).toJson();
    rows.add(
      GroupPendingBroadcast(
        id: 'protected-authority:$deliveryId',
        groupId: groupId,
        kind: groupPendingBroadcastKindProtectedAuthority,
        sysText: outer,
        recipientPeerIds: <String>[recipient.transportPeerId],
        eventAt: instant,
        sourceMessageId: deliveryId,
        createdAt: instant,
        updatedAt: instant,
      ),
    );
  }
  return ProtectedGroupAuthorityPreparation(
    groupId: groupId,
    rows: List<GroupPendingBroadcast>.unmodifiable(rows),
    authorityProof: authorityProof,
    control: control,
    replayData: Map<String, dynamic>.unmodifiable(replayData),
  );
}

/// Verifies that a durable PREPARED proof is the exact stable authority version
/// requested by a sender retry. This compares only account-signed,
/// secret-free bytes; target-specific encrypted deliveries remain outside the
/// proof and are recovered from their immutable pending rows.
bool protectedGroupAuthorityProofMatchesPrepareRequest({
  required AuthenticatedGroupAuthorityProof proof,
  required ProtectedGroupAuthorityPrepareRequest request,
  required int keyEpoch,
}) {
  final frozen = request.frozenRecipients
      .where(
        (device) =>
            device.isActive &&
            device.transportPeerId != request.senderDevice.transportPeerId &&
            device.mlKemPublicKey?.trim().isNotEmpty == true,
      )
      .toList(growable: false);
  final acl = frozen.map((device) => device.transportPeerId).toSet().toList()
    ..sort();
  final eventAt = _utc(request.replayData['timestamp']);
  if (eventAt == null || _strict(proof.signature) == null) return false;
  final unsigned = AuthenticatedGroupAuthorityProof(
    eventId: request.transitionId,
    groupId: request.groupId,
    eventAt: eventAt,
    keyEpoch: keyEpoch,
    control: request.control.wireValue,
    actorAccountPeerId: request.actorAccountPeerId,
    actorAccountPublicKey: request.actorAccountPublicKey,
    senderTransportPeerId: request.senderDevice.transportPeerId,
    senderTransportPublicKey: request.senderDevice.deviceSigningPublicKey,
    authorityData: secretFreeProtectedAuthorityData(
      control: request.control.wireValue,
      replayData: request.replayData,
      frozenRecipientPeerIds: acl,
    ),
    signature: '',
  );
  return proof.sameUnsigned(unsigned);
}

Future<bool> persistPreparedProtectedGroupAuthority({
  required GroupPendingBroadcastRepository repository,
  required ProtectedGroupAuthorityPreparation preparation,
}) async {
  final proof = preparation.authorityProof;
  if (!preparation.hasAuthenticatedAuthority || proof == null) return false;
  if (repository
      case final GroupPendingBroadcastProtectedBatchRepository batch) {
    return batch.enqueueProtectedBatch(
      preparation.rows,
      groupId: preparation.groupId,
      authorityPrepared: GroupPendingBroadcastAuthorityFact(
        sourcePeerId: proof.actorAccountPeerId,
        sourceEventId: authenticatedGroupAuthoritySourceEventId(
          AuthenticatedGroupAuthorityPhase.prepared,
          proof.eventId,
        ),
        sourceTimestamp: fixedGroupAuthorityUtc(proof.eventAt),
        payload: authenticatedGroupAuthorityFactPayload(proof),
      ),
    );
  }
  return false;
}

/// Receives only authenticated control authority. User-authored content types
/// are unrepresentable in [ProtectedGroupAuthorityControl].
Future<ProtectedGroupAuthorityHandleResult> handleProtectedGroupAuthority({
  required ChatMessage message,
  required String ownTransportPeerId,
  required String ownMlKemSecretKey,
  required GroupRepository groupRepository,
  required LinkedGroupDecrypt callDecrypt,
  required LinkedGroupVerify callVerify,
  required LoadAuthenticatedGroupAuthorityProof loadAuthorityProof,
  required AppendAuthenticatedGroupAuthorityProof appendAuthorityProof,
  required ApplyProtectedGroupAuthorityReplay applyReplay,
  DateTime Function()? now,
}) async {
  final recipientTransportPeerId = ownTransportPeerId.trim();
  if (recipientTransportPeerId.isEmpty) {
    return ProtectedGroupAuthorityHandleResult.terminalRejected;
  }
  final outer = ProtectedGroupEnvelope.tryParse(
    message.content,
    expectedType: protectedGroupAuthorityEnvelopeType,
  );
  if (outer == null ||
      outer.senderPeerId != message.from ||
      outer.recipientPeerId != message.to ||
      outer.recipientPeerId != recipientTransportPeerId) {
    return ProtectedGroupAuthorityHandleResult.terminalRejected;
  }
  try {
    final decrypted = await callDecrypt(
      ownMlKemSecretKey: ownMlKemSecretKey,
      kem: outer.kem,
      ciphertext: outer.ciphertext,
      nonce: outer.nonce,
    );
    final plaintext = decrypted['plaintext'];
    if (decrypted['ok'] != true || plaintext is! String) {
      return ProtectedGroupAuthorityHandleResult.terminalRejected;
    }
    final payload = ProtectedGroupAuthorityPayload.tryParse(plaintext);
    if (payload == null ||
        payload.recipientTransportPeerId != recipientTransportPeerId ||
        payload.senderTransportPeerId != outer.senderPeerId ||
        protectedGroupAuthorityDeliveryId(
              payload.control.wireValue,
              payload.transitionId,
              payload.recipientTransportPeerId,
            ) !=
            outer.id) {
      return ProtectedGroupAuthorityHandleResult.terminalRejected;
    }
    final proof = payload.authorityProof;
    final expectedEventAt = _utc(payload.replayData['timestamp']);
    final expectedAuthorityData = secretFreeProtectedAuthorityData(
      control: payload.control.wireValue,
      replayData: payload.replayData,
      frozenRecipientPeerIds: payload.frozenRecipientPeerIds,
    );
    final legacyAuthorityData =
        payload.control == ProtectedGroupAuthorityControl.groupKeyUpdate
        ? legacyTargetQualifiedKeyAuthorityData(payload.replayData)
        : secretFreeProtectedAuthorityData(
            control: payload.control.wireValue,
            replayData: payload.replayData,
          );
    final authorityDataMatches =
        canonicalLinkedGroupAuthorityJson(proof.authorityData) ==
            canonicalLinkedGroupAuthorityJson(expectedAuthorityData) ||
        canonicalLinkedGroupAuthorityJson(proof.authorityData) ==
            canonicalLinkedGroupAuthorityJson(legacyAuthorityData);
    final replayKeyEpoch = payload.replayData['keyGeneration'];
    if (expectedEventAt == null ||
        proof.eventId != payload.transitionId ||
        proof.groupId != payload.groupId ||
        proof.eventAt.toUtc() != expectedEventAt ||
        proof.control != payload.control.wireValue ||
        proof.actorAccountPeerId != payload.actorAccountPeerId ||
        proof.actorAccountPublicKey != payload.actorAccountPublicKey ||
        proof.senderTransportPeerId != payload.senderTransportPeerId ||
        proof.senderTransportPublicKey != payload.senderTransportPublicKey ||
        (payload.control == ProtectedGroupAuthorityControl.groupKeyUpdate &&
            replayKeyEpoch != proof.keyEpoch) ||
        !authorityDataMatches) {
      return ProtectedGroupAuthorityHandleResult.terminalRejected;
    }
    final instant = (now ?? DateTime.now)().toUtc();
    if (instant.isBefore(payload.issuedAt) ||
        !payload.expiresAt.isAfter(instant) ||
        !await callVerify(
          publicKey: payload.actorAccountPublicKey,
          data: payload.canonicalSignedPayload(),
          signature: payload.signature,
        ) ||
        !await callVerify(
          publicKey: proof.actorAccountPublicKey,
          data: proof.canonicalSignedPayload(),
          signature: proof.signature,
        )) {
      return ProtectedGroupAuthorityHandleResult.terminalRejected;
    }
    return await runGroupAuthorityPhase(
      groupId: payload.groupId,
      action: () async {
        final complete = await loadAuthorityProof(
          groupId: payload.groupId,
          phase: AuthenticatedGroupAuthorityPhase.complete,
          eventId: payload.transitionId,
        );
        if (complete != null) {
          return _sameAuthenticatedProof(complete, proof)
              ? ProtectedGroupAuthorityHandleResult.duplicate
              : ProtectedGroupAuthorityHandleResult.terminalRejected;
        }

        final prepared = await loadAuthorityProof(
          groupId: payload.groupId,
          phase: AuthenticatedGroupAuthorityPhase.prepared,
          eventId: payload.transitionId,
        );
        if (prepared != null && !_sameAuthenticatedProof(prepared, proof)) {
          return ProtectedGroupAuthorityHandleResult.terminalRejected;
        }
        if (prepared == null) {
          final group = await groupRepository.getGroup(payload.groupId);
          if (group == null) {
            return ProtectedGroupAuthorityHandleResult.prerequisiteWaiting;
          }
          final actor = await groupRepository.getMember(
            payload.groupId,
            payload.actorAccountPeerId,
          );
          if (actor == null ||
              actor.publicKey?.trim() != payload.actorAccountPublicKey ||
              !_authorizedSenderDevice(actor, payload)) {
            return ProtectedGroupAuthorityHandleResult.terminalRejected;
          }
          final currentKey = await groupRepository.getLatestKey(
            payload.groupId,
          );
          if (payload.control !=
                  ProtectedGroupAuthorityControl.groupKeyUpdate &&
              currentKey?.keyGeneration != proof.keyEpoch) {
            return ProtectedGroupAuthorityHandleResult.prerequisiteWaiting;
          }
          await appendAuthorityProof(
            phase: AuthenticatedGroupAuthorityPhase.prepared,
            proof: proof,
          );
        }

        final applied = await applyReplay(payload.control, payload.replayData);
        if (applied == ProtectedGroupAuthorityApplyResult.rejected) {
          return ProtectedGroupAuthorityHandleResult.terminalRejected;
        }
        if (applied == ProtectedGroupAuthorityApplyResult.retryable) {
          return ProtectedGroupAuthorityHandleResult.retryable;
        }
        await appendAuthorityProof(
          phase: AuthenticatedGroupAuthorityPhase.complete,
          proof: proof,
        );
        return applied == ProtectedGroupAuthorityApplyResult.applied
            ? ProtectedGroupAuthorityHandleResult.applied
            : ProtectedGroupAuthorityHandleResult.duplicate;
      },
    );
  } catch (_) {
    return ProtectedGroupAuthorityHandleResult.retryable;
  }
}

bool _sameAuthenticatedProof(
  AuthenticatedGroupAuthorityProof left,
  AuthenticatedGroupAuthorityProof right,
) => left.signature == right.signature && left.sameUnsigned(right);

/// Returns whether the durable local projection already matches the protected
/// replay's exact intended authority. `null` means the replay shape is not a
/// valid representation of that control and must be terminally rejected.
Future<bool?> protectedGroupAuthorityReplayConverged({
  required ProtectedGroupAuthorityControl control,
  required Map<String, dynamic> replayData,
  required GroupRepository groupRepository,
}) async {
  final groupId = _strict(replayData['groupId']);
  if (groupId == null) return null;
  if (control == ProtectedGroupAuthorityControl.groupKeyUpdate) {
    final generation = replayData['keyGeneration'];
    final encryptedKey = _strict(replayData['encryptedKey']);
    if (generation is! int || generation <= 0 || encryptedKey == null) {
      return null;
    }
    final stored = await groupRepository.getKeyByGeneration(
      groupId,
      generation,
    );
    return stored != null && stored.encryptedKey == encryptedKey;
  }

  final text = _strict(replayData['text']);
  if (text == null) return null;
  final Map<String, dynamic> payload;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) return null;
    payload = decoded;
  } catch (_) {
    return null;
  }
  final sys = _strict(payload['__sys']);
  if (sys == null) return null;
  switch (control) {
    case ProtectedGroupAuthorityControl.deviceAnnounce:
      if (sys != 'device_announce') return null;
      final senderId = _strict(replayData['senderId']);
      final announced = payload['announcedDevice'];
      if (senderId == null || announced is! Map<String, dynamic>) return null;
      final deviceId = _strict(announced['deviceId']);
      final transportPeerId = _strict(announced['transportPeerId']);
      final publicKey = _strict(announced['deviceSigningPublicKey']);
      if (deviceId == null || transportPeerId == null || publicKey == null) {
        return null;
      }
      final member = await groupRepository.getMember(groupId, senderId);
      final device = member?.findDeviceById(deviceId);
      return device != null &&
          device.transportPeerId == transportPeerId &&
          device.deviceSigningPublicKey == publicKey &&
          device.mlKemPublicKey == announced['mlKemPublicKey'] &&
          device.keyPackageId == announced['keyPackageId'];
    case ProtectedGroupAuthorityControl.memberAdd:
      if (sys != 'member_added' && sys != 'members_added') return null;
      final memberMaps = sys == 'member_added'
          ? <Object?>[payload['member']]
          : (payload['members'] is List
                ? List<Object?>.from(payload['members'] as List)
                : null);
      if (memberMaps == null || memberMaps.isEmpty) return null;
      for (final raw in memberMaps) {
        if (raw is! Map<String, dynamic>) return null;
        final peerId = _strict(raw['peerId']);
        if (peerId == null) return null;
        final stored = await groupRepository.getMember(groupId, peerId);
        if (stored == null ||
            canonicalLinkedGroupAuthorityJson(stored.toConfigJson()) !=
                canonicalLinkedGroupAuthorityJson(raw)) {
          return false;
        }
      }
      return true;
    case ProtectedGroupAuthorityControl.memberConfig:
      if (sys != 'group_config_updated') return null;
      final expected = payload['groupConfig'];
      if (expected is! Map<String, dynamic>) return null;
      final group = await groupRepository.getGroup(groupId);
      if (group == null) return false;
      final members = await groupRepository.getMembers(groupId);
      final actual = <String, Object?>{
        'group': group.toMap(),
        'members': members.map((member) => member.toMap()).toList(),
      };
      return canonicalLinkedGroupAuthorityJson(actual) ==
          canonicalLinkedGroupAuthorityJson(expected);
    case ProtectedGroupAuthorityControl.memberRole:
      if (sys != 'member_role_updated') return null;
      final raw = payload['member'];
      if (raw is! Map<String, dynamic>) return null;
      final peerId = _strict(raw['peerId']);
      if (peerId == null) return null;
      final stored = await groupRepository.getMember(groupId, peerId);
      return stored != null &&
          canonicalLinkedGroupAuthorityJson(stored.toConfigJson()) ==
              canonicalLinkedGroupAuthorityJson(raw);
    case ProtectedGroupAuthorityControl.memberRemove:
      if (sys != 'member_removed') return null;
      final raw = payload['member'];
      if (raw is! Map<String, dynamic>) return null;
      final peerId = _strict(raw['peerId']);
      if (peerId == null) return null;
      return await groupRepository.getMember(groupId, peerId) == null;
    case ProtectedGroupAuthorityControl.groupDissolve:
      if (sys != 'group_dissolved') return null;
      return (await groupRepository.getGroup(groupId))?.isDissolved == true;
    case ProtectedGroupAuthorityControl.groupKeyUpdate:
      throw StateError('handled above');
  }
}

/// Verifies that the local sender projection represented by a durable,
/// secret-free authority proof has committed. This is intentionally usable
/// after restart, when plaintext key material and the original preparation
/// object are no longer in memory.
Future<bool?> protectedGroupAuthorityProofConverged({
  required AuthenticatedGroupAuthorityProof proof,
  required GroupRepository groupRepository,
}) async {
  final control = ProtectedGroupAuthorityControl.fromWire(proof.control);
  if (control == null || proof.authorityData['groupId'] != proof.groupId) {
    return null;
  }
  if (control == ProtectedGroupAuthorityControl.groupKeyUpdate) {
    final generation = proof.authorityData['keyGeneration'];
    final encryptedKeyHash = _strict(proof.authorityData['encryptedKeyHash']);
    if (generation is! int || generation <= 0 || encryptedKeyHash == null) {
      return null;
    }
    final stored = await groupRepository.getKeyByGeneration(
      proof.groupId,
      generation,
    );
    return stored != null &&
        groupAuthoritySha256(stored.encryptedKey) == encryptedKeyHash;
  }
  return protectedGroupAuthorityReplayConverged(
    control: control,
    replayData: Map<String, dynamic>.from(proof.authorityData),
    groupRepository: groupRepository,
  );
}

bool sameAuthenticatedGroupAuthorityProof(
  AuthenticatedGroupAuthorityProof left,
  AuthenticatedGroupAuthorityProof right,
) => left.sameUnsigned(right) && left.signature == right.signature;

/// Repairs sender-side complete history from an authenticated prepared fact
/// only after the durable local projection converges. Callers serialize this
/// through [runGroupAuthorityPhaseIfNeeded].
Future<bool> ensureLocalProtectedGroupAuthorityComplete({
  required String groupId,
  required String eventId,
  required ProtectedGroupAuthorityControl expectedControl,
  AuthenticatedGroupAuthorityProof? expectedProof,
  required GroupRepository groupRepository,
  required LoadAuthenticatedGroupAuthorityProof loadAuthorityProof,
  required AppendAuthenticatedGroupAuthorityProof appendAuthorityProof,
}) async {
  final complete = await loadAuthorityProof(
    groupId: groupId,
    phase: AuthenticatedGroupAuthorityPhase.complete,
    eventId: eventId,
  );
  if (complete != null) {
    return complete.control == expectedControl.wireValue &&
        (expectedProof == null ||
            sameAuthenticatedGroupAuthorityProof(complete, expectedProof));
  }
  final prepared = await loadAuthorityProof(
    groupId: groupId,
    phase: AuthenticatedGroupAuthorityPhase.prepared,
    eventId: eventId,
  );
  if (prepared == null ||
      prepared.control != expectedControl.wireValue ||
      (expectedProof != null &&
          !sameAuthenticatedGroupAuthorityProof(prepared, expectedProof))) {
    return false;
  }
  final converged = await protectedGroupAuthorityProofConverged(
    proof: prepared,
    groupRepository: groupRepository,
  );
  if (converged != true) return false;
  await appendAuthorityProof(
    phase: AuthenticatedGroupAuthorityPhase.complete,
    proof: prepared,
  );
  final stored = await loadAuthorityProof(
    groupId: groupId,
    phase: AuthenticatedGroupAuthorityPhase.complete,
    eventId: eventId,
  );
  return stored != null &&
      sameAuthenticatedGroupAuthorityProof(stored, prepared);
}

/// Recovers a locally authored key PREPARED fact that has no broadcast owner.
///
/// A zero-target rotation can crash after its atomic PREPARED fact but before
/// local key promotion. The persisted rotation draft is the secret-bearing
/// retry address; the authenticated proof supplies the exact epoch/hash/time.
/// Promotion is idempotent, then the key projection and COMPLETE fact commit in
/// one repository transaction before the draft retires.
Future<bool> recoverPreparedProtectedGroupKey({
  required AuthenticatedGroupAuthorityProof proof,
  required GroupRepository groupRepository,
  required Future<void> Function(GroupKeyInfo key) promoteKey,
  required LoadAuthenticatedGroupAuthorityProof loadAuthorityProof,
}) {
  return runGroupAuthorityPhaseIfNeeded(
    groupId: proof.groupId,
    authorityPhaseHeld: isGroupAuthorityPhaseHeld(proof.groupId),
    action: () async {
      try {
        if (proof.control !=
                ProtectedGroupAuthorityControl.groupKeyUpdate.wireValue ||
            proof.authorityData['groupId'] != proof.groupId) {
          return false;
        }
        final recipients = _strictRecipientAcl(
          proof.authorityData['recipientTransportPeerIds'],
        );
        if (recipients == null || recipients.isNotEmpty) {
          // This recovery entry point has no broadcast owner. A nonempty ACL
          // without rows is not proof of custody: it can also be an aborted
          // preparation whose rows were cancelled. Fresh/deferred nonempty
          // transitions complete locally before their rows are allowed to
          // retire; only an explicitly signed empty ACL is rowless by design.
          return false;
        }
        final complete = await loadAuthorityProof(
          groupId: proof.groupId,
          phase: AuthenticatedGroupAuthorityPhase.complete,
          eventId: proof.eventId,
        );
        if (complete != null) {
          return sameAuthenticatedGroupAuthorityProof(complete, proof);
        }
        if (groupRepository is! GroupKeyRotationDraftRepository ||
            groupRepository is! AtomicProtectedGroupKeyAuthorityRepository) {
          return false;
        }
        final group = await groupRepository.getGroup(proof.groupId);
        if (group == null || group.selfRemovedAt != null || group.isDissolved) {
          return false;
        }
        final generation = proof.authorityData['keyGeneration'];
        final encryptedKeyHash = _strict(
          proof.authorityData['encryptedKeyHash'],
        );
        if (generation is! int ||
            generation <= 0 ||
            generation != proof.keyEpoch ||
            encryptedKeyHash == null) {
          return false;
        }
        bool matches(GroupKeyInfo? key) =>
            key != null &&
            key.keyGeneration == generation &&
            key.createdAt.toUtc() == proof.eventAt.toUtc() &&
            groupAuthoritySha256(key.encryptedKey) == encryptedKeyHash;
        final latest = await groupRepository.getLatestKey(proof.groupId);
        if (latest != null &&
            (latest.keyGeneration > generation ||
                (latest.keyGeneration == generation && !matches(latest)))) {
          return false;
        }
        final committed = await groupRepository.getKeyByGeneration(
          proof.groupId,
          generation,
        );
        final draftRepository =
            groupRepository as GroupKeyRotationDraftRepository;
        final draft = await draftRepository.getPendingKeyRotation(
          proof.groupId,
        );
        final key = matches(committed)
            ? committed!
            : matches(draft)
            ? draft!
            : null;
        if (key == null) return false;

        await promoteKey(key);
        final atomicRepository =
            groupRepository as AtomicProtectedGroupKeyAuthorityRepository;
        await atomicRepository.commitProtectedGroupKeyAuthority(
          key: key,
          authorityComplete: ProtectedGroupAuthorityCompleteFact(
            sourcePeerId: proof.actorAccountPeerId,
            sourceEventId: authenticatedGroupAuthoritySourceEventId(
              AuthenticatedGroupAuthorityPhase.complete,
              proof.eventId,
            ),
            sourceTimestamp: fixedGroupAuthorityUtc(proof.eventAt),
            payload: authenticatedGroupAuthorityFactPayload(proof),
          ),
        );
        if (draft != null && matches(draft)) {
          await draftRepository.clearPendingKeyRotation(
            proof.groupId,
            draft.keyGeneration,
          );
        }
        final stored = await loadAuthorityProof(
          groupId: proof.groupId,
          phase: AuthenticatedGroupAuthorityPhase.complete,
          eventId: proof.eventId,
        );
        return stored != null &&
            sameAuthenticatedGroupAuthorityProof(stored, proof);
      } catch (_) {
        return false;
      }
    },
  );
}

/// Recovers the sender half of a protected dissolve from durable PREPARED
/// history and exact protected rows.
///
/// Each accepted target's exact row retires as its durable receipt. Remaining
/// rows are the survivor set; after the final receipt, authenticated PREPARED
/// history owns the rowless crash gap until the repository atomically commits
/// terminal projection, COMPLETE history, and display-custody cleanup.
Future<bool> recoverPreparedProtectedGroupDissolve({
  required String groupId,
  required String eventId,
  required GroupRepository groupRepository,
  required GroupPendingBroadcastRepository pendingRepository,
  required AckOrExpiryInboxStore protectedInboxStore,
  PendingSiblingDeviceRepository? pendingSiblingDeviceRepository,
  required LoadAuthenticatedGroupAuthorityProof loadAuthorityProof,
}) {
  return runGroupAuthorityPhaseIfNeeded(
    groupId: groupId,
    authorityPhaseHeld: isGroupAuthorityPhaseHeld(groupId),
    action: () async {
      try {
        final complete = await loadAuthorityProof(
          groupId: groupId,
          phase: AuthenticatedGroupAuthorityPhase.complete,
          eventId: eventId,
        );
        if (complete != null) {
          return complete.control ==
                  ProtectedGroupAuthorityControl.groupDissolve.wireValue &&
              (await groupRepository.getGroup(groupId))?.isDissolved == true;
        }

        final prepared = await loadAuthorityProof(
          groupId: groupId,
          phase: AuthenticatedGroupAuthorityPhase.prepared,
          eventId: eventId,
        );
        if (prepared == null ||
            prepared.control !=
                ProtectedGroupAuthorityControl.groupDissolve.wireValue ||
            prepared.groupId != groupId) {
          return false;
        }
        final updatedGroup = await _dissolvedProjectionFromPreparedProof(
          prepared,
          groupRepository,
        );
        if (updatedGroup == null) return false;

        final expectedRecipients = _strictRecipientAcl(
          prepared.authorityData['recipientTransportPeerIds'],
        );
        if (expectedRecipients == null) return false;
        final pendingRows = await pendingRepository.forGroup(groupId);
        if (pendingRows.any(
          (row) =>
              row.kind == groupPendingBroadcastKindProtectedAuthority &&
              parseProtectedGroupAuthorityDeliveryId(
                    row.sourceMessageId ?? '',
                  ) ==
                  null,
        )) {
          return false;
        }
        final rows =
            pendingRows
                .where((row) {
                  if (row.kind != groupPendingBroadcastKindProtectedAuthority) {
                    return false;
                  }
                  final identity = parseProtectedGroupAuthorityDeliveryId(
                    row.sourceMessageId ?? '',
                  );
                  return identity?.control ==
                          ProtectedGroupAuthorityControl.groupDissolve &&
                      identity?.transitionId == eventId;
                })
                .toList(growable: false)
              ..sort(
                (left, right) => left.recipientPeerIds.single.compareTo(
                  right.recipientPeerIds.single,
                ),
              );
        final rowRecipients = <String>{};
        for (final row in rows) {
          if (row.recipientPeerIds.length != 1) return false;
          final recipient = row.recipientPeerIds.single;
          if (!rowRecipients.add(recipient)) return false;
          final envelope = ProtectedGroupEnvelope.tryParse(
            row.sysText,
            expectedType: protectedGroupAuthorityEnvelopeType,
          );
          final identity = parseProtectedGroupAuthorityDeliveryId(
            row.sourceMessageId ?? '',
          );
          if (envelope == null ||
              identity == null ||
              envelope.id != row.sourceMessageId ||
              envelope.recipientPeerId != recipient ||
              identity.recipientTransportPeerId != recipient) {
            return false;
          }
        }
        if (!expectedRecipients.toSet().containsAll(rowRecipients)) {
          return false;
        }

        final pendingSiblingRepository = pendingSiblingDeviceRepository;
        if (pendingSiblingRepository != null && rows.isNotEmpty) {
          final pendingSiblings = await pendingSiblingRepository
              .getPendingSiblingDevicesForGroup(groupId);
          if (pendingSiblings.any(
            (pending) => rowRecipients.contains(pending.transportPeerId),
          )) {
            return false;
          }
        }
        var allAccepted = true;
        for (final row in rows) {
          final outcome = await protectedInboxStore
              .storeInAckCustodyInboxDetailed(
                row.recipientPeerIds.single,
                row.sysText,
                custodyKind: AckCustodyKind.groupAuthorityV1,
              );
          if (!outcome.ackOrExpiryAccepted) {
            allAccepted = false;
            continue;
          }
          // Exact-row retirement is the durable per-target receipt. Once a
          // target accepts custody it can never become a retry prerequisite
          // again, so alternating target availability still converges. A
          // crash after the final retirement is recovered from rowless
          // authenticated PREPARED history.
          if (!await removeGroupPendingBroadcastIfExact(
            pendingRepository,
            row,
          )) {
            allAccepted = false;
          }
        }
        if (!allAccepted) return false;

        if (groupRepository is! AtomicProtectedGroupDissolveRepository) {
          return false;
        }
        final atomicRepository =
            groupRepository as AtomicProtectedGroupDissolveRepository;
        await atomicRepository.commitProtectedGroupDissolve(
          group: updatedGroup,
          authorityComplete: ProtectedGroupAuthorityCompleteFact(
            sourcePeerId: prepared.actorAccountPeerId,
            sourceEventId: authenticatedGroupAuthoritySourceEventId(
              AuthenticatedGroupAuthorityPhase.complete,
              prepared.eventId,
            ),
            sourceTimestamp: fixedGroupAuthorityUtc(prepared.eventAt),
            payload: authenticatedGroupAuthorityFactPayload(prepared),
          ),
          expectedBroadcasts: const <GroupPendingBroadcast>[],
        );
        final storedComplete = await loadAuthorityProof(
          groupId: groupId,
          phase: AuthenticatedGroupAuthorityPhase.complete,
          eventId: eventId,
        );
        return storedComplete != null &&
            sameAuthenticatedGroupAuthorityProof(storedComplete, prepared) &&
            (await groupRepository.getGroup(groupId))?.isDissolved == true;
      } catch (_) {
        return false;
      }
    },
  );
}

Future<GroupModel?> _dissolvedProjectionFromPreparedProof(
  AuthenticatedGroupAuthorityProof proof,
  GroupRepository groupRepository,
) async {
  final data = proof.authorityData;
  if (data['groupId'] != proof.groupId ||
      data['senderId'] != proof.actorAccountPeerId ||
      data['messageId'] != proof.eventId) {
    return null;
  }
  final timestamp = DateTime.tryParse(data['timestamp'] as String? ?? '');
  final text = data['text'];
  if (timestamp == null ||
      timestamp.toUtc() != proof.eventAt.toUtc() ||
      text is! String) {
    return null;
  }
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic> ||
      decoded['__sys'] != 'group_dissolved' ||
      decoded['dissolvedBy'] != proof.actorAccountPeerId) {
    return null;
  }
  final dissolvedAt = DateTime.tryParse(
    decoded['dissolvedAt'] as String? ?? '',
  );
  final audit = decoded['signedTransitionAudit'];
  if (dissolvedAt == null ||
      dissolvedAt.toUtc() != proof.eventAt.toUtc() ||
      audit is! Map<String, dynamic> ||
      audit['transitionType'] != 'group_dissolved' ||
      audit['groupId'] != proof.groupId ||
      audit['sourceEventId'] != proof.eventId) {
    return null;
  }
  final current = await groupRepository.getGroup(proof.groupId);
  if (current == null || current.selfRemovedAt != null) return null;
  if (current.isDissolved) {
    return current.dissolvedAt?.toUtc() == proof.eventAt.toUtc() &&
            current.dissolvedBy == proof.actorAccountPeerId
        ? current
        : null;
  }
  return current.copyWith(
    isDissolved: true,
    dissolvedAt: proof.eventAt.toUtc(),
    dissolvedBy: proof.actorAccountPeerId,
    lastMembershipEventAt: proof.eventAt.toUtc(),
    lastMembershipEventId: proof.eventId,
  );
}

List<String>? _strictRecipientAcl(Object? raw) {
  if (raw is! List || raw.any((value) => value is! String)) return null;
  final recipients = raw.cast<String>();
  if (recipients.any(
        (recipient) => recipient.isEmpty || recipient.trim() != recipient,
      ) ||
      recipients.toSet().length != recipients.length) {
    return null;
  }
  final sorted = recipients.toList()..sort();
  return _sameStrings(recipients, sorted) ? recipients : null;
}

class ProtectedGroupAuthorityDeliveryIdentity {
  const ProtectedGroupAuthorityDeliveryIdentity({
    required this.control,
    required this.transitionId,
    required this.recipientTransportPeerId,
  });

  final ProtectedGroupAuthorityControl control;
  final String transitionId;
  final String recipientTransportPeerId;
}

/// Reverses the canonical length-prefixed v86 delivery tuple without relying
/// on an auxiliary target hash or mutable ledger.
ProtectedGroupAuthorityDeliveryIdentity? parseProtectedGroupAuthorityDeliveryId(
  String deliveryId,
) {
  if (deliveryId.isEmpty ||
      deliveryId.length > protectedGroupLogicalIdMaxLength ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(deliveryId)) {
    return null;
  }
  var offset = 0;
  String? readField() {
    final colon = deliveryId.indexOf(':', offset);
    if (colon <= offset) return null;
    final byteLength = int.tryParse(deliveryId.substring(offset, colon));
    if (byteLength == null || byteLength <= 0) return null;
    final start = colon + 1;
    final end = start + byteLength;
    if (end > deliveryId.length) return null;
    final value = deliveryId.substring(start, end);
    offset = end;
    return value;
  }

  final controlRaw = readField();
  final transitionId = readField();
  final recipient = readField();
  final control = controlRaw == null
      ? null
      : ProtectedGroupAuthorityControl.fromWire(controlRaw);
  if (control == null ||
      transitionId == null ||
      recipient == null ||
      offset != deliveryId.length) {
    return null;
  }
  return ProtectedGroupAuthorityDeliveryIdentity(
    control: control,
    transitionId: transitionId,
    recipientTransportPeerId: recipient,
  );
}

String protectedGroupAuthorityDeliveryId(
  String kind,
  String transitionId,
  String recipientTransportPeerId,
) {
  String field(String value) => '${utf8.encode(value).length}:$value';
  // v86's unique source ID is the canonical target-qualified tuple itself.
  // Keeping it reversible avoids an unowned target hash/ledger and lets exact
  // retries compare the same kind + transition + physical recipient bytes.
  return '${field(kind)}${field(transitionId)}'
      '${field(recipientTransportPeerId)}';
}

bool _authorizedSenderDevice(
  GroupMember actor,
  ProtectedGroupAuthorityPayload payload,
) {
  final devices = actor.activeDevicesWithLegacyFallback();
  return devices.any(
    (device) =>
        device.transportPeerId == payload.senderTransportPeerId &&
        device.deviceSigningPublicKey == payload.senderTransportPublicKey,
  );
}

bool _exactKeys(Map<String, dynamic> map, Set<String> keys) =>
    map.length == keys.length && map.keys.toSet().containsAll(keys);

String? _strict(Object? value) {
  if (value is! String || value.isEmpty || value.trim() != value) return null;
  return value;
}

DateTime? _utc(Object? value) {
  final raw = _strict(value);
  if (raw == null || !raw.endsWith('Z')) return null;
  final parsed = DateTime.tryParse(raw);
  return parsed != null && parsed.isUtc ? parsed : null;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
