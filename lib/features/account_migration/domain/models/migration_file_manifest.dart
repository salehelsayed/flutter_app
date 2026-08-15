enum MigrationFileManifestItemKind {
  chatMedia,
  directMediaBlobCustody,
  groupMediaBlobCustody,
  postMedia,
  contactAvatar,
  identityAvatar,
  groupAvatar,
  pendingUpload,
  videoThumbnail,
}

enum MigrationFileCriticality { critical, nonCriticalCache }

enum MigrationFileManifestIssueCode {
  missingRequiredFile,
  unsupportedAbsolutePath,
  invalidCustodyArtifact,
  missingChatMediaMetadata,
  missingSecureStoreKey,
  missingPostMediaCrypto,
  fileSizeMismatch,
  transientFile,
}

class MigrationFileManifestItem {
  final MigrationFileManifestItemKind kind;
  final MigrationFileCriticality criticality;
  final String relativePath;
  final int sizeBytes;
  final String sha256;
  final String sourceTable;
  final String sourceId;
  final Map<String, Object?> metadata;

  const MigrationFileManifestItem({
    required this.kind,
    required this.criticality,
    required this.relativePath,
    required this.sizeBytes,
    required this.sha256,
    required this.sourceTable,
    required this.sourceId,
    this.metadata = const {},
  });

  Map<String, Object?> toJson() {
    return {
      'kind': kind.name,
      'criticality': criticality.name,
      'relative_path': relativePath,
      'size_bytes': sizeBytes,
      'sha256': sha256,
      'source_table': sourceTable,
      'source_id': sourceId,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class MigrationFileManifestIssue {
  final MigrationFileManifestIssueCode code;
  final String sourceTable;
  final String sourceId;
  final String? relativePath;
  final bool blocking;
  final MigrationFileCriticality? criticality;
  final Map<String, Object?> diagnostics;

  const MigrationFileManifestIssue({
    required this.code,
    required this.sourceTable,
    required this.sourceId,
    this.relativePath,
    this.blocking = true,
    this.criticality,
    this.diagnostics = const {},
  });

  Map<String, Object?> toJson() {
    return {
      'code': code.name,
      'source_table': sourceTable,
      'source_id': sourceId,
      if (relativePath != null) 'relative_path': relativePath,
      'blocking': blocking,
      if (criticality != null) 'criticality': criticality!.name,
      if (diagnostics.isNotEmpty) 'diagnostics': diagnostics,
    };
  }
}

class MigrationFilePathRepair {
  final String sourceTable;
  final String sourceId;
  final String? oldPath;
  final String relativePath;
  final String reason;

  const MigrationFilePathRepair({
    required this.sourceTable,
    required this.sourceId,
    this.oldPath,
    required this.relativePath,
    required this.reason,
  });

  Map<String, Object?> toJson() {
    return {
      'source_table': sourceTable,
      'source_id': sourceId,
      if (oldPath != null) 'old_path': oldPath,
      'relative_path': relativePath,
      'reason': reason,
    };
  }
}

class MigrationFileManifest {
  final List<MigrationFileManifestItem> items;
  final List<MigrationFileManifestIssue> issues;
  final List<MigrationFilePathRepair> pathRepairs;

  const MigrationFileManifest({
    this.items = const [],
    this.issues = const [],
    this.pathRepairs = const [],
  });

  bool get isValid => issues.every((issue) => !issue.blocking);

  int get totalCriticalBytes {
    return items
        .where((item) => item.criticality == MigrationFileCriticality.critical)
        .fold<int>(0, (sum, item) => sum + item.sizeBytes);
  }

  int get totalNonCriticalBytes {
    return items
        .where(
          (item) =>
              item.criticality == MigrationFileCriticality.nonCriticalCache,
        )
        .fold<int>(0, (sum, item) => sum + item.sizeBytes);
  }

  bool hasIssue(MigrationFileManifestIssueCode code) {
    return issues.any((issue) => issue.code == code);
  }

  Map<String, Object?> toJson() {
    return {
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
      if (pathRepairs.isNotEmpty)
        'path_repairs': pathRepairs
            .map((repair) => repair.toJson())
            .toList(growable: false),
      'total_critical_bytes': totalCriticalBytes,
      'total_non_critical_bytes': totalNonCriticalBytes,
      'valid': isValid,
    };
  }
}
