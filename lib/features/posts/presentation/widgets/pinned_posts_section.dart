import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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

    final readableColors = context.backgroundReadableColors;
    final previewPosts = widget.posts.take(5).toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: readableColors.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: readableColors.border),
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
                        Text(
                          AppLocalizations.of(context)!.pinned_title,
                          style: TextStyle(
                            color: readableColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _summaryCopy(widget.posts),
                          style: TextStyle(
                            color: readableColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _countCopy(widget.posts.length, context),
                    style: const TextStyle(
                      color: Color(0xFF8FD6B5),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: readableColors.iconSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: readableColors.divider),
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
                        AppLocalizations.of(
                          context,
                        )!.pinned_see_all(widget.posts.length),
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

  static String _countCopy(int count, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return count == 1 ? l10n.pinned_count_1 : l10n.pinned_count_n(count);
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
    final readableColors = context.backgroundReadableColors;
    final isAuthor = viewerPeerId != null && viewerPeerId == post.authorPeerId;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: readableColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: readableColors.border),
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
                    style: TextStyle(
                      color: readableColors.textPrimary,
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
              style: TextStyle(
                color: readableColors.textSecondary,
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
                  child: Text(AppLocalizations.of(context)!.pinned_dismiss),
                ),
              if (!isAuthor && onMessage != null)
                TextButton(
                  onPressed: () => onMessage!(post),
                  child: Text(
                    AppLocalizations.of(
                      context,
                    )!.pinned_message(post.authorUsername),
                  ),
                ),
              if (isAuthor && onEdit != null)
                TextButton(
                  onPressed: () => onEdit!(post),
                  child: Text(AppLocalizations.of(context)!.pinned_edit),
                ),
              if (isAuthor && onRemove != null)
                TextButton(
                  onPressed: () => onRemove!(post),
                  child: Text(AppLocalizations.of(context)!.pinned_remove),
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
    final readableColors = context.backgroundReadableColors;
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
                  color: readableColors.disabledSurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$overflowCount',
                  style: TextStyle(
                    color: readableColors.textPrimary,
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
    final readableColors = context.backgroundReadableColors;

    return Container(
      width: 28,
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: readableColors.surfaceBase,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: readableColors.border, width: 2),
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
      backgroundColor: context.backgroundReadableColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: context.backgroundReadableColors.textPrimary,
        title: Text(
          posts.length == 1
              ? AppLocalizations.of(context)!.pinned_count_1
              : AppLocalizations.of(context)!.pinned_count_n(posts.length),
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
