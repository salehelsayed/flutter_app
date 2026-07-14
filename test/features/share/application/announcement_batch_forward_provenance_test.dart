import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'announcement_forward_test_harness.dart';

void main() {
  test(
    'batch output keys are target unit scoped stable and source anonymous',
    () {
      const base = ForwardProvenance(operationDedupKey: 'opaque-unit-token');
      final contact = announcementForwardProvenanceForContact(
        base: base,
        contactPeerId: 'group:shared-id',
      );
      final group = groupForwardProvenanceForGroup(
        base: base,
        groupId: 'shared-id',
      );

      expect(contact.operationDedupKey, isNot(group.operationDedupKey));
      expect(
        announcementForwardProvenanceForContact(
          base: base,
          contactPeerId: 'group:shared-id',
        ).operationDedupKey,
        contact.operationDedupKey,
      );
      for (final value in [
        contact.operationDedupKey,
        group.operationDedupKey,
      ]) {
        expect(value, isNot(contains('shared-id')));
        expect(value, isNot(contains('contact:')));
        expect(value, isNot(contains('group:')));
        expect(value, isNot(base.operationDedupKey));
      }
    },
  );

  test(
    'group cell retry reuses one durable message and logical identity',
    () async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);
      final destination = harness.group('destination-chat');
      await harness.seedWritableGroup(destination);
      harness.bridge.responses['group:publish'] = {'ok': false};
      harness.bridge.responses['group:inboxStore'] = {'ok': false};
      var clockCalls = 0;
      final coordinator = harness.coordinator(
        forwardNow: () {
          clockCalls++;
          return DateTime.utc(2026, 7, 12, 12);
        },
      );
      final target = ShareTargetSelection.group(destination);
      final request = harness.request();
      final sourceMessageBefore = (await harness.groupMessages.getMessage(
        announcementSourceMessageId,
      ))!;
      final sourceAttachmentBefore =
          (await harness.media.getAttachmentsForMessage(
            announcementSourceMessageId,
            owner: MediaOwnerLane.group,
          )).single;
      final sourceBytesBefore = File(
        sourceAttachmentBefore.localPath!,
      ).readAsBytesSync();

      final first = await coordinator.deliverGroupMediaForward(
        request: request,
        targets: [target],
      );
      final second = await coordinator.deliverGroupMediaForward(
        request: request,
        targets: [target],
      );

      expect(first.results, hasLength(1));
      expect(second.results, hasLength(1));
      final rows = await harness.groupMessages.getMessagesPage(
        destination.id,
        limit: 20,
      );
      expect(
        rows,
        hasLength(1),
        reason: 'same target/unit cannot mint a sibling',
      );
      final expected = groupForwardProvenanceForGroup(
        base: request.provenance,
        groupId: destination.id,
      ).operationDedupKey;
      expect(rows.single.id, expected);
      expect(rows.single.logicalDeliveryId, expected);
      expect(rows.single.isForwarded, isTrue);
      final attachments = await harness.media.getAttachmentsForMessage(
        expected,
        owner: MediaOwnerLane.group,
      );
      expect(
        attachments,
        hasLength(1),
        reason: 'same operation cannot accumulate sibling attachment rows',
      );
      final destinationUploads = harness.bridge
          .commandPayloads('media:upload')
          .where((payload) => payload['to'] == destination.id)
          .toList(growable: false);
      expect(destinationUploads, hasLength(1));
      expect(
        destinationUploads.single['id'],
        attachments.single.id,
        reason: 'the one durable attachment owns the one uploaded blob id',
      );
      expect(
        clockCalls,
        1,
        reason: 'route retry retains the first output timestamp',
      );
      for (final source in announcementSourceSentinels) {
        expect(expected, isNot(contains(source)));
      }
      final sourceMessageAfter = await harness.groupMessages.getMessage(
        announcementSourceMessageId,
      );
      final sourceAttachmentAfter =
          (await harness.media.getAttachmentsForMessage(
            announcementSourceMessageId,
            owner: MediaOwnerLane.group,
          )).single;
      expect(sourceMessageAfter?.toMap(), sourceMessageBefore.toMap());
      expect(sourceAttachmentAfter.toMap(), sourceAttachmentBefore.toMap());
      expect(
        File(sourceAttachmentAfter.localPath!).readAsBytesSync(),
        sourceBytesBefore,
        reason: 'forwarding never rewrites or consumes source bytes',
      );
      expect(
        harness.media.saves.where(
          (save) =>
              save.messageId == announcementSourceMessageId ||
              save.attachmentId == announcementSourceAttachmentId,
        ),
        isEmpty,
        reason: 'source rows stay read-only across initial send and retry',
      );
      expect(
        harness.bridge
            .commandPayloads('media:upload')
            .where((payload) => payload['to'] == announcementSourceGroupId),
        isEmpty,
        reason: 'source announcement is never an upload destination',
      );
      final destinationPublishes = harness.bridge
          .commandPayloads('group:publish')
          .where((payload) => payload['groupId'] == destination.id)
          .toList(growable: false);
      expect(
        destinationPublishes,
        hasLength(1),
        reason: 'the initial attempt emits one destination publish only',
      );
      expect(
        harness.bridge
            .commandPayloads('group:publish')
            .where(
              (payload) => payload['groupId'] == announcementSourceGroupId,
            ),
        isEmpty,
        reason: 'forwarding never publishes back into the source announcement',
      );
      expect(
        harness.bridge
            .commandPayloads('group:inboxStore')
            .where(
              (payload) => payload['groupId'] == announcementSourceGroupId,
            ),
        isEmpty,
        reason: 'forwarding never stores source-announcement inbox custody',
      );
    },
  );
}
