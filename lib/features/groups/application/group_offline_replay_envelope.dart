import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/protected_group_content_contract.dart'
    as core_contract;
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/utils/group_reaction_transition_order.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';

export 'package:flutter_app/features/groups/domain/utils/group_reaction_transition_order.dart'
    show GroupReactionTransitionOrder, compareGroupReactionTransitionIds;

const groupOfflineReplayEnvelopeKind = 'group_offline_replay';
const groupOfflineReplayEnvelopeVersion = 1;
const groupOfflineReplayPayloadTypeMessage = 'group_message';
const groupOfflineReplayPayloadTypeReaction = 'group_reaction';
const groupOfflineReplaySignatureVersion = 1;
const groupOfflineReplaySignatureAlgorithm = 'ed25519';
const groupReactionNotificationExtensionKind = 'group_reaction_notification';
const groupReactionNotificationExtensionVersion = 1;
const groupContentCustodyKind = 'group_content_v1';

class GroupContentAuthorityVersion {
  const GroupContentAuthorityVersion({
    required this.eventAt,
    required this.eventId,
    required this.keyEpoch,
  });

  final DateTime eventAt;
  final String eventId;
  final int keyEpoch;
}

typedef VerifyHistoricalGroupContentSigner =
    Future<bool> Function({
      required String groupId,
      required GroupContentAuthorityVersion authorityVersion,
      required String logicalSenderPeerId,
      required String senderDeviceId,
      required String senderTransportPeerId,
      required String senderPublicKey,
    });

class VerifiedGroupContentReplay {
  const VerifiedGroupContentReplay({
    required this.plaintext,
    required this.groupId,
    required this.payloadType,
    required this.contentEventId,
    required this.authorityVersion,
    required this.logicalSenderPeerId,
    required this.senderDeviceId,
    required this.senderTransportPeerId,
    required this.senderPublicKey,
    required this.recipientPeerIds,
    required this.keyEpoch,
    required this.mediaManifest,
    required this.mediaManifestHash,
  });

  final String plaintext;
  final String groupId;
  final String payloadType;
  final String contentEventId;
  final GroupContentAuthorityVersion authorityVersion;
  final String logicalSenderPeerId;
  final String senderDeviceId;
  final String senderTransportPeerId;
  final String senderPublicKey;
  final List<String> recipientPeerIds;
  final int keyEpoch;
  final ProtectedGroupMediaManifest? mediaManifest;
  final String? mediaManifestHash;
}

String fixedGroupContentUtc(DateTime value) {
  final utc = value.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  String six(int value) => value.toString().padLeft(6, '0');
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:'
      '${two(utc.minute)}:${two(utc.second)}.'
      '${six(utc.microsecond + utc.millisecond * 1000)}Z';
}

DateTime? parseFixedGroupContentUtc(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
      ).hasMatch(value)) {
    return null;
  }
  final parsed = DateTime.tryParse(value)?.toUtc();
  return parsed != null && fixedGroupContentUtc(parsed) == value
      ? parsed
      : null;
}

/// Event-log identity shared by local strict authoring and protected receive.
String localProtectedGroupMessageSourceEventId(String messageId) =>
    'pm1:${base64Url.encode(utf8.encode(messageId)).replaceAll('=', '')}';

/// Event-log identity shared by local strict authoring and protected receive.
String localProtectedGroupReactionSourceEventId(String transitionId) =>
    'pr1:$transitionId';

/// Reconstructs the exact event evidence that protected receive will append
/// for the same signed envelope. This contains no private key or plaintext
/// outside the already-local canonical payload.
Map<String, Object?> buildLocalProtectedGroupContentEventPayload({
  required String replayEnvelope,
  required Map<String, Object?> payload,
}) {
  final envelope = _decodeStringMap(replayEnvelope);
  if (envelope == null ||
      envelope['kind'] != groupOfflineReplayEnvelopeKind ||
      envelope['version'] != groupOfflineReplayEnvelopeVersion ||
      envelope['custodyKind'] != groupContentCustodyKind) {
    throw const FormatException('invalid local protected content envelope');
  }
  _requireExactReplayStrings(envelope);
  final groupId = _strictNonEmptyString(envelope['groupId']);
  final payloadType = _strictNonEmptyString(envelope['payloadType']);
  final contentEventId = _strictNonEmptyString(envelope['contentEventId']);
  final authorityEventAt = _strictNonEmptyString(envelope['authorityEventAt']);
  final authorityEventId = _strictNonEmptyString(envelope['authorityEventId']);
  final authorityKeyEpoch = envelope['authorityKeyEpoch'];
  final logicalSenderPeerId = _strictNonEmptyString(envelope['senderPeerId']);
  final senderDeviceId = _strictNonEmptyString(envelope['senderDeviceId']);
  final senderTransportPeerId = _strictNonEmptyString(
    envelope['senderTransportPeerId'],
  );
  final senderPublicKey = _strictNonEmptyString(envelope['senderPublicKey']);
  final signedPayloadRaw = envelope['signedPayload'];
  final signedPayload = signedPayloadRaw is String
      ? _decodeStringMap(signedPayloadRaw)
      : null;
  final recipientPeerIds = _strictRecipientList(
    envelope.containsKey('recipientPeerIds')
        ? envelope['recipientPeerIds']
        : signedPayload?['recipientPeerIds'],
    'recipientPeerIds',
  );
  final exactPayload = Map<String, Object?>.from(payload);
  final strictPayloadFields = <String, Object?>{
    'groupId': groupId,
    'keyEpoch': envelope['keyEpoch'],
    'senderDeviceId': senderDeviceId,
    'transportPeerId': senderTransportPeerId,
    'custodyKind': groupContentCustodyKind,
    'contentEventId': contentEventId,
    'authorityEventAt': authorityEventAt,
    'authorityEventId': authorityEventId,
    'authorityKeyEpoch': authorityKeyEpoch,
    'recipientPeerIds': recipientPeerIds,
    if (envelope['mediaManifest'] case final String mediaManifest)
      'mediaManifest': mediaManifest,
    if (envelope['mediaManifestHash'] case final String mediaManifestHash)
      'mediaManifestHash': mediaManifestHash,
  };
  for (final entry in strictPayloadFields.entries) {
    if (exactPayload.containsKey(entry.key) &&
        !_sameCanonicalValue(exactPayload[entry.key], entry.value)) {
      throw const FormatException('crossed local protected plaintext');
    }
    exactPayload[entry.key] = entry.value;
  }
  final senderField = payloadType == groupOfflineReplayPayloadTypeReaction
      ? 'senderPeerId'
      : 'senderId';
  final timestamp = _strictNonEmptyString(exactPayload['timestamp']);
  if (groupId == null ||
      (payloadType != groupOfflineReplayPayloadTypeMessage &&
          payloadType != groupOfflineReplayPayloadTypeReaction) ||
      contentEventId == null ||
      envelope['messageId'] != contentEventId ||
      authorityEventAt == null ||
      parseFixedGroupContentUtc(authorityEventAt) == null ||
      authorityEventId == null ||
      authorityKeyEpoch is! int ||
      authorityKeyEpoch < 0 ||
      authorityKeyEpoch != envelope['keyEpoch'] ||
      logicalSenderPeerId == null ||
      senderDeviceId == null ||
      senderTransportPeerId == null ||
      senderPublicKey == null ||
      exactPayload[senderField] != logicalSenderPeerId ||
      timestamp == null ||
      parseFixedGroupContentUtc(timestamp) == null ||
      (payloadType == groupOfflineReplayPayloadTypeMessage
          ? exactPayload['messageId'] != contentEventId
          : exactPayload['eventId'] != contentEventId) ||
      signedPayload == null ||
      signedPayload['plaintextHash'] != _hashString(jsonEncode(exactPayload))) {
    throw const FormatException('crossed local protected content evidence');
  }
  return <String, Object?>{
    'custodyKind': groupContentCustodyKind,
    'groupId': groupId,
    'payloadType': payloadType,
    'contentEventId': contentEventId,
    'authorityEventAt': authorityEventAt,
    'authorityEventId': authorityEventId,
    'authorityKeyEpoch': authorityKeyEpoch,
    'logicalSenderPeerId': logicalSenderPeerId,
    'senderDeviceId': senderDeviceId,
    'senderTransportPeerId': senderTransportPeerId,
    'senderPublicKey': senderPublicKey,
    'recipientPeerIds': recipientPeerIds,
    'payload': exactPayload,
  };
}

bool _sameCanonicalValue(Object? left, Object? right) {
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
  return left == right;
}

class GroupContentRetryPayload {
  const GroupContentRetryPayload({
    required this.groupId,
    required this.message,
    required this.contentEventId,
    required this.pendingRecipientPeerIds,
    required this.fullRecipientPeerIds,
    required this.payloadType,
    required this.authorityVersion,
    required this.logicalSenderPeerId,
    required this.senderDeviceId,
    required this.senderTransportPeerId,
    required this.senderPublicKey,
    required this.mediaManifest,
    required this.mediaManifestHash,
  });

  final String groupId;
  final String message;
  final String contentEventId;
  final List<String> pendingRecipientPeerIds;
  final List<String> fullRecipientPeerIds;
  final String payloadType;
  final GroupContentAuthorityVersion authorityVersion;
  final String logicalSenderPeerId;
  final String senderDeviceId;
  final String senderTransportPeerId;
  final String senderPublicKey;
  final ProtectedGroupMediaManifest? mediaManifest;
  final String? mediaManifestHash;

  int contentExpiresAtOrBeforeMsFor(String recipientPeerId) {
    final manifest = mediaManifest;
    if (manifest == null) {
      throw StateError('blob-free group content has no expiry ceiling');
    }
    return manifest.contentExpiresAtOrBeforeMsFor(recipientPeerId);
  }

  String encodeWithPending(Iterable<String> pending) {
    final normalized = _strictSortedUniqueRecipients(pending, 'pending');
    if (normalized.isEmpty ||
        normalized.any((peerId) => !fullRecipientPeerIds.contains(peerId))) {
      throw const FormatException('invalid group content pending recipients');
    }
    return jsonEncode(<String, Object?>{
      'groupId': groupId,
      'message': message,
      'custodyContract': ackOrExpiryInboxCustodyContract,
      'custodyKind': groupContentCustodyKind,
      'recipientPeerIds': normalized,
    });
  }

  static GroupContentRetryPayload decode(String raw) {
    core_contract.ProtectedGroupContentRetryManifest.decode(raw);
    final wrapper = _decodeStringMap(raw);
    if (wrapper == null ||
        !_sameExactKeySet(wrapper, const <String>{
          'groupId',
          'message',
          'custodyContract',
          'custodyKind',
          'recipientPeerIds',
        }) ||
        wrapper['custodyContract'] != ackOrExpiryInboxCustodyContract ||
        wrapper['custodyKind'] != groupContentCustodyKind) {
      throw const FormatException('not strict group content custody');
    }
    final groupId = _strictNonEmptyString(wrapper['groupId']);
    final message = _strictNonEmptyString(wrapper['message']);
    if (groupId == null || message == null) {
      throw const FormatException('missing group content retry authority');
    }
    final envelope = _decodeStringMap(message);
    if (envelope == null) {
      throw const FormatException('crossed group content envelope');
    }
    try {
      _requireStrictGroupContentEnvelopeKeySet(envelope);
    } catch (_) {
      throw const FormatException('invalid group content envelope key set');
    }
    if (envelope['kind'] != groupOfflineReplayEnvelopeKind ||
        envelope['version'] != groupOfflineReplayEnvelopeVersion ||
        envelope['custodyKind'] != groupContentCustodyKind ||
        envelope['groupId'] != groupId) {
      throw const FormatException('crossed group content envelope');
    }
    final contentEventId = _strictNonEmptyString(envelope['contentEventId']);
    final payloadType = envelope['payloadType'];
    final signedPayloadRaw = _strictNonEmptyString(envelope['signedPayload']);
    final signedPayload = signedPayloadRaw == null
        ? null
        : _decodeStringMap(signedPayloadRaw);
    if (contentEventId == null ||
        envelope['messageId'] != contentEventId ||
        signedPayload == null ||
        signedPayload['custodyKind'] != groupContentCustodyKind ||
        signedPayload['contentEventId'] != contentEventId ||
        signedPayload['groupId'] != groupId) {
      throw const FormatException('unsigned group content discriminator');
    }
    if (payloadType != groupOfflineReplayPayloadTypeMessage &&
        payloadType != groupOfflineReplayPayloadTypeReaction) {
      throw const FormatException('invalid group content payload type');
    }
    if (payloadType == groupOfflineReplayPayloadTypeReaction) {
      if (GroupReactionTransitionOrder.tryParse(contentEventId) == null ||
          envelope['notificationExtension'] is! Map) {
        throw const FormatException('invalid strict reaction authority');
      }
    } else if (envelope.containsKey('notificationExtension')) {
      throw const FormatException(
        'message must not declare reaction extension',
      );
    }
    final full = _strictRecipientList(envelope['recipientPeerIds'], 'full');
    final signedFull = _strictRecipientList(
      signedPayload['recipientPeerIds'],
      'signed full',
    );
    if (!_sameStringList(full, signedFull) ||
        envelope['recipientSetHash'] != _recipientSetHashFromNormalized(full) ||
        signedPayload['recipientSetHash'] != envelope['recipientSetHash']) {
      throw const FormatException('group content ACL mismatch');
    }
    final manifestBinding = _decodeProtectedGroupMediaManifestBinding(
      envelope: envelope,
      signedPayload: signedPayload,
      groupId: groupId,
      contentEventId: contentEventId,
      recipientPeerIds: full,
      payloadType: payloadType as String,
      invalid: (reason) => throw FormatException(reason),
    );
    final pending = _strictRecipientList(
      wrapper['recipientPeerIds'],
      'pending',
    );
    if (pending.isEmpty || pending.any((peerId) => !full.contains(peerId))) {
      throw const FormatException('invalid group content pending subset');
    }
    for (final field in const <String>[
      'authorityEventAt',
      'authorityEventId',
      'authorityKeyEpoch',
    ]) {
      if (envelope[field] != signedPayload[field]) {
        throw const FormatException('group content authority mismatch');
      }
    }
    if (parseFixedGroupContentUtc(envelope['authorityEventAt']) == null ||
        _strictNonEmptyString(envelope['authorityEventId']) == null ||
        envelope['authorityKeyEpoch'] is! int ||
        (envelope['authorityKeyEpoch'] as int) < 0 ||
        envelope['authorityKeyEpoch'] != envelope['keyEpoch']) {
      throw const FormatException('invalid group content authority version');
    }
    try {
      _requireExactReplayStrings(envelope);
      _strictGroupContentWireId(groupId, 'groupId');
      _strictGroupContentWireId(contentEventId, 'contentEventId');
      _strictGroupContentWireId(
        envelope['authorityEventId'],
        'authorityEventId',
      );
      if (canonicalizeGroupEventLogPayload(signedPayload) != signedPayloadRaw ||
          envelope['signatureAlgorithm'] !=
              groupOfflineReplaySignatureAlgorithm ||
          _strictNonEmptyString(envelope['signature']) == null) {
        throw const FormatException('noncanonical group content signature');
      }
      final senderPeerId = _strictNonEmptyString(envelope['senderPeerId']);
      final senderDeviceId = _strictNonEmptyString(envelope['senderDeviceId']);
      final senderTransportPeerId = _strictNonEmptyString(
        envelope['senderTransportPeerId'],
      );
      final senderPublicKey = _strictNonEmptyString(
        envelope['senderPublicKey'],
      );
      final ciphertext = _strictNonEmptyString(envelope['ciphertext']);
      final nonce = _strictNonEmptyString(envelope['nonce']);
      final plaintextHash = _strictNonEmptyString(
        signedPayload['plaintextHash'],
      );
      final keyEpoch = envelope['keyEpoch'];
      if (senderPeerId == null ||
          senderDeviceId == null ||
          senderTransportPeerId == null ||
          senderPublicKey == null ||
          ciphertext == null ||
          nonce == null ||
          plaintextHash == null ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(plaintextHash) ||
          keyEpoch is! int ||
          keyEpoch < 0) {
        throw const FormatException('incomplete group content signature');
      }
      final authority = GroupContentAuthorityVersion(
        eventAt: parseFixedGroupContentUtc(envelope['authorityEventAt'])!,
        eventId: envelope['authorityEventId'] as String,
        keyEpoch: keyEpoch,
      );
      final expectedSignedPayload = _buildReplaySignedPayloadFromHashes(
        groupId: groupId,
        payloadType: payloadType,
        keyEpoch: keyEpoch,
        ciphertextHash: _hashString(ciphertext),
        nonceHash: _hashString(nonce),
        plaintextHash: plaintextHash,
        messageId: contentEventId,
        senderPeerId: senderPeerId,
        senderDeviceId: senderDeviceId,
        senderTransportPeerId: senderTransportPeerId,
        senderPublicKey: senderPublicKey,
        senderKeyPackageId: _strictNonEmptyString(
          envelope['senderKeyPackageId'],
        ),
        recipientSetHash: envelope['recipientSetHash'] as String,
        recipientPeerIds: full,
        contentEventId: contentEventId,
        contentAuthorityVersion: authority,
        mediaManifestHash: manifestBinding.$3,
      );
      if (expectedSignedPayload != signedPayloadRaw) {
        throw const FormatException('group content signed map mismatch');
      }
      if (payloadType == groupOfflineReplayPayloadTypeReaction) {
        _validateRetryReactionExtension(
          envelope,
          contentEventId: contentEventId,
          senderPeerId: senderPeerId,
          senderTransportPeerId: senderTransportPeerId,
          recipientSetHash: envelope['recipientSetHash'] as String,
          recipientPeerIds: full,
        );
      }
    } catch (_) {
      throw const FormatException('invalid group content relay eligibility');
    }
    return GroupContentRetryPayload(
      groupId: groupId,
      message: message,
      contentEventId: contentEventId,
      pendingRecipientPeerIds: pending,
      fullRecipientPeerIds: full,
      payloadType: payloadType,
      authorityVersion: GroupContentAuthorityVersion(
        eventAt: parseFixedGroupContentUtc(envelope['authorityEventAt'])!,
        eventId: envelope['authorityEventId'] as String,
        keyEpoch: envelope['authorityKeyEpoch'] as int,
      ),
      logicalSenderPeerId: envelope['senderPeerId'] as String,
      senderDeviceId: envelope['senderDeviceId'] as String,
      senderTransportPeerId: envelope['senderTransportPeerId'] as String,
      senderPublicKey: envelope['senderPublicKey'] as String,
      mediaManifest: manifestBinding.$1,
      mediaManifestHash: manifestBinding.$3,
    );
  }
}

String localPreparedProtectedGroupMessageSourceEventId(String messageId) =>
    'ppm1:${base64Url.encode(utf8.encode(messageId)).replaceAll('=', '')}';

String localPreparedProtectedGroupReactionSourceEventId(String transitionId) =>
    'ppr1:$transitionId';

String localProtectedGroupContentTerminalSourceEventId({
  required String payloadType,
  required String contentEventId,
  required String reason,
}) =>
    'pt1:${base64Url.encode(utf8.encode(payloadType)).replaceAll('=', '')}:'
    '${base64Url.encode(utf8.encode(contentEventId)).replaceAll('=', '')}:'
    '${sha256.convert(utf8.encode(reason))}';

Map<String, Object?> buildLocalProtectedGroupContentPreparedEventPayload({
  required Map<String, Object?> eventPayload,
  required String ownerKind,
  required String ownerId,
  required String ownerStatus,
  required String inboxRetryPayload,
}) {
  if ((ownerKind != 'group_message' && ownerKind != 'group_reaction') ||
      ownerId.isEmpty ||
      ownerStatus.isEmpty ||
      inboxRetryPayload.isEmpty ||
      eventPayload['custodyKind'] != groupContentCustodyKind) {
    throw const FormatException('invalid prepared group content owner');
  }
  final retry = GroupContentRetryPayload.decode(inboxRetryPayload);
  return <String, Object?>{
    ...eventPayload,
    'preparedOwnerKind': ownerKind,
    'preparedOwnerId': ownerId,
    'preparedOwnerStatus': ownerStatus,
    // Pending recipients are deliberately absent from this binding. Each
    // accepted custody receipt shrinks that mutable wrapper subset via CAS;
    // the signed replay envelope and its frozen full ACL remain immutable.
    'replayEnvelopeHash': sha256.convert(utf8.encode(retry.message)).toString(),
  };
}

bool _sameExactKeySet(Map<String, Object?> value, Set<String> expected) {
  final actual = value.keys.toSet();
  return actual.length == expected.length && actual.containsAll(expected);
}

bool isGroupContentRetryPayload(String? raw) {
  if (raw == null || raw.isEmpty) return false;
  try {
    GroupContentRetryPayload.decode(raw);
    return true;
  } catch (_) {
    return false;
  }
}

/// Cheap routing discriminator used only to keep malformed strict rows out of
/// legacy aggregate storage. Full authority still comes exclusively from
/// [GroupContentRetryPayload.decode].
bool declaresGroupContentRetryPayload(String? raw) {
  if (raw == null || raw.isEmpty) return false;
  final wrapper = _decodeStringMap(raw);
  if (wrapper == null) {
    return raw.contains(groupContentCustodyKind) ||
        raw.contains('contentEventId') ||
        raw.contains('authorityEventAt') ||
        raw.contains('authorityEventId') ||
        raw.contains('authorityKeyEpoch');
  }
  if (wrapper['custodyKind'] == groupContentCustodyKind) return true;
  final message = wrapper['message'];
  final envelope = message is String ? _decodeStringMap(message) : null;
  if (envelope == null) {
    return raw.contains(groupContentCustodyKind) ||
        raw.contains('contentEventId') ||
        raw.contains('authorityEventAt') ||
        raw.contains('authorityEventId') ||
        raw.contains('authorityKeyEpoch');
  }
  if (envelope['custodyKind'] == groupContentCustodyKind ||
      envelope.containsKey('contentEventId') ||
      envelope.containsKey('authorityEventAt') ||
      envelope.containsKey('authorityEventId') ||
      envelope.containsKey('authorityKeyEpoch')) {
    return true;
  }
  final signedRaw = envelope['signedPayload'];
  final signed = signedRaw is String ? _decodeStringMap(signedRaw) : null;
  return signedRaw is String &&
      (signedRaw.contains(groupContentCustodyKind) ||
          signedRaw.contains('contentEventId') ||
          signedRaw.contains('authorityEventAt') ||
          signedRaw.contains('authorityEventId') ||
          signedRaw.contains('authorityKeyEpoch') ||
          signed?['custodyKind'] == groupContentCustodyKind);
}

/// Sender-authored, content-free notification hints that are signed separately
/// from the byte-compatible v1 replay payload. Display authority remains local
/// to the recipient; this extension only allows the relay to select a typed
/// wake and a transition identity.
class GroupReactionNotificationExtensionInput {
  const GroupReactionNotificationExtensionInput({
    required this.transitionId,
    required this.action,
    required this.targetMessageId,
    required this.reactorPeerId,
    required this.reactorTransportPeerId,
    required this.notificationRecipientTransportPeerIds,
  });

  final String transitionId;
  final String action;
  final String targetMessageId;
  final String reactorPeerId;
  final String reactorTransportPeerId;
  final List<String> notificationRecipientTransportPeerIds;
}

class GroupOfflineReplaySignatureException implements Exception {
  GroupOfflineReplaySignatureException(this.reason);

  final String reason;

  @override
  String toString() => 'GroupOfflineReplaySignatureException($reason)';
}

enum GroupOfflineReplayPreparationOperation { groupEncrypt, payloadSign }

/// Opt-in classification for the two native crypto operations used while
/// preparing a replay envelope. Other validation and state failures retain
/// their original exception identity so callers can keep them fail-closed.
class GroupOfflineReplayPreparationException implements Exception {
  const GroupOfflineReplayPreparationException({
    required this.operation,
    required this.cause,
  });

  final GroupOfflineReplayPreparationOperation operation;
  final Object cause;

  @override
  String toString() =>
      'GroupOfflineReplayPreparationException(${operation.name})';
}

class _ReplaySignatureVerification {
  const _ReplaySignatureVerification({
    required this.payloadType,
    required this.groupId,
    required this.keyEpoch,
    required this.messageId,
    required this.senderPeerId,
    required this.senderPublicKey,
    required this.senderDeviceId,
    required this.senderTransportPeerId,
    required this.plaintextHash,
    required this.contentEventId,
    required this.contentAuthorityVersion,
    required this.recipientPeerIds,
    required this.mediaManifest,
    required this.mediaManifestHash,
    this.reactionNotificationExtension,
  });

  final String payloadType;
  final String groupId;
  final int keyEpoch;
  final String? messageId;
  final String senderPeerId;
  final String senderPublicKey;
  final String? senderDeviceId;
  final String? senderTransportPeerId;
  final String plaintextHash;
  final String? contentEventId;
  final GroupContentAuthorityVersion? contentAuthorityVersion;
  final List<String> recipientPeerIds;
  final ProtectedGroupMediaManifest? mediaManifest;
  final String? mediaManifestHash;
  final _VerifiedGroupReactionNotificationExtension?
  reactionNotificationExtension;
}

class _VerifiedGroupReactionNotificationExtension {
  const _VerifiedGroupReactionNotificationExtension({
    required this.transitionId,
    required this.action,
    required this.targetMessageId,
    required this.reactorPeerId,
    required this.reactorTransportPeerId,
  });

  final String transitionId;
  final String action;
  final String targetMessageId;
  final String reactorPeerId;
  final String reactorTransportPeerId;
}

const Set<String> _reactionNotificationExtensionKeys = <String>{
  'version',
  'transitionId',
  'action',
  'targetMessageId',
  'reactorPeerId',
  'reactorTransportPeerId',
  'replayRecipientSetHash',
  'notificationRecipientTransportPeerIds',
  'baseEnvelopeHash',
  'signatureAlgorithm',
  'signedPayload',
  'signature',
};

const Set<String> _strictGroupContentEnvelopeKeys = <String>{
  'kind',
  'version',
  'groupId',
  'payloadType',
  'keyEpoch',
  'messageId',
  'senderPeerId',
  'senderDeviceId',
  'senderTransportPeerId',
  'senderPublicKey',
  'senderKeyPackageId',
  'recipientPeerIds',
  'recipientSetHash',
  'ciphertext',
  'nonce',
  'signatureAlgorithm',
  'signedPayload',
  'signature',
  'custodyKind',
  'contentEventId',
  'authorityEventAt',
  'authorityEventId',
  'authorityKeyEpoch',
  'mediaManifest',
  'mediaManifestHash',
  'notificationExtension',
};

void _requireStrictGroupContentEnvelopeKeySet(Map<String, Object?> envelope) {
  final keys = envelope.keys.toSet();
  if (keys.any((key) => !_strictGroupContentEnvelopeKeys.contains(key))) {
    throw GroupOfflineReplaySignatureException(
      'protected_envelope_key_set_invalid',
    );
  }
  for (final required in const <String>[
    'kind',
    'version',
    'groupId',
    'payloadType',
    'keyEpoch',
    'messageId',
    'senderPeerId',
    'senderDeviceId',
    'senderTransportPeerId',
    'senderPublicKey',
    'recipientSetHash',
    'ciphertext',
    'nonce',
    'signatureAlgorithm',
    'signedPayload',
    'signature',
    'custodyKind',
    'contentEventId',
    'authorityEventAt',
    'authorityEventId',
    'authorityKeyEpoch',
  ]) {
    if (!keys.contains(required)) {
      throw GroupOfflineReplaySignatureException(
        'protected_envelope_key_set_invalid',
      );
    }
  }
}

Future<String> buildGroupOfflineReplayEnvelope({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String payloadType,
  required String plaintext,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  GroupKeyInfo? keyInfo,
  String? messageId,
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderKeyPackageId,
  List<String>? recipientPeerIds,
  GroupReactionNotificationExtensionInput? reactionNotificationExtension,
  GroupContentAuthorityVersion? contentAuthorityVersion,
  String? contentEventId,
  ProtectedGroupMediaManifest? mediaManifest,
  bool classifyPreparationCryptoFailures = false,
}) async {
  final resolvedKey = keyInfo ?? await _loadReplayKey(groupRepo, groupId);
  final strictContent =
      contentAuthorityVersion != null || _trimToNull(contentEventId) != null;
  if (strictContent &&
      (contentAuthorityVersion == null ||
          _trimToNull(contentEventId) == null)) {
    throw ArgumentError('strict group content requires authority and event id');
  }
  if (strictContent &&
      payloadType != groupOfflineReplayPayloadTypeMessage &&
      payloadType != groupOfflineReplayPayloadTypeReaction) {
    throw ArgumentError('unsupported strict group content payload type');
  }
  if (strictContent &&
      payloadType == groupOfflineReplayPayloadTypeReaction &&
      reactionNotificationExtension == null) {
    throw ArgumentError('strict group reaction requires notification binding');
  }
  if (mediaManifest != null &&
      (!strictContent || payloadType != groupOfflineReplayPayloadTypeMessage)) {
    throw ArgumentError(
      'group media manifest requires protected message content',
    );
  }
  if (contentAuthorityVersion != null &&
      (contentAuthorityVersion.keyEpoch < 0 ||
          contentAuthorityVersion.keyEpoch != resolvedKey.keyGeneration)) {
    throw ArgumentError('group content authority/key epoch mismatch');
  }
  final normalizedRecipientPeerIds = strictContent
      ? _strictSortedUniqueRecipients(
          recipientPeerIds ?? const <String>[],
          'recipientPeerIds',
        )
      : _normalizedRecipientPeerIds(recipientPeerIds);
  final normalizedContentEventId = _trimToNull(contentEventId);
  if (strictContent) {
    _strictGroupContentWireId(groupId, 'groupId');
    _strictGroupContentWireId(normalizedContentEventId, 'contentEventId');
    if (_trimToNull(messageId) != normalizedContentEventId) {
      throw ArgumentError(
        'strict group content messageId must equal contentEventId',
      );
    }
  }
  final encodedMediaManifest = mediaManifest?.encode();
  final mediaManifestHash = mediaManifest?.fingerprintSha256;
  if (mediaManifest != null &&
      (!mediaManifest.matchesAuthority(
            expectedGroupId: groupId,
            expectedMessageId: normalizedContentEventId!,
            expectedRecipientPeerIds: normalizedRecipientPeerIds,
          ) ||
          ProtectedGroupMediaManifest.decode(encodedMediaManifest!).encode() !=
              encodedMediaManifest)) {
    throw ArgumentError('group media manifest authority mismatch');
  }
  final contentAuthorityAt = contentAuthorityVersion == null
      ? null
      : fixedGroupContentUtc(contentAuthorityVersion.eventAt);
  final contentAuthorityEventId = contentAuthorityVersion == null
      ? null
      : _strictGroupContentWireId(
          contentAuthorityVersion.eventId,
          'authorityEventId',
        );
  var protectedPlaintext = plaintext;
  if (strictContent) {
    final decoded = _decodeStringMap(plaintext);
    if (decoded == null) {
      throw ArgumentError('strict group content plaintext must be an object');
    }
    final strictFields = <String, Object?>{
      'groupId': groupId,
      'keyEpoch': resolvedKey.keyGeneration,
      'senderDeviceId': _requiredTrimmed(
        senderDeviceId ?? '',
        'senderDeviceId',
      ),
      'transportPeerId': _requiredTrimmed(
        senderTransportPeerId ?? '',
        'senderTransportPeerId',
      ),
      'custodyKind': groupContentCustodyKind,
      'contentEventId': normalizedContentEventId,
      'authorityEventAt': contentAuthorityAt,
      'authorityEventId': contentAuthorityEventId,
      'authorityKeyEpoch': contentAuthorityVersion!.keyEpoch,
      'recipientPeerIds': normalizedRecipientPeerIds,
      'mediaManifest': ?encodedMediaManifest,
      'mediaManifestHash': ?mediaManifestHash,
    };
    for (final entry in strictFields.entries) {
      if (decoded.containsKey(entry.key) && decoded[entry.key] != entry.value) {
        throw ArgumentError('crossed strict content field ${entry.key}');
      }
      decoded[entry.key] = entry.value;
    }
    protectedPlaintext = jsonEncode(decoded);
  }
  Future<Map<String, dynamic>> encryptReplayPayload() async {
    final result = await callGroupEncrypt(
      bridge,
      resolvedKey.encryptedKey,
      protectedPlaintext,
    );
    final ciphertext = result['ciphertext'];
    final nonce = result['nonce'];
    if (result['ok'] != true ||
        ciphertext is! String ||
        ciphertext.isEmpty ||
        nonce is! String ||
        nonce.isEmpty) {
      throw BridgeCommandException(
        'group.encrypt',
        result['errorCode']?.toString() ?? 'GROUP_ENCRYPT_FAILED',
        result['errorMessage']?.toString() ??
            'group.encrypt did not return ciphertext and nonce',
      );
    }
    return result;
  }

  final encryptResult = classifyPreparationCryptoFailures
      ? await _classifyReplayPreparationFailure(
          operation: GroupOfflineReplayPreparationOperation.groupEncrypt,
          action: encryptReplayPayload,
        )
      : await encryptReplayPayload();
  final ciphertext = encryptResult['ciphertext'] as String;
  final nonce = encryptResult['nonce'] as String;

  final resolvedSenderPeerId = _requiredTrimmed(senderPeerId, 'senderPeerId');
  final resolvedSenderPublicKey = _requiredTrimmed(
    senderPublicKey,
    'senderPublicKey',
  );
  final normalizedDeviceId =
      _trimToNull(senderDeviceId) ?? resolvedSenderPeerId;
  final normalizedTransportPeerId =
      _trimToNull(senderTransportPeerId) ?? normalizedDeviceId;
  final normalizedMessageId = _trimToNull(messageId);
  final relayVisibleMessageId = strictContent
      ? normalizedContentEventId
      : _relayVisibleReplayMessageId(normalizedMessageId);
  final recipientSetHash = _recipientSetHashFromNormalized(
    normalizedRecipientPeerIds,
  );
  final normalizedSenderKeyPackageId = _trimToNull(senderKeyPackageId);
  final signedPayload = _buildReplaySignedPayload(
    groupId: groupId,
    payloadType: payloadType,
    keyEpoch: resolvedKey.keyGeneration,
    ciphertext: ciphertext,
    nonce: nonce,
    plaintext: protectedPlaintext,
    messageId: relayVisibleMessageId,
    senderPeerId: resolvedSenderPeerId,
    senderDeviceId: normalizedDeviceId,
    senderTransportPeerId: normalizedTransportPeerId,
    senderPublicKey: resolvedSenderPublicKey,
    senderKeyPackageId: normalizedSenderKeyPackageId,
    recipientSetHash: recipientSetHash,
    recipientPeerIds: strictContent ? normalizedRecipientPeerIds : null,
    contentEventId: normalizedContentEventId,
    contentAuthorityVersion: contentAuthorityVersion,
    mediaManifestHash: mediaManifestHash,
  );
  Future<String> signReplayPayload() async {
    final result = await callSignPayload(
      bridge: bridge,
      dataToSign: signedPayload,
      privateKey: senderPrivateKey,
    );
    final signature = result['signature'];
    if (result['ok'] != true || signature is! String || signature.isEmpty) {
      throw StateError('Failed to sign group offline replay envelope');
    }
    return signature;
  }

  final signature = classifyPreparationCryptoFailures
      ? await _classifyReplayPreparationFailure(
          operation: GroupOfflineReplayPreparationOperation.payloadSign,
          action: signReplayPayload,
        )
      : await signReplayPayload();

  final baseEnvelope = <String, Object?>{
    'kind': groupOfflineReplayEnvelopeKind,
    'version': groupOfflineReplayEnvelopeVersion,
    'groupId': groupId,
    'payloadType': payloadType,
    'keyEpoch': resolvedKey.keyGeneration,
    'messageId': ?relayVisibleMessageId,
    'senderPeerId': resolvedSenderPeerId,
    'senderDeviceId': normalizedDeviceId,
    'senderTransportPeerId': normalizedTransportPeerId,
    'senderPublicKey': resolvedSenderPublicKey,
    'senderKeyPackageId': ?normalizedSenderKeyPackageId,
    if (normalizedRecipientPeerIds.isNotEmpty)
      'recipientPeerIds': normalizedRecipientPeerIds,
    'recipientSetHash': recipientSetHash,
    'ciphertext': ciphertext,
    'nonce': nonce,
    'signatureAlgorithm': groupOfflineReplaySignatureAlgorithm,
    'signedPayload': signedPayload,
    'signature': signature,
    if (strictContent) 'custodyKind': groupContentCustodyKind,
    if (strictContent) 'contentEventId': normalizedContentEventId,
    if (strictContent) 'authorityEventAt': contentAuthorityAt,
    if (strictContent) 'authorityEventId': contentAuthorityEventId,
    if (strictContent) 'authorityKeyEpoch': contentAuthorityVersion!.keyEpoch,
    'mediaManifest': ?encodedMediaManifest,
    'mediaManifestHash': ?mediaManifestHash,
  };

  final notificationInput = reactionNotificationExtension;
  if (notificationInput == null) {
    return jsonEncode(baseEnvelope);
  }
  if (payloadType != groupOfflineReplayPayloadTypeReaction) {
    throw ArgumentError(
      'Reaction notification extensions require payloadType=group_reaction',
    );
  }
  final extension = await _buildGroupReactionNotificationExtension(
    bridge: bridge,
    baseEnvelope: baseEnvelope,
    input: notificationInput,
    senderPeerId: resolvedSenderPeerId,
    senderTransportPeerId: normalizedTransportPeerId,
    senderPrivateKey: senderPrivateKey,
    replayRecipientPeerIds: normalizedRecipientPeerIds,
    replayRecipientSetHash: recipientSetHash,
  );
  return jsonEncode({...baseEnvelope, 'notificationExtension': extension});
}

Future<T> _classifyReplayPreparationFailure<T>({
  required GroupOfflineReplayPreparationOperation operation,
  required Future<T> Function() action,
}) async {
  try {
    return await action();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(
      GroupOfflineReplayPreparationException(
        operation: operation,
        cause: error,
      ),
      stackTrace,
    );
  }
}

Future<void> storeGroupOfflineReplayEnvelope({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String payloadType,
  required String plaintext,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  GroupKeyInfo? keyInfo,
  String? messageId,
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderKeyPackageId,
  List<String>? recipientPeerIds,
  bool preserveRecipientPeerIds = false,
  GroupReactionNotificationExtensionInput? reactionNotificationExtension,
  GroupContentAuthorityVersion? contentAuthorityVersion,
  String? contentEventId,
  ProtectedGroupMediaManifest? mediaManifest,
}) async {
  final replayEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    payloadType: payloadType,
    plaintext: plaintext,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderPrivateKey: senderPrivateKey,
    keyInfo: keyInfo,
    messageId: messageId,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    senderKeyPackageId: senderKeyPackageId,
    recipientPeerIds: recipientPeerIds,
    reactionNotificationExtension: reactionNotificationExtension,
    contentAuthorityVersion: contentAuthorityVersion,
    contentEventId: contentEventId,
    mediaManifest: mediaManifest,
  );

  await callGroupInboxStore(
    bridge,
    groupId,
    replayEnvelope,
    recipientPeerIds: recipientPeerIds,
    preserveRecipientPeerIds: preserveRecipientPeerIds,
  );
}

Future<Map<String, Object?>> _buildGroupReactionNotificationExtension({
  required Bridge bridge,
  required Map<String, Object?> baseEnvelope,
  required GroupReactionNotificationExtensionInput input,
  required String senderPeerId,
  required String senderTransportPeerId,
  required String senderPrivateKey,
  required List<String> replayRecipientPeerIds,
  required String replayRecipientSetHash,
}) async {
  final transitionId = _requiredTrimmed(input.transitionId, 'transitionId');
  final action = _requiredTrimmed(input.action, 'action');
  if (action != 'add' && action != 'remove') {
    throw ArgumentError.value(action, 'action', 'must be add or remove');
  }
  final targetMessageId = _requiredTrimmed(
    input.targetMessageId,
    'targetMessageId',
  );
  final reactorPeerId = _requiredTrimmed(input.reactorPeerId, 'reactorPeerId');
  final reactorTransportPeerId = _requiredTrimmed(
    input.reactorTransportPeerId,
    'reactorTransportPeerId',
  );
  if (reactorPeerId != senderPeerId ||
      reactorTransportPeerId != senderTransportPeerId) {
    throw ArgumentError(
      'Reaction notification actor must match the base replay sender',
    );
  }
  final notificationRecipients = _normalizedRecipientPeerIds(
    input.notificationRecipientTransportPeerIds,
  );
  final replayRecipients = replayRecipientPeerIds.toSet();
  if (notificationRecipients.any(
    (recipient) => !replayRecipients.contains(recipient),
  )) {
    throw ArgumentError(
      'Reaction notification recipients must be a replay-recipient subset',
    );
  }

  final baseEnvelopeHash = _hashString(
    canonicalizeGroupEventLogPayload(baseEnvelope),
  );
  final signedPayload = canonicalizeGroupEventLogPayload({
    'kind': groupReactionNotificationExtensionKind,
    'version': groupReactionNotificationExtensionVersion,
    'transitionId': transitionId,
    'action': action,
    'targetMessageId': targetMessageId,
    'reactorPeerId': reactorPeerId,
    'reactorTransportPeerId': reactorTransportPeerId,
    'replayRecipientSetHash': replayRecipientSetHash,
    'notificationRecipientTransportPeerIds': notificationRecipients,
    'baseEnvelopeHash': baseEnvelopeHash,
  });
  final signResult = await callSignPayload(
    bridge: bridge,
    dataToSign: signedPayload,
    privateKey: senderPrivateKey,
  );
  final signature = signResult['signature'];
  if (signResult['ok'] != true || signature is! String || signature.isEmpty) {
    throw StateError('Failed to sign group reaction notification extension');
  }

  return <String, Object?>{
    'version': groupReactionNotificationExtensionVersion,
    'transitionId': transitionId,
    'action': action,
    'targetMessageId': targetMessageId,
    'reactorPeerId': reactorPeerId,
    'reactorTransportPeerId': reactorTransportPeerId,
    'replayRecipientSetHash': replayRecipientSetHash,
    'notificationRecipientTransportPeerIds': notificationRecipients,
    'baseEnvelopeHash': baseEnvelopeHash,
    'signatureAlgorithm': groupOfflineReplaySignatureAlgorithm,
    'signedPayload': signedPayload,
    'signature': signature,
  };
}

String encodeGroupOfflineReplayInboxRetryPayload({
  required String groupId,
  required String message,
  List<String>? recipientPeerIds,
}) {
  return jsonEncode({
    'groupId': groupId,
    'message': message,
    'recipientPeerIds': ?recipientPeerIds,
  });
}

Future<String> buildGroupOfflineReplayInboxRetryPayload({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String payloadType,
  required String plaintext,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  GroupKeyInfo? keyInfo,
  String? messageId,
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderKeyPackageId,
  List<String>? recipientPeerIds,
  GroupReactionNotificationExtensionInput? reactionNotificationExtension,
  GroupContentAuthorityVersion? contentAuthorityVersion,
  String? contentEventId,
  ProtectedGroupMediaManifest? mediaManifest,
}) async {
  if (contentAuthorityVersion != null &&
      (recipientPeerIds == null || recipientPeerIds.isEmpty)) {
    throw ArgumentError(
      'zero-target strict content is local terminal and has no retry wrapper',
    );
  }
  final replayEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    payloadType: payloadType,
    plaintext: plaintext,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderPrivateKey: senderPrivateKey,
    keyInfo: keyInfo,
    messageId: messageId,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    senderKeyPackageId: senderKeyPackageId,
    recipientPeerIds: recipientPeerIds,
    reactionNotificationExtension: reactionNotificationExtension,
    contentAuthorityVersion: contentAuthorityVersion,
    contentEventId: contentEventId,
    mediaManifest: mediaManifest,
  );

  if (contentAuthorityVersion != null) {
    return jsonEncode(<String, Object?>{
      'groupId': groupId,
      'message': replayEnvelope,
      'custodyContract': ackOrExpiryInboxCustodyContract,
      'custodyKind': groupContentCustodyKind,
      'recipientPeerIds': _strictSortedUniqueRecipients(
        recipientPeerIds ?? const <String>[],
        'recipientPeerIds',
      ),
    });
  }
  return encodeGroupOfflineReplayInboxRetryPayload(
    groupId: groupId,
    message: replayEnvelope,
    recipientPeerIds: recipientPeerIds,
  );
}

Future<void> storeGroupOfflineReplayFromRetryPayload({
  required Bridge bridge,
  required String inboxRetryPayload,
}) async {
  final payload = jsonDecode(inboxRetryPayload) as Map<String, dynamic>;
  final groupId = payload['groupId'] as String;
  final message = payload['message'] as String;
  final preservesRecipientPeerIds = payload.containsKey('recipientPeerIds');
  final recipientPeerIds = (payload['recipientPeerIds'] as List<dynamic>?)
      ?.cast<String>();
  await callGroupInboxStore(
    bridge,
    groupId,
    message,
    recipientPeerIds: recipientPeerIds,
    preserveRecipientPeerIds: preservesRecipientPeerIds,
  );
}

Future<InboxStoreOutcome> storeGroupContentRetryRecipient({
  required AckOrExpiryInboxStore store,
  required String inboxRetryPayload,
  required String recipientPeerId,
}) async {
  final decoded = GroupContentRetryPayload.decode(inboxRetryPayload);
  final recipient = recipientPeerId.trim();
  if (recipient.isEmpty ||
      !decoded.pendingRecipientPeerIds.contains(recipient) ||
      !decoded.fullRecipientPeerIds.contains(recipient)) {
    throw const FormatException('recipient is not pending group content');
  }
  final manifest = decoded.mediaManifest;
  final InboxStoreOutcome outcome;
  if (manifest == null) {
    outcome = await store.storeInAckCustodyInboxDetailed(
      recipient,
      decoded.message,
      custodyKind: AckCustodyKind.groupContentV1,
    );
  } else {
    if (store is! GroupContentExpiryBoundedInboxStore) {
      throw StateError('group media content expiry capability unavailable');
    }
    final boundedStore = store as GroupContentExpiryBoundedInboxStore;
    final ceiling = manifest.contentExpiresAtOrBeforeMsFor(recipient);
    outcome = await boundedStore.storeInGroupContentExpiryBoundedInboxDetailed(
      recipient,
      decoded.message,
      custodyExpiresAtOrBeforeMs: ceiling,
    );
    if (outcome.expiresAtMs != ceiling) {
      throw StateError('group content custody expiry proof mismatch');
    }
  }
  if (!outcome.ackOrExpiryAccepted) {
    throw StateError('group content custody was not accepted');
  }
  return outcome;
}

String buildGroupReactionTransitionId({
  required String groupId,
  required String messageId,
  required String logicalActorPeerId,
  required String action,
  required String emoji,
  required DateTime timestamp,
}) {
  final fixedTimestamp = fixedGroupContentUtc(timestamp);
  final stateDigest = _hashString(
    jsonEncode(<String>[
      'group_reaction_state_v1',
      groupId,
      messageId,
      logicalActorPeerId,
    ]),
  ).substring(0, 32);
  final eventDigest = _hashString(
    jsonEncode(<String>[
      'group_reaction_event_v1',
      stateDigest,
      action,
      emoji,
      fixedTimestamp,
    ]),
  ).substring(0, 32);
  final epochMicros = timestamp.toUtc().microsecondsSinceEpoch;
  if (epochMicros < 0 || epochMicros.toString().length > 20) {
    throw RangeError.value(epochMicros, 'timestamp');
  }
  return 'gr1:$stateDigest:${epochMicros.toString().padLeft(20, '0')}:'
      '$eventDigest';
}

String deterministicGroupReactionStateId({
  required String groupId,
  required String messageId,
  required String logicalActorPeerId,
}) {
  final digest = _hashString(
    jsonEncode(<String>[
      'group_reaction_state_v1',
      groupId,
      messageId,
      logicalActorPeerId,
    ]),
  ).substring(0, 32);
  return 'group-reaction-state-$digest';
}

bool isGroupOfflineReplayEnvelope(Map<String, dynamic> envelope) {
  return envelope['kind'] == groupOfflineReplayEnvelopeKind &&
      envelope['ciphertext'] is String &&
      envelope['nonce'] is String &&
      envelope['keyEpoch'] is int;
}

Future<String> decryptGroupOfflineReplayEnvelope({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required Map<String, dynamic> envelope,
  String? expectedRelayPeerId,
  String? expectedRecipientPeerId,
}) async {
  final verification = await _verifyReplaySignature(
    bridge: bridge,
    groupRepo: groupRepo,
    fallbackGroupId: groupId,
    envelope: envelope,
    expectedRelayPeerId: expectedRelayPeerId,
    expectedRecipientPeerId: expectedRecipientPeerId,
  );
  final keyEpoch = envelope['keyEpoch'] as int;
  final keyInfo = await groupRepo.getKeyByGeneration(groupId, keyEpoch);
  if (keyInfo == null) {
    throw StateError(
      'Missing group replay key for group $groupId at epoch $keyEpoch',
    );
  }

  return callGroupDecrypt(
    bridge,
    keyInfo.encryptedKey,
    envelope['ciphertext'] as String,
    envelope['nonce'] as String,
  ).then((plaintext) {
    _verifyPlaintextBinding(plaintext, verification, fallbackGroupId: groupId);
    return plaintext;
  });
}

/// Verifies and decrypts strict content against the exact historical authority
/// named by its signed body. The injected verifier is the only supported
/// bypass of current-roster device checks; legacy replay keeps using
/// [decryptGroupOfflineReplayEnvelope].
Future<VerifiedGroupContentReplay> decryptVerifiedGroupContentReplay({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required Map<String, dynamic> envelope,
  required VerifyHistoricalGroupContentSigner verifyHistoricalSigner,
  String? expectedRelayPeerId,
  String? expectedRecipientPeerId,
}) async {
  final verification = await _verifyReplaySignature(
    bridge: bridge,
    groupRepo: groupRepo,
    fallbackGroupId: groupId,
    envelope: envelope,
    expectedRelayPeerId: expectedRelayPeerId,
    expectedRecipientPeerId: expectedRecipientPeerId,
    verifyHistoricalSigner: verifyHistoricalSigner,
  );
  final authority = verification.contentAuthorityVersion;
  final contentEventId = verification.contentEventId;
  final deviceId = verification.senderDeviceId;
  final transportPeerId = verification.senderTransportPeerId;
  if (authority == null ||
      contentEventId == null ||
      deviceId == null ||
      transportPeerId == null) {
    throw GroupOfflineReplaySignatureException('not_protected_content');
  }
  final keyInfo = await groupRepo.getKeyByGeneration(
    groupId,
    verification.keyEpoch,
  );
  if (keyInfo == null) {
    throw StateError(
      'Missing group replay key for group $groupId at epoch '
      '${verification.keyEpoch}',
    );
  }
  final plaintext = await callGroupDecrypt(
    bridge,
    keyInfo.encryptedKey,
    envelope['ciphertext'] as String,
    envelope['nonce'] as String,
  );
  _verifyPlaintextBinding(plaintext, verification, fallbackGroupId: groupId);
  return VerifiedGroupContentReplay(
    plaintext: plaintext,
    groupId: verification.groupId,
    payloadType: verification.payloadType,
    contentEventId: contentEventId,
    authorityVersion: authority,
    logicalSenderPeerId: verification.senderPeerId,
    senderDeviceId: deviceId,
    senderTransportPeerId: transportPeerId,
    senderPublicKey: verification.senderPublicKey,
    recipientPeerIds: List<String>.unmodifiable(verification.recipientPeerIds),
    keyEpoch: verification.keyEpoch,
    mediaManifest: verification.mediaManifest,
    mediaManifestHash: verification.mediaManifestHash,
  );
}

Future<_ReplaySignatureVerification> _verifyReplaySignature({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String fallbackGroupId,
  required Map<String, dynamic> envelope,
  String? expectedRelayPeerId,
  String? expectedRecipientPeerId,
  VerifyHistoricalGroupContentSigner? verifyHistoricalSigner,
}) async {
  if (envelope['kind'] != groupOfflineReplayEnvelopeKind) {
    throw GroupOfflineReplaySignatureException('envelope_kind_invalid');
  }
  final groupId = _readRequiredString(
    envelope,
    'groupId',
    reason: 'missing_group_id',
  );
  if (groupId != fallbackGroupId) {
    throw GroupOfflineReplaySignatureException('group_mismatch');
  }
  final payloadType = _readRequiredString(
    envelope,
    'payloadType',
    reason: 'missing_payload_type',
  );
  if (envelope['version'] != groupOfflineReplayEnvelopeVersion) {
    throw GroupOfflineReplaySignatureException('envelope_version_invalid');
  }
  final keyEpoch = envelope['keyEpoch'];
  if (keyEpoch is! int || keyEpoch < 0) {
    throw GroupOfflineReplaySignatureException('missing_key_epoch');
  }
  final ciphertext = _readRequiredString(
    envelope,
    'ciphertext',
    reason: 'missing_ciphertext',
  );
  final nonce = _readRequiredString(envelope, 'nonce', reason: 'missing_nonce');
  final senderPeerId = _readRequiredString(
    envelope,
    'senderPeerId',
    reason: 'missing_sender',
  );
  final senderPublicKey = _readRequiredString(
    envelope,
    'senderPublicKey',
    reason: 'missing_sender_key',
  );
  final senderDeviceId = _trimToNull(envelope['senderDeviceId'] as String?);
  final senderTransportPeerId = _trimToNull(
    envelope['senderTransportPeerId'] as String?,
  );
  final senderKeyPackageId = _trimToNull(
    envelope['senderKeyPackageId'] as String?,
  );
  final messageId = _trimToNull(envelope['messageId'] as String?);
  final recipientSetHash = _readRequiredString(
    envelope,
    'recipientSetHash',
    reason: 'missing_recipient_hash',
  );
  final custodyKind = _trimToNull(envelope['custodyKind'] as String?);
  if (custodyKind != null && custodyKind != groupContentCustodyKind) {
    throw GroupOfflineReplaySignatureException('custody_kind_invalid');
  }
  final isProtectedContent = custodyKind == groupContentCustodyKind;
  if (isProtectedContent) {
    _requireStrictGroupContentEnvelopeKeySet(envelope);
    _requireExactReplayStrings(envelope);
  }
  if (isProtectedContent &&
      payloadType != groupOfflineReplayPayloadTypeMessage &&
      payloadType != groupOfflineReplayPayloadTypeReaction) {
    throw GroupOfflineReplaySignatureException(
      'protected_payload_type_invalid',
    );
  }
  final recipientPeerIds = isProtectedContent
      ? _readExactRecipientPeerIds(
          envelope['recipientPeerIds'],
          reason: 'recipient_list_malformed',
        )
      : _readOptionalRecipientPeerIds(envelope['recipientPeerIds']);
  if (recipientPeerIds != null &&
      _recipientSetHashFromNormalized(recipientPeerIds) != recipientSetHash) {
    throw GroupOfflineReplaySignatureException('recipient_hash_mismatch');
  }
  final expectedRecipient = _trimToNull(expectedRecipientPeerId);
  if (expectedRecipient != null &&
      recipientPeerIds != null &&
      !recipientPeerIds.contains(expectedRecipient)) {
    throw GroupOfflineReplaySignatureException('recipient_not_entitled');
  }

  if (envelope['signatureAlgorithm'] != groupOfflineReplaySignatureAlgorithm) {
    throw GroupOfflineReplaySignatureException('signature_algorithm_invalid');
  }
  final signedPayload = _readRequiredString(
    envelope,
    'signedPayload',
    reason: 'missing_signed_payload',
  );
  final signature = _readRequiredString(
    envelope,
    'signature',
    reason: 'missing_signature',
  );
  final decodedSignedPayload = _decodeStringMap(signedPayload);
  if (decodedSignedPayload == null ||
      canonicalizeGroupEventLogPayload(decodedSignedPayload) != signedPayload) {
    throw GroupOfflineReplaySignatureException('signed_payload_malformed');
  }

  final plaintextHash = _readRequiredString(
    decodedSignedPayload,
    'plaintextHash',
    reason: 'missing_plaintext_hash',
  );
  String? contentEventId;
  GroupContentAuthorityVersion? contentAuthorityVersion;
  if (isProtectedContent) {
    contentEventId = _readRequiredString(
      envelope,
      'contentEventId',
      reason: 'missing_content_event_id',
    );
    final authorityEventAt = parseFixedGroupContentUtc(
      envelope['authorityEventAt'],
    );
    final authorityEventId = _readRequiredString(
      envelope,
      'authorityEventId',
      reason: 'missing_authority_event_id',
    );
    final authorityKeyEpoch = envelope['authorityKeyEpoch'];
    if (authorityEventAt == null ||
        authorityKeyEpoch is! int ||
        authorityKeyEpoch < 0 ||
        messageId != contentEventId ||
        authorityKeyEpoch != keyEpoch) {
      throw GroupOfflineReplaySignatureException('authority_version_invalid');
    }
    contentAuthorityVersion = GroupContentAuthorityVersion(
      eventAt: authorityEventAt,
      eventId: authorityEventId,
      keyEpoch: authorityKeyEpoch,
    );
  }
  final manifestBinding = isProtectedContent
      ? _decodeProtectedGroupMediaManifestBinding(
          envelope: envelope,
          signedPayload: decodedSignedPayload,
          groupId: groupId,
          contentEventId: contentEventId!,
          recipientPeerIds: recipientPeerIds ?? const <String>[],
          payloadType: payloadType,
          invalid: (reason) =>
              throw GroupOfflineReplaySignatureException(reason),
        )
      : (null, null, null);
  final expectedSignedPayload = _buildReplaySignedPayloadFromHashes(
    groupId: groupId,
    payloadType: payloadType,
    keyEpoch: keyEpoch,
    ciphertextHash: _hashString(ciphertext),
    nonceHash: _hashString(nonce),
    plaintextHash: plaintextHash,
    messageId: messageId,
    senderPeerId: senderPeerId,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    senderPublicKey: senderPublicKey,
    senderKeyPackageId: senderKeyPackageId,
    recipientSetHash: recipientSetHash,
    recipientPeerIds: isProtectedContent ? recipientPeerIds : null,
    contentEventId: contentEventId,
    contentAuthorityVersion: contentAuthorityVersion,
    mediaManifestHash: manifestBinding.$3,
  );
  if (expectedSignedPayload != signedPayload) {
    throw GroupOfflineReplaySignatureException('signed_payload_mismatch');
  }

  String signaturePublicKey;
  final historicalVerifier = verifyHistoricalSigner;
  if (historicalVerifier != null) {
    if (!isProtectedContent ||
        contentAuthorityVersion == null ||
        senderDeviceId == null ||
        senderTransportPeerId == null ||
        !await historicalVerifier(
          groupId: groupId,
          authorityVersion: contentAuthorityVersion,
          logicalSenderPeerId: senderPeerId,
          senderDeviceId: senderDeviceId,
          senderTransportPeerId: senderTransportPeerId,
          senderPublicKey: senderPublicKey,
        )) {
      throw GroupOfflineReplaySignatureException(
        'historical_sender_unauthorized',
      );
    }
    signaturePublicKey = senderPublicKey;
  } else {
    var member = await groupRepo.getMember(groupId, senderPeerId);
    var device = _resolveSigningDevice(
      member: member,
      senderPublicKey: senderPublicKey,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
    );
    if (member == null) {
      final snapshotRepo = groupRepo is RemovedGroupMemberSnapshotRepository
          ? groupRepo as RemovedGroupMemberSnapshotRepository
          : null;
      member = await snapshotRepo?.getRemovedMemberSnapshot(
        groupId,
        senderPeerId,
      );
      device = _resolveSigningDevice(
        member: member,
        senderPublicKey: senderPublicKey,
        senderDeviceId: senderDeviceId,
        senderTransportPeerId: senderTransportPeerId,
      );
      if (member == null || device == null) {
        throw GroupOfflineReplaySignatureException('unknown_sender');
      }
    }
    if (device == null) {
      final inactiveDevice = _resolveSigningDevice(
        member: member,
        senderPublicKey: senderPublicKey,
        senderDeviceId: senderDeviceId,
        senderTransportPeerId: senderTransportPeerId,
        activeOnly: false,
      );
      if (inactiveDevice != null && !inactiveDevice.isActive) {
        throw GroupOfflineReplaySignatureException('revoked_device');
      }
      throw GroupOfflineReplaySignatureException('unknown_sender');
    }
    if (device.deviceSigningPublicKey != senderPublicKey) {
      throw GroupOfflineReplaySignatureException('sender_key_mismatch');
    }
    if (senderDeviceId != null && device.deviceId != senderDeviceId) {
      throw GroupOfflineReplaySignatureException('sender_device_mismatch');
    }
    if (senderTransportPeerId != null &&
        device.transportPeerId != senderTransportPeerId) {
      throw GroupOfflineReplaySignatureException('sender_transport_mismatch');
    }
    signaturePublicKey = device.deviceSigningPublicKey;
  }

  final relayPeerId = _trimToNull(expectedRelayPeerId);
  if (relayPeerId != null &&
      (isProtectedContent
          ? relayPeerId != senderTransportPeerId
          : relayPeerId != senderPeerId &&
                relayPeerId != senderTransportPeerId)) {
    throw GroupOfflineReplaySignatureException('relay_sender_mismatch');
  }

  final validSignature = await callVerifyPayload(
    bridge: bridge,
    publicKey: signaturePublicKey,
    data: signedPayload,
    signature: signature,
  );
  if (!validSignature) {
    throw GroupOfflineReplaySignatureException('signature_invalid');
  }

  final reactionNotificationExtension =
      await _verifyGroupReactionNotificationExtension(
        bridge: bridge,
        envelope: envelope,
        payloadType: payloadType,
        senderPeerId: senderPeerId,
        senderTransportPeerId: senderTransportPeerId,
        senderPublicKey: senderPublicKey,
        replayRecipientPeerIds: recipientPeerIds ?? const <String>[],
        replayRecipientSetHash: recipientSetHash,
      );
  if (isProtectedContent &&
      payloadType == groupOfflineReplayPayloadTypeReaction &&
      (reactionNotificationExtension == null ||
          reactionNotificationExtension.transitionId != contentEventId ||
          GroupReactionTransitionOrder.tryParse(contentEventId) == null)) {
    throw GroupOfflineReplaySignatureException(
      'protected_reaction_authority_invalid',
    );
  }

  return _ReplaySignatureVerification(
    payloadType: payloadType,
    groupId: groupId,
    keyEpoch: keyEpoch,
    messageId: messageId,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    plaintextHash: plaintextHash,
    contentEventId: contentEventId,
    contentAuthorityVersion: contentAuthorityVersion,
    recipientPeerIds: recipientPeerIds ?? const <String>[],
    mediaManifest: manifestBinding.$1,
    mediaManifestHash: manifestBinding.$3,
    reactionNotificationExtension: reactionNotificationExtension,
  );
}

Future<_VerifiedGroupReactionNotificationExtension?>
_verifyGroupReactionNotificationExtension({
  required Bridge bridge,
  required Map<String, dynamic> envelope,
  required String payloadType,
  required String senderPeerId,
  required String? senderTransportPeerId,
  required String senderPublicKey,
  required List<String> replayRecipientPeerIds,
  required String replayRecipientSetHash,
}) async {
  final rawExtension = envelope['notificationExtension'];
  if (rawExtension == null) return null;
  if (payloadType != groupOfflineReplayPayloadTypeReaction ||
      rawExtension is! Map) {
    throw GroupOfflineReplaySignatureException(
      'notification_extension_malformed',
    );
  }
  final extension = rawExtension.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
  if (extension.keys.toSet().length !=
          _reactionNotificationExtensionKeys.length ||
      !extension.keys.toSet().containsAll(_reactionNotificationExtensionKeys)) {
    throw GroupOfflineReplaySignatureException(
      'notification_extension_key_set_invalid',
    );
  }
  _requireExactNotificationExtensionStrings(extension);
  if (extension['version'] != groupReactionNotificationExtensionVersion ||
      extension['signatureAlgorithm'] != groupOfflineReplaySignatureAlgorithm) {
    throw GroupOfflineReplaySignatureException(
      'notification_extension_version_invalid',
    );
  }
  final transitionId = _readRequiredString(
    extension,
    'transitionId',
    reason: 'notification_transition_missing',
  );
  final action = _readRequiredString(
    extension,
    'action',
    reason: 'notification_action_missing',
  );
  if (action != 'add' && action != 'remove') {
    throw GroupOfflineReplaySignatureException('notification_action_invalid');
  }
  final targetMessageId = _readRequiredString(
    extension,
    'targetMessageId',
    reason: 'notification_target_missing',
  );
  final reactorPeerId = _readRequiredString(
    extension,
    'reactorPeerId',
    reason: 'notification_reactor_missing',
  );
  final reactorTransportPeerId = _readRequiredString(
    extension,
    'reactorTransportPeerId',
    reason: 'notification_reactor_transport_missing',
  );
  final extensionReplaySetHash = _readRequiredString(
    extension,
    'replayRecipientSetHash',
    reason: 'notification_replay_hash_missing',
  );
  final baseEnvelopeHash = _readRequiredString(
    extension,
    'baseEnvelopeHash',
    reason: 'notification_base_hash_missing',
  );
  final notificationRecipients = _readExactRecipientPeerIds(
    extension['notificationRecipientTransportPeerIds'],
    reason: 'notification_recipient_list_malformed',
  );
  final signedPayload = _readRequiredString(
    extension,
    'signedPayload',
    reason: 'notification_signed_payload_missing',
  );
  final signature = _readRequiredString(
    extension,
    'signature',
    reason: 'notification_signature_missing',
  );

  final expectedTransport = _trimToNull(senderTransportPeerId);
  if (reactorPeerId != senderPeerId ||
      expectedTransport == null ||
      reactorTransportPeerId != expectedTransport ||
      extensionReplaySetHash != replayRecipientSetHash) {
    throw GroupOfflineReplaySignatureException(
      'notification_sender_or_replay_mismatch',
    );
  }
  final replaySet = replayRecipientPeerIds.toSet();
  if (notificationRecipients.any(
    (recipient) => !replaySet.contains(recipient),
  )) {
    throw GroupOfflineReplaySignatureException(
      'notification_recipient_not_replay_subset',
    );
  }
  final baseEnvelope = Map<String, Object?>.from(envelope)
    ..remove('notificationExtension');
  final expectedBaseHash = _hashString(
    canonicalizeGroupEventLogPayload(baseEnvelope),
  );
  if (baseEnvelopeHash != expectedBaseHash) {
    throw GroupOfflineReplaySignatureException(
      'notification_base_hash_mismatch',
    );
  }
  final expectedSignedPayload = canonicalizeGroupEventLogPayload({
    'kind': groupReactionNotificationExtensionKind,
    'version': groupReactionNotificationExtensionVersion,
    'transitionId': transitionId,
    'action': action,
    'targetMessageId': targetMessageId,
    'reactorPeerId': reactorPeerId,
    'reactorTransportPeerId': reactorTransportPeerId,
    'replayRecipientSetHash': extensionReplaySetHash,
    'notificationRecipientTransportPeerIds': notificationRecipients,
    'baseEnvelopeHash': baseEnvelopeHash,
  });
  if (signedPayload != expectedSignedPayload) {
    throw GroupOfflineReplaySignatureException(
      'notification_signed_payload_mismatch',
    );
  }
  final valid = await callVerifyPayload(
    bridge: bridge,
    publicKey: senderPublicKey,
    data: signedPayload,
    signature: signature,
  );
  if (!valid) {
    throw GroupOfflineReplaySignatureException(
      'notification_signature_invalid',
    );
  }
  return _VerifiedGroupReactionNotificationExtension(
    transitionId: transitionId,
    action: action,
    targetMessageId: targetMessageId,
    reactorPeerId: reactorPeerId,
    reactorTransportPeerId: reactorTransportPeerId,
  );
}

/// Structural retry validation mirrors relay admission without doing crypto.
/// The relay remains signature authority; this prevents permanently
/// ineligible staged bytes from entering the retry loop.
void _validateRetryReactionExtension(
  Map<String, Object?> envelope, {
  required String contentEventId,
  required String senderPeerId,
  required String senderTransportPeerId,
  required String recipientSetHash,
  required List<String> recipientPeerIds,
}) {
  final raw = envelope['notificationExtension'];
  if (raw is! Map) {
    throw const FormatException('missing reaction notification extension');
  }
  final extension = raw.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
  final keys = extension.keys.toSet();
  if (keys.length != _reactionNotificationExtensionKeys.length ||
      !keys.containsAll(_reactionNotificationExtensionKeys)) {
    throw const FormatException('invalid reaction extension key set');
  }
  try {
    _requireExactNotificationExtensionStrings(extension);
  } on GroupOfflineReplaySignatureException {
    throw const FormatException('noncanonical reaction extension');
  }
  if (extension['version'] != groupReactionNotificationExtensionVersion ||
      extension['signatureAlgorithm'] != groupOfflineReplaySignatureAlgorithm) {
    throw const FormatException('invalid reaction extension version');
  }
  final transitionId = _strictNonEmptyString(extension['transitionId']);
  final action = _strictNonEmptyString(extension['action']);
  final targetMessageId = _strictNonEmptyString(extension['targetMessageId']);
  final reactorPeerId = _strictNonEmptyString(extension['reactorPeerId']);
  final reactorTransportPeerId = _strictNonEmptyString(
    extension['reactorTransportPeerId'],
  );
  final replaySetHash = _strictNonEmptyString(
    extension['replayRecipientSetHash'],
  );
  final baseEnvelopeHash = _strictNonEmptyString(extension['baseEnvelopeHash']);
  final signedPayload = _strictNonEmptyString(extension['signedPayload']);
  final signature = _strictNonEmptyString(extension['signature']);
  if (transitionId != contentEventId ||
      GroupReactionTransitionOrder.tryParse(transitionId) == null ||
      (action != 'add' && action != 'remove') ||
      targetMessageId == null ||
      reactorPeerId != senderPeerId ||
      reactorTransportPeerId != senderTransportPeerId ||
      replaySetHash != recipientSetHash ||
      baseEnvelopeHash == null ||
      signedPayload == null ||
      signature == null) {
    throw const FormatException('reaction extension authority mismatch');
  }
  final notificationRecipients = _strictRecipientList(
    extension['notificationRecipientTransportPeerIds'],
    'notification recipients',
  );
  final replaySet = recipientPeerIds.toSet();
  if (notificationRecipients.any((peerId) => !replaySet.contains(peerId))) {
    throw const FormatException('reaction notification ACL mismatch');
  }
  final baseEnvelope = Map<String, Object?>.from(envelope)
    ..remove('notificationExtension');
  if (baseEnvelopeHash !=
      _hashString(canonicalizeGroupEventLogPayload(baseEnvelope))) {
    throw const FormatException('reaction base envelope mismatch');
  }
  final expectedSignedPayload = canonicalizeGroupEventLogPayload({
    'kind': groupReactionNotificationExtensionKind,
    'version': groupReactionNotificationExtensionVersion,
    'transitionId': transitionId,
    'action': action,
    'targetMessageId': targetMessageId,
    'reactorPeerId': reactorPeerId,
    'reactorTransportPeerId': reactorTransportPeerId,
    'replayRecipientSetHash': replaySetHash,
    'notificationRecipientTransportPeerIds': notificationRecipients,
    'baseEnvelopeHash': baseEnvelopeHash,
  });
  if (signedPayload != expectedSignedPayload) {
    throw const FormatException('reaction extension signed map mismatch');
  }
}

void _verifyPlaintextBinding(
  String plaintext,
  _ReplaySignatureVerification verification, {
  required String fallbackGroupId,
}) {
  if (_hashString(plaintext) != verification.plaintextHash) {
    throw GroupOfflineReplaySignatureException('plaintext_hash_mismatch');
  }
  final payload = _decodeStringMap(plaintext);
  if (payload == null) {
    throw GroupOfflineReplaySignatureException('plaintext_malformed');
  }

  final payloadGroupId = payload['groupId'];
  if (payloadGroupId is String &&
      payloadGroupId.isNotEmpty &&
      payloadGroupId != fallbackGroupId) {
    throw GroupOfflineReplaySignatureException('payload_group_mismatch');
  }
  final keyEpoch = payload['keyEpoch'];
  if (keyEpoch != null && keyEpoch is! int) {
    throw GroupOfflineReplaySignatureException('payload_epoch_malformed');
  }

  final payloadSender =
      verification.payloadType == groupOfflineReplayPayloadTypeReaction
      ? _trimToNull(payload['senderPeerId'] as String?)
      : _trimToNull(payload['senderId'] as String?);
  if (payloadSender != null && payloadSender != verification.senderPeerId) {
    throw GroupOfflineReplaySignatureException('payload_sender_mismatch');
  }
  final payloadDeviceId = _trimToNull(payload['senderDeviceId'] as String?);
  if (payloadDeviceId != null &&
      verification.senderDeviceId != null &&
      payloadDeviceId != verification.senderDeviceId) {
    throw GroupOfflineReplaySignatureException('payload_device_mismatch');
  }
  final payloadTransportPeerId = _trimToNull(
    payload['transportPeerId'] as String?,
  );
  if (payloadTransportPeerId != null &&
      verification.senderTransportPeerId != null &&
      payloadTransportPeerId != verification.senderTransportPeerId) {
    throw GroupOfflineReplaySignatureException('payload_transport_mismatch');
  }
  final strictContent = verification.contentAuthorityVersion != null;
  final payloadMessageId =
      verification.payloadType == groupOfflineReplayPayloadTypeReaction
      ? _trimToNull(payload[strictContent ? 'eventId' : 'id'] as String?)
      : _trimToNull(payload['messageId'] as String?);
  if (verification.messageId != null &&
      (payloadMessageId == null ||
          payloadMessageId != verification.messageId)) {
    throw GroupOfflineReplaySignatureException('payload_message_mismatch');
  }

  final notificationExtension = verification.reactionNotificationExtension;
  if (notificationExtension != null) {
    final eventId = _trimToNull(payload['eventId'] as String?);
    final action = _trimToNull(payload['action'] as String?);
    final targetMessageId = _trimToNull(payload['messageId'] as String?);
    final reactorPeerId = _trimToNull(payload['senderPeerId'] as String?);
    if (eventId != notificationExtension.transitionId ||
        action != notificationExtension.action ||
        targetMessageId != notificationExtension.targetMessageId ||
        reactorPeerId != notificationExtension.reactorPeerId) {
      throw GroupOfflineReplaySignatureException(
        'notification_plaintext_parity_mismatch',
      );
    }
  }
  final contentAuthority = verification.contentAuthorityVersion;
  if (contentAuthority != null) {
    final recipientPeerIds = _readExactRecipientPeerIds(
      payload['recipientPeerIds'],
      reason: 'payload_recipient_list_malformed',
    );
    if (payloadGroupId != verification.groupId ||
        keyEpoch != verification.keyEpoch ||
        payloadSender != verification.senderPeerId ||
        payloadDeviceId != verification.senderDeviceId ||
        payloadTransportPeerId != verification.senderTransportPeerId ||
        payloadMessageId != verification.contentEventId ||
        payload['custodyKind'] != groupContentCustodyKind ||
        payload['contentEventId'] != verification.contentEventId ||
        payload['authorityEventAt'] !=
            fixedGroupContentUtc(contentAuthority.eventAt) ||
        payload['authorityEventId'] != contentAuthority.eventId ||
        payload['authorityKeyEpoch'] != contentAuthority.keyEpoch ||
        !_sameStringList(recipientPeerIds, verification.recipientPeerIds)) {
      throw GroupOfflineReplaySignatureException(
        'protected_content_plaintext_parity_mismatch',
      );
    }
    final manifest = verification.mediaManifest;
    final manifestHash = verification.mediaManifestHash;
    if ((manifest == null) != (manifestHash == null) ||
        payload['mediaManifest'] != manifest?.encode() ||
        payload['mediaManifestHash'] != manifestHash) {
      throw GroupOfflineReplaySignatureException(
        'protected_content_media_plaintext_parity_mismatch',
      );
    }
  }
}

GroupMemberDeviceIdentity? _resolveSigningDevice({
  required GroupMember? member,
  required String senderPublicKey,
  required String? senderDeviceId,
  required String? senderTransportPeerId,
  bool activeOnly = true,
}) {
  if (member == null) return null;
  GroupMemberDeviceIdentity? device;
  if (senderDeviceId != null) {
    device = member.findDeviceById(
      senderDeviceId,
      activeOnly: activeOnly,
      allowLegacyFallback: true,
    );
    if (device != null) return device;
    return _accountSignedUnboundTransportDevice(
      member: member,
      senderPublicKey: senderPublicKey,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
    );
  }
  if (senderTransportPeerId != null) {
    device = member.findDeviceByTransportPeerId(
      senderTransportPeerId,
      activeOnly: activeOnly,
      allowLegacyFallback: true,
    );
    if (device != null) return device;
    return _accountSignedUnboundTransportDevice(
      member: member,
      senderPublicKey: senderPublicKey,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
    );
  }
  return _firstDeviceForSigningKey(
    member,
    senderPublicKey,
    activeOnly: activeOnly,
    allowLegacyFallback: true,
  );
}

GroupMemberDeviceIdentity? _accountSignedUnboundTransportDevice({
  required GroupMember member,
  required String senderPublicKey,
  required String? senderDeviceId,
  required String? senderTransportPeerId,
}) {
  final trustedMemberPublicKey = member.publicKey?.trim();
  if (trustedMemberPublicKey == null ||
      trustedMemberPublicKey.isEmpty ||
      trustedMemberPublicKey != senderPublicKey.trim()) {
    return null;
  }

  final normalizedDeviceId = _trimToNull(senderDeviceId);
  final normalizedTransportPeerId = _trimToNull(senderTransportPeerId);
  final resolvedDeviceId = normalizedDeviceId ?? normalizedTransportPeerId;
  if (resolvedDeviceId == null || resolvedDeviceId.isEmpty) {
    return null;
  }
  final existingById = member.findDeviceById(
    resolvedDeviceId,
    activeOnly: false,
  );
  final existingByTransport = member.findDeviceByTransportPeerId(
    normalizedTransportPeerId,
    activeOnly: false,
  );
  if (existingById != null || existingByTransport != null) {
    return null;
  }
  return GroupMemberDeviceIdentity(
    deviceId: resolvedDeviceId,
    transportPeerId: normalizedTransportPeerId ?? resolvedDeviceId,
    deviceSigningPublicKey: trustedMemberPublicKey,
    mlKemPublicKey: member.mlKemPublicKey,
  );
}

GroupMemberDeviceIdentity? _firstDeviceForSigningKey(
  GroupMember member,
  String? signingPublicKey, {
  bool activeOnly = true,
  bool allowLegacyFallback = false,
}) {
  final normalized = signingPublicKey?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  final devices = activeOnly ? member.activeDevices : member.devices;
  for (final device in devices) {
    if (device.deviceSigningPublicKey == normalized) {
      return device;
    }
  }
  if (allowLegacyFallback) {
    final legacy = member.legacyDeviceIdentity;
    if (legacy?.deviceSigningPublicKey == normalized) {
      return legacy;
    }
  }
  return null;
}

String _buildReplaySignedPayload({
  required String groupId,
  required String payloadType,
  required int keyEpoch,
  required String ciphertext,
  required String nonce,
  required String plaintext,
  required String? messageId,
  required String senderPeerId,
  required String? senderDeviceId,
  required String? senderTransportPeerId,
  required String senderPublicKey,
  required String? senderKeyPackageId,
  required String recipientSetHash,
  List<String>? recipientPeerIds,
  String? contentEventId,
  GroupContentAuthorityVersion? contentAuthorityVersion,
  String? mediaManifestHash,
}) {
  return _buildReplaySignedPayloadFromHashes(
    groupId: groupId,
    payloadType: payloadType,
    keyEpoch: keyEpoch,
    ciphertextHash: _hashString(ciphertext),
    nonceHash: _hashString(nonce),
    plaintextHash: _hashString(plaintext),
    messageId: messageId,
    senderPeerId: senderPeerId,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    senderPublicKey: senderPublicKey,
    senderKeyPackageId: senderKeyPackageId,
    recipientSetHash: recipientSetHash,
    recipientPeerIds: recipientPeerIds,
    contentEventId: contentEventId,
    contentAuthorityVersion: contentAuthorityVersion,
    mediaManifestHash: mediaManifestHash,
  );
}

String _buildReplaySignedPayloadFromHashes({
  required String groupId,
  required String payloadType,
  required int keyEpoch,
  required String ciphertextHash,
  required String nonceHash,
  required String plaintextHash,
  required String? messageId,
  required String senderPeerId,
  required String? senderDeviceId,
  required String? senderTransportPeerId,
  required String senderPublicKey,
  required String? senderKeyPackageId,
  required String recipientSetHash,
  List<String>? recipientPeerIds,
  String? contentEventId,
  GroupContentAuthorityVersion? contentAuthorityVersion,
  String? mediaManifestHash,
}) {
  return canonicalizeGroupEventLogPayload({
    'schemaVersion': groupOfflineReplaySignatureVersion,
    'kind': groupOfflineReplayEnvelopeKind,
    'groupId': groupId,
    'payloadType': payloadType,
    'keyEpoch': keyEpoch,
    'messageId': ?messageId,
    'senderPeerId': senderPeerId,
    'senderDeviceId': ?senderDeviceId,
    'senderTransportPeerId': ?senderTransportPeerId,
    'senderSigningPublicKey': senderPublicKey,
    'senderKeyPackageId': ?senderKeyPackageId,
    'ciphertextHash': ciphertextHash,
    'nonceHash': nonceHash,
    'plaintextHash': plaintextHash,
    'recipientSetHash': recipientSetHash,
    if (contentAuthorityVersion != null) 'custodyKind': groupContentCustodyKind,
    if (contentAuthorityVersion != null) 'contentEventId': contentEventId,
    if (contentAuthorityVersion != null)
      'authorityEventAt': fixedGroupContentUtc(contentAuthorityVersion.eventAt),
    if (contentAuthorityVersion != null)
      'authorityEventId': contentAuthorityVersion.eventId,
    if (contentAuthorityVersion != null)
      'authorityKeyEpoch': contentAuthorityVersion.keyEpoch,
    if (contentAuthorityVersion != null)
      'recipientPeerIds': recipientPeerIds ?? const <String>[],
    'mediaManifestHash': ?mediaManifestHash,
  });
}

List<String> _normalizedRecipientPeerIds(List<String>? recipientPeerIds) {
  final normalized =
      (recipientPeerIds ?? const <String>[])
          .map((peerId) => peerId.trim())
          .where((peerId) => peerId.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return normalized;
}

List<String> _strictSortedUniqueRecipients(
  Iterable<String> values,
  String field,
) {
  final raw = values.toList(growable: false);
  final normalized = <String>[];
  final seen = <String>{};
  for (final value in raw) {
    if (value.isEmpty || value.trim() != value || !seen.add(value)) {
      throw FormatException('invalid $field');
    }
    normalized.add(value);
  }
  normalized.sort();
  return normalized;
}

List<String> _strictRecipientList(Object? value, String field) {
  if (value is! List) throw FormatException('invalid $field');
  final raw = <String>[];
  for (final entry in value) {
    if (entry is! String) throw FormatException('invalid $field');
    raw.add(entry);
  }
  final normalized = _strictSortedUniqueRecipients(raw, field);
  if (!_sameStringList(raw, normalized)) {
    throw FormatException('non-canonical $field');
  }
  return normalized;
}

bool _sameStringList(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String? _strictNonEmptyString(Object? value) {
  if (value is! String || value.isEmpty || value.trim() != value) return null;
  return value;
}

String _strictGroupContentWireId(Object? value, String field) {
  final normalized = _strictNonEmptyString(value);
  if (normalized == null ||
      normalized.length > 512 ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(normalized)) {
    throw ArgumentError.value(value, field, 'invalid group content wire id');
  }
  return normalized;
}

String _recipientSetHashFromNormalized(List<String> recipientPeerIds) =>
    _hashString(jsonEncode(recipientPeerIds));

String _hashString(String value) =>
    sha256.convert(utf8.encode(value)).toString();

String _requiredTrimmed(String value, String field) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, field, 'must not be empty');
  }
  return trimmed;
}

String _readRequiredString(
  Map<String, Object?> payload,
  String field, {
  required String reason,
}) {
  final value = payload[field];
  if (value is! String || value.trim().isEmpty) {
    throw GroupOfflineReplaySignatureException(reason);
  }
  return value.trim();
}

void _requireExactReplayStrings(Map<String, Object?> envelope) {
  for (final field in const <String>[
    'kind',
    'groupId',
    'payloadType',
    'messageId',
    'senderPeerId',
    'senderDeviceId',
    'senderTransportPeerId',
    'senderPublicKey',
    'recipientSetHash',
    'ciphertext',
    'nonce',
    'signatureAlgorithm',
    'signedPayload',
    'signature',
    'custodyKind',
    'contentEventId',
    'authorityEventAt',
    'authorityEventId',
  ]) {
    final value = envelope[field];
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw GroupOfflineReplaySignatureException(
        'noncanonical_strict_field_$field',
      );
    }
  }
  final optional = envelope['senderKeyPackageId'];
  if (optional != null &&
      (optional is! String ||
          optional.isEmpty ||
          optional.trim() != optional)) {
    throw GroupOfflineReplaySignatureException(
      'noncanonical_strict_field_senderKeyPackageId',
    );
  }
  for (final field in const <String>['mediaManifest', 'mediaManifestHash']) {
    if (!envelope.containsKey(field)) continue;
    final value = envelope[field];
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw GroupOfflineReplaySignatureException(
        'noncanonical_strict_field_$field',
      );
    }
  }
}

(ProtectedGroupMediaManifest?, String?, String?)
_decodeProtectedGroupMediaManifestBinding({
  required Map<String, Object?> envelope,
  required Map<String, Object?> signedPayload,
  required String groupId,
  required String contentEventId,
  required List<String> recipientPeerIds,
  required String payloadType,
  required Never Function(String reason) invalid,
}) {
  final envelopeManifest = envelope['mediaManifest'];
  final envelopeHash = envelope['mediaManifestHash'];
  final signedHash = signedPayload['mediaManifestHash'];
  final anyPresent =
      envelope.containsKey('mediaManifest') ||
      envelope.containsKey('mediaManifestHash') ||
      signedPayload.containsKey('mediaManifestHash');
  if (!anyPresent) return (null, null, null);
  if (payloadType != groupOfflineReplayPayloadTypeMessage ||
      envelopeManifest is! String ||
      envelopeHash is! String ||
      signedPayload.containsKey('mediaManifest') ||
      signedHash != envelopeHash ||
      envelopeManifest.isEmpty ||
      envelopeManifest.trim() != envelopeManifest ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(envelopeHash) ||
      _hashString(envelopeManifest) != envelopeHash) {
    invalid('protected_media_manifest_binding_invalid');
  }
  try {
    final manifest = ProtectedGroupMediaManifest.decode(envelopeManifest);
    if (manifest.encode() != envelopeManifest ||
        manifest.fingerprintSha256 != envelopeHash ||
        !manifest.matchesAuthority(
          expectedGroupId: groupId,
          expectedMessageId: contentEventId,
          expectedRecipientPeerIds: recipientPeerIds,
        )) {
      invalid('protected_media_manifest_authority_mismatch');
    }
    return (manifest, envelopeManifest, envelopeHash);
  } catch (_) {
    invalid('protected_media_manifest_malformed');
  }
}

void _requireExactNotificationExtensionStrings(Map<String, Object?> extension) {
  for (final field in const <String>[
    'transitionId',
    'action',
    'targetMessageId',
    'reactorPeerId',
    'reactorTransportPeerId',
    'replayRecipientSetHash',
    'baseEnvelopeHash',
    'signatureAlgorithm',
    'signedPayload',
    'signature',
  ]) {
    final value = extension[field];
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw GroupOfflineReplaySignatureException(
        'noncanonical_notification_field_$field',
      );
    }
  }
}

List<String>? _readOptionalRecipientPeerIds(Object? value) {
  if (value == null) return null;
  if (value is! List) {
    throw GroupOfflineReplaySignatureException('recipient_list_malformed');
  }
  final recipientPeerIds = <String>[];
  for (final entry in value) {
    if (entry is! String || entry.trim().isEmpty) {
      throw GroupOfflineReplaySignatureException('recipient_list_malformed');
    }
    recipientPeerIds.add(entry.trim());
  }
  return _normalizedRecipientPeerIds(recipientPeerIds);
}

List<String> _readExactRecipientPeerIds(
  Object? value, {
  required String reason,
}) {
  if (value is! List) {
    throw GroupOfflineReplaySignatureException(reason);
  }
  final raw = <String>[];
  for (final entry in value) {
    if (entry is! String || entry.trim().isEmpty || entry != entry.trim()) {
      throw GroupOfflineReplaySignatureException(reason);
    }
    raw.add(entry);
  }
  final normalized = _normalizedRecipientPeerIds(raw);
  if (raw.length != normalized.length) {
    throw GroupOfflineReplaySignatureException(reason);
  }
  for (var index = 0; index < raw.length; index++) {
    if (raw[index] != normalized[index]) {
      throw GroupOfflineReplaySignatureException(reason);
    }
  }
  return normalized;
}

Map<String, Object?>? _decodeStringMap(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map) return null;
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  } catch (_) {
    return null;
  }
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

String? _relayVisibleReplayMessageId(String? messageId) {
  if (messageId == null || _isMembershipReplayMessageId(messageId)) {
    return null;
  }
  return messageId;
}

bool _isMembershipReplayMessageId(String messageId) {
  final normalized = messageId.trim().toLowerCase();
  const membershipPrefixes = <String>[
    'sys-member_',
    'member_added:',
    'members_added:',
    'member_joined:',
    'member_removed:',
    'member_role_updated:',
  ];
  return membershipPrefixes.any(normalized.startsWith);
}

Future<GroupKeyInfo> _loadReplayKey(
  GroupRepository groupRepo,
  String groupId,
) async {
  final keyInfo = await groupRepo.getLatestKey(groupId);
  if (keyInfo == null) {
    throw StateError('Missing group replay key for group $groupId');
  }
  return keyInfo;
}
