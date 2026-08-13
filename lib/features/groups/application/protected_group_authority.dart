import 'dart:convert';

import 'package:flutter_app/features/groups/application/linked_group_bootstrap_service.dart';
import 'package:flutter_app/features/groups/application/protected_group_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
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
  });

  final String groupId;
  final List<GroupPendingBroadcast> rows;
  bool get hasRecipients => rows.isNotEmpty;
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
  if (preparation == null || !preparation.hasRecipients) return true;
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
          replayRaw is! Map<String, dynamic>) {
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
};

/// Builds one immutable target-qualified row per frozen physical recipient.
/// Callers persist the returned rows before committing their local transition.
Future<List<GroupPendingBroadcast>> buildProtectedGroupAuthorityRows({
  required String groupId,
  required String transitionId,
  required ProtectedGroupAuthorityControl control,
  required Map<String, dynamic> replayData,
  required String actorAccountPeerId,
  required String actorAccountPublicKey,
  required String actorAccountPrivateKey,
  required GroupMemberDeviceIdentity senderDevice,
  required List<GroupMemberDeviceIdentity> frozenRecipients,
  List<GroupMemberDeviceIdentity>? deliveryRecipients,
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
      acl.isEmpty ||
      actorAccountPeerId.trim().isEmpty ||
      actorAccountPublicKey.trim().isEmpty ||
      actorAccountPrivateKey.trim().isEmpty ||
      senderDevice.transportPeerId.trim().isEmpty ||
      senderDevice.deviceSigningPublicKey.trim().isEmpty) {
    return const [];
  }
  final instant = (now ?? DateTime.now)().toUtc();
  final rows = <GroupPendingBroadcast>[];
  for (final recipient in recipients) {
    final recipientKey = recipient.mlKemPublicKey!.trim();
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
      replayData: replayData,
      signature: '',
    );
    final signed = await callSign(
      payload.canonicalSignedPayload(),
      actorAccountPrivateKey,
    );
    final signature = _strict(signed['signature']);
    if (signed['ok'] != true || signature == null) return const [];
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
      return const [];
    }
    final deliveryId = protectedGroupAuthorityDeliveryId(
      control.wireValue,
      transitionId,
      recipient.transportPeerId,
    );
    if (deliveryId.length > protectedGroupLogicalIdMaxLength ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(deliveryId)) {
      return const [];
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
  return rows;
}

Future<bool> persistPreparedProtectedGroupAuthority({
  required GroupPendingBroadcastRepository repository,
  required List<GroupPendingBroadcast> rows,
}) async {
  if (rows.isEmpty) return false;
  if (repository
      case final GroupPendingBroadcastProtectedBatchRepository batch) {
    return batch.enqueueProtectedBatch(rows);
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
    final instant = (now ?? DateTime.now)().toUtc();
    if (instant.isBefore(payload.issuedAt) ||
        !payload.expiresAt.isAfter(instant) ||
        !await callVerify(
          publicKey: payload.actorAccountPublicKey,
          data: payload.canonicalSignedPayload(),
          signature: payload.signature,
        )) {
      return ProtectedGroupAuthorityHandleResult.terminalRejected;
    }
    return switch (await applyReplay(payload.control, payload.replayData)) {
      ProtectedGroupAuthorityApplyResult.applied =>
        ProtectedGroupAuthorityHandleResult.applied,
      ProtectedGroupAuthorityApplyResult.duplicate =>
        ProtectedGroupAuthorityHandleResult.duplicate,
      ProtectedGroupAuthorityApplyResult.rejected =>
        ProtectedGroupAuthorityHandleResult.terminalRejected,
      ProtectedGroupAuthorityApplyResult.retryable =>
        ProtectedGroupAuthorityHandleResult.retryable,
    };
  } catch (_) {
    return ProtectedGroupAuthorityHandleResult.retryable;
  }
}

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
