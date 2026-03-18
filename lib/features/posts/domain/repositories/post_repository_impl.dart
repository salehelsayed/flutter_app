import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_job.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_upload_recovery_item.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pending_child_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PostRepositoryImpl implements PostRepository {
  final Future<void> Function(Map<String, Object?> row) dbInsertPost;
  final Future<Map<String, Object?>?> Function(String postId) dbLoadPost;
  final Future<List<Map<String, Object?>>> Function() dbLoadPostsFeed;
  final Future<List<Map<String, Object?>>> Function()?
  dbLoadRetryableOutgoingPosts;
  final Future<List<Map<String, Object?>>> Function(String nowIso)?
  dbLoadExpiredPosts;
  final Future<void> Function(String postId)? dbDeletePostCascade;
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertRecipientDelivery;
  final Future<List<Map<String, Object?>>> Function(String postId)
  dbLoadRecipientDeliveries;
  final Future<List<Map<String, Object?>>> Function(String passId)?
  dbLoadPostPassRecipientDeliveries;
  final Future<void> Function(Map<String, Object?> row)? dbUpsertPostPass;
  final Future<Map<String, Object?>?> Function(String passId)? dbLoadPostPass;
  final Future<List<Map<String, Object?>>> Function(String postId)?
  dbLoadPostPasses;
  final Future<List<Map<String, Object?>>> Function()?
  dbLoadRetryableOutgoingPostPasses;
  final Future<int> Function(String postId)? dbCountPostPasses;
  final Future<List<Map<String, Object?>>> Function(List<String> postIds)?
  dbLoadPostPassCounts;
  final Future<Map<String, int>> Function(
    List<String> postIds,
    String viewerPeerId,
  )?
  dbLoadViewerSharedToCountsForPosts;
  final Future<void> Function(Map<String, Object?> row)?
  dbUpsertRepostEngagementParticipant;
  final Future<List<Map<String, Object?>>> Function(String postId)?
  dbLoadRepostEngagementParticipants;
  final Future<void> Function(Map<String, Object?> row)?
  dbUpsertRepostHeartBaselinePeer;
  final Future<List<Map<String, Object?>>> Function(String postId)?
  dbLoadRepostHeartBaselinePeers;
  final Future<List<Map<String, Object?>>> Function(List<String> postIds)?
  dbLoadRepostHeartBaselinePeersForPosts;
  final Future<void> Function(Map<String, Object?> row)?
  dbInsertRepostProjectionState;
  final Future<Map<String, Object?>?> Function(String postId)?
  dbLoadRepostProjectionState;
  final Future<List<Map<String, Object?>>> Function(List<String> postIds)?
  dbLoadRepostProjectionStates;
  final Future<void> Function(Map<String, Object?> row)? dbUpsertPostOrigin;
  final Future<Map<String, Object?>?> Function(String postId)? dbLoadPostOrigin;
  final Future<void> Function(String postId) dbMarkPostFocused;
  final Future<void> Function(Map<String, Object?> row)? dbInsertPostComment;
  final Future<Map<String, Object?>?> Function(String commentId)?
  dbLoadPostComment;
  final Future<List<Map<String, Object?>>> Function(String postId)?
  dbLoadPostComments;
  final Future<void> Function(Map<String, Object?> row)?
  dbInsertPendingChildEvent;
  final Future<List<Map<String, Object?>>> Function(String postId)?
  dbLoadPendingChildEvents;
  final Future<void> Function(String eventId)? dbDeletePendingChildEvent;
  final Future<void> Function(Map<String, Object?> row)?
  dbUpsertFollowOnOutboxEvent;
  final Future<Map<String, Object?>?> Function(String eventId)?
  dbLoadFollowOnOutboxEvent;
  final Future<List<Map<String, Object?>>> Function()?
  dbLoadRetryableFollowOnOutboxEvents;
  final Future<void> Function(Map<String, Object?> row)?
  dbUpsertFollowOnOutboxRecipientDelivery;
  final Future<List<Map<String, Object?>>> Function(String eventId)?
  dbLoadFollowOnOutboxRecipientDeliveries;
  final Future<List<Map<String, Object?>>> Function(List<String> eventIds)?
  dbLoadRetryableFollowOnOutboxRecipientDeliveries;
  final Future<void> Function(Map<String, Object?> row)? dbUpsertPostReaction;
  final Future<Map<String, Object?>?> Function(String reactionId)?
  dbLoadPostReaction;
  final Future<List<Map<String, Object?>>> Function(String postId)?
  dbLoadPostReactions;
  final Future<void> Function(Map<String, Object?> row)?
  dbUpsertCommentReaction;
  final Future<Map<String, Object?>?> Function(String reactionId)?
  dbLoadCommentReaction;
  final Future<List<Map<String, Object?>>> Function(String commentId)?
  dbLoadCommentReactions;
  final Future<void> Function(Map<String, Object?> row)? dbUpsertPostMedia;
  final Future<List<Map<String, Object?>>> Function(String postId)?
  dbLoadPostMedia;
  final Future<void> Function(String postId, List<Map<String, Object?>> rows)?
  dbReplacePostMediaUploadRecoveryItems;
  final Future<List<Map<String, Object?>>> Function(String postId)?
  dbLoadPostMediaUploadRecoveryItems;
  final Future<List<Map<String, Object?>>> Function()?
  dbLoadPendingMediaUploadPosts;
  final Future<List<Map<String, Object?>>> Function(List<String> postIds)?
  dbLoadPostMediaForPosts;
  final Future<void> Function(String mediaId, String localPath)?
  dbUpdatePostMediaLocalPath;
  final Future<void> Function(String mediaId, String downloadStatus)?
  dbUpdatePostMediaDownloadStatus;
  final Future<void> Function(String postId, List<Map<String, Object?>> rows)?
  dbReplacePostMedia;
  final Future<void> Function(Map<String, Object?> row)? dbUpsertPostPinState;
  final Future<Map<String, Object?>?> Function(String postId)?
  dbLoadPostPinState;
  final Future<List<Map<String, Object?>>> Function()?
  dbLoadActivePostPinStates;
  final Future<void> Function(Map<String, Object?> row)? dbUpsertPinDismissal;
  final Future<List<Map<String, Object?>>> Function()? dbLoadPinDismissals;
  final Future<void> Function(String postId)? dbDeletePinDismissal;
  final Future<void> Function(
    String postId,
    String authorPeerId,
    List<int> avatarBlob,
    String createdAt,
  )?
  dbSavePassAvatarSnapshot;
  final Future<List<int>?> Function(String postId)? dbLoadPassAvatarSnapshot;
  final Future<Map<String, List<int>>> Function(List<String> postIds)?
  dbLoadPassAvatarSnapshotsForPosts;

  final StreamController<String> _postChangesController =
      StreamController<String>.broadcast();

  PostRepositoryImpl({
    required this.dbInsertPost,
    required this.dbLoadPost,
    required this.dbLoadPostsFeed,
    this.dbLoadRetryableOutgoingPosts,
    this.dbLoadExpiredPosts,
    this.dbDeletePostCascade,
    required this.dbUpsertRecipientDelivery,
    required this.dbLoadRecipientDeliveries,
    this.dbLoadPostPassRecipientDeliveries,
    this.dbUpsertPostPass,
    this.dbLoadPostPass,
    this.dbLoadPostPasses,
    this.dbLoadRetryableOutgoingPostPasses,
    this.dbCountPostPasses,
    this.dbLoadPostPassCounts,
    this.dbLoadViewerSharedToCountsForPosts,
    this.dbUpsertRepostEngagementParticipant,
    this.dbLoadRepostEngagementParticipants,
    this.dbUpsertRepostHeartBaselinePeer,
    this.dbLoadRepostHeartBaselinePeers,
    this.dbLoadRepostHeartBaselinePeersForPosts,
    this.dbInsertRepostProjectionState,
    this.dbLoadRepostProjectionState,
    this.dbLoadRepostProjectionStates,
    this.dbUpsertPostOrigin,
    this.dbLoadPostOrigin,
    required this.dbMarkPostFocused,
    this.dbInsertPostComment,
    this.dbLoadPostComment,
    this.dbLoadPostComments,
    this.dbInsertPendingChildEvent,
    this.dbLoadPendingChildEvents,
    this.dbDeletePendingChildEvent,
    this.dbUpsertFollowOnOutboxEvent,
    this.dbLoadFollowOnOutboxEvent,
    this.dbLoadRetryableFollowOnOutboxEvents,
    this.dbUpsertFollowOnOutboxRecipientDelivery,
    this.dbLoadFollowOnOutboxRecipientDeliveries,
    this.dbLoadRetryableFollowOnOutboxRecipientDeliveries,
    this.dbUpsertPostReaction,
    this.dbLoadPostReaction,
    this.dbLoadPostReactions,
    this.dbUpsertCommentReaction,
    this.dbLoadCommentReaction,
    this.dbLoadCommentReactions,
    this.dbUpsertPostMedia,
    this.dbLoadPostMedia,
    this.dbReplacePostMediaUploadRecoveryItems,
    this.dbLoadPostMediaUploadRecoveryItems,
    this.dbLoadPendingMediaUploadPosts,
    this.dbLoadPostMediaForPosts,
    this.dbUpdatePostMediaLocalPath,
    this.dbUpdatePostMediaDownloadStatus,
    this.dbReplacePostMedia,
    this.dbUpsertPostPinState,
    this.dbLoadPostPinState,
    this.dbLoadActivePostPinStates,
    this.dbUpsertPinDismissal,
    this.dbLoadPinDismissals,
    this.dbDeletePinDismissal,
    this.dbSavePassAvatarSnapshot,
    this.dbLoadPassAvatarSnapshot,
    this.dbLoadPassAvatarSnapshotsForPosts,
  });

  @override
  Stream<String> get postChanges => _postChangesController.stream;

  @override
  Future<void> savePost(PostModel post) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_REPO_SAVE_START',
      details: {'postId': post.id},
    );
    await dbInsertPost(post.toMap());
    _postChangesController.add(post.id);
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_REPO_SAVE_SUCCESS',
      details: {'postId': post.id},
    );
  }

  @override
  Future<PostModel?> getPost(String postId) async {
    final row = await dbLoadPost(postId);
    return row == null ? null : PostModel.fromMap(row);
  }

  @override
  Future<bool> postExists(String postId) async {
    final row = await dbLoadPost(postId);
    return row != null;
  }

  @override
  Future<List<PostModel>> loadFeed() async {
    final rows = await dbLoadPostsFeed();
    return rows.map(PostModel.fromMap).toList(growable: false);
  }

  @override
  Future<List<PostModel>> loadRetryableOutgoingPosts() async {
    final dbLoad = dbLoadRetryableOutgoingPosts;
    if (dbLoad == null) {
      final rows = await dbLoadPostsFeed();
      return rows
          .map(PostModel.fromMap)
          .where(
            (post) =>
                !post.isIncoming &&
                (post.deliveryStatus == 'sending' ||
                    post.deliveryStatus == 'partial' ||
                    post.deliveryStatus == 'failed'),
          )
          .toList(growable: false);
    }
    final rows = await dbLoad();
    return rows.map(PostModel.fromMap).toList(growable: false);
  }

  @override
  Future<List<PostModel>> loadExpiredPosts(String nowIso) async {
    final dbLoad = _require(
      dbLoadExpiredPosts,
      'Expired-post loading is not configured for this repository.',
    );
    final rows = await dbLoad(nowIso);
    return rows.map(PostModel.fromMap).toList(growable: false);
  }

  @override
  Future<void> deletePostCascade(String postId) async {
    final dbDelete = _require(
      dbDeletePostCascade,
      'Expired-post cleanup is not configured for this repository.',
    );
    await dbDelete(postId);
    _postChangesController.add(postId);
  }

  @override
  Future<void> saveComment(PostCommentModel comment) async {
    final dbInsert = _require(
      dbInsertPostComment,
      'Posts comment persistence is not configured for this repository.',
    );
    await dbInsert(comment.toMap());
    _postChangesController.add(comment.postId);
  }

  @override
  Future<List<PostCommentModel>> loadComments(String postId) async {
    final dbLoad = _require(
      dbLoadPostComments,
      'Posts comments are not configured for this repository.',
    );
    final rows = await dbLoad(postId);
    return rows.map(PostCommentModel.fromMap).toList(growable: false);
  }

  @override
  Future<bool> commentExists(String commentId) async {
    final dbLoad = _require(
      dbLoadPostComment,
      'Posts comment lookup is not configured for this repository.',
    );
    return await dbLoad(commentId) != null;
  }

  @override
  Future<void> savePostReaction(PostReactionModel reaction) async {
    final dbUpsert = _require(
      dbUpsertPostReaction,
      'Posts reactions are not configured for this repository.',
    );
    await dbUpsert(reaction.toMap());
    _postChangesController.add(reaction.postId);
  }

  @override
  Future<PostReactionModel?> getPostReaction(String reactionId) async {
    final dbLoad = _require(
      dbLoadPostReaction,
      'Posts reactions are not configured for this repository.',
    );
    final row = await dbLoad(reactionId);
    return row == null ? null : PostReactionModel.fromMap(row);
  }

  @override
  Future<List<PostReactionModel>> loadPostReactions(String postId) async {
    final dbLoad = _require(
      dbLoadPostReactions,
      'Posts reactions are not configured for this repository.',
    );
    final rows = await dbLoad(postId);
    return rows.map(PostReactionModel.fromMap).toList(growable: false);
  }

  @override
  Future<void> saveCommentReaction(PostCommentReactionModel reaction) async {
    final dbUpsert = _require(
      dbUpsertCommentReaction,
      'Post comment reactions are not configured for this repository.',
    );
    await dbUpsert(reaction.toMap());
    _postChangesController.add(reaction.postId);
  }

  @override
  Future<PostCommentReactionModel?> getCommentReaction(
    String reactionId,
  ) async {
    final dbLoad = _require(
      dbLoadCommentReaction,
      'Post comment reactions are not configured for this repository.',
    );
    final row = await dbLoad(reactionId);
    return row == null ? null : PostCommentReactionModel.fromMap(row);
  }

  @override
  Future<List<PostCommentReactionModel>> loadCommentReactions(
    String commentId,
  ) async {
    final dbLoad = _require(
      dbLoadCommentReactions,
      'Post comment reactions are not configured for this repository.',
    );
    final rows = await dbLoad(commentId);
    return rows.map(PostCommentReactionModel.fromMap).toList(growable: false);
  }

  @override
  Future<void> savePostMediaAttachment(
    PostMediaAttachmentModel attachment,
  ) async {
    final dbUpsert = _require(
      dbUpsertPostMedia,
      'Post media is not configured for this repository.',
    );
    await dbUpsert(attachment.toMap());
    _postChangesController.add(attachment.postId);
  }

  @override
  Future<void> replacePostMediaAttachments(
    String postId,
    List<PostMediaAttachmentModel> attachments,
  ) async {
    final dbReplace = _require(
      dbReplacePostMedia,
      'Post media replacement is not configured for this repository.',
    );
    await dbReplace(
      postId,
      attachments
          .map((attachment) => attachment.toMap())
          .toList(growable: false),
    );
    _postChangesController.add(postId);
  }

  @override
  Future<List<PostMediaAttachmentModel>> loadPostMediaAttachments(
    String postId,
  ) async {
    final dbLoad = _require(
      dbLoadPostMedia,
      'Post media is not configured for this repository.',
    );
    final rows = await dbLoad(postId);
    return rows.map(PostMediaAttachmentModel.fromMap).toList(growable: false);
  }

  @override
  Future<void> replacePostMediaUploadRecoveryItems(
    String postId,
    List<PostMediaUploadRecoveryItem> items,
  ) async {
    final dbReplace = _require(
      dbReplacePostMediaUploadRecoveryItems,
      'Post media upload recovery is not configured for this repository.',
    );
    await dbReplace(
      postId,
      items.map((item) => item.toMap()).toList(growable: false),
    );
    _postChangesController.add(postId);
  }

  @override
  Future<List<PostMediaUploadRecoveryItem>> loadPostMediaUploadRecoveryItems(
    String postId,
  ) async {
    final dbLoad = _require(
      dbLoadPostMediaUploadRecoveryItems,
      'Post media upload recovery is not configured for this repository.',
    );
    final rows = await dbLoad(postId);
    return rows
        .map(PostMediaUploadRecoveryItem.fromMap)
        .toList(growable: false);
  }

  @override
  Future<List<PostModel>> loadPendingMediaUploadPosts() async {
    final dbLoad = _require(
      dbLoadPendingMediaUploadPosts,
      'Pending media-upload post loading is not configured for this repository.',
    );
    final rows = await dbLoad();
    return rows.map(PostModel.fromMap).toList(growable: false);
  }

  @override
  Future<Map<String, List<PostMediaAttachmentModel>>>
  loadPostMediaAttachmentsForPosts(List<String> postIds) async {
    if (postIds.isEmpty) {
      return const <String, List<PostMediaAttachmentModel>>{};
    }
    final dbLoad = _require(
      dbLoadPostMediaForPosts,
      'Post media is not configured for this repository.',
    );
    final rows = await dbLoad(postIds);
    final result = <String, List<PostMediaAttachmentModel>>{};
    for (final row in rows) {
      final attachment = PostMediaAttachmentModel.fromMap(row);
      result.putIfAbsent(attachment.postId, () => <PostMediaAttachmentModel>[]);
      result[attachment.postId]!.add(attachment);
    }
    for (final entry in result.entries) {
      entry.value.sort((a, b) {
        final positionCompare = a.position.compareTo(b.position);
        if (positionCompare != 0) {
          return positionCompare;
        }
        return a.createdAt.compareTo(b.createdAt);
      });
    }
    return result;
  }

  @override
  Future<void> updatePostMediaLocalPath(
    String mediaId,
    String localPath,
  ) async {
    final dbUpdate = _require(
      dbUpdatePostMediaLocalPath,
      'Post media local-path updates are not configured for this repository.',
    );
    await dbUpdate(mediaId, localPath);
  }

  @override
  Future<void> updatePostMediaDownloadStatus(
    String mediaId,
    String downloadStatus,
  ) async {
    final dbUpdate = _require(
      dbUpdatePostMediaDownloadStatus,
      'Post media status updates are not configured for this repository.',
    );
    await dbUpdate(mediaId, downloadStatus);
  }

  @override
  Future<void> stagePendingChildEvent(PostPendingChildEvent event) async {
    final dbInsert = _require(
      dbInsertPendingChildEvent,
      'Posts orphan-event staging is not configured for this repository.',
    );
    await dbInsert(event.toMap());
  }

  @override
  Future<List<PostPendingChildEvent>> loadPendingChildEvents(
    String postId,
  ) async {
    final dbLoad = _require(
      dbLoadPendingChildEvents,
      'Posts orphan-event staging is not configured for this repository.',
    );
    final rows = await dbLoad(postId);
    return rows.map(PostPendingChildEvent.fromMap).toList(growable: false);
  }

  @override
  Future<void> deletePendingChildEvent(String eventId) async {
    final dbDelete = _require(
      dbDeletePendingChildEvent,
      'Posts orphan-event staging is not configured for this repository.',
    );
    await dbDelete(eventId);
  }

  @override
  Future<void> saveFollowOnOutboxEvent(PostFollowOnOutboxEvent event) async {
    final dbUpsert = _require(
      dbUpsertFollowOnOutboxEvent,
      'Posts follow-on outbox is not configured for this repository.',
    );
    await dbUpsert(event.toMap());
  }

  @override
  Future<PostFollowOnOutboxEvent?> getFollowOnOutboxEvent(
    String eventId,
  ) async {
    final dbLoad = _require(
      dbLoadFollowOnOutboxEvent,
      'Posts follow-on outbox is not configured for this repository.',
    );
    final row = await dbLoad(eventId);
    return row == null ? null : PostFollowOnOutboxEvent.fromMap(row);
  }

  @override
  Future<void> saveFollowOnOutboxRecipientDelivery(
    PostFollowOnOutboxRecipientDelivery delivery,
  ) async {
    final dbUpsert = _require(
      dbUpsertFollowOnOutboxRecipientDelivery,
      'Posts follow-on outbox is not configured for this repository.',
    );
    await dbUpsert(delivery.toMap());
  }

  @override
  Future<List<PostFollowOnOutboxRecipientDelivery>>
  loadFollowOnOutboxRecipientDeliveries(String eventId) async {
    final dbLoad = _require(
      dbLoadFollowOnOutboxRecipientDeliveries,
      'Posts follow-on outbox is not configured for this repository.',
    );
    final rows = await dbLoad(eventId);
    return rows
        .map(PostFollowOnOutboxRecipientDelivery.fromMap)
        .toList(growable: false);
  }

  @override
  Future<List<PostFollowOnOutboxJob>> loadRetryableFollowOnOutboxJobs() async {
    final dbLoadEvents = _require(
      dbLoadRetryableFollowOnOutboxEvents,
      'Posts follow-on outbox is not configured for this repository.',
    );
    final eventRows = await dbLoadEvents();
    if (eventRows.isEmpty) {
      return const <PostFollowOnOutboxJob>[];
    }

    final events = eventRows
        .map(PostFollowOnOutboxEvent.fromMap)
        .toList(growable: false);
    final dbLoadDeliveries = _require(
      dbLoadRetryableFollowOnOutboxRecipientDeliveries,
      'Posts follow-on outbox is not configured for this repository.',
    );
    final deliveryRows = await dbLoadDeliveries(
      events.map((event) => event.eventId).toList(growable: false),
    );
    final deliveriesByEventId =
        <String, List<PostFollowOnOutboxRecipientDelivery>>{};
    for (final row in deliveryRows) {
      final delivery = PostFollowOnOutboxRecipientDelivery.fromMap(row);
      deliveriesByEventId.putIfAbsent(
        delivery.eventId,
        () => <PostFollowOnOutboxRecipientDelivery>[],
      );
      deliveriesByEventId[delivery.eventId]!.add(delivery);
    }

    return events
        .map(
          (event) => PostFollowOnOutboxJob(
            event: event,
            recipientDeliveries: deliveriesByEventId[event.eventId] ?? const [],
          ),
        )
        .where((job) => job.recipientDeliveries.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> saveRecipientDelivery(PostRecipientDelivery delivery) async {
    await dbUpsertRecipientDelivery(delivery.toMap());
    _postChangesController.add(delivery.postId);
  }

  @override
  Future<List<PostRecipientDelivery>> getRecipientDeliveries(
    String postId,
  ) async {
    final rows = await dbLoadRecipientDeliveries(postId);
    return rows.map(PostRecipientDelivery.fromMap).toList(growable: false);
  }

  @override
  Future<List<PostRecipientDelivery>> getPostPassRecipientDeliveries(
    String passId,
  ) async {
    final dbLoad = _require(
      dbLoadPostPassRecipientDeliveries,
      'Post pass recipient deliveries are not configured for this repository.',
    );
    final rows = await dbLoad(passId);
    return rows.map(PostRecipientDelivery.fromMap).toList(growable: false);
  }

  @override
  Future<void> savePostPass(PostPassModel pass) async {
    final dbUpsert = _require(
      dbUpsertPostPass,
      'Post passes are not configured for this repository.',
    );
    await dbUpsert(pass.toMap());
    _postChangesController.add(pass.postId);
  }

  @override
  Future<bool> postPassExists(String passId) async {
    final dbLoad = _require(
      dbLoadPostPass,
      'Post passes are not configured for this repository.',
    );
    return await dbLoad(passId) != null;
  }

  @override
  Future<List<PostPassModel>> loadRetryableOutgoingPostPasses() async {
    final dbLoad = _require(
      dbLoadRetryableOutgoingPostPasses,
      'Retryable outgoing post-pass loading is not configured for this repository.',
    );
    final rows = await dbLoad();
    return rows.map(PostPassModel.fromMap).toList(growable: false);
  }

  @override
  Future<List<PostPassModel>> loadPostPasses(String postId) async {
    final dbLoad = _require(
      dbLoadPostPasses,
      'Post passes are not configured for this repository.',
    );
    final rows = await dbLoad(postId);
    return rows.map(PostPassModel.fromMap).toList(growable: false);
  }

  @override
  Future<int> loadPostPassCount(String postId) async {
    final dbCount = _require(
      dbCountPostPasses,
      'Post passes are not configured for this repository.',
    );
    return dbCount(postId);
  }

  @override
  Future<Map<String, int>> loadPostPassCounts(List<String> postIds) async {
    if (postIds.isEmpty) {
      return const <String, int>{};
    }
    final dbLoad = _require(
      dbLoadPostPassCounts,
      'Post passes are not configured for this repository.',
    );
    final rows = await dbLoad(postIds);
    return <String, int>{
      for (final row in rows)
        row['post_id'] as String: ((row['share_count'] as num?)?.toInt() ?? 0),
    };
  }

  @override
  Future<Map<String, int>> loadViewerSharedToCountsForPosts(
    List<String> postIds,
    String viewerPeerId,
  ) async {
    if (postIds.isEmpty || viewerPeerId.isEmpty) {
      return const <String, int>{};
    }
    final dbLoad = dbLoadViewerSharedToCountsForPosts;
    if (dbLoad != null) {
      return dbLoad(postIds, viewerPeerId);
    }

    final results = <String, int>{};
    for (final postId in postIds) {
      final passes = await loadPostPasses(postId);
      var viewerSharedToCount = 0;
      for (final pass in passes) {
        if (pass.isIncoming || pass.senderPeerId != viewerPeerId) {
          continue;
        }
        viewerSharedToCount += pass.recipientCount ?? 1;
      }
      if (viewerSharedToCount > 0) {
        results[postId] = viewerSharedToCount;
      }
    }
    return results;
  }

  @override
  Future<void> saveRepostEngagementParticipant({
    required String postId,
    required String participantPeerId,
    required String createdAt,
  }) async {
    final dbUpsert = _require(
      dbUpsertRepostEngagementParticipant,
      'Repost engagement participants are not configured for this repository.',
    );
    await dbUpsert(<String, Object?>{
      'post_id': postId,
      'participant_peer_id': participantPeerId,
      'created_at': createdAt,
    });
    _postChangesController.add(postId);
  }

  @override
  Future<Set<String>> loadRepostEngagementParticipantPeerIds(
    String postId,
  ) async {
    final dbLoad = _require(
      dbLoadRepostEngagementParticipants,
      'Repost engagement participants are not configured for this repository.',
    );
    final rows = await dbLoad(postId);
    return rows
        .map((row) => row['participant_peer_id'] as String?)
        .whereType<String>()
        .where((peerId) => peerId.isNotEmpty)
        .toSet();
  }

  @override
  Future<void> saveRepostHeartBaselinePeerIds({
    required String postId,
    required Iterable<String> peerIds,
    required String createdAt,
  }) async {
    final dbUpsert = _require(
      dbUpsertRepostHeartBaselinePeer,
      'Repost heart baselines are not configured for this repository.',
    );
    final sortedPeerIds =
        peerIds
            .where((peerId) => peerId.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    for (final peerId in sortedPeerIds) {
      await dbUpsert(<String, Object?>{
        'post_id': postId,
        'sender_peer_id': peerId,
        'created_at': createdAt,
      });
    }
    _postChangesController.add(postId);
  }

  @override
  Future<Set<String>> loadRepostHeartBaselinePeerIds(String postId) async {
    final dbLoad = _require(
      dbLoadRepostHeartBaselinePeers,
      'Repost heart baselines are not configured for this repository.',
    );
    final rows = await dbLoad(postId);
    return rows
        .map((row) => row['sender_peer_id'] as String?)
        .whereType<String>()
        .where((peerId) => peerId.isNotEmpty)
        .toSet();
  }

  @override
  Future<Map<String, Set<String>>> loadRepostHeartBaselinePeerIdsForPosts(
    List<String> postIds,
  ) async {
    if (postIds.isEmpty) {
      return const <String, Set<String>>{};
    }
    final dbLoad = _require(
      dbLoadRepostHeartBaselinePeersForPosts,
      'Repost heart baselines are not configured for this repository.',
    );
    final rows = await dbLoad(postIds);
    final results = <String, Set<String>>{};
    for (final row in rows) {
      final postId = row['post_id'] as String?;
      final senderPeerId = row['sender_peer_id'] as String?;
      if (postId == null || senderPeerId == null || senderPeerId.isEmpty) {
        continue;
      }
      results.putIfAbsent(postId, () => <String>{}).add(senderPeerId);
    }
    return results;
  }

  @override
  Future<void> seedRepostTotalBaseline({
    required String postId,
    required int repostTotalBaseline,
    required int existingLocalPassCount,
    required String createdAt,
  }) async {
    final dbInsert = _require(
      dbInsertRepostProjectionState,
      'Repost projection state is not configured for this repository.',
    );
    final dbLoad = _require(
      dbLoadRepostProjectionState,
      'Repost projection state is not configured for this repository.',
    );
    final expectedVisibleShareCount = repostTotalBaseline + 1;
    final baselineDelta = expectedVisibleShareCount > existingLocalPassCount
        ? expectedVisibleShareCount - existingLocalPassCount
        : 0;
    final existingRow = await dbLoad(postId);
    final existingBaseline =
        (existingRow?['repost_total_baseline'] as num?)?.toInt() ?? 0;
    final existingSharedToBaseline =
        (existingRow?['shared_to_count_baseline'] as num?)?.toInt() ?? 0;
    if (baselineDelta <= existingBaseline) {
      return;
    }
    await dbInsert(<String, Object?>{
      'post_id': postId,
      'repost_total_baseline': baselineDelta,
      'shared_to_count_baseline': existingSharedToBaseline,
      'created_at': createdAt,
    });
    _postChangesController.add(postId);
  }

  @override
  Future<int> loadRepostTotalBaseline(String postId) async {
    final dbLoad = _require(
      dbLoadRepostProjectionState,
      'Repost projection state is not configured for this repository.',
    );
    final row = await dbLoad(postId);
    return (row?['repost_total_baseline'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<Map<String, int>> loadRepostTotalBaselines(
    List<String> postIds,
  ) async {
    if (postIds.isEmpty) {
      return const <String, int>{};
    }
    final dbLoad = _require(
      dbLoadRepostProjectionStates,
      'Repost projection state is not configured for this repository.',
    );
    final rows = await dbLoad(postIds);
    return <String, int>{
      for (final row in rows)
        if (row['post_id'] is String)
          row['post_id'] as String:
              ((row['repost_total_baseline'] as num?)?.toInt() ?? 0),
    };
  }

  @override
  Future<void> seedRepostSharedToBaseline({
    required String postId,
    required int sharedToCountBaseline,
    required int existingLocalSharedToCount,
    required int currentPassRecipientCount,
    required String createdAt,
  }) async {
    final dbInsert = _require(
      dbInsertRepostProjectionState,
      'Repost projection state is not configured for this repository.',
    );
    final dbLoad = _require(
      dbLoadRepostProjectionState,
      'Repost projection state is not configured for this repository.',
    );
    final expectedVisibleSharedToCount =
        sharedToCountBaseline + currentPassRecipientCount;
    final baselineDelta =
        expectedVisibleSharedToCount > existingLocalSharedToCount
        ? expectedVisibleSharedToCount - existingLocalSharedToCount
        : 0;
    final existingRow = await dbLoad(postId);
    final existingEventBaseline =
        (existingRow?['repost_total_baseline'] as num?)?.toInt() ?? 0;
    final existingSharedToBaseline =
        (existingRow?['shared_to_count_baseline'] as num?)?.toInt() ?? 0;
    if (baselineDelta <= existingSharedToBaseline) {
      return;
    }
    await dbInsert(<String, Object?>{
      'post_id': postId,
      'repost_total_baseline': existingEventBaseline,
      'shared_to_count_baseline': baselineDelta,
      'created_at': createdAt,
    });
    _postChangesController.add(postId);
  }

  @override
  Future<int> loadRepostSharedToBaseline(String postId) async {
    final dbLoad = _require(
      dbLoadRepostProjectionState,
      'Repost projection state is not configured for this repository.',
    );
    final row = await dbLoad(postId);
    final sharedToBaseline =
        (row?['shared_to_count_baseline'] as num?)?.toInt() ?? 0;
    if (sharedToBaseline > 0) {
      return sharedToBaseline;
    }
    return (row?['repost_total_baseline'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<Map<String, int>> loadRepostSharedToBaselines(
    List<String> postIds,
  ) async {
    if (postIds.isEmpty) {
      return const <String, int>{};
    }
    final dbLoad = _require(
      dbLoadRepostProjectionStates,
      'Repost projection state is not configured for this repository.',
    );
    final rows = await dbLoad(postIds);
    return <String, int>{
      for (final row in rows)
        if (row['post_id'] is String)
          row['post_id'] as String: () {
            final sharedToBaseline =
                (row['shared_to_count_baseline'] as num?)?.toInt() ?? 0;
            if (sharedToBaseline > 0) {
              return sharedToBaseline;
            }
            return (row['repost_total_baseline'] as num?)?.toInt() ?? 0;
          }(),
    };
  }

  @override
  Future<void> savePostOrigin(PostOriginModel origin) async {
    final dbUpsert = _require(
      dbUpsertPostOrigin,
      'Post origin metadata is not configured for this repository.',
    );
    await dbUpsert(origin.toMap());
    _postChangesController.add(origin.postId);
  }

  @override
  Future<PostOriginModel?> getPostOrigin(String postId) async {
    final dbLoad = _require(
      dbLoadPostOrigin,
      'Post origin metadata is not configured for this repository.',
    );
    final row = await dbLoad(postId);
    return row == null ? null : PostOriginModel.fromMap(row);
  }

  @override
  Future<void> savePostPinState(PostPinStateModel pinState) async {
    final dbUpsert = _require(
      dbUpsertPostPinState,
      'Post pins are not configured for this repository.',
    );
    await dbUpsert(pinState.toMap());
    _postChangesController.add(pinState.postId);
  }

  @override
  Future<PostPinStateModel?> getPostPinState(String postId) async {
    final dbLoad = _require(
      dbLoadPostPinState,
      'Post pins are not configured for this repository.',
    );
    final row = await dbLoad(postId);
    return row == null ? null : PostPinStateModel.fromMap(row);
  }

  @override
  Future<List<PostPinStateModel>> loadActivePinStates() async {
    final dbLoad = _require(
      dbLoadActivePostPinStates,
      'Post pins are not configured for this repository.',
    );
    final rows = await dbLoad();
    return rows.map(PostPinStateModel.fromMap).toList(growable: false);
  }

  @override
  Future<void> savePinDismissal(String postId, String dismissedAt) async {
    final dbUpsert = _require(
      dbUpsertPinDismissal,
      'Pin dismissals are not configured for this repository.',
    );
    await dbUpsert(<String, Object?>{
      'post_id': postId,
      'dismissed_at': dismissedAt,
    });
    _postChangesController.add(postId);
  }

  @override
  Future<Set<String>> loadDismissedPinPostIds() async {
    final dbLoad = _require(
      dbLoadPinDismissals,
      'Pin dismissals are not configured for this repository.',
    );
    final rows = await dbLoad();
    return rows.map((row) => row['post_id'] as String).toSet();
  }

  @override
  Future<void> clearPinDismissal(String postId) async {
    final dbDelete = _require(
      dbDeletePinDismissal,
      'Pin dismissals are not configured for this repository.',
    );
    await dbDelete(postId);
    _postChangesController.add(postId);
  }

  @override
  Future<void> markFocused(String postId) async {
    await dbMarkPostFocused(postId);
    _postChangesController.add(postId);
  }

  @override
  Future<void> savePassAvatarSnapshot({
    required String postId,
    required String authorPeerId,
    required List<int> avatarBlob,
    required String createdAt,
  }) async {
    final dbSave = _require(
      dbSavePassAvatarSnapshot,
      'Pass avatar snapshots are not configured for this repository.',
    );
    await dbSave(postId, authorPeerId, avatarBlob, createdAt);
  }

  @override
  Future<List<int>?> loadPassAvatarSnapshot(String postId) async {
    final dbLoad = _require(
      dbLoadPassAvatarSnapshot,
      'Pass avatar snapshots are not configured for this repository.',
    );
    return dbLoad(postId);
  }

  @override
  Future<Map<String, List<int>>> loadPassAvatarSnapshotsForPosts(
    List<String> postIds,
  ) async {
    if (postIds.isEmpty) {
      return const <String, List<int>>{};
    }
    final dbLoad = _require(
      dbLoadPassAvatarSnapshotsForPosts,
      'Pass avatar snapshots are not configured for this repository.',
    );
    return dbLoad(postIds);
  }

  @override
  void dispose() {
    _postChangesController.close();
  }

  T _require<T>(T? value, String message) {
    if (value == null) {
      throw UnsupportedError(message);
    }
    return value;
  }
}
