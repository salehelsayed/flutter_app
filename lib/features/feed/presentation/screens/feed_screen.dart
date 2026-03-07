import 'dart:typed_data';

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

                            return SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.only(
                                left: horizontalPadding,
                                right: horizontalPadding,
                                bottom: 60 + bottomInset,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: _buildFeedCards(context),
                                    ),
                                  ),
                                ),
                              ),
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

  List<Widget> _buildFeedCards(BuildContext context) {
    if (feedItems.isEmpty) {
      if (!feedLoaded) return [];
      return [
        const SizedBox(height: 12),
        _EmptyFeedStateCard(username: username),
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

    final widgets = <Widget>[const SizedBox(height: 16)];

    // Build above-divider cards (unread/active threads)
    final aboveItems = [...aboveDivider];
    aboveItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    for (var i = 0; i < aboveItems.length; i++) {
      _addCardWidget(context, widgets, aboveItems[i]);
      if (i != aboveItems.length - 1 || belowDivider.isNotEmpty) {
        widgets.add(const SizedBox(height: 16));
      }
    }

    // Insert session divider when both sections have content
    if (aboveItems.isNotEmpty && belowDivider.isNotEmpty) {
      widgets.add(const SessionDivider());
    }

    // Build below-divider cards (connections + read/replied threads)
    belowDivider.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    for (var i = 0; i < belowDivider.length; i++) {
      _addCardWidget(context, widgets, belowDivider[i]);
      if (i != belowDivider.length - 1) {
        widgets.add(const SizedBox(height: 16));
      }
    }

    widgets.add(const SizedBox(height: 20));
    return widgets;
  }

  void _showReactionBar(BuildContext context, String messageId) {
    final allReactions = reactions[messageId] ?? [];
    final ownReaction = userPeerId != null
        ? allReactions
            .where((r) => r.senderPeerId == userPeerId)
            .firstOrNull
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

  void _addCardWidget(BuildContext context, List<Widget> widgets, FeedItem item) {
    if (item is GroupThreadFeedItem) {
      widgets.add(
        FeedCard(
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
        ),
      );
    } else if (item is ConnectionFeedItem) {
      if (item.introducedBy != null && userPeerId != null) {
        widgets.add(
          IntroductionConnectionCard(
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
          ),
        );
      } else {
        widgets.add(
          ConnectionCard(
            contactPeerId: item.contactPeerId,
            contactUsername: item.contactUsername,
            contactAvatarPath: item.contactAvatarPath,
            introducedBy: item.introducedBy,
            onSendMessage: onSendMessage != null
                ? () => onSendMessage!(item)
                : null,
            isBlocked: item.isBlocked,
          ),
        );
      }
    } else if (item is ThreadFeedItem) {
      widgets.add(
        FeedCard(
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
              ? (hasFocus) =>
                    onInputFocusChanged!(item.contactPeerId, hasFocus)
              : null,
          onQuoteReply: onQuoteReply != null
              ? (msgId) => onQuoteReply!(item.contactPeerId, msgId)
              : null,
          onAttach: onAttach != null
              ? () => onAttach!(item.contactPeerId)
              : null,
          reactions: reactions,
          ownPeerId: userPeerId,
          onMessageLongPress: onReactionSelected != null
              ? (msgId) => _showReactionBar(context, msgId)
              : null,
          onReactionTap: onReactionSelected != null
              ? (msgId, emoji) => onReactionSelected!(msgId, emoji)
              : null,
        ),
      );
    }
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
