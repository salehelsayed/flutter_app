import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';

enum MigrationCheckpointWriteResult { recorded, alreadyVerified, conflict }

class MigrationVerifiedSegment {
  final int index;
  final int plaintextLength;
  final String plaintextSha256;
  final String ciphertextSha256;

  const MigrationVerifiedSegment({
    required this.index,
    required this.plaintextLength,
    required this.plaintextSha256,
    required this.ciphertextSha256,
  });

  bool matches(MigrationTransferSegmentDescriptor descriptor) {
    return index == descriptor.index &&
        plaintextLength == descriptor.plaintextLength &&
        plaintextSha256 == descriptor.plaintextSha256 &&
        ciphertextSha256 == descriptor.ciphertextSha256;
  }

  Map<String, Object?> toJson() {
    return {
      'index': index,
      'plaintext_length': plaintextLength,
      'plaintext_sha256': plaintextSha256,
      'ciphertext_sha256': ciphertextSha256,
    };
  }

  factory MigrationVerifiedSegment.fromJson(Map<String, dynamic> json) {
    return MigrationVerifiedSegment(
      index: json['index'] as int,
      plaintextLength: json['plaintext_length'] as int,
      plaintextSha256: json['plaintext_sha256'] as String,
      ciphertextSha256: json['ciphertext_sha256'] as String,
    );
  }
}

abstract class MigrationTransferCheckpointStore {
  Future<MigrationCheckpointWriteResult> markVerified({
    required String sessionId,
    required String bundleId,
    required MigrationVerifiedSegment segment,
  });

  Future<List<MigrationVerifiedSegment>> loadVerified({
    required String sessionId,
    required String bundleId,
  });

  Future<void> clear({required String sessionId, required String bundleId});
}

class InMemoryMigrationTransferCheckpointStore
    implements MigrationTransferCheckpointStore {
  final _segmentsByBundle = <String, Map<int, MigrationVerifiedSegment>>{};

  @override
  Future<MigrationCheckpointWriteResult> markVerified({
    required String sessionId,
    required String bundleId,
    required MigrationVerifiedSegment segment,
  }) async {
    final key = _key(sessionId, bundleId);
    final segments = _segmentsByBundle.putIfAbsent(key, () => {});
    final existing = segments[segment.index];
    if (existing != null) {
      if (existing.plaintextLength == segment.plaintextLength &&
          existing.plaintextSha256 == segment.plaintextSha256 &&
          existing.ciphertextSha256 == segment.ciphertextSha256) {
        return MigrationCheckpointWriteResult.alreadyVerified;
      }
      return MigrationCheckpointWriteResult.conflict;
    }
    segments[segment.index] = segment;
    return MigrationCheckpointWriteResult.recorded;
  }

  @override
  Future<List<MigrationVerifiedSegment>> loadVerified({
    required String sessionId,
    required String bundleId,
  }) async {
    final segments = _segmentsByBundle[_key(sessionId, bundleId)];
    if (segments == null) return const [];
    return segments.values.toList(growable: false)
      ..sort((a, b) => a.index.compareTo(b.index));
  }

  @override
  Future<void> clear({
    required String sessionId,
    required String bundleId,
  }) async {
    _segmentsByBundle.remove(_key(sessionId, bundleId));
  }

  String _key(String sessionId, String bundleId) => '$sessionId::$bundleId';
}

class FileMigrationTransferCheckpointStore
    implements MigrationTransferCheckpointStore {
  final String filePath;

  const FileMigrationTransferCheckpointStore({required this.filePath});

  @override
  Future<MigrationCheckpointWriteResult> markVerified({
    required String sessionId,
    required String bundleId,
    required MigrationVerifiedSegment segment,
  }) async {
    final store = await _loadStore();
    final key = _key(sessionId, bundleId);
    final segments = store.putIfAbsent(key, () => {});
    final existing = segments[segment.index];
    if (existing != null) {
      if (existing.plaintextLength == segment.plaintextLength &&
          existing.plaintextSha256 == segment.plaintextSha256 &&
          existing.ciphertextSha256 == segment.ciphertextSha256) {
        return MigrationCheckpointWriteResult.alreadyVerified;
      }
      return MigrationCheckpointWriteResult.conflict;
    }
    segments[segment.index] = segment;
    await _saveStore(store);
    return MigrationCheckpointWriteResult.recorded;
  }

  @override
  Future<List<MigrationVerifiedSegment>> loadVerified({
    required String sessionId,
    required String bundleId,
  }) async {
    final store = await _loadStore();
    final segments = store[_key(sessionId, bundleId)];
    if (segments == null) return const [];
    return segments.values.toList(growable: false)
      ..sort((a, b) => a.index.compareTo(b.index));
  }

  @override
  Future<void> clear({
    required String sessionId,
    required String bundleId,
  }) async {
    final store = await _loadStore();
    store.remove(_key(sessionId, bundleId));
    await _saveStore(store);
  }

  Future<Map<String, Map<int, MigrationVerifiedSegment>>> _loadStore() async {
    final file = File(filePath);
    if (!await file.exists()) return {};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return {};
    return {
      for (final entry in decoded.entries)
        entry.key: {
          for (final segmentEntry
              in (entry.value as Map<String, dynamic>).entries)
            int.parse(segmentEntry.key): MigrationVerifiedSegment.fromJson(
              Map<String, dynamic>.from(segmentEntry.value as Map),
            ),
        },
    };
  }

  Future<void> _saveStore(
    Map<String, Map<int, MigrationVerifiedSegment>> store,
  ) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        for (final entry in store.entries)
          entry.key: {
            for (final segmentEntry in entry.value.entries)
              segmentEntry.key.toString(): segmentEntry.value.toJson(),
          },
      }),
    );
  }

  String _key(String sessionId, String bundleId) => '$sessionId::$bundleId';
}

Future<List<int>> migrationMissingSegmentIndexes({
  required MigrationTransferCheckpointStore checkpointStore,
  required MigrationTransferManifest manifest,
}) async {
  final verified = await checkpointStore.loadVerified(
    sessionId: manifest.sessionId,
    bundleId: manifest.bundleId,
  );
  return manifest.missingIndexes(
    verified.map((segment) => segment.index).toSet(),
  );
}

/// Per-entry resume ledger for protocol v2 entry-streamed transfers — the
/// checkpoint store's successor. Tracks the verified plaintext offset and
/// incremental hash per entry plus which entries are fully verified, so an
/// interrupted transfer resumes from (entry, offset) instead of restarting.
class MigrationTransferLedgerStatus {
  /// First manifest entry (in manifest order) that is not yet verified, or
  /// null when every entry is verified.
  final String? nextEntryId;

  /// Verified plaintext offset of [nextEntryId] (0 when nothing received).
  final int nextOffset;

  /// Fully verified entry ids in manifest order.
  final List<String> verifiedEntryIds;

  /// Verified plaintext offset per entry id (size for verified entries).
  final Map<String, int> entryOffsets;

  const MigrationTransferLedgerStatus({
    required this.nextEntryId,
    required this.nextOffset,
    required this.verifiedEntryIds,
    required this.entryOffsets,
  });

  Map<String, Object?> toJson() {
    return {
      'next_entry_id': nextEntryId,
      'next_offset': nextOffset,
      'verified_entry_ids': verifiedEntryIds,
      'entry_offsets': entryOffsets,
    };
  }

  factory MigrationTransferLedgerStatus.fromJson(Map<String, dynamic> json) {
    final rawVerified = json['verified_entry_ids'];
    final rawOffsets = json['entry_offsets'];
    return MigrationTransferLedgerStatus(
      nextEntryId: json['next_entry_id'] as String?,
      nextOffset: (json['next_offset'] as int?) ?? 0,
      verifiedEntryIds: rawVerified is List
          ? rawVerified.whereType<String>().toList(growable: false)
          : const [],
      entryOffsets: rawOffsets is Map
          ? {
              for (final entry in rawOffsets.entries)
                entry.key.toString(): entry.value as int,
            }
          : const {},
    );
  }
}

class MigrationTransferLedgerEntry {
  final int verifiedOffset;
  final String incrementalSha256;
  final bool verified;
  final int? sizeBytes;
  final String? sha256;

  const MigrationTransferLedgerEntry({
    required this.verifiedOffset,
    required this.incrementalSha256,
    this.verified = false,
    this.sizeBytes,
    this.sha256,
  });

  Map<String, Object?> toJson() {
    return {
      'verified_offset': verifiedOffset,
      'incremental_sha256': incrementalSha256,
      'verified': verified,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (sha256 != null) 'sha256': sha256,
    };
  }

  factory MigrationTransferLedgerEntry.fromJson(Map<String, dynamic> json) {
    return MigrationTransferLedgerEntry(
      verifiedOffset: json['verified_offset'] as int,
      incrementalSha256: (json['incremental_sha256'] as String?) ?? '',
      verified: (json['verified'] as bool?) ?? false,
      sizeBytes: json['size_bytes'] as int?,
      sha256: json['sha256'] as String?,
    );
  }
}

abstract class MigrationTransferLedgerStore {
  Future<void> recordProgress({
    required MigrationTransferManifest manifest,
    required String entryId,
    required int verifiedOffset,
    required String incrementalSha256,
  });

  Future<void> markEntryVerified({
    required MigrationTransferManifest manifest,
    required String entryId,
    required int sizeBytes,
    required String sha256,
  });

  Future<MigrationTransferLedgerEntry?> entryState({
    required MigrationTransferManifest manifest,
    required String entryId,
  });

  Future<MigrationTransferLedgerStatus> status(
    MigrationTransferManifest manifest,
  );

  Future<int> missingEntryCount(MigrationTransferManifest manifest);

  Future<void> clear({required String sessionId, required String bundleId});
}

class FileMigrationTransferLedgerStore implements MigrationTransferLedgerStore {
  final String filePath;

  const FileMigrationTransferLedgerStore({required this.filePath});

  @override
  Future<void> recordProgress({
    required MigrationTransferManifest manifest,
    required String entryId,
    required int verifiedOffset,
    required String incrementalSha256,
  }) async {
    final store = await _loadLedger();
    final entries = store.putIfAbsent(
      _ledgerKey(manifest.sessionId, manifest.bundleId),
      () => {},
    );
    entries[entryId] = MigrationTransferLedgerEntry(
      verifiedOffset: verifiedOffset,
      incrementalSha256: incrementalSha256,
    );
    await _saveLedger(store);
  }

  @override
  Future<void> markEntryVerified({
    required MigrationTransferManifest manifest,
    required String entryId,
    required int sizeBytes,
    required String sha256,
  }) async {
    final store = await _loadLedger();
    final entries = store.putIfAbsent(
      _ledgerKey(manifest.sessionId, manifest.bundleId),
      () => {},
    );
    entries[entryId] = MigrationTransferLedgerEntry(
      verifiedOffset: sizeBytes,
      incrementalSha256: sha256,
      verified: true,
      sizeBytes: sizeBytes,
      sha256: sha256,
    );
    await _saveLedger(store);
  }

  @override
  Future<MigrationTransferLedgerEntry?> entryState({
    required MigrationTransferManifest manifest,
    required String entryId,
  }) async {
    final store = await _loadLedger();
    return store[_ledgerKey(manifest.sessionId, manifest.bundleId)]?[entryId];
  }

  @override
  Future<MigrationTransferLedgerStatus> status(
    MigrationTransferManifest manifest,
  ) async {
    final store = await _loadLedger();
    return _ledgerStatus(
      manifest,
      store[_ledgerKey(manifest.sessionId, manifest.bundleId)] ?? const {},
    );
  }

  @override
  Future<int> missingEntryCount(MigrationTransferManifest manifest) async {
    final store = await _loadLedger();
    return _ledgerMissingEntryCount(
      manifest,
      store[_ledgerKey(manifest.sessionId, manifest.bundleId)] ?? const {},
    );
  }

  @override
  Future<void> clear({
    required String sessionId,
    required String bundleId,
  }) async {
    final store = await _loadLedger();
    store.remove(_ledgerKey(sessionId, bundleId));
    await _saveLedger(store);
  }

  Future<Map<String, Map<String, MigrationTransferLedgerEntry>>>
  _loadLedger() async {
    final file = File(filePath);
    if (!await file.exists()) return {};
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException {
      // A torn ledger write must degrade to "no progress", never crash the
      // receiver; resumed bytes are still re-verified by entry hashes.
      return {};
    }
    if (decoded is! Map<String, dynamic>) return {};
    return {
      for (final bundleEntry in decoded.entries)
        if (bundleEntry.value is Map)
          bundleEntry.key: {
            for (final entry
                in Map<String, dynamic>.from(bundleEntry.value as Map).entries)
              if (entry.value is Map)
                entry.key: MigrationTransferLedgerEntry.fromJson(
                  Map<String, dynamic>.from(entry.value as Map),
                ),
          },
    };
  }

  Future<void> _saveLedger(
    Map<String, Map<String, MigrationTransferLedgerEntry>> store,
  ) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    final tempFile = File('$filePath.tmp');
    await tempFile.writeAsString(
      jsonEncode({
        for (final bundleEntry in store.entries)
          bundleEntry.key: {
            for (final entry in bundleEntry.value.entries)
              entry.key: entry.value.toJson(),
          },
      }),
      flush: true,
    );
    await tempFile.rename(filePath);
  }
}

class InMemoryMigrationTransferLedgerStore
    implements MigrationTransferLedgerStore {
  final _entriesByBundle =
      <String, Map<String, MigrationTransferLedgerEntry>>{};

  @override
  Future<void> recordProgress({
    required MigrationTransferManifest manifest,
    required String entryId,
    required int verifiedOffset,
    required String incrementalSha256,
  }) async {
    _entriesByBundle.putIfAbsent(
      _ledgerKey(manifest.sessionId, manifest.bundleId),
      () => {},
    )[entryId] = MigrationTransferLedgerEntry(
      verifiedOffset: verifiedOffset,
      incrementalSha256: incrementalSha256,
    );
  }

  @override
  Future<void> markEntryVerified({
    required MigrationTransferManifest manifest,
    required String entryId,
    required int sizeBytes,
    required String sha256,
  }) async {
    _entriesByBundle.putIfAbsent(
      _ledgerKey(manifest.sessionId, manifest.bundleId),
      () => {},
    )[entryId] = MigrationTransferLedgerEntry(
      verifiedOffset: sizeBytes,
      incrementalSha256: sha256,
      verified: true,
      sizeBytes: sizeBytes,
      sha256: sha256,
    );
  }

  @override
  Future<MigrationTransferLedgerEntry?> entryState({
    required MigrationTransferManifest manifest,
    required String entryId,
  }) async {
    return _entriesByBundle[_ledgerKey(
      manifest.sessionId,
      manifest.bundleId,
    )]?[entryId];
  }

  @override
  Future<MigrationTransferLedgerStatus> status(
    MigrationTransferManifest manifest,
  ) async {
    return _ledgerStatus(
      manifest,
      _entriesByBundle[_ledgerKey(manifest.sessionId, manifest.bundleId)] ??
          const {},
    );
  }

  @override
  Future<int> missingEntryCount(MigrationTransferManifest manifest) async {
    return _ledgerMissingEntryCount(
      manifest,
      _entriesByBundle[_ledgerKey(manifest.sessionId, manifest.bundleId)] ??
          const {},
    );
  }

  @override
  Future<void> clear({
    required String sessionId,
    required String bundleId,
  }) async {
    _entriesByBundle.remove(_ledgerKey(sessionId, bundleId));
  }
}

String _ledgerKey(String sessionId, String bundleId) =>
    '$sessionId::$bundleId';

MigrationTransferLedgerStatus _ledgerStatus(
  MigrationTransferManifest manifest,
  Map<String, MigrationTransferLedgerEntry> entries,
) {
  final verifiedEntryIds = <String>[];
  final entryOffsets = <String, int>{};
  String? nextEntryId;
  var nextOffset = 0;
  for (final descriptor in manifest.entries) {
    final state = entries[descriptor.entryId];
    if (state != null) {
      entryOffsets[descriptor.entryId] = state.verifiedOffset;
    }
    if (state?.verified ?? false) {
      verifiedEntryIds.add(descriptor.entryId);
      continue;
    }
    if (nextEntryId == null) {
      nextEntryId = descriptor.entryId;
      nextOffset = state?.verifiedOffset ?? 0;
    }
  }
  return MigrationTransferLedgerStatus(
    nextEntryId: nextEntryId,
    nextOffset: nextOffset,
    verifiedEntryIds: verifiedEntryIds,
    entryOffsets: entryOffsets,
  );
}

int _ledgerMissingEntryCount(
  MigrationTransferManifest manifest,
  Map<String, MigrationTransferLedgerEntry> entries,
) {
  return manifest.entries
      .where((descriptor) => !(entries[descriptor.entryId]?.verified ?? false))
      .length;
}
