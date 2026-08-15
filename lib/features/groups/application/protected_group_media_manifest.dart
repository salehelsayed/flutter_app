import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';

const String protectedGroupMediaManifestSchema = 'group_media_manifest_v1';
const String groupMediaBlobCustodyKind = 'group_media_blob_v1';
const String groupMediaBlobCustodyContract = 'ack_or_expiry_v1';
const String groupMediaBlobTransportMime = 'application/octet-stream';
const String groupMediaBlobEncryptionScheme = 'blob_aes_256_gcm_v1';
const int protectedGroupContentMaxFrameBytes = 128 * 1024;
// Plan 365 supports the account primary plus one active linked secondary for
// every member. The authoring transport is excluded from its own physical ACL.
const int protectedGroupMediaMaxPhysicalRecipients =
    groupMembershipLimit * 2 - 1;

final RegExp _groupMediaSha256 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _groupMediaBlobId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Exact relay authority returned by one target-qualified strict blob store.
///
/// Relay identity is deliberately local-only. The signed manifest projects
/// the recipient-specific expiry but never reveals which relay accepted it.
final class GroupMediaBlobUploadReceipt {
  const GroupMediaBlobUploadReceipt({
    required this.expiresAtMs,
    required this.custodyRelayPeerId,
    required this.storeStatus,
  });

  final int expiresAtMs;
  final String custodyRelayPeerId;
  final String storeStatus;

  static GroupMediaBlobUploadReceipt? parseExact({
    required Map<String, dynamic> response,
    required String custodyBlobId,
    required String contentHash,
    required int ciphertextSize,
  }) {
    final status = response['storeStatus'];
    final expiresAtMs = response['expiresAtMs'];
    final relayPeerId = response['custodyRelayPeerId'];
    if (response['ok'] != true ||
        response['id'] != custodyBlobId ||
        (status != 'stored' && status != 'duplicate') ||
        response['custodyKind'] != groupMediaBlobCustodyKind ||
        response['custodyContract'] != groupMediaBlobCustodyContract ||
        response['contentHash'] != contentHash ||
        response['size'] != ciphertextSize ||
        response['mime'] != groupMediaBlobTransportMime ||
        expiresAtMs is! int ||
        expiresAtMs <= 0 ||
        relayPeerId is! String ||
        relayPeerId.trim().isEmpty ||
        relayPeerId != relayPeerId.trim()) {
      return null;
    }
    return GroupMediaBlobUploadReceipt(
      expiresAtMs: expiresAtMs,
      custodyRelayPeerId: relayPeerId,
      storeStatus: status as String,
    );
  }
}

/// The immutable relay-lifetime commitment for one physical group recipient.
///
/// Relay identities stay device-local; the signed content binds only the
/// exact recipient, kind, contract and expiry that the sender received from
/// the strict blob store.
final class GroupMediaBlobTargetCommitment {
  GroupMediaBlobTargetCommitment({
    required String recipientPeerId,
    required this.expiresAtMs,
    String custodyKind = groupMediaBlobCustodyKind,
    String custodyContract = groupMediaBlobCustodyContract,
  }) : recipientPeerId = _canonicalString(recipientPeerId, 'recipientPeerId'),
       custodyKind = _canonicalString(custodyKind, 'custodyKind'),
       custodyContract = _canonicalString(custodyContract, 'custodyContract') {
    if (this.custodyKind != groupMediaBlobCustodyKind ||
        this.custodyContract != groupMediaBlobCustodyContract ||
        expiresAtMs <= 0) {
      throw ArgumentError('invalid strict group-media target commitment');
    }
  }

  factory GroupMediaBlobTargetCommitment.fromJson(
    String recipientPeerId,
    Object? value,
  ) {
    final map = _strictMap(value, 'target commitment');
    _requireExactKeys(map, const <String>{
      'custodyKind',
      'custodyContract',
      'expiresAtMs',
    });
    return GroupMediaBlobTargetCommitment(
      recipientPeerId: recipientPeerId,
      custodyKind: map['custodyKind'] as String,
      custodyContract: map['custodyContract'] as String,
      expiresAtMs: _strictInt(map['expiresAtMs'], 'expiresAtMs'),
    );
  }

  final String recipientPeerId;
  final String custodyKind;
  final String custodyContract;
  final int expiresAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'custodyKind': custodyKind,
    'custodyContract': custodyContract,
    'expiresAtMs': expiresAtMs,
  };
}

/// One encrypt-once attachment and all of its independent relay obligations.
final class ProtectedGroupMediaAttachmentCommitment {
  ProtectedGroupMediaAttachmentCommitment({
    required String attachmentId,
    required String custodyBlobId,
    required String ciphertextSha256,
    required this.ciphertextSize,
    required String mime,
    required String mediaType,
    required String encryptionKeyBase64,
    required String encryptionNonce,
    String encryptionScheme = groupMediaBlobEncryptionScheme,
    this.width,
    this.height,
    this.durationMs,
    List<double>? waveform,
    String? caption,
    required Iterable<GroupMediaBlobTargetCommitment> targets,
  }) : attachmentId = _canonicalString(attachmentId, 'attachmentId'),
       custodyBlobId = _canonicalString(custodyBlobId, 'custodyBlobId'),
       ciphertextSha256 = _canonicalString(
         ciphertextSha256,
         'ciphertextSha256',
       ),
       mime = _canonicalString(mime, 'mime'),
       mediaType = _canonicalString(mediaType, 'mediaType'),
       encryptionKeyBase64 = _canonicalString(
         encryptionKeyBase64,
         'encryptionKeyBase64',
       ),
       encryptionNonce = _canonicalString(encryptionNonce, 'encryptionNonce'),
       encryptionScheme = _canonicalString(
         encryptionScheme,
         'encryptionScheme',
       ),
       waveform = List<double>.unmodifiable(waveform ?? const <double>[]),
       caption = _nullableCanonicalString(caption, 'caption'),
       targets = _canonicalTargets(targets) {
    if (!_groupMediaBlobId.hasMatch(this.custodyBlobId) ||
        !_groupMediaSha256.hasMatch(this.ciphertextSha256) ||
        ciphertextSize <= 0 ||
        !RegExp(r'^[^/\s]+/[^/\s]+$').hasMatch(this.mime) ||
        this.encryptionScheme != groupMediaBlobEncryptionScheme ||
        (width != null && width! <= 0) ||
        (height != null && height! <= 0) ||
        (durationMs != null && durationMs! < 0) ||
        this.waveform.any((sample) => !sample.isFinite)) {
      throw ArgumentError('invalid strict group-media attachment commitment');
    }
  }

  factory ProtectedGroupMediaAttachmentCommitment.fromJson(
    Object? value, {
    required List<String> recipientPeerIds,
    required String custodyKind,
    required String custodyContract,
  }) {
    final map = _strictMap(value, 'media attachment commitment');
    _requireAllowedAndRequiredKeys(
      map,
      allowed: const <String>{
        'attachmentId',
        'custodyBlobId',
        'ciphertextSha256',
        'ciphertextSize',
        'mime',
        'mediaType',
        'width',
        'height',
        'durationMs',
        'waveform',
        'encryptionScheme',
        'encryptionKeyBase64',
        'encryptionNonce',
        'caption',
        'expiresAtMs',
      },
      required: const <String>{
        'attachmentId',
        'custodyBlobId',
        'ciphertextSha256',
        'ciphertextSize',
        'mime',
        'mediaType',
        'encryptionScheme',
        'encryptionKeyBase64',
        'encryptionNonce',
        'expiresAtMs',
      },
    );
    if (custodyKind != groupMediaBlobCustodyKind ||
        custodyContract != groupMediaBlobCustodyContract) {
      throw const FormatException('invalid group-media custody authority');
    }
    final rawExpiries = map['expiresAtMs'];
    if (rawExpiries is! List || rawExpiries.length != recipientPeerIds.length) {
      throw const FormatException('invalid group-media expiry matrix');
    }
    final rawWaveform = map['waveform'];
    if (rawWaveform != null && rawWaveform is! List) {
      throw const FormatException('invalid group-media waveform');
    }
    final rawWaveformList = rawWaveform as List?;
    return ProtectedGroupMediaAttachmentCommitment(
      attachmentId: map['attachmentId'] as String,
      custodyBlobId: map['custodyBlobId'] as String,
      ciphertextSha256: map['ciphertextSha256'] as String,
      ciphertextSize: _strictInt(map['ciphertextSize'], 'ciphertextSize'),
      mime: map['mime'] as String,
      mediaType: map['mediaType'] as String,
      width: _nullableStrictInt(map['width'], 'width'),
      height: _nullableStrictInt(map['height'], 'height'),
      durationMs: _nullableStrictInt(map['durationMs'], 'durationMs'),
      waveform: rawWaveformList == null
          ? const <double>[]
          : rawWaveformList
                .map((value) {
                  if (value is! num) {
                    throw const FormatException('invalid waveform sample');
                  }
                  return value.toDouble();
                })
                .toList(growable: false),
      encryptionScheme: map['encryptionScheme'] as String,
      encryptionKeyBase64: map['encryptionKeyBase64'] as String,
      encryptionNonce: map['encryptionNonce'] as String,
      caption: map['caption'] as String?,
      targets: List<GroupMediaBlobTargetCommitment>.generate(
        recipientPeerIds.length,
        (index) => GroupMediaBlobTargetCommitment(
          recipientPeerId: recipientPeerIds[index],
          custodyKind: custodyKind,
          custodyContract: custodyContract,
          expiresAtMs: _strictInt(rawExpiries[index], 'expiresAtMs'),
        ),
        growable: false,
      ),
    );
  }

  final String attachmentId;
  final String custodyBlobId;
  final String ciphertextSha256;
  final int ciphertextSize;
  final String mime;
  final String mediaType;
  final int? width;
  final int? height;
  final int? durationMs;
  final List<double> waveform;
  final String encryptionScheme;
  final String encryptionKeyBase64;
  final String encryptionNonce;
  final String? caption;
  final List<GroupMediaBlobTargetCommitment> targets;

  Set<String> get recipientPeerIds =>
      targets.map((target) => target.recipientPeerId).toSet();

  GroupMediaBlobTargetCommitment? targetFor(String recipientPeerId) {
    for (final target in targets) {
      if (target.recipientPeerId == recipientPeerId) return target;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'attachmentId': attachmentId,
    'custodyBlobId': custodyBlobId,
    'ciphertextSha256': ciphertextSha256,
    'ciphertextSize': ciphertextSize,
    'mime': mime,
    'mediaType': mediaType,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (durationMs != null) 'durationMs': durationMs,
    if (waveform.isNotEmpty) 'waveform': waveform,
    'encryptionScheme': encryptionScheme,
    'encryptionKeyBase64': encryptionKeyBase64,
    'encryptionNonce': encryptionNonce,
    if (caption != null) 'caption': caption,
    'expiresAtMs': targets.map((target) => target.expiresAtMs).toList(),
  };
}

/// Canonical target-to-attachment matrix carried inside `group_content_v1`.
final class ProtectedGroupMediaManifest {
  ProtectedGroupMediaManifest({
    required String groupId,
    required String messageId,
    required Iterable<ProtectedGroupMediaAttachmentCommitment> attachments,
  }) : groupId = _canonicalString(groupId, 'groupId'),
       messageId = _canonicalString(messageId, 'messageId'),
       attachments = _canonicalAttachments(attachments) {
    if (this.attachments.isEmpty) {
      throw ArgumentError('strict group-media manifest has no attachments');
    }
    final expectedTargets = this.attachments.first.recipientPeerIds;
    if (expectedTargets.length > protectedGroupMediaMaxPhysicalRecipients) {
      throw ArgumentError('strict group-media physical ACL exceeds support');
    }
    if (this.attachments.any(
      (attachment) =>
          !_sameStrings(attachment.recipientPeerIds, expectedTargets),
    )) {
      throw ArgumentError('strict group-media target matrices differ');
    }
  }

  factory ProtectedGroupMediaManifest.fromJson(Object? value) {
    final map = _strictMap(value, 'group-media manifest');
    _requireExactKeys(map, const <String>{
      'schema',
      'groupId',
      'messageId',
      'custodyKind',
      'custodyContract',
      'recipientPeerIds',
      'attachments',
    });
    if (map['schema'] != protectedGroupMediaManifestSchema ||
        map['custodyKind'] != groupMediaBlobCustodyKind ||
        map['custodyContract'] != groupMediaBlobCustodyContract ||
        map['attachments'] is! List) {
      throw const FormatException('invalid group-media manifest');
    }
    final recipientPeerIds = _strictStringList(
      map['recipientPeerIds'],
      'recipientPeerIds',
    );
    final rawAttachments = map['attachments'] as List;
    final parsed = rawAttachments
        .map(
          (value) => ProtectedGroupMediaAttachmentCommitment.fromJson(
            value,
            recipientPeerIds: recipientPeerIds,
            custodyKind: map['custodyKind'] as String,
            custodyContract: map['custodyContract'] as String,
          ),
        )
        .toList(growable: false);
    if (!_strictlySorted(parsed.map((entry) => entry.attachmentId).toList())) {
      throw const FormatException('group-media attachments are not canonical');
    }
    return ProtectedGroupMediaManifest(
      groupId: map['groupId'] as String,
      messageId: map['messageId'] as String,
      attachments: parsed,
    );
  }

  factory ProtectedGroupMediaManifest.decode(String raw) {
    try {
      return ProtectedGroupMediaManifest.fromJson(jsonDecode(raw));
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('invalid group-media manifest', error);
    }
  }

  final String groupId;
  final String messageId;
  final List<ProtectedGroupMediaAttachmentCommitment> attachments;

  List<String> get recipientPeerIds => attachments.first.targets
      .map((target) => target.recipientPeerId)
      .toList(growable: false);

  int contentExpiresAtOrBeforeMsFor(String recipientPeerId) {
    var ceiling = 0;
    for (final attachment in attachments) {
      final target = attachment.targetFor(recipientPeerId);
      if (target == null) {
        throw ArgumentError.value(
          recipientPeerId,
          'recipientPeerId',
          'is absent from the strict group-media manifest',
        );
      }
      if (ceiling == 0 || target.expiresAtMs < ceiling) {
        ceiling = target.expiresAtMs;
      }
    }
    return ceiling;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': protectedGroupMediaManifestSchema,
    'groupId': groupId,
    'messageId': messageId,
    'custodyKind': groupMediaBlobCustodyKind,
    'custodyContract': groupMediaBlobCustodyContract,
    'recipientPeerIds': recipientPeerIds,
    'attachments': attachments.map((entry) => entry.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());

  String get fingerprintSha256 =>
      sha256.convert(utf8.encode(encode())).toString();

  bool matchesAuthority({
    required String expectedGroupId,
    required String expectedMessageId,
    required Iterable<String> expectedRecipientPeerIds,
  }) =>
      groupId == expectedGroupId &&
      messageId == expectedMessageId &&
      _sameStrings(recipientPeerIds.toSet(), expectedRecipientPeerIds.toSet());
}

typedef VerifyPreparedGroupMediaManifest =
    Future<bool> Function(ProtectedGroupMediaManifest manifest);

/// One-shot proof that the manifest's exact artifacts, per-target custody
/// rows and accepted receipts are durable before `group_content_v1` is armed.
///
/// The application coordinator constructs this only after staging and upload;
/// the raw sender consumes it under the same group-authority phase as content
/// persistence. Reuse or a false durable recheck fails closed.
final class PreparedGroupMediaManifestAuthority {
  PreparedGroupMediaManifestAuthority({
    required this.manifest,
    required VerifyPreparedGroupMediaManifest verifyDurableAuthority,
  }) : _verifyDurableAuthority = verifyDurableAuthority;

  final ProtectedGroupMediaManifest manifest;
  final VerifyPreparedGroupMediaManifest _verifyDurableAuthority;
  bool _claimed = false;

  Future<bool> claimAndVerify({
    required String groupId,
    required String messageId,
    required Iterable<String> recipientPeerIds,
  }) async {
    if (_claimed ||
        !manifest.matchesAuthority(
          expectedGroupId: groupId,
          expectedMessageId: messageId,
          expectedRecipientPeerIds: recipientPeerIds,
        )) {
      return false;
    }
    _claimed = true;
    try {
      return await _verifyDurableAuthority(manifest);
    } on Object {
      return false;
    }
  }
}

String deterministicGroupMediaCustodyBlobId({
  required String groupId,
  required String messageId,
  required String attachmentId,
}) {
  final canonical = <String>[
    _canonicalString(groupId, 'groupId'),
    _canonicalString(messageId, 'messageId'),
    _canonicalString(attachmentId, 'attachmentId'),
  ];
  final digest = sha256
      .convert(
        utf8.encode(
          'mknoon:group-media-blob:v1\u0000${canonical.join('\u0000')}',
        ),
      )
      .toString();
  return 'gmb1_$digest';
}

bool protectedGroupContentFitsRelayFrame(String encodedEnvelope) =>
    utf8.encode(encodedEnvelope).length <= protectedGroupContentMaxFrameBytes;

List<GroupMediaBlobTargetCommitment> _canonicalTargets(
  Iterable<GroupMediaBlobTargetCommitment> targets,
) {
  final result = targets.toList()
    ..sort(
      (left, right) => left.recipientPeerId.compareTo(right.recipientPeerId),
    );
  if (result.map((target) => target.recipientPeerId).toSet().length !=
      result.length) {
    throw ArgumentError('duplicate strict group-media recipient');
  }
  return List<GroupMediaBlobTargetCommitment>.unmodifiable(result);
}

List<ProtectedGroupMediaAttachmentCommitment> _canonicalAttachments(
  Iterable<ProtectedGroupMediaAttachmentCommitment> attachments,
) {
  final result = attachments.toList()
    ..sort((left, right) => left.attachmentId.compareTo(right.attachmentId));
  if (result.map((entry) => entry.attachmentId).toSet().length !=
          result.length ||
      result.map((entry) => entry.custodyBlobId).toSet().length !=
          result.length) {
    throw ArgumentError('duplicate strict group-media attachment authority');
  }
  return List<ProtectedGroupMediaAttachmentCommitment>.unmodifiable(result);
}

Map<String, Object?> _strictMap(Object? value, String field) {
  if (value is! Map) throw FormatException('invalid $field');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('invalid $field key');
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<String> _strictStringList(Object? value, String field) {
  if (value is! List || value.any((entry) => entry is! String)) {
    throw FormatException('invalid $field');
  }
  final result = value.cast<String>().toList(growable: false);
  if (result.any((entry) => entry.isEmpty || entry.trim() != entry) ||
      !_strictlySorted(result)) {
    throw FormatException('non-canonical $field');
  }
  return result;
}

void _requireExactKeys(Map<String, Object?> map, Set<String> expected) {
  if (!_sameStrings(map.keys.toSet(), expected)) {
    throw const FormatException('non-canonical group-media fields');
  }
}

void _requireAllowedAndRequiredKeys(
  Map<String, Object?> map, {
  required Set<String> allowed,
  required Set<String> required,
}) {
  if (map.keys.any((key) => !allowed.contains(key)) ||
      required.any((key) => !map.containsKey(key))) {
    throw const FormatException('non-canonical group-media fields');
  }
}

String _canonicalString(String value, String field) {
  if (value.isEmpty || value.trim() != value) {
    throw ArgumentError.value(value, field, 'must be non-blank and trimmed');
  }
  return value;
}

String? _nullableCanonicalString(String? value, String field) =>
    value == null ? null : _canonicalString(value, field);

int _strictInt(Object? value, String field) {
  if (value is! int) throw FormatException('invalid $field');
  return value;
}

int? _nullableStrictInt(Object? value, String field) =>
    value == null ? null : _strictInt(value, field);

bool _strictlySorted(List<String> values) {
  for (var index = 1; index < values.length; index++) {
    if (values[index - 1].compareTo(values[index]) >= 0) return false;
  }
  return true;
}

bool _sameStrings(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
