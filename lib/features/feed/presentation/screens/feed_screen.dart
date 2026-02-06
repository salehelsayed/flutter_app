import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/widgets/connection_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_header.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

/// Pure UI Feed screen.
///
/// Displays a fixed header, a responsive feed content area, and a pinned bottom
/// navigation bar.
class FeedScreen extends StatelessWidget {
  final String username;
  final String? userAvatarPath;
  final String? userPeerId;
  final List<FeedItem> feedItems;
  final ValueChanged<String>? onUsernameChanged;
  final P2PService? p2pService;
  final void Function(String) onSwitchView;
  final String activeTab;

  const FeedScreen({
    super.key,
    required this.username,
    this.userAvatarPath,
    this.userPeerId,
    required this.feedItems,
    this.onUsernameChanged,
    this.p2pService,
    required this.onSwitchView,
    required this.activeTab,
  });

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 390 ? 14.0 : 18.0;

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    8,
                    horizontalPadding,
                    0,
                  ),
                  child: FeedHeader(
                    username: username,
                    avatarPath: userAvatarPath,
                    peerId: userPeerId,
                    onUsernameChanged: onUsernameChanged,
                    p2pService: p2pService,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, contentConstraints) {
                      final maxFeedWidth = contentConstraints.maxWidth >= 900
                          ? 640.0
                          : contentConstraints.maxWidth >= 600
                          ? 560.0
                          : 460.0;

                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: contentConstraints.maxHeight,
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: maxFeedWidth,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _buildFeedCards(),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    8,
                    horizontalPadding,
                    10,
                  ),
                  child: FeedNavigationBar(
                    activeTab: activeTab,
                    onSwitchView: onSwitchView,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildFeedCards() {
    final connectionItems = feedItems.whereType<ConnectionFeedItem>().toList();
    if (connectionItems.isEmpty) {
      return [
        const SizedBox(height: 12),
        _EmptyFeedStateCard(username: username),
      ];
    }

    return [
      const SizedBox(height: 6),
      for (var i = 0; i < connectionItems.length; i++) ...[
        ConnectionCard(
          contactPeerId: connectionItems[i].contactPeerId,
          contactUsername: connectionItems[i].contactUsername,
          contactAvatarPath: connectionItems[i].contactAvatarPath,
        ),
        if (i != connectionItems.length - 1) const SizedBox(height: 16),
      ],
      const SizedBox(height: 20),
    ];
  }
}

class _EmptyFeedStateCard extends StatelessWidget {
  final String username;

  const _EmptyFeedStateCard({required this.username});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color.fromRGBO(24, 26, 32, 0.72),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.12)),
      ),
      child: Text(
        'Your feed is ready, @$username. New connections will appear here.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color.fromRGBO(255, 255, 255, 0.78),
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
