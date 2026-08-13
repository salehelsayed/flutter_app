import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/config/multi_device_sync_flag.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';
import 'package:flutter_app/features/groups/application/protected_group_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/pending_sibling_device.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/linked_group_bootstrap_repository.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/qr_code/application/direct_linked_device_qr.dart';
import 'package:uuid/uuid.dart';

const linkedGroupBootstrapPurpose = 'linked_device_bootstrap_v1';
const linkedGroupBootstrapVersion = 1;
const linkedGroupBootstrapSigningDomain = 'mknoon/linked-group-bootstrap/v1';
const linkedGroupBootstrapLifetime = Duration(days: 7);

typedef LinkedGroupEncrypt =
    Future<Map<String, dynamic>> Function({
      required String recipientMlKemPublicKey,
      required String plaintext,
    });
typedef LinkedGroupDecrypt =
    Future<Map<String, dynamic>> Function({
      required String ownMlKemSecretKey,
      required String kem,
      required String ciphertext,
      required String nonce,
    });
typedef LinkedGroupSign =
    Future<Map<String, dynamic>> Function(String data, String privateKey);
typedef LinkedGroupVerify =
    Future<bool> Function({
      required String publicKey,
      required String data,
      required String signature,
    });

enum AuthorLinkedGroupBootstrapResult {
  committed,
  duplicate,
  alreadyAuthoritative,
  selectorDisabled,
  multiDeviceDisabled,
  linkedScannerRefused,
  repositoryUnsupported,
  groupUnavailable,
  selfMembershipUnavailable,
  roleMismatch,
  targetConflict,
  cryptoFailed,
  stateChanged,
  pendingConflict,
}

enum HandleLinkedGroupBootstrapResult {
  applied,
  duplicate,
  terminalRejected,
  retryable,
}

/// Immutable signed snapshot carried inside one protected bootstrap envelope.
class LinkedGroupBootstrapPayload {
  const LinkedGroupBootstrapPayload({
    required this.bootstrapId,
    required this.issuedAt,
    required this.expiresAt,
    required this.accountPeerId,
    required this.accountPublicKey,
    required this.targetDeviceId,
    required this.targetTransportPeerId,
    required this.targetTransportPublicKey,
    required this.targetMlKemPublicKey,
    required this.group,
    required this.members,
    required this.key,
    required this.signature,
  });

  final String bootstrapId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String accountPeerId;
  final String accountPublicKey;
  final String targetDeviceId;
  final String targetTransportPeerId;
  final String targetTransportPublicKey;
  final String targetMlKemPublicKey;
  final GroupModel group;
  final List<GroupMember> members;
  final GroupKeyInfo key;
  final String signature;

  Map<String, Object?> unsignedBody() => <String, Object?>{
    'purpose': linkedGroupBootstrapPurpose,
    'version': linkedGroupBootstrapVersion,
    'bootstrapId': bootstrapId,
    'issuedAt': issuedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'accountPeerId': accountPeerId,
    'accountPublicKey': accountPublicKey,
    'targetDeviceId': targetDeviceId,
    'targetTransportPeerId': targetTransportPeerId,
    'targetTransportPublicKey': targetTransportPublicKey,
    'targetMlKemPublicKey': targetMlKemPublicKey,
    'group': group.toMap(),
    'members': (members.toList()..sort((a, b) => a.peerId.compareTo(b.peerId)))
        .map((member) => member.toMap())
        .toList(growable: false),
    'key': key.toMap(),
  };

  String canonicalSignedPayload() =>
      '$linkedGroupBootstrapSigningDomain\n'
      '${canonicalLinkedGroupAuthorityJson(unsignedBody())}';

  String toInnerJson() => jsonEncode(<String, Object?>{
    'body': unsignedBody(),
    'signature': signature,
  });

  LinkedGroupBootstrapPayload withSignature(String value) =>
      LinkedGroupBootstrapPayload(
        bootstrapId: bootstrapId,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        accountPeerId: accountPeerId,
        accountPublicKey: accountPublicKey,
        targetDeviceId: targetDeviceId,
        targetTransportPeerId: targetTransportPeerId,
        targetTransportPublicKey: targetTransportPublicKey,
        targetMlKemPublicKey: targetMlKemPublicKey,
        group: group,
        members: members,
        key: key,
        signature: value,
      );

  static LinkedGroupBootstrapPayload? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 2 ||
          !decoded.containsKey('body') ||
          !decoded.containsKey('signature')) {
        return null;
      }
      final signature = _strictString(decoded['signature']);
      final body = decoded['body'];
      if (signature == null ||
          body is! Map<String, dynamic> ||
          body.keys.toSet().length != _bootstrapBodyKeys.length ||
          !body.keys.toSet().containsAll(_bootstrapBodyKeys) ||
          body['purpose'] != linkedGroupBootstrapPurpose ||
          body['version'] != linkedGroupBootstrapVersion) {
        return null;
      }
      final bootstrapId = _strictString(body['bootstrapId']);
      final accountPeerId = _strictString(body['accountPeerId']);
      final accountPublicKey = _strictString(body['accountPublicKey']);
      final targetDeviceId = _strictString(body['targetDeviceId']);
      final targetTransportPeerId = _strictString(
        body['targetTransportPeerId'],
      );
      final targetTransportPublicKey = _strictString(
        body['targetTransportPublicKey'],
      );
      final targetMlKemPublicKey = _strictString(body['targetMlKemPublicKey']);
      final issuedAt = _strictUtc(body['issuedAt']);
      final expiresAt = _strictUtc(body['expiresAt']);
      if (bootstrapId == null ||
          accountPeerId == null ||
          accountPublicKey == null ||
          targetDeviceId == null ||
          targetTransportPeerId == null ||
          targetTransportPublicKey == null ||
          targetMlKemPublicKey == null ||
          issuedAt == null ||
          expiresAt == null ||
          !expiresAt.isAfter(issuedAt) ||
          expiresAt.difference(issuedAt) > linkedGroupBootstrapLifetime) {
        return null;
      }
      final groupRaw = body['group'];
      final membersRaw = body['members'];
      final keyRaw = body['key'];
      if (groupRaw is! Map<String, dynamic> ||
          membersRaw is! List ||
          membersRaw.isEmpty ||
          keyRaw is! Map<String, dynamic>) {
        return null;
      }
      final group = GroupModel.fromMap(groupRaw);
      if (!_sameExactKeys(groupRaw, group.toMap().keys.toSet())) return null;
      final members = <GroupMember>[];
      final peerIds = <String>{};
      for (final rawMember in membersRaw) {
        if (rawMember is! Map<String, dynamic>) return null;
        final member = GroupMember.fromMap(rawMember);
        if (!_sameExactKeys(rawMember, member.toMap().keys.toSet()) ||
            member.groupId != group.id ||
            !peerIds.add(member.peerId)) {
          return null;
        }
        members.add(member);
      }
      final key = GroupKeyInfo.fromMap(keyRaw);
      if (!_sameExactKeys(keyRaw, key.toMap().keys.toSet()) ||
          key.groupId != group.id ||
          key.keyGeneration <= 0 ||
          key.encryptedKey.trim().isEmpty) {
        return null;
      }
      return LinkedGroupBootstrapPayload(
        bootstrapId: bootstrapId,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        accountPeerId: accountPeerId,
        accountPublicKey: accountPublicKey,
        targetDeviceId: targetDeviceId,
        targetTransportPeerId: targetTransportPeerId,
        targetTransportPublicKey: targetTransportPublicKey,
        targetMlKemPublicKey: targetMlKemPublicKey,
        group: group,
        members: members,
        key: key,
        signature: signature,
      );
    } catch (_) {
      return null;
    }
  }
}

const _bootstrapBodyKeys = <String>{
  'purpose',
  'version',
  'bootstrapId',
  'issuedAt',
  'expiresAt',
  'accountPeerId',
  'accountPublicKey',
  'targetDeviceId',
  'targetTransportPeerId',
  'targetTransportPublicKey',
  'targetMlKemPublicKey',
  'group',
  'members',
  'key',
};

/// Builds and atomically persists one selected-group self bootstrap.
Future<AuthorLinkedGroupBootstrapResult> authorLinkedGroupBootstrap({
  required GroupRepository groupRepository,
  required String groupId,
  required String ownAccountPeerId,
  required String ownAccountPublicKey,
  required String ownAccountPrivateKey,
  required DirectLinkedDeviceQrDocument verifiedTarget,
  required bool isOrdinaryPrimary,
  required LinkedGroupSign callSign,
  required LinkedGroupEncrypt callEncrypt,
  DirectLinkedDeviceSelector selector = const DirectLinkedDeviceSelector(),
  bool multiDeviceSyncEnabled = kMultiDeviceSyncEnabled,
  String? bootstrapIdOverride,
  DateTime Function()? now,
}) async {
  if (!selector.allowsLinkedDeviceAuthoring) {
    return AuthorLinkedGroupBootstrapResult.selectorDisabled;
  }
  if (!multiDeviceSyncEnabled) {
    return AuthorLinkedGroupBootstrapResult.multiDeviceDisabled;
  }
  if (!isOrdinaryPrimary) {
    return AuthorLinkedGroupBootstrapResult.linkedScannerRefused;
  }
  if (groupRepository is! LinkedGroupBootstrapRepository) {
    return AuthorLinkedGroupBootstrapResult.repositoryUnsupported;
  }
  final bootstrapRepository = groupRepository as LinkedGroupBootstrapRepository;
  final accountPeerId = ownAccountPeerId.trim();
  final accountPublicKey = ownAccountPublicKey.trim();
  if (verifiedTarget.accountPeerId != accountPeerId ||
      verifiedTarget.accountPublicKey != accountPublicKey) {
    return AuthorLinkedGroupBootstrapResult.targetConflict;
  }
  final group = await groupRepository.getGroup(groupId);
  if (group == null || group.isDissolved || group.selfRemovedAt != null) {
    return AuthorLinkedGroupBootstrapResult.groupUnavailable;
  }
  final members = await groupRepository.getMembers(groupId);
  final selfMembers = members
      .where((member) => member.peerId == accountPeerId)
      .toList(growable: false);
  if (selfMembers.length != 1) {
    return AuthorLinkedGroupBootstrapResult.selfMembershipUnavailable;
  }
  final self = selfMembers.single;
  final expectedGroupRole = self.role == MemberRole.admin
      ? GroupRole.admin
      : GroupRole.member;
  if (group.myRole != expectedGroupRole ||
      self.publicKey?.trim() != accountPublicKey) {
    return AuthorLinkedGroupBootstrapResult.roleMismatch;
  }
  final key = await groupRepository.getLatestKey(groupId);
  if (key == null || key.encryptedKey.trim().isEmpty) {
    return AuthorLinkedGroupBootstrapResult.groupUnavailable;
  }

  for (final member in members) {
    for (final device in member.devices) {
      final sharesIdentity =
          device.deviceId == verifiedTarget.deviceId ||
          device.transportPeerId == verifiedTarget.transportPeerId ||
          device.deviceSigningPublicKey == verifiedTarget.transportPublicKey;
      if (!sharesIdentity) continue;
      final exact =
          member.peerId == accountPeerId &&
          device.deviceId == verifiedTarget.deviceId &&
          device.transportPeerId == verifiedTarget.transportPeerId &&
          device.deviceSigningPublicKey == verifiedTarget.transportPublicKey &&
          device.mlKemPublicKey == verifiedTarget.deviceMlKemPublicKey &&
          device.isActive;
      return exact
          ? AuthorLinkedGroupBootstrapResult.alreadyAuthoritative
          : AuthorLinkedGroupBootstrapResult.targetConflict;
    }
  }

  final keyPackageId = defaultGroupWelcomeKeyPackageIdForDevice(
    verifiedTarget.deviceId,
  );
  if (keyPackageId == null) {
    return AuthorLinkedGroupBootstrapResult.targetConflict;
  }
  final linkedDevice = GroupMemberDeviceIdentity(
    deviceId: verifiedTarget.deviceId,
    transportPeerId: verifiedTarget.transportPeerId,
    deviceSigningPublicKey: verifiedTarget.transportPublicKey,
    mlKemPublicKey: verifiedTarget.deviceMlKemPublicKey,
    keyPackageId: keyPackageId,
    keyPackagePublicMaterial: verifiedTarget.deviceMlKemPublicKey,
  );
  final currentDevices = self.devices.toList(growable: true);
  if (currentDevices.isEmpty) {
    final legacyDevice = self.legacyDeviceIdentity;
    if (legacyDevice != null) {
      currentDevices.add(legacyDevice);
    }
  }
  if (currentDevices.isEmpty ||
      currentDevices.any(
        (device) =>
            device.deviceId == linkedDevice.deviceId ||
            device.transportPeerId == linkedDevice.transportPeerId,
      )) {
    return AuthorLinkedGroupBootstrapResult.targetConflict;
  }
  currentDevices.add(linkedDevice);
  final updatedSelf = self.copyWith(devices: currentDevices);
  final snapshotMembers = members
      .map((member) => member.peerId == accountPeerId ? updatedSelf : member)
      .toList(growable: false);
  final instant = (now ?? DateTime.now)().toUtc();
  final bootstrapId = (bootstrapIdOverride ?? const Uuid().v4()).trim();
  if (bootstrapId.isEmpty) {
    return AuthorLinkedGroupBootstrapResult.cryptoFailed;
  }
  var payload = LinkedGroupBootstrapPayload(
    bootstrapId: bootstrapId,
    issuedAt: instant,
    expiresAt: instant.add(linkedGroupBootstrapLifetime),
    accountPeerId: accountPeerId,
    accountPublicKey: accountPublicKey,
    targetDeviceId: verifiedTarget.deviceId,
    targetTransportPeerId: verifiedTarget.transportPeerId,
    targetTransportPublicKey: verifiedTarget.transportPublicKey,
    targetMlKemPublicKey: verifiedTarget.deviceMlKemPublicKey,
    group: group,
    members: snapshotMembers,
    key: key,
    signature: '',
  );
  try {
    final sign = await callSign(
      payload.canonicalSignedPayload(),
      ownAccountPrivateKey.trim(),
    );
    final signature = sign['signature'];
    if (sign['ok'] != true ||
        signature is! String ||
        signature.trim().isEmpty) {
      return AuthorLinkedGroupBootstrapResult.cryptoFailed;
    }
    payload = payload.withSignature(signature.trim());
    final encrypted = await callEncrypt(
      recipientMlKemPublicKey: verifiedTarget.deviceMlKemPublicKey,
      plaintext: payload.toInnerJson(),
    );
    final kem = _strictString(encrypted['kem']);
    final ciphertext = _strictString(encrypted['ciphertext']);
    final nonce = _strictString(encrypted['nonce']);
    if (encrypted['ok'] != true ||
        kem == null ||
        ciphertext == null ||
        nonce == null) {
      return AuthorLinkedGroupBootstrapResult.cryptoFailed;
    }
    final outer = ProtectedGroupEnvelope(
      type: linkedGroupBootstrapEnvelopeType,
      id: bootstrapId,
      senderPeerId: accountPeerId,
      recipientPeerId: verifiedTarget.transportPeerId,
      kem: kem,
      ciphertext: ciphertext,
      nonce: nonce,
    ).toJson();
    final pendingDevice = PendingSiblingDevice(
      groupId: groupId,
      memberPeerId: accountPeerId,
      deviceId: verifiedTarget.deviceId,
      transportPeerId: verifiedTarget.transportPeerId,
      deviceSigningPublicKey: verifiedTarget.transportPublicKey,
      mlKemPublicKey: verifiedTarget.deviceMlKemPublicKey,
      keyPackageId: keyPackageId,
      verifiedAccountSigningPublicKey: accountPublicKey,
      announcedAt: instant,
    );
    final pendingBroadcast = GroupPendingBroadcast(
      id: 'linked-bootstrap:$bootstrapId',
      groupId: groupId,
      kind: groupPendingBroadcastKindLinkedBootstrap,
      sysText: outer,
      recipientPeerIds: <String>[verifiedTarget.transportPeerId],
      eventAt: instant,
      sourceMessageId: bootstrapId,
      createdAt: instant,
      updatedAt: instant,
    );
    final committed = await bootstrapRepository
        .commitLinkedGroupBootstrapAuthoring(
          expectedGroup: group,
          expectedMembers: members,
          expectedSelfMember: self,
          expectedLatestKey: key,
          updatedSelfMember: updatedSelf,
          pendingDevice: pendingDevice,
          pendingBroadcast: pendingBroadcast,
        );
    return switch (committed) {
      LinkedGroupBootstrapAuthorCommitOutcome.committed =>
        AuthorLinkedGroupBootstrapResult.committed,
      LinkedGroupBootstrapAuthorCommitOutcome.duplicate =>
        AuthorLinkedGroupBootstrapResult.duplicate,
      LinkedGroupBootstrapAuthorCommitOutcome.refusedPendingConflict =>
        AuthorLinkedGroupBootstrapResult.pendingConflict,
      LinkedGroupBootstrapAuthorCommitOutcome.refusedStateChanged =>
        AuthorLinkedGroupBootstrapResult.stateChanged,
    };
  } catch (_) {
    return AuthorLinkedGroupBootstrapResult.cryptoFailed;
  }
}

/// Verifies, decrypts, and atomically materializes one fresh linked group.
Future<HandleLinkedGroupBootstrapResult> handleLinkedGroupBootstrapEnvelope({
  required ChatMessage message,
  required LinkedInstallationAuthoritySnapshot linkedAuthority,
  required String ownMlKemPublicKey,
  required String ownMlKemSecretKey,
  required GroupRepository groupRepository,
  required LinkedGroupDecrypt callDecrypt,
  required LinkedGroupVerify callVerify,
  DateTime Function()? now,
}) async {
  if (!linkedAuthority.isActiveLinkedSecondary ||
      groupRepository is! LinkedGroupBootstrapRepository) {
    return HandleLinkedGroupBootstrapResult.terminalRejected;
  }
  final bootstrapRepository = groupRepository as LinkedGroupBootstrapRepository;
  final credential = linkedAuthority.credential!;
  final outer = ProtectedGroupEnvelope.tryParse(
    message.content,
    expectedType: linkedGroupBootstrapEnvelopeType,
  );
  if (outer == null ||
      message.from != outer.senderPeerId ||
      message.to != outer.recipientPeerId ||
      outer.senderPeerId != credential.accountPeerId ||
      outer.recipientPeerId != credential.transportPeerId) {
    return HandleLinkedGroupBootstrapResult.terminalRejected;
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
      return HandleLinkedGroupBootstrapResult.terminalRejected;
    }
    final payload = LinkedGroupBootstrapPayload.tryParse(plaintext);
    if (payload == null ||
        payload.bootstrapId != outer.id ||
        payload.accountPeerId != credential.accountPeerId ||
        payload.accountPublicKey != credential.accountPublicKey ||
        payload.targetDeviceId != credential.deviceId ||
        payload.targetTransportPeerId != credential.transportPeerId ||
        payload.targetTransportPublicKey != credential.transportPublicKey ||
        payload.targetMlKemPublicKey != ownMlKemPublicKey.trim() ||
        !ed25519PublicKeyMatchesPeerId(
          base64PublicKey: payload.accountPublicKey,
          claimedPeerId: payload.accountPeerId,
        ) ||
        !ed25519PublicKeyMatchesPeerId(
          base64PublicKey: payload.targetTransportPublicKey,
          claimedPeerId: payload.targetTransportPeerId,
        )) {
      return HandleLinkedGroupBootstrapResult.terminalRejected;
    }
    final instant = (now ?? DateTime.now)().toUtc();
    if (instant.isBefore(payload.issuedAt) ||
        !payload.expiresAt.isAfter(instant)) {
      return HandleLinkedGroupBootstrapResult.terminalRejected;
    }
    if (!await callVerify(
      publicKey: payload.accountPublicKey,
      data: payload.canonicalSignedPayload(),
      signature: payload.signature,
    )) {
      return HandleLinkedGroupBootstrapResult.terminalRejected;
    }
    final selfMembers = payload.members
        .where((member) => member.peerId == payload.accountPeerId)
        .toList(growable: false);
    if (selfMembers.length != 1) {
      return HandleLinkedGroupBootstrapResult.terminalRejected;
    }
    final self = selfMembers.single;
    final target = self.findDeviceById(payload.targetDeviceId);
    final derivedRole = self.role == MemberRole.admin
        ? GroupRole.admin
        : GroupRole.member;
    if (target == null ||
        target.transportPeerId != payload.targetTransportPeerId ||
        target.deviceSigningPublicKey != payload.targetTransportPublicKey ||
        target.mlKemPublicKey != payload.targetMlKemPublicKey ||
        payload.group.myRole != derivedRole ||
        payload.key.groupId != payload.group.id) {
      return HandleLinkedGroupBootstrapResult.terminalRejected;
    }
    final result = await bootstrapRepository
        .commitLinkedGroupBootstrapMaterialization(
          bootstrapId: payload.bootstrapId,
          group: payload.group,
          members: payload.members,
          key: payload.key,
        );
    return switch (result) {
      LinkedGroupBootstrapMaterializationOutcome.committed =>
        HandleLinkedGroupBootstrapResult.applied,
      LinkedGroupBootstrapMaterializationOutcome.duplicate =>
        HandleLinkedGroupBootstrapResult.duplicate,
      LinkedGroupBootstrapMaterializationOutcome.refusedConflict =>
        HandleLinkedGroupBootstrapResult.terminalRejected,
    };
  } catch (_) {
    return HandleLinkedGroupBootstrapResult.retryable;
  }
}

String canonicalLinkedGroupAuthorityJson(Object? value) =>
    jsonEncode(_canonicalizeLinkedGroupValue(value));

Object? _canonicalizeLinkedGroupValue(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      if (entry.key is! String) throw const FormatException('non-string key');
      sorted[entry.key as String] = _canonicalizeLinkedGroupValue(entry.value);
    }
    return sorted;
  }
  if (value is List) {
    return value.map(_canonicalizeLinkedGroupValue).toList(growable: false);
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw const FormatException('unsupported canonical value');
}

String? _strictString(Object? value) {
  if (value is! String || value.isEmpty || value.trim() != value) return null;
  return value;
}

DateTime? _strictUtc(Object? value) {
  final raw = _strictString(value);
  if (raw == null || !raw.endsWith('Z')) return null;
  final parsed = DateTime.tryParse(raw);
  return parsed != null && parsed.isUtc ? parsed : null;
}

bool _sameExactKeys(Map<String, dynamic> map, Set<String> keys) =>
    map.length == keys.length && map.keys.toSet().containsAll(keys);
