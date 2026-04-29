import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_repost_visual_state.dart';
import 'package:flutter_app/features/posts/presentation/widgets/pinned_posts_section.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

class PostsScreen extends StatelessWidget {
  final String username;
  final List<PostModel> posts;
  final List<PostModel> pinnedPosts;
  final ScrollController? scrollController;
  final Map<String, GlobalKey> postKeys;
  final String? viewerPeerId;
  final String activeTab;
  final void Function(String tab) onSwitchView;
  final VoidCallback onCompose;
  final void Function(PostModel post)? onOpenComments;
  final void Function(PostModel post)? onToggleHeart;
  final void Function(PostModel post)? onPassAlong;
  final void Function(PostModel post)? onPinPost;
  final void Function(PostModel post)? onDismissPin;
  final void Function(PostModel post)? onMessageFromPin;
  final void Function(PostModel post)? onEditPinnedPost;
  final void Function(PostModel post)? onRemovePin;
  final String? focusedPostId;
  final String? statusMessage;
  final Set<String> activePinnedPostIds;
  final BackgroundPreference backgroundPreference;

  const PostsScreen({
    super.key,
    required this.username,
    required this.posts,
    this.pinnedPosts = const <PostModel>[],
    this.scrollController,
    this.postKeys = const <String, GlobalKey>{},
    this.viewerPeerId,
    required this.activeTab,
    required this.onSwitchView,
    required this.onCompose,
    this.onOpenComments,
    this.onToggleHeart,
    this.onPassAlong,
    this.onPinPost,
    this.onDismissPin,
    this.onMessageFromPin,
    this.onEditPinnedPost,
    this.onRemovePin,
    this.focusedPostId,
    this.statusMessage,
    this.activePinnedPostIds = const <String>{},
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final grouped = _groupPosts(posts);

    return AmbientBackground(
      preference: backgroundPreference,
      child: Builder(
        builder: (context) {
          final readableColors = context.backgroundReadableColors;

          return Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                SafeArea(
                  bottom: false,
                  child: CustomScrollView(
                    controller: scrollController,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        sliver: SliverToBoxAdapter(
                          child: _PostsHeader(
                            username: username,
                            onCompose: onCompose,
                          ),
                        ),
                      ),
                      if (statusMessage != null)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverToBoxAdapter(
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: readableColors.surfaceRaised,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: readableColors.border,
                                ),
                              ),
                              child: Text(
                                statusMessage!,
                                style: TextStyle(
                                  color: readableColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (pinnedPosts.isNotEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          sliver: SliverToBoxAdapter(
                            child: PinnedPostsSection(
                              posts: pinnedPosts,
                              viewerPeerId: viewerPeerId,
                              onDismiss: onDismissPin,
                              onMessage: onMessageFromPin,
                              onEdit: onEditPinnedPost,
                              onRemove: onRemovePin,
                            ),
                          ),
                        ),
                      if (posts.isEmpty && pinnedPosts.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyState(onCompose: onCompose),
                        )
                      else if (posts.isNotEmpty)
                        for (final section in grouped.entries) ...[
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                            sliver: SliverToBoxAdapter(
                              child: Text(
                                _translateGroupKey(section.key, context),
                                style: TextStyle(
                                  color: readableColors.textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final post = section.value[index];
                              return PostCard(
                                key:
                                    postKeys[post.id] ??
                                    ValueKey<String>('post-${post.id}'),
                                post: post,
                                onOpenComments: onOpenComments == null
                                    ? null
                                    : () => onOpenComments!(post),
                                onToggleHeart: onToggleHeart == null
                                    ? null
                                    : () => onToggleHeart!(post),
                                onPassAlong: onPassAlong == null
                                    ? null
                                    : () => onPassAlong!(post),
                                onPinPost:
                                    onPinPost != null &&
                                        viewerPeerId != null &&
                                        post.authorPeerId == viewerPeerId &&
                                        !activePinnedPostIds.contains(post.id)
                                    ? () => onPinPost!(post)
                                    : null,
                                viewerPeerId: viewerPeerId,
                                repostVisualState: resolvePostRepostVisualState(
                                  post,
                                  viewerPeerId: viewerPeerId,
                                ),
                                isFocused:
                                    post.id == focusedPostId || post.isFocused,
                              );
                            }, childCount: section.value.length),
                          ),
                        ],
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            8,
                            20,
                            88 + bottomInset,
                          ),
                          child: Text(
                            AppLocalizations.of(context)!.posts_caught_up,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: readableColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomInset - 14,
                  child: Center(
                    child: FeedNavigationBar(
                      activeTab: activeTab,
                      onSwitchView: onSwitchView,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Map<String, List<PostModel>> _groupPosts(List<PostModel> input) {
    final now = DateTime.now();
    final grouped = <String, List<PostModel>>{};
    for (final post in input) {
      final timestamp = DateTime.tryParse(post.visibleAt)?.toLocal() ?? now;
      final diff = now.difference(timestamp);
      final key = switch (diff) {
        _ when diff.inHours < 4 => 'right_now',
        _
            when now.year == timestamp.year &&
                now.month == timestamp.month &&
                now.day == timestamp.day =>
          'earlier_today',
        _
            when now
                    .subtract(const Duration(days: 1))
                    .difference(
                      DateTime(timestamp.year, timestamp.month, timestamp.day),
                    )
                    .inDays ==
                0 =>
          'yesterday',
        _ => '${timestamp.month}/${timestamp.day}/${timestamp.year}',
      };
      grouped.putIfAbsent(key, () => <PostModel>[]).add(post);
    }
    return grouped;
  }

  String _translateGroupKey(String key, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (key) {
      case 'right_now':
        return l10n.posts_time_now;
      case 'earlier_today':
        return l10n.posts_time_earlier;
      case 'yesterday':
        return l10n.posts_time_yesterday;
      default:
        return key; // date string like 3/18/2026
    }
  }
}

class _PostsHeader extends StatelessWidget {
  final String username;
  final VoidCallback onCompose;

  const _PostsHeader({required this.username, required this.onCompose});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.posts_title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: readableColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          AppLocalizations.of(context)!.posts_header_subtitle(username),
          style: TextStyle(color: readableColors.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 18),
        InkWell(
          onTap: onCompose,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: readableColors.surfaceRaised,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: readableColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_outlined, color: readableColors.iconSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.posts_compose_button,
                    style: TextStyle(
                      color: readableColors.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: readableColors.iconMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCompose;

  const _EmptyState({required this.onCompose});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppLocalizations.of(context)!.posts_empty_title,
              style: TextStyle(
                color: readableColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context)!.posts_empty_desc,
              textAlign: TextAlign.center,
              style: TextStyle(color: readableColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onCompose,
              child: Text(AppLocalizations.of(context)!.posts_empty_button),
            ),
          ],
        ),
      ),
    );
  }
}
