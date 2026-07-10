import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'announcement_forward_test_harness.dart';

void main() {
  test(
    'multi-target forward processes once and creates distinct encrypted attachment identities per destination',
    () async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);

      final contact = harness.contact('contact-destination');
      await harness.contacts.addContact(contact);
      final group = harness.group('group-destination');
      await harness.seedWritableGroup(group);

      final result = await harness.coordinator().deliverGroupMediaForward(
        request: harness.request(),
        caption: harness.request().composedCaption,
        targets: [
          ShareTargetSelection.contact(contact),
          ShareTargetSelection.group(group),
        ],
      );

      expect(
        result.failureCount,
        0,
        reason: result.results.map((e) => e.detail).join('; '),
      );
      expect(harness.preprocessCount, 1);
      final uploads = harness.bridge.commandPayloads('media:upload');
      expect(uploads, hasLength(2));
      final blobIds = uploads.map((map) => map['id']).toSet();
      expect(blobIds, hasLength(2));
      expect(blobIds, isNot(contains(announcementSourceAttachmentId)));

      final directMessage = (await harness.directMessages.getMessagesForContact(
        contact.peerId,
      )).single;
      final groupMessage = (await harness.groupMessages.getMessagesPage(
        group.id,
      )).single;
      final directAttachment = (await harness.media.getAttachmentsForMessage(
        directMessage.id,
        owner: MediaOwnerLane.direct,
      )).single;
      final groupAttachment = (await harness.media.getAttachmentsForMessage(
        groupMessage.id,
        owner: MediaOwnerLane.group,
      )).single;
      expect(directMessage.id, isNot(groupMessage.id));
      expect(directAttachment.id, isNot(groupAttachment.id));
      expect(
        directAttachment.encryptionKeyBase64,
        isNot(groupAttachment.encryptionKeyBase64),
      );
      expect(
        directAttachment.encryptionNonce,
        isNot(groupAttachment.encryptionNonce),
      );
      expect(
        directAttachment.encryptionKeyBase64,
        isNot(announcementSourceKey),
      );
      expect(groupAttachment.encryptionNonce, isNot(announcementSourceNonce));
    },
  );

  test(
    'partial failure reports per target and retry selection contains failures only',
    () async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);

      final sent = harness.contact('sent-contact');
      final failed = harness.contact('failed-contact');
      await harness.contacts.addContact(sent);
      await harness.contacts.addContact(failed);
      final queued = harness.group('queued-group');
      await harness.seedWritableGroup(queued);
      final attempted = [
        ShareTargetSelection.contact(sent),
        ShareTargetSelection.group(queued),
        ShareTargetSelection.contact(failed),
      ];
      final calls = <String>[];
      var retrying = false;
      final coordinator = harness.coordinator(
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
              required uploadHooks,
            }) async {
              calls.add('contact:${contact.peerId}');
              final isFailedTarget = contact.peerId == failed.peerId;
              return ShareBatchTargetResult(
                target: ShareTargetSelection.contact(contact),
                status: isFailedTarget && !retrying
                    ? ShareBatchTargetStatus.failed
                    : ShareBatchTargetStatus.sent,
                detail: isFailedTarget && !retrying ? 'Failed.' : 'Sent.',
              );
            },
        sendToGroupFn:
            ({
              required identity,
              required shareIntent,
              required group,
              required processedMedia,
              required uploadHooks,
            }) async {
              calls.add('group:${group.id}');
              return ShareBatchTargetResult(
                target: ShareTargetSelection.group(group),
                status: ShareBatchTargetStatus.queued,
                detail: 'Queued.',
              );
            },
      );

      final first = await coordinator.deliverGroupMediaForward(
        request: harness.request(),
        caption: null,
        targets: attempted,
      );
      expect(first.sentCount, 1);
      expect(first.queuedCount, 1);
      expect(first.failureCount, 1);
      final retained = retainFailedAnnouncementForwardTargetKeys(
        sourceGroupId: announcementSourceGroupId,
        attemptedTargetKeys: {
          ...attempted.map((target) => target.key),
          'group:$announcementSourceGroupId',
        },
        failedTargetKeys: first.failedTargetKeys,
      );
      expect(retained, {'contact:${failed.peerId}'});

      calls.clear();
      retrying = true;
      final retryTargets = attempted
          .where((target) => retained.contains(target.key))
          .toList(growable: false);
      final retry = await coordinator.deliverGroupMediaForward(
        request: harness.request(),
        caption: null,
        targets: retryTargets,
      );
      expect(retry.sentCount, 1);
      expect(calls, ['contact:${failed.peerId}']);
      expect(calls, isNot(contains('contact:${sent.peerId}')));
      expect(calls, isNot(contains('group:${queued.id}')));
      expect(retained, isNot(contains('group:$announcementSourceGroupId')));
    },
  );
}
