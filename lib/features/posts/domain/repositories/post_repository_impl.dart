import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pending_child_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PostRepositoryImpl implements PostRepository {
  final Future<void> Function(Map<String, Object?> row) dbInsertPost;
  final Future<Map<String, Object?>?> Function(String postId) dbLoadPost;
  final Future<List<Map<String, Object?>>> Function() dbLoadPostsFeed;
  final Future<List<Map<String, Object?>>> Function(String nowIso)?
  dbLoadExpiredPosts;
  final Future<void> Function(String postId)? dbDeletePostCascade;
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertRecipientDelivery;
  final Future<List<Map<String, Object?>>> Function(String postId)
  dbLoadRecipientDeliveries;
  final Future<void> Function(Map<String, Object?> row)? dbUpsertPostPass;
  final Future<Map<String, Object?>?> Function(String passId)? dbLoadPostPass;
  final Future<List<Map<String, Object?>>> Function(String postId)?
  dbLoadPostPasses;
  final Future<int> Function(String postId)? dbCountPostPasses;
  final Future<List<Map<String, Object?>>> Function(List<String> postIds)?
  dbLoadPostPassCounts;
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
  final Future<List<Map<String, Object?>>> Function(List<String> postIds)?
  dbLoadPostMediaForPosts;
  final Future<void> Function(String mediaId, String localPath)?
  dbUpdatePostMediaLocalPath;
  final Future<void> Function(String mediaId, String downloadStatus)?
  dbUpdatePostMediaDownloadStatus;

  final StreamController<String> _postChangesController =
      StreamController<String>.broadcast();

  PostRepositoryImpl({
    required this.dbInsertPost,
    required this.dbLoadPost,
    required this.dbLoadPostsFeed,
    this.dbLoadExpiredPosts,
    this.dbDeletePostCascade,
    required this.dbUpsertRecipientDelivery,
    required this.dbLoadRecipientDeliveries,
    this.dbUpsertPostPass,
    this.dbLoadPostPass,
    this.dbLoadPostPasses,
    this.dbCountPostPasses,
    this.dbLoadPostPassCounts,
    this.dbUpsertPostOrigin,
    this.dbLoadPostOrigin,
    required this.dbMarkPostFocused,
    this.dbInsertPostComment,
    this.dbLoadPostComment,
    this.dbLoadPostComments,
    this.dbInsertPendingChildEvent,
    this.dbLoadPendingChildEvents,
    this.dbDeletePendingChildEvent,
    this.dbUpsertPostReaction,
    this.dbLoadPostReaction,
    this.dbLoadPostReactions,
    this.dbUpsertCommentReaction,
    this.dbLoadCommentReaction,
    this.dbLoadCommentReactions,
    this.dbUpsertPostMedia,
    this.dbLoadPostMedia,
    this.dbLoadPostMediaForPosts,
    this.dbUpdatePostMediaLocalPath,
    this.dbUpdatePostMediaDownloadStatus,
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
  Future<void> markFocused(String postId) async {
    await dbMarkPostFocused(postId);
    _postChangesController.add(postId);
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
