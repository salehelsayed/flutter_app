import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

Future<List<PostModel>> loadPostsFeed({required PostRepository postRepo}) {
  return postRepo.loadFeed();
}
