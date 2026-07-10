import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/announcement_forward_test_harness.dart';

class _RecordingCoordinator implements ShareBatchDeliveryCoordinator {
  final List<List<ShareTargetSelection>> calls = [];

  @override
  Future<ShareBatchDeliveryResult> deliver({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
    ShareBatchDeliveryProgressCallback? onProgress,
  }) => throw UnimplementedError();

  @override
  Future<ShareBatchDeliveryResult> deliverGroupMediaForward({
    required request,
    String? caption,
    required List<ShareTargetSelection> targets,
  }) async {
    calls.add(List.of(targets));
    return ShareBatchDeliveryResult(
      results: targets
          .map(
            (target) => ShareBatchTargetResult(
              target: target,
              status: ShareBatchTargetStatus.sent,
              detail: 'Sent.',
            ),
          )
          .toList(growable: false),
    );
  }
}

Future<void> _pumpPicker(
  WidgetTester tester,
  AnnouncementForwardHarness harness,
  _RecordingCoordinator coordinator,
) async {
  final chatListener = ChatMessageListener(
    chatMessageStream: const Stream<ChatMessage>.empty(),
    messageRepo: harness.directMessages,
    contactRepo: harness.contacts,
  );
  final groupListener = GroupMessageListener(
    groupRepo: harness.groups,
    msgRepo: harness.groupMessages,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ShareTargetPickerWired(
        shareIntent: ShareIntent(
          type: ShareIntentType.mixed,
          text: 'source caption',
          filePaths: [harness.sourceFile.path],
        ),
        identityRepo: harness.identities,
        contactRepository: harness.contacts,
        messageRepository: harness.directMessages,
        mediaAttachmentRepository: harness.media,
        chatMessageListener: chatListener,
        bridge: harness.bridge,
        p2pService: harness.p2p,
        mediaFileManager: harness.fileManager,
        imageProcessor: AnnouncementForwardHarness.imageProcessor(),
        groupRepository: harness.groups,
        groupMessageRepository: harness.groupMessages,
        groupMessageListener: groupListener,
        batchShareCoordinator: coordinator,
        groupMediaForwardRequest: harness.request(),
        onClose: (_) async {},
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<({GroupModel chat, GroupModel adminAnnouncement})> _seedTargets(
  AnnouncementForwardHarness harness,
) async {
  await harness.contacts.addContact(harness.contact('active-contact'));
  final blocked = harness.contact('blocked-contact');
  await harness.contacts.addContact(blocked);
  await harness.contacts.blockContact(blocked.peerId);
  final chat = harness.group('target-chat');
  final adminAnnouncement = harness.group(
    'target-admin-announcement',
    type: GroupType.announcement,
    role: GroupRole.admin,
  );
  final readerAnnouncement = harness.group(
    'target-reader-announcement',
    type: GroupType.announcement,
    role: GroupRole.member,
  );
  final qa = harness.group(
    'target-qa',
    type: GroupType.qa,
    role: GroupRole.admin,
  );
  for (final group in [chat, adminAnnouncement, readerAnnouncement, qa]) {
    await harness.seedWritableGroup(group);
  }
  return (chat: chat, adminAnnouncement: adminAnnouncement);
}

void main() {
  testWidgets(
    'announcement forward lists only allowed contact and group targets',
    (tester) async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);
      await _seedTargets(harness);
      final coordinator = _RecordingCoordinator();
      await _pumpPicker(tester, harness, coordinator);

      expect(find.text('active-contact'), findsOneWidget);
      expect(find.text('blocked-contact'), findsNothing);
      expect(find.text('target-chat'), findsOneWidget);
      expect(find.text('target-admin-announcement'), findsOneWidget);
      expect(find.text('target-reader-announcement'), findsNothing);
      expect(find.text('target-qa'), findsNothing);
      expect(find.text(announcementSourceGroupId), findsNothing);
    },
  );

  testWidgets(
    'send-time revalidation removes a demoted announcement target and preserves valid targets',
    (tester) async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);
      final targets = await _seedTargets(harness);
      final coordinator = _RecordingCoordinator();
      await _pumpPicker(tester, harness, coordinator);

      await tester.tap(
        find.byKey(const ValueKey('share-contact-active-contact')),
      );
      await tester.tap(find.byKey(const ValueKey('share-group-target-chat')));
      await tester.tap(
        find.byKey(const ValueKey('share-group-target-admin-announcement')),
      );
      await tester.pump();

      await harness.contacts.blockContact('active-contact');
      await harness.groups.saveGroup(
        targets.adminAnnouncement.copyWith(myRole: GroupRole.member),
      );
      await tester.tap(find.text('Send'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(coordinator.calls, hasLength(1));
      expect(coordinator.calls.single.map((target) => target.key), [
        'group:${targets.chat.id}',
      ]);
      expect(
        coordinator.calls.single.map((target) => target.key),
        isNot(contains('group:$announcementSourceGroupId')),
      );
    },
  );
}
