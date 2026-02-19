import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/widgets/connection_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_header.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/session_divider.dart';
import 'package:flutter_app/features/feed/presentation/widgets/thread_card.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

/// Pure UI Feed screen.
///
/// Displays a fixed header, a responsive feed content area, and a pinned bottom
/// navigation bar.
class FeedScreen extends StatelessWidget {
  final String username;
  final Uint8List? userAvatarBytes;
  final String? userPeerId;
  final List<FeedItem> feedItems;
  final ValueChanged<String>? onUsernameChanged;
  final P2PService? p2pService;
  final void Function(String) onSwitchView;
  final String activeTab;
  final void Function(ConnectionFeedItem)? onSendMessage;
  final void Function(String contactPeerId)? onReplyToMessage;
  final int totalUnreadCount;
  final String? expandedCardId;
  final void Function(String)? onToggleExpand;

  const FeedScreen({
    super.key,
    required this.username,
    this.userAvatarBytes,
    this.userPeerId,
    required this.feedItems,
    this.onUsernameChanged,
    this.p2pService,
    required this.onSwitchView,
    required this.activeTab,
    this.onSendMessage,
    this.onReplyToMessage,
    this.totalUnreadCount = 0,
    this.expandedCardId,
    this.onToggleExpand,
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
                    avatarBytes: userAvatarBytes,
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
                    feedBadgeCount: totalUnreadCount,
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
    if (feedItems.isEmpty) {
      return [
        const SizedBox(height: 12),
        _EmptyFeedStateCard(username: username),
      ];
    }

    final widgets = <Widget>[const SizedBox(height: 16)];

    for (var i = 0; i < feedItems.length; i++) {
      final item = feedItems[i];

      if (item is ConnectionFeedItem) {
        widgets.add(
          ConnectionCard(
            contactPeerId: item.contactPeerId,
            contactUsername: item.contactUsername,
            contactAvatarPath: item.contactAvatarPath,
            onSendMessage: onSendMessage != null
                ? () => onSendMessage!(item)
                : null,
          ),
        );
      } else if (item is ThreadFeedItem) {
        final isExpanded = expandedCardId == item.id;
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              bottom: item.isMultiMessage && !isExpanded ? 12 : 0,
            ),
            child: ThreadCard(
              thread: item,
              isExpanded: isExpanded,
              onToggleExpand: onToggleExpand != null
                  ? () => onToggleExpand!(item.id)
                  : null,
              onReply: onReplyToMessage != null
                  ? () => onReplyToMessage!(item.contactPeerId)
                  : null,
            ),
          ),
        );
      } else if (item is MessageFeedItem) {
        widgets.add(
          MessageFeedCard(
            contactPeerId: item.contactPeerId,
            contactUsername: item.contactUsername,
            messageText: item.messageText,
            messageTime: item.messageTime,
            unreadCount: item.unreadCount,
            onReply: onReplyToMessage != null
                ? () => onReplyToMessage!(item.contactPeerId)
                : null,
          ),
        );
      }

      if (i != feedItems.length - 1) {
        widgets.add(const SizedBox(height: 16));
      }
    }

    widgets.add(const SizedBox(height: 20));
    return widgets;
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
