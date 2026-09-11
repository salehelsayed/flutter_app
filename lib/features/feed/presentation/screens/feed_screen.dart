import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/feed_letter.dart';
import 'package:flutter_app/features/feed/domain/models/feed_session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/caught_up_empty_state.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_composer.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_header.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_swipe_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_group.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_one_to_one.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_system.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Pure UI Feed screen — 134-P5 "letters" pending-reply inbox.
///
/// Renders the feed as a flat list of letter cards (1:1 / group / system).
/// Tapping a card FOCUSES it: the focused card stays opaque/expanded while all
/// other cards collapse + fade out, the screen-level [FeedComposer] appears,
/// and the feed-local navigation bar fades away (independent of the keyboard).
class FeedScreen extends StatefulWidget {
  // ── Identity / header ──────────────────────────────────────────────────
  final String username;
  final String? userPeerId;
  final ValueChanged<String>? onUsernameChanged;
  final P2PService? p2pService;

  // ── Feed data ──────────────────────────────────────────────────────────
  final List<FeedItem> feedItems;
  final ValueListenable<List<FeedItem>>? feedItemsListenable;
  final bool feedLoaded;

  // ── Shell / nav ────────────────────────────────────────────────────────
  final void Function(String) onSwitchView;
  final String activeTab;
  final int totalUnreadCount;
  final ValueListenable<int>? totalUnreadCountListenable;
  final int orbitBadgeCount;
  final ValueListenable<int>? orbitBadgeCountListenable;

  // ── Background ─────────────────────────────────────────────────────────
  final BackgroundPreference backgroundPreference;
  final BackgroundReadableTone? readableToneOverride;

  // ── System "tap to say hi" (pre-bound at the call site) ─────────────────
  final void Function(ConnectionFeedItem)? onSendMessage;

  // ── Open full conversation (1:1 by peerId, group routed by item) ────────
  final void Function(String contactPeerId)? onOpenFullConversation;
  final void Function(GroupThreadFeedItem)? onGroupTap;

  // ── Focus + composer (134-P5) ──────────────────────────────────────────
  /// The focused thread id, or null when nothing is focused. Encodes:
  /// 1:1 = contactPeerId, group = `group:<groupId>`, system = contactPeerId.
  final String? focusedId;
  final void Function(String threadId)? onFocusCard;
  final VoidCallback? onClearFocus;
  final void Function(String threadId, String text)? onComposerSend;
  final void Function(String threadId, String text)? onComposerDraftChanged;
  /// The host retains this draft when the focused composer is unmounted.
  final String composerDraft;

  /// Outgoing replies sent during the current focus session, keyed by the same
  /// thread id encoding as [focusedId]. Drives the append-stay green bubbles
  /// and the never-silent retry affordance.
  final Map<String, List<FeedSessionReply>> sessionReplies;

  /// Re-invokes the send for a failed/pending session reply (TC-30 retry).
  final void Function(String threadId, FeedSessionReply reply)? onRetrySend;

  // ── Swipe contract (P6 wires the gestures to these) ────────────────────
  final void Function(String threadId)? onSwipeCommit;
  final void Function(String threadId)? onSwipeDismiss;
  final void Function(String threadId)? onUndoDismiss;

  /// 134-P6 gesture arena (TC-35): the feed tells the host (feed_wired) when a
  /// card swipe is live so the screen-level Feed↔Orbit host swipe yields the
  /// gesture (true on horizontal drag start, false on settle).
  final void Function(bool active)? onCardSwipeActive;

  const FeedScreen({
    super.key,
    required this.username,
    this.userPeerId,
    required this.feedItems,
    this.feedItemsListenable,
    this.feedLoaded = true,
    this.onUsernameChanged,
    this.p2pService,
    required this.onSwitchView,
    required this.activeTab,
    this.onSendMessage,
    this.totalUnreadCount = 0,
    this.totalUnreadCountListenable,
    this.orbitBadgeCount = 0,
    this.orbitBadgeCountListenable,
    this.onOpenFullConversation,
    this.onGroupTap,
    this.focusedId,
    this.onFocusCard,
    this.onClearFocus,
    this.onComposerSend,
    this.onComposerDraftChanged,
    this.composerDraft = '',
    this.sessionReplies = const {},
    this.onRetrySend,
    this.onSwipeCommit,
    this.onSwipeDismiss,
    this.onUndoDismiss,
    this.onCardSwipeActive,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
    this.readableToneOverride,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  bool get _isFocused => widget.focusedId != null;

  /// 134 §7 reduced-motion: motion is disabled when the platform requests
  /// either `disableAnimations` or `accessibleNavigation`. Cached in
  /// [didChangeDependencies] so [build]/the entry builders read a plain bool.
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mq = MediaQuery.of(context);
    _reduceMotion = mq.disableAnimations || mq.accessibleNavigation;
  }

  /// Collapses a motion [Duration] to zero under reduced motion. Threaded
  /// through EVERY feed-local animation so each becomes instant (134 §7).
  Duration _motion(Duration d) => _reduceMotion ? Duration.zero : d;

  /// The thread id for a feed item using the same encoding as [focusedId].
  String? _threadIdFor(FeedItem item) {
    if (item is GroupThreadFeedItem) return 'group:${item.groupId}';
    if (item is ConnectionFeedItem) return item.contactPeerId;
    if (item is ThreadFeedItem) return item.contactPeerId;
    return null;
  }

  /// The human display name for a feed item (used by the Undo SnackBar copy).
  String _displayNameFor(FeedItem item) {
    if (item is GroupThreadFeedItem) return item.groupName;
    if (item is ConnectionFeedItem) return item.contactUsername;
    if (item is ThreadFeedItem) return item.contactUsername;
    return '';
  }

  /// Maps the focused thread id back to its feed item (group "open full
  /// conversation" routes by item, not by id).
  FeedItem? _focusedItem(List<FeedItem> items) {
    final focusedId = widget.focusedId;
    if (focusedId == null) return null;
    for (final item in items) {
      if (_threadIdFor(item) == focusedId) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        if (_isFocused) widget.onClearFocus?.call();
      },
      behavior: HitTestBehavior.translucent,
      child: AmbientBackground(
        preference: widget.backgroundPreference,
        isFeedSurface: true,
        // 134 §7: under reduced motion the feed-surface ambient entrance must
        // not run its infinite repeat() — render the static final frame.
        reduceMotion: _reduceMotion,
        readableToneOverride: widget.readableToneOverride,
        child: Stack(
          children: [
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
                        // 211: the connection dot now lives on the Orbit
                        // top-right chrome (FeedScreen.p2pService is kept for
                        // its other consumers/callers; the header no longer
                        // takes it).
                        child: FeedHeader(
                          username: widget.username,
                          onUsernameChanged: widget.onUsernameChanged,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, contentConstraints) {
                            final listenable = widget.feedItemsListenable;
                            if (listenable == null) {
                              return _buildFeedContent(
                                context: context,
                                horizontalPadding: horizontalPadding,
                                contentConstraints: contentConstraints,
                                bottomInset: bottomInset,
                                items: widget.feedItems,
                              );
                            }
                            return ValueListenableBuilder<List<FeedItem>>(
                              valueListenable: listenable,
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
            // Feed-screen-local nav bar — fades out (NOT keyboard-gated) while a
            // card is focused. AnimatedOpacity(0) still hit-tests, so wrap in
            // IgnorePointer.
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset - 14,
              child: IgnorePointer(
                ignoring: _isFocused,
                child: AnimatedOpacity(
                  opacity: _isFocused ? 0.0 : 1.0,
                  duration: _motion(const Duration(milliseconds: 200)),
                  child: Center(child: _buildNavigationBar()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

    final focusedItem = _focusedItem(items);

    return Stack(
      children: [
        _FeedScrollableContent(
          horizontalPadding: centeredHorizontalPadding,
          bottomInset: bottomInset,
          entries: _buildFeedEntries(items),
          loadingSliver: _buildLoadingSliver(),
          entryBuilder: _buildFeedEntry,
        ),
        // Single shared composer — shown ONLY while focused.
        if (_isFocused && focusedItem != null)
          Positioned(
            left: centeredHorizontalPadding,
            right: centeredHorizontalPadding,
            bottom: 12 + MediaQuery.viewInsetsOf(context).bottom,
            child: _buildComposer(context, focusedItem),
          ),
      ],
    );
  }

  Widget _buildComposer(BuildContext context, FeedItem focusedItem) {
    final l10n = AppLocalizations.of(context)!;
    final focusedId = widget.focusedId!;

    String hint;
    if (focusedItem is GroupThreadFeedItem) {
      // Decision G: verb + route source from the GROUP, never a sender run.
      hint = l10n.feed_reply_to_name(focusedItem.groupName);
    } else if (focusedItem is ConnectionFeedItem) {
      hint = l10n.feed_message_name(focusedItem.contactUsername);
    } else if (focusedItem is ThreadFeedItem) {
      hint = l10n.feed_reply_to_name(focusedItem.contactUsername);
    } else {
      hint = l10n.feed_reply_to_name('');
    }

    return FeedComposer(
      key: ValueKey('feed-composer-$focusedId'),
      draftText: widget.composerDraft,
      hintText: hint,
      addAnotherHint: l10n.feed_add_another,
      onSend: (text) => widget.onComposerSend?.call(focusedId, text),
      onDraftChanged: (text) =>
          widget.onComposerDraftChanged?.call(focusedId, text),
    );
  }

  /// Routes the "open full conversation" history entry point for [item]:
  /// 1:1 / system → the contact conversation (by peerId), group → [onGroupTap]
  /// (routed by item, never a sender run). Shared by the focused header (B3).
  VoidCallback? _onOpenConversationFor(FeedItem item) {
    if (item is GroupThreadFeedItem) {
      return widget.onGroupTap != null ? () => widget.onGroupTap!(item) : null;
    }
    if (item is ConnectionFeedItem) {
      return widget.onOpenFullConversation != null
          ? () => widget.onOpenFullConversation!(item.contactPeerId)
          : null;
    }
    if (item is ThreadFeedItem) {
      return widget.onOpenFullConversation != null
          ? () => widget.onOpenFullConversation!(item.contactPeerId)
          : null;
    }
    return null;
  }

  /// Focused-only header (134 §5/§6): a neutral back affordance that returns to
  /// the feed plus the focused thread's identity. The "open full conversation"
  /// history entry point is NOT here — it sits at the END of the thread column
  /// (see [_buildOpenConversationLink]).
  Widget _buildFocusedHeader(BuildContext context, FeedItem item) {
    final tokens = context.feedTokens;
    final name = _displayNameFor(item);

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space3 * 0.5),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('feed-focused-back'),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            iconSize: 18,
            color: tokens.textMeta.color,
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => widget.onClearFocus?.call(),
          ),
          if (name.isNotEmpty)
            Expanded(
              child: Text(
                name,
                style: tokens.textMessage.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
        ],
      ),
    );
  }

  /// The "open full conversation" history entry point, rendered CENTERED at the
  /// END of the focused thread column (below the incoming bubbles and any sent
  /// session replies). Returns an empty box when the thread has no routable
  /// conversation target.
  Widget _buildOpenConversationLink(BuildContext context, FeedItem item) {
    final onOpen = _onOpenConversationFor(item);
    if (onOpen == null) return const SizedBox.shrink();
    final tokens = context.feedTokens;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.only(top: tokens.space3),
      child: Center(
        child: GestureDetector(
          key: const ValueKey('feed-open-full-conversation'),
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.feed_open_full_conversation,
                  style: tokens.textMeta.copyWith(color: tokens.teal400),
                ),
                const SizedBox(width: 4),
                Icon(Icons.north_east, size: 14, color: tokens.teal400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationBar() {
    final unreadCountListenable = widget.totalUnreadCountListenable;
    final orbitCountListenable = widget.orbitBadgeCountListenable;
    if (unreadCountListenable == null && orbitCountListenable == null) {
      return FeedNavigationBar(
        activeTab: widget.activeTab,
        onSwitchView: widget.onSwitchView,
        feedBadgeCount: widget.totalUnreadCount,
        orbitBadgeCount: widget.orbitBadgeCount,
      );
    }

    if (unreadCountListenable == null) {
      return ValueListenableBuilder<int>(
        valueListenable: orbitCountListenable!,
        builder: (context, orbitCount, child) => FeedNavigationBar(
          activeTab: widget.activeTab,
          onSwitchView: widget.onSwitchView,
          feedBadgeCount: widget.totalUnreadCount,
          orbitBadgeCount: orbitCount,
        ),
      );
    }

    if (orbitCountListenable == null) {
      return ValueListenableBuilder<int>(
        valueListenable: unreadCountListenable,
        builder: (context, unreadCount, child) => FeedNavigationBar(
          activeTab: widget.activeTab,
          onSwitchView: widget.onSwitchView,
          feedBadgeCount: unreadCount,
          orbitBadgeCount: widget.orbitBadgeCount,
        ),
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: unreadCountListenable,
      builder: (context, unreadCount, child) => ValueListenableBuilder<int>(
        valueListenable: orbitCountListenable,
        builder: (context, orbitCount, nestedChild) => FeedNavigationBar(
          activeTab: widget.activeTab,
          onSwitchView: widget.onSwitchView,
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
      if (!widget.feedLoaded) return const [];
      return const [
        _FeedEntry.spacer(height: 12),
        _FeedEntry.emptyState(),
      ];
    }

    final entries = <_FeedEntry>[const _FeedEntry.spacer(height: 16)];
    for (var i = 0; i < items.length; i++) {
      entries.add(_FeedEntry.item(items[i]));
      if (i != items.length - 1) {
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
      case _FeedEntryType.spacer:
        return SizedBox(height: entry.height);
      case _FeedEntryType.emptyState:
        return const CaughtUpEmptyState();
    }
  }

  Widget _buildFeedItemWidget(BuildContext context, FeedItem item) {
    final threadId = _threadIdFor(item);
    final isFocused = threadId != null && threadId == widget.focusedId;
    // Any card is collapsed when SOME other card is focused.
    final collapsed = _isFocused && !isFocused;

    Widget card = _buildLetterCard(context, item, focused: isFocused);

    // 134-P6: wrap each (un-collapsed) letter card in the swipe host. Removal is
    // STORE-DRIVEN (markCleared → re-projection drops the item), so FeedSwipeCard
    // springs back rather than removing the widget itself. Skip the wrapper when
    // collapsed (the body becomes a 0-height box — nothing to swipe).
    if (threadId != null && !collapsed) {
      // A freshly-scanned contact who has messaged renders BOTH a "connection"
      // system card AND a 1:1 thread card, sharing the same bare peerId. Qualify
      // the swipe-clear id by kind (connection: vs bare/group:) so the cleared
      // watermark targets the RIGHT row and only the swiped card disappears.
      final swipeThreadId = item is ConnectionFeedItem
          ? 'connection:$threadId'
          : threadId;
      card = FeedSwipeCard(
        key: ValueKey<String>('feed-swipe-$swipeThreadId'),
        focused: isFocused,
        reduceMotion: _reduceMotion,
        onCommit: () => widget.onSwipeCommit?.call(swipeThreadId),
        onDismissThread: () => _onCardDismiss(swipeThreadId),
        onSwipeStart: () => widget.onCardSwipeActive?.call(true),
        onSwipeEnd: () => widget.onCardSwipeActive?.call(false),
        child: card,
      );
    }

    // Collapse + fade non-focused siblings (134 §8).
    final body = AnimatedOpacity(
      opacity: collapsed ? 0.0 : 1.0,
      duration: _motion(const Duration(milliseconds: 220)),
      curve: Curves.easeOut,
      child: AnimatedSize(
        duration: _motion(const Duration(milliseconds: 220)),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: collapsed
            ? const SizedBox(width: double.infinity, height: 0)
            : card,
      ),
    );

    if (threadId == null) return body;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (isFocused) return;
        widget.onFocusCard?.call(threadId);
      },
      child: body,
    );
  }

  /// Handles a swipe-LEFT dismiss: marks the thread cleared (read-state
  /// untouched). Removal is SILENT — no "Removed …" Undo SnackBar (the user
  /// found it intrusive / sticky). The cleared watermark still hides the card;
  /// the store-level undo (`clearClearedLocally`) remains available, just no
  /// longer surfaced via a snackbar.
  void _onCardDismiss(String threadId) {
    widget.onSwipeDismiss?.call(threadId);
  }

  Widget _buildLetterCard(
    BuildContext context,
    FeedItem item, {
    required bool focused,
  }) {
    final body = _buildLetterCardBody(context, item, focused: focused);
    if (!focused) return body;
    // A focused thread gets a top-of-column header (back affordance + identity)
    // above its message body, and the "open full conversation" link CENTERED at
    // the very END of the column (below the bubbles + any sent replies).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFocusedHeader(context, item),
        body,
        _buildOpenConversationLink(context, item),
      ],
    );
  }

  Widget _buildLetterCardBody(
    BuildContext context,
    FeedItem item, {
    required bool focused,
  }) {
    if (item is GroupThreadFeedItem) {
      return _withSessionReplies(
        context,
        threadId: 'group:${item.groupId}',
        focused: focused,
        card: LetterCardGroup(
          letter: GroupLetter.fromThread(item),
          focused: focused,
        ),
      );
    }
    if (item is ConnectionFeedItem) {
      final boundSend = widget.onSendMessage != null
          ? () => widget.onSendMessage!(item)
          : null;
      return _withSessionReplies(
        context,
        threadId: item.contactPeerId,
        focused: focused,
        card: LetterCardSystem(
          letter: SystemLetter.fromConnection(item),
          onSendMessage: boundSend,
        ),
      );
    }
    if (item is ThreadFeedItem) {
      return _withSessionReplies(
        context,
        threadId: item.contactPeerId,
        focused: focused,
        card: LetterCardOneToOne(
          letter: OneToOneLetter.fromThread(item),
          focused: focused,
        ),
      );
    }
    throw ArgumentError.value(
      item,
      'item',
      'Unsupported feed item type ${item.runtimeType}',
    );
  }

  /// Appends the current focus session's outgoing replies under [card] as
  /// green outgoing bubbles (append-stay) and renders a tappable retry
  /// affordance for any failed/pending one (never-silent send, TC-22 / TC-30).
  Widget _withSessionReplies(
    BuildContext context, {
    required String threadId,
    required bool focused,
    required Widget card,
  }) {
    final replies = widget.sessionReplies[threadId];
    if (replies == null || replies.isEmpty) return card;

    final tokens = context.feedTokens;
    final l10n = AppLocalizations.of(context)!;
    final bubbles = <Widget>[];
    for (final reply in replies) {
      bubbles.add(SizedBox(height: tokens.space3 * 0.5));
      bubbles.add(
        LetterBubble(text: reply.text, role: LetterBubbleRole.outgoing),
      );
      if (reply.failed) {
        bubbles.add(SizedBox(height: tokens.space3 * 0.25));
        bubbles.add(
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              key: ValueKey('feed-retry-${reply.messageId}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onRetrySend?.call(threadId, reply),
              child: Text(
                l10n.feed_tap_to_retry,
                style: tokens.textMeta.copyWith(color: tokens.green500),
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [card, ...bubbles],
    );
  }
}

class _FeedScrollableContent extends StatefulWidget {
  final double horizontalPadding;
  final double bottomInset;
  final List<_FeedEntry> entries;
  final Widget loadingSliver;
  final Widget Function(BuildContext context, _FeedEntry entry) entryBuilder;

  const _FeedScrollableContent({
    required this.horizontalPadding,
    required this.bottomInset,
    required this.entries,
    required this.loadingSliver,
    required this.entryBuilder,
  });

  @override
  State<_FeedScrollableContent> createState() => _FeedScrollableContentState();
}

class _FeedScrollableContentState extends State<_FeedScrollableContent> {
  final ScrollController _scrollController = ScrollController();

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
    return KeyedSubtree(key: ValueKey<String>(item.id), child: child);
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

    return CustomScrollView(
      key: const PageStorageKey<String>('feed-scroll'),
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      cacheExtent: 1200,
      slivers: [
        SliverPadding(
          // 134-P5 (TC-19b): clear the floating composer / nav bar so the last
          // card is never hidden behind them.
          padding: EdgeInsets.only(
            left: widget.horizontalPadding,
            right: widget.horizontalPadding,
            bottom: 170 + widget.bottomInset,
          ),
          sliver: sliver,
        ),
      ],
    );
  }
}

enum _FeedEntryType { item, spacer, emptyState }

@immutable
class _FeedEntry {
  final _FeedEntryType type;
  final FeedItem? item;
  final double? height;

  const _FeedEntry._({
    required this.type,
    this.item,
    this.height,
  });

  const _FeedEntry.item(FeedItem item)
    : this._(type: _FeedEntryType.item, item: item);

  const _FeedEntry.spacer({required double height})
    : this._(type: _FeedEntryType.spacer, height: height);

  const _FeedEntry.emptyState() : this._(type: _FeedEntryType.emptyState);
}

class _FeedLoadingCard extends StatelessWidget {
  final int index;

  const _FeedLoadingCard({required this.index});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Container(
      key: ValueKey('feed-loading-card-$index'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: readableColors.surfaceSubtle,
        border: Border.all(color: readableColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    final readableColors = context.backgroundReadableColors;

    return Container(
      key: const ValueKey('feed-loading-status'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: readableColors.surfaceRaised,
        border: Border.all(color: readableColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: readableColors.iconSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.feed_loading,
                  style: TextStyle(
                    color: readableColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)!.feed_syncing_threads,
                  style: TextStyle(
                    color: readableColors.textSecondary,
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
    final readableColors = context.backgroundReadableColors;

    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          color: readableColors.disabledSurface,
        ),
      ),
    );
  }
}
