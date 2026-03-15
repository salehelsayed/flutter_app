import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PostRepositoryImpl implements PostRepository {
  final Future<void> Function(Map<String, Object?> row) dbInsertPost;
  final Future<Map<String, Object?>?> Function(String postId) dbLoadPost;
  final Future<List<Map<String, Object?>>> Function() dbLoadPostsFeed;
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertRecipientDelivery;
  final Future<List<Map<String, Object?>>> Function(String postId)
  dbLoadRecipientDeliveries;
  final Future<void> Function(String postId) dbMarkPostFocused;

  final StreamController<String> _postChangesController =
      StreamController<String>.broadcast();

  PostRepositoryImpl({
    required this.dbInsertPost,
    required this.dbLoadPost,
    required this.dbLoadPostsFeed,
    required this.dbUpsertRecipientDelivery,
    required this.dbLoadRecipientDeliveries,
    required this.dbMarkPostFocused,
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
  Future<void> markFocused(String postId) async {
    await dbMarkPostFocused(postId);
    _postChangesController.add(postId);
  }

  @override
  void dispose() {
    _postChangesController.close();
  }
}
