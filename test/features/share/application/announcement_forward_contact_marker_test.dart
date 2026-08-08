import 'dart:convert';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'announcement_forward_test_harness.dart';

void main() {
  test(
    'contact forward marker and opaque per-target key survive retry without source attribution',
    () async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);

      final first = harness.contact('contact-one');
      final failedThenRetried = harness.contact('contact-two');
      await harness.contacts.addContact(first);
      await harness.contacts.addContact(failedThenRetried);
      harness.bridge.responseSequences['media:upload'] = [
        {'ok': true},
        {'ok': false, 'errorMessage': 'first contact-two upload fails'},
        {'ok': true},
      ];
      final coordinator = harness.coordinator();

      final firstPass = await coordinator.deliverGroupMediaForward(
        request: harness.request(),
        caption: 'forwarded caption',
        targets: [
          ShareTargetSelection.contact(first),
          ShareTargetSelection.contact(failedThenRetried),
        ],
      );
      expect(firstPass.sentCount, 1);
      expect(firstPass.queuedCount, 0);
      expect(firstPass.failureCount, 1);
      expect(firstPass.failedTargetKeys, {
        'contact:${failedThenRetried.peerId}',
      });

      final retry = await coordinator.deliverGroupMediaForward(
        request: harness.request(),
        caption: 'forwarded caption',
        targets: [ShareTargetSelection.contact(failedThenRetried)],
      );
      expect(retry.sentCount, 1);
      expect(retry.queuedCount, 0);
      expect(retry.failureCount, 0);

      final firstMessage = (await harness.directMessages.getMessagesForContact(
        first.peerId,
      )).single;
      final retriedMessage =
          (await harness.directMessages.getMessagesForContact(
            failedThenRetried.peerId,
          )).single;
      final firstExpectedKey = announcementForwardProvenanceForContact(
        base: harness.request().provenance,
        contactPeerId: first.peerId,
      ).operationDedupKey;
      final retriedExpectedKey = announcementForwardProvenanceForContact(
        base: harness.request().provenance,
        contactPeerId: failedThenRetried.peerId,
      ).operationDedupKey;
      expect(firstMessage.dedupKey, firstExpectedKey);
      expect(retriedMessage.dedupKey, retriedExpectedKey);
      expect(firstExpectedKey, isNot(retriedExpectedKey));
      expect(firstMessage.isForwarded, isTrue);
      expect(retriedMessage.isForwarded, isTrue);

      final uploads = harness.bridge.commandPayloads('media:upload');
      expect(uploads, hasLength(3));
      expect(uploads[1]['to'], failedThenRetried.peerId);
      expect(uploads[2]['to'], failedThenRetried.peerId);
      expect(
        uploads[1]['id'],
        isNot(uploads[2]['id']),
        reason: 'retry mints a fresh outgoing blob identity',
      );
      expect(harness.bridge.generatedBlobKeys, hasLength(3));
      expect(
        harness.bridge.generatedBlobKeys[1],
        isNot(harness.bridge.generatedBlobKeys[2]),
      );
      expect(
        harness.bridge.generatedBlobNonces[1],
        isNot(harness.bridge.generatedBlobNonces[2]),
      );

      final firstAttachment = (await harness.media.getAttachmentsForMessage(
        firstMessage.id,
        owner: MediaOwnerLane.direct,
      )).single;
      final retriedAttachment = (await harness.media.getAttachmentsForMessage(
        retriedMessage.id,
        owner: MediaOwnerLane.direct,
      )).single;
      expect(firstAttachment.id, isNot(retriedAttachment.id));
      expect(
        firstAttachment.encryptionKeyBase64,
        isNot(retriedAttachment.encryptionKeyBase64),
      );

      final contactWires = harness.p2p.storeInInboxLog
          .map((entry) => entry.message)
          .toList(growable: false);
      final innerPayloads = contactWires
          .map((wire) {
            final envelope = jsonDecode(wire) as Map<String, dynamic>;
            return jsonDecode(
                  (envelope['encrypted'] as Map<String, dynamic>)['ciphertext']
                      as String,
                )
                as Map<String, dynamic>;
          })
          .toList(growable: false);
      expect(innerPayloads, hasLength(2));
      expect(innerPayloads.every((map) => map['isForwarded'] == true), isTrue);
      final serialized = <String>[
        ...innerPayloads.map(jsonEncode),
        ...contactWires,
      ].join('\n');
      for (final source in const [
        announcementSourceGroupId,
        announcementSourceMessageId,
        announcementSourceAttachmentId,
        announcementSourceSenderId,
        announcementSourceKey,
        announcementSourceNonce,
      ]) {
        expect(serialized, isNot(contains(source)));
        expect(firstExpectedKey, isNot(contains(source)));
        expect(retriedExpectedKey, isNot(contains(source)));
      }
    },
  );
}
