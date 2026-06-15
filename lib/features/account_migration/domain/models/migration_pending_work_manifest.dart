enum MigrationPendingWorkItemKind {
  oneToOneMessageRetry,
  oneToOneUnackedInboxStore,
  chatMediaUpload,
  postMediaUpload,
  postDelivery,
  postFollowOn,
  introductionOutbox,
  pendingIntroductionResponse,
  groupMessageRetry,
  groupInboxStoreRetry,
  groupPendingKeyRepair,
  groupPendingMembership,
  groupReactionReplay,
}

enum MigrationPendingWorkResumePolicy {
  resumeOnNewPhoneAfterCommit,
  pauseOnNewPhoneAfterCommit,
  failOnNewPhoneAfterCommit,
}

enum MigrationPendingWorkIssueCode {
  missingSourceId,
  missingMessageId,
  missingTargetPeerId,
  missingSenderPeerId,
  missingGroupId,
  missingPostId,
  missingEventId,
  missingRequiredPayload,
  missingRequiredFileManifestItem,
  unsupportedPendingFilePath,
  sensitiveMaterialLeakage,
  terminalRetryContradiction,
}

class MigrationPendingWorkManifestItem {
  final MigrationPendingWorkItemKind kind;
  final MigrationPendingWorkResumePolicy resumePolicy;
  final String sourceTable;
  final String sourceId;
  final String? currentStatus;
  final Map<String, String> relatedIds;
  final List<String> requiredFileRelativePaths;
  final Map<String, Object?> metadata;

  const MigrationPendingWorkManifestItem({
    required this.kind,
    required this.sourceTable,
    required this.sourceId,
    this.resumePolicy =
        MigrationPendingWorkResumePolicy.resumeOnNewPhoneAfterCommit,
    this.currentStatus,
    this.relatedIds = const {},
    this.requiredFileRelativePaths = const [],
    this.metadata = const {},
  });

  String? get status => currentStatus;

  String? get accountPeerId => relatedIds['account_peer_id'];

  String? get threadId => relatedIds['thread_id'];

  String? get groupId => relatedIds['group_id'];

  String? get messageId => relatedIds['message_id'];

  String? get postId => relatedIds['post_id'];

  String? get eventId => relatedIds['event_id'];

  String? get targetPeerId => relatedIds['target_peer_id'];

  String? get localPath {
    return requiredFileRelativePaths.isEmpty
        ? null
        : requiredFileRelativePaths.first;
  }

  Map<String, Object?> toJson() {
    return {
      'kind': kind.name,
      'resume_policy': resumePolicy.name,
      'source_table': sourceTable,
      'source_id': sourceId,
      if (currentStatus != null) 'current_status': currentStatus,
      if (relatedIds.isNotEmpty) 'related_ids': relatedIds,
      if (requiredFileRelativePaths.isNotEmpty)
        'required_file_relative_paths': requiredFileRelativePaths,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class MigrationPendingWorkManifestIssue {
  final MigrationPendingWorkIssueCode code;
  final MigrationPendingWorkItemKind kind;
  final String sourceTable;
  final String sourceId;
  final MigrationPendingWorkResumePolicy policy;
  final Map<String, String> relatedIds;
  final bool blocking;
  final String? field;

  const MigrationPendingWorkManifestIssue({
    required this.code,
    required this.kind,
    required this.sourceTable,
    required this.sourceId,
    this.policy = MigrationPendingWorkResumePolicy.pauseOnNewPhoneAfterCommit,
    this.relatedIds = const {},
    this.blocking = true,
    this.field,
  });

  Map<String, Object?> toJson() {
    return {
      'code': code.name,
      'kind': kind.name,
      'source_table': sourceTable,
      'source_id': sourceId,
      'policy': policy.name,
      'blocking': blocking,
      if (relatedIds.isNotEmpty) 'related_ids': relatedIds,
      if (field != null) 'field': field,
    };
  }
}

class MigrationPendingWorkManifest {
  final List<MigrationPendingWorkManifestItem> items;
  final List<MigrationPendingWorkManifestIssue> issues;

  const MigrationPendingWorkManifest({
    this.items = const [],
    this.issues = const [],
  });

  bool get isValid => issues.every((issue) => !issue.blocking);

  bool hasIssue(MigrationPendingWorkIssueCode code) {
    return issues.any((issue) => issue.code == code);
  }

  Iterable<MigrationPendingWorkManifestItem> itemsForKind(
    MigrationPendingWorkItemKind kind,
  ) {
    return items.where((item) => item.kind == kind);
  }

  bool get hasOldPhoneResumePolicy {
    return items.any(
      (item) =>
          item.resumePolicy !=
          MigrationPendingWorkResumePolicy.resumeOnNewPhoneAfterCommit,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
      'valid': isValid,
    };
  }
}
