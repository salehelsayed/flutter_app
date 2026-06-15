import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

enum MigrationTransferManifestError {
  unsupportedProtocolVersion,
  importerTooOld,
  senderTooOld,
  emptySessionId,
  emptyBundleId,
  invalidSegmentSize,
  invalidTotalBytes,
  missingManifestHash,
  missingSessionKem,
  missingEntry,
  invalidEntry,
  missingSegment,
  segmentIndexMismatch,
  duplicateSegmentIndex,
  duplicateNonce,
  segmentOffsetMismatch,
  segmentLengthMismatch,
  segmentChecksumMissing,
  segmentCiphertextChecksumMissing,
}

class MigrationTransferSegmentDescriptor {
  final int index;
  final int offset;
  final int plaintextLength;
  final String plaintextSha256;
  final String ciphertextSha256;
  final String nonce;

  const MigrationTransferSegmentDescriptor({
    required this.index,
    required this.offset,
    required this.plaintextLength,
    required this.plaintextSha256,
    required this.ciphertextSha256,
    required this.nonce,
  });

  Map<String, Object?> toJson() {
    return {
      'index': index,
      'offset': offset,
      'plaintext_length': plaintextLength,
      'plaintext_sha256': plaintextSha256,
      'ciphertext_sha256': ciphertextSha256,
      'nonce': nonce,
    };
  }
}

enum MigrationTransferEntryKind {
  database,
  file,
  secureValues,
}

class MigrationTransferSessionKem {
  final String algorithm;
  final String direction;
  final String? kemCiphertext;

  const MigrationTransferSessionKem({
    required this.algorithm,
    required this.direction,
    this.kemCiphertext,
  });

  Map<String, Object?> toJson() {
    return {
      'algorithm': algorithm,
      'direction': direction,
      if (kemCiphertext != null) 'kem_ciphertext': kemCiphertext,
    };
  }

  factory MigrationTransferSessionKem.fromJson(Map<String, dynamic> json) {
    return MigrationTransferSessionKem(
      algorithm: json['algorithm'] as String,
      direction: json['direction'] as String,
      kemCiphertext: json['kem_ciphertext'] as String?,
    );
  }
}

class MigrationTransferEntryDescriptor {
  final String entryId;
  final MigrationTransferEntryKind kind;
  final String? relativePath;
  final int sizeBytes;
  final String sha256;
  final int chunkSize;
  final int chunkCount;

  const MigrationTransferEntryDescriptor({
    required this.entryId,
    required this.kind,
    this.relativePath,
    required this.sizeBytes,
    required this.sha256,
    required this.chunkSize,
    required this.chunkCount,
  });

  Map<String, Object?> toJson() {
    return {
      'entry_id': entryId,
      'kind': kind.name,
      if (relativePath != null) 'relative_path': relativePath,
      'size_bytes': sizeBytes,
      'sha256': sha256,
      'chunk_size': chunkSize,
      'chunk_count': chunkCount,
    };
  }

  factory MigrationTransferEntryDescriptor.fromJson(
    Map<String, dynamic> json,
  ) {
    return MigrationTransferEntryDescriptor(
      entryId: json['entry_id'] as String,
      kind: MigrationTransferEntryKind.values.byName(json['kind'] as String),
      relativePath: json['relative_path'] as String?,
      sizeBytes: json['size_bytes'] as int,
      sha256: json['sha256'] as String,
      chunkSize: json['chunk_size'] as int,
      chunkCount: json['chunk_count'] as int,
    );
  }
}

class MigrationTransferManifest {
  static const int legacyProtocolVersion = 1;
  static const int protocolVersion = 2;

  final int protocolVersionValue;
  final int minimumImporterProtocolVersion;
  final String sessionId;
  final String bundleId;
  final int segmentSize;
  final int totalBytes;
  final String manifestSha256;
  final MigrationTransferSessionKem? sessionKem;
  final List<MigrationTransferEntryDescriptor> entries;
  final List<MigrationTransferSegmentDescriptor> segments;

  const MigrationTransferManifest({
    this.protocolVersionValue = protocolVersion,
    this.minimumImporterProtocolVersion = protocolVersion,
    required this.sessionId,
    required this.bundleId,
    required this.segmentSize,
    required this.totalBytes,
    required this.manifestSha256,
    this.sessionKem,
    this.entries = const [],
    this.segments = const [],
  });

  factory MigrationTransferManifest.legacyV1({
    int protocolVersionValue = legacyProtocolVersion,
    int minimumImporterProtocolVersion = legacyProtocolVersion,
    required String sessionId,
    required String bundleId,
    required int segmentSize,
    required int totalBytes,
    required String manifestSha256,
    required List<MigrationTransferSegmentDescriptor> segments,
  }) {
    return MigrationTransferManifest(
      protocolVersionValue: protocolVersionValue,
      minimumImporterProtocolVersion: minimumImporterProtocolVersion,
      sessionId: sessionId,
      bundleId: bundleId,
      segmentSize: segmentSize,
      totalBytes: totalBytes,
      manifestSha256: manifestSha256,
      segments: segments,
    );
  }

  factory MigrationTransferManifest.v2({
    int protocolVersionValue = protocolVersion,
    int minimumImporterProtocolVersion = protocolVersion,
    required String sessionId,
    required String bundleId,
    required int totalBytes,
    required String manifestSha256,
    required MigrationTransferSessionKem sessionKem,
    required List<MigrationTransferEntryDescriptor> entries,
  }) {
    var maxChunkSize = 0;
    for (final entry in entries) {
      if (entry.chunkSize > maxChunkSize) {
        maxChunkSize = entry.chunkSize;
      }
    }
    return MigrationTransferManifest(
      protocolVersionValue: protocolVersionValue,
      minimumImporterProtocolVersion: minimumImporterProtocolVersion,
      sessionId: sessionId,
      bundleId: bundleId,
      segmentSize: maxChunkSize == 0 ? 1 : maxChunkSize,
      totalBytes: totalBytes,
      manifestSha256: manifestSha256,
      sessionKem: sessionKem,
      entries: entries,
      segments: const [],
    );
  }

  factory MigrationTransferManifest.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    final rawSegments = json['segments'];
    final rawSessionKem = json['session_kem'];
    return MigrationTransferManifest(
      protocolVersionValue: json['protocol_version'] as int,
      minimumImporterProtocolVersion:
          json['minimum_importer_protocol_version'] as int,
      sessionId: json['session_id'] as String,
      bundleId: json['bundle_id'] as String,
      segmentSize: (json['segment_size'] as int?) ?? 1,
      totalBytes: json['total_bytes'] as int,
      manifestSha256: json['manifest_sha256'] as String,
      sessionKem: rawSessionKem is Map
          ? MigrationTransferSessionKem.fromJson(
              Map<String, dynamic>.from(rawSessionKem),
            )
          : null,
      entries: rawEntries is List
          ? rawEntries
                .whereType<Map>()
                .map(
                  (entry) => MigrationTransferEntryDescriptor.fromJson(
                    Map<String, dynamic>.from(entry),
                  ),
                )
                .toList(growable: false)
          : const [],
      segments: rawSegments is List
          ? rawSegments
                .whereType<Map>()
                .map(
                  (entry) => MigrationTransferSegmentDescriptor(
                    index: entry['index'] as int,
                    offset: entry['offset'] as int,
                    plaintextLength: entry['plaintext_length'] as int,
                    plaintextSha256: entry['plaintext_sha256'] as String,
                    ciphertextSha256: entry['ciphertext_sha256'] as String,
                    nonce: entry['nonce'] as String,
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }

  MigrationTransferManifest copyWith({
    int? protocolVersionValue,
    int? minimumImporterProtocolVersion,
    String? sessionId,
    String? bundleId,
    int? segmentSize,
    int? totalBytes,
    String? manifestSha256,
    MigrationTransferSessionKem? sessionKem,
    List<MigrationTransferEntryDescriptor>? entries,
    List<MigrationTransferSegmentDescriptor>? segments,
  }) {
    return MigrationTransferManifest(
      protocolVersionValue: protocolVersionValue ?? this.protocolVersionValue,
      minimumImporterProtocolVersion:
          minimumImporterProtocolVersion ?? this.minimumImporterProtocolVersion,
      sessionId: sessionId ?? this.sessionId,
      bundleId: bundleId ?? this.bundleId,
      segmentSize: segmentSize ?? this.segmentSize,
      totalBytes: totalBytes ?? this.totalBytes,
      manifestSha256: manifestSha256 ?? this.manifestSha256,
      sessionKem: sessionKem ?? this.sessionKem,
      entries: entries ?? this.entries,
      segments: segments ?? this.segments,
    );
  }

  List<MigrationTransferSegmentDescriptor> get orderedSegments {
    return [...segments]..sort((a, b) => a.index.compareTo(b.index));
  }

  List<MigrationTransferEntryDescriptor> get orderedEntries {
    return [...entries]..sort((a, b) => a.entryId.compareTo(b.entryId));
  }

  MigrationTransferManifestCompatibility compatibility({
    int? importerProtocolVersion,
  }) {
    final errors = <MigrationTransferManifestError>[];
    // With no explicit importer version, validate against the newest protocol
    // this build supports; senderTooOld only applies when a concrete importer
    // version is being checked (a v1 manifest is still self-consistent).
    final importerVersion = importerProtocolVersion ?? protocolVersion;
    if (protocolVersionValue != legacyProtocolVersion &&
        protocolVersionValue != protocolVersion) {
      errors.add(MigrationTransferManifestError.unsupportedProtocolVersion);
    }
    if (protocolVersionValue > importerVersion ||
        minimumImporterProtocolVersion > importerVersion) {
      errors.add(MigrationTransferManifestError.importerTooOld);
    }
    if (importerProtocolVersion != null &&
        protocolVersionValue < importerVersion) {
      errors.add(MigrationTransferManifestError.senderTooOld);
    }
    if (sessionId.trim().isEmpty) {
      errors.add(MigrationTransferManifestError.emptySessionId);
    }
    if (bundleId.trim().isEmpty) {
      errors.add(MigrationTransferManifestError.emptyBundleId);
    }
    if (segmentSize <= 0) {
      errors.add(MigrationTransferManifestError.invalidSegmentSize);
    }
    if (totalBytes < 0) {
      errors.add(MigrationTransferManifestError.invalidTotalBytes);
    }
    if (manifestSha256.trim().isEmpty) {
      errors.add(MigrationTransferManifestError.missingManifestHash);
    }

    if (protocolVersionValue == protocolVersion) {
      _validateV2(errors);
      return MigrationTransferManifestCompatibility(errors);
    }

    _validateLegacySegments(errors);
    return MigrationTransferManifestCompatibility(errors);
  }

  void _validateV2(List<MigrationTransferManifestError> errors) {
    if (sessionKem == null ||
        sessionKem!.algorithm.trim().isEmpty ||
        sessionKem!.direction.trim().isEmpty) {
      errors.add(MigrationTransferManifestError.missingSessionKem);
    }
    if (totalBytes > 0 && entries.isEmpty) {
      errors.add(MigrationTransferManifestError.missingEntry);
    }

    final seenEntries = <String>{};
    var totalEntryBytes = 0;
    for (final entry in entries) {
      if (entry.entryId.trim().isEmpty || !seenEntries.add(entry.entryId)) {
        errors.add(MigrationTransferManifestError.invalidEntry);
      }
      if (entry.kind == MigrationTransferEntryKind.file &&
          (entry.relativePath == null || entry.relativePath!.trim().isEmpty)) {
        errors.add(MigrationTransferManifestError.invalidEntry);
      }
      if (entry.sizeBytes < 0 ||
          entry.sha256.trim().isEmpty ||
          entry.chunkSize <= 0 ||
          entry.chunkCount <= 0) {
        errors.add(MigrationTransferManifestError.invalidEntry);
      }
      final expectedChunkCount = entry.sizeBytes == 0
          ? 1
          : ((entry.sizeBytes + entry.chunkSize - 1) ~/ entry.chunkSize);
      if (entry.chunkCount != expectedChunkCount) {
        errors.add(MigrationTransferManifestError.invalidEntry);
      }
      totalEntryBytes += entry.sizeBytes;
    }
    if (totalEntryBytes != totalBytes) {
      errors.add(MigrationTransferManifestError.invalidTotalBytes);
    }
    if (segments.isNotEmpty) {
      errors.add(MigrationTransferManifestError.invalidEntry);
    }
  }

  void _validateLegacySegments(List<MigrationTransferManifestError> errors) {
    if (totalBytes > 0 && segments.isEmpty) {
      errors.add(MigrationTransferManifestError.missingSegment);
    }

    final ordered = orderedSegments;
    final seenIndexes = <int>{};
    final seenNonces = <String>{};
    var expectedOffset = 0;
    for (var position = 0; position < ordered.length; position += 1) {
      final segment = ordered[position];
      if (!seenIndexes.add(segment.index)) {
        errors.add(MigrationTransferManifestError.duplicateSegmentIndex);
      }
      if (segment.index != position) {
        errors.add(MigrationTransferManifestError.segmentIndexMismatch);
      }
      if (segment.nonce.trim().isEmpty || !seenNonces.add(segment.nonce)) {
        errors.add(MigrationTransferManifestError.duplicateNonce);
      }
      if (segment.offset != expectedOffset) {
        errors.add(MigrationTransferManifestError.segmentOffsetMismatch);
      }
      if (segment.plaintextLength <= 0 ||
          (position < ordered.length - 1 &&
              segment.plaintextLength != segmentSize) ||
          segment.plaintextLength > segmentSize) {
        errors.add(MigrationTransferManifestError.segmentLengthMismatch);
      }
      if (segment.plaintextSha256.trim().isEmpty) {
        errors.add(MigrationTransferManifestError.segmentChecksumMissing);
      }
      if (segment.ciphertextSha256.trim().isEmpty) {
        errors.add(
          MigrationTransferManifestError.segmentCiphertextChecksumMissing,
        );
      }
      expectedOffset += segment.plaintextLength;
    }
    if (expectedOffset != totalBytes) {
      errors.add(MigrationTransferManifestError.invalidTotalBytes);
    }
  }

  bool hasSegment(int index) {
    return segments.any((segment) => segment.index == index);
  }

  bool get isEntryStreamed => protocolVersionValue == protocolVersion;

  MigrationTransferEntryDescriptor? entryById(String entryId) {
    for (final entry in entries) {
      if (entry.entryId == entryId) {
        return entry;
      }
    }
    return null;
  }

  /// Total chunks actually transmitted: zero-size entries are verified from
  /// the manifest hash alone and never produce a wire chunk.
  int get totalChunkCount {
    var total = 0;
    for (final entry in entries) {
      if (entry.sizeBytes > 0) {
        total += entry.chunkCount;
      }
    }
    return total;
  }

  /// Bytes that still need receiver-side validation work at complete():
  /// the staged database open/checksum plus the metadata blob parse. Media
  /// entries are already hash-verified per chunk, so they no longer scale
  /// the complete budget.
  int get importValidationBytes {
    var total = 0;
    for (final entry in entries) {
      if (entry.kind == MigrationTransferEntryKind.database ||
          entry.kind == MigrationTransferEntryKind.secureValues) {
        total += entry.sizeBytes;
      }
    }
    return total;
  }

  List<int> missingIndexes(Set<int> verifiedIndexes) {
    return orderedSegments
        .where((segment) => !verifiedIndexes.contains(segment.index))
        .map((segment) => segment.index)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return {
      'protocol_version': protocolVersionValue,
      'minimum_importer_protocol_version': minimumImporterProtocolVersion,
      'session_id': sessionId,
      'bundle_id': bundleId,
      'segment_size': segmentSize,
      'total_bytes': totalBytes,
      'manifest_sha256': manifestSha256,
      if (sessionKem != null) 'session_kem': sessionKem!.toJson(),
      if (entries.isNotEmpty)
        'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'segments': orderedSegments
          .map((segment) => segment.toJson())
          .toList(growable: false),
    };
  }
}

class MigrationTransferManifestCompatibility {
  final List<MigrationTransferManifestError> errors;

  const MigrationTransferManifestCompatibility(this.errors);

  bool get isAccepted => errors.isEmpty;

  bool hasError(MigrationTransferManifestError error) {
    return errors.contains(error);
  }
}

String migrationTransferCanonicalJson(Object? value) {
  return jsonEncode(_canonicalize(value));
}

String migrationTransferSha256Hex(List<int> bytes) {
  return sha256.convert(bytes).toString();
}

String migrationTransferStringSha256Hex(String value) {
  return migrationTransferSha256Hex(utf8.encode(value));
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
