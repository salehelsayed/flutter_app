import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

abstract class PostRepository {
  Stream<String> get postChanges;

  Future<void> savePost(PostModel post);

  Future<PostModel?> getPost(String postId);

  Future<bool> postExists(String postId);

  Future<List<PostModel>> loadFeed();

  Future<void> saveRecipientDelivery(PostRecipientDelivery delivery);

  Future<List<PostRecipientDelivery>> getRecipientDeliveries(String postId);

  Future<void> markFocused(String postId);

  void dispose();
}
