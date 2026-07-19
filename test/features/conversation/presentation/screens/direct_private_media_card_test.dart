import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/private_media_action_eligibility.dart';
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

  testWidgets('terminal and unsupported cards keep action rows in-bubble', (
    tester,
  ) async {
    final consumed = privateMessage(
      id: 'consumed-private',
      isIncoming: true,
      policy: const PrivateMediaPolicy.viewOnce(),
      state: PrivateMediaLifecycleState.consumed,
    );
    final unsupported = privateMessage(
      id: 'unsupported-private',
      isIncoming: true,
      policy: const PrivateMediaPolicy.unsupported(sourceVersion: 9),
      state: PrivateMediaLifecycleState.unsupported,
    );
    final parents = {consumed.id: consumed, unsupported.id: unsupported};
    final replies = <String>[];
    final deletions = <String>[];

    await pumpConversation(
      tester,
      messages: [consumed, unsupported],
      onQuoteReply: replies.add,
      onDeleteMessage: deletions.add,
      onLoadPrivateParentDecision: (messageId) async {
        return DirectPrivateMediaActionEligibility.evaluate(
          parent: parents[messageId],
          attachment: null,
          expectedMessageId: messageId,
          attachmentRequired: false,
          requireIncoming: false,
        );
      },
    );

    expect(
      find.descendant(
        of: slot(consumed.id),
        matching: find.byKey(const ValueKey('private-terminal-consumed')),
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
    for (final messageId in parents.keys) {
      expectSlotInsideDecoratedBody(tester, messageId);
      final scopedSlot = slot(messageId);
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

    await tester.tap(
      find.descendant(
        of: slot(consumed.id),
        matching: find.byKey(const ValueKey('private-action-reply')),
      ),
    );
    await tester.pump();
    expect(replies, [consumed.id]);

    await tester.tap(
      find.descendant(
        of: slot(unsupported.id),
        matching: find.byKey(const ValueKey('private-action-deleteForMe')),
      ),
    );
    await tester.pump();
    expect(deletions, [unsupported.id]);
  });
}
