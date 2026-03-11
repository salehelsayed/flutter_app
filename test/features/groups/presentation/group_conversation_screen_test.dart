import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';

void main() {
  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-1',
    myRole: GroupRole.admin,
  );

  final testMessages = [
    GroupMessage(
      id: 'msg-1',
      groupId: 'group-1',
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: 'Hello everyone!',
      timestamp: DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
      isIncoming: true,
    ),
  ];

  Widget buildTestWidget({
    List<GroupMessage> messages = const [],
    bool canWrite = true,
    GroupModel? group,
    bool initialLoadDone = false,
    ValueListenable<ConversationComposerViewState>? composerStateListenable,
    String? activeQuoteText,
    bool isActiveQuoteUnavailable = false,
    VoidCallback? onClearQuote,
    ValueChanged<String>? onQuoteReply,
    Map<String, List<MediaAttachment>> mediaMap = const {},
  }) {
    return MaterialApp(
      home: Scaffold(
        body: GroupConversationScreen(
          group: group ?? testGroup,
          messages: messages,
          ownPeerId: 'peer-1',
          onSend: (_) {},
          onBack: () {},
          canWrite: canWrite,
          initialLoadDone: initialLoadDone,
          composerStateListenable: composerStateListenable,
          activeQuoteText: activeQuoteText,
          isActiveQuoteUnavailable: isActiveQuoteUnavailable,
          onClearQuote: onClearQuote,
          onQuoteReply: onQuoteReply,
          mediaMap: mediaMap,
        ),
      ),
    );
  }

  testWidgets('renders messages', (tester) async {
    await tester.pumpWidget(buildTestWidget(messages: testMessages));

    expect(find.text('Hello everyone!'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('shows compose area when canWrite is true', (tester) async {
    await tester.pumpWidget(buildTestWidget(canWrite: true));

    expect(find.text('Write something...'), findsOneWidget);
  });

  testWidgets('renders active quote preview and dismisses it', (tester) async {
    var cleared = false;

    await tester.pumpWidget(
      buildTestWidget(
        activeQuoteText: 'Quoted target',
        onClearQuote: () => cleared = true,
      ),
    );

    expect(find.text('Quoted target'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(cleared, isTrue);
  });

  testWidgets('shows loading shell while initial group page is still loading', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pump();

    expect(find.byKey(const ValueKey('group-loading-shell')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('group-loading-bubble-0')),
      findsOneWidget,
    );
    expect(find.text('No messages yet'), findsNothing);
  });

  testWidgets('shows empty state once group load completes with no messages', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget(initialLoadDone: true));
    await tester.pump();

    expect(find.byKey(const ValueKey('group-loading-shell')), findsNothing);
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('hides compose area for readers in announcement group', (
    tester,
  ) async {
    final announcementGroup = GroupModel(
      id: 'group-2',
      name: 'Announcements',
      type: GroupType.announcement,
      topicName: 'topic-2',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );

    await tester.pumpWidget(
      buildTestWidget(group: announcementGroup, canWrite: false),
    );

    expect(
      find.text('Only admins can send messages in this group'),
      findsOneWidget,
    );
  });

  testWidgets(
    'composer listenable updates do not rebuild header or message list',
    (tester) async {
      final composerState = ValueNotifier(
        const ConversationComposerViewState(),
      );
      addTearDown(composerState.dispose);

      await tester.pumpWidget(
        buildTestWidget(
          messages: testMessages,
          composerStateListenable: composerState,
        ),
      );
      await tester.pump();

      final headerElement = tester.element(
        find.byKey(const ValueKey('group-header')),
      );
      final listElement = tester.element(
        find.byKey(const ValueKey('group-messages')),
      );

      composerState.value = const ConversationComposerViewState(
        isRecording: true,
        recordingDuration: Duration(seconds: 4),
        amplitudeValues: [0.1, 0.3, 0.8],
      );
      await tester.pump();

      expect(find.text('0:04'), findsOneWidget);
      expect(
        identical(
          headerElement,
          tester.element(find.byKey(const ValueKey('group-header'))),
        ),
        isTrue,
      );
      expect(
        identical(
          listElement,
          tester.element(find.byKey(const ValueKey('group-messages'))),
        ),
        isTrue,
      );

      composerState.value = const ConversationComposerViewState(
        isProcessing: true,
        processingProgress: 0.6,
      );
      await tester.pump();

      expect(find.text('60%'), findsOneWidget);
      expect(
        identical(
          headerElement,
          tester.element(find.byKey(const ValueKey('group-header'))),
        ),
        isTrue,
      );
      expect(
        identical(
          listElement,
          tester.element(find.byKey(const ValueKey('group-messages'))),
        ),
        isTrue,
      );
    },
  );

  testWidgets('wraps incoming messages with swipe-to-quote when enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(messages: testMessages, onQuoteReply: (_) {}),
    );

    expect(find.byType(SwipeToQuoteBubble), findsOneWidget);
  });

  testWidgets('does not wrap outgoing messages with swipe-to-quote', (
    tester,
  ) async {
    final outgoing = [
      GroupMessage(
        id: 'msg-out',
        groupId: 'group-1',
        senderPeerId: 'peer-1',
        senderUsername: 'You',
        text: 'Sent by me',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: false,
      ),
    ];

    await tester.pumpWidget(
      buildTestWidget(messages: outgoing, onQuoteReply: (_) {}),
    );

    expect(find.byType(SwipeToQuoteBubble), findsNothing);
  });

  testWidgets(
    'does not wrap incoming messages with swipe-to-quote for readers',
    (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          messages: testMessages,
          canWrite: false,
          onQuoteReply: (_) {},
        ),
      );

      expect(find.byType(SwipeToQuoteBubble), findsNothing);
    },
  );

  testWidgets('renders quoted replies from existing parent messages', (
    tester,
  ) async {
    final messages = [
      GroupMessage(
        id: 'msg-parent',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: 'Original group message',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: true,
      ),
      GroupMessage(
        id: 'msg-reply',
        groupId: 'group-1',
        senderPeerId: 'peer-3',
        senderUsername: 'Bob',
        text: 'Reply message',
        quotedMessageId: 'msg-parent',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: true,
      ),
    ];

    await tester.pumpWidget(buildTestWidget(messages: messages));

    expect(find.text('Original group message'), findsWidgets);
    expect(find.text('Reply message'), findsOneWidget);
  });

  testWidgets('renders unavailable fallback when quoted parent is missing', (
    tester,
  ) async {
    final messages = [
      GroupMessage(
        id: 'msg-reply',
        groupId: 'group-1',
        senderPeerId: 'peer-3',
        senderUsername: 'Bob',
        text: 'Reply message',
        quotedMessageId: 'missing-parent',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        isIncoming: true,
      ),
    ];

    await tester.pumpWidget(buildTestWidget(messages: messages));

    expect(find.text('Message unavailable'), findsOneWidget);
  });

  testWidgets('resolves quoted media-only parent from mediaMap', (
    tester,
  ) async {
    final parent = GroupMessage(
      id: 'msg-media-parent',
      groupId: 'group-1',
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: '',
      timestamp: DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
      isIncoming: true,
    );
    final reply = GroupMessage(
      id: 'msg-media-reply',
      groupId: 'group-1',
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: 'Replying to the photo',
      quotedMessageId: 'msg-media-parent',
      timestamp: DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
      isIncoming: true,
    );
    final mediaAttachment = MediaAttachment(
      id: 'blob-parent-1',
      messageId: 'msg-media-parent',
      mime: 'image/jpeg',
      size: 1024,
      mediaType: 'image',
      downloadStatus: 'done',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

    await tester.pumpWidget(
      buildTestWidget(
        messages: [parent, reply],
        mediaMap: {
          'msg-media-parent': [mediaAttachment],
        },
      ),
    );

    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Message unavailable'), findsNothing);
  });
}
