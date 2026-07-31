import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

void main() {
  const ownPeerId = '12D3KooWOwnPrivateCardPeer';
  const contactPeerId = '12D3KooWContactPrivateCardPeer';

  MediaAttachment attachment({
    required String id,
    required String messageId,
    required String mime,
    required String mediaType,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: 42,
      mediaType: mediaType,
      localPath: '/private/$id',
      downloadStatus: 'done',
      createdAt: '2026-07-19T10:00:00.000Z',
      ownerLane: MediaOwnerLane.direct,
    );
  }

  ConversationMessage privateMessage({
    required String id,
    required bool isIncoming,
    required PrivateMediaPolicy policy,
    required PrivateMediaLifecycleState state,
    List<MediaAttachment> media = const [],
    String status = 'delivered',
    String? transport,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: contactPeerId,
      senderPeerId: isIncoming ? contactPeerId : ownPeerId,
      text: '',
      timestamp: '2026-07-19T10:00:00.000Z',
      status: status,
      isIncoming: isIncoming,
      createdAt: '2026-07-19T10:00:00.000Z',
      transport: transport,
      privateMediaPolicy: policy,
      privateMediaState: state,
      media: media,
    );
  }

  Future<void> pumpConversation(
    WidgetTester tester, {
    required List<ConversationMessage> messages,
    Map<String, List<MessageReaction>> reactions = const {},
    ValueChanged<String>? onQuoteReply,
    ValueChanged<String>? onDeleteMessage,
    DirectPrivateParentDecisionLoader? onLoadPrivateParentDecision,
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ConversationScreen(
            contactPeerId: contactPeerId,
            contactUsername: 'Alice',
            connectionDate: 'July 19, 2026',
            ownPeerId: ownPeerId,
            messages: messages,
            onSend: (_) {},
            onBack: () {},
            initialLoadDone: true,
            hasMoreOlderMessages: false,
            reactions: reactions,
            onReactionSelected: (_, _) {},
            onQuoteReply: onQuoteReply,
            onDeleteMessage: onDeleteMessage,
            onLoadPrivateParentDecision: onLoadPrivateParentDecision,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  Finder row(String messageId) => find.byKey(ValueKey('msg-$messageId'));
  Finder slot(String messageId) =>
      find.byKey(ValueKey('private-media-slot-$messageId'));
  Finder decoratedBody(String messageId) =>
      find.byKey(ValueKey('private-media-decorated-body-$messageId'));

  LetterCard letterCardUnder(WidgetTester tester, Finder root) {
    final card = find.descendant(of: root, matching: find.byType(LetterCard));
    expect(card, findsOneWidget);
    return tester.widget<LetterCard>(card);
  }

  LetterCard liveLetterCard(WidgetTester tester, String messageId) =>
      letterCardUnder(tester, row(messageId));

  void expectCompactReceiptGeometry(WidgetTester tester, String messageId) {
    final messageRow = row(messageId);
    final scopedSlot = find.descendant(
      of: messageRow,
      matching: slot(messageId),
    );
    final summary = find.descendant(
      of: scopedSlot,
      matching: find.byKey(
        const ValueKey('private-terminal-view-once-consumed-summary'),
      ),
    );
    final icon = find.descendant(
      of: summary,
      matching: find.byIcon(Icons.visibility_off_outlined),
    );
    final label = find.descendant(of: summary, matching: find.byType(Text));
    final body = find.descendant(
      of: messageRow,
      matching: decoratedBody(messageId),
    );
    expect(summary, findsOneWidget);
    expect(icon, findsOneWidget);
    expect(label, findsOneWidget);
    expect(body, findsOneWidget);

    final iconRect = tester.getRect(icon);
    final labelRect = tester.getRect(label);
    final bodyRect = tester.getRect(body);
    final visualLeft = iconRect.left < labelRect.left
        ? iconRect.left
        : labelRect.left;
    final visualRight = iconRect.right > labelRect.right
        ? iconRect.right
        : labelRect.right;
    final visualSpan = visualRight - visualLeft;

    expect(bodyRect.left, lessThanOrEqualTo(visualLeft + 1));
    expect(bodyRect.right, greaterThanOrEqualTo(visualRight - 1));
    expect(bodyRect.width, greaterThanOrEqualTo(visualSpan + 23));
    expect(
      bodyRect.width,
      lessThanOrEqualTo(visualSpan + 49),
      reason:
          'The receipt bubble should hug its content plus terminal padding '
          'and unchanged footer metadata.',
    );
  }

  AlignmentGeometry liveBubbleAlignment(WidgetTester tester, String messageId) {
    final candidates = tester
        .widgetList<Align>(
          find.descendant(of: row(messageId), matching: find.byType(Align)),
        )
        .where(
          (align) =>
              align.alignment == Alignment.centerLeft ||
              align.alignment == Alignment.centerRight,
        )
        .toList();
    expect(candidates, hasLength(1));
    return candidates.single.alignment;
  }

  void expectSlotInsideDecoratedBody(
    WidgetTester tester,
    String messageId, {
    Finder? scope,
  }) {
    final root = scope ?? row(messageId);
    final scopedSlot = find.descendant(of: root, matching: slot(messageId));
    final scopedBody = find.descendant(
      of: root,
      matching: decoratedBody(messageId),
    );
    expect(scopedSlot, findsOneWidget);
    expect(scopedBody, findsOneWidget);

    final slotRect = tester.getRect(scopedSlot);
    final bodyRect = tester.getRect(scopedBody);
    expect(slotRect.width, greaterThan(0));
    expect(slotRect.height, greaterThan(0));
    expect(bodyRect.left, lessThanOrEqualTo(slotRect.left));
    expect(bodyRect.top, lessThanOrEqualTo(slotRect.top));
    expect(bodyRect.right, greaterThanOrEqualTo(slotRect.right));
    expect(bodyRect.bottom, greaterThanOrEqualTo(slotRect.bottom));

    expect(
      find.descendant(of: scopedSlot, matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(of: scopedSlot, matching: find.byType(RawImage)),
      findsNothing,
    );
    expect(
      find.descendant(of: scopedSlot, matching: find.byType(MediaGrid)),
      findsNothing,
    );

    final visual = find.descendant(
      of: scopedSlot,
      matching: find.byKey(const ValueKey('private-media-card-visual')),
    );
    if (visual.evaluate().isNotEmpty) {
      final container = tester.widget<Container>(visual.first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.image, isNull);
    }

    final decoratedBoxes = find.descendant(
      of: scopedSlot,
      matching: find.byType(DecoratedBox),
    );
    for (final decoratedBox in tester.widgetList<DecoratedBox>(
      decoratedBoxes,
    )) {
      final decoration = decoratedBox.decoration;
      if (decoration is BoxDecoration) {
        expect(decoration.image, isNull);
      }
    }
  }

  testWidgets(
    'private media renders one cohesive in-bubble card, never an empty bubble',
    (tester) async {
      final outgoing = privateMessage(
        id: 'outgoing-photo',
        isIncoming: false,
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
        status: 'sent',
        media: [
          attachment(
            id: 'outgoing-photo-attachment',
            messageId: 'outgoing-photo',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
        ],
      );
      final incoming = privateMessage(
        id: 'incoming-video',
        isIncoming: true,
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.available,
        media: [
          attachment(
            id: 'incoming-video-attachment',
            messageId: 'incoming-video',
            mime: 'video/mp4',
            mediaType: 'video',
          ),
        ],
      );

      await pumpConversation(tester, messages: [outgoing, incoming]);

      for (final messageId in ['outgoing-photo', 'incoming-video']) {
        expect(
          find.descendant(
            of: row(messageId),
            matching: find.byType(LetterCard),
          ),
          findsOneWidget,
        );
        expect(
          liveLetterCard(tester, messageId).hugPrivateContentBubble,
          isFalse,
        );
        expectSlotInsideDecoratedBody(tester, messageId);
      }
      expect(find.byType(LetterCard), findsNWidgets(2));
    },
  );

  testWidgets('card shows no-pixel visual header and media-kind title', (
    tester,
  ) async {
    final protectedGif = privateMessage(
      id: 'protected-gif',
      isIncoming: false,
      policy: const PrivateMediaPolicy.protected(),
      state: PrivateMediaLifecycleState.available,
      status: 'sent',
      media: [
        attachment(
          id: 'protected-gif-attachment',
          messageId: 'protected-gif',
          mime: 'image/gif',
          mediaType: 'gif',
        ),
      ],
    );
    final viewOnceVideo = privateMessage(
      id: 'view-once-video',
      isIncoming: true,
      policy: const PrivateMediaPolicy.viewOnce(),
      state: PrivateMediaLifecycleState.available,
      media: [
        attachment(
          id: 'view-once-video-attachment',
          messageId: 'view-once-video',
          mime: 'video/mp4',
          mediaType: 'video',
        ),
      ],
    );

    await pumpConversation(tester, messages: [protectedGif, viewOnceVideo]);

    expect(
      find.descendant(
        of: row('protected-gif'),
        matching: find.text('Protected photo'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row('view-once-video'),
        matching: find.text('View-once video'),
      ),
      findsOneWidget,
    );
    for (final messageId in ['protected-gif', 'view-once-video']) {
      expect(
        find.descendant(
          of: row(messageId),
          matching: find.byKey(const ValueKey('private-media-card-visual')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row(messageId), matching: find.text('Alice')),
        findsNothing,
      );
      expectSlotInsideDecoratedBody(tester, messageId);
    }
  });

  testWidgets('card preserves reactions and context overlay', (tester) async {
    final message = privateMessage(
      id: 'overlay-private',
      isIncoming: false,
      policy: const PrivateMediaPolicy.protected(),
      state: PrivateMediaLifecycleState.available,
      status: 'sent',
      media: [
        attachment(
          id: 'overlay-private-attachment',
          messageId: 'overlay-private',
          mime: 'image/jpeg',
          mediaType: 'image',
        ),
      ],
    );
    final reaction = MessageReaction(
      id: 'reaction-1',
      messageId: message.id,
      emoji: '❤️',
      senderPeerId: contactPeerId,
      timestamp: '2026-07-19T10:01:00.000Z',
      createdAt: '2026-07-19T10:01:00.000Z',
    );

    await pumpConversation(
      tester,
      messages: [message],
      reactions: {
        message.id: [reaction],
      },
      onQuoteReply: (_) {},
    );

    expect(find.text('❤️'), findsOneWidget);
    await tester.longPress(
      find.byKey(const ValueKey('private-media-outgoing')),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final selected = find.byKey(MessageContextOverlay.selectedMessageKey);
    expect(selected, findsOneWidget);
    expectSlotInsideDecoratedBody(tester, message.id, scope: selected);
  });

  testWidgets(
    'consumed view-once receipt is minimal in live and lifted cards while outer reply and delete remain reachable',
    (tester) async {
      final incoming = privateMessage(
        id: 'consumed-incoming',
        isIncoming: true,
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.consumed,
        transport: 'direct',
      );
      final outgoing = privateMessage(
        id: 'consumed-outgoing',
        isIncoming: false,
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.consumed,
        status: 'sent',
        transport: 'direct',
      );
      final replies = <String>[];
      final deletions = <String>[];

      await pumpConversation(
        tester,
        messages: [incoming, outgoing],
        onQuoteReply: replies.add,
        onDeleteMessage: deletions.add,
      );

      for (final message in [incoming, outgoing]) {
        final card = liveLetterCard(tester, message.id);
        expect(card.hugPrivateContentBubble, isTrue);
        expect(card.time, isNotEmpty);
        expect(
          find.descendant(of: row(message.id), matching: find.text(card.time)),
          findsOneWidget,
        );
        expectSlotInsideDecoratedBody(tester, message.id);
        expectCompactReceiptGeometry(tester, message.id);
      }
      expect(liveBubbleAlignment(tester, incoming.id), Alignment.centerLeft);
      expect(liveBubbleAlignment(tester, outgoing.id), Alignment.centerRight);
      expect(
        find.descendant(
          of: row(incoming.id),
          matching: find.byIcon(Icons.device_hub),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row(outgoing.id),
          matching: find.byIcon(Icons.device_hub),
        ),
        findsOneWidget,
      );

      final liveSlot = slot(incoming.id);
      expect(
        find.descendant(
          of: liveSlot,
          matching: find.byKey(
            const ValueKey('private-terminal-view-once-consumed-summary'),
          ),
        ),
        findsOneWidget,
      );
      for (final key in const [
        ValueKey('private-action-reply'),
        ValueKey('private-action-info'),
        ValueKey('private-action-deleteForMe'),
      ]) {
        expect(
          find.descendant(of: liveSlot, matching: find.byKey(key)),
          findsNothing,
        );
      }

      await tester.longPress(
        find.descendant(
          of: liveSlot,
          matching: find.byKey(
            const ValueKey('private-terminal-view-once-consumed-summary'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final lifted = find.byKey(MessageContextOverlay.selectedMessageKey);
      expect(lifted, findsOneWidget);
      expect(letterCardUnder(tester, lifted).hugPrivateContentBubble, isTrue);
      expectSlotInsideDecoratedBody(tester, incoming.id, scope: lifted);
      expect(
        find.descendant(
          of: lifted,
          matching: find.byKey(
            const ValueKey('private-terminal-view-once-consumed-summary'),
          ),
        ),
        findsOneWidget,
      );
      for (final key in const [
        ValueKey('private-action-reply'),
        ValueKey('private-action-info'),
        ValueKey('private-action-deleteForMe'),
      ]) {
        expect(
          find.descendant(of: lifted, matching: find.byKey(key)),
          findsNothing,
        );
      }
      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.deleteActionKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.infoActionKey), findsNothing);

      await tester.tap(find.byKey(MessageContextOverlay.replyActionKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(replies, [incoming.id]);
      expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);

      await tester.longPress(
        find.descendant(
          of: liveSlot,
          matching: find.byKey(
            const ValueKey('private-terminal-view-once-consumed-summary'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(deletions, [incoming.id]);
    },
  );

  testWidgets('non-view-once terminal cards retain generic copy and actions', (
    tester,
  ) async {
    final consumedViewOnce = privateMessage(
      id: 'view-once-consumed-comparator',
      isIncoming: true,
      policy: const PrivateMediaPolicy.viewOnce(),
      state: PrivateMediaLifecycleState.consumed,
      transport: 'direct',
    );
    final protectedConsumed = privateMessage(
      id: 'protected-consumed',
      isIncoming: false,
      policy: const PrivateMediaPolicy.protected(),
      state: PrivateMediaLifecycleState.consumed,
      status: 'sent',
    );
    final expired = privateMessage(
      id: 'expired-private',
      isIncoming: true,
      policy: const PrivateMediaPolicy.viewOnce(),
      state: PrivateMediaLifecycleState.expired,
    );
    final unsupported = privateMessage(
      id: 'unsupported-private',
      isIncoming: true,
      policy: const PrivateMediaPolicy.unsupported(sourceVersion: 9),
      state: PrivateMediaLifecycleState.unsupported,
    );

    await pumpConversation(
      tester,
      messages: [consumedViewOnce, protectedConsumed, expired, unsupported],
      onQuoteReply: (_) {},
      onDeleteMessage: (_) {},
    );

    expect(
      liveLetterCard(tester, consumedViewOnce.id).hugPrivateContentBubble,
      isTrue,
    );
    for (final messageId in [
      protectedConsumed.id,
      expired.id,
      unsupported.id,
    ]) {
      expect(
        liveLetterCard(tester, messageId).hugPrivateContentBubble,
        isFalse,
      );
    }
    final compactWidth = tester
        .getSize(decoratedBody(consumedViewOnce.id))
        .width;
    for (final messageId in [
      protectedConsumed.id,
      expired.id,
      unsupported.id,
    ]) {
      expect(
        tester.getSize(decoratedBody(messageId)).width,
        greaterThan(compactWidth + 48),
        reason:
            'Other private terminal bubbles must retain their existing '
            'non-compact layout.',
      );
    }

    expect(
      find.descendant(
        of: slot(protectedConsumed.id),
        matching: find.byKey(const ValueKey('private-terminal-consumed')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: slot(protectedConsumed.id),
        matching: find.byKey(
          const ValueKey('private-media-terminal-generic-title'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: slot(expired.id),
        matching: find.byKey(const ValueKey('private-terminal-expired')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: slot(unsupported.id),
        matching: find.byKey(const ValueKey('private-media-unsupported')),
      ),
      findsOneWidget,
    );
    for (final messageId in [
      protectedConsumed.id,
      expired.id,
      unsupported.id,
    ]) {
      expectSlotInsideDecoratedBody(tester, messageId);
      final scopedSlot = slot(messageId);
      expect(
        find.descendant(
          of: scopedSlot,
          matching: find.byKey(
            const ValueKey('private-terminal-view-once-consumed-summary'),
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: scopedSlot,
          matching: find.byKey(const ValueKey('private-action-reply')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: scopedSlot,
          matching: find.byKey(const ValueKey('private-action-info')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: scopedSlot,
          matching: find.byKey(const ValueKey('private-action-deleteForMe')),
        ),
        findsOneWidget,
      );
    }
  });
}
