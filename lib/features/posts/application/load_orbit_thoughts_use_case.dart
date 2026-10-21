import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

/// The newest live incoming thought for each current friend in Orbit.
class LoadOrbitThoughtsUseCase {
  final PostRepository _postRepo;
  final ContactRepository _contactRepo;
  final DateTime Function() _nowProvider;

  LoadOrbitThoughtsUseCase({
    required PostRepository postRepo,
    required ContactRepository contactRepo,
    DateTime Function()? nowProvider,
  }) : _postRepo = postRepo,
       _contactRepo = contactRepo,
       _nowProvider = nowProvider ?? DateTime.now;

  Future<List<PostModel>> execute({required String localPeerId}) async {
    final posts = await _postRepo.loadFeed();
    // Check current contact authority after loading persisted thoughts: a later
    // block, archive or deletion must also remove the author's existing dot.
    final contacts = await _contactRepo.getActiveContacts();
    final allowedAuthors = contacts
        .where((contact) => !contact.isArchived && !contact.isBlocked)
        .map((contact) => contact.peerId)
        .toSet();
    final now = _nowProvider().toUtc();
    final newestByAuthor = <String, PostModel>{};
    final createdById = <String, DateTime>{};

    for (final post in posts) {
      if (!post.isIncoming ||
          post.authorPeerId == localPeerId ||
          !allowedAuthors.contains(post.authorPeerId)) {
        continue;
      }
      final expiresAt = DateTime.tryParse(post.expiresAt)?.toUtc();
      final createdAt = DateTime.tryParse(post.createdAt)?.toUtc();
      if (expiresAt == null || !expiresAt.isAfter(now) || createdAt == null) {
        continue;
      }
      createdById[post.id] = createdAt;
      final previous = newestByAuthor[post.authorPeerId];
      if (previous == null ||
          createdAt.isAfter(createdById[previous.id]!) ||
          (createdAt.isAtSameMomentAs(createdById[previous.id]!) &&
              post.id.compareTo(previous.id) < 0)) {
        newestByAuthor[post.authorPeerId] = post;
      }
    }

    return newestByAuthor.values.toList(growable: false)..sort((a, b) {
      if (a.isRead != b.isRead) {
        return a.isRead ? 1 : -1;
      }
      final byCreatedAt = createdById[b.id]!.compareTo(createdById[a.id]!);
      return byCreatedAt != 0 ? byCreatedAt : a.id.compareTo(b.id);
    });
  }
}
