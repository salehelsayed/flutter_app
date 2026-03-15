import 'dart:async';

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

class InMemoryPostRepository implements PostRepository {
  final Map<String, PostModel> _posts = <String, PostModel>{};
  final Map<String, PostCommentModel> _commentsById =
      <String, PostCommentModel>{};
  final Map<String, List<PostCommentModel>> _commentsByPostId =
      <String, List<PostCommentModel>>{};
  final Map<String, PostReactionModel> _postReactionsById =
      <String, PostReactionModel>{};
  final Map<String, List<PostReactionModel>> _postReactionsByPostId =
      <String, List<PostReactionModel>>{};
  final Map<String, PostCommentReactionModel> _commentReactionsById =
      <String, PostCommentReactionModel>{};
  final Map<String, List<PostCommentReactionModel>>
  _commentReactionsByCommentId = <String, List<PostCommentReactionModel>>{};
  final Map<String, PostMediaAttachmentModel> _postMediaById =
      <String, PostMediaAttachmentModel>{};
  final Map<String, List<PostMediaAttachmentModel>> _postMediaByPostId =
      <String, List<PostMediaAttachmentModel>>{};
  final Map<String, List<PostRecipientDelivery>> _deliveries =
      <String, List<PostRecipientDelivery>>{};
  final Map<String, PostPassModel> _postPassesById = <String, PostPassModel>{};
  final Map<String, List<PostPassModel>> _postPassesByPostId =
      <String, List<PostPassModel>>{};
  final Map<String, PostOriginModel> _postOrigins = <String, PostOriginModel>{};
  final Map<String, PostPendingChildEvent> _pendingChildEventsById =
      <String, PostPendingChildEvent>{};
  final Map<String, List<PostPendingChildEvent>> _pendingChildEventsByPostId =
      <String, List<PostPendingChildEvent>>{};
  final StreamController<String> _changes =
      StreamController<String>.broadcast();

  @override
  Stream<String> get postChanges => _changes.stream;

  @override
  Future<void> savePost(PostModel post) async {
    _posts[post.id] = post;
    _changes.add(post.id);
  }

  @override
  Future<PostModel?> getPost(String postId) async {
    final post = _posts[postId];
    if (post == null) {
      return null;
    }
    return _decoratePost(post);
  }

  @override
  Future<bool> postExists(String postId) async => _posts.containsKey(postId);

  @override
  Future<List<PostModel>> loadFeed() async {
    final posts = _posts.values.map(_decoratePost).toList(growable: false)
      ..sort((a, b) {
        final visibleCompare = b.visibleAt.compareTo(a.visibleAt);
        if (visibleCompare != 0) {
          return visibleCompare;
        }
        final createdCompare = b.createdAt.compareTo(a.createdAt);
        if (createdCompare != 0) {
          return createdCompare;
        }
        return b.id.compareTo(a.id);
      });
    return posts;
  }

  @override
  Future<List<PostModel>> loadExpiredPosts(String nowIso) async {
    return _posts.values
        .where(
          (post) =>
              !post.keepAvailable && post.expiresAt.compareTo(nowIso) <= 0,
        )
        .toList(growable: false)
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  }

  @override
  Future<void> deletePostCascade(String postId) async {
    _posts.remove(postId);
    _commentsByPostId.remove(postId)?.forEach((comment) {
      _commentsById.remove(comment.id);
      _commentReactionsByCommentId.remove(comment.id)?.forEach((reaction) {
        _commentReactionsById.remove(reaction.reactionId);
      });
    });
    _postReactionsByPostId.remove(postId)?.forEach((reaction) {
      _postReactionsById.remove(reaction.reactionId);
    });
    _postMediaByPostId.remove(postId)?.forEach((attachment) {
      _postMediaById.remove(attachment.mediaId);
    });
    _deliveries.remove(postId);
    _postOrigins.remove(postId);
    _postPassesByPostId.remove(postId)?.forEach((pass) {
      _postPassesById.remove(pass.passId);
    });
    _pendingChildEventsByPostId.remove(postId)?.forEach((event) {
      _pendingChildEventsById.remove(event.eventId);
    });
    _changes.add(postId);
  }

  @override
  Future<void> saveComment(PostCommentModel comment) async {
    _commentsById[comment.id] = comment;
    final comments = _commentsByPostId.putIfAbsent(
      comment.postId,
      () => <PostCommentModel>[],
    );
    comments.removeWhere((existing) => existing.id == comment.id);
    comments.add(comment);
    comments.sort((a, b) {
      final timestampCompare = a.commentedAt.compareTo(b.commentedAt);
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      return a.id.compareTo(b.id);
    });
    _changes.add(comment.postId);
  }

  @override
  Future<List<PostCommentModel>> loadComments(String postId) async {
    return List<PostCommentModel>.from(_commentsByPostId[postId] ?? const []);
  }

  @override
  Future<bool> commentExists(String commentId) async =>
      _commentsById.containsKey(commentId);

  @override
  Future<void> savePostReaction(PostReactionModel reaction) async {
    _postReactionsById[reaction.reactionId] = reaction;
    final reactions = _postReactionsByPostId.putIfAbsent(
      reaction.postId,
      () => <PostReactionModel>[],
    );
    reactions.removeWhere(
      (existing) => existing.reactionId == reaction.reactionId,
    );
    reactions.add(reaction);
    reactions.sort((a, b) {
      final timestampCompare = a.reactedAt.compareTo(b.reactedAt);
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      return a.reactionId.compareTo(b.reactionId);
    });
    _changes.add(reaction.postId);
  }

  @override
  Future<PostReactionModel?> getPostReaction(String reactionId) async {
    return _postReactionsById[reactionId];
  }

  @override
  Future<List<PostReactionModel>> loadPostReactions(String postId) async {
    return List<PostReactionModel>.from(
      _postReactionsByPostId[postId] ?? const [],
    );
  }

  @override
  Future<void> saveCommentReaction(PostCommentReactionModel reaction) async {
    _commentReactionsById[reaction.reactionId] = reaction;
    final reactions = _commentReactionsByCommentId.putIfAbsent(
      reaction.commentId,
      () => <PostCommentReactionModel>[],
    );
    reactions.removeWhere(
      (existing) => existing.reactionId == reaction.reactionId,
    );
    reactions.add(reaction);
    reactions.sort((a, b) {
      final timestampCompare = a.reactedAt.compareTo(b.reactedAt);
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      return a.reactionId.compareTo(b.reactionId);
    });
    _changes.add(reaction.postId);
  }

  @override
  Future<PostCommentReactionModel?> getCommentReaction(
    String reactionId,
  ) async {
    return _commentReactionsById[reactionId];
  }

  @override
  Future<List<PostCommentReactionModel>> loadCommentReactions(
    String commentId,
  ) async {
    return List<PostCommentReactionModel>.from(
      _commentReactionsByCommentId[commentId] ?? const [],
    );
  }

  @override
  Future<void> savePostMediaAttachment(
    PostMediaAttachmentModel attachment,
  ) async {
    _postMediaById[attachment.mediaId] = attachment;
    final attachments = _postMediaByPostId.putIfAbsent(
      attachment.postId,
      () => <PostMediaAttachmentModel>[],
    );
    attachments.removeWhere(
      (existing) => existing.mediaId == attachment.mediaId,
    );
    attachments.add(attachment);
    attachments.sort((a, b) {
      final positionCompare = a.position.compareTo(b.position);
      if (positionCompare != 0) {
        return positionCompare;
      }
      final timestampCompare = a.createdAt.compareTo(b.createdAt);
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      return a.mediaId.compareTo(b.mediaId);
    });
    _changes.add(attachment.postId);
  }

  @override
  Future<List<PostMediaAttachmentModel>> loadPostMediaAttachments(
    String postId,
  ) async {
    return List<PostMediaAttachmentModel>.from(
      _postMediaByPostId[postId] ?? const [],
    );
  }

  @override
  Future<Map<String, List<PostMediaAttachmentModel>>>
  loadPostMediaAttachmentsForPosts(List<String> postIds) async {
    final result = <String, List<PostMediaAttachmentModel>>{};
    for (final postId in postIds) {
      final attachments = await loadPostMediaAttachments(postId);
      if (attachments.isNotEmpty) {
        result[postId] = attachments;
      }
    }
    return result;
  }

  @override
  Future<void> updatePostMediaLocalPath(
    String mediaId,
    String localPath,
  ) async {
    final attachment = _postMediaById[mediaId];
    if (attachment == null) {
      return;
    }
    await savePostMediaAttachment(
      attachment.copyWith(localPath: localPath, downloadStatus: 'done'),
    );
  }

  @override
  Future<void> updatePostMediaDownloadStatus(
    String mediaId,
    String downloadStatus,
  ) async {
    final attachment = _postMediaById[mediaId];
    if (attachment == null) {
      return;
    }
    await savePostMediaAttachment(
      attachment.copyWith(downloadStatus: downloadStatus),
    );
  }

  @override
  Future<void> stagePendingChildEvent(PostPendingChildEvent event) async {
    final previous = _pendingChildEventsById[event.eventId];
    if (previous != null) {
      _pendingChildEventsByPostId[previous.postId]?.removeWhere(
        (existing) => existing.eventId == event.eventId,
      );
    }
    _pendingChildEventsById[event.eventId] = event;
    final events = _pendingChildEventsByPostId.putIfAbsent(
      event.postId,
      () => <PostPendingChildEvent>[],
    );
    events.removeWhere((existing) => existing.eventId == event.eventId);
    events.add(event);
    events.sort((a, b) {
      final timestampCompare = a.createdAt.compareTo(b.createdAt);
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      return a.eventId.compareTo(b.eventId);
    });
  }

  @override
  Future<List<PostPendingChildEvent>> loadPendingChildEvents(
    String postId,
  ) async {
    return List<PostPendingChildEvent>.from(
      _pendingChildEventsByPostId[postId] ?? const [],
    );
  }

  @override
  Future<void> deletePendingChildEvent(String eventId) async {
    final event = _pendingChildEventsById.remove(eventId);
    if (event == null) {
      return;
    }
    final events = _pendingChildEventsByPostId[event.postId];
    events?.removeWhere((existing) => existing.eventId == eventId);
    if (events != null && events.isEmpty) {
      _pendingChildEventsByPostId.remove(event.postId);
    }
  }

  @override
  Future<void> saveRecipientDelivery(PostRecipientDelivery delivery) async {
    final deliveries = _deliveries.putIfAbsent(
      delivery.postId,
      () => <PostRecipientDelivery>[],
    );
    deliveries.removeWhere(
      (existing) => existing.recipientPeerId == delivery.recipientPeerId,
    );
    deliveries.add(delivery);
    _changes.add(delivery.postId);
  }

  @override
  Future<List<PostRecipientDelivery>> getRecipientDeliveries(
    String postId,
  ) async {
    return List<PostRecipientDelivery>.from(_deliveries[postId] ?? const []);
  }

  @override
  Future<void> savePostPass(PostPassModel pass) async {
    _postPassesById[pass.passId] = pass;
    final passes = _postPassesByPostId.putIfAbsent(
      pass.postId,
      () => <PostPassModel>[],
    );
    passes.removeWhere((existing) => existing.passId == pass.passId);
    passes.add(pass);
    passes.sort((a, b) {
      final timestampCompare = b.passedAt.compareTo(a.passedAt);
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      return b.passId.compareTo(a.passId);
    });
    _changes.add(pass.postId);
  }

  @override
  Future<bool> postPassExists(String passId) async =>
      _postPassesById.containsKey(passId);

  @override
  Future<List<PostPassModel>> loadPostPasses(String postId) async {
    return List<PostPassModel>.from(_postPassesByPostId[postId] ?? const []);
  }

  @override
  Future<int> loadPostPassCount(String postId) async {
    return (_postPassesByPostId[postId] ?? const <PostPassModel>[]).length;
  }

  @override
  Future<Map<String, int>> loadPostPassCounts(List<String> postIds) async {
    return <String, int>{
      for (final postId in postIds)
        postId: (_postPassesByPostId[postId] ?? const <PostPassModel>[]).length,
    };
  }

  @override
  Future<void> savePostOrigin(PostOriginModel origin) async {
    _postOrigins[origin.postId] = origin;
    _changes.add(origin.postId);
  }

  @override
  Future<PostOriginModel?> getPostOrigin(String postId) async {
    return _postOrigins[postId];
  }

  @override
  Future<void> markFocused(String postId) async {
    final post = _posts[postId];
    if (post == null) {
      return;
    }
    _posts[postId] = post.copyWith(isFocused: true);
    _changes.add(postId);
  }

  @override
  void dispose() {
    _changes.close();
  }

  PostModel _decoratePost(PostModel post) {
    final origin = _postOrigins[post.id];
    final passCount =
        (_postPassesByPostId[post.id] ?? const <PostPassModel>[]).length;
    return post.copyWith(
      passedByPeerId: origin?.passerPeerId,
      passedByUsername: origin?.passerUsername,
      passedAt: origin?.passCreatedAt,
      shareCount: passCount,
    );
  }
}
