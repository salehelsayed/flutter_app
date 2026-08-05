import 'dart:convert';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'announcement_forward_test_harness.dart';

Iterable<String> _keys(Object? value) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      yield entry.key.toString();
      yield* _keys(entry.value);
    }
  } else if (value is Iterable) {
    for (final item in value) {
      yield* _keys(item);
    }
  } else if (value is String &&
      (value.startsWith('{') || value.startsWith('['))) {
    try {
      yield* _keys(jsonDecode(value));
    } catch (_) {}
  }
}

void main() {
  test(
    'announcement forward uses group source direct group destinations and no owner wire field',
    () async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);

      // Literal same-parent collision rows: only the group-owned attachment
      // may qualify as the announcement source. Direct and legacy unresolved
      // rows remain invisible to the owner-scoped source gate.
      await harness.media.saveAttachment(
        const MediaAttachment(
          id: 'same-parent-direct-collision',
          messageId: announcementSourceMessageId,
          mime: 'image/jpeg',
          size: 1,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-07-10T12:00:00.000Z',
          ownerLane: MediaOwnerLane.direct,
        ),
        owner: MediaOwnerLane.direct,
      );
      harness.media.seedUnresolvedOwnerRowForTest(
        const MediaAttachment(
          id: 'same-parent-unresolved-collision',
          messageId: announcementSourceMessageId,
          mime: 'image/jpeg',
          size: 1,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-07-10T12:00:00.000Z',
        ),
      );
      harness.media.reads.clear();
      harness.media.saves.clear();
      harness.media.atomicStages.clear();

      final contact = harness.contact('owner-contact-destination');
      await harness.contacts.addContact(contact);
      final group = harness.group('owner-group-destination');
      await harness.seedWritableGroup(group);
      final result = await harness.coordinator().deliverGroupMediaForward(
        request: harness.request(),
        caption: 'destination caption',
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

      expect(
        harness.media.reads.where(
          (call) => call.messageId == announcementSourceMessageId,
        ),
        everyElement((call) => call.owner == MediaOwnerLane.group),
      );
      final qualifiedSource = await harness.media.getAttachmentsForMessage(
        announcementSourceMessageId,
        owner: MediaOwnerLane.group,
      );
      expect(qualifiedSource.map((row) => row.id), [
        announcementSourceAttachmentId,
      ]);
      expect(<MediaOwnerLane>{
        ...harness.media.saves.map((call) => call.owner),
        ...harness.media.atomicStages.map((call) => call.owner),
      }, containsAll({MediaOwnerLane.direct, MediaOwnerLane.group}));

      final directMessage = (await harness.directMessages.getMessagesForContact(
        contact.peerId,
      )).single;
      final groupMessage = (await harness.groupMessages.getMessagesPage(
        group.id,
      )).single;
      expect(
        (await harness.media.getAttachmentsForMessage(
          directMessage.id,
          owner: MediaOwnerLane.direct,
        )).single.ownerLane,
        MediaOwnerLane.direct,
      );
      expect(
        (await harness.media.getAttachmentsForMessage(
          groupMessage.id,
          owner: MediaOwnerLane.group,
        )).single.ownerLane,
        MediaOwnerLane.group,
      );

      final captured = <Object?>[
        ...harness.bridge.sentMessages.map(jsonDecode),
        ...harness.p2p.sentMessageLog.map((entry) => jsonDecode(entry.content)),
        ...harness.p2p.storeInInboxLog.map(
          (entry) => jsonDecode(entry.message),
        ),
        if (groupMessage.wireEnvelope != null)
          jsonDecode(groupMessage.wireEnvelope!),
        if (groupMessage.inboxRetryPayload != null)
          jsonDecode(groupMessage.inboxRetryPayload!),
        harness.request().privacySafeDiagnostic,
      ];
      for (final surface in captured) {
        final keys = _keys(surface).map((key) => key.toLowerCase()).toList();
        expect(keys, isNot(contains('owner')));
        expect(keys, isNot(contains('ownerlane')));
        expect(keys, isNot(contains('owner_lane')));
        final serialized = jsonEncode(surface);
        for (final source in const [
          announcementSourceGroupId,
          announcementSourceMessageId,
          announcementSourceAttachmentId,
          announcementSourceSenderId,
          announcementSourceKey,
          announcementSourceNonce,
        ]) {
          expect(serialized, isNot(contains(source)));
        }
      }
    },
  );
}
