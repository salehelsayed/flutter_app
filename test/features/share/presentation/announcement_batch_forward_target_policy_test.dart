import 'package:flutter/material.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/groups/application/announcement_media_forward_request.dart';
import 'package:flutter_app/features/groups/application/group_media_batch_forward.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/share/application/group_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_app/features/share/presentation/navigation/group_media_batch_forward_picker_route.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../application/announcement_forward_test_harness.dart';

void main() {
  testWidgets('routed batch picker target set is exact', (tester) async {
    final harness = AnnouncementForwardHarness();
    await harness.setUp();
    addTearDown(harness.dispose);
    await harness.contacts.addContact(harness.contact('active-contact'));
    final blocked = harness.contact('blocked-contact');
    await harness.contacts.addContact(blocked);
    await harness.contacts.blockContact(blocked.peerId);
    final chat = harness.group('target-chat');
    final chatReader = harness.group('target-chat-reader');
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
    final splitRoleAnnouncement = harness.group(
      'target-split-role-announcement',
      type: GroupType.announcement,
      role: GroupRole.admin,
    );
    final qa = harness.group(
      'target-qa',
      type: GroupType.qa,
      role: GroupRole.admin,
    );
    for (final group in [
      chat,
      chatReader,
      adminAnnouncement,
      readerAnnouncement,
      splitRoleAnnouncement,
      qa,
    ]) {
      await harness.seedWritableGroup(group);
    }
    await harness.groups.updateMemberRole(
      chatReader.id,
      announcementOwnPeerId,
      MemberRole.reader,
    );
    await harness.groups.updateMemberRole(
      splitRoleAnnouncement.id,
      announcementOwnPeerId,
      MemberRole.reader,
    );

    await _pump(tester, harness, _draft(announcement: true));

    expect(
      find.byKey(const ValueKey('group-batch-forward-contact-active-contact')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('group-batch-forward-contact-blocked-contact')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('group-batch-forward-group-target-chat')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('group-batch-forward-group-target-chat-reader'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('group-batch-forward-group-target-admin-announcement'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('group-batch-forward-group-target-reader-announcement'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey(
          'group-batch-forward-group-target-split-role-announcement',
        ),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('group-batch-forward-group-target-qa')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('group-batch-forward-group-announcement-source-A'),
      ),
      findsNothing,
      reason: 'the source announcement is never a destination',
    );
  });

  testWidgets('discussion batch never widens to announcement targets', (
    tester,
  ) async {
    final harness = AnnouncementForwardHarness();
    await harness.setUp();
    addTearDown(harness.dispose);
    final chat = harness.group('target-chat');
    final announcement = harness.group(
      'target-admin-announcement',
      type: GroupType.announcement,
      role: GroupRole.admin,
    );
    await harness.seedWritableGroup(chat);
    await harness.seedWritableGroup(announcement);

    await _pump(tester, harness, _draft(announcement: false));

    expect(
      find.byKey(const ValueKey('group-batch-forward-group-target-chat')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('group-batch-forward-group-target-admin-announcement'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'real route sends edited draft to selected target through coordinator once',
    (tester) async {
      final wakeLock = FakeUploadWakeLockDriver();
      UploadWakeLockController.debugReset(driver: wakeLock);
      addTearDown(UploadWakeLockController.debugReset);
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);
      final contact = harness.contact('route-contact');
      await harness.contacts.addContact(contact);
      final draft = _draft(announcement: true);
      final routeResults = <GroupMediaBatchForwardCompletion?>[];
      final delivery = _RecordingDeliveryCoordinator();

      await _pump(
        tester,
        harness,
        draft,
        deliveryCoordinator: delivery,
        onResult: routeResults.add,
      );
      await tester.enterText(
        find.byKey(const ValueKey('group-batch-forward-caption-0')),
        'edited route caption',
      );
      await tester.tap(
        find.byKey(const ValueKey('group-batch-forward-contact-route-contact')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('group-batch-forward-send')));
      for (var index = 0; index < 12; index++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(delivery.initialCalls, 1);
      expect(
        delivery.initialDraft?.items.first.caption,
        'edited route caption',
      );
      expect(delivery.initialDraft?.items.last.caption, 'caption 2');
      expect(delivery.initialTargets, hasLength(1));
      expect(delivery.initialTargets.single.key, 'contact:${contact.peerId}');
      expect(routeResults, hasLength(1));
      expect(routeResults.single, isNotNull);
      expect(
        routeResults.single!.fullySettledSourceIdentities,
        draft.items.map((item) => item.identity).toSet(),
      );
      expect(routeResults.single!.failedSourceIdentities, isEmpty);
      expect(
        find.byKey(const ValueKey('group-batch-forward-picker')),
        findsNothing,
      );
      expect(wakeLock.enableCalls, 1);
      expect(wakeLock.disableCalls, 1);
    },
  );

  testWidgets(
    'picker fails closed without coherent capability or exact key generation',
    (tester) async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);
      final destination = harness.group('snapshot-required-chat');
      await harness.seedWritableGroup(destination);
      final draft = _draft(announcement: true);

      await _pump(
        tester,
        harness,
        draft,
        groupRepository: _NoSnapshotPickerRepository(harness.groups),
      );
      expect(
        find.byKey(
          const ValueKey('group-batch-forward-group-snapshot-required-chat'),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('group-batch-forward-close')));
      for (var index = 0; index < 8; index++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      await _pump(
        tester,
        harness,
        draft,
        groupRepository: _KeyDriftPickerRepository(harness.groups),
      );
      expect(
        find.byKey(
          const ValueKey('group-batch-forward-group-snapshot-required-chat'),
        ),
        findsNothing,
      );
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  AnnouncementForwardHarness harness,
  GroupMediaBatchForwardDraft draft, {
  GroupMediaBatchForwardDeliveryCoordinator? deliveryCoordinator,
  GroupRepository? groupRepository,
  ValueChanged<GroupMediaBatchForwardCompletion?>? onResult,
}) async {
  final delivery =
      deliveryCoordinator ??
      GroupMediaBatchForwardDeliveryCoordinator(
        revalidateForDispatch: (candidate) async =>
            GroupMediaBatchForwardBuildResult.ready(candidate),
        deliverSingle: ({required request, caption, required targets}) async =>
            ShareBatchDeliveryResult(
              results: [
                for (final target in targets)
                  ShareBatchTargetResult(
                    target: target,
                    status: ShareBatchTargetStatus.sent,
                    detail: 'sent',
                  ),
              ],
            ),
      );
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            key: const ValueKey('open-group-batch-forward-picker'),
            onPressed: () async {
              final result = await Navigator.of(context)
                  .push<GroupMediaBatchForwardCompletion>(
                    buildGroupMediaBatchForwardPickerRoute(
                      draft: draft,
                      identityRepository: harness.identities,
                      contactRepository: harness.contacts,
                      groupRepository: groupRepository ?? harness.groups,
                      deliveryCoordinator: delivery,
                    ),
                  );
              onResult?.call(result);
            },
            child: const Text('Open batch forward'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(
    find.byKey(const ValueKey('open-group-batch-forward-picker')),
  );
  for (var index = 0; index < 8; index++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

class _RecordingDeliveryCoordinator
    extends GroupMediaBatchForwardDeliveryCoordinator {
  _RecordingDeliveryCoordinator()
    : super(
        revalidateForDispatch: (candidate) async =>
            GroupMediaBatchForwardBuildResult.ready(candidate),
        deliverSingle: ({required request, caption, required targets}) async {
          return ShareBatchDeliveryResult(
            results: [
              for (final target in targets)
                ShareBatchTargetResult(
                  target: target,
                  status: ShareBatchTargetStatus.sent,
                  detail: 'sent',
                ),
            ],
          );
        },
      );

  int initialCalls = 0;
  GroupMediaBatchForwardDraft? initialDraft;
  List<ShareTargetSelection> initialTargets = const [];

  @override
  Future<GroupMediaBatchForwardAttemptResult> deliverInitial({
    required GroupMediaBatchForwardDraft draft,
    required List<ShareTargetSelection> targets,
    GroupMediaBatchForwardProgressCallback? onProgress,
  }) {
    initialCalls++;
    initialDraft = draft;
    initialTargets = List.unmodifiable(targets);
    return super.deliverInitial(
      draft: draft,
      targets: targets,
      onProgress: onProgress,
    );
  }
}

class _NoSnapshotPickerRepository implements GroupRepository {
  _NoSnapshotPickerRepository(this.backing);

  final GroupRepository backing;

  @override
  Future<List<GroupModel>> getActiveGroups() => backing.getActiveGroups();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _KeyDriftPickerRepository
    implements GroupRepository, GroupForwardAuthorizationSnapshotRepository {
  _KeyDriftPickerRepository(this.backing);

  final GroupRepository backing;

  @override
  Future<List<GroupModel>> getActiveGroups() => backing.getActiveGroups();

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) =>
      backing.getLatestKey(groupId);

  @override
  Future<GroupForwardAuthorizationSnapshot?>
  loadGroupForwardAuthorizationSnapshot(String groupId) async {
    final snapshotRepo = backing as GroupForwardAuthorizationSnapshotRepository;
    final snapshot = await snapshotRepo.loadGroupForwardAuthorizationSnapshot(
      groupId,
    );
    if (snapshot == null) return null;
    return GroupForwardAuthorizationSnapshot(
      group: snapshot.group,
      members: snapshot.members,
      latestKeyGeneration: (snapshot.latestKeyGeneration ?? 0) + 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GroupMediaBatchForwardDraft _draft({required bool announcement}) {
  final sourceGroupId = announcement
      ? announcementSourceGroupId
      : 'discussion-source';
  GroupMediaBatchForwardItemDraft item(int index) {
    final identity = GroupSharedMediaIdentity(
      groupId: sourceGroupId,
      messageId: 'source-message-$index',
      attachmentId: 'source-attachment-$index',
    );
    final provenance = ForwardProvenance(
      operationDedupKey: 'opaque-unit-${index == 1 ? 'one' : 'two'}',
    );
    final request = announcement
        ? AnnouncementMediaForwardRequest(
            groupId: sourceGroupId,
            messageId: identity.messageId,
            attachmentId: identity.attachmentId,
            initialCaption: 'caption $index',
            provenance: provenance,
          )
        : GroupMediaForwardRequest(
            groupId: sourceGroupId,
            messageId: identity.messageId,
            attachmentId: identity.attachmentId,
            initialCaption: 'caption $index',
            provenance: provenance,
          );
    return GroupMediaBatchForwardItemDraft(
      identity: identity,
      request: request,
      resolvedPath: '/safe/source-$index.jpg',
      parentTimestamp: DateTime.utc(2026, 7, 12 - index),
      mime: 'image/jpeg',
      sizeBytes: 128,
      caption: 'caption $index',
    );
  }

  return GroupMediaBatchForwardDraft(
    sourceGroupId: sourceGroupId,
    sourceKind: announcement
        ? GroupMediaBatchForwardSourceKind.announcement
        : GroupMediaBatchForwardSourceKind.discussion,
    items: [item(1), item(2)],
  );
}
