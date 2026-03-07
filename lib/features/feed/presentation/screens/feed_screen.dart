import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/full_emoji_picker.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_bar.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/connection_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/introduction_connection_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_header.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/session_divider.dart';
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
  final bool feedLoaded;
  final ValueChanged<String>? onUsernameChanged;
  final P2PService? p2pService;
  final void Function(String) onSwitchView;
  final String activeTab;
  final void Function(ConnectionFeedItem)? onSendMessage;
  final void Function(String contactPeerId)? onReplyToMessage;
  final int totalUnreadCount;
  final String? expandedCardId;
  final void Function(String)? onToggleExpand;
  final void Function(String contactPeerId, String text)? onInlineSend;
  final void Function(String contactPeerId)? onViewFullConversation;
  final Map<String, String>? draftTexts;
  final String? activeFocusPeerId;
  final void Function(String contactPeerId, String text)? onDraftChanged;
  final void Function(String contactPeerId, bool hasFocus)? onInputFocusChanged;
  final Map<String, String>? activeQuoteMessageIds;
  final void Function(String contactPeerId, String messageId)? onQuoteReply;
  final void Function(String contactPeerId)? onClearQuote;
  final void Function(String contactPeerId)? onAttach;
  final VoidCallback? onAvatarTap;
  final SessionReplyTracker? sessionReplies;
  final Map<String, List<MessageReaction>> reactions;
  final ValueListenable<List<MessageReaction>> Function(String messageId)?
  reactionListenableForMessage;
  final void Function(String messageId, String emoji)? onReactionSelected;
  final void Function(GroupThreadFeedItem)? onGroupTap;
  final void Function(String groupId, String text)? onGroupInlineSend;

  const FeedScreen({
    super.key,
    required this.username,
    this.userAvatarBytes,
    this.userPeerId,
    required this.feedItems,
    this.feedLoaded = true,
    this.onUsernameChanged,
    this.p2pService,
    required this.onSwitchView,
    required this.activeTab,
    this.onSendMessage,
    this.onReplyToMessage,
    this.totalUnreadCount = 0,
    this.expandedCardId,
    this.onToggleExpand,
    this.onInlineSend,
    this.onViewFullConversation,
    this.draftTexts,
    this.activeFocusPeerId,
    this.onDraftChanged,
    this.onInputFocusChanged,
    this.activeQuoteMessageIds,
    this.onQuoteReply,
    this.onClearQuote,
    this.onAttach,
    this.onAvatarTap,
    this.sessionReplies,
    this.reactions = const {},
    this.reactionListenableForMessage,
    this.onReactionSelected,
    this.onGroupTap,
    this.onGroupInlineSend,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: AmbientBackground(
        child: Stack(
          children: [
            // Main content with top-only SafeArea
            SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding = constraints.maxWidth < 390
                      ? 14.0
                      : 18.0;

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
                          onAvatarTap: onAvatarTap,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, contentConstraints) {
                            final maxFeedWidth =
                                contentConstraints.maxWidth >= 900
                                ? 640.0
                                : contentConstraints.maxWidth >= 600
                                ? 560.0
                                : 460.0;
                            final centeredHorizontalPadding = math.max(
                              horizontalPadding,
                              (contentConstraints.maxWidth - maxFeedWidth) / 2,
                            );

                            return CustomScrollView(
                              key: const PageStorageKey<String>('feed-scroll'),
                              physics: const BouncingScrollPhysics(),
                              cacheExtent: 1200,
                              slivers: [
                                SliverPadding(
                                  padding: EdgeInsets.only(
                                    left: centeredHorizontalPadding,
                                    right: centeredHorizontalPadding,
                                    bottom: 60 + bottomInset,
                                  ),
                                  sliver: _buildFeedSliver(context),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            // Floating nav bar pinned to bottom
            if (activeFocusPeerId == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: bottomInset - 14,
                child: Center(
                  child: FeedNavigationBar(
                    activeTab: activeTab,
                    onSwitchView: onSwitchView,
                    feedBadgeCount: totalUnreadCount,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedSliver(BuildContext context) {
    final entries = _buildFeedEntries();
    if (entries.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildFeedEntry(context, entries[index]),
        childCount: entries.length,
        findChildIndexCallback: (key) => _findFeedEntryIndex(entries, key),
      ),
    );
  }

  List<_FeedEntry> _buildFeedEntries() {
    if (feedItems.isEmpty) {
      if (!feedLoaded) return const [];
      return [
        const _FeedEntry.spacer(height: 12),
        _FeedEntry.emptyState(username: username),
      ];
    }

    // Partition into above/below divider
    // Above: unread/active threads only
    // Below: connections + read/replied threads (sorted by timestamp)
    final aboveDivider = <FeedItem>[];
    final belowDivider = <FeedItem>[];

    for (final item in feedItems) {
      if (item is ConnectionFeedItem) {
        belowDivider.add(item);
      } else if (item is GroupThreadFeedItem) {
        if (item.conversationState == ConversationState.unread ||
            item.conversationState == ConversationState.active) {
          aboveDivider.add(item);
        } else {
          belowDivider.add(item);
        }
      } else if (item is ThreadFeedItem) {
        if (item.conversationState == ConversationState.unread ||
            item.conversationState == ConversationState.active) {
          aboveDivider.add(item);
        } else {
          belowDivider.add(item);
        }
      }
    }

    final entries = <_FeedEntry>[const _FeedEntry.spacer(height: 16)];

    // Build above-divider cards (unread/active threads)
    final aboveItems = [...aboveDivider];
    aboveItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    for (var i = 0; i < aboveItems.length; i++) {
      entries.add(_FeedEntry.item(aboveItems[i]));
      if (i != aboveItems.length - 1 || belowDivider.isNotEmpty) {
        entries.add(const _FeedEntry.spacer(height: 16));
      }
    }

    // Insert session divider when both sections have content
    if (aboveItems.isNotEmpty && belowDivider.isNotEmpty) {
      entries.add(const _FeedEntry.sessionDivider());
    }

    // Build below-divider cards (connections + read/replied threads)
    belowDivider.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    for (var i = 0; i < belowDivider.length; i++) {
      entries.add(_FeedEntry.item(belowDivider[i]));
      if (i != belowDivider.length - 1) {
        entries.add(const _FeedEntry.spacer(height: 16));
      }
    }

    entries.add(const _FeedEntry.spacer(height: 20));
    return entries;
  }

  Widget _buildFeedEntry(BuildContext context, _FeedEntry entry) {
    switch (entry.type) {
      case _FeedEntryType.item:
        return _buildFeedItemWidget(context, entry.item!);
      case _FeedEntryType.sessionDivider:
        return const SessionDivider();
      case _FeedEntryType.spacer:
        return SizedBox(height: entry.height);
      case _FeedEntryType.emptyState:
        return _EmptyFeedStateCard(username: entry.username!);
    }
  }

  int? _findFeedEntryIndex(List<_FeedEntry> entries, Key key) {
    if (key is! ValueKey<String>) {
      return null;
    }

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (entry.item?.id == key.value) {
        return index;
      }
    }
    return null;
  }

  void _showReactionBar(BuildContext context, String messageId) {
    final allReactions =
        reactionListenableForMessage?.call(messageId).value ??
        reactions[messageId] ??
        const [];
    final ownReaction = userPeerId != null
        ? allReactions.where((r) => r.senderPeerId == userPeerId).firstOrNull
        : null;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => ReactionBar(
        currentEmoji: ownReaction?.emoji,
        onReactionSelected: (emoji) {
          Navigator.of(dialogContext).pop();
          onReactionSelected?.call(messageId, emoji);
        },
        onPlusTap: () {
          Navigator.of(dialogContext).pop();
          _showFullPicker(context, messageId);
        },
        onDismiss: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  void _showFullPicker(BuildContext context, String messageId) async {
    final emoji = await showFullEmojiPicker(context);
    if (emoji != null) {
      onReactionSelected?.call(messageId, emoji);
    }
  }

  Widget _buildFeedItemWidget(BuildContext context, FeedItem item) {
    if (item is GroupThreadFeedItem) {
      return FeedCard(
        key: ValueKey(item.id),
        thread: item,
        isExpanded: expandedCardId == item.id,
        onToggleExpand: onToggleExpand != null
            ? () => onToggleExpand!(item.id)
            : null,
        onInlineSend: onGroupInlineSend != null
            ? (text) => onGroupInlineSend!(item.groupId, text)
            : null,
        onViewFullConversation: onGroupTap != null
            ? () => onGroupTap!(item)
            : null,
      );
    }
    if (item is ConnectionFeedItem) {
      if (item.introducedBy != null && userPeerId != null) {
        return IntroductionConnectionCard(
          key: ValueKey(item.id),
          ownPeerId: userPeerId!,
          ownUsername: username,
          contactPeerId: item.contactPeerId,
          contactUsername: item.contactUsername,
          introducedBy: item.introducedBy!,
          introducedByPeerId: item.introducedByPeerId,
          onSendMessage: onSendMessage != null
              ? () => onSendMessage!(item)
              : null,
          isBlocked: item.isBlocked,
        );
      }
      return ConnectionCard(
        key: ValueKey(item.id),
        contactPeerId: item.contactPeerId,
        contactUsername: item.contactUsername,
        contactAvatarPath: item.contactAvatarPath,
        introducedBy: item.introducedBy,
        onSendMessage: onSendMessage != null
            ? () => onSendMessage!(item)
            : null,
        isBlocked: item.isBlocked,
      );
    }
    if (item is ThreadFeedItem) {
      return FeedCard(
        key: ValueKey(item.id),
        thread: item,
        sessionReply: sessionReplies?.get(item.contactPeerId),
        isExpanded: expandedCardId == item.id,
        onToggleExpand: onToggleExpand != null
            ? () => onToggleExpand!(item.id)
            : null,
        onInlineSend: onInlineSend != null
            ? (text) => onInlineSend!(item.contactPeerId, text)
            : null,
        onViewFullConversation: onViewFullConversation != null
            ? () => onViewFullConversation!(item.contactPeerId)
            : null,
        initialText: draftTexts?[item.contactPeerId] ?? '',
        shouldRequestFocus: activeFocusPeerId == item.contactPeerId,
        onDraftChanged: onDraftChanged != null
            ? (text) => onDraftChanged!(item.contactPeerId, text)
            : null,
        onInputFocusChanged: onInputFocusChanged != null
            ? (hasFocus) => onInputFocusChanged!(item.contactPeerId, hasFocus)
            : null,
        onQuoteReply: onQuoteReply != null
            ? (msgId) => onQuoteReply!(item.contactPeerId, msgId)
            : null,
        onAttach: onAttach != null ? () => onAttach!(item.contactPeerId) : null,
        reactions: reactions,
        reactionListenableForMessage: reactionListenableForMessage,
        ownPeerId: userPeerId,
        onMessageLongPress: onReactionSelected != null
            ? (msgId) => _showReactionBar(context, msgId)
            : null,
        onReactionTap: onReactionSelected != null
            ? (msgId, emoji) => onReactionSelected!(msgId, emoji)
            : null,
      );
    }

    throw ArgumentError.value(
      item,
      'item',
      'Unsupported feed item type ${item.runtimeType}',
    );
  }
}

enum _FeedEntryType { item, sessionDivider, spacer, emptyState }

@immutable
class _FeedEntry {
  final _FeedEntryType type;
  final FeedItem? item;
  final double? height;
  final String? username;

  const _FeedEntry._({
    required this.type,
    this.item,
    this.height,
    this.username,
  });

  const _FeedEntry.item(FeedItem item)
    : this._(type: _FeedEntryType.item, item: item);

  const _FeedEntry.sessionDivider()
    : this._(type: _FeedEntryType.sessionDivider);

  const _FeedEntry.spacer({required double height})
    : this._(type: _FeedEntryType.spacer, height: height);

  const _FeedEntry.emptyState({required String username})
    : this._(type: _FeedEntryType.emptyState, username: username);
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
