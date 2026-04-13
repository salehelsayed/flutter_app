import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/presentation/widgets/collapsed_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/open_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  void setPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  ThreadFeedItem buildThreadItem({
    required String id,
    required String username,
    required DateTime timestamp,
  }) {
    return ThreadFeedItem(
      id: id,
      timestamp: timestamp,
      contactPeerId: '${id}_peer',
      contactUsername: username,
      conversationState: ConversationState.read,
      messages: [
        ThreadMessage(
          id: '${id}_message_0',
          text: 'First message for $username',
          time: '12:00',
          timestamp: timestamp.subtract(const Duration(minutes: 5)),
          isIncoming: true,
          isUnread: false,
          status: 'read',
        ),
        ThreadMessage(
          id: '${id}_message_1',
          text: 'Latest message for $username',
          time: '12:05',
          timestamp: timestamp,
          isIncoming: false,
          isUnread: false,
          status: 'read',
        ),
      ],
    );
  }

  Widget buildFeedScreen({
    required List<FeedItem> feedItems,
    ValueNotifier<List<FeedItem>>? feedItemsListenable,
    bool feedLoaded = true,
    String? expandedCardId,
    String? activeFocusPeerId,
    String? editingContactPeerId,
    EdgeInsets viewInsets = EdgeInsets.zero,
    SessionReplyTracker? sessionReplies,
    Map<String, String>? activeQuoteMessageIds,
    Map<String, List<MessageReaction>> reactions = const {},
    void Function(String contactPeerId)? onClearQuote,
    void Function(String messageId, String emoji)? onReactionSelected,
    void Function(String contactPeerId, String messageId)? onEditMessage,
    void Function(String contactPeerId, String messageId)? onDeleteMessage,
    void Function(String contactPeerId)? onCancelEdit,
    void Function(String groupId, String text)? onGroupInlineSend,
    void Function(String groupId, String messageId, String emoji)?
    onGroupReactionTap,
    void Function(String groupId, String messageId, String emoji)?
    onGroupReactionSelected,
    void Function(String contactPeerId, String messageId)? onQuoteReply,
    void Function(GroupThreadFeedItem)? onGroupAttach,
    String? userPeerId = 'alice-peer',
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(viewInsets: viewInsets),
            child: FeedScreen(
              username: 'Alice',
              feedItems: feedItems,
              feedItemsListenable: feedItemsListenable,
              feedLoaded: feedLoaded,
              activeTab: 'feed',
              onSwitchView: (_) {},
              activeFocusPeerId: activeFocusPeerId,
              expandedCardId: expandedCardId,
              onToggleExpand: (_) {},
              sessionReplies: sessionReplies,
              editingContactPeerId: editingContactPeerId,
              activeQuoteMessageIds: activeQuoteMessageIds,
              onClearQuote: onClearQuote,
              onReactionSelected: onReactionSelected,
              onEditMessage: onEditMessage,
              onDeleteMessage: onDeleteMessage,
              onCancelEdit: onCancelEdit,
              onGroupInlineSend: onGroupInlineSend,
              onGroupReactionTap: onGroupReactionTap,
              onGroupReactionSelected: onGroupReactionSelected,
              onQuoteReply: onQuoteReply,
              onGroupAttach: onGroupAttach,
              reactions: reactions,
              userPeerId: userPeerId,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders loading placeholders while feed is still loading', (
    tester,
  ) async {
    setPhoneViewport(tester);

    await tester.pumpWidget(
      buildFeedScreen(feedItems: const [], feedLoaded: false),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('feed-loading-card-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-loading-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-loading-card-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-loading-status')), findsOneWidget);
    expect(find.text('Loading Feed...'), findsOneWidget);
    expect(find.text('Your recent threads are still syncing.'), findsOneWidget);
    expect(find.textContaining('Your feed is ready'), findsNothing);
    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('Orbit'), findsOneWidget);
    expect(find.text('Remember'), findsNothing);
  });

  testWidgets('renders empty state once feed load completes with no items', (
    tester,
  ) async {
    setPhoneViewport(tester);

    await tester.pumpWidget(
      buildFeedScreen(feedItems: const [], feedLoaded: true),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('feed-loading-card-0')), findsNothing);
    expect(find.textContaining('Your feed is ready'), findsOneWidget);
  });

  testWidgets(
    'swaps loading placeholders for real feed items when data arrives',
    (tester) async {
      setPhoneViewport(tester);

      final itemsNotifier = ValueNotifier<List<FeedItem>>(const <FeedItem>[]);
      addTearDown(itemsNotifier.dispose);

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: const [],
          feedItemsListenable: itemsNotifier,
          feedLoaded: false,
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('feed-loading-card-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-loading-status')), findsOneWidget);

      itemsNotifier.value = [
        buildThreadItem(
          id: 'thread_bob',
          username: 'Bob',
          timestamp: DateTime.utc(2026, 3, 1, 10),
        ),
      ];
      await tester.pump();

      expect(find.byKey(const ValueKey('feed-loading-card-0')), findsNothing);
      expect(find.byKey(const ValueKey('feed-loading-status')), findsNothing);
      expect(find.byKey(const ValueKey<String>('thread_bob')), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    },
  );

  testWidgets(
    'renders feed through CustomScrollView instead of eager scroll view',
    (tester) async {
      setPhoneViewport(tester);

      final items = List<FeedItem>.generate(
        30,
        (index) => buildThreadItem(
          id: 'thread_$index',
          username: 'User $index',
          timestamp: DateTime.utc(
            2026,
            3,
            1,
          ).subtract(Duration(minutes: index)),
        ),
      );

      await tester.pumpWidget(buildFeedScreen(feedItems: items));
      await tester.pump();

      final tailCardFinder = find.byKey(const ValueKey<String>('thread_29'));
      final feedScrollViewFinder = find.byType(CustomScrollView);

      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(FeedCard).evaluate().length, lessThan(items.length));
      expect(tailCardFinder, findsNothing);

      for (var attempt = 0; attempt < 20; attempt++) {
        if (tailCardFinder.evaluate().isNotEmpty) {
          break;
        }

        await tester.drag(feedScrollViewFinder, const Offset(0, -400));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 700));

      expect(tailCardFinder, findsOneWidget);
      expect(find.text('User 29'), findsOneWidget);
    },
  );

  testWidgets(
    'keeps bottom navigation visible when reply input is focused without keyboard insets',
    (tester) async {
      setPhoneViewport(tester);

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [
            buildThreadItem(
              id: 'thread_bob',
              username: 'Bob',
              timestamp: DateTime.utc(2026, 3, 1, 10),
            ),
          ],
          activeFocusPeerId: 'thread_bob_peer',
        ),
      );
      await tester.pump();

      expect(find.byType(FeedNavigationBar), findsOneWidget);
    },
  );

  testWidgets(
    'hides bottom navigation when reply input is focused with software keyboard visible',
    (tester) async {
      setPhoneViewport(tester);

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [
            buildThreadItem(
              id: 'thread_bob',
              username: 'Bob',
              timestamp: DateTime.utc(2026, 3, 1, 10),
            ),
          ],
          activeFocusPeerId: 'thread_bob_peer',
          viewInsets: const EdgeInsets.only(bottom: 320),
        ),
      );
      await tester.pump();

      expect(find.byType(FeedNavigationBar), findsNothing);
    },
  );

  testWidgets(
    'preserves the expanded card element when thread ordering changes',
    (tester) async {
      setPhoneViewport(tester);

      final bob = buildThreadItem(
        id: 'thread_bob',
        username: 'Bob',
        timestamp: DateTime.utc(2026, 3, 1, 10),
      );
      final cara = buildThreadItem(
        id: 'thread_cara',
        username: 'Cara',
        timestamp: DateTime.utc(2026, 3, 1, 11),
      );

      await tester.pumpWidget(
        buildFeedScreen(feedItems: [bob, cara], expandedCardId: 'thread_bob'),
      );
      await tester.pump();

      final bobFinder = find.byKey(const ValueKey<String>('thread_bob'));
      final beforeElement = tester.element(bobFinder);

      expect(find.byType(ScrollableMessagePreview), findsOneWidget);

      final bobReordered = buildThreadItem(
        id: 'thread_bob',
        username: 'Bob',
        timestamp: DateTime.utc(2026, 3, 1, 12),
      );

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [bobReordered, cara],
          expandedCardId: 'thread_bob',
        ),
      );
      await tester.pump();

      final afterElement = tester.element(bobFinder);
      expect(identical(beforeElement, afterElement), isTrue);
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);
    },
  );

  testWidgets('maps active quote id to visible preview text and dismisses it', (
    tester,
  ) async {
    setPhoneViewport(tester);

    final item = ThreadFeedItem(
      id: 'thread_bob',
      timestamp: DateTime.utc(2026, 3, 1, 10),
      contactPeerId: 'bob-peer',
      contactUsername: 'Bob',
      conversationState: ConversationState.read,
      messages: [
        ThreadMessage(
          id: 'bob-msg-1',
          text: 'First quote target',
          time: '12:00',
          timestamp: DateTime.utc(2026, 3, 1, 9, 55),
          isIncoming: true,
        ),
      ],
    );
    String? clearedPeerId;

    await tester.pumpWidget(
      buildFeedScreen(
        feedItems: [item],
        activeQuoteMessageIds: const {'bob-peer': 'bob-msg-1'},
        onClearQuote: (contactPeerId) => clearedPeerId = contactPeerId,
      ),
    );
    await tester.pump();

    expect(find.text('Replying to'), findsOneWidget);
    expect(find.text('First quote target'), findsWidgets);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(clearedPeerId, 'bob-peer');
  });

  testWidgets(
    'maps active group quote id to visible preview text and dismisses it',
    (tester) async {
      setPhoneViewport(tester);

      final item = GroupThreadFeedItem(
        id: 'group_thread_g1',
        timestamp: DateTime.utc(2026, 3, 1, 10),
        groupId: 'g1',
        groupName: 'Group One',
        groupType: GroupType.chat,
        messages: [
          ThreadMessage(
            id: 'gm-1',
            text: 'Quote this group message',
            time: '12:00',
            timestamp: DateTime.utc(2026, 3, 1, 9, 55),
            isIncoming: true,
            isUnread: true,
            senderUsername: 'Alice',
            senderPeerId: 'peer-alice',
          ),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );
      String? clearedKey;

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [item],
          activeQuoteMessageIds: const {'group:g1': 'gm-1'},
          onClearQuote: (contactPeerId) => clearedKey = contactPeerId,
        ),
      );
      await tester.pump();

      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Quote this group message'), findsWidgets);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(clearedKey, 'group:g1');
    },
  );

  testWidgets(
    'group card with session reply shows collapsed mode instead of open mode',
    (tester) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      setPhoneViewport(tester);

      // Group card in unread state (open mode)
      final groupItem = GroupThreadFeedItem(
        id: 'group_thread_g1',
        timestamp: DateTime.now(),
        groupId: 'g1',
        groupName: 'Test Group',
        groupType: GroupType.chat,
        messages: [
          ThreadMessage(
            id: 'gm-1',
            text: 'Hello group',
            time: '3:33 AM',
            timestamp: DateTime.now(),
            isIncoming: true,
            isUnread: true,
            senderUsername: 'Hisam',
            senderPeerId: 'peer-hisam',
          ),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );

      // Without session reply — should be in open mode
      await tester.pumpWidget(buildFeedScreen(feedItems: [groupItem]));
      await tester.pump();
      expect(find.byType(OpenModeCardBody), findsOneWidget);

      // With session reply — should collapse to show sent message
      final tracker = SessionReplyTracker();
      tracker.track('group:g1', SessionReply.justNow('My reply'));

      await tester.pumpWidget(
        buildFeedScreen(feedItems: [groupItem], sessionReplies: tracker),
      );
      await tester.pump();
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      expect(find.byType(OpenModeCardBody), findsNothing);
    },
  );

  testWidgets(
    'announcement member group card stays read-only even when callbacks are provided',
    (tester) async {
      setPhoneViewport(tester);

      final groupItem = GroupThreadFeedItem(
        id: 'group_thread_announce',
        timestamp: DateTime.utc(2026, 3, 1, 10),
        groupId: 'announce',
        groupName: 'Announcements',
        groupType: GroupType.announcement,
        myRole: GroupRole.member,
        messages: [
          ThreadMessage(
            id: 'gm-announce-1',
            text: 'Admin update',
            time: '12:00',
            timestamp: DateTime.utc(2026, 3, 1, 9, 55),
            isIncoming: true,
            isUnread: true,
            senderUsername: 'Admin',
            senderPeerId: 'peer-admin',
          ),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [groupItem],
          onGroupInlineSend: (groupId, text) {},
          onQuoteReply: (contactPeerId, messageId) {},
          onGroupAttach: (_) {},
        ),
      );
      await tester.pump();

      expect(
        find.text('Only admins can send messages in this group'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byType(SwipeToQuoteBubble), findsNothing);
    },
  );

  testWidgets(
    'inline group reaction chips route through the dedicated inspection callback',
    (tester) async {
      setPhoneViewport(tester);

      final groupItem = GroupThreadFeedItem(
        id: 'group_thread_reactions',
        timestamp: DateTime.utc(2026, 3, 1, 10),
        groupId: 'group-1',
        groupName: 'Reaction Group',
        groupType: GroupType.chat,
        messages: [
          ThreadMessage(
            id: 'group-msg-1',
            text: 'Group message with reactions',
            time: '12:00',
            timestamp: DateTime.utc(2026, 3, 1, 9, 55),
            isIncoming: true,
            isUnread: true,
            senderUsername: 'Bob',
            senderPeerId: 'peer-bob',
          ),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );
      String? tappedGroupId;
      String? tappedMessageId;
      String? tappedEmoji;

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [groupItem],
          reactions: {
            'group-msg-1': [
              MessageReaction(
                id: 'rxn-1',
                messageId: 'group-msg-1',
                emoji: '👍',
                senderPeerId: 'peer-bob',
                timestamp: '2026-03-01T09:56:00.000Z',
                createdAt: '2026-03-01T09:56:00.000Z',
              ),
            ],
          },
          onGroupReactionTap: (groupId, messageId, emoji) {
            tappedGroupId = groupId;
            tappedMessageId = messageId;
            tappedEmoji = emoji;
          },
        ),
      );
      await tester.pump();

      await tester.tap(find.text('👍'));
      await tester.pump();

      expect(tappedGroupId, 'group-1');
      expect(tappedMessageId, 'group-msg-1');
      expect(tappedEmoji, '👍');
    },
  );

  testWidgets(
    'announcement reader cards keep inline reaction inspection available while compose stays read-only',
    (tester) async {
      setPhoneViewport(tester);

      final groupItem = GroupThreadFeedItem(
        id: 'group_thread_announce_reactions',
        timestamp: DateTime.utc(2026, 3, 1, 10),
        groupId: 'announce-1',
        groupName: 'Announcements',
        groupType: GroupType.announcement,
        myRole: GroupRole.member,
        messages: [
          ThreadMessage(
            id: 'announce-msg-1',
            text: 'Admin reaction message',
            time: '12:00',
            timestamp: DateTime.utc(2026, 3, 1, 9, 55),
            isIncoming: true,
            isUnread: true,
            senderUsername: 'Admin',
            senderPeerId: 'peer-admin',
          ),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );
      String? tappedGroupId;
      String? tappedMessageId;
      String? tappedEmoji;

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [groupItem],
          reactions: {
            'announce-msg-1': [
              MessageReaction(
                id: 'rxn-announce',
                messageId: 'announce-msg-1',
                emoji: '👏',
                senderPeerId: 'peer-admin',
                timestamp: '2026-03-01T09:56:00.000Z',
                createdAt: '2026-03-01T09:56:00.000Z',
              ),
            ],
          },
          onGroupInlineSend: (_, __) {},
          onGroupAttach: (_) {},
          onQuoteReply: (_, __) {},
          onGroupReactionTap: (groupId, messageId, emoji) {
            tappedGroupId = groupId;
            tappedMessageId = messageId;
            tappedEmoji = emoji;
          },
        ),
      );
      await tester.pump();

      expect(
        find.text('Only admins can send messages in this group'),
        findsOneWidget,
      );

      await tester.tap(find.text('👏'));
      await tester.pump();

      expect(tappedGroupId, 'announce-1');
      expect(tappedMessageId, 'announce-msg-1');
      expect(tappedEmoji, '👏');
    },
  );

  testWidgets(
    'group message long-press in Feed uses the shared context overlay with reactions reply and copy',
    (tester) async {
      setPhoneViewport(tester);

      final item = GroupThreadFeedItem(
        id: 'group_thread_overlay',
        timestamp: DateTime.utc(2026, 3, 1, 10),
        groupId: 'group-1',
        groupName: 'Overlay Group',
        groupType: GroupType.chat,
        messages: [
          ThreadMessage(
            id: 'group-msg-1',
            text: 'Incoming group message',
            time: '12:00',
            timestamp: DateTime.utc(2026, 3, 1, 9, 55),
            isIncoming: true,
            isUnread: true,
            senderUsername: 'Bob',
            senderPeerId: 'peer-bob',
          ),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );
      String? quotedPeerId;
      String? quotedMessageId;

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [item],
          reactions: {
            'group-msg-1': [
              MessageReaction(
                id: 'rxn-1',
                messageId: 'group-msg-1',
                emoji: '👍',
                senderPeerId: 'peer-bob',
                timestamp: '2026-03-01T09:56:00.000Z',
                createdAt: '2026-03-01T09:56:00.000Z',
              ),
            ],
          },
          onGroupReactionSelected: (_, __, ___) {},
          onQuoteReply: (contactPeerId, messageId) {
            quotedPeerId = contactPeerId;
            quotedMessageId = messageId;
          },
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('Incoming group message'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.reactionBarKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(MessageContextOverlay.selectedMessageKey),
          matching: find.text('Incoming group message'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(MessageContextOverlay.replyActionKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(quotedPeerId, 'group:group-1');
      expect(quotedMessageId, 'group-msg-1');
      expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
    },
  );

  testWidgets(
    'incoming long-press opens shared overlay and routes reply through feed callback',
    (tester) async {
      setPhoneViewport(tester);

      final item = ThreadFeedItem(
        id: 'thread_bob',
        timestamp: DateTime.utc(2026, 3, 1, 10),
        contactPeerId: 'bob-peer',
        contactUsername: 'Bob',
        messages: [
          ThreadMessage(
            id: 'bob-msg-1',
            text: 'Incoming from Bob',
            time: '12:00',
            timestamp: DateTime.utc(2026, 3, 1, 9, 55),
            isIncoming: true,
            isUnread: true,
          ),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );
      String? quotedPeerId;
      String? quotedMessageId;

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [item],
          onReactionSelected: (_, _) {},
          onQuoteReply: (contactPeerId, messageId) {
            quotedPeerId = contactPeerId;
            quotedMessageId = messageId;
          },
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('Incoming from Bob'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
      expect(
        find.byKey(MessageContextOverlay.selectedMessageKey),
        findsOneWidget,
      );
      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(MessageContextOverlay.selectedMessageKey),
          matching: find.text('Incoming from Bob'),
        ),
        findsOneWidget,
      );

      final reactionRect = tester.getRect(
        find.byKey(MessageContextOverlay.reactionBarKey),
      );
      final selectedRect = tester.getRect(
        find.byKey(MessageContextOverlay.selectedMessageKey),
      );
      final menuRect = tester.getRect(
        find.byKey(MessageContextOverlay.menuKey),
      );

      expect(reactionRect.bottom, lessThanOrEqualTo(selectedRect.top));
      expect(selectedRect.bottom, lessThanOrEqualTo(menuRect.top));

      await tester.tap(find.byKey(MessageContextOverlay.replyActionKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(quotedPeerId, 'bob-peer');
      expect(quotedMessageId, 'bob-msg-1');
      expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
    },
  );

  testWidgets(
    'sent long-press in expanded collapsed card exposes reply action',
    (tester) async {
      setPhoneViewport(tester);

      final item = ThreadFeedItem(
        id: 'thread_bob',
        timestamp: DateTime.utc(2026, 3, 1, 10),
        contactPeerId: 'bob-peer',
        contactUsername: 'Bob',
        messages: [
          ThreadMessage(
            id: 'bob-msg-1',
            text: 'Incoming from Bob',
            time: '12:00',
            timestamp: DateTime.utc(2026, 3, 1, 9, 55),
            isIncoming: true,
          ),
          ThreadMessage(
            id: 'bob-msg-2',
            text: 'My sent message',
            time: '12:05',
            timestamp: DateTime.utc(2026, 3, 1, 10),
            isIncoming: false,
            status: 'delivered',
          ),
        ],
        conversationState: ConversationState.read,
      );
      String? quotedMessageId;

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [item],
          expandedCardId: 'thread_bob',
          onReactionSelected: (_, _) {},
          onQuoteReply: (_, messageId) => quotedMessageId = messageId,
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('My sent message'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.byKey(MessageContextOverlay.selectedMessageKey),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(MessageContextOverlay.selectedMessageKey),
          matching: find.text('My sent message'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);

      await tester.tap(find.byKey(MessageContextOverlay.replyActionKey));
      await tester.pump();

      expect(quotedMessageId, 'bob-msg-2');
    },
  );

  testWidgets(
    'feed edit action appears only on the last sent row even when a newer incoming row exists',
    (tester) async {
      setPhoneViewport(tester);

      String? editedPeerId;
      String? editedMessageId;
      final item = ThreadFeedItem(
        id: 'thread_bob',
        timestamp: DateTime.utc(2026, 3, 1, 10, 10),
        contactPeerId: 'bob-peer',
        contactUsername: 'Bob',
        messages: [
          ThreadMessage(
            id: 'bob-sent-old',
            text: 'Older sent message',
            time: '12:00',
            timestamp: DateTime.utc(2026, 3, 1, 10, 0),
            isIncoming: false,
            status: 'delivered',
          ),
          ThreadMessage(
            id: 'bob-sent-last',
            text: 'Last sent message',
            time: '12:05',
            timestamp: DateTime.utc(2026, 3, 1, 10, 5),
            isIncoming: false,
            status: 'delivered',
          ),
          ThreadMessage(
            id: 'bob-incoming-newer',
            text: 'Newer incoming message',
            time: '12:10',
            timestamp: DateTime.utc(2026, 3, 1, 10, 10),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [item],
          expandedCardId: 'thread_bob',
          onReactionSelected: (_, _) {},
          onEditMessage: (contactPeerId, messageId) {
            editedPeerId = contactPeerId;
            editedMessageId = messageId;
          },
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('Last sent message'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.editActionKey), findsOneWidget);

      await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
      await tester.pump();

      expect(editedPeerId, 'bob-peer');
      expect(editedMessageId, 'bob-sent-last');

      await tester.longPress(find.text('Older sent message'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);
    },
  );

  testWidgets('feed hides edit for media-only outgoing rows', (tester) async {
    setPhoneViewport(tester);

    final item = ThreadFeedItem(
      id: 'thread_media',
      timestamp: DateTime.utc(2026, 3, 1, 10, 10),
      contactPeerId: 'media-peer',
      contactUsername: 'Media Bob',
      messages: [
        ThreadMessage(
          id: 'media-parent',
          text: 'Earlier incoming',
          time: '12:00',
          timestamp: DateTime.utc(2026, 3, 1, 10, 0),
          isIncoming: true,
        ),
        ThreadMessage(
          id: 'media-only-last',
          text: '',
          time: '12:10',
          timestamp: DateTime.utc(2026, 3, 1, 10, 10),
          isIncoming: false,
          status: 'delivered',
          media: const [
            MediaAttachment(
              id: 'media-1',
              messageId: 'media-only-last',
              mime: 'image/jpeg',
              size: 1,
              localPath: '/tmp/pic.jpg',
              mediaType: 'image',
              downloadStatus: 'done',
              createdAt: '2026-03-01T10:10:00.000Z',
            ),
          ],
        ),
      ],
      conversationState: ConversationState.read,
    );

    await tester.pumpWidget(
      buildFeedScreen(
        feedItems: [item],
        expandedCardId: 'thread_media',
        onReactionSelected: (_, _) {},
        onEditMessage: (_, __) {},
      ),
    );
    await tester.pump();

    await tester.longPress(find.byType(MessageBubble).last);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);
  });

  testWidgets('feed delete action routes through the shared overlay callback', (
    tester,
  ) async {
    setPhoneViewport(tester);

    String? deletedPeerId;
    String? deletedMessageId;
    final item = ThreadFeedItem(
      id: 'thread_delete',
      timestamp: DateTime.utc(2026, 3, 1, 10),
      contactPeerId: 'delete-peer',
      contactUsername: 'Delete Bob',
      messages: [
        ThreadMessage(
          id: 'delete-msg-1',
          text: 'Delete from feed',
          time: '12:00',
          timestamp: DateTime.utc(2026, 3, 1, 9, 55),
          isIncoming: true,
          isUnread: true,
        ),
      ],
      unreadCount: 1,
      conversationState: ConversationState.unread,
    );

    await tester.pumpWidget(
      buildFeedScreen(
        feedItems: [item],
        onReactionSelected: (_, _) {},
        onDeleteMessage: (contactPeerId, messageId) {
          deletedPeerId = contactPeerId;
          deletedMessageId = messageId;
        },
      ),
    );
    await tester.pump();

    await tester.longPress(find.text('Delete from feed'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(MessageContextOverlay.deleteActionKey), findsOneWidget);

    await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(deletedPeerId, 'delete-peer');
    expect(deletedMessageId, 'delete-msg-1');
    expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
  });

  testWidgets('deleted feed rows stay inert and never reopen the overlay', (
    tester,
  ) async {
    setPhoneViewport(tester);

    final item = ThreadFeedItem(
      id: 'thread_deleted',
      timestamp: DateTime.utc(2026, 3, 1, 10),
      contactPeerId: 'deleted-peer',
      contactUsername: 'Deleted Bob',
      messages: [
        ThreadMessage(
          id: 'deleted-msg-1',
          text: '',
          time: '12:00',
          timestamp: DateTime.utc(2026, 3, 1, 9, 55),
          isIncoming: true,
          isDeleted: true,
        ),
      ],
      conversationState: ConversationState.read,
    );

    await tester.pumpWidget(
      buildFeedScreen(feedItems: [item], onDeleteMessage: (_, __) {}),
    );
    await tester.pump();

    expect(find.text('This message was deleted'), findsOneWidget);

    await tester.longPress(find.text('This message was deleted'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
  });

  testWidgets('collapsed feed preview renders edited indicator', (
    tester,
  ) async {
    setPhoneViewport(tester);

    final item = ThreadFeedItem(
      id: 'thread_edited',
      timestamp: DateTime.utc(2026, 3, 1, 10, 5),
      contactPeerId: 'edited-peer',
      contactUsername: 'Edited Bob',
      conversationState: ConversationState.read,
      messages: [
        ThreadMessage(
          id: 'edited-incoming',
          text: 'Original incoming',
          time: '12:00',
          timestamp: DateTime.utc(2026, 3, 1, 10, 0),
          isIncoming: true,
        ),
        ThreadMessage(
          id: 'edited-outgoing',
          text: 'Edited outgoing preview',
          time: '12:05',
          timestamp: DateTime.utc(2026, 3, 1, 10, 5),
          isIncoming: false,
          status: 'delivered',
          editedAt: '2026-03-01T10:06:00.000Z',
        ),
      ],
    );

    await tester.pumpWidget(buildFeedScreen(feedItems: [item]));
    await tester.pump();

    expect(find.text('Edited outgoing preview'), findsOneWidget);
    expect(find.text('(edited)'), findsOneWidget);
  });

  testWidgets(
    'after restart, feed direct-thread screen rebuilds stored reply edit delete and reaction state without stale pre-restart UI',
    (tester) async {
      setPhoneViewport(tester);

      const threadId = 'thread_restart';
      const contactPeerId = 'restart-peer';
      const parentId = 'restart-parent';
      const replyId = 'restart-reply';

      final preRestartItem = ThreadFeedItem(
        id: threadId,
        timestamp: DateTime.utc(2026, 2, 9, 15, 32),
        contactPeerId: contactPeerId,
        contactUsername: 'Restart Bob',
        conversationState: ConversationState.read,
        messages: [
          ThreadMessage(
            id: parentId,
            text: 'Quote source before restart',
            time: '15:30',
            timestamp: DateTime.utc(2026, 2, 9, 15, 30),
            isIncoming: true,
          ),
          ThreadMessage(
            id: 'restart-edited',
            text: 'Editable before restart',
            time: '15:31',
            timestamp: DateTime.utc(2026, 2, 9, 15, 31),
            isIncoming: false,
            status: 'delivered',
          ),
          ThreadMessage(
            id: 'restart-deleted',
            text: 'Delete me after restart',
            time: '15:32',
            timestamp: DateTime.utc(2026, 2, 9, 15, 32),
            isIncoming: true,
            status: 'read',
          ),
        ],
      );

      final postRestartItem = ThreadFeedItem(
        id: threadId,
        timestamp: DateTime.utc(2026, 2, 9, 15, 42),
        contactPeerId: contactPeerId,
        contactUsername: 'Restart Bob',
        conversationState: ConversationState.read,
        messages: [
          ThreadMessage(
            id: parentId,
            text: 'Quote source before restart',
            time: '15:30',
            timestamp: DateTime.utc(2026, 2, 9, 15, 30),
            isIncoming: true,
          ),
          ThreadMessage(
            id: 'restart-edited',
            text: 'Edited after restart',
            time: '15:31',
            timestamp: DateTime.utc(2026, 2, 9, 15, 31),
            isIncoming: false,
            status: 'delivered',
            editedAt: '2026-02-09T15:40:00.000Z',
          ),
          ThreadMessage(
            id: 'restart-deleted',
            text: '',
            time: '15:32',
            timestamp: DateTime.utc(2026, 2, 9, 15, 32),
            isIncoming: true,
            isDeleted: true,
            status: 'read',
          ),
          ThreadMessage(
            id: replyId,
            text: 'Reply restored after restart',
            time: '15:42',
            timestamp: DateTime.utc(2026, 2, 9, 15, 42),
            isIncoming: false,
            status: 'delivered',
            quotedMessageId: parentId,
          ),
        ],
      );

      final postRestartReactions = {
        replyId: [
          MessageReaction(
            id: 'restart-reaction-1',
            messageId: replyId,
            emoji: '🔥',
            senderPeerId: contactPeerId,
            timestamp: '2026-02-09T15:43:00.000Z',
            createdAt: '2026-02-09T15:43:00.000Z',
          ),
        ],
      };

      await tester.pumpWidget(
        buildFeedScreen(feedItems: [preRestartItem], expandedCardId: threadId),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Editable before restart'), findsOneWidget);
      expect(find.text('Delete me after restart'), findsOneWidget);
      expect(find.text('Reply restored after restart'), findsNothing);
      expect(find.text('(edited)'), findsNothing);
      expect(find.text('This message was deleted'), findsNothing);
      expect(find.text('🔥'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [postRestartItem],
          expandedCardId: threadId,
          reactions: postRestartReactions,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Editable before restart'), findsNothing);
      expect(find.text('Delete me after restart'), findsNothing);
      expect(find.text('Edited after restart'), findsOneWidget);
      expect(find.text('Reply restored after restart'), findsOneWidget);
      expect(find.text('Quote source before restart'), findsOneWidget);
      expect(find.text('(edited)'), findsOneWidget);
      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
    },
  );

  testWidgets('copy action copies exact text and dismisses the overlay', (
    tester,
  ) async {
    setPhoneViewport(tester);

    String? copiedText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final item = ThreadFeedItem(
      id: 'thread_bob',
      timestamp: DateTime.utc(2026, 3, 1, 10),
      contactPeerId: 'bob-peer',
      contactUsername: 'Bob',
      messages: [
        ThreadMessage(
          id: 'bob-msg-1',
          text: 'Copy this exactly',
          time: '12:00',
          timestamp: DateTime.utc(2026, 3, 1, 9, 55),
          isIncoming: true,
          isUnread: true,
        ),
      ],
      unreadCount: 1,
      conversationState: ConversationState.unread,
    );

    await tester.pumpWidget(
      buildFeedScreen(
        feedItems: [item],
        onReactionSelected: (_, _) {},
        onQuoteReply: (_, _) {},
      ),
    );
    await tester.pump();

    await tester.longPress(find.text('Copy this exactly'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(MessageContextOverlay.copyActionKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(copiedText, 'Copy this exactly');
    expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
    expect(find.text('Message copied to clipboard'), findsOneWidget);
  });

  testWidgets(
    'copy action stays safe after the feed host context changes during the clipboard await',
    (tester) async {
      setPhoneViewport(tester);

      final showFeed = ValueNotifier(true);
      final clipboardCompleter = Completer<void>();
      var clipboardCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardCalls++;
          await clipboardCompleter.future;
        }
        return null;
      });
      addTearDown(() {
        if (!clipboardCompleter.isCompleted) {
          clipboardCompleter.complete();
        }
        showFeed.dispose();
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final item = ThreadFeedItem(
        id: 'thread_copy_safe',
        timestamp: DateTime.utc(2026, 3, 1, 10),
        contactPeerId: 'safe-peer',
        contactUsername: 'Safe Bob',
        messages: [
          ThreadMessage(
            id: 'safe-msg-1',
            text: 'Context can change safely',
            time: '12:00',
            timestamp: DateTime.utc(2026, 3, 1, 9, 55),
            isIncoming: true,
            isUnread: true,
          ),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showFeed,
              builder: (context, isVisible, _) {
                if (!isVisible) {
                  return const SizedBox.shrink();
                }
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(viewInsets: EdgeInsets.zero),
                  child: FeedScreen(
                    username: 'Alice',
                    feedItems: [item],
                    feedLoaded: true,
                    activeTab: 'feed',
                    onSwitchView: (_) {},
                    onToggleExpand: (_) {},
                    onReactionSelected: (_, _) {},
                    onQuoteReply: (_, _) {},
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('Context can change safely'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.copyActionKey));
      await tester.pump();

      expect(clipboardCalls, 1);

      showFeed.value = false;
      await tester.pump();

      clipboardCompleter.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Message copied to clipboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('media-only long-press hides copy action', (tester) async {
    setPhoneViewport(tester);

    final item = ThreadFeedItem(
      id: 'thread_bob',
      timestamp: DateTime.utc(2026, 3, 1, 10),
      contactPeerId: 'bob-peer',
      contactUsername: 'Bob',
      messages: [
        ThreadMessage(
          id: 'bob-msg-1',
          text: '',
          time: '12:00',
          timestamp: DateTime.utc(2026, 3, 1, 9, 55),
          isIncoming: true,
          isUnread: true,
          media: [
            MediaAttachment(
              id: 'media-1',
              messageId: 'bob-msg-1',
              mime: 'image/jpeg',
              size: 5000,
              mediaType: 'image',
              downloadStatus: 'pending',
              createdAt: '2026-03-01T09:55:00Z',
            ),
          ],
        ),
      ],
      unreadCount: 1,
      conversationState: ConversationState.unread,
    );

    await tester.pumpWidget(
      buildFeedScreen(
        feedItems: [item],
        onReactionSelected: (_, _) {},
        onQuoteReply: (_, _) {},
      ),
    );
    await tester.pump();

    await tester.longPress(find.byType(MessageBubble));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
    expect(find.byKey(MessageContextOverlay.copyActionKey), findsNothing);
  });

  testWidgets(
    'whitespace-only long-press hides edit and copy but keeps reply and delete available in feed',
    (tester) async {
      setPhoneViewport(tester);

      final item = ThreadFeedItem(
        id: 'thread_spaces',
        timestamp: DateTime.utc(2026, 3, 1, 10, 10),
        contactPeerId: 'spaces-peer',
        contactUsername: 'Space Bob',
        messages: [
          ThreadMessage(
            id: 'spaces-incoming',
            text: 'Earlier incoming',
            time: '12:00',
            timestamp: DateTime.utc(2026, 3, 1, 10, 0),
            isIncoming: true,
          ),
          ThreadMessage(
            id: 'spaces-outgoing',
            text: '   \n\t  ',
            time: '12:10',
            timestamp: DateTime.utc(2026, 3, 1, 10, 10),
            isIncoming: false,
            status: 'delivered',
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [item],
          expandedCardId: 'thread_spaces',
          onReactionSelected: (_, _) {},
          onEditMessage: (_, __) {},
          onDeleteMessage: (_, __) {},
        ),
      );
      await tester.pump();

      await tester.longPress(find.byType(MessageBubble).last);
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);
      expect(find.byKey(MessageContextOverlay.copyActionKey), findsNothing);
      expect(find.byKey(MessageContextOverlay.deleteActionKey), findsOneWidget);
    },
  );
}
