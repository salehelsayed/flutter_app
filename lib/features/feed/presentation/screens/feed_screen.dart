import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/full_emoji_picker.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/connection_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/introduction_connection_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_header.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/session_divider.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

/// Pure UI Feed screen.
///
/// Displays a fixed header, a responsive feed content area, and a pinned bottom
/// navigation bar.
class FeedScreen extends StatelessWidget {
  static const editModeBannerKey = ValueKey('feed-edit-mode-banner');
  static const cancelEditKey = ValueKey('feed-cancel-edit-action');

  final String username;
  final Uint8List? userAvatarBytes;
  final String? userPeerId;
  final List<FeedItem> feedItems;
  final ValueListenable<List<FeedItem>>? feedItemsListenable;
  final bool feedLoaded;
  final ValueChanged<String>? onUsernameChanged;
  final P2PService? p2pService;
  final void Function(String) onSwitchView;
  final String activeTab;
  final void Function(ConnectionFeedItem)? onSendMessage;
  final void Function(String contactPeerId)? onReplyToMessage;
  final int totalUnreadCount;
  final ValueListenable<int>? totalUnreadCountListenable;
  final int orbitBadgeCount;
  final ValueListenable<int>? orbitBadgeCountListenable;
  final String? expandedCardId;
  final void Function(String)? onToggleExpand;
  final void Function(String contactPeerId, String text)? onInlineSend;
  final void Function(String contactPeerId)? onViewFullConversation;
  final Map<String, String>? draftTexts;
  final String? activeFocusPeerId;
  final String? pendingViewportFollowContactPeerId;
  final int viewportFollowRequestId;
  final void Function(String contactPeerId, String text)? onDraftChanged;
  final void Function(String contactPeerId, bool hasFocus)? onInputFocusChanged;
  final String? editingContactPeerId;
  final void Function(String contactPeerId, String messageId)? onEditMessage;
  final void Function(String contactPeerId, String messageId)? onDeleteMessage;
  final void Function(String contactPeerId)? onCancelEdit;
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
  final void Function(GroupThreadFeedItem)? onGroupAttach;
  final void Function(String groupId, String messageId, String emoji)?
  onGroupReactionTap;
  final void Function(String groupId, String messageId, String emoji)?
  onGroupReactionSelected;

  const FeedScreen({
    super.key,
    required this.username,
    this.userAvatarBytes,
    this.userPeerId,
    required this.feedItems,
    this.feedItemsListenable,
    this.feedLoaded = true,
    this.onUsernameChanged,
    this.p2pService,
    required this.onSwitchView,
    required this.activeTab,
    this.onSendMessage,
    this.onReplyToMessage,
    this.totalUnreadCount = 0,
    this.totalUnreadCountListenable,
    this.orbitBadgeCount = 0,
    this.orbitBadgeCountListenable,
    this.expandedCardId,
    this.onToggleExpand,
    this.onInlineSend,
    this.onViewFullConversation,
    this.draftTexts,
    this.activeFocusPeerId,
    this.pendingViewportFollowContactPeerId,
    this.viewportFollowRequestId = 0,
    this.onDraftChanged,
    this.onInputFocusChanged,
    this.editingContactPeerId,
    this.onEditMessage,
    this.onDeleteMessage,
    this.onCancelEdit,
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
    this.onGroupAttach,
    this.onGroupReactionTap,
    this.onGroupReactionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final shouldHideNavigationBar = _shouldHideNavigationBar(context);

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
                            final feedItemsListenable =
                                this.feedItemsListenable;
                            if (feedItemsListenable == null) {
                              return _buildFeedContent(
                                context: context,
                                horizontalPadding: horizontalPadding,
                                contentConstraints: contentConstraints,
                                bottomInset: bottomInset,
                                items: feedItems,
                              );
                            }

                            return ValueListenableBuilder<List<FeedItem>>(
                              valueListenable: feedItemsListenable,
                              builder: (context, items, child) =>
                                  _buildFeedContent(
                                    context: context,
                                    horizontalPadding: horizontalPadding,
                                    contentConstraints: contentConstraints,
                                    bottomInset: bottomInset,
                                    items: items,
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
            if (!shouldHideNavigationBar)
              Positioned(
                left: 0,
                right: 0,
                bottom: bottomInset - 14,
                child: Center(child: _buildNavigationBar()),
              ),
          ],
        ),
      ),
    );
  }

  bool _shouldHideNavigationBar(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return activeFocusPeerId != null && keyboardVisible;
  }

  Widget _buildFeedContent({
    required BuildContext context,
    required double horizontalPadding,
    required BoxConstraints contentConstraints,
    required double bottomInset,
    required List<FeedItem> items,
  }) {
    final maxFeedWidth = contentConstraints.maxWidth >= 900
        ? 640.0
        : contentConstraints.maxWidth >= 600
        ? 560.0
        : 460.0;
    final centeredHorizontalPadding = math.max(
      horizontalPadding,
      (contentConstraints.maxWidth - maxFeedWidth) / 2,
    );

    return _FeedScrollableContent(
      horizontalPadding: centeredHorizontalPadding,
      bottomInset: bottomInset,
      entries: _buildFeedEntries(items),
      loadingSliver: _buildLoadingSliver(),
      entryBuilder: _buildFeedEntry,
      pendingViewportFollowContactPeerId: pendingViewportFollowContactPeerId,
      viewportFollowRequestId: viewportFollowRequestId,
    );
  }

  Widget _buildNavigationBar() {
    final unreadCountListenable = totalUnreadCountListenable;
    final orbitCountListenable = orbitBadgeCountListenable;
    if (unreadCountListenable == null && orbitCountListenable == null) {
      return FeedNavigationBar(
        activeTab: activeTab,
        onSwitchView: onSwitchView,
        feedBadgeCount: totalUnreadCount,
        orbitBadgeCount: orbitBadgeCount,
      );
    }

    if (unreadCountListenable == null) {
      return ValueListenableBuilder<int>(
        valueListenable: orbitCountListenable!,
        builder: (context, orbitCount, child) => FeedNavigationBar(
          activeTab: activeTab,
          onSwitchView: onSwitchView,
          feedBadgeCount: totalUnreadCount,
          orbitBadgeCount: orbitCount,
        ),
      );
    }

    if (orbitCountListenable == null) {
      return ValueListenableBuilder<int>(
        valueListenable: unreadCountListenable,
        builder: (context, unreadCount, child) => FeedNavigationBar(
          activeTab: activeTab,
          onSwitchView: onSwitchView,
          feedBadgeCount: unreadCount,
          orbitBadgeCount: orbitBadgeCount,
        ),
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: unreadCountListenable,
      builder: (context, unreadCount, child) => ValueListenableBuilder<int>(
        valueListenable: orbitCountListenable,
        builder: (context, orbitCount, nestedChild) => FeedNavigationBar(
          activeTab: activeTab,
          onSwitchView: onSwitchView,
          feedBadgeCount: unreadCount,
          orbitBadgeCount: orbitCount,
        ),
      ),
    );
  }

  Widget _buildLoadingSliver() {
    return SliverList(
      delegate: SliverChildListDelegate.fixed([
        const SizedBox(height: 16),
        const _FeedLoadingStatusCard(),
        const SizedBox(height: 16),
        const _FeedLoadingCard(index: 0),
        const SizedBox(height: 16),
        const _FeedLoadingCard(index: 1),
        const SizedBox(height: 16),
        const _FeedLoadingCard(index: 2),
        const SizedBox(height: 20),
      ]),
    );
  }

  List<_FeedEntry> _buildFeedEntries(List<FeedItem> items) {
    if (items.isEmpty) {
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

    for (final item in items) {
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

  void _showMessageContextOverlay(
    BuildContext context,
    ThreadFeedItem thread,
    ThreadMessage message,
    BuildContext bubbleContext,
  ) {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final renderObject = bubbleContext.findRenderObject();
    Rect anchorRect = Rect.fromCenter(
      center: MediaQuery.of(context).size.center(Offset.zero),
      width: 0,
      height: 0,
    );
    if (renderObject is RenderBox && renderObject.hasSize) {
      final topLeft = renderObject.localToGlobal(Offset.zero);
      anchorRect = topLeft & renderObject.size;
    }

    final allReactions =
        reactionListenableForMessage?.call(message.id).value ??
        reactions[message.id] ??
        const [];
    final ownReaction = userPeerId != null
        ? allReactions.where((r) => r.senderPeerId == userPeerId).firstOrNull
        : null;
    final hasCopyAction = !message.isDeleted && message.text.trim().isNotEmpty;
    final hasEditAction = _canEditMessage(thread, message);
    final hasDeleteAction = _canDeleteMessage(message);

    showDialog(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => MessageContextOverlay(
        anchorRect: anchorRect,
        selectedMessage: _buildOverlaySelectedBubble(
          context,
          thread,
          message,
          allReactions,
        ),
        currentEmoji: ownReaction?.emoji,
        showCopyAction: hasCopyAction,
        showEditAction: hasEditAction,
        showDeleteAction: hasDeleteAction,
        onDismiss: () => Navigator.of(dialogContext).pop(),
        onReactionSelected: (emoji) {
          Navigator.of(dialogContext).pop();
          onReactionSelected?.call(message.id, emoji);
        },
        onPlusTap: () {
          Navigator.of(dialogContext).pop();
          _showFullPicker(context, message.id);
        },
        onReplyTap: () {
          Navigator.of(dialogContext).pop();
          onQuoteReply?.call(thread.contactPeerId, message.id);
        },
        onEditTap: hasEditAction
            ? () {
                Navigator.of(dialogContext).pop();
                onEditMessage?.call(thread.contactPeerId, message.id);
              }
            : null,
        onCopyTap: hasCopyAction
            ? () async {
                Navigator.of(dialogContext).pop();
                await _copyMessageText(context, message.text);
              }
            : null,
        onDeleteTap: hasDeleteAction
            ? () {
                Navigator.of(dialogContext).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  onDeleteMessage?.call(thread.contactPeerId, message.id);
                });
              }
            : null,
      ),
    );
  }

  MessageBubble _buildOverlaySelectedBubble(
    BuildContext context,
    CardThreadFeedItem thread,
    ThreadMessage message,
    List<MessageReaction> reactions,
  ) {
    final (quotedText, isQuoteUnavailable) = _resolveQuotedText(
      thread,
      message,
    );

    return MessageBubble(
      text: message.text,
      time: message.time,
      isUnread: message.isUnread,
      isIncoming: message.isIncoming,
      isDeleted: message.isDeleted,
      status: message.status,
      isEdited: message.isEdited,
      senderPeerId: message.isIncoming
          ? (message.senderPeerId ?? thread.displayId)
          : null,
      senderLabel: message.isIncoming
          ? (message.senderUsername ?? thread.displayName)
          : AppLocalizations.of(context)!.feed_you,
      quotedText: quotedText,
      isQuoteUnavailable: isQuoteUnavailable,
      media: message.media,
      reactions: message.isDeleted ? const [] : reactions,
      ownPeerId: userPeerId,
    );
  }

  (String?, bool) _resolveQuotedText(
    CardThreadFeedItem thread,
    ThreadMessage message,
  ) {
    final quotedMessageId = message.quotedMessageId;
    if (quotedMessageId == null) {
      return (null, false);
    }

    final quoted = thread.messages
        .where((candidate) => candidate.id == quotedMessageId)
        .firstOrNull;
    if (quoted == null || quoted.isDeleted) {
      return ('Message unavailable', true);
    }
    if (quoted.text.isNotEmpty) {
      return (quoted.text, false);
    }
    if (quoted.media.isNotEmpty) {
      return (mediaPreviewText(quoted.media), false);
    }
    return ('Message unavailable', true);
  }

  bool _canEditMessage(ThreadFeedItem thread, ThreadMessage message) {
    if (onEditMessage == null) return false;
    if (message.isDeleted) return false;
    if (message.isIncoming || message.text.trim().isEmpty) return false;
    return thread.lastSentMessage?.id == message.id;
  }

  bool _canDeleteMessage(ThreadMessage message) {
    if (onDeleteMessage == null) return false;
    return !message.isDeleted;
  }

  Future<void> _copyMessageText(BuildContext context, String text) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final copiedLabel = AppLocalizations.of(
      context,
    )!.conversation_context_copied;
    await Clipboard.setData(ClipboardData(text: text));
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(copiedLabel),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showFullPicker(BuildContext context, String messageId) async {
    final emoji = await showFullEmojiPicker(context);
    if (emoji != null) {
      onReactionSelected?.call(messageId, emoji);
    }
  }

  void _showGroupMessageContextOverlay(
    BuildContext context,
    GroupThreadFeedItem thread,
    ThreadMessage message,
    BuildContext bubbleContext,
  ) {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final renderObject = bubbleContext.findRenderObject();
    Rect anchorRect = Rect.fromCenter(
      center: MediaQuery.of(context).size.center(Offset.zero),
      width: 0,
      height: 0,
    );
    if (renderObject is RenderBox && renderObject.hasSize) {
      final topLeft = renderObject.localToGlobal(Offset.zero);
      anchorRect = topLeft & renderObject.size;
    }

    final allReactions =
        reactionListenableForMessage?.call(message.id).value ??
        reactions[message.id] ??
        const [];
    final ownReaction = userPeerId != null
        ? allReactions.where((r) => r.senderPeerId == userPeerId).firstOrNull
        : null;
    final showReplyAction = thread.canWrite && onQuoteReply != null;
    final showCopyAction = message.text.trim().isNotEmpty;
    final showReactionBar = thread.canReact && onGroupReactionSelected != null;
    if (!showReplyAction && !showCopyAction && !showReactionBar) {
      return;
    }

    showDialog(
      context: bubbleContext,
      useSafeArea: false,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => MessageContextOverlay(
        anchorRect: anchorRect,
        selectedMessage: _buildOverlaySelectedBubble(
          context,
          thread,
          message,
          allReactions,
        ),
        currentEmoji: ownReaction?.emoji,
        onDismiss: () => Navigator.of(dialogContext).pop(),
        showReactionBar: showReactionBar,
        showReplyAction: showReplyAction,
        showCopyAction: showCopyAction,
        onReactionSelected: showReactionBar
            ? (emoji) {
                Navigator.of(dialogContext).pop();
                onGroupReactionSelected?.call(
                  thread.groupId,
                  message.id,
                  emoji,
                );
              }
            : null,
        onPlusTap: showReactionBar
            ? () {
                Navigator.of(dialogContext).pop();
                _showGroupFullPicker(context, thread.groupId, message.id);
              }
            : null,
        onReplyTap: showReplyAction
            ? () {
                Navigator.of(dialogContext).pop();
                onQuoteReply?.call('group:${thread.groupId}', message.id);
              }
            : null,
        onCopyTap: showCopyAction
            ? () async {
                Navigator.of(dialogContext).pop();
                await _copyMessageText(context, message.text);
              }
            : null,
      ),
    );
  }

  void _showGroupFullPicker(
    BuildContext context,
    String groupId,
    String messageId,
  ) async {
    final emoji = await showFullEmojiPicker(context);
    if (emoji != null) {
      onGroupReactionSelected?.call(groupId, messageId, emoji);
    }
  }

  Widget _buildFeedItemWidget(BuildContext context, FeedItem item) {
    if (item is GroupThreadFeedItem) {
      final activeQuoteMessageId =
          activeQuoteMessageIds?['group:${item.groupId}'];
      final groupDraftKey = 'group:${item.groupId}';
      final canWrite = item.canWrite;
      final canReact = item.canReact;
      final hasCopyableMessage = item.messages.any(
        (message) => message.text.trim().isNotEmpty,
      );
      return FeedCard(
        thread: item,
        canWrite: canWrite,
        sessionReply: sessionReplies?.get('group:${item.groupId}'),
        isExpanded: expandedCardId == item.id,
        onToggleExpand: onToggleExpand != null
            ? () => onToggleExpand!(item.id)
            : null,
        onInlineSend: canWrite && onGroupInlineSend != null
            ? (text) => onGroupInlineSend!(item.groupId, text)
            : null,
        onViewFullConversation: onGroupTap != null
            ? () => onGroupTap!(item)
            : null,
        initialText: draftTexts?[groupDraftKey] ?? '',
        activeQuoteText: canWrite
            ? _resolveActiveQuoteText(item, activeQuoteMessageId)
            : null,
        onDraftChanged: onDraftChanged != null
            ? (text) => onDraftChanged!(groupDraftKey, text)
            : null,
        onQuoteReply: canWrite && onQuoteReply != null
            ? (msgId) => onQuoteReply!('group:${item.groupId}', msgId)
            : null,
        onClearQuote: canWrite && onClearQuote != null
            ? () => onClearQuote!('group:${item.groupId}')
            : null,
        onAttach: canWrite && onGroupAttach != null
            ? () => onGroupAttach!(item)
            : null,
        reactions: reactions,
        reactionListenableForMessage: reactionListenableForMessage,
        ownPeerId: userPeerId,
        onMessageLongPress:
            (canReact && onGroupReactionSelected != null) ||
                (canWrite && onQuoteReply != null) ||
                hasCopyableMessage
            ? (message, bubbleContext) => _showGroupMessageContextOverlay(
                context,
                item,
                message,
                bubbleContext,
              )
            : null,
        onReactionTap: onGroupReactionTap != null
            ? (msgId, emoji) => onGroupReactionTap!(item.groupId, msgId, emoji)
            : null,
      );
    }
    if (item is ConnectionFeedItem) {
      if (item.introducedBy != null && userPeerId != null) {
        return IntroductionConnectionCard(
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
      final activeQuoteMessageId = activeQuoteMessageIds?[item.contactPeerId];
      return FeedCard(
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
        isEditingMessage: editingContactPeerId == item.contactPeerId,
        onCancelEdit:
            editingContactPeerId == item.contactPeerId && onCancelEdit != null
            ? () => onCancelEdit!(item.contactPeerId)
            : null,
        activeQuoteText: _resolveActiveQuoteText(item, activeQuoteMessageId),
        onQuoteReply: onQuoteReply != null
            ? (msgId) => onQuoteReply!(item.contactPeerId, msgId)
            : null,
        onClearQuote: onClearQuote != null
            ? () => onClearQuote!(item.contactPeerId)
            : null,
        onAttach: onAttach != null ? () => onAttach!(item.contactPeerId) : null,
        reactions: reactions,
        reactionListenableForMessage: reactionListenableForMessage,
        ownPeerId: userPeerId,
        onMessageLongPress:
            onReactionSelected != null ||
                onQuoteReply != null ||
                onEditMessage != null ||
                onDeleteMessage != null
            ? (message, bubbleContext) => _showMessageContextOverlay(
                context,
                item,
                message,
                bubbleContext,
              )
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

  String? _resolveActiveQuoteText(
    CardThreadFeedItem item,
    String? activeQuoteMessageId,
  ) {
    if (activeQuoteMessageId == null) return null;

    final quoted = item.messages
        .where((message) => message.id == activeQuoteMessageId)
        .firstOrNull;
    if (quoted == null) return 'Message unavailable';
    if (quoted.isDeleted) return 'Message unavailable';
    if (quoted.text.isNotEmpty) return quoted.text;
    if (quoted.media.isNotEmpty) return mediaPreviewText(quoted.media);
    return 'Message unavailable';
  }
}

class _FeedScrollableContent extends StatefulWidget {
  final double horizontalPadding;
  final double bottomInset;
  final List<_FeedEntry> entries;
  final Widget loadingSliver;
  final Widget Function(BuildContext context, _FeedEntry entry) entryBuilder;
  final String? pendingViewportFollowContactPeerId;
  final int viewportFollowRequestId;

  const _FeedScrollableContent({
    required this.horizontalPadding,
    required this.bottomInset,
    required this.entries,
    required this.loadingSliver,
    required this.entryBuilder,
    this.pendingViewportFollowContactPeerId,
    this.viewportFollowRequestId = 0,
  });

  @override
  State<_FeedScrollableContent> createState() => _FeedScrollableContentState();
}

class _FeedScrollableContentState extends State<_FeedScrollableContent> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();
  final Map<String, GlobalKey> _threadCardKeys = <String, GlobalKey>{};

  GlobalKey _threadCardKey(String itemId) {
    return _threadCardKeys.putIfAbsent(
      itemId,
      () => GlobalKey(debugLabel: 'feed-thread-$itemId'),
    );
  }

  @override
  void didUpdateWidget(covariant _FeedScrollableContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewportFollowRequestId == oldWidget.viewportFollowRequestId) {
      return;
    }
    final contactPeerId = widget.pendingViewportFollowContactPeerId;
    if (contactPeerId == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reorientToThreadCard(contactPeerId);
    });
  }

  Future<void> _reorientToThreadCard(String contactPeerId) async {
    final target = _targetThreadForContact(contactPeerId);
    if (target == null) {
      return;
    }

    final directContext = _threadCardKeys[target.id]?.currentContext;
    if (directContext != null) {
      await _ensureVisible(directContext);
      return;
    }

    if (!_scrollController.hasClients) {
      return;
    }

    final estimatedOffset = _estimatedOffsetForIndex(target.index);
    await _scrollController.animateTo(
      estimatedOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mountedContext = _threadCardKeys[target.id]?.currentContext;
      if (mountedContext == null) {
        return;
      }
      _ensureVisible(mountedContext);
    });
  }

  Future<void> _ensureVisible(BuildContext context) {
    return Scrollable.ensureVisible(
      context,
      alignment: 0.18,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  ({String id, int index})? _targetThreadForContact(String contactPeerId) {
    for (var index = 0; index < widget.entries.length; index++) {
      final item = widget.entries[index].item;
      if (item is ThreadFeedItem && item.contactPeerId == contactPeerId) {
        return (id: item.id, index: index);
      }
    }
    return null;
  }

  double _estimatedOffsetForIndex(int targetIndex) {
    final position = _scrollController.position;
    final anchors = _visibleThreadAnchors();
    final estimatedEntryExtent = _estimatedEntryExtent(anchors);
    final nearestAnchor = anchors.isEmpty
        ? null
        : anchors.reduce(
            (best, candidate) =>
                (candidate.index - targetIndex).abs() <
                    (best.index - targetIndex).abs()
                ? candidate
                : best,
          );
    final rawOffset =
        ((nearestAnchor?.absoluteOffset ?? position.pixels) +
            ((targetIndex - (nearestAnchor?.index ?? 0)) *
                estimatedEntryExtent)) -
        (position.viewportDimension * 0.18);
    return rawOffset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  List<({int index, double absoluteOffset})> _visibleThreadAnchors() {
    if (!_scrollController.hasClients) {
      return const [];
    }
    final viewportContext = _viewportKey.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    if (viewportRenderObject is! RenderBox) {
      return const [];
    }

    final anchors = <({int index, double absoluteOffset})>[];
    for (var index = 0; index < widget.entries.length; index++) {
      final item = widget.entries[index].item;
      if (item is! ThreadFeedItem) {
        continue;
      }
      final context = _threadCardKeys[item.id]?.currentContext;
      if (context == null) {
        continue;
      }
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }
      final relativeTop = renderObject.localToGlobal(
        Offset.zero,
        ancestor: viewportRenderObject,
      );
      anchors.add((
        index: index,
        absoluteOffset: _scrollController.position.pixels + relativeTop.dy,
      ));
    }
    anchors.sort((a, b) => a.index.compareTo(b.index));
    return anchors;
  }

  double _estimatedEntryExtent(
    List<({int index, double absoluteOffset})> anchors,
  ) {
    if (anchors.length < 2) {
      return 72;
    }

    final perIndexExtents = <double>[];
    for (var index = 1; index < anchors.length; index++) {
      final previous = anchors[index - 1];
      final current = anchors[index];
      final deltaIndex = current.index - previous.index;
      if (deltaIndex <= 0) {
        continue;
      }
      perIndexExtents.add(
        (current.absoluteOffset - previous.absoluteOffset) / deltaIndex,
      );
    }

    if (perIndexExtents.isEmpty) {
      return 72;
    }

    final averageExtent =
        perIndexExtents.reduce((sum, extent) => sum + extent) /
        perIndexExtents.length;
    return averageExtent.clamp(48, 180).toDouble();
  }

  int? _findFeedEntryIndex(Key key) {
    if (key is! ValueKey<String>) {
      return null;
    }

    for (var index = 0; index < widget.entries.length; index++) {
      final entry = widget.entries[index];
      if (entry.item?.id == key.value) {
        return index;
      }
    }
    return null;
  }

  Widget _buildWrappedEntry(BuildContext context, _FeedEntry entry) {
    final child = widget.entryBuilder(context, entry);
    final item = entry.item;
    if (item == null) {
      return child;
    }

    Widget wrappedChild = child;
    if (item is ThreadFeedItem) {
      wrappedChild = SizedBox(key: _threadCardKey(item.id), child: child);
    }

    return KeyedSubtree(key: ValueKey<String>(item.id), child: wrappedChild);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sliver = widget.entries.isEmpty
        ? widget.loadingSliver
        : SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _buildWrappedEntry(context, widget.entries[index]),
              childCount: widget.entries.length,
              findChildIndexCallback: _findFeedEntryIndex,
            ),
          );

    return SizedBox(
      key: _viewportKey,
      child: CustomScrollView(
        key: const PageStorageKey<String>('feed-scroll'),
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        cacheExtent: 1200,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(
              left: widget.horizontalPadding,
              right: widget.horizontalPadding,
              bottom: 60 + widget.bottomInset,
            ),
            sliver: sliver,
          ),
        ],
      ),
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

class _FeedLoadingCard extends StatelessWidget {
  final int index;

  const _FeedLoadingCard({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('feed-loading-card-$index'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color.fromRGBO(24, 26, 32, 0.6),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _FeedLoadingBar(widthFactor: 0.34, height: 16),
          SizedBox(height: 14),
          _FeedLoadingBar(widthFactor: 0.82),
          SizedBox(height: 10),
          _FeedLoadingBar(widthFactor: 0.66),
          SizedBox(height: 18),
          _FeedLoadingBar(widthFactor: 0.48, height: 38),
        ],
      ),
    );
  }
}

class _FeedLoadingStatusCard extends StatelessWidget {
  const _FeedLoadingStatusCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('feed-loading-status'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color.fromRGBO(16, 18, 24, 0.78),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.12)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: Color.fromRGBO(255, 255, 255, 0.78),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Loading Feed...',
                  style: TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.92),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Your recent threads are still syncing.',
                  style: TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.62),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedLoadingBar extends StatelessWidget {
  final double widthFactor;
  final double height;

  const _FeedLoadingBar({required this.widthFactor, this.height = 12});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          color: const Color.fromRGBO(255, 255, 255, 0.11),
        ),
      ),
    );
  }
}
