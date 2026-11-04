import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

/// One tag the author has used on their own Thoughts.
class OwnThoughtTag {
  const OwnThoughtTag({
    required this.key,
    required this.label,
    required this.lastUsed,
  });

  /// The lowercased word after '#': the same tag however it was written.
  final String key;

  /// The tag as last written, with its '#'.
  final String label;

  /// When the newest Thought carrying it was written.
  final DateTime lastUsed;
}

Future<List<OwnThoughtTag>> loadOwnThoughtTags({
  required PostRepository postRepo,
  required PostModel? live,
  DateTime Function()? nowProvider,
}) async => const [];
