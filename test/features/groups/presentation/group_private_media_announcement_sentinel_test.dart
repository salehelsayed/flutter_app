import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'GPL-15 availability-off private rows are generic while announcement rows stay ordinary',
    (tester) async {
      final attachment = MediaAttachment(
        id: 'attachment-a',
        messageId: 'message-a',
        mime: 'image/jpeg',
        size: 64,
        mediaType: 'image',
        downloadStatus: 'pending',
        createdAt: '2026-07-12T12:00:00.000Z',
        ownerLane: MediaOwnerLane.group,
      );

      await tester.pumpWidget(
        _app(
          group: _group(GroupType.chat),
          message: _message(
            text: 'TOP SECRET PRIVATE BODY',
            policy: const GroupPrivateMediaPolicy.viewOnce(),
          ),
          attachment: attachment,
        ),
      );
      await tester.pump();

      expect(find.text('TOP SECRET PRIVATE BODY'), findsNothing);
      expect(find.text('Media unavailable'), findsOneWidget);
      expect(find.byType(MediaGridCell), findsNothing);

      await tester.pumpWidget(
        _app(
          group: _group(GroupType.announcement),
          message: _message(
            text: 'ANNOUNCEMENT ORDINARY BODY',
            policy: const GroupPrivateMediaPolicy.ordinary(),
          ),
          attachment: attachment,
        ),
      );
      await tester.pump();

      expect(find.text('ANNOUNCEMENT ORDINARY BODY'), findsOneWidget);
      expect(find.byType(MediaGridCell), findsOneWidget);
    },
  );

  testWidgets(
    'GPL-15Q ordinary replies quote private and unsupported parents only as generic unavailable',
    (tester) async {
      const secret = 'QUOTED PRIVATE BODY MUST NEVER RENDER';
      final attachment = MediaAttachment(
        id: 'attachment-parent',
        messageId: 'message-parent',
        mime: 'image/jpeg',
        size: 64,
        mediaType: 'image',
        downloadStatus: 'pending',
        createdAt: '2026-07-12T12:00:00.000Z',
        ownerLane: MediaOwnerLane.group,
      );

      for (final policy in const <GroupPrivateMediaPolicy>[
        GroupPrivateMediaPolicy.viewOnce(),
        GroupPrivateMediaPolicy.unsupported(sourceVersion: 9),
      ]) {
        final parent = _message(
          id: 'message-parent',
          text: secret,
          policy: policy,
        );
        final child = _message(
          id: 'message-child',
          text: 'ordinary reply',
          policy: const GroupPrivateMediaPolicy.ordinary(),
          quotedMessageId: parent.id,
        );
        final (
          activeQuoteText,
          activeQuoteUnavailable,
        ) = resolveGroupQuotedPreview(
          quoted: parent,
          quotedMedia: [attachment],
          privatePlaceholder: 'Media unavailable',
        );
        expect(activeQuoteText, 'Media unavailable');
        expect(activeQuoteUnavailable, isFalse);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GroupConversationScreen(
              group: _group(GroupType.chat),
              messages: [parent, child],
              ownPeerId: 'self-peer',
              onSend: (_) {},
              onBack: () {},
              initialLoadDone: true,
              mediaMap: {
                parent.id: [attachment],
              },
            ),
          ),
        );
        await tester.pump();

        expect(find.text(secret), findsNothing);
        expect(find.text('Media unavailable'), findsNWidgets(2));
        expect(find.text('ordinary reply'), findsOneWidget);
      }
    },
  );
}

Widget _app({
  required GroupModel group,
  required GroupMessage message,
  required MediaAttachment attachment,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: GroupConversationScreen(
      group: group,
      messages: [message],
      ownPeerId: 'self-peer',
      onSend: (_) {},
      onBack: () {},
      initialLoadDone: true,
      mediaMap: {
        message.id: [attachment.copyWith(messageId: message.id)],
      },
    ),
  );
}

GroupModel _group(GroupType type) => GroupModel(
  id: 'group-a',
  name: 'Group A',
  type: type,
  topicName: 'topic-a',
  createdAt: DateTime.utc(2026, 7, 12),
  createdBy: 'self-peer',
  myRole: GroupRole.admin,
);

GroupMessage _message({
  String id = 'message-a',
  required String text,
  required GroupPrivateMediaPolicy policy,
  String? quotedMessageId,
}) => GroupMessage(
  id: id,
  groupId: 'group-a',
  senderPeerId: 'sender-peer',
  senderUsername: 'Sender',
  text: text,
  quotedMessageId: quotedMessageId,
  timestamp: DateTime.utc(2026, 7, 12, 12),
  isIncoming: true,
  privateMediaPolicy: policy,
  createdAt: DateTime.utc(2026, 7, 12, 12),
);
