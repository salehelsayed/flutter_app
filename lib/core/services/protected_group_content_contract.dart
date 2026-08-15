import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'inbox_store_outcome.dart';

const String protectedGroupContentCustodyKind = 'group_content_v1';
const String protectedGroupOfflineReplayEnvelopeKind = 'group_offline_replay';
const int protectedGroupOfflineReplayEnvelopeVersion = 1;
const String protectedGroupContentMessagePayloadType = 'group_message';
const String protectedGroupContentReactionPayloadType = 'group_reaction';
const String protectedGroupOfflineReplaySignatureAlgorithm = 'ed25519';

/// Transport routing classification for a possible strict group-content wire
/// envelope.
///
/// [signedContent] means the canonical `signedPayload` declares the protected
/// custody kind. It is still only a routing claim until receive verifies the
/// signature. [unverifiedCandidate] keeps malformed or crossed declarations on
/// the protected custody path so an unsigned outer hint can never trigger the
/// generic stage-and-ACK path.
enum ProtectedGroupContentWireClassification {
  unrelated,
  signedContent,
  unverifiedCandidate,
}

/// Classifies strict content from the canonical, signature-bound payload.
///
/// Unsigned outer `type`/`custodyKind` values are never positive content
/// authority. They only make a malformed row an [unverifiedCandidate], which
/// callers must retain without ACK until trustworthy durable evidence exists.
ProtectedGroupContentWireClassification classifyProtectedGroupContentWire(
  String raw,
) {
  final envelope = _decodeStringMap(raw);
  if (envelope == null) {
    return _rawDeclaresProtectedGroupContent(raw)
        ? ProtectedGroupContentWireClassification.unverifiedCandidate
        : ProtectedGroupContentWireClassification.unrelated;
  }

  final signedRaw = envelope['signedPayload'];
  final signed = signedRaw is String ? _decodeStringMap(signedRaw) : null;
  if (signedRaw is String &&
      signed != null &&
      _canonicalJson(signed) == signedRaw &&
      signed['custodyKind'] == protectedGroupContentCustodyKind) {
    return ProtectedGroupContentWireClassification.signedContent;
  }

  if (_mapDeclaresProtectedGroupContent(envelope) ||
      (signed != null && _mapDeclaresProtectedGroupContent(signed)) ||
      (signedRaw is String && _rawDeclaresProtectedGroupContent(signedRaw))) {
    return ProtectedGroupContentWireClassification.unverifiedCandidate;
  }
  return ProtectedGroupContentWireClassification.unrelated;
}

const Set<String> _protectedGroupContentEvidenceKeys = <String>{
  'contentEventId',
  'authorityEventAt',
  'authorityEventId',
  'authorityKeyEpoch',
};

bool _mapDeclaresProtectedGroupContent(Map<String, Object?> value) =>
    value['custodyKind'] == protectedGroupContentCustodyKind ||
    value['type'] == protectedGroupContentCustodyKind ||
    value.keys.any(_protectedGroupContentEvidenceKeys.contains);

bool _rawDeclaresProtectedGroupContent(String value) =>
    value.contains(protectedGroupContentCustodyKind) ||
    _protectedGroupContentEvidenceKeys.any(value.contains);

/// Durable state of the message targeted by protected group reaction content.
enum ProtectedGroupReactionTargetDisposition {
  available,
  prerequisiteWaiting,
  terminal,
}

/// Canonical order encoded by a strict group-reaction transition identifier.
class GroupReactionTransitionOrder {
  const GroupReactionTransitionOrder({
    required this.stateDigest,
    required this.epochMicros,
    required this.eventDigest,
    required this.value,
  });

  final String stateDigest;
  final BigInt epochMicros;
  final String eventDigest;
  final String value;

  static GroupReactionTransitionOrder? tryParse(String? value) {
    if (value == null) return null;
    final match = RegExp(
      r'^gr1:([0-9a-f]{32}):(\d{20}):([0-9a-f]{32})$',
    ).firstMatch(value);
    if (match == null) return null;
    final epochMicros = BigInt.tryParse(match.group(2)!);
    if (epochMicros == null) return null;
    return GroupReactionTransitionOrder(
      stateDigest: match.group(1)!,
      epochMicros: epochMicros,
      eventDigest: match.group(3)!,
      value: value,
    );
  }
}

/// The sole production transition comparator used by application and DB code.
int compareGroupReactionTransitionIds(String left, String right) {
  final parsedLeft = GroupReactionTransitionOrder.tryParse(left);
  final parsedRight = GroupReactionTransitionOrder.tryParse(right);
  if (parsedLeft == null || parsedRight == null) {
    throw const FormatException('invalid group reaction transition id');
  }
  final time = parsedLeft.epochMicros.compareTo(parsedRight.epochMicros);
  return time != 0 ? time : parsedLeft.value.compareTo(parsedRight.value);
}

const Set<String> _strictWrapperKeys = <String>{
  'groupId',
  'message',
  'custodyContract',
  'custodyKind',
  'recipientPeerIds',
};

const Set<String> _strictEnvelopeKeys = <String>{
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

const Set<String> _requiredStrictEnvelopeKeys = <String>{
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
};

/// Core-owned structural authority for a persisted strict retry wrapper.
///
/// Cryptographic verification remains at the relay/receive boundary. This
/// parser deliberately owns the storage contract so core DB helpers can reject
/// poisoned wrappers without importing a feature/application library.
class ProtectedGroupContentRetryManifest {
  const ProtectedGroupContentRetryManifest({
    required this.groupId,
    required this.replayEnvelope,
    required this.contentEventId,
    required this.payloadType,
    required this.pendingRecipientPeerIds,
    required this.fullRecipientPeerIds,
    required this.keyEpoch,
    required this.logicalSenderPeerId,
    required this.senderDeviceId,
    required this.senderTransportPeerId,
    required this.senderPublicKey,
    required this.plaintextHash,
    required this.reactionTargetMessageId,
    required this.reactionAction,
    required this.mediaManifest,
    required this.mediaManifestHash,
  });

  final String groupId;
  final String replayEnvelope;
  final String contentEventId;
  final String payloadType;
  final List<String> pendingRecipientPeerIds;
  final List<String> fullRecipientPeerIds;
  final int keyEpoch;
  final String logicalSenderPeerId;
  final String senderDeviceId;
  final String senderTransportPeerId;
  final String senderPublicKey;
  final String plaintextHash;
  final String? reactionTargetMessageId;
  final String? reactionAction;
  final String? mediaManifest;
  final String? mediaManifestHash;

  bool matchesCanonicalPlaintext(Map<String, Object?> plaintext) =>
      _hash(jsonEncode(plaintext)) == plaintextHash;

  static ProtectedGroupContentRetryManifest decode(String raw) {
    final wrapper = _decodeStringMap(raw);
    if (wrapper == null ||
        !_sameKeySet(wrapper, _strictWrapperKeys) ||
        wrapper['custodyContract'] != ackOrExpiryInboxCustodyContract ||
        wrapper['custodyKind'] != protectedGroupContentCustodyKind) {
      throw const FormatException('not strict group content custody');
    }
    final groupId = _exactNonEmptyString(wrapper['groupId']);
    final message = _exactNonEmptyString(wrapper['message']);
    if (groupId == null || message == null || !_isWireId(groupId)) {
      throw const FormatException('invalid group content retry authority');
    }
    final envelope = _decodeStringMap(message);
    if (envelope == null ||
        envelope.keys.any((key) => !_strictEnvelopeKeys.contains(key)) ||
        !_requiredStrictEnvelopeKeys.every(envelope.containsKey) ||
        envelope['kind'] != protectedGroupOfflineReplayEnvelopeKind ||
        envelope['version'] != protectedGroupOfflineReplayEnvelopeVersion ||
        envelope['custodyKind'] != protectedGroupContentCustodyKind ||
        envelope['groupId'] != groupId) {
      throw const FormatException('crossed group content envelope');
    }
    _requireExactStrings(envelope, const <String>[
      'kind',
      'groupId',
      'payloadType',
      'messageId',
      'senderPeerId',
      'senderDeviceId',
      'senderTransportPeerId',
      'senderPublicKey',
      'senderKeyPackageId',
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
      'mediaManifest',
      'mediaManifestHash',
    ]);
    final payloadType = envelope['payloadType'];
    final contentEventId = _exactNonEmptyString(envelope['contentEventId']);
    if ((payloadType != protectedGroupContentMessagePayloadType &&
            payloadType != protectedGroupContentReactionPayloadType) ||
        contentEventId == null ||
        !_isWireId(contentEventId) ||
        envelope['messageId'] != contentEventId ||
        envelope['signatureAlgorithm'] !=
            protectedGroupOfflineReplaySignatureAlgorithm) {
      throw const FormatException('invalid group content identity');
    }
    if (payloadType == protectedGroupContentReactionPayloadType) {
      if (GroupReactionTransitionOrder.tryParse(contentEventId) == null ||
          envelope['notificationExtension'] is! Map) {
        throw const FormatException('invalid group reaction authority');
      }
    } else if (envelope.containsKey('notificationExtension')) {
      throw const FormatException('message declares reaction extension');
    }
    final keyEpoch = envelope['keyEpoch'];
    final authorityKeyEpoch = envelope['authorityKeyEpoch'];
    final authorityAt = _exactNonEmptyString(envelope['authorityEventAt']);
    final authorityId = _exactNonEmptyString(envelope['authorityEventId']);
    if (keyEpoch is! int ||
        keyEpoch < 0 ||
        authorityKeyEpoch != keyEpoch ||
        authorityAt == null ||
        !_isFixedUtc(authorityAt) ||
        authorityId == null ||
        !_isWireId(authorityId)) {
      throw const FormatException('invalid group content authority version');
    }
    final full = _strictRecipients(envelope['recipientPeerIds'], 'full');
    final pending = _strictRecipients(wrapper['recipientPeerIds'], 'pending');
    if (full.isEmpty ||
        pending.isEmpty ||
        pending.any((peerId) => !full.contains(peerId)) ||
        envelope['recipientSetHash'] != _recipientSetHash(full)) {
      throw const FormatException('invalid group content recipient authority');
    }
    final signedPayloadRaw = _exactNonEmptyString(envelope['signedPayload']);
    final signedPayload = signedPayloadRaw == null
        ? null
        : _decodeStringMap(signedPayloadRaw);
    final senderPeerId = envelope['senderPeerId'] as String;
    final senderDeviceId = envelope['senderDeviceId'] as String;
    final senderTransportPeerId = envelope['senderTransportPeerId'] as String;
    final senderPublicKey = envelope['senderPublicKey'] as String;
    final senderKeyPackageId = envelope['senderKeyPackageId'] as String?;
    final ciphertext = envelope['ciphertext'] as String;
    final nonce = envelope['nonce'] as String;
    final plaintextHash = signedPayload?['plaintextHash'];
    final mediaManifest = envelope['mediaManifest'];
    final mediaManifestHash = envelope['mediaManifestHash'];
    final signedMediaManifestHash = signedPayload?['mediaManifestHash'];
    final hasMediaManifest =
        envelope.containsKey('mediaManifest') ||
        envelope.containsKey('mediaManifestHash') ||
        (signedPayload?.containsKey('mediaManifest') ?? false) ||
        (signedPayload?.containsKey('mediaManifestHash') ?? false);
    if (hasMediaManifest) {
      final decodedManifest = mediaManifest is String
          ? _decodeStringMap(mediaManifest)
          : null;
      if (payloadType != protectedGroupContentMessagePayloadType ||
          mediaManifest is! String ||
          mediaManifestHash is! String ||
          (signedPayload?.containsKey('mediaManifest') ?? false) ||
          signedMediaManifestHash != mediaManifestHash ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(mediaManifestHash) ||
          _hash(mediaManifest) != mediaManifestHash ||
          decodedManifest == null ||
          !_sameKeySet(decodedManifest, const <String>{
            'schema',
            'groupId',
            'messageId',
            'custodyKind',
            'custodyContract',
            'recipientPeerIds',
            'attachments',
          }) ||
          decodedManifest['schema'] != 'group_media_manifest_v1' ||
          decodedManifest['groupId'] != groupId ||
          decodedManifest['messageId'] != contentEventId ||
          decodedManifest['custodyKind'] != 'group_media_blob_v1' ||
          decodedManifest['custodyContract'] !=
              ackOrExpiryInboxCustodyContract ||
          !_matchesStrictRecipients(
            decodedManifest['recipientPeerIds'],
            full,
          ) ||
          decodedManifest['attachments'] is! List ||
          (decodedManifest['attachments'] as List).isEmpty) {
        throw const FormatException('crossed group media manifest');
      }
    }
    final expectedSignedPayload = <String, Object?>{
      'schemaVersion': 1,
      'kind': protectedGroupOfflineReplayEnvelopeKind,
      'groupId': groupId,
      'payloadType': payloadType,
      'keyEpoch': keyEpoch,
      'messageId': contentEventId,
      'senderPeerId': senderPeerId,
      'senderDeviceId': senderDeviceId,
      'senderTransportPeerId': senderTransportPeerId,
      'senderSigningPublicKey': senderPublicKey,
      'senderKeyPackageId': ?senderKeyPackageId,
      'ciphertextHash': _hash(ciphertext),
      'nonceHash': _hash(nonce),
      'plaintextHash': plaintextHash,
      'recipientSetHash': envelope['recipientSetHash'],
      'custodyKind': protectedGroupContentCustodyKind,
      'contentEventId': contentEventId,
      'authorityEventAt': authorityAt,
      'authorityEventId': authorityId,
      'authorityKeyEpoch': authorityKeyEpoch,
      'recipientPeerIds': full,
      if (mediaManifestHash is String) 'mediaManifestHash': mediaManifestHash,
    };
    if (signedPayload == null ||
        plaintextHash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(plaintextHash) ||
        _canonicalJson(signedPayload) != signedPayloadRaw ||
        _canonicalJson(expectedSignedPayload) != signedPayloadRaw ||
        _exactNonEmptyString(envelope['signature']) == null) {
      throw const FormatException('crossed group content signature');
    }
    final signedFull = _strictRecipients(
      signedPayload['recipientPeerIds'],
      'signed full',
    );
    if (!_sameStrings(full, signedFull)) {
      throw const FormatException('group content ACL mismatch');
    }
    String? reactionTargetMessageId;
    String? reactionAction;
    if (payloadType == protectedGroupContentReactionPayloadType) {
      _validateReactionExtension(
        envelope,
        transitionId: contentEventId,
        senderPeerId: senderPeerId,
        senderTransportPeerId: senderTransportPeerId,
        replayRecipientSetHash: envelope['recipientSetHash'] as String,
        fullRecipientPeerIds: full,
      );
      final extension = (envelope['notificationExtension'] as Map)
          .cast<String, Object?>();
      reactionTargetMessageId = extension['targetMessageId'] as String;
      reactionAction = extension['action'] as String;
    }
    return ProtectedGroupContentRetryManifest(
      groupId: groupId,
      replayEnvelope: message,
      contentEventId: contentEventId,
      payloadType: payloadType as String,
      pendingRecipientPeerIds: pending,
      fullRecipientPeerIds: full,
      keyEpoch: keyEpoch,
      logicalSenderPeerId: senderPeerId,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
      senderPublicKey: senderPublicKey,
      plaintextHash: plaintextHash,
      reactionTargetMessageId: reactionTargetMessageId,
      reactionAction: reactionAction,
      mediaManifest: mediaManifest as String?,
      mediaManifestHash: mediaManifestHash as String?,
    );
  }
}

Map<String, Object?>? _decodeStringMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  } catch (_) {
    return null;
  }
}

bool _sameKeySet(Map<String, Object?> value, Set<String> expected) =>
    value.length == expected.length && value.keys.toSet().containsAll(expected);

String? _exactNonEmptyString(Object? value) =>
    value is String && value.isNotEmpty && value.trim() == value ? value : null;

void _requireExactStrings(Map<String, Object?> value, Iterable<String> fields) {
  for (final field in fields) {
    if (!value.containsKey(field)) continue;
    final candidate = value[field];
    if (candidate is! String ||
        candidate.isEmpty ||
        candidate.trim() != candidate) {
      throw const FormatException('invalid group content string');
    }
  }
}

bool _isWireId(String value) =>
    value.length <= 512 && RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);

bool _isFixedUtc(String value) {
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
  ).hasMatch(value)) {
    return false;
  }
  final parsed = DateTime.tryParse(value)?.toUtc();
  if (parsed == null) return false;
  String two(int number) => number.toString().padLeft(2, '0');
  String six(int number) => number.toString().padLeft(6, '0');
  final canonical =
      '${parsed.year.toString().padLeft(4, '0')}-'
      '${two(parsed.month)}-${two(parsed.day)}T${two(parsed.hour)}:'
      '${two(parsed.minute)}:${two(parsed.second)}.'
      '${six(parsed.microsecond + parsed.millisecond * 1000)}Z';
  return canonical == value;
}

List<String> _strictRecipients(Object? raw, String field) {
  if (raw is! List) throw FormatException('invalid $field recipients');
  final result = <String>[];
  String? prior;
  for (final value in raw) {
    final recipient = _exactNonEmptyString(value);
    if (recipient == null ||
        (prior != null && prior.compareTo(recipient) >= 0)) {
      throw FormatException('invalid $field recipients');
    }
    result.add(recipient);
    prior = recipient;
  }
  return List<String>.unmodifiable(result);
}

bool _matchesStrictRecipients(Object? raw, List<String> expected) {
  try {
    return _sameStrings(_strictRecipients(raw, 'manifest'), expected);
  } on FormatException {
    return false;
  }
}

String _recipientSetHash(List<String> recipients) =>
    _hash(jsonEncode(recipients));

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      sorted[entry.key.toString()] = _canonicalize(entry.value);
    }
    return sorted;
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}

String _canonicalJson(Map<String, Object?> value) =>
    jsonEncode(_canonicalize(value));

const Set<String> _reactionExtensionKeys = <String>{
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

void _validateReactionExtension(
  Map<String, Object?> envelope, {
  required String transitionId,
  required String senderPeerId,
  required String senderTransportPeerId,
  required String replayRecipientSetHash,
  required List<String> fullRecipientPeerIds,
}) {
  final raw = envelope['notificationExtension'];
  if (raw is! Map) {
    throw const FormatException('missing reaction notification extension');
  }
  final extension = raw.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
  if (!_sameKeySet(extension, _reactionExtensionKeys)) {
    throw const FormatException('invalid reaction extension key set');
  }
  _requireExactStrings(extension, const <String>[
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
  ]);
  final action = extension['action'];
  final targetMessageId = extension['targetMessageId'];
  final notificationRecipients = _strictRecipients(
    extension['notificationRecipientTransportPeerIds'],
    'notification',
  );
  final baseEnvelope = Map<String, Object?>.from(envelope)
    ..remove('notificationExtension');
  final baseEnvelopeHash = _hash(_canonicalJson(baseEnvelope));
  final extensionSignedPayload = extension['signedPayload'];
  final expectedSignedPayload = <String, Object?>{
    'kind': 'group_reaction_notification',
    'version': 1,
    'transitionId': transitionId,
    'action': action,
    'targetMessageId': targetMessageId,
    'reactorPeerId': senderPeerId,
    'reactorTransportPeerId': senderTransportPeerId,
    'replayRecipientSetHash': replayRecipientSetHash,
    'notificationRecipientTransportPeerIds': notificationRecipients,
    'baseEnvelopeHash': baseEnvelopeHash,
  };
  if (extension['version'] != 1 ||
      extension['transitionId'] != transitionId ||
      (action != 'add' && action != 'remove') ||
      _exactNonEmptyString(targetMessageId) == null ||
      extension['reactorPeerId'] != senderPeerId ||
      extension['reactorTransportPeerId'] != senderTransportPeerId ||
      extension['replayRecipientSetHash'] != replayRecipientSetHash ||
      notificationRecipients.any(
        (recipient) => !fullRecipientPeerIds.contains(recipient),
      ) ||
      extension['baseEnvelopeHash'] != baseEnvelopeHash ||
      extension['signatureAlgorithm'] !=
          protectedGroupOfflineReplaySignatureAlgorithm ||
      extensionSignedPayload is! String ||
      extensionSignedPayload != _canonicalJson(expectedSignedPayload) ||
      _exactNonEmptyString(extension['signature']) == null) {
    throw const FormatException('crossed reaction notification extension');
  }
}
