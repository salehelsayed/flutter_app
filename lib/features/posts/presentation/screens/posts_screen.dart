import 'package:flutter/material.dart';

import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';

class PostsScreen extends StatelessWidget {
  final String username;
  final List<PostModel> posts;
  final ScrollController? scrollController;
  final Map<String, GlobalKey> postKeys;
  final String activeTab;
  final void Function(String tab) onSwitchView;
  final VoidCallback onCompose;
  final void Function(PostModel post)? onOpenComments;
  final void Function(PostModel post)? onToggleHeart;
  final String? focusedPostId;
  final String? statusMessage;

  const PostsScreen({
    super.key,
    required this.username,
    required this.posts,
    this.scrollController,
    this.postKeys = const <String, GlobalKey>{},
    required this.activeTab,
    required this.onSwitchView,
    required this.onCompose,
    this.onOpenComments,
    this.onToggleHeart,
    this.focusedPostId,
    this.statusMessage,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final grouped = _groupPosts(posts);

    return AmbientBackground(
      child: Material(
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
                            color: const Color(0xFF1A2630),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            statusMessage!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  if (posts.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(onCompose: onCompose),
                    )
                  else
                    for (final section in grouped.entries) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            section.key,
                            style: const TextStyle(
                              color: Color.fromRGBO(255, 255, 255, 0.6),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final itemIndex = index ~/ 2;
                              if (index.isOdd) {
                                return const SizedBox(height: 12);
                              }
                              final post = section.value[itemIndex];
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
                                isFocused:
                                    post.id == focusedPostId || post.isFocused,
                              );
                            },
                            childCount: section.value.isEmpty
                                ? 0
                                : (section.value.length * 2) - 1,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 6)),
                    ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 88 + bottomInset),
                      child: const Text(
                        "You're all caught up",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color.fromRGBO(255, 255, 255, 0.45),
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
        _ when diff.inHours < 4 => 'Right now',
        _
            when now.year == timestamp.year &&
                now.month == timestamp.month &&
                now.day == timestamp.day =>
          'Earlier today',
        _
            when now
                    .subtract(const Duration(days: 1))
                    .difference(
                      DateTime(timestamp.year, timestamp.month, timestamp.day),
                    )
                    .inDays ==
                0 =>
          'Yesterday',
        _ => '${timestamp.month}/${timestamp.day}/${timestamp.year}',
      };
      grouped.putIfAbsent(key, () => <PostModel>[]).add(post);
    }
    return grouped;
  }
}

class _PostsHeader extends StatelessWidget {
  final String username;
  final VoidCallback onCompose;

  const _PostsHeader({required this.username, required this.onCompose});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Posts',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'What\'s happening around your friends today, $username?',
          style: const TextStyle(
            color: Color.fromRGBO(255, 255, 255, 0.6),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 18),
        InkWell(
          onTap: onCompose,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF151922),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color.fromRGBO(255, 255, 255, 0.08),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.edit_outlined, color: Colors.white70),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Share something with your friends',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white38),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "You're all caught up",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your direct-friend posts will appear here after they land or replay.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color.fromRGBO(255, 255, 255, 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onCompose,
              child: const Text('Create your first post'),
            ),
          ],
        ),
      ),
    );
  }
}
