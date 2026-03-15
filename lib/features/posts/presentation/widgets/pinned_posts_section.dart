import 'package:flutter/material.dart';

import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

class PinnedPostsSection extends StatefulWidget {
  final List<PostModel> posts;
  final String? viewerPeerId;
  final void Function(PostModel post)? onDismiss;
  final void Function(PostModel post)? onMessage;
  final void Function(PostModel post)? onEdit;
  final void Function(PostModel post)? onRemove;

  const PinnedPostsSection({
    super.key,
    required this.posts,
    this.viewerPeerId,
    this.onDismiss,
    this.onMessage,
    this.onEdit,
    this.onRemove,
  });

  @override
  State<PinnedPostsSection> createState() => _PinnedPostsSectionState();
}

class _PinnedPostsSectionState extends State<PinnedPostsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) {
      return const SizedBox.shrink();
    }

    final previewPosts = widget.posts.take(5).toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151922),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.08)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  _PinnedAvatarStack(posts: widget.posts),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pinned posts',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _summaryCopy(widget.posts),
                          style: const TextStyle(
                            color: Color.fromRGBO(255, 255, 255, 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _countCopy(widget.posts.length),
                    style: const TextStyle(
                      color: Color(0xFF8FD6B5),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(
              height: 1,
              color: Color.fromRGBO(255, 255, 255, 0.08),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (var index = 0; index < previewPosts.length; index++) ...[
                    _PinnedPostCard(
                      post: previewPosts[index],
                      viewerPeerId: widget.viewerPeerId,
                      onDismiss: widget.onDismiss,
                      onMessage: widget.onMessage,
                      onEdit: widget.onEdit,
                      onRemove: widget.onRemove,
                    ),
                    if (index != previewPosts.length - 1)
                      const SizedBox(height: 12),
                  ],
                  if (widget.posts.length > previewPosts.length) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _PinnedPostsSeeAllPage(
                              posts: widget.posts,
                              viewerPeerId: widget.viewerPeerId,
                              onDismiss: widget.onDismiss,
                              onMessage: widget.onMessage,
                              onEdit: widget.onEdit,
                              onRemove: widget.onRemove,
                            ),
                            fullscreenDialog: true,
                          ),
                        );
                      },
                      child: Text(
                        'See all ${widget.posts.length} pinned posts',
                        style: const TextStyle(
                          color: Color(0xFF8FD6B5),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _countCopy(int count) {
    return count == 1 ? '1 pinned post' : '$count pinned posts';
  }

  static String _summaryCopy(List<PostModel> posts) {
    final authors = <String>{
      for (final post in posts) post.authorUsername,
    }.toList(growable: false);
    if (authors.length == 1) {
      return '${authors.single} has an active offer';
    }
    if (authors.length == 2) {
      return '${authors.first} and ${authors.last} have active offers';
    }
    return '${authors.first}, ${authors[1]}, and ${authors.length - 2} more';
  }
}

class _PinnedPostCard extends StatelessWidget {
  final PostModel post;
  final String? viewerPeerId;
  final void Function(PostModel post)? onDismiss;
  final void Function(PostModel post)? onMessage;
  final void Function(PostModel post)? onEdit;
  final void Function(PostModel post)? onRemove;

  const _PinnedPostCard({
    required this.post,
    required this.viewerPeerId,
    this.onDismiss,
    this.onMessage,
    this.onEdit,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isAuthor = viewerPeerId != null && viewerPeerId == post.authorPeerId;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F141B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(peerId: post.authorPeerId, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    post.authorUsername,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (post.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              post.text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (!isAuthor && onDismiss != null)
                TextButton(
                  onPressed: () => onDismiss!(post),
                  child: const Text('Dismiss'),
                ),
              if (!isAuthor && onMessage != null)
                TextButton(
                  onPressed: () => onMessage!(post),
                  child: Text('Message ${post.authorUsername}'),
                ),
              if (isAuthor && onEdit != null)
                TextButton(
                  onPressed: () => onEdit!(post),
                  child: const Text('Edit'),
                ),
              if (isAuthor && onRemove != null)
                TextButton(
                  onPressed: () => onRemove!(post),
                  child: const Text('Remove'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PinnedAvatarStack extends StatelessWidget {
  final List<PostModel> posts;

  const _PinnedAvatarStack({required this.posts});

  @override
  Widget build(BuildContext context) {
    final authorsByPeerId = <String, PostModel>{};
    for (final post in posts) {
      authorsByPeerId.putIfAbsent(post.authorPeerId, () => post);
    }
    final authorPosts = authorsByPeerId.values.toList(growable: false);
    final visibleAuthors = authorPosts.take(6).toList(growable: false);
    final overflowCount = authorPosts.length - visibleAuthors.length;
    return SizedBox(
      width: 28.0 * visibleAuthors.length + (overflowCount > 0 ? 30 : 0),
      height: 28,
      child: Stack(
        children: [
          for (var index = 0; index < visibleAuthors.length; index++)
            Positioned(
              left: index * 20.0,
              child: _AvatarBadge(post: visibleAuthors[index]),
            ),
          if (overflowCount > 0)
            Positioned(
              left: visibleAuthors.length * 20.0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF263341),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$overflowCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  final PostModel post;

  const _AvatarBadge({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF0F141B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF151922), width: 2),
      ),
      child: ClipOval(
        child: UserAvatar(
          peerId: post.authorPeerId,
          size: 24,
          showGlow: false,
          showPhotoFrame: false,
        ),
      ),
    );
  }
}

class _PinnedPostsSeeAllPage extends StatelessWidget {
  final List<PostModel> posts;
  final String? viewerPeerId;
  final void Function(PostModel post)? onDismiss;
  final void Function(PostModel post)? onMessage;
  final void Function(PostModel post)? onEdit;
  final void Function(PostModel post)? onRemove;

  const _PinnedPostsSeeAllPage({
    required this.posts,
    required this.viewerPeerId,
    this.onDismiss,
    this.onMessage,
    this.onEdit,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1016),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          posts.length == 1 ? '1 pinned post' : '${posts.length} pinned posts',
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: posts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _PinnedPostCard(
            post: posts[index],
            viewerPeerId: viewerPeerId,
            onDismiss: onDismiss,
            onMessage: onMessage,
            onEdit: onEdit,
            onRemove: onRemove,
          );
        },
      ),
    );
  }
}
