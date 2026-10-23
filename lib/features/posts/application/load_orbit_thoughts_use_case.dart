import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

/// The newest live thought per Orbit author: one per current friend, and the
/// user's own.
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

  /// Friends' newest live incoming thoughts, unseen first, then newest first.
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
      final createdAt = _liveCreatedAt(post, now);
      if (createdAt == null) continue;
      createdById[post.id] = createdAt;
      final previous = newestByAuthor[post.authorPeerId];
      if (previous == null ||
          _isNewer(post, createdAt, previous, createdById[previous.id]!)) {
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

  /// The user's own newest live outgoing thought, or null when none is live.
  Future<PostModel?> executeOwn({required String localPeerId}) async {
    final posts = await _postRepo.loadFeed();
    final now = _nowProvider().toUtc();
    PostModel? newest;
    DateTime? newestCreatedAt;
    for (final post in posts) {
      if (post.isIncoming || post.authorPeerId != localPeerId) continue;
      final createdAt = _liveCreatedAt(post, now);
      if (createdAt == null) continue;
      if (newest == null || _isNewer(post, createdAt, newest, newestCreatedAt!)) {
        newest = post;
        newestCreatedAt = createdAt;
      }
    }
    return newest;
  }

  /// The creation instant of a live thought with valid timestamps, else null.
  static DateTime? _liveCreatedAt(PostModel post, DateTime now) {
    final expiresAt = DateTime.tryParse(post.expiresAt)?.toUtc();
    if (expiresAt == null || !expiresAt.isAfter(now)) return null;
    return DateTime.tryParse(post.createdAt)?.toUtc();
  }

  /// Later creation wins; the smaller ID settles an exact tie.
  static bool _isNewer(
    PostModel post,
    DateTime createdAt,
    PostModel previous,
    DateTime previousCreatedAt,
  ) =>
      createdAt.isAfter(previousCreatedAt) ||
      (createdAt.isAtSameMomentAs(previousCreatedAt) &&
          post.id.compareTo(previous.id) < 0);
}
