import 'dart:async';

import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class InMemoryPostRepository implements PostRepository {
  final Map<String, PostModel> _posts = <String, PostModel>{};
  final Map<String, List<PostRecipientDelivery>> _deliveries =
      <String, List<PostRecipientDelivery>>{};
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
  Future<PostModel?> getPost(String postId) async => _posts[postId];

  @override
  Future<bool> postExists(String postId) async => _posts.containsKey(postId);

  @override
  Future<List<PostModel>> loadFeed() async {
    final posts = _posts.values.toList(growable: false)
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
}
