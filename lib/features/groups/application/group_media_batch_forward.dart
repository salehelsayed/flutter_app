import 'dart:io';

import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/features/groups/application/announcement_media_forward_request.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const int kGroupMediaBatchForwardMinItems = 1;
const int kGroupMediaBatchForwardRouteMinItems = 2;
const int kGroupMediaBatchForwardMaxItems = 10;
const int kGroupMediaBatchForwardMaxTotalBytes =
    kGroupMediaTotalMessageLimitBytes;

enum GroupMediaBatchForwardSourceKind { discussion, announcement }

enum GroupMediaBatchForwardDenial {
  invalidSelection,
  sourceUnavailable,
  sourceScopeChanged,
  sizeLimitExceeded,
  invalidOperationToken,
}

/// One route-local output unit. Every selected attachment remains one ordinary
/// forwarded message; no album, source identity, or batch envelope is added to
/// either the direct or group wire contract.
class GroupMediaBatchForwardItemDraft {
  const GroupMediaBatchForwardItemDraft({
    required this.identity,
    required this.request,
    required this.resolvedPath,
    required this.parentTimestamp,
    required this.mime,
    required this.sizeBytes,
    required this.caption,
  });

  final GroupSharedMediaIdentity identity;
  final GroupMediaForwardRequest request;
  final String resolvedPath;
  final DateTime parentTimestamp;
  final String mime;
  final int sizeBytes;
  final String caption;

  GroupMediaBatchForwardItemDraft copyWith({String? caption}) =>
      GroupMediaBatchForwardItemDraft(
        identity: identity,
        request: request,
        resolvedPath: resolvedPath,
        parentTimestamp: parentTimestamp,
        mime: mime,
        sizeBytes: sizeBytes,
        caption: caption ?? this.caption,
      );

  @override
  String toString() => 'GroupMediaBatchForwardItemDraft(redacted)';
}

class GroupMediaBatchForwardDraft {
  GroupMediaBatchForwardDraft({
    required this.sourceGroupId,
    required this.sourceKind,
    required Iterable<GroupMediaBatchForwardItemDraft> items,
  }) : items = List.unmodifiable(items);

  final String sourceGroupId;
  final GroupMediaBatchForwardSourceKind sourceKind;
  final List<GroupMediaBatchForwardItemDraft> items;

  GroupMediaBatchForwardDraft copyWith({
    Iterable<GroupMediaBatchForwardItemDraft>? items,
  }) => GroupMediaBatchForwardDraft(
    sourceGroupId: sourceGroupId,
    sourceKind: sourceKind,
    items: items ?? this.items,
  );

  @override
  String toString() =>
      'GroupMediaBatchForwardDraft(sourceKind: $sourceKind, '
      'itemCount: ${items.length})';
}

class GroupMediaBatchForwardBuildResult {
  const GroupMediaBatchForwardBuildResult.ready(this.draft) : denial = null;

  const GroupMediaBatchForwardBuildResult.denied(this.denial) : draft = null;

  final GroupMediaBatchForwardDraft? draft;
  final GroupMediaBatchForwardDenial? denial;

  bool get isReady => draft != null && denial == null;

  @override
  String toString() => isReady
      ? 'GroupMediaBatchForwardBuildResult(ready, '
            'itemCount: ${draft!.items.length})'
      : 'GroupMediaBatchForwardBuildResult(denied: $denial)';
}

typedef GroupMediaBatchForwardCurrentGroupLoader =
    Future<GroupModel?> Function(String groupId);
typedef GroupMediaBatchForwardParentTimestampLoader =
    Future<DateTime?> Function(GroupSharedMediaIdentity identity);
typedef GroupMediaBatchForwardRequestLoader =
    Future<GroupMediaForwardRequest?> Function({
      required GroupModel group,
      required GroupSharedMediaIdentity identity,
    });
typedef GroupMediaBatchForwardSourceVerifier =
    Future<GroupMediaForwardSourceResult> Function(
      GroupMediaForwardRequest request,
    );
typedef GroupMediaBatchForwardFileLength = Future<int> Function(String path);

Future<int> _defaultFileLength(String path) => File(path).length();

/// Builds and revalidates the shared Plan-250/251 source foundation.
///
/// Selection is canonicalized exactly like Plan 249: parent timestamp DESC,
/// then message id DESC, then attachment id DESC. Qualification is
/// all-or-nothing and completes for every source before a target picker may
/// open or a delivery may start. The accepted resource contract is 1..10
/// visual items, each within the existing single-forward type cap and at most
/// 500 MB total current bytes. The reusable foundation retains Plan 249's
/// `1..10` contract; the library route reserves one item for Plan 236/240 and
/// opens this batch picker only at [kGroupMediaBatchForwardRouteMinItems].
class GroupMediaBatchForwardDraftBuilder {
  GroupMediaBatchForwardDraftBuilder({
    required GroupMediaBatchForwardCurrentGroupLoader loadCurrentGroup,
    required GroupMediaBatchForwardParentTimestampLoader loadParentTimestamp,
    required GroupMediaBatchForwardRequestLoader buildRequest,
    required GroupMediaBatchForwardSourceVerifier verifySource,
    GroupMediaBatchForwardFileLength fileLength = _defaultFileLength,
  }) : _loadCurrentGroup = loadCurrentGroup,
       _loadParentTimestamp = loadParentTimestamp,
       _buildRequest = buildRequest,
       _verifySource = verifySource,
       _fileLength = fileLength;

  factory GroupMediaBatchForwardDraftBuilder.fromPolicies({
    required GroupRepository groupRepository,
    required GroupMessageRepository messageRepository,
    required GroupMediaForwardRequestBuilder requestBuilder,
    required GroupMediaForwardSourceGate sourceGate,
    GroupMediaBatchForwardFileLength fileLength = _defaultFileLength,
  }) => GroupMediaBatchForwardDraftBuilder(
    loadCurrentGroup: groupRepository.getGroup,
    loadParentTimestamp: (identity) async {
      final parent = await messageRepository.getMessage(identity.messageId);
      return parent == null || parent.groupId != identity.groupId
          ? null
          : parent.timestamp;
    },
    buildRequest: ({required group, required identity}) => requestBuilder.build(
      group: group,
      messageId: identity.messageId,
      attachmentId: identity.attachmentId,
    ),
    verifySource: sourceGate.verify,
    fileLength: fileLength,
  );

  final GroupMediaBatchForwardCurrentGroupLoader _loadCurrentGroup;
  final GroupMediaBatchForwardParentTimestampLoader _loadParentTimestamp;
  final GroupMediaBatchForwardRequestLoader _buildRequest;
  final GroupMediaBatchForwardSourceVerifier _verifySource;
  final GroupMediaBatchForwardFileLength _fileLength;

  Future<GroupMediaBatchForwardBuildResult> build({
    required GroupModel sourceGroup,
    required List<GroupSharedMediaIdentity> identities,
  }) async {
    final sourceKind = _sourceKind(sourceGroup.type);
    if (sourceKind == null ||
        !_validIdentities(sourceGroup.id, identities) ||
        sourceGroup.isArchived ||
        sourceGroup.isDissolved) {
      return const GroupMediaBatchForwardBuildResult.denied(
        GroupMediaBatchForwardDenial.invalidSelection,
      );
    }

    final currentGroup = await _safeLoadGroup(sourceGroup.id);
    if (!_sameActiveSource(currentGroup, sourceGroup.id, sourceKind)) {
      return const GroupMediaBatchForwardBuildResult.denied(
        GroupMediaBatchForwardDenial.sourceScopeChanged,
      );
    }

    final orderedSources = await _canonicalSources(identities);
    if (orderedSources == null) {
      return const GroupMediaBatchForwardBuildResult.denied(
        GroupMediaBatchForwardDenial.sourceUnavailable,
      );
    }
    final requests = <GroupMediaForwardRequest>[];
    for (final source in orderedSources) {
      final identity = source.identity;
      final GroupMediaForwardRequest? request;
      try {
        request = await _buildRequest(group: currentGroup!, identity: identity);
      } catch (_) {
        return const GroupMediaBatchForwardBuildResult.denied(
          GroupMediaBatchForwardDenial.sourceUnavailable,
        );
      }
      if (request == null ||
          !_requestMatchesIdentity(request, identity, sourceKind)) {
        return const GroupMediaBatchForwardBuildResult.denied(
          GroupMediaBatchForwardDenial.sourceUnavailable,
        );
      }
      requests.add(request);
    }

    return _qualifyRequests(
      sourceGroupId: sourceGroup.id,
      sourceKind: sourceKind,
      sources: orderedSources,
      requests: requests,
    );
  }

  /// Re-hashes every current source before dispatch while preserving each
  /// route-local edited caption and opaque operation token. No token is minted
  /// and no destination is consulted until this whole call succeeds.
  Future<GroupMediaBatchForwardBuildResult> revalidateForDispatch(
    GroupMediaBatchForwardDraft draft,
  ) async {
    final identities = [for (final item in draft.items) item.identity];
    if (!_validIdentities(draft.sourceGroupId, identities, minimumItems: 1) ||
        !_validDraftRequests(draft)) {
      return const GroupMediaBatchForwardBuildResult.denied(
        GroupMediaBatchForwardDenial.invalidSelection,
      );
    }

    final currentGroup = await _safeLoadGroup(draft.sourceGroupId);
    if (!_sameActiveSource(
      currentGroup,
      draft.sourceGroupId,
      draft.sourceKind,
    )) {
      return const GroupMediaBatchForwardBuildResult.denied(
        GroupMediaBatchForwardDenial.sourceScopeChanged,
      );
    }

    final orderedSources = await _canonicalSources(identities);
    if (orderedSources == null) {
      return const GroupMediaBatchForwardBuildResult.denied(
        GroupMediaBatchForwardDenial.sourceUnavailable,
      );
    }
    final requestsByIdentity = {
      for (final item in draft.items) item.identity: item.request,
    };
    final qualified = await _qualifyRequests(
      sourceGroupId: draft.sourceGroupId,
      sourceKind: draft.sourceKind,
      sources: orderedSources,
      requests: [
        for (final source in orderedSources)
          requestsByIdentity[source.identity]!,
      ],
      preservedCaptions: {
        for (final item in draft.items) item.identity: item.caption,
      },
    );
    if (!qualified.isReady) return qualified;

    final refreshed = qualified.draft!;
    final originalTokens = {
      for (final item in draft.items)
        item.identity: item.request.provenance.operationDedupKey,
    };
    for (final item in refreshed.items) {
      if (item.request.provenance.operationDedupKey !=
          originalTokens[item.identity]) {
        return const GroupMediaBatchForwardBuildResult.denied(
          GroupMediaBatchForwardDenial.invalidOperationToken,
        );
      }
    }
    return qualified;
  }

  Future<GroupMediaBatchForwardBuildResult> _qualifyRequests({
    required String sourceGroupId,
    required GroupMediaBatchForwardSourceKind sourceKind,
    required List<_GroupMediaBatchForwardCanonicalSource> sources,
    required List<GroupMediaForwardRequest> requests,
    Map<GroupSharedMediaIdentity, String>? preservedCaptions,
  }) async {
    if (requests.length != sources.length) {
      return const GroupMediaBatchForwardBuildResult.denied(
        GroupMediaBatchForwardDenial.invalidSelection,
      );
    }

    final items = <GroupMediaBatchForwardItemDraft>[];
    final tokens = <String>{};
    var totalBytes = 0;
    for (var index = 0; index < requests.length; index++) {
      final request = requests[index];
      final canonicalSource = sources[index];
      final identity = canonicalSource.identity;
      if (!_requestMatchesIdentity(request, identity, sourceKind)) {
        return const GroupMediaBatchForwardBuildResult.denied(
          GroupMediaBatchForwardDenial.sourceScopeChanged,
        );
      }
      final token = request.provenance.operationDedupKey.trim();
      if (token.isEmpty ||
          !tokens.add(token) ||
          _tokenContainsSourceIdentity(token, identity)) {
        return const GroupMediaBatchForwardBuildResult.denied(
          GroupMediaBatchForwardDenial.invalidOperationToken,
        );
      }

      final GroupMediaForwardSourceResult verification;
      try {
        verification = await _verifySource(request);
      } catch (_) {
        return const GroupMediaBatchForwardBuildResult.denied(
          GroupMediaBatchForwardDenial.sourceUnavailable,
        );
      }
      final source = verification.source;
      if (source == null || source.resolvedPath.trim().isEmpty) {
        return const GroupMediaBatchForwardBuildResult.denied(
          GroupMediaBatchForwardDenial.sourceUnavailable,
        );
      }

      final int currentLength;
      try {
        currentLength = await _fileLength(source.resolvedPath);
      } catch (_) {
        return const GroupMediaBatchForwardBuildResult.denied(
          GroupMediaBatchForwardDenial.sourceUnavailable,
        );
      }
      final size = GroupMediaSizePolicy.validateSize(
        sizeBytes: currentLength,
        mime: source.attachment.mime,
      );
      if (!size.isValid) {
        return const GroupMediaBatchForwardBuildResult.denied(
          GroupMediaBatchForwardDenial.sizeLimitExceeded,
        );
      }
      totalBytes += currentLength;
      if (totalBytes > kGroupMediaBatchForwardMaxTotalBytes) {
        return const GroupMediaBatchForwardBuildResult.denied(
          GroupMediaBatchForwardDenial.sizeLimitExceeded,
        );
      }

      final initialCaption = switch (request) {
        AnnouncementMediaForwardRequest announcement =>
          announcement.composedCaption ?? '',
        _ => request.initialCaption,
      };
      items.add(
        GroupMediaBatchForwardItemDraft(
          identity: identity,
          request: request,
          resolvedPath: source.resolvedPath,
          parentTimestamp: canonicalSource.parentTimestamp,
          mime: source.attachment.mime,
          sizeBytes: currentLength,
          caption: preservedCaptions?[identity] ?? initialCaption,
        ),
      );
    }

    return GroupMediaBatchForwardBuildResult.ready(
      GroupMediaBatchForwardDraft(
        sourceGroupId: sourceGroupId,
        sourceKind: sourceKind,
        items: items,
      ),
    );
  }

  Future<GroupModel?> _safeLoadGroup(String groupId) async {
    try {
      return await _loadCurrentGroup(groupId);
    } catch (_) {
      return null;
    }
  }

  Future<List<_GroupMediaBatchForwardCanonicalSource>?> _canonicalSources(
    List<GroupSharedMediaIdentity> identities,
  ) async {
    final sources = <_GroupMediaBatchForwardCanonicalSource>[];
    for (final identity in identities) {
      final DateTime? timestamp;
      try {
        timestamp = await _loadParentTimestamp(identity);
      } catch (_) {
        return null;
      }
      if (timestamp == null) return null;
      sources.add(
        _GroupMediaBatchForwardCanonicalSource(
          identity: identity,
          parentTimestamp: timestamp,
        ),
      );
    }
    sources.sort(_compareSourcesNewestFirst);
    return sources;
  }

  static int _compareSourcesNewestFirst(
    _GroupMediaBatchForwardCanonicalSource left,
    _GroupMediaBatchForwardCanonicalSource right,
  ) {
    final timestamp = right.parentTimestamp.compareTo(left.parentTimestamp);
    if (timestamp != 0) return timestamp;
    final message = right.identity.messageId.compareTo(left.identity.messageId);
    if (message != 0) return message;
    return right.identity.attachmentId.compareTo(left.identity.attachmentId);
  }

  bool _validIdentities(
    String sourceGroupId,
    List<GroupSharedMediaIdentity> identities, {
    int minimumItems = kGroupMediaBatchForwardMinItems,
  }) {
    if (sourceGroupId.trim().isEmpty ||
        identities.length < minimumItems ||
        identities.length > kGroupMediaBatchForwardMaxItems) {
      return false;
    }
    final unique = <GroupSharedMediaIdentity>{};
    for (final identity in identities) {
      if (identity.groupId != sourceGroupId ||
          identity.messageId.trim().isEmpty ||
          identity.attachmentId.trim().isEmpty ||
          !unique.add(identity)) {
        return false;
      }
    }
    return true;
  }

  bool _validDraftRequests(GroupMediaBatchForwardDraft draft) {
    final tokens = <String>{};
    for (final item in draft.items) {
      if (!_requestMatchesIdentity(
            item.request,
            item.identity,
            draft.sourceKind,
          ) ||
          item.resolvedPath.trim().isEmpty ||
          item.sizeBytes <= 0) {
        return false;
      }
      final token = item.request.provenance.operationDedupKey.trim();
      if (token.isEmpty ||
          !tokens.add(token) ||
          _tokenContainsSourceIdentity(token, item.identity)) {
        return false;
      }
    }
    return true;
  }

  bool _sameActiveSource(
    GroupModel? group,
    String sourceGroupId,
    GroupMediaBatchForwardSourceKind sourceKind,
  ) =>
      group != null &&
      group.id == sourceGroupId &&
      !group.isArchived &&
      !group.isDissolved &&
      _sourceKind(group.type) == sourceKind;

  bool _requestMatchesIdentity(
    GroupMediaForwardRequest request,
    GroupSharedMediaIdentity identity,
    GroupMediaBatchForwardSourceKind sourceKind,
  ) =>
      request.groupId == identity.groupId &&
      request.messageId == identity.messageId &&
      request.attachmentId == identity.attachmentId &&
      (sourceKind == GroupMediaBatchForwardSourceKind.announcement) ==
          (request is AnnouncementMediaForwardRequest);

  bool _tokenContainsSourceIdentity(
    String token,
    GroupSharedMediaIdentity identity,
  ) =>
      token.contains(identity.groupId) ||
      token.contains(identity.messageId) ||
      token.contains(identity.attachmentId);

  GroupMediaBatchForwardSourceKind? _sourceKind(GroupType type) =>
      switch (type) {
        GroupType.chat => GroupMediaBatchForwardSourceKind.discussion,
        GroupType.announcement => GroupMediaBatchForwardSourceKind.announcement,
        GroupType.qa => null,
      };
}

class _GroupMediaBatchForwardCanonicalSource {
  const _GroupMediaBatchForwardCanonicalSource({
    required this.identity,
    required this.parentTimestamp,
  });

  final GroupSharedMediaIdentity identity;
  final DateTime parentTimestamp;
}
