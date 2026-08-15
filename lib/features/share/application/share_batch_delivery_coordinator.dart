import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/conversation/application/direct_media_fanout_admission.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/group_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/build_received_media_forward.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/application/announcement_media_forward_request.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/application/prepared_group_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/self_removed_group_lifecycle_guard.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/l10n/app_localizations_en.dart';

import 'share_target_selection.dart';

const _shareBatchUuid = Uuid();

DateTime _defaultForwardNow() => DateTime.now().toUtc();

/// Stable only for one action+contact retry and opaque outside this process.
/// Source identities are not inputs and cannot appear in the resulting key.
ForwardProvenance announcementForwardProvenanceForContact({
  required ForwardProvenance base,
  required String contactPeerId,
}) => ForwardProvenance(
  operationDedupKey: sha256
      .convert(
        utf8.encode('${base.operationDedupKey}\u0000contact:$contactPeerId'),
      )
      .toString(),
);

Set<String> retainFailedAnnouncementForwardTargetKeys({
  required String sourceGroupId,
  required Set<String> attemptedTargetKeys,
  required Set<String> failedTargetKeys,
}) => attemptedTargetKeys
    .intersection(failedTargetKeys)
    .where((key) => key != 'group:$sourceGroupId')
    .toSet();

bool canDeliverAnnouncementForwardToGroup({
  required bool isArchived,
  required bool isDissolved,
  required bool isAnnouncement,
  required bool isAdmin,
  required bool hasLatestKey,
  required MemberRole? ownMemberRole,
}) {
  final canWrite =
      ownMemberRole == MemberRole.admin ||
      (!isAnnouncement && ownMemberRole == MemberRole.writer);
  return !isArchived &&
      !isDissolved &&
      (!isAnnouncement || isAdmin) &&
      hasLatestKey &&
      canWrite;
}

class _ForwardGroupAuthority {
  const _ForwardGroupAuthority({
    required this.group,
    required this.members,
    required this.latestKeyGeneration,
  });

  final GroupModel group;
  final List<GroupMember> members;
  final int latestKeyGeneration;
}

class _ForwardGroupUploadLeaf {
  const _ForwardGroupUploadLeaf({
    required this.authority,
    required this.attachment,
  });

  final _ForwardGroupAuthority authority;
  final MediaAttachment attachment;
}

String _forwardGroupAuthorityFingerprint(_ForwardGroupAuthority authority) {
  final group = authority.group;
  final memberRows =
      authority.members
          .map((member) => jsonEncode(member.toConfigJson()))
          .toList(growable: false)
        ..sort();
  return jsonEncode(<String, Object?>{
    'groupId': group.id,
    'groupType': group.type.toValue(),
    'createdBy': group.createdBy,
    'myRole': group.myRole.toValue(),
    'isArchived': group.isArchived,
    'isDissolved': group.isDissolved,
    'selfRemovedAt': group.selfRemovedAt?.toUtc().toIso8601String(),
    'lastMembershipEventAt': group.lastMembershipEventAt
        ?.toUtc()
        .toIso8601String(),
    'lastMembershipEventId': group.lastMembershipEventId,
    'latestKeyGeneration': authority.latestKeyGeneration,
    'members': memberRows,
  });
}

bool _sameForwardGroupAuthority(
  _ForwardGroupAuthority left,
  _ForwardGroupAuthority right,
) =>
    _forwardGroupAuthorityFingerprint(left) ==
    _forwardGroupAuthorityFingerprint(right);

class _InternalForwardTargetResolution {
  const _InternalForwardTargetResolution.ready({
    required this.requested,
    required this.current,
  }) : failureDetail = null;

  const _InternalForwardTargetResolution.failed({
    required this.requested,
    required this.failureDetail,
  }) : current = null;

  final ShareTargetSelection requested;
  final ShareTargetSelection? current;
  final String? failureDetail;

  bool get isReady => current != null;

  ShareBatchTargetResult get failure => ShareBatchTargetResult(
    target: requested,
    status: ShareBatchTargetStatus.failed,
    detail: failureDetail ?? 'Share failed.',
  );
}

enum ShareBatchTargetStatus { sent, queued, failed }

enum ShareBatchDeliveryPhase { uploading, sending }

class ShareBatchDeliveryProgress {
  final int sentBytes;
  final int totalBytes;
  final ShareBatchDeliveryPhase phase;

  const ShareBatchDeliveryProgress({
    required this.sentBytes,
    required this.totalBytes,
    required this.phase,
  });
}

typedef ShareBatchDeliveryProgressCallback =
    void Function(ShareBatchDeliveryProgress progress);

class ShareBatchUploadHooks {
  final void Function({required String blobId, required int budgetBytes})
  _onStarted;
  final void Function({required bool succeeded}) _onSettled;
  final void Function() _onSending;

  const ShareBatchUploadHooks({
    required void Function({required String blobId, required int budgetBytes})
    onStarted,
    required void Function({required bool succeeded}) onSettled,
    required void Function() onSending,
  }) : _onStarted = onStarted,
       _onSettled = onSettled,
       _onSending = onSending;

  static final none = ShareBatchUploadHooks(
    onStarted: ({required blobId, required budgetBytes}) {},
    onSettled: ({required succeeded}) {},
    onSending: () {},
  );

  void started({required String blobId, required int budgetBytes}) =>
      _onStarted(blobId: blobId, budgetBytes: budgetBytes);

  void settled({required bool succeeded}) => _onSettled(succeeded: succeeded);

  void sending() => _onSending();
}

/// Retry-stable and opaque for one explicit group destination. The target id
/// is only a local derivation input; neither it nor any source identity appears
/// in the resulting encrypted-inner operation key.
ForwardProvenance groupForwardProvenanceForGroup({
  required ForwardProvenance base,
  required String groupId,
}) => ForwardProvenance(
  operationDedupKey: sha256
      .convert(utf8.encode('${base.operationDedupKey}\u0000group:$groupId'))
      .toString(),
);

class ShareBatchTargetResult {
  final ShareTargetSelection target;
  final ShareBatchTargetStatus status;
  final String detail;

  const ShareBatchTargetResult({
    required this.target,
    required this.status,
    required this.detail,
  });
}

class ShareBatchDeliveryResult {
  final List<ShareBatchTargetResult> results;
  final int skippedOversizedGifCount;
  final String? skippedOversizedGifReason;

  const ShareBatchDeliveryResult({
    required this.results,
    this.skippedOversizedGifCount = 0,
    this.skippedOversizedGifReason,
  });

  int get sentCount => results
      .where((result) => result.status == ShareBatchTargetStatus.sent)
      .length;

  int get queuedCount => results
      .where((result) => result.status == ShareBatchTargetStatus.queued)
      .length;

  int get failureCount => results
      .where((result) => result.status == ShareBatchTargetStatus.failed)
      .length;

  bool get hasFailures => failureCount > 0;

  bool get hasCompletions => sentCount + queuedCount > 0;

  bool get hasSkippedOversizedGifs => skippedOversizedGifCount > 0;

  Set<String> get failedTargetKeys => results
      .where((result) => result.status == ShareBatchTargetStatus.failed)
      .map((result) => result.target.key)
      .toSet();
}

abstract class ShareBatchDeliveryCoordinator {
  Future<ShareBatchDeliveryResult> deliver({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
    ShareBatchDeliveryProgressCallback? onProgress,
  });

  /// 236: one explicit accepted group-media Forward. Unlike [deliver], the
  /// source is a stable `(groupId, messageId, attachmentId)` identity that is
  /// reloaded, canonically validated, and snapshotted at dispatch time. Every
  /// destination is reloaded from its repository immediately before its upload
  /// — a missing or ineligible target is a failed result, never a stale-picker
  /// fallback.
  Future<ShareBatchDeliveryResult> deliverGroupMediaForward({
    required GroupMediaForwardRequest request,
    String? caption,
    required List<ShareTargetSelection> targets,
  });
}

typedef ProcessSharedMediaFn =
    Future<ProcessedShareMediaBatch> Function(ShareIntent shareIntent);

class ProcessedShareMediaBatch {
  final List<PendingComposerMedia> processedMedia;
  final int skippedOversizedGifCount;
  final String? skippedOversizedGifReason;

  const ProcessedShareMediaBatch({
    required this.processedMedia,
    this.skippedOversizedGifCount = 0,
    this.skippedOversizedGifReason,
  });
}

typedef SendToContactFn =
    Future<ShareBatchTargetResult> Function({
      required IdentityModel identity,
      required ShareIntent shareIntent,
      required ContactModel contact,
      required List<PendingComposerMedia> processedMedia,
      required ShareBatchUploadHooks uploadHooks,
    });

typedef SendToGroupFn =
    Future<ShareBatchTargetResult> Function({
      required IdentityModel identity,
      required ShareIntent shareIntent,
      required GroupModel group,
      required List<PendingComposerMedia> processedMedia,
      required ShareBatchUploadHooks uploadHooks,
    });

class DefaultShareBatchDeliveryCoordinator
    implements ShareBatchDeliveryCoordinator {
  final IdentityRepository identityRepository;
  final ContactRepository contactRepository;
  final MessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final GroupRepository? groupRepository;
  final GroupMessageRepository? groupMessageRepository;
  final GroupInviteDeliveryAttemptRepository?
  groupInviteDeliveryAttemptRepository;
  final Bridge bridge;
  final P2PService p2pService;
  final MediaFileManager mediaFileManager;
  final ImageProcessor imageProcessor;
  final ImageQualityPreference qualityPreference;
  final ImageQualityPreference videoQualityPreference;
  final ProcessSharedMediaFn? processSharedMediaFn;
  final SendToContactFn? sendToContactFn;
  final SendToGroupFn? sendToGroupFn;
  final Stream<Map<String, dynamic>>? mediaUploadProgressEvents;
  final String shareStoredOfflinePromise;
  final bool directMediaBlobCustodyClientEnabled;
  final DirectEventFanoutAuthoring? Function()? directEventFanoutResolver;
  final PreparedGroupMediaBlobCustodyCoordinator?
  preparedGroupMediaBlobCustodyCoordinator;
  final DateTime Function() _forwardNow;
  final Map<String, DateTime> _forwardTimestampByOperationKey = {};

  DefaultShareBatchDeliveryCoordinator({
    required this.identityRepository,
    required this.contactRepository,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.groupRepository,
    required this.groupMessageRepository,
    this.groupInviteDeliveryAttemptRepository,
    required this.bridge,
    required this.p2pService,
    required this.mediaFileManager,
    required this.imageProcessor,
    this.qualityPreference = ImageQualityPreference.compressed,
    this.videoQualityPreference = ImageQualityPreference.compressed,
    this.processSharedMediaFn,
    this.sendToContactFn,
    this.sendToGroupFn,
    this.mediaUploadProgressEvents,
    bool? directMediaBlobCustodyClientEnabled,
    this.directEventFanoutResolver,
    this.preparedGroupMediaBlobCustodyCoordinator,
    String? shareStoredOfflinePromise,
    DateTime Function()? forwardNow,
  }) : shareStoredOfflinePromise =
           shareStoredOfflinePromise ??
           AppLocalizationsEn().share_stored_offline_promise,
       directMediaBlobCustodyClientEnabled =
           directMediaBlobCustodyClientEnabled ??
           kDirectMediaBlobCustodyClientEnabled,
       _forwardNow = forwardNow ?? _defaultForwardNow;

  String? get _currentSenderDeviceId {
    final peerId = p2pService.currentState.peerId?.trim();
    return peerId == null || peerId.isEmpty ? null : peerId;
  }

  PreparedGroupMediaBlobCustodyCoordinator get _strictGroupMediaOwner =>
      preparedGroupMediaBlobCustodyCoordinator ??
      PreparedGroupMediaBlobCustodyCoordinator(
        artifactStore: GroupMediaBlobArtifactStore(),
      );

  bool get _canServeFreshDirectMediaLinkedFanout =>
      directMediaBlobCustodyClientEnabled &&
      mediaAttachmentRepository is DirectMediaBlobCustodyRepository &&
      (mediaAttachmentRepository as DirectMediaBlobCustodyRepository)
          .supportsDirectMediaBlobCustody &&
      mediaAttachmentRepository
          is FreshOutgoingDirectMediaBlobGenerationRepository &&
      (mediaAttachmentRepository
              as FreshOutgoingDirectMediaBlobGenerationRepository)
          .supportsFreshOutgoingDirectMediaBlobGeneration &&
      mediaAttachmentRepository
          is OutgoingDirectLinkedMediaBlobFanoutRepository &&
      (mediaAttachmentRepository
              as OutgoingDirectLinkedMediaBlobFanoutRepository)
          .supportsDirectLinkedMediaBlobFanout &&
      mediaAttachmentRepository
          is OutgoingDirectMediaInboxCustodyStagingRepository &&
      (mediaAttachmentRepository
              as OutgoingDirectMediaInboxCustodyStagingRepository)
          .supportsDirectMediaInboxCustody &&
      messageRepository is OutgoingDirectTextInboxCustodyRepository &&
      (messageRepository as OutgoingDirectTextInboxCustodyRepository)
          .supportsDirectTextInboxCustody &&
      messageRepository is OutgoingTransportMutationRepository &&
      p2pService is AckOrExpiryInboxStore &&
      p2pService is MediaExpiryBoundedInboxStore;

  /// Resolves every direct-media destination before an entry may preprocess,
  /// copy, encrypt, persist, or upload a source file.
  ///
  /// The returned map is the one decision consumed by the later target loop;
  /// no sender is allowed to re-read admission after preprocessing. Contact
  /// ids are deduplicated because one logical destination has one roster fact
  /// for this batch.
  Future<Map<String, DirectMediaFanoutAdmission>>
  _preflightDirectMediaAdmissions({
    required bool hasFiles,
    required Iterable<ShareTargetSelection> targets,
  }) async {
    if (!hasFiles) return const <String, DirectMediaFanoutAdmission>{};
    final admissions = <String, DirectMediaFanoutAdmission>{};
    for (final target in targets) {
      if (target.kind != ShareTargetSelectionKind.contact) continue;
      final peerId = target.requireContact.peerId;
      if (admissions.containsKey(peerId)) continue;
      admissions[peerId] = await resolveDirectMediaFanoutAdmission(
        mediaAttachmentRepository: mediaAttachmentRepository,
        contactAccountPeerId: peerId,
        canServeLinkedFanout: _canServeFreshDirectMediaLinkedFanout,
      );
    }
    return admissions;
  }

  Future<Map<String, GroupContentAuthoringAdmission>>
  _preflightGroupMediaAdmissions({
    required bool hasFiles,
    required IdentityModel identity,
    required Iterable<ShareTargetSelection> targets,
  }) async {
    if (!hasFiles) return const <String, GroupContentAuthoringAdmission>{};
    final groupRepo = groupRepository;
    if (groupRepo == null) {
      return const <String, GroupContentAuthoringAdmission>{};
    }
    final admissions = <String, GroupContentAuthoringAdmission>{};
    for (final target in targets) {
      if (target.kind != ShareTargetSelectionKind.group) continue;
      final groupId = target.requireGroup.id;
      if (admissions.containsKey(groupId)) continue;
      admissions[groupId] = await prepareGroupContentAuthoringAdmission(
        groupRepo: groupRepo,
        groupId: groupId,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderDeviceId: _currentSenderDeviceId,
        senderTransportPeerId: _currentSenderDeviceId,
        inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepository,
      );
    }
    return admissions;
  }

  /// Returns a complete refusal only when no READY destination is allowed to
  /// consume a preprocessed media batch. A ready group (or admitted direct
  /// contact) still justifies the shared preprocessing work; refused direct
  /// targets remain failed later without acquiring any media authority.
  ShareBatchDeliveryResult? _refuseBeforeMediaPreprocessingIfNoTargetAdmitted({
    required bool hasFiles,
    required List<_InternalForwardTargetResolution> targetPlan,
    required Map<String, DirectMediaFanoutAdmission> contactAdmissions,
    required Map<String, GroupContentAuthoringAdmission> groupAdmissions,
    required bool allowStrictFreshGroupMedia,
  }) {
    if (!hasFiles) return null;
    for (final planned in targetPlan) {
      final target = planned.current;
      if (target == null) continue;
      if (target.kind == ShareTargetSelectionKind.group) {
        final admission = groupAdmissions[target.requireGroup.id];
        if (admission?.kind ==
                GroupContentAuthoringResolutionKind.legacyUninitialized ||
            (allowStrictFreshGroupMedia &&
                admission?.kind ==
                    GroupContentAuthoringResolutionKind.strict)) {
          return null;
        }
      } else if (contactAdmissions[target.requireContact.peerId]?.refuses ==
          false) {
        return null;
      }
    }
    return ShareBatchDeliveryResult(
      results: targetPlan
          .map(
            (planned) => planned.isReady
                ? ShareBatchTargetResult(
                    target: planned.current!,
                    status: ShareBatchTargetStatus.failed,
                    detail: 'Media preparation failed.',
                  )
                : planned.failure,
          )
          .toList(growable: false),
    );
  }

  /// Reads the reviewed operation token at an entry leg whose source gate has
  /// ALREADY succeeded.
  ///
  /// Called only from the received-direct, direct-library, and group-origin
  /// entries. An uncleared [DirectForwardSourceAuthority] or a blank token
  /// means no authorization, so the target stays on its existing legacy owner.
  /// `_sendToContact` and every fresh-owner layer below it receive the returned
  /// value as an opaque argument and never recompute it.
  String? _entryAuthorizedForwardDedupKey(ShareIntent entryIntent) {
    if (entryIntent.directForwardSourceAuthority != null) return null;
    final token = entryIntent.forwardProvenance?.operationDedupKey;
    if (token == null) return null;
    final trimmed = token.trim();
    return trimmed.isEmpty || trimmed != token ? null : token;
  }

  ShareIntent _targetScopedForwardIntent({
    required ShareIntent shareIntent,
    required ShareTargetSelection target,
  }) {
    final base = shareIntent.forwardProvenance;
    if (base == null) return shareIntent;

    final targetProvenance = switch (target.kind) {
      ShareTargetSelectionKind.contact =>
        announcementForwardProvenanceForContact(
          base: base,
          contactPeerId: target.requireContact.peerId,
        ),
      ShareTargetSelectionKind.group => groupForwardProvenanceForGroup(
        base: base,
        groupId: target.requireGroup.id,
      ),
    };
    return shareIntent.copyWith(forwardProvenance: targetProvenance);
  }

  @override
  Future<ShareBatchDeliveryResult> deliver({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
    ShareBatchDeliveryProgressCallback? onProgress,
  }) async {
    if (targets.isEmpty) {
      return const ShareBatchDeliveryResult(results: []);
    }

    final isInternalForward =
        shareIntent.forwardProvenance != null ||
        shareIntent.directForwardSourceAuthority != null;
    if (!isInternalForward) {
      // External OS shares retain their historical target and fallback
      // semantics. Current-target fail-closed authorization is scoped only to
      // explicit in-app Forward operations.
      return _deliverOrdinary(
        shareIntent: shareIntent,
        targets: targets,
        onProgress: onProgress,
        externalOrdinaryShare: true,
      );
    }

    final identity = await identityRepository.loadIdentity();
    if (identity == null) {
      return _failAllTargets(targets, 'Identity unavailable.');
    }
    final targetResolutions = await _authorizeInternalForwardTargets(
      identity: identity,
      targets: targets,
      allowAnnouncementTarget: true,
    );
    if (!targetResolutions.any((resolution) => resolution.isReady)) {
      return ShareBatchDeliveryResult(
        results: targetResolutions
            .map((resolution) => resolution.failure)
            .toList(growable: false),
      );
    }

    final directAuthority = shareIntent.directForwardSourceAuthority;
    if (directAuthority == null) {
      return _deliverOrdinary(
        shareIntent: shareIntent,
        targets: targets,
        onProgress: onProgress,
        preloadedIdentity: identity,
        internalForwardTargetResolutions: targetResolutions,
      );
    }

    // `captureForDispatch` may create an immutable source copy. Direct target
    // admission therefore belongs above it, and the exact decisions are
    // carried into the later target loop rather than re-read after capture.
    final contactAdmissions = await _preflightDirectMediaAdmissions(
      hasFiles: shareIntent.hasFiles,
      targets: targetResolutions
          .where((resolution) => resolution.isReady)
          .map((resolution) => resolution.current!),
    );
    final groupAdmissions = await _preflightGroupMediaAdmissions(
      hasFiles: shareIntent.hasFiles,
      identity: identity,
      targets: targetResolutions
          .where((resolution) => resolution.isReady)
          .map((resolution) => resolution.current!),
    );
    final preflightRefusal = _refuseBeforeMediaPreprocessingIfNoTargetAdmitted(
      hasFiles: shareIntent.hasFiles,
      targetPlan: targetResolutions,
      contactAdmissions: contactAdmissions,
      groupAdmissions: groupAdmissions,
      allowStrictFreshGroupMedia: true,
    );
    if (preflightRefusal != null) return preflightRefusal;

    // Direct received-media paths carried through the picker are previews, not
    // dispatch authority. Reload the exact current direct rows, requalify their
    // parent/policy/canonical bytes, and consume only immutable lock-captured
    // snapshots below. A denial occurs before preprocessing, upload, or send.
    final capture = await BuildReceivedMediaForward(
      loadParentMessage: messageRepository.getMessage,
      mediaAttachmentRepository: mediaAttachmentRepository,
      mediaFileManager: mediaFileManager,
    ).captureForDispatch(shareIntent);
    final lease = capture.lease;
    if (lease == null) {
      return ShareBatchDeliveryResult(
        results: targets
            .map(
              (target) => ShareBatchTargetResult(
                target: target,
                status: ShareBatchTargetStatus.failed,
                detail: 'Source media is unavailable.',
              ),
            )
            .toList(growable: false),
      );
    }
    try {
      return await _deliverOrdinary(
        shareIntent: lease.shareIntent,
        targets: targets,
        onProgress: onProgress,
        preloadedIdentity: identity,
        internalForwardTargetResolutions: targetResolutions,
        // 350: the immutable capture above IS the received-direct source gate.
        // Only after it succeeds (and clears the source authority) may a
        // contact destination read this entry's reviewed operation token.
        sourceGatedInternalForward: true,
        precomputedContactAdmissions: contactAdmissions,
        precomputedGroupMediaAdmissions: groupAdmissions,
      );
    } finally {
      await lease.dispose();
    }
  }

  Future<ShareBatchDeliveryResult> _deliverOrdinary({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
    ShareBatchDeliveryProgressCallback? onProgress,
    IdentityModel? preloadedIdentity,
    List<_InternalForwardTargetResolution>? internalForwardTargetResolutions,
    bool externalOrdinaryShare = false,
    bool sourceGatedInternalForward = false,
    Map<String, DirectMediaFanoutAdmission>? precomputedContactAdmissions,
    Map<String, GroupContentAuthoringAdmission>?
    precomputedGroupMediaAdmissions,
  }) async {
    final identity =
        preloadedIdentity ?? await identityRepository.loadIdentity();
    if (identity == null) {
      return ShareBatchDeliveryResult(
        results: targets
            .map(
              (target) => ShareBatchTargetResult(
                target: target,
                status: ShareBatchTargetStatus.failed,
                detail: 'Identity unavailable.',
              ),
            )
            .toList(growable: false),
      );
    }

    final targetPlan =
        internalForwardTargetResolutions ??
        targets
            .map(
              (target) => _InternalForwardTargetResolution.ready(
                requested: target,
                current: target,
              ),
            )
            .toList(growable: false);
    final contactAdmissions =
        precomputedContactAdmissions ??
        await _preflightDirectMediaAdmissions(
          hasFiles: shareIntent.hasFiles,
          targets: targetPlan
              .where((item) => item.isReady)
              .map((item) => item.current!),
        );
    final groupAdmissions =
        precomputedGroupMediaAdmissions ??
        await _preflightGroupMediaAdmissions(
          hasFiles: shareIntent.hasFiles,
          identity: identity,
          targets: targetPlan
              .where((item) => item.isReady)
              .map((item) => item.current!),
        );
    final preflightRefusal = _refuseBeforeMediaPreprocessingIfNoTargetAdmitted(
      hasFiles: shareIntent.hasFiles,
      targetPlan: targetPlan,
      contactAdmissions: contactAdmissions,
      groupAdmissions: groupAdmissions,
      allowStrictFreshGroupMedia: externalOrdinaryShare,
    );
    if (preflightRefusal != null) return preflightRefusal;
    final processedBatch = await (processSharedMediaFn ?? _processSharedMedia)(
      shareIntent,
    );
    final processedMedia = processedBatch.processedMedia;
    final results = <ShareBatchTargetResult>[];

    var bytesPerTarget = 0;
    for (final media in processedMedia) {
      bytesPerTarget += media.budgetBytes;
    }
    final totalBytes =
        bytesPerTarget * targetPlan.where((item) => item.isReady).length;
    final progressTracker = onProgress == null || totalBytes <= 0
        ? null
        : _ShareBatchProgressTracker(
            totalBytes: totalBytes,
            onProgress: onProgress,
          );
    final uploadHooks = progressTracker?.hooks ?? ShareBatchUploadHooks.none;
    final progressSubscription = progressTracker == null
        ? null
        : (mediaUploadProgressEvents ?? mediaUploadProgressStream).listen(
            progressTracker.onUploadEvent,
          );

    try {
      for (final planned in targetPlan) {
        if (!planned.isReady) {
          results.add(planned.failure);
          continue;
        }
        var target = planned.current!;
        if (internalForwardTargetResolutions != null) {
          final current = await _authorizeInternalForwardTarget(
            identity: identity,
            target: planned.requested,
            allowAnnouncementTarget: true,
          );
          if (!current.isReady) {
            results.add(current.failure);
            continue;
          }
          target = current.current!;
        }
        // 236 TC-236-03E: each target is its own exception boundary — one
        // thrown target becomes one typed failed result and can never abort
        // the targets after it.
        ShareBatchTargetResult result;
        try {
          final targetIntent = _targetScopedForwardIntent(
            shareIntent: shareIntent,
            target: target,
          );
          final mediaAdmission = target.kind == ShareTargetSelectionKind.contact
              ? contactAdmissions[target.requireContact.peerId]
              : null;
          if (shareIntent.hasFiles &&
              target.kind == ShareTargetSelectionKind.contact &&
              mediaAdmission?.refuses != false) {
            results.add(
              ShareBatchTargetResult(
                target: target,
                status: ShareBatchTargetStatus.failed,
                detail: 'Media preparation failed.',
              ),
            );
            continue;
          }
          final groupMediaAdmission =
              target.kind == ShareTargetSelectionKind.group
              ? groupAdmissions[target.requireGroup.id]
              : null;
          if (shareIntent.hasFiles &&
              target.kind == ShareTargetSelectionKind.group &&
              (groupMediaAdmission == null ||
                  groupMediaAdmission.kind ==
                      GroupContentAuthoringResolutionKind.refuse ||
                  (!externalOrdinaryShare &&
                      groupMediaAdmission.kind ==
                          GroupContentAuthoringResolutionKind.strict))) {
            results.add(
              ShareBatchTargetResult(
                target: target,
                status: ShareBatchTargetStatus.failed,
                detail: 'Media preparation failed.',
              ),
            );
            continue;
          }
          result = switch (target.kind) {
            ShareTargetSelectionKind.contact =>
              sendToContactFn != null
                  ? await sendToContactFn!(
                      identity: identity,
                      shareIntent: targetIntent,
                      contact: target.requireContact,
                      processedMedia: processedMedia,
                      uploadHooks: uploadHooks,
                    )
                  : await _sendToContact(
                      identity: identity,
                      shareIntent: targetIntent,
                      contact: target.requireContact,
                      processedMedia: processedMedia,
                      uploadHooks: uploadHooks,
                      requireCurrentContact:
                          internalForwardTargetResolutions != null,
                      externalOrdinaryShare: externalOrdinaryShare,
                      mediaAdmission: mediaAdmission,
                      authorizedForwardDedupKey: sourceGatedInternalForward
                          ? _entryAuthorizedForwardDedupKey(targetIntent)
                          : null,
                    ),
            ShareTargetSelectionKind.group =>
              sendToGroupFn != null
                  ? await sendToGroupFn!(
                      identity: identity,
                      shareIntent: targetIntent,
                      group: target.requireGroup,
                      processedMedia: processedMedia,
                      uploadHooks: uploadHooks,
                    )
                  : await _sendToGroup(
                      identity: identity,
                      shareIntent: targetIntent,
                      group: target.requireGroup,
                      processedMedia: processedMedia,
                      uploadHooks: uploadHooks,
                      groupMediaAdmission: groupMediaAdmission,
                    ),
          };
        } catch (_) {
          uploadHooks.settled(succeeded: false);
          result = ShareBatchTargetResult(
            target: target,
            status: ShareBatchTargetStatus.failed,
            detail: 'Share failed.',
          );
        }
        results.add(result);
      }
    } finally {
      await progressSubscription?.cancel();
    }

    return ShareBatchDeliveryResult(
      results: results,
      skippedOversizedGifCount: processedBatch.skippedOversizedGifCount,
      skippedOversizedGifReason: processedBatch.skippedOversizedGifReason,
    );
  }

  ShareBatchDeliveryResult _failAllTargets(
    List<ShareTargetSelection> targets,
    String detail,
  ) => ShareBatchDeliveryResult(
    results: targets
        .map(
          (target) => ShareBatchTargetResult(
            target: target,
            status: ShareBatchTargetStatus.failed,
            detail: detail,
          ),
        )
        .toList(growable: false),
  );

  Future<List<_InternalForwardTargetResolution>>
  _authorizeInternalForwardTargets({
    required IdentityModel identity,
    required List<ShareTargetSelection> targets,
    required bool allowAnnouncementTarget,
    String? sourceGroupIdToExclude,
  }) async {
    final resolutions = <_InternalForwardTargetResolution>[];
    for (final target in targets) {
      resolutions.add(
        await _authorizeInternalForwardTarget(
          identity: identity,
          target: target,
          allowAnnouncementTarget: allowAnnouncementTarget,
          sourceGroupIdToExclude: sourceGroupIdToExclude,
        ),
      );
    }
    return List.unmodifiable(resolutions);
  }

  /// Reloads one exact destination from durable repositories. Picker rows are
  /// display state only and are never a fallback for an internal Forward.
  Future<_InternalForwardTargetResolution> _authorizeInternalForwardTarget({
    required IdentityModel identity,
    required ShareTargetSelection target,
    required bool allowAnnouncementTarget,
    String? sourceGroupIdToExclude,
  }) async {
    try {
      switch (target.kind) {
        case ShareTargetSelectionKind.contact:
          final requestedPeerId = target.requireContact.peerId;
          final current = await contactRepository.getContact(requestedPeerId);
          final mlKemKey = current?.mlKemPublicKey?.trim();
          if (current == null ||
              current.peerId != requestedPeerId ||
              !GroupMediaForwardPolicy.canTargetContact(current) ||
              mlKemKey == null ||
              mlKemKey.isEmpty) {
            return _InternalForwardTargetResolution.failed(
              requested: target,
              failureDetail: 'Contact is no longer available.',
            );
          }
          return _InternalForwardTargetResolution.ready(
            requested: target,
            current: ShareTargetSelection.contact(current),
          );
        case ShareTargetSelectionKind.group:
          final groupRepo = groupRepository;
          if (groupRepo == null) {
            return _InternalForwardTargetResolution.failed(
              requested: target,
              failureDetail: 'Group sharing is unavailable.',
            );
          }
          final authority = await _loadForwardGroupAuthority(
            groupRepo: groupRepo,
            groupId: target.requireGroup.id,
            senderPeerId: identity.peerId,
            allowAnnouncementTarget: allowAnnouncementTarget,
            sourceGroupIdToExclude: sourceGroupIdToExclude,
          );
          if (authority == null ||
              authority.group.id != target.requireGroup.id) {
            return _InternalForwardTargetResolution.failed(
              requested: target,
              failureDetail: 'You no longer have permission to post there.',
            );
          }
          return _InternalForwardTargetResolution.ready(
            requested: target,
            current: ShareTargetSelection.group(authority.group),
          );
      }
    } catch (_) {
      return _InternalForwardTargetResolution.failed(
        requested: target,
        failureDetail: 'Share failed.',
      );
    }
  }

  /// Plan 249's explicit direct-only ordinary-delivery seam.
  ///
  /// Unlike [deliver], this rejects any source that does not remain exactly
  /// one processed media item and reloads each exact active contact directly
  /// before its send. Existing callers retain [deliver]'s historical
  /// preprocessing and stale-picker fallback behavior unless they opt in to
  /// this concrete method.
  Future<ShareBatchDeliveryResult> deliverDirectMediaBatchForwardStrict({
    required ShareIntent shareIntent,
    required List<ContactModel> contacts,
    ShareBatchDeliveryProgressCallback? onProgress,
  }) async {
    if (contacts.isEmpty) {
      return const ShareBatchDeliveryResult(results: []);
    }

    ShareBatchDeliveryResult failAll(String detail) => ShareBatchDeliveryResult(
      results: contacts
          .map(
            (contact) => ShareBatchTargetResult(
              target: ShareTargetSelection.contact(contact),
              status: ShareBatchTargetStatus.failed,
              detail: detail,
            ),
          )
          .toList(growable: false),
    );

    if (shareIntent.filePaths.length != 1) {
      return failAll('Source media is unavailable.');
    }

    final identity = await identityRepository.loadIdentity();
    if (identity == null) {
      return failAll('Identity unavailable.');
    }

    final contactAdmissions = await _preflightDirectMediaAdmissions(
      hasFiles: true,
      targets: contacts.map(ShareTargetSelection.contact),
    );
    if (!contactAdmissions.values.any((admission) => !admission.refuses)) {
      return failAll('Media preparation failed.');
    }

    final ProcessedShareMediaBatch processedBatch;
    try {
      processedBatch = await (processSharedMediaFn ?? _processSharedMedia)(
        shareIntent,
      );
    } catch (_) {
      return failAll('Source media is unavailable.');
    }
    if (processedBatch.processedMedia.length != 1) {
      return failAll('Source media is unavailable.');
    }
    final processedMedia = processedBatch.processedMedia;
    // 350: this is the trusted application port reached only after
    // `DirectMediaBatchForwardDeliveryCoordinator` revalidated the exact
    // source. Plan 249's per-item token is intentionally NOT contact-scoped.
    final authorizedForwardDedupKey = _entryAuthorizedForwardDedupKey(
      shareIntent,
    );

    final mediaBytes = processedMedia.single.budgetBytes;
    final totalBytes = mediaBytes * contacts.length;
    final progressTracker = onProgress == null || totalBytes <= 0
        ? null
        : _ShareBatchProgressTracker(
            totalBytes: totalBytes,
            onProgress: onProgress,
          );
    final uploadHooks = progressTracker?.hooks ?? ShareBatchUploadHooks.none;
    final progressSubscription = progressTracker == null
        ? null
        : (mediaUploadProgressEvents ?? mediaUploadProgressStream).listen(
            progressTracker.onUploadEvent,
          );

    final results = <ShareBatchTargetResult>[];
    try {
      for (final requested in contacts) {
        ShareBatchTargetResult failed() => ShareBatchTargetResult(
          target: ShareTargetSelection.contact(requested),
          status: ShareBatchTargetStatus.failed,
          detail: 'Contact is no longer available.',
        );

        try {
          final current = await contactRepository.getContact(requested.peerId);
          final currentMlKemKey = current?.mlKemPublicKey?.trim();
          if (current == null ||
              current.peerId != requested.peerId ||
              !GroupMediaForwardPolicy.canTargetContact(current) ||
              currentMlKemKey == null ||
              currentMlKemKey.isEmpty) {
            results.add(failed());
            continue;
          }
          final mediaAdmission = contactAdmissions[current.peerId];
          if (mediaAdmission?.refuses != false) {
            results.add(
              ShareBatchTargetResult(
                target: ShareTargetSelection.contact(requested),
                status: ShareBatchTargetStatus.failed,
                detail: 'Media preparation failed.',
              ),
            );
            continue;
          }

          final sender = sendToContactFn;
          final result = sender != null
              ? await sender(
                  identity: identity,
                  // Plan 249: one item operation token is intentionally reused
                  // across its contact fan-out. Each destination still gets a
                  // fresh message/attachment identity and encryption material.
                  shareIntent: shareIntent,
                  contact: current,
                  processedMedia: processedMedia,
                  uploadHooks: uploadHooks,
                )
              : await _sendToContact(
                  identity: identity,
                  shareIntent: shareIntent,
                  contact: current,
                  processedMedia: processedMedia,
                  uploadHooks: uploadHooks,
                  useSuppliedContact: true,
                  mediaAdmission: mediaAdmission,
                  authorizedForwardDedupKey: authorizedForwardDedupKey,
                );
          results.add(result);
        } catch (_) {
          uploadHooks.settled(succeeded: false);
          results.add(failed());
        }
      }
    } finally {
      await progressSubscription?.cancel();
    }

    return ShareBatchDeliveryResult(
      results: results,
      skippedOversizedGifCount: processedBatch.skippedOversizedGifCount,
      skippedOversizedGifReason: processedBatch.skippedOversizedGifReason,
    );
  }

  @override
  Future<ShareBatchDeliveryResult> deliverGroupMediaForward({
    required GroupMediaForwardRequest request,
    String? caption,
    required List<ShareTargetSelection> targets,
  }) async {
    if (targets.isEmpty) {
      return const ShareBatchDeliveryResult(results: []);
    }

    ShareBatchDeliveryResult failAll(String detail) {
      return ShareBatchDeliveryResult(
        results: targets
            .map(
              (target) => ShareBatchTargetResult(
                target: target,
                status: ShareBatchTargetStatus.failed,
                detail: detail,
              ),
            )
            .toList(growable: false),
      );
    }

    final identity = await identityRepository.loadIdentity();
    if (identity == null) {
      return failAll('Identity unavailable.');
    }
    final groupRepo = groupRepository;
    final groupMsgRepo = groupMessageRepository;
    if (groupRepo == null || groupMsgRepo == null) {
      return failAll('Group forwarding is unavailable.');
    }
    final allowAnnouncementTarget = request is AnnouncementMediaForwardRequest;
    final sourceGroupIdToExclude = allowAnnouncementTarget
        ? request.groupId
        : null;
    final targetResolutions = await _authorizeInternalForwardTargets(
      identity: identity,
      targets: targets,
      allowAnnouncementTarget: allowAnnouncementTarget,
      sourceGroupIdToExclude: sourceGroupIdToExclude,
    );
    if (!targetResolutions.any((resolution) => resolution.isReady)) {
      return ShareBatchDeliveryResult(
        results: targetResolutions
            .map((resolution) => resolution.failure)
            .toList(growable: false),
      );
    }

    // The immutable group-source snapshot below may copy the media. Admit all
    // direct destinations first and carry these decisions through dispatch.
    final contactAdmissions = await _preflightDirectMediaAdmissions(
      hasFiles: true,
      targets: targetResolutions
          .where((resolution) => resolution.isReady)
          .map((resolution) => resolution.current!),
    );
    final groupAdmissions = await _preflightGroupMediaAdmissions(
      hasFiles: true,
      identity: identity,
      targets: targetResolutions
          .where((resolution) => resolution.isReady)
          .map((resolution) => resolution.current!),
    );
    final preflightRefusal = _refuseBeforeMediaPreprocessingIfNoTargetAdmitted(
      hasFiles: true,
      targetPlan: targetResolutions,
      contactAdmissions: contactAdmissions,
      groupAdmissions: groupAdmissions,
      allowStrictFreshGroupMedia: true,
    );
    if (preflightRefusal != null) return preflightRefusal;

    // Dispatch-time source verification: reload the exact parent and
    // group-owned row and revalidate the CURRENT canonical plaintext before
    // any target lookup, source read, or upload. Its relay contentHash belongs
    // to the authenticated ciphertext and is never applied to this file.
    final gate = GroupMediaForwardSourceGate(
      groupRepository: groupRepo,
      messageRepository: groupMsgRepo,
      mediaAttachmentRepository: mediaAttachmentRepository,
      mediaFileManager: mediaFileManager,
    );
    final sourceResult = await gate.verify(
      request,
      captureImmutableSnapshot: true,
    );
    final source = sourceResult.source;
    if (source == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEDIA_FORWARD_SOURCE_DENIED',
        details: {
          'reason': sourceResult.denialReason ?? 'unknown_source_denial',
          'targetCount': targets.length,
          'sourceKind': request is AnnouncementMediaForwardRequest
              ? 'announcement'
              : 'discussion',
        },
      );
      return failAll('This media can no longer be forwarded.');
    }
    final snapshot = source.immutableSnapshot;
    if (snapshot == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEDIA_FORWARD_SOURCE_DENIED',
        details: {
          'reason': 'immutable_snapshot_missing',
          'targetCount': targets.length,
          'sourceKind': request is AnnouncementMediaForwardRequest
              ? 'announcement'
              : 'discussion',
        },
      );
      return failAll('This media can no longer be forwarded.');
    }

    try {
      final trimmedCaption = caption?.trim() ?? '';
      final shareIntent = ShareIntent(
        type: trimmedCaption.isEmpty
            ? ShareIntentType.files
            : ShareIntentType.mixed,
        text: trimmedCaption.isEmpty ? null : trimmedCaption,
        filePaths: [snapshot.path],
        forwardProvenance: request.provenance,
      );

      // Process the immutable, lock-captured source once; every destination
      // below still gets its own fresh attachment id, encryption, and upload.
      final processedBatch =
          await (processSharedMediaFn ?? _processSharedMedia)(shareIntent);
      final processedMedia = processedBatch.processedMedia;
      if (processedMedia.length != 1 ||
          processedBatch.skippedOversizedGifCount > 0) {
        return failAll('This media can no longer be forwarded.');
      }
      final results = <ShareBatchTargetResult>[];
      for (final planned in targetResolutions) {
        if (!planned.isReady) {
          results.add(planned.failure);
          continue;
        }
        results.add(
          await _deliverForwardTarget(
            identity: identity,
            shareIntent: shareIntent,
            target: planned.current!,
            processedMedia: processedMedia,
            sourceGroupIdToExclude: sourceGroupIdToExclude,
            allowAnnouncementTarget: allowAnnouncementTarget,
            // 350: the verified source + immutable snapshot above IS this
            // entry's source gate.
            sourceGatedInternalForward: true,
            mediaAdmission:
                planned.current!.kind == ShareTargetSelectionKind.contact
                ? contactAdmissions[planned.current!.requireContact.peerId]
                : null,
            groupMediaAdmission:
                planned.current!.kind == ShareTargetSelectionKind.group
                ? groupAdmissions[planned.current!.requireGroup.id]
                : null,
          ),
        );
      }

      return ShareBatchDeliveryResult(
        results: results,
        skippedOversizedGifCount: processedBatch.skippedOversizedGifCount,
        skippedOversizedGifReason: processedBatch.skippedOversizedGifReason,
      );
    } finally {
      await snapshot.dispose();
    }
  }

  /// One forward destination: reload the CURRENT target from its repository
  /// (a missing target is failure, never stale-picker fallback), require its
  /// current authority, and isolate any thrown error to this target alone.
  Future<ShareBatchTargetResult> _deliverForwardTarget({
    required IdentityModel identity,
    required ShareIntent shareIntent,
    required ShareTargetSelection target,
    required List<PendingComposerMedia> processedMedia,
    String? sourceGroupIdToExclude,
    required bool allowAnnouncementTarget,
    bool sourceGatedInternalForward = false,
    DirectMediaFanoutAdmission? mediaAdmission,
    GroupContentAuthoringAdmission? groupMediaAdmission,
  }) async {
    ShareBatchTargetResult failed(String detail) {
      return ShareBatchTargetResult(
        target: target,
        status: ShareBatchTargetStatus.failed,
        detail: detail,
      );
    }

    try {
      switch (target.kind) {
        case ShareTargetSelectionKind.contact:
          if (mediaAdmission?.refuses != false) {
            return failed('Media preparation failed.');
          }
          final current = await contactRepository.getContact(
            target.requireContact.peerId,
          );
          if (current == null) {
            return failed('Contact is no longer available.');
          }
          if (!GroupMediaForwardPolicy.canTargetContact(current)) {
            return failed('Contact is no longer available.');
          }
          final mlKemKey = current.mlKemPublicKey?.trim();
          if (mlKemKey == null || mlKemKey.isEmpty) {
            return failed('Contact is missing required encryption support.');
          }
          final targetIntent = _targetScopedForwardIntent(
            shareIntent: shareIntent,
            target: ShareTargetSelection.contact(current),
          );
          final sender = sendToContactFn;
          return sender != null
              ? await sender(
                  identity: identity,
                  shareIntent: targetIntent,
                  contact: current,
                  processedMedia: processedMedia,
                  uploadHooks: ShareBatchUploadHooks.none,
                )
              : await _sendToContact(
                  identity: identity,
                  shareIntent: targetIntent,
                  contact: current,
                  processedMedia: processedMedia,
                  uploadHooks: ShareBatchUploadHooks.none,
                  requireCurrentContact: true,
                  mediaAdmission: mediaAdmission,
                  authorizedForwardDedupKey: sourceGatedInternalForward
                      ? _entryAuthorizedForwardDedupKey(targetIntent)
                      : null,
                );
        case ShareTargetSelectionKind.group:
          if (groupMediaAdmission == null ||
              groupMediaAdmission.kind ==
                  GroupContentAuthoringResolutionKind.refuse) {
            return failed('Media preparation failed.');
          }
          final groupRepo = groupRepository!;
          final current = await groupRepo.getGroup(target.requireGroup.id);
          if (current == null) {
            return failed('Group was not found.');
          }
          if (current.id == sourceGroupIdToExclude) {
            return failed('The source announcement cannot be a destination.');
          }
          if (!GroupMediaForwardPolicy.canTargetGroup(current)) {
            return failed('You no longer have permission to post there.');
          }
          if (current.type == GroupType.announcement &&
              !allowAnnouncementTarget) {
            return failed('You no longer have permission to post there.');
          }
          if (current.isArchived || current.isDissolved) {
            return failed('You no longer have permission to post there.');
          }
          final targetIntent = _targetScopedForwardIntent(
            shareIntent: shareIntent,
            target: ShareTargetSelection.group(current),
          );
          final sender = sendToGroupFn;
          if (sender == null) {
            return _sendToGroup(
              identity: identity,
              shareIntent: targetIntent,
              group: current,
              processedMedia: processedMedia,
              uploadHooks: ShareBatchUploadHooks.none,
              allowAnnouncementTarget: allowAnnouncementTarget,
              sourceGroupIdToExclude: sourceGroupIdToExclude,
              groupMediaAdmission: groupMediaAdmission,
            );
          }
          final authority = await _loadForwardGroupAuthority(
            groupRepo: groupRepo,
            groupId: current.id,
            senderPeerId: identity.peerId,
            allowAnnouncementTarget: allowAnnouncementTarget,
            sourceGroupIdToExclude: sourceGroupIdToExclude,
          );
          if (authority == null) {
            return failed('You no longer have permission to post there.');
          }
          return await sender(
            identity: identity,
            shareIntent: targetIntent,
            group: authority.group,
            processedMedia: processedMedia,
            uploadHooks: ShareBatchUploadHooks.none,
          );
      }
    } catch (_) {
      return failed('Share failed.');
    }
  }

  /// Hydrates the key first, then makes the coherent repository snapshot the
  /// final await before the caller starts any upload/sender work.
  Future<_ForwardGroupAuthority?> _loadForwardGroupAuthority({
    required GroupRepository groupRepo,
    required String groupId,
    required String senderPeerId,
    required bool allowAnnouncementTarget,
    String? sourceGroupIdToExclude,
  }) async {
    final GroupForwardAuthorizationSnapshotRepository? snapshotRepo =
        groupRepo is GroupForwardAuthorizationSnapshotRepository
        ? groupRepo as GroupForwardAuthorizationSnapshotRepository
        : null;
    if (snapshotRepo == null) return null;
    final hydratedLatestKey = await groupRepo.getLatestKey(groupId);
    final snapshot = await snapshotRepo.loadGroupForwardAuthorizationSnapshot(
      groupId,
    );
    final group = snapshot?.group;
    if (snapshot == null || group == null) return null;

    final normalizedSender = senderPeerId.trim();
    final ownMembers = snapshot.members
        .where((member) => member.peerId.trim() == normalizedSender)
        .toList(growable: false);
    final ownMember = ownMembers.length == 1 ? ownMembers.single : null;
    final keyMatches =
        hydratedLatestKey != null &&
        hydratedLatestKey.groupId == group.id &&
        snapshot.latestKeyGeneration == hydratedLatestKey.keyGeneration;
    if (group.id != groupId ||
        group.id == sourceGroupIdToExclude ||
        !GroupMediaForwardPolicy.canTargetGroup(group) ||
        (group.type == GroupType.announcement && !allowAnnouncementTarget) ||
        !canDeliverAnnouncementForwardToGroup(
          isArchived: group.isArchived,
          isDissolved: group.isDissolved,
          isAnnouncement: group.type == GroupType.announcement,
          isAdmin: group.myRole == GroupRole.admin,
          hasLatestKey: keyMatches,
          ownMemberRole: ownMember?.role,
        )) {
      return null;
    }
    return _ForwardGroupAuthority(
      group: group,
      members: snapshot.members,
      latestKeyGeneration: hydratedLatestKey!.keyGeneration,
    );
  }

  Future<ProcessedShareMediaBatch> _processSharedMedia(
    ShareIntent shareIntent,
  ) async {
    if (!shareIntent.hasFiles) {
      return const ProcessedShareMediaBatch(processedMedia: []);
    }

    final processed = <PendingComposerMedia>[];
    var skippedOversizedGifCount = 0;
    for (final path in shareIntent.filePaths) {
      PendingComposerMedia prepared;
      try {
        final file = File(path);
        if (!file.existsSync()) {
          continue;
        }
        prepared = await preparePendingComposerMedia(
          inputPath: path,
          imageProcessor: imageProcessor,
          imageQualityPreference: qualityPreference,
          videoQualityPreference: videoQualityPreference,
        );
      } catch (_) {
        final file = File(path);
        if (!file.existsSync()) {
          continue;
        }
        prepared = PendingComposerMedia(
          file: file,
          budgetBytes: file.lengthSync(),
        );
      }
      // Per-type SEND size gate on FINAL (post-processing) budget bytes (OQ-2 —
      // the per-type cap table now applies to share-batch too). Replaces the old
      // raw pre-compression GIF-only lengthSync check (INV-SZ-2). Oversized media
      // is skipped per-file and surfaced via the batch summary; since images and
      // video are compressed before this point, GIF is the dominant survivor of
      // an oversize, so the summary copy stays GIF-worded.
      final sizeValidation = GroupMediaSizePolicy.validateSize(
        sizeBytes: prepared.budgetBytes,
        mime: _mimeFromPath(prepared.file.path),
      );
      if (!sizeValidation.isValid) {
        skippedOversizedGifCount++;
        continue;
      }
      processed.add(prepared);
    }

    return ProcessedShareMediaBatch(
      processedMedia: processed,
      skippedOversizedGifCount: skippedOversizedGifCount,
      // Media-agnostic: the per-type gate skips ANY oversized type (image,
      // video, audio, file, gif), so the summary must not claim "GIF".
      skippedOversizedGifReason: skippedOversizedGifCount > 0
          ? 'Some attachments were too large and were skipped.'
          : null,
    );
  }

  /// Shared fresh-parent custody sender for the two authorized producers.
  ///
  /// [authorizedForwardDedupKey] is null for a marker-free external OS share.
  /// A nonblank value is the reviewed entry's exact operation token: the parent
  /// and its send completion are forwarded and carry that dedup key. This
  /// method never derives the token from [shareIntent].
  Future<ShareBatchTargetResult> _sendFreshDirectMediaWithBlobCustody({
    required IdentityModel identity,
    required ShareIntent shareIntent,
    required ContactModel contact,
    required List<PendingComposerMedia> processedMedia,
    required ShareBatchUploadHooks uploadHooks,
    required DirectMediaBlobCustodyRepository repository,
    required DirectMediaFanoutAdmission mediaAdmission,
    required String? authorizedForwardDedupKey,
  }) async {
    final isForwardedParent = authorizedForwardDedupKey != null;
    final parentDedupKey = authorizedForwardDedupKey;
    final messageId = _shareBatchUuid.v4();
    final timestamp = _forwardNow().toUtc().toIso8601String();
    final attachmentIds = List<String>.generate(
      processedMedia.length,
      (_) => _shareBatchUuid.v4(),
      growable: false,
    );
    final lease = mediaUploadInFlightTracker.tryClaimAll(
      attachmentIds,
      source: MediaUploadTriggerSource.foreground,
    );
    if (lease == null) {
      return ShareBatchTargetResult(
        target: ShareTargetSelection.contact(contact),
        status: ShareBatchTargetStatus.failed,
        detail: 'Media upload is already in progress.',
      );
    }

    var hasDurableAuthority = false;
    var progressStarted = false;
    var progressSettled = false;
    var uploadCompleted = false;
    var completedAttachments = const <MediaAttachment>[];
    DirectLinkedMediaFanoutContext? linkedMediaFanout;
    ConversationMessage? attemptedParent;
    List<MediaAttachment> attemptedAttachments = const <MediaAttachment>[];
    try {
      final expectedAttachments = <MediaAttachment>[];
      final sources = <PreparedDirectMediaBlobSource>[];
      for (var index = 0; index < processedMedia.length; index++) {
        final media = processedMedia[index];
        final attachmentId = attachmentIds[index];
        final mime = _mimeFromPath(media.file.path);
        final size = await media.file.length();
        if (size <= 0) {
          return ShareBatchTargetResult(
            target: ShareTargetSelection.contact(contact),
            status: ShareBatchTargetStatus.failed,
            detail: 'Media is unavailable.',
          );
        }
        final localPath = MediaFilePathConvention.relativePathForPendingUpload(
          messageId: messageId,
          attachmentId: attachmentId,
          mime: mime,
        );
        final attachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: mime,
          size: size,
          mediaType: MediaAttachment.mediaTypeFromMime(mime),
          width: media.width,
          height: media.height,
          durationMs: media.durationMs,
          localPath: localPath,
          downloadStatus: 'upload_pending',
          createdAt: timestamp,
          ownerLane: MediaOwnerLane.direct,
        );
        expectedAttachments.add(attachment);
        sources.add(
          PreparedDirectMediaBlobSource(
            attachment: attachment,
            plaintextPath: media.file.path,
          ),
        );
      }
      final intentId = computeDirectMediaCustodyIntentId(
        messageId: messageId,
        attachmentIds: attachmentIds,
      );
      final parent = ConversationMessage(
        id: messageId,
        contactPeerId: contact.peerId,
        senderPeerId: identity.peerId,
        text: sanitizeMessageText(shareIntent.text ?? ''),
        timestamp: timestamp,
        status: 'sending',
        isIncoming: false,
        createdAt: timestamp,
        directMediaCustodyIntentId: intentId,
        dedupKey: parentDedupKey ?? messageId,
        isForwarded: isForwardedParent,
      );
      attemptedParent = parent;
      attemptedAttachments = List<MediaAttachment>.unmodifiable(
        expectedAttachments,
      );
      for (var index = 0; index < expectedAttachments.length; index++) {
        uploadHooks.started(
          blobId: expectedAttachments[index].id,
          budgetBytes: processedMedia[index].budgetBytes,
        );
      }
      progressStarted = true;

      // 362: the fanout admission boundary in _sendToContact now governs
      // this entry AND the legacy loop, above every send-owned write, so
      // the old too-late guard that used to sit here is gone.
      final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
        repository: repository,
        artifactStore: DirectMediaBlobArtifactStore(),
      );
      if (mediaAdmission.requiresLinkedFanout) {
        final snapshot = mediaAdmission.snapshot!;
        final fanoutResult = await coordinator.prepareAndUploadFreshFanout(
          bridge: bridge,
          identityPeerId: identity.peerId,
          contactAccountPeerId: contact.peerId,
          snapshot: snapshot,
          expectedParent: parent,
          sources: sources,
          allowFreshParent: true,
          authorizedForwardDedupKey: authorizedForwardDedupKey,
          onAuthorityReady: (winnerAttachments) =>
              _copyFreshDirectMediaPreviewAfterAuthority(
                messageId: messageId,
                processedMedia: processedMedia,
                expectedAttachments: expectedAttachments,
                winnerAttachments: winnerAttachments,
              ),
          onGenerationReady: p2pService.isLocalPeer(contact.peerId)
              ? (artifacts) async {
                  for (final artifact in artifacts) {
                    await p2pService.sendLocalMedia(
                      peerId: contact.peerId,
                      filePath: artifact.absoluteCiphertextPath,
                      mime: kOpaqueMediaTransportMime,
                      mediaId: artifact.attachment.id,
                      fromPeerId: identity.peerId,
                      durationMs: artifact.attachment.durationMs,
                      enc: true,
                      encScheme: artifact.attachment.encryptionScheme,
                    );
                  }
                }
              : null,
        );
        uploadCompleted = fanoutResult.isComplete;
        completedAttachments = fanoutResult.attachments;
        hasDurableAuthority = fanoutResult.hasDurableAuthority;
        if (uploadCompleted) {
          linkedMediaFanout = DirectLinkedMediaFanoutContext(
            contactAccountPeerId: contact.peerId,
            snapshot: snapshot,
            targetRows: fanoutResult.targetRows,
          );
        }
      } else {
        final uploadResult = await coordinator.prepareAndUploadFreshMessage(
          bridge: bridge,
          identityPeerId: identity.peerId,
          recipientPeerId: contact.peerId,
          parent: parent,
          sources: sources,
          authorizedForwardDedupKey: authorizedForwardDedupKey,
          onAuthorityReady: (winnerAttachments) =>
              _copyFreshDirectMediaPreviewAfterAuthority(
                messageId: messageId,
                processedMedia: processedMedia,
                expectedAttachments: expectedAttachments,
                winnerAttachments: winnerAttachments,
              ),
          onGenerationReady: p2pService.isLocalPeer(contact.peerId)
              ? (artifacts) async {
                  for (final artifact in artifacts) {
                    await p2pService.sendLocalMedia(
                      peerId: contact.peerId,
                      filePath: artifact.absoluteCiphertextPath,
                      mime: kOpaqueMediaTransportMime,
                      mediaId: artifact.attachment.id,
                      fromPeerId: identity.peerId,
                      durationMs: artifact.attachment.durationMs,
                      enc: true,
                      encScheme: artifact.attachment.encryptionScheme,
                    );
                  }
                }
              : null,
        );
        uploadCompleted = uploadResult.isComplete;
        completedAttachments = uploadResult.attachments;
        hasDurableAuthority = uploadResult.hasDurableAuthority;
      }
      for (final _ in attachmentIds) {
        uploadHooks.settled(succeeded: uploadCompleted);
      }
      progressSettled = true;
      if (!uploadCompleted) {
        hasDurableAuthority =
            hasDurableAuthority ||
            (mediaAdmission.requiresLinkedFanout
                ? false
                : await _hasExactFreshDirectMediaAuthority(
                    parent: parent,
                    expectedAttachments: expectedAttachments,
                    repository: repository,
                    authorizedForwardDedupKey: authorizedForwardDedupKey,
                  ));
        return ShareBatchTargetResult(
          target: ShareTargetSelection.contact(contact),
          status: hasDurableAuthority
              ? ShareBatchTargetStatus.queued
              : ShareBatchTargetStatus.failed,
          detail: hasDurableAuthority
              ? 'Saved locally for later retry.'
              : 'Media preparation failed.',
        );
      }

      uploadHooks.sending();
      try {
        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepository,
          targetPeerId: contact.peerId,
          text: parent.text,
          senderPeerId: identity.peerId,
          senderUsername: identity.username,
          messageId: messageId,
          timestamp: timestamp,
          createdAt: timestamp,
          dedupKey: parentDedupKey ?? messageId,
          isForwarded: isForwardedParent,
          bridge: bridge,
          recipientMlKemPublicKey: contact.mlKemPublicKey,
          mediaAttachments: completedAttachments,
          mediaAttachmentRepo: mediaAttachmentRepository,
          directLinkedMediaFanout: linkedMediaFanout,
        );
        return ShareBatchTargetResult(
          target: ShareTargetSelection.contact(contact),
          status: result == SendChatMessageResult.success
              ? ShareBatchTargetStatus.sent
              : ShareBatchTargetStatus.queued,
          detail: result == SendChatMessageResult.success
              ? 'Sent.'
              : 'Saved locally for later retry.',
        );
      } on Object {
        return ShareBatchTargetResult(
          target: ShareTargetSelection.contact(contact),
          status: ShareBatchTargetStatus.queued,
          detail: 'Saved locally for later retry.',
        );
      }
    } on Object {
      try {
        final parent = attemptedParent;
        if (!hasDurableAuthority && parent != null) {
          hasDurableAuthority = await _hasExactFreshDirectMediaAuthority(
            parent: parent,
            expectedAttachments: attemptedAttachments,
            repository: repository,
            authorizedForwardDedupKey: authorizedForwardDedupKey,
          );
        }
      } on Object {
        // Keep the known authority fact. A failed re-read cannot revoke it.
      }
      return ShareBatchTargetResult(
        target: ShareTargetSelection.contact(contact),
        status: hasDurableAuthority
            ? ShareBatchTargetStatus.queued
            : ShareBatchTargetStatus.failed,
        detail: hasDurableAuthority
            ? 'Saved locally for later retry.'
            : 'Share failed.',
      );
    } finally {
      if (progressStarted && !progressSettled) {
        for (final _ in attachmentIds) {
          uploadHooks.settled(succeeded: uploadCompleted);
        }
      }
      mediaUploadInFlightTracker.release(lease);
    }
  }

  Future<bool> _copyFreshDirectMediaPreviewAfterAuthority({
    required String messageId,
    required List<PendingComposerMedia> processedMedia,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> winnerAttachments,
  }) async {
    final winnerById = <String, MediaAttachment>{
      for (final attachment in winnerAttachments) attachment.id: attachment,
    };
    if (winnerById.length != processedMedia.length ||
        expectedAttachments.length != processedMedia.length) {
      return false;
    }
    for (var index = 0; index < processedMedia.length; index++) {
      final source = processedMedia[index].file;
      final expectedId = expectedAttachments[index].id;
      final winner = winnerById[expectedId];
      if (winner == null || winner.messageId != messageId) return false;
      final expectedPath = MediaFilePathConvention.relativePathForPendingUpload(
        messageId: messageId,
        attachmentId: winner.id,
        mime: winner.mime,
      );
      if (winner.localPath != expectedPath) return false;
      final copiedPath = await mediaFileManager.copyToDurableStorage(
        sourceFilePath: source.path,
        messageId: messageId,
        attachmentId: winner.id,
        mime: winner.mime,
      );
      if (copiedPath.replaceAll('\\', '/') != expectedPath) return false;
      final absolutePath = await mediaFileManager.resolveStoredPath(copiedPath);
      if (await FileSystemEntity.type(absolutePath, followLinks: false) !=
          FileSystemEntityType.file) {
        return false;
      }
      final sourceDigest = await sha256.bind(source.openRead()).first;
      final copyDigest = await sha256.bind(File(absolutePath).openRead()).first;
      if (sourceDigest.toString() != copyDigest.toString()) return false;
    }
    return true;
  }

  /// Exact share-level authority re-read after an ambiguous commit.
  ///
  /// [authorizedForwardDedupKey] null requires the marker-free external shape;
  /// a nonblank value requires the exact forwarded shape. Any drift in
  /// recipient, token, `isForwarded`, ID, or projection is NOT authority.
  Future<bool> _hasExactFreshDirectMediaAuthority({
    required ConversationMessage parent,
    required List<MediaAttachment> expectedAttachments,
    required DirectMediaBlobCustodyRepository repository,
    required String? authorizedForwardDedupKey,
  }) async {
    final attachmentIds = expectedAttachments
        .map((attachment) => attachment.id)
        .toList(growable: false);
    final ids = attachmentIds.toSet();
    if (attachmentIds.isEmpty || ids.length != attachmentIds.length) {
      return false;
    }
    if (authorizedForwardDedupKey != null) {
      final token = authorizedForwardDedupKey.trim();
      if (token.isEmpty ||
          token != authorizedForwardDedupKey ||
          !parent.isForwarded ||
          parent.dedupKey != authorizedForwardDedupKey) {
        return false;
      }
    } else if (parent.isForwarded || parent.id != parent.dedupKey) {
      return false;
    }
    final currentParent = await messageRepository.getMessage(parent.id);
    final currentAttachments = await mediaAttachmentRepository
        .getAttachmentsForMessage(parent.id, owner: MediaOwnerLane.direct);
    final currentRows = await repository.loadDirectMediaBlobCustodyForMessage(
      parent.id,
    );
    final exactIntent = computeDirectMediaCustodyIntentId(
      messageId: parent.id,
      attachmentIds: attachmentIds,
    );
    final expectedById = <String, MediaAttachment>{
      for (final attachment in expectedAttachments) attachment.id: attachment,
    };
    final currentById = <String, MediaAttachment>{
      for (final attachment in currentAttachments) attachment.id: attachment,
    };
    final rowById = <String, DirectMediaBlobCustodyRow>{
      for (final row in currentRows) row.attachmentId: row,
    };
    return currentParent != null &&
        !currentParent.isIncoming &&
        currentParent.id == parent.id &&
        currentParent.contactPeerId == parent.contactPeerId &&
        currentParent.senderPeerId == parent.senderPeerId &&
        currentParent.text == parent.text &&
        currentParent.timestamp == parent.timestamp &&
        currentParent.createdAt == parent.createdAt &&
        currentParent.dedupKey == parent.dedupKey &&
        currentParent.isForwarded == parent.isForwarded &&
        currentParent.timestamp == currentParent.createdAt &&
        currentParent.editedAt == null &&
        currentParent.quotedMessageId == null &&
        currentParent.deletedAt == null &&
        currentParent.deletedByPeerId == null &&
        currentParent.hiddenAt == null &&
        currentParent.directMediaCustodyIntentId == exactIntent &&
        currentParent.privateMediaPolicy.version == 0 &&
        currentParent.privateMediaMode == PrivateMediaMode.ordinary &&
        currentParent.privateMediaDurationSeconds == null &&
        currentParent.privateMediaState == PrivateMediaLifecycleState.none &&
        currentAttachments.length == ids.length &&
        currentRows.length == ids.length &&
        expectedById.length == ids.length &&
        currentById.length == ids.length &&
        rowById.length == ids.length &&
        ids.every((attachmentId) {
          final expected = expectedById[attachmentId];
          final current = currentById[attachmentId];
          final row = rowById[attachmentId];
          if (expected == null || current == null || row == null) return false;
          final expectedPath =
              MediaFilePathConvention.relativePathForPendingUpload(
                messageId: parent.id,
                attachmentId: attachmentId,
                mime: expected.mime,
              );
          return expected.messageId == parent.id &&
              expected.ownerLane == MediaOwnerLane.direct &&
              expected.localPath == expectedPath &&
              expected.downloadStatus == 'upload_pending' &&
              expected.contentHash == null &&
              current.messageId == parent.id &&
              current.ownerLane == MediaOwnerLane.direct &&
              current.mime == expected.mime &&
              current.size == expected.size &&
              current.mediaType == expected.mediaType &&
              current.width == expected.width &&
              current.height == expected.height &&
              current.durationMs == expected.durationMs &&
              current.createdAt == expected.createdAt &&
              current.localPath == expectedPath &&
              current.downloadStatus == 'upload_pending' &&
              current.contentHash == row.contentHash &&
              current.encryptionNonce != null &&
              current.encryptionNonce!.isNotEmpty &&
              current.encryptionScheme != null &&
              current.encryptionScheme!.isNotEmpty &&
              row.messageId == parent.id &&
              row.recipientPeerId == parent.contactPeerId &&
              row.direction == DirectMediaBlobCustodyDirection.outgoing &&
              (row.state == DirectMediaBlobCustodyState.outgoingPrepared ||
                  row.state == DirectMediaBlobCustodyState.outgoingStored);
        });
  }

  /// [authorizedForwardDedupKey] is read ONLY at a reviewed forward entry leg
  /// whose source gate already succeeded, and is passed here as an independent
  /// value. This method and every layer below it must never re-derive it from
  /// [shareIntent]'s provenance, the candidate parent, or the attachments.
  Future<ShareBatchTargetResult> _sendToContact({
    required IdentityModel identity,
    required ShareIntent shareIntent,
    required ContactModel contact,
    required List<PendingComposerMedia> processedMedia,
    required ShareBatchUploadHooks uploadHooks,
    bool useSuppliedContact = false,
    bool requireCurrentContact = false,
    bool externalOrdinaryShare = false,
    DirectMediaFanoutAdmission? mediaAdmission,
    String? authorizedForwardDedupKey,
  }) async {
    assert(!(useSuppliedContact && requireCurrentContact));
    final currentContact = useSuppliedContact
        ? contact
        : await contactRepository.getContact(contact.peerId);
    final currentMlKemKey = currentContact?.mlKemPublicKey?.trim();
    if (requireCurrentContact &&
        (currentContact == null ||
            !GroupMediaForwardPolicy.canTargetContact(currentContact) ||
            currentMlKemKey == null ||
            currentMlKemKey.isEmpty)) {
      return ShareBatchTargetResult(
        target: ShareTargetSelection.contact(contact),
        status: ShareBatchTargetStatus.failed,
        detail: 'Contact is no longer available.',
      );
    }
    final resolvedContact = currentContact ?? contact;
    final directBlobRepository = switch (mediaAttachmentRepository) {
      DirectMediaBlobCustodyRepository repository
          when repository.supportsDirectMediaBlobCustody =>
        repository,
      _ => null,
    };
    final freshBlobRepository = switch (mediaAttachmentRepository) {
      FreshOutgoingDirectMediaBlobGenerationRepository repository
          when repository.supportsFreshOutgoingDirectMediaBlobGeneration =>
        repository,
      _ => null,
    };
    final directInboxCapability = switch (mediaAttachmentRepository) {
      OutgoingDirectMediaInboxCustodyStagingRepository repository
          when repository.supportsDirectMediaInboxCustody =>
        repository,
      _ => null,
    };
    final textCustodyCapability = switch (messageRepository) {
      OutgoingDirectTextInboxCustodyRepository repository
          when repository.supportsDirectTextInboxCustody =>
        repository,
      _ => null,
    };
    final resolvedMlKemKey = resolvedContact.mlKemPublicKey?.trim();
    // Exactly one of two authorized fresh producers may select strict custody.
    final externalOrdinaryAuthorized =
        authorizedForwardDedupKey == null &&
        externalOrdinaryShare &&
        !useSuppliedContact &&
        !requireCurrentContact &&
        shareIntent.forwardProvenance == null &&
        shareIntent.directForwardSourceAuthority == null;
    // An uncleared source authority means the entry's snapshot gate has not
    // completed; it can never reach strict selection.
    final internalForwardAuthorized =
        authorizedForwardDedupKey != null &&
        authorizedForwardDedupKey.trim() == authorizedForwardDedupKey &&
        authorizedForwardDedupKey.isNotEmpty &&
        !externalOrdinaryShare &&
        shareIntent.directForwardSourceAuthority == null;
    final strictFreshSelected =
        directMediaBlobCustodyClientEnabled &&
        (externalOrdinaryAuthorized || internalForwardAuthorized) &&
        processedMedia.isNotEmpty &&
        GroupMediaForwardPolicy.canTargetContact(resolvedContact) &&
        resolvedMlKemKey != null &&
        resolvedMlKemKey.isNotEmpty &&
        directBlobRepository != null &&
        freshBlobRepository != null &&
        directInboxCapability != null &&
        textCustodyCapability != null &&
        messageRepository is OutgoingTransportMutationRepository &&
        p2pService is AckOrExpiryInboxStore &&
        p2pService is MediaExpiryBoundedInboxStore;
    // Admission was resolved by the entry BEFORE preprocessing/copying. A
    // media sender that reaches this private sink without that decision is a
    // wiring defect and fails closed; it never performs a late roster read.
    // The linked route is immutable too: contact/key/capability drift may make
    // the strict owner unavailable, but can never demote the captured linked
    // snapshot to the legacy singular uploader below.
    final linkedAdmissionCannotUseStrictOwner =
        mediaAdmission?.requiresLinkedFanout == true && !strictFreshSelected;
    if (processedMedia.isNotEmpty &&
        (mediaAdmission?.refuses != false ||
            linkedAdmissionCannotUseStrictOwner)) {
      return ShareBatchTargetResult(
        target: ShareTargetSelection.contact(contact),
        status: ShareBatchTargetStatus.failed,
        detail: 'Media preparation failed.',
      );
    }
    if (strictFreshSelected) {
      return _sendFreshDirectMediaWithBlobCustody(
        identity: identity,
        shareIntent: shareIntent,
        contact: resolvedContact,
        processedMedia: processedMedia,
        uploadHooks: uploadHooks,
        repository: directBlobRepository,
        mediaAdmission: mediaAdmission!,
        authorizedForwardDedupKey: internalForwardAuthorized
            ? authorizedForwardDedupKey
            : null,
      );
    }
    final attachments = <MediaAttachment>[];

    for (final media in processedMedia) {
      final mime = _mimeFromPath(media.file.path);
      final attachmentId = _shareBatchUuid.v4();
      // LAN best-effort first, but the relay upload below ALWAYS runs
      // (composer semantics): it is the durable recovery copy AND the
      // source of the attachment's encryption metadata. The old
      // LAN-success `continue` skipped uploadMedia entirely, building a
      // metadata-free attachment the G5 send gate now rejects (112 Phase
      // 2.4). Phase 4: encrypt once — the LAN leg streams the SAME
      // ciphertext artifact the relay upload consumes, never the raw
      // shared file.
      EncryptedMediaArtifact? preparedArtifact;
      if (p2pService.isLocalPeer(resolvedContact.peerId)) {
        try {
          preparedArtifact = await prepareEncryptedMediaArtifact(
            bridge: bridge,
            localFilePath: media.file.path,
          );
          await p2pService.sendLocalMedia(
            peerId: resolvedContact.peerId,
            filePath: preparedArtifact.encryptedPath,
            mime: kOpaqueMediaTransportMime,
            mediaId: attachmentId,
            fromPeerId: identity.peerId,
            durationMs: media.durationMs,
            enc: true,
            encScheme: preparedArtifact.scheme,
          );
        } catch (_) {
          // Fail closed on the LAN leg — never stream the raw shared file.
          preparedArtifact = null;
        }
      }

      uploadHooks.started(blobId: attachmentId, budgetBytes: media.budgetBytes);
      MediaAttachment? uploaded;
      try {
        final outcome = await runUploadMedia(
          uploadMediaFn: uploadMedia,
          bridge: bridge,
          localFilePath: media.file.path,
          mime: mime,
          recipientPeerId: resolvedContact.peerId,
          mediaFileManager: mediaFileManager,
          width: media.width,
          height: media.height,
          durationMs: media.durationMs,
          blobId: attachmentId,
          preparedArtifact: preparedArtifact,
        );
        uploaded = outcome.attachmentOrNull;
      } finally {
        uploadHooks.settled(succeeded: uploaded != null);
      }
      if (uploaded == null) {
        return ShareBatchTargetResult(
          target: ShareTargetSelection.contact(resolvedContact),
          status: ShareBatchTargetStatus.failed,
          detail: 'Media upload failed.',
        );
      }
      attachments.add(uploaded);
    }

    final text = shareIntent.text ?? '';
    uploadHooks.sending();
    final (result, message) = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepository,
      targetPeerId: resolvedContact.peerId,
      text: text,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      bridge: bridge,
      recipientMlKemPublicKey: resolvedContact.mlKemPublicKey,
      mediaAttachments: attachments.isEmpty ? null : attachments,
      mediaAttachmentRepo: mediaAttachmentRepository,
      dedupKey: shareIntent.forwardProvenance?.operationDedupKey,
      isForwarded: shareIntent.forwardProvenance != null,
      directEventFanout: directEventFanoutResolver?.call(),
    );

    return ShareBatchTargetResult(
      target: ShareTargetSelection.contact(resolvedContact),
      status: switch (result) {
        SendChatMessageResult.success => ShareBatchTargetStatus.sent,
        _ when message != null => ShareBatchTargetStatus.queued,
        _ => ShareBatchTargetStatus.failed,
      },
      detail: switch (result) {
        SendChatMessageResult.success => 'Sent.',
        SendChatMessageResult.nodeNotRunning =>
          'Saved locally for later retry.',
        SendChatMessageResult.peerNotFound => 'Saved locally for later retry.',
        SendChatMessageResult.dialFailed => 'Saved locally for later retry.',
        SendChatMessageResult.sendFailed when message != null =>
          'Saved locally for later retry.',
        SendChatMessageResult.invalidMessage => 'Nothing valid to share.',
        SendChatMessageResult.encryptionRequired =>
          'Contact is missing required encryption support.',
        _ => 'Share failed.',
      },
    );
  }

  Future<ShareBatchTargetResult> _sendToGroup({
    required IdentityModel identity,
    required ShareIntent shareIntent,
    required GroupModel group,
    required List<PendingComposerMedia> processedMedia,
    required ShareBatchUploadHooks uploadHooks,
    bool allowAnnouncementTarget = true,
    String? sourceGroupIdToExclude,
    GroupContentAuthoringAdmission? groupMediaAdmission,
  }) async {
    final groupRepo = groupRepository;
    final msgRepo = groupMessageRepository;
    if (groupRepo == null || msgRepo == null) {
      return ShareBatchTargetResult(
        target: ShareTargetSelection.group(group),
        status: ShareBatchTargetStatus.failed,
        detail: 'Group sharing is unavailable.',
      );
    }

    var exactMediaAdmission = groupMediaAdmission;
    if (processedMedia.isNotEmpty && exactMediaAdmission == null) {
      exactMediaAdmission = await prepareGroupContentAuthoringAdmission(
        groupRepo: groupRepo,
        groupId: group.id,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderDeviceId: _currentSenderDeviceId,
        senderTransportPeerId: _currentSenderDeviceId,
        inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepository,
      );
    }
    if (processedMedia.isNotEmpty &&
        (exactMediaAdmission == null ||
            exactMediaAdmission.kind ==
                GroupContentAuthoringResolutionKind.refuse)) {
      return ShareBatchTargetResult(
        target: ShareTargetSelection.group(group),
        status: ShareBatchTargetStatus.failed,
        detail: 'Media preparation failed.',
      );
    }

    String? bgTaskId;
    try {
      bgTaskId = await callBgBegin(bridge);
      final operationKey = shareIntent.forwardProvenance?.operationDedupKey
          .trim();
      final stableOperationKey = operationKey == null || operationKey.isEmpty
          ? null
          : operationKey;
      final existingOutput = stableOperationKey == null
          ? null
          : await msgRepo.getMessage(stableOperationKey);

      final authority = await _loadForwardGroupAuthority(
        groupRepo: groupRepo,
        groupId: group.id,
        senderPeerId: identity.peerId,
        allowAnnouncementTarget: allowAnnouncementTarget,
        sourceGroupIdToExclude: sourceGroupIdToExclude,
      );
      if (authority == null) {
        return ShareBatchTargetResult(
          target: ShareTargetSelection.group(group),
          status: ShareBatchTargetStatus.failed,
          detail: 'You no longer have permission to post there.',
        );
      }
      final resolvedGroup = authority.group;
      if (existingOutput != null) {
        final coherent =
            stableOperationKey != null &&
            existingOutput.id == stableOperationKey &&
            existingOutput.logicalDeliveryId == stableOperationKey &&
            existingOutput.groupId == resolvedGroup.id &&
            existingOutput.senderPeerId == identity.peerId &&
            !existingOutput.isIncoming &&
            existingOutput.isForwarded;
        if (!coherent) {
          return ShareBatchTargetResult(
            target: ShareTargetSelection.group(resolvedGroup),
            status: ShareBatchTargetStatus.failed,
            detail: 'Forward identity is no longer available.',
          );
        }
        final alreadySent =
            existingOutput.status == 'sent' ||
            existingOutput.status == 'delivered';
        return ShareBatchTargetResult(
          target: ShareTargetSelection.group(resolvedGroup),
          status: alreadySent
              ? ShareBatchTargetStatus.sent
              : ShareBatchTargetStatus.queued,
          detail: alreadySent ? 'Sent.' : 'Saved locally for existing retry.',
        );
      }
      if (processedMedia.isNotEmpty &&
          exactMediaAdmission!.kind ==
              GroupContentAuthoringResolutionKind.strict) {
        final now = _forwardNow();
        final messageId = stableOperationKey ?? _shareBatchUuid.v4();
        final sources = <PreparedGroupMediaBlobSource>[];
        for (final media in processedMedia) {
          final attachmentId = _shareBatchUuid.v4();
          final mime = _mimeFromPath(media.file.path);
          final size = await media.file.length();
          uploadHooks.started(
            blobId: attachmentId,
            budgetBytes: media.budgetBytes,
          );
          sources.add(
            PreparedGroupMediaBlobSource(
              attachment: MediaAttachment(
                id: attachmentId,
                messageId: messageId,
                mime: mime,
                size: size,
                mediaType: MediaAttachment.mediaTypeFromMime(mime),
                width: media.width,
                height: media.height,
                durationMs: media.durationMs,
                localPath: media.file.path,
                downloadStatus: 'upload_pending',
                createdAt: now.toUtc().toIso8601String(),
                ownerLane: MediaOwnerLane.group,
              ),
              plaintextPath: media.file.path,
            ),
          );
        }
        uploadHooks.sending();
        final strict = await _strictGroupMediaOwner.prepareAndSend(
          bridge: bridge,
          groupRepository: groupRepo,
          messageRepository: msgRepo,
          mediaAttachmentRepository: mediaAttachmentRepository,
          identityPeerId: identity.peerId,
          senderPublicKey: identity.publicKey,
          senderPrivateKey: identity.privateKey,
          senderUsername: identity.username,
          senderDeviceId: _currentSenderDeviceId,
          senderTransportPeerId: _currentSenderDeviceId,
          inviteDeliveryAttemptRepository: groupInviteDeliveryAttemptRepository,
          parent: GroupMessage(
            id: messageId,
            groupId: resolvedGroup.id,
            senderPeerId: identity.peerId,
            senderUsername: identity.username,
            text: shareIntent.text ?? '',
            timestamp: now,
            status: GroupMessage.statusQueuedOffline,
            isIncoming: false,
            createdAt: now,
            logicalDeliveryId: messageId,
            isForwarded: shareIntent.forwardProvenance != null,
          ),
          sources: sources,
        );
        for (final _ in processedMedia) {
          uploadHooks.settled(succeeded: strict.preparation.isComplete);
        }
        if (!strict.preparation.isComplete) {
          return ShareBatchTargetResult(
            target: ShareTargetSelection.group(resolvedGroup),
            status: strict.preparation.hasDurableAuthority
                ? ShareBatchTargetStatus.queued
                : ShareBatchTargetStatus.failed,
            detail: strict.preparation.hasDurableAuthority
                ? 'Saved locally for later retry.'
                : 'Media preparation failed.',
          );
        }
        final result = strict.sendResult;
        final message = strict.message;
        final pendingCompletion =
            result == SendGroupMessageResult.success &&
            message?.status == 'pending';
        return ShareBatchTargetResult(
          target: ShareTargetSelection.group(resolvedGroup),
          status: switch (result) {
            SendGroupMessageResult.success when pendingCompletion =>
              ShareBatchTargetStatus.queued,
            SendGroupMessageResult.success => ShareBatchTargetStatus.sent,
            SendGroupMessageResult.successNoPeers ||
            SendGroupMessageResult.queuedOffline =>
              ShareBatchTargetStatus.queued,
            _ when strict.preparation.hasDurableAuthority =>
              ShareBatchTargetStatus.queued,
            _ => ShareBatchTargetStatus.failed,
          },
          detail: switch (result) {
            SendGroupMessageResult.success when pendingCompletion =>
              'Stored while group delivery finishes.',
            SendGroupMessageResult.success => 'Sent.',
            SendGroupMessageResult.successNoPeers ||
            SendGroupMessageResult.queuedOffline =>
              'Saved locally for later retry.',
            _ => 'Share failed.',
          },
        );
      }
      var mediaUploadFailed = false;
      final attachments = <MediaAttachment>[];
      var uploadAuthority = authority;
      for (final media in processedMedia) {
        final guardedUpload =
            await runSelfRemovedGroupLifecycleLeaf<_ForwardGroupUploadLeaf?>(
              groupRepo: groupRepo,
              groupId: resolvedGroup.id,
              action: (currentGroup) async {
                if (currentGroup.isDissolved) return null;
                final currentAuthority = await _loadForwardGroupAuthority(
                  groupRepo: groupRepo,
                  groupId: resolvedGroup.id,
                  senderPeerId: identity.peerId,
                  allowAnnouncementTarget: allowAnnouncementTarget,
                  sourceGroupIdToExclude: sourceGroupIdToExclude,
                );
                if (currentAuthority == null ||
                    !_sameForwardGroupAuthority(
                      uploadAuthority,
                      currentAuthority,
                    )) {
                  return null;
                }

                final attachmentId = _shareBatchUuid.v4();
                uploadHooks.started(
                  blobId: attachmentId,
                  budgetBytes: media.budgetBytes,
                );
                MediaAttachment? uploaded;
                try {
                  final outcome = await runUploadMedia(
                    uploadMediaFn: uploadMedia,
                    bridge: bridge,
                    localFilePath: media.file.path,
                    mime: _mimeFromPath(media.file.path),
                    recipientPeerId: resolvedGroup.id,
                    mediaFileManager: mediaFileManager,
                    width: media.width,
                    height: media.height,
                    durationMs: media.durationMs,
                    allowedPeers: groupMediaAllowedPeersForMembers(
                      currentAuthority.members,
                    ),
                    blobId: attachmentId,
                  );
                  uploaded = outcome.attachmentOrNull;
                } finally {
                  uploadHooks.settled(succeeded: uploaded != null);
                }
                if (uploaded == null) {
                  mediaUploadFailed = true;
                  return null;
                }
                return _ForwardGroupUploadLeaf(
                  authority: currentAuthority,
                  attachment: uploaded.copyWith(
                    id: attachmentId,
                    downloadStatus: 'done',
                  ),
                );
              },
            );
        final uploadLeaf = guardedUpload.value;
        if (!guardedUpload.didRun || uploadLeaf == null) {
          return ShareBatchTargetResult(
            target: ShareTargetSelection.group(resolvedGroup),
            status: ShareBatchTargetStatus.failed,
            detail: mediaUploadFailed
                ? 'Media upload failed.'
                : 'You no longer have permission to post there.',
          );
        }
        uploadAuthority = uploadLeaf.authority;
        attachments.add(uploadLeaf.attachment);
      }

      final senderDeviceId = _currentSenderDeviceId;
      final forwardTimestamp = stableOperationKey == null
          ? null
          : _forwardTimestampByOperationKey.putIfAbsent(
              stableOperationKey,
              _forwardNow,
            );
      uploadHooks.sending();
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: resolvedGroup.id,
        text: shareIntent.text ?? '',
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        senderDeviceId: senderDeviceId,
        senderTransportPeerId: senderDeviceId,
        messageId: stableOperationKey,
        logicalDeliveryId: stableOperationKey,
        timestamp: forwardTimestamp,
        mediaAttachments: attachments.isEmpty ? null : attachments,
        mediaAttachmentRepo: mediaAttachmentRepository,
        inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepository,
        // Only an explicit internal Forward carries provenance; OS shares
        // and ordinary sends stay unmarked (TC-236-13).
        isForwarded: shareIntent.forwardProvenance != null,
        currentAuthorityCheck: () async {
          final currentAuthority = await _loadForwardGroupAuthority(
            groupRepo: groupRepo,
            groupId: resolvedGroup.id,
            senderPeerId: identity.peerId,
            allowAnnouncementTarget: allowAnnouncementTarget,
            sourceGroupIdToExclude: sourceGroupIdToExclude,
          );
          return currentAuthority != null &&
              _sameForwardGroupAuthority(uploadAuthority, currentAuthority);
        },
      );
      final pendingCompletion =
          result == SendGroupMessageResult.success &&
          message?.status == 'pending';

      return ShareBatchTargetResult(
        target: ShareTargetSelection.group(resolvedGroup),
        status: switch (result) {
          SendGroupMessageResult.success when pendingCompletion =>
            ShareBatchTargetStatus.queued,
          SendGroupMessageResult.success => ShareBatchTargetStatus.sent,
          SendGroupMessageResult.successNoPeers =>
            ShareBatchTargetStatus.queued,
          // 210b: durably queued while the sender is offline (self-healing).
          SendGroupMessageResult.queuedOffline => ShareBatchTargetStatus.queued,
          _ when message != null => ShareBatchTargetStatus.queued,
          _ => ShareBatchTargetStatus.failed,
        },
        detail: switch (result) {
          SendGroupMessageResult.success when pendingCompletion =>
            'Stored while group delivery finishes.',
          SendGroupMessageResult.success => 'Sent.',
          SendGroupMessageResult.successNoPeers =>
            'Stored for offline group delivery.',
          SendGroupMessageResult.queuedOffline => shareStoredOfflinePromise,
          SendGroupMessageResult.groupNotFound => 'Group was not found.',
          SendGroupMessageResult.unauthorized =>
            'You no longer have permission to post there.',
          SendGroupMessageResult.error when message != null =>
            'Saved for retry.',
          _ => 'Share failed.',
        },
      );
    } finally {
      await callBgEnd(bridge, bgTaskId);
    }
  }
}

class _ShareBatchProgressTracker {
  final int totalBytes;
  final ShareBatchDeliveryProgressCallback onProgress;

  String? _activeBlobId;
  int _activeBudgetBytes = 0;
  int _currentBytes = 0;
  int _completedBytes = 0;

  _ShareBatchProgressTracker({
    required this.totalBytes,
    required this.onProgress,
  });

  late final ShareBatchUploadHooks hooks = ShareBatchUploadHooks(
    onStarted: _onUploadStarted,
    onSettled: _onUploadSettled,
    onSending: _onSending,
  );

  void onUploadEvent(Map<String, dynamic> event) {
    final activeBlobId = _activeBlobId;
    if (activeBlobId == null || event['id'] != activeBlobId) {
      return;
    }
    final rawSentBytes = event['sentBytes'];
    if (rawSentBytes is! num) {
      return;
    }
    final clamped = rawSentBytes.toInt().clamp(0, _activeBudgetBytes).toInt();
    if (clamped <= _currentBytes) {
      return;
    }
    _currentBytes = clamped;
    _emit(ShareBatchDeliveryPhase.uploading);
  }

  void _onUploadStarted({required String blobId, required int budgetBytes}) {
    if (_activeBlobId != null) {
      _onUploadSettled(succeeded: false);
    }
    _activeBlobId = blobId;
    _activeBudgetBytes = budgetBytes < 0 ? 0 : budgetBytes;
    _currentBytes = 0;
    _emit(ShareBatchDeliveryPhase.uploading);
  }

  void _onUploadSettled({required bool succeeded}) {
    if (_activeBlobId == null) {
      return;
    }
    final settledBytes = succeeded ? _activeBudgetBytes : _currentBytes;

    // Clear the active id before folding completion so a late synchronous
    // final event cannot be adopted or counted twice.
    _activeBlobId = null;
    _activeBudgetBytes = 0;
    _currentBytes = 0;
    _completedBytes = (_completedBytes + settledBytes)
        .clamp(0, totalBytes)
        .toInt();
    _emit(ShareBatchDeliveryPhase.uploading);
  }

  void _onSending() {
    _emit(ShareBatchDeliveryPhase.sending);
  }

  void _emit(ShareBatchDeliveryPhase phase) {
    final sentBytes = (_completedBytes + _currentBytes)
        .clamp(0, totalBytes)
        .toInt();
    try {
      onProgress(
        ShareBatchDeliveryProgress(
          sentBytes: sentBytes,
          totalBytes: totalBytes,
          phase: phase,
        ),
      );
    } catch (_) {
      // Progress observers are non-authoritative UI telemetry. A throwing
      // observer must never turn a target that already owns durable v111
      // authority into a picker-owned `failed` result and duplicate work.
    }
  }
}

String _mimeFromPath(String path) {
  final ext = path.split('.').last.toLowerCase();
  const map = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'mkv': 'video/x-matroska',
    'm4v': 'video/x-m4v',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
  };
  return map[ext] ?? 'application/octet-stream';
}
