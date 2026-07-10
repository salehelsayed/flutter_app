import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/groups/application/announcement_media_forward_request.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../share/application/announcement_forward_test_harness.dart';

void main() {
  test(
    'caption modes preserve remove or replace source caption deterministically',
    () async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);
      final sourceParentBefore = await harness.groupMessages.getMessage(
        announcementSourceMessageId,
      );
      final sourceRowsBefore = await harness.media.getAttachmentsForMessage(
        announcementSourceMessageId,
        owner: MediaOwnerLane.group,
      );
      final sourceBytesBefore = harness.sourceFile.readAsBytesSync();

      final cases =
          <
            ({
              AnnouncementForwardCaptionMode mode,
              String? edited,
              String expected,
            })
          >[
            (
              mode: AnnouncementForwardCaptionMode.keep,
              edited: null,
              expected: 'source caption',
            ),
            (
              mode: AnnouncementForwardCaptionMode.remove,
              edited: null,
              expected: '',
            ),
            (
              mode: AnnouncementForwardCaptionMode.edit,
              edited: '  replacement  ',
              expected: 'replacement',
            ),
          ];
      for (final (index, value) in cases.indexed) {
        final contact = harness.contact('caption-target-$index');
        await harness.contacts.addContact(contact);
        final request = harness.request(
          captionMode: value.mode,
          editedCaption: value.edited,
        );
        final result = await harness.coordinator().deliverGroupMediaForward(
          request: request,
          caption: request.composedCaption,
          targets: [ShareTargetSelection.contact(contact)],
        );
        expect(result.failureCount, 0, reason: result.results.single.detail);
        final outgoing = (await harness.directMessages.getMessagesForContact(
          contact.peerId,
        )).single;
        expect(outgoing.text, value.expected);
      }

      expect(
        (await harness.groupMessages.getMessage(
          announcementSourceMessageId,
        ))?.toMap(),
        sourceParentBefore?.toMap(),
      );
      final sourceRowsAfter = await harness.media.getAttachmentsForMessage(
        announcementSourceMessageId,
        owner: MediaOwnerLane.group,
      );
      expect(
        sourceRowsAfter.map((row) => row.toMap()),
        sourceRowsBefore.map((row) => row.toMap()),
      );
      expect(
        File(harness.sourceFile.path).readAsBytesSync(),
        sourceBytesBefore,
      );
    },
  );
}
