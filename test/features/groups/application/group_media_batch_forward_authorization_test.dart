import 'dart:io';

import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../share/application/announcement_forward_test_harness.dart';

void main() {
  test(
    'GBF-04 contact deletion at final reload prevents every upload',
    () async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);
      final contact = harness.contact('revoked-contact');
      final contacts = _DeleteOnSecondReadContacts(contact.peerId);
      await contacts.addContact(contact);
      final coordinator = _coordinator(
        harness: harness,
        contacts: contacts,
        groups: harness.groups,
      );

      final result = await coordinator.deliverGroupMediaForward(
        request: harness.request(),
        targets: [ShareTargetSelection.contact(contact)],
      );

      expect(result.failureCount, 1);
      expect(contacts.targetReads, 2);
      expect(harness.bridge.commandPayloads('media:upload'), isEmpty);
      expect(
        await harness.directMessages.getMessagesForContact(contact.peerId),
        isEmpty,
      );
    },
  );

  test('GBF-04 absent coherent-snapshot capability fails closed', () async {
    final harness = AnnouncementForwardHarness();
    await harness.setUp();
    addTearDown(harness.dispose);
    final destination = harness.group('missing-snapshot-capability');
    final backing = InMemoryGroupRepository();
    await _seedCanonicalSourceGroup(harness: harness, groups: backing);
    await _seedWritableTarget(backing, destination);
    final groups = _NoSnapshotGroupRepository(backing);

    await _expectDeniedGroupForward(
      harness: harness,
      groups: groups,
      destination: destination,
      request: harness.request(),
    );
  });

  test('GBF-04 own-member removal in final snapshot prevents upload', () async {
    final harness = AnnouncementForwardHarness();
    await harness.setUp();
    addTearDown(harness.dispose);
    final destination = harness.group('removed-own-member');
    final groups = _RemoveOwnMemberOnSnapshotGroups(destination.id);
    await _seedCanonicalSourceGroup(harness: harness, groups: groups);
    await _seedWritableTarget(groups, destination);

    await _expectDeniedGroupForward(
      harness: harness,
      groups: groups,
      destination: destination,
      request: harness.request(),
    );
    expect(groups.didMutate, isTrue);
  });

  test(
    'GBF-04 announcement own-member admin to reader prevents upload',
    () async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);
      final destination = harness.group(
        'demoted-announcement-member',
        type: GroupType.announcement,
        role: GroupRole.admin,
      );
      final groups = _DemoteOwnMemberOnSnapshotGroups(destination.id);
      await _seedCanonicalSourceGroup(harness: harness, groups: groups);
      await _seedWritableTarget(groups, destination);

      await _expectDeniedGroupForward(
        harness: harness,
        groups: groups,
        destination: destination,
        request: harness.request(),
      );
      expect(groups.didMutate, isTrue);
    },
  );

  test('GBF-04 chat own-member writer to reader prevents upload', () async {
    final harness = AnnouncementForwardHarness();
    await harness.setUp();
    addTearDown(harness.dispose);
    final destination = harness.group('demoted-chat-writer');
    final groups = _DemoteOwnMemberOnSnapshotGroups(destination.id);
    await _seedCanonicalSourceGroup(harness: harness, groups: groups);
    await _seedWritableTarget(
      groups,
      destination,
      ownMemberRole: MemberRole.writer,
    );

    await _expectDeniedGroupForward(
      harness: harness,
      groups: groups,
      destination: destination,
      request: harness.request(),
    );
    expect(groups.didMutate, isTrue);
  });

  test('GBF-04 hydrated key generation drift prevents upload', () async {
    final harness = AnnouncementForwardHarness();
    await harness.setUp();
    addTearDown(harness.dispose);
    final destination = harness.group('rotated-key-target');
    final groups = _RotateKeyOnSnapshotGroups(destination.id);
    await _seedCanonicalSourceGroup(harness: harness, groups: groups);
    await _seedWritableTarget(groups, destination);

    await _expectDeniedGroupForward(
      harness: harness,
      groups: groups,
      destination: destination,
      request: harness.request(),
    );
    expect(groups.didMutate, isTrue);
  });

  test('GBF-04 missing hydrated/current key prevents upload', () async {
    final harness = AnnouncementForwardHarness();
    await harness.setUp();
    addTearDown(harness.dispose);
    final destination = harness.group('missing-key-target');
    final groups = InMemoryGroupRepository();
    await _seedCanonicalSourceGroup(harness: harness, groups: groups);
    await _seedWritableTarget(groups, destination, includeKey: false);

    await _expectDeniedGroupForward(
      harness: harness,
      groups: groups,
      destination: destination,
      request: harness.request(),
    );
  });

  test(
    'GBF-04 discussion source cannot dispatch to admin announcement',
    () async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);
      final destination = harness.group(
        'announcement-from-discussion',
        type: GroupType.announcement,
        role: GroupRole.admin,
      );
      await _seedWritableTarget(harness.groups, destination);
      final request = GroupMediaForwardRequest(
        groupId: announcementSourceGroupId,
        messageId: announcementSourceMessageId,
        attachmentId: announcementSourceAttachmentId,
        initialCaption: 'source caption',
        provenance: const ForwardProvenance(
          operationDedupKey: 'opaque-discussion-action',
        ),
      );

      await _expectDeniedGroupForward(
        harness: harness,
        groups: harness.groups,
        destination: destination,
        request: request,
      );
    },
  );

  test(
    'GBF-04 inactive source and unsupported type guards are zero-effect',
    () async {
      for (final state in <String>['archived', 'dissolved', 'qa', 'source']) {
        final harness = AnnouncementForwardHarness();
        await harness.setUp();
        try {
          final groups = harness.groups;
          late final GroupModel destination;
          switch (state) {
            case 'archived':
              destination = harness
                  .group('archived-target')
                  .copyWith(
                    isArchived: true,
                    archivedAt: DateTime.utc(2026, 7, 12),
                  );
            case 'dissolved':
              destination = harness
                  .group('dissolved-target')
                  .copyWith(
                    isDissolved: true,
                    dissolvedAt: DateTime.utc(2026, 7, 12),
                    dissolvedBy: 'admin',
                  );
            case 'qa':
              destination = harness.group('qa-target', type: GroupType.qa);
            case 'source':
              destination = (await groups.getGroup(announcementSourceGroupId))!;
          }
          if (state != 'source') {
            await _seedWritableTarget(groups, destination);
          }

          await _expectDeniedGroupForward(
            harness: harness,
            groups: groups,
            destination: destination,
            request: harness.request(),
            reason: state,
          );
        } finally {
          harness.dispose();
        }
      }
    },
  );
}

DefaultShareBatchDeliveryCoordinator _coordinator({
  required AnnouncementForwardHarness harness,
  required InMemoryContactRepository contacts,
  required GroupRepository groups,
}) => DefaultShareBatchDeliveryCoordinator(
  identityRepository: harness.identities,
  contactRepository: contacts,
  messageRepository: harness.directMessages,
  mediaAttachmentRepository: harness.media,
  groupRepository: groups,
  groupMessageRepository: harness.groupMessages,
  bridge: harness.bridge,
  p2pService: harness.p2p,
  mediaFileManager: harness.fileManager,
  imageProcessor: AnnouncementForwardHarness.imageProcessor(),
  processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
    processedMedia: [
      PendingComposerMedia(
        file: File(harness.sourceFile.path),
        budgetBytes: harness.sourceFile.lengthSync(),
      ),
    ],
  ),
);

Future<void> _expectDeniedGroupForward({
  required AnnouncementForwardHarness harness,
  required GroupRepository groups,
  required GroupModel destination,
  required GroupMediaForwardRequest request,
  String? reason,
}) async {
  final beforeMessages = (await harness.groupMessages.getMessagesPage(
    destination.id,
    limit: 50,
  )).map((message) => message.id).toList(growable: false);
  final coordinator = _coordinator(
    harness: harness,
    contacts: harness.contacts,
    groups: groups,
  );

  final result = await coordinator.deliverGroupMediaForward(
    request: request,
    targets: [ShareTargetSelection.group(destination)],
  );

  expect(result.failureCount, 1, reason: reason);
  expect(
    harness.bridge.commandPayloads('media:upload'),
    isEmpty,
    reason: reason,
  );
  expect(
    harness.bridge.commandPayloads('group:publish'),
    isEmpty,
    reason: reason,
  );
  expect(
    harness.bridge.commandPayloads('group:inboxStore'),
    isEmpty,
    reason: reason,
  );
  expect(harness.media.saves, isEmpty, reason: reason);
  expect(
    (await harness.groupMessages.getMessagesPage(
      destination.id,
      limit: 50,
    )).map((message) => message.id),
    beforeMessages,
    reason: reason,
  );
}

class _DeleteOnSecondReadContacts extends InMemoryContactRepository {
  _DeleteOnSecondReadContacts(this.targetPeerId);

  final String targetPeerId;
  int targetReads = 0;

  @override
  Future<ContactModel?> getContact(String peerId) async {
    if (peerId == targetPeerId && ++targetReads >= 2) return null;
    return super.getContact(peerId);
  }
}

class _NoSnapshotGroupRepository implements GroupRepository {
  _NoSnapshotGroupRepository(this.backing);

  final InMemoryGroupRepository backing;

  @override
  Future<GroupModel?> getGroup(String id) => backing.getGroup(id);

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) =>
      backing.getLatestKey(groupId);

  @override
  Future<List<GroupMember>> getMembers(String groupId) =>
      backing.getMembers(groupId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

abstract class _MutateOnSnapshotGroups extends InMemoryGroupRepository {
  _MutateOnSnapshotGroups(this.targetGroupId);

  final String targetGroupId;
  bool didMutate = false;

  Future<void> mutate();

  @override
  Future<GroupForwardAuthorizationSnapshot?>
  loadGroupForwardAuthorizationSnapshot(String groupId) async {
    if (groupId == targetGroupId && !didMutate) {
      didMutate = true;
      await mutate();
    }
    return super.loadGroupForwardAuthorizationSnapshot(groupId);
  }
}

class _RemoveOwnMemberOnSnapshotGroups extends _MutateOnSnapshotGroups {
  _RemoveOwnMemberOnSnapshotGroups(super.targetGroupId);

  @override
  Future<void> mutate() => removeMember(targetGroupId, announcementOwnPeerId);
}

class _DemoteOwnMemberOnSnapshotGroups extends _MutateOnSnapshotGroups {
  _DemoteOwnMemberOnSnapshotGroups(super.targetGroupId);

  @override
  Future<void> mutate() =>
      updateMemberRole(targetGroupId, announcementOwnPeerId, MemberRole.reader);
}

class _RotateKeyOnSnapshotGroups extends _MutateOnSnapshotGroups {
  _RotateKeyOnSnapshotGroups(super.targetGroupId);

  @override
  Future<void> mutate() => saveKey(
    GroupKeyInfo(
      groupId: targetGroupId,
      keyGeneration: 2,
      encryptedKey: 'rotated-$targetGroupId',
      createdAt: DateTime.utc(2026, 7, 12),
    ),
  );
}

Future<void> _seedCanonicalSourceGroup({
  required AnnouncementForwardHarness harness,
  required InMemoryGroupRepository groups,
}) async {
  final source = await harness.groups.getGroup(announcementSourceGroupId);
  expect(source, isNotNull);
  await groups.saveGroup(source!);
}

Future<void> _seedWritableTarget(
  InMemoryGroupRepository groups,
  GroupModel group, {
  MemberRole ownMemberRole = MemberRole.admin,
  bool includeKey = true,
}) async {
  await groups.saveGroup(group);
  if (includeKey) {
    await groups.saveKey(
      GroupKeyInfo(
        groupId: group.id,
        keyGeneration: 1,
        encryptedKey: 'key-${group.id}',
        createdAt: DateTime.utc(2026),
      ),
    );
  }
  await groups.saveMember(
    GroupMember(
      groupId: group.id,
      peerId: announcementOwnPeerId,
      username: 'Owner',
      role: ownMemberRole,
      publicKey: 'owner-key',
      mlKemPublicKey: 'owner-mlkem',
      joinedAt: DateTime.utc(2026),
    ),
  );
}
