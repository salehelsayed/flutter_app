import 'dart:async';

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
  final Map<String, List<PostMediaUploadRecoveryItem>>
  _postMediaUploadRecoveryByPostId =
      <String, List<PostMediaUploadRecoveryItem>>{};
  final Map<String, List<PostRecipientDelivery>> _deliveriesByOwner =
      <String, List<PostRecipientDelivery>>{};
  final Map<String, PostPassModel> _postPassesById = <String, PostPassModel>{};
  final Map<String, List<PostPassModel>> _postPassesByPostId =
      <String, List<PostPassModel>>{};
  final Map<String, Set<String>> _repostEngagementParticipantsByPostId =
      <String, Set<String>>{};
  final Map<String, Set<String>> _repostHeartBaselinePeersByPostId =
      <String, Set<String>>{};
  final Map<String, int> _repostTotalBaselinesByPostId = <String, int>{};
  final Map<String, int> _repostSharedToBaselinesByPostId = <String, int>{};
  final Map<String, PostOriginModel> _postOrigins = <String, PostOriginModel>{};
  final Map<String, PostPendingChildEvent> _pendingChildEventsById =
      <String, PostPendingChildEvent>{};
  final Map<String, List<PostPendingChildEvent>> _pendingChildEventsByPostId =
      <String, List<PostPendingChildEvent>>{};
  final Map<String, PostFollowOnOutboxEvent> _followOnOutboxEventsById =
      <String, PostFollowOnOutboxEvent>{};
  final Map<String, List<PostFollowOnOutboxRecipientDelivery>>
  _followOnOutboxDeliveriesByEventId =
      <String, List<PostFollowOnOutboxRecipientDelivery>>{};
  final Map<String, PostPinStateModel> _pinStates =
      <String, PostPinStateModel>{};
  final Map<String, String> _pinDismissals = <String, String>{};
  final Map<String, List<int>> _passAvatarSnapshots = <String, List<int>>{};
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
  Future<List<PostModel>> loadPostsByIds(List<String> postIds) async {
    final posts = <PostModel>[];
    for (final postId in postIds) {
      final post = _posts[postId];
      if (post != null) {
        posts.add(_decoratePost(post));
      }
    }
    return posts;
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
  Future<List<PostModel>> loadRetryableOutgoingPosts() async {
    return _posts.values
        .map(_decoratePost)
        .where(
          (post) =>
              !post.isIncoming &&
              (post.deliveryStatus == 'sending' ||
                  post.deliveryStatus == 'partial' ||
                  post.deliveryStatus == 'failed'),
        )
        .toList(growable: false)
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
    _postMediaUploadRecoveryByPostId.remove(postId);
    final deliveryOwnerKeys = _deliveriesByOwner.keys.toList(growable: false);
    for (final ownerKey in deliveryOwnerKeys) {
      _deliveriesByOwner[ownerKey]?.removeWhere(
        (delivery) => delivery.postId == postId,
      );
      if ((_deliveriesByOwner[ownerKey] ?? const []).isEmpty) {
        _deliveriesByOwner.remove(ownerKey);
      }
    }
    _postOrigins.remove(postId);
    _repostEngagementParticipantsByPostId.remove(postId);
    _repostHeartBaselinePeersByPostId.remove(postId);
    _repostTotalBaselinesByPostId.remove(postId);
    _repostSharedToBaselinesByPostId.remove(postId);
    _pinStates.remove(postId);
    _pinDismissals.remove(postId);
    _passAvatarSnapshots.remove(postId);
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
  Future<void> replacePostMediaAttachments(
    String postId,
    List<PostMediaAttachmentModel> attachments,
  ) async {
    _postMediaByPostId.remove(postId)?.forEach((attachment) {
      _postMediaById.remove(attachment.mediaId);
    });
    for (final attachment in attachments) {
      _postMediaById[attachment.mediaId] = attachment;
    }
    _postMediaByPostId[postId] =
        List<PostMediaAttachmentModel>.from(attachments)..sort((a, b) {
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
    if (attachments.isEmpty) {
      _postMediaByPostId.remove(postId);
    }
    _changes.add(postId);
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
  Future<void> replacePostMediaUploadRecoveryItems(
    String postId,
    List<PostMediaUploadRecoveryItem> items,
  ) async {
    if (items.isEmpty) {
      _postMediaUploadRecoveryByPostId.remove(postId);
      _changes.add(postId);
      return;
    }
    _postMediaUploadRecoveryByPostId[postId] =
        List<PostMediaUploadRecoveryItem>.from(items)..sort((a, b) {
          final positionCompare = a.position.compareTo(b.position);
          if (positionCompare != 0) {
            return positionCompare;
          }
          return a.createdAt.compareTo(b.createdAt);
        });
    _changes.add(postId);
  }

  @override
  Future<List<PostMediaUploadRecoveryItem>> loadPostMediaUploadRecoveryItems(
    String postId,
  ) async {
    return List<PostMediaUploadRecoveryItem>.from(
      _postMediaUploadRecoveryByPostId[postId] ?? const [],
    );
  }

  @override
  Future<List<PostModel>> loadPendingMediaUploadPosts() async {
    final posts = <PostModel>[];
    for (final postId in _postMediaUploadRecoveryByPostId.keys) {
      final post = _posts[postId];
      if (post == null || post.isIncoming) {
        continue;
      }
      posts.add(_decoratePost(post));
    }
    posts.sort((a, b) {
      final createdCompare = a.createdAt.compareTo(b.createdAt);
      if (createdCompare != 0) {
        return createdCompare;
      }
      return a.id.compareTo(b.id);
    });
    return posts;
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
  Future<void> saveFollowOnOutboxEvent(PostFollowOnOutboxEvent event) async {
    _followOnOutboxEventsById[event.eventId] = event;
  }

  @override
  Future<PostFollowOnOutboxEvent?> getFollowOnOutboxEvent(
    String eventId,
  ) async {
    return _followOnOutboxEventsById[eventId];
  }

  @override
  Future<void> saveFollowOnOutboxRecipientDelivery(
    PostFollowOnOutboxRecipientDelivery delivery,
  ) async {
    final deliveries = _followOnOutboxDeliveriesByEventId.putIfAbsent(
      delivery.eventId,
      () => <PostFollowOnOutboxRecipientDelivery>[],
    );
    deliveries.removeWhere(
      (existing) => existing.recipientPeerId == delivery.recipientPeerId,
    );
    deliveries.add(delivery);
    deliveries.sort((a, b) => a.recipientPeerId.compareTo(b.recipientPeerId));
  }

  @override
  Future<List<PostFollowOnOutboxRecipientDelivery>>
  loadFollowOnOutboxRecipientDeliveries(String eventId) async {
    return List<PostFollowOnOutboxRecipientDelivery>.from(
      _followOnOutboxDeliveriesByEventId[eventId] ?? const [],
    );
  }

  @override
  Future<List<PostFollowOnOutboxJob>> loadRetryableFollowOnOutboxJobs() async {
    final events = _followOnOutboxEventsById.values.toList(growable: false)
      ..sort((a, b) {
        final createdCompare = a.createdAt.compareTo(b.createdAt);
        if (createdCompare != 0) {
          return createdCompare;
        }
        return a.eventId.compareTo(b.eventId);
      });

    final jobs = <PostFollowOnOutboxJob>[];
    for (final event in events) {
      final retryableDeliveries =
          (_followOnOutboxDeliveriesByEventId[event.eventId] ??
                  const <PostFollowOnOutboxRecipientDelivery>[])
              .where((delivery) => !delivery.isSettled)
              .toList(growable: false);
      if (retryableDeliveries.isEmpty) {
        continue;
      }
      jobs.add(
        PostFollowOnOutboxJob(
          event: event,
          recipientDeliveries: retryableDeliveries,
        ),
      );
    }
    return jobs;
  }

  @override
  Future<void> saveRecipientDelivery(PostRecipientDelivery delivery) async {
    final deliveries = _deliveriesByOwner.putIfAbsent(
      _deliveryOwnerKey(delivery.deliveryOwnerKind, delivery.deliveryOwnerId),
      () => <PostRecipientDelivery>[],
    );
    deliveries.removeWhere(
      (existing) => existing.recipientPeerId == delivery.recipientPeerId,
    );
    deliveries.add(delivery);
    deliveries.sort((a, b) => a.recipientPeerId.compareTo(b.recipientPeerId));
    _changes.add(delivery.postId);
  }

  @override
  Future<List<PostRecipientDelivery>> getRecipientDeliveries(
    String postId,
  ) async {
    return List<PostRecipientDelivery>.from(
      _deliveriesByOwner[_deliveryOwnerKey(
            postRecipientDeliveryOwnerKindPost,
            postId,
          )] ??
          const [],
    );
  }

  @override
  Future<List<PostRecipientDelivery>> getPostPassRecipientDeliveries(
    String passId,
  ) async {
    return List<PostRecipientDelivery>.from(
      _deliveriesByOwner[_deliveryOwnerKey(
            postRecipientDeliveryOwnerKindPass,
            passId,
          )] ??
          const [],
    );
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
  Future<List<PostPassModel>> loadRetryableOutgoingPostPasses() async {
    return _postPassesById.values
        .where(
          (pass) =>
              !pass.isIncoming &&
              (pass.deliveryStatus == 'sending' ||
                  pass.deliveryStatus == 'partial' ||
                  pass.deliveryStatus == 'failed'),
        )
        .toList(growable: false)
      ..sort((a, b) {
        final passedCompare = b.passedAt.compareTo(a.passedAt);
        if (passedCompare != 0) {
          return passedCompare;
        }
        return b.passId.compareTo(a.passId);
      });
  }

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
  Future<Map<String, int>> loadViewerSharedToCountsForPosts(
    List<String> postIds,
    String viewerPeerId,
  ) async {
    if (postIds.isEmpty || viewerPeerId.isEmpty) {
      return const <String, int>{};
    }
    return <String, int>{
      for (final postId in postIds)
        if ((_postPassesByPostId[postId] ?? const <PostPassModel>[])
                .where(
                  (pass) =>
                      !pass.isIncoming && pass.senderPeerId == viewerPeerId,
                )
                .fold<int>(
                  0,
                  (total, pass) => total + (pass.recipientCount ?? 1),
                ) >
            0)
          postId: (_postPassesByPostId[postId] ?? const <PostPassModel>[])
              .where(
                (pass) => !pass.isIncoming && pass.senderPeerId == viewerPeerId,
              )
              .fold<int>(
                0,
                (total, pass) => total + (pass.recipientCount ?? 1),
              ),
    };
  }

  @override
  Future<void> saveRepostEngagementParticipant({
    required String postId,
    required String participantPeerId,
    required String createdAt,
  }) async {
    if (participantPeerId.isEmpty) {
      return;
    }
    _repostEngagementParticipantsByPostId
        .putIfAbsent(postId, () => <String>{})
        .add(participantPeerId);
    _changes.add(postId);
  }

  @override
  Future<Set<String>> loadRepostEngagementParticipantPeerIds(
    String postId,
  ) async {
    return Set<String>.from(
      _repostEngagementParticipantsByPostId[postId] ?? const <String>{},
    );
  }

  @override
  Future<void> saveRepostHeartBaselinePeerIds({
    required String postId,
    required Iterable<String> peerIds,
    required String createdAt,
  }) async {
    final baselinePeerIds = _repostHeartBaselinePeersByPostId.putIfAbsent(
      postId,
      () => <String>{},
    );
    baselinePeerIds.addAll(
      peerIds.where((peerId) => peerId.isNotEmpty).toSet(),
    );
    _changes.add(postId);
  }

  @override
  Future<Set<String>> loadRepostHeartBaselinePeerIds(String postId) async {
    return Set<String>.from(
      _repostHeartBaselinePeersByPostId[postId] ?? const <String>{},
    );
  }

  @override
  Future<Map<String, Set<String>>> loadRepostHeartBaselinePeerIdsForPosts(
    List<String> postIds,
  ) async {
    return <String, Set<String>>{
      for (final postId in postIds)
        if (_repostHeartBaselinePeersByPostId.containsKey(postId))
          postId: Set<String>.from(
            _repostHeartBaselinePeersByPostId[postId] ?? const <String>{},
          ),
    };
  }

  @override
  Future<void> seedRepostTotalBaseline({
    required String postId,
    required int repostTotalBaseline,
    required int existingLocalPassCount,
    required String createdAt,
  }) async {
    final expectedVisibleShareCount = repostTotalBaseline + 1;
    final baselineDelta = expectedVisibleShareCount > existingLocalPassCount
        ? expectedVisibleShareCount - existingLocalPassCount
        : 0;
    final existingBaseline = _repostTotalBaselinesByPostId[postId] ?? 0;
    if (baselineDelta <= existingBaseline) {
      return;
    }
    _repostTotalBaselinesByPostId[postId] = baselineDelta;
    _changes.add(postId);
  }

  @override
  Future<int> loadRepostTotalBaseline(String postId) async {
    return _repostTotalBaselinesByPostId[postId] ?? 0;
  }

  @override
  Future<Map<String, int>> loadRepostTotalBaselines(
    List<String> postIds,
  ) async {
    return <String, int>{
      for (final postId in postIds)
        if (_repostTotalBaselinesByPostId.containsKey(postId))
          postId: _repostTotalBaselinesByPostId[postId] ?? 0,
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
    final expectedVisibleSharedToCount =
        sharedToCountBaseline + currentPassRecipientCount;
    final baselineDelta =
        expectedVisibleSharedToCount > existingLocalSharedToCount
        ? expectedVisibleSharedToCount - existingLocalSharedToCount
        : 0;
    final existingBaseline = _repostSharedToBaselinesByPostId[postId] ?? 0;
    if (baselineDelta <= existingBaseline) {
      return;
    }
    _repostSharedToBaselinesByPostId[postId] = baselineDelta;
    _changes.add(postId);
  }

  @override
  Future<int> loadRepostSharedToBaseline(String postId) async {
    return _repostSharedToBaselinesByPostId[postId] ??
        _repostTotalBaselinesByPostId[postId] ??
        0;
  }

  @override
  Future<Map<String, int>> loadRepostSharedToBaselines(
    List<String> postIds,
  ) async {
    return <String, int>{
      for (final postId in postIds)
        if (_repostSharedToBaselinesByPostId.containsKey(postId) ||
            _repostTotalBaselinesByPostId.containsKey(postId))
          postId:
              _repostSharedToBaselinesByPostId[postId] ??
              _repostTotalBaselinesByPostId[postId] ??
              0,
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
  Future<void> savePostPinState(PostPinStateModel pinState) async {
    _pinStates[pinState.postId] = pinState;
    _changes.add(pinState.postId);
  }

  @override
  Future<PostPinStateModel?> getPostPinState(String postId) async {
    return _pinStates[postId];
  }

  @override
  Future<List<PostPinStateModel>> loadActivePinStates() async {
    final states =
        _pinStates.values
            .where((state) => state.isActive)
            .toList(growable: false)
          ..sort((a, b) {
            final effectiveCompare = b.effectiveAt.compareTo(a.effectiveAt);
            if (effectiveCompare != 0) {
              return effectiveCompare;
            }
            return b.postId.compareTo(a.postId);
          });
    return states;
  }

  @override
  Future<void> savePinDismissal(String postId, String dismissedAt) async {
    _pinDismissals[postId] = dismissedAt;
    _changes.add(postId);
  }

  @override
  Future<Set<String>> loadDismissedPinPostIds() async {
    return _pinDismissals.keys.toSet();
  }

  @override
  Future<void> clearPinDismissal(String postId) async {
    _pinDismissals.remove(postId);
    _changes.add(postId);
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
  Future<void> savePassAvatarSnapshot({
    required String postId,
    required String authorPeerId,
    required List<int> avatarBlob,
    required String createdAt,
  }) async {
    _passAvatarSnapshots.putIfAbsent(postId, () => avatarBlob);
  }

  @override
  Future<List<int>?> loadPassAvatarSnapshot(String postId) async {
    return _passAvatarSnapshots[postId];
  }

  @override
  Future<Map<String, List<int>>> loadPassAvatarSnapshotsForPosts(
    List<String> postIds,
  ) async {
    return <String, List<int>>{
      for (final postId in postIds)
        if (_passAvatarSnapshots.containsKey(postId))
          postId: _passAvatarSnapshots[postId]!,
    };
  }

  @override
  void dispose() {
    _changes.close();
  }

  String _deliveryOwnerKey(String ownerKind, String ownerId) {
    return '$ownerKind::$ownerId';
  }

  PostModel _decoratePost(PostModel post) {
    final origin = _postOrigins[post.id];
    final postPasses = _postPassesByPostId[post.id] ?? const <PostPassModel>[];
    final passCount =
        postPasses.length + (_repostTotalBaselinesByPostId[post.id] ?? 0);
    final totalSharedToCount =
        postPasses.fold<int>(
          0,
          (total, pass) => total + (pass.recipientCount ?? 1),
        ) +
        (_repostSharedToBaselinesByPostId[post.id] ??
            _repostTotalBaselinesByPostId[post.id] ??
            0);
    return post.copyWith(
      passedByPeerId: origin?.passerPeerId,
      passedByUsername: origin?.passerUsername,
      passedAt: origin?.passCreatedAt,
      shareCount: passCount,
      totalSharedToCount: totalSharedToCount,
    );
  }
}
