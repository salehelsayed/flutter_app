import 'dart:convert';

import 'package:crypto/crypto.dart';

const kDirectMediaBlobCustodyKind = 'direct_media_blob_v1';
const kDirectMediaBlobCustodyContract = 'ack_or_expiry_v1';
const kDirectMediaBlobTransportMime = 'application/octet-stream';
const kDirectMediaBlobManifestDomain = 'mknoon.direct-media-blob-manifest.v1';

final RegExp _lowercaseSha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// Public, recipient-verifiable commitment to one protected direct-media blob.
///
/// This projection intentionally contains no local path, relay identity, store
/// status, encryption key, or nonce. Those values remain local durable state.
final class DirectMediaBlobCustodyCommitment {
  const DirectMediaBlobCustodyCommitment({
    this.kind = kDirectMediaBlobCustodyKind,
    this.contract = kDirectMediaBlobCustodyContract,
    required this.contentHash,
    required this.ciphertextSize,
    this.transportMime = kDirectMediaBlobTransportMime,
    required this.expiresAtMs,
  });

  final String kind;
  final String contract;
  final String contentHash;
  final int ciphertextSize;
  final String transportMime;
  final int expiresAtMs;

  bool get isValid =>
      kind == kDirectMediaBlobCustodyKind &&
      contract == kDirectMediaBlobCustodyContract &&
      _lowercaseSha256Pattern.hasMatch(contentHash) &&
      ciphertextSize > 0 &&
      transportMime == kDirectMediaBlobTransportMime &&
      expiresAtMs > 0;

  factory DirectMediaBlobCustodyCommitment.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('blobCustody must be an object');
    }
    final json = Map<String, Object?>.from(value);
    const expectedKeys = <String>{
      'kind',
      'contract',
      'contentHash',
      'ciphertextSize',
      'transportMime',
      'expiresAtMs',
    };
    if (json.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(json.keys.toSet()).isNotEmpty) {
      throw const FormatException('blobCustody has an invalid shape');
    }
    final commitment = DirectMediaBlobCustodyCommitment(
      kind: json['kind'] as String? ?? '',
      contract: json['contract'] as String? ?? '',
      contentHash: json['contentHash'] as String? ?? '',
      ciphertextSize: (json['ciphertextSize'] as num?)?.toInt() ?? 0,
      transportMime: json['transportMime'] as String? ?? '',
      expiresAtMs: (json['expiresAtMs'] as num?)?.toInt() ?? 0,
    );
    if (json['ciphertextSize'] is! int ||
        json['expiresAtMs'] is! int ||
        !commitment.isValid) {
      throw const FormatException('blobCustody contains invalid authority');
    }
    return commitment;
  }

  Map<String, Object> toJson() {
    if (!isValid) {
      throw const FormatException('cannot serialize invalid blobCustody');
    }
    return <String, Object>{
      'kind': kind,
      'contract': contract,
      'contentHash': contentHash,
      'ciphertextSize': ciphertextSize,
      'transportMime': transportMime,
      'expiresAtMs': expiresAtMs,
    };
  }

  List<Object> manifestProjection(String attachmentId) {
    if (attachmentId.trim().isEmpty || attachmentId != attachmentId.trim()) {
      throw const FormatException('invalid blob attachment id');
    }
    if (!isValid) {
      throw const FormatException('invalid blob custody commitment');
    }
    return <Object>[
      attachmentId,
      kind,
      contract,
      contentHash,
      ciphertextSize,
      transportMime,
      expiresAtMs,
    ];
  }
}

final class DirectMediaBlobManifestProjection {
  const DirectMediaBlobManifestProjection({
    required this.attachmentId,
    required this.commitment,
  });

  final String attachmentId;
  final DirectMediaBlobCustodyCommitment commitment;
}

/// Exact, validated relay authority returned by a strict upload.
///
/// [storeStatus] is deliberately ephemeral and is not part of the durable DB
/// row. Durable state records only the exact proof tuple and selected relay.
final class DirectMediaBlobUploadReceipt {
  const DirectMediaBlobUploadReceipt({
    required this.commitment,
    required this.custodyRelayPeerId,
    required this.storeStatus,
  });

  final DirectMediaBlobCustodyCommitment commitment;
  final String custodyRelayPeerId;
  final String storeStatus;

  static DirectMediaBlobUploadReceipt? parseExact({
    required Map<String, dynamic> response,
    required String attachmentId,
    required String contentHash,
    required int ciphertextSize,
  }) {
    final relay = response['custodyRelayPeerId'];
    final status = response['storeStatus'];
    final expiresAtMs = response['expiresAtMs'];
    final exact =
        response['ok'] == true &&
        response['id'] == attachmentId &&
        (status == 'stored' || status == 'duplicate') &&
        response['custodyKind'] == kDirectMediaBlobCustodyKind &&
        response['custodyContract'] == kDirectMediaBlobCustodyContract &&
        response['contentHash'] == contentHash &&
        response['size'] == ciphertextSize &&
        response['mime'] == kDirectMediaBlobTransportMime &&
        expiresAtMs is int &&
        expiresAtMs > 0 &&
        relay is String &&
        relay.trim().isNotEmpty &&
        relay == relay.trim();
    if (!exact) return null;
    final commitment = DirectMediaBlobCustodyCommitment(
      contentHash: contentHash,
      ciphertextSize: ciphertextSize,
      expiresAtMs: expiresAtMs,
    );
    if (!commitment.isValid) return null;
    return DirectMediaBlobUploadReceipt(
      commitment: commitment,
      custodyRelayPeerId: relay,
      storeStatus: status as String,
    );
  }
}

/// Computes the exact v108 binding for a complete strict attachment manifest.
///
/// Attachment order supplied by a caller is ignored. Duplicate or empty IDs,
/// an empty manifest, and invalid commitments fail closed.
String computeDirectMediaBlobManifestHash(
  Iterable<DirectMediaBlobManifestProjection> manifest,
) {
  final sorted = manifest.toList(growable: false)
    ..sort((left, right) => left.attachmentId.compareTo(right.attachmentId));
  if (sorted.isEmpty) {
    throw const FormatException('strict blob manifest must not be empty');
  }
  for (var index = 0; index < sorted.length; index++) {
    if (index > 0 &&
        sorted[index - 1].attachmentId == sorted[index].attachmentId) {
      throw const FormatException('duplicate strict blob attachment id');
    }
  }
  final canonical = <Object>[
    kDirectMediaBlobManifestDomain,
    ...sorted.map(
      (entry) => entry.commitment.manifestProjection(entry.attachmentId),
    ),
  ];
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

/// Local-only exact adoption fingerprint for one strict attachment.
///
/// This intentionally persists only a one-way digest of the public commitment,
/// never the commitment fields themselves. Including [attachmentId] prevents a
/// valid proof for one row from being adopted by another row after v111 ACK or
/// expiry convergence removes the independent custody record.
String computeDirectMediaBlobCommitmentFingerprint({
  required String attachmentId,
  required DirectMediaBlobCustodyCommitment commitment,
}) => computeDirectMediaBlobManifestHash(<DirectMediaBlobManifestProjection>[
  DirectMediaBlobManifestProjection(
    attachmentId: attachmentId,
    commitment: commitment,
  ),
]);

int earliestDirectMediaBlobExpiryMs(
  Iterable<DirectMediaBlobManifestProjection> manifest,
) {
  final entries = manifest.toList(growable: false);
  if (entries.isEmpty) {
    throw const FormatException('strict blob manifest must not be empty');
  }
  var earliest = entries.first.commitment.expiresAtMs;
  for (final entry in entries) {
    if (!entry.commitment.isValid) {
      throw const FormatException('invalid blob custody commitment');
    }
    if (entry.commitment.expiresAtMs < earliest) {
      earliest = entry.commitment.expiresAtMs;
    }
  }
  return earliest;
}
