import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_screen.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../share/application/announcement_forward_test_harness.dart';

void main() {
  testWidgets(
    'reader opens Forward picker for verified media while announcement compose remains read-only',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);
      await harness.contacts.addContact(harness.contact('picker-contact'));
      final group = (await harness.groups.getGroup(announcementSourceGroupId))!;
      final groupListener = GroupMessageListener(
        groupRepo: harness.groups,
        msgRepo: harness.groupMessages,
      );
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream<ChatMessage>.empty(),
        messageRepo: harness.directMessages,
        contactRepo: harness.contacts,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationWired(
            group: group,
            groupRepo: harness.groups,
            msgRepo: harness.groupMessages,
            groupMessageListener: groupListener,
            bridge: harness.bridge,
            identityRepo: harness.identities,
            contactRepo: harness.contacts,
            p2pService: harness.p2p,
            mediaAttachmentRepo: harness.media,
            mediaFileManager: harness.fileManager,
            imageProcessor: AnnouncementForwardHarness.imageProcessor(),
            forwardMessageRepository: harness.directMessages,
            forwardChatMessageListener: chatListener,
          ),
        ),
      );
      final cell = find.byKey(
        const ValueKey(
          'media-grid-cell-$announcementSourceMessageId-$announcementSourceAttachmentId',
        ),
      );
      for (var i = 0; i < 60 && !tester.any(cell); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump();
      }

      expect(
        find.byKey(const ValueKey('group-read-only-banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('composer-attach-button')),
        findsNothing,
      );
      expect(cell, findsOneWidget);
      await tester.tap(cell);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
      expect(
        find.byKey(const ValueKey('media_action_forward')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('media_action_reply')), findsNothing);
      expect(find.byKey(const ValueKey('media_action_quote')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('media_action_forward')));
      final pickerWired = find.byType(ShareTargetPickerWired);
      for (var i = 0; i < 60 && !tester.any(pickerWired); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump();
      }
      expect(pickerWired, findsOneWidget);
      final picker = tester.widget<ShareTargetPickerScreen>(
        find.byType(ShareTargetPickerScreen),
      );
      expect(picker.sharedFilePaths, [harness.sourceFile.path]);
      expect(picker.sharedText, 'source caption');
      expect(find.byKey(const ValueKey('share-preview-image')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-caption-field')), findsOneWidget);
    },
  );
}
