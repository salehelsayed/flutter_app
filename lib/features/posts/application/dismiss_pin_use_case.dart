import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

Future<void> dismissPin({
  required PostRepository postRepo,
  required String postId,
  DateTime Function()? nowProvider,
}) async {
  final dismissedAt = (nowProvider ?? DateTime.now)
      .call()
      .toUtc()
      .toIso8601String();
  await postRepo.savePinDismissal(postId, dismissedAt);
}
