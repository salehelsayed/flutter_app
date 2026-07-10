import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../share/application/announcement_forward_test_harness.dart';

void main() {
  test(
    'reader forward sends only to selected destination and never publishes to source announcement',
    () async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);
      final destination = harness.group('destination-chat-B');
      await harness.seedWritableGroup(destination);
      final sourceMessageBefore = await harness.groupMessages.getMessage(
        announcementSourceMessageId,
      );
      final sourceRowsBefore = await harness.media.getAttachmentsForMessage(
        announcementSourceMessageId,
        owner: MediaOwnerLane.group,
      );
      final sourceBytesBefore = harness.sourceFile.readAsBytesSync();

      final destinationResult = await harness
          .coordinator()
          .deliverGroupMediaForward(
            request: harness.request(),
            caption: 'destination caption',
            targets: [ShareTargetSelection.group(destination)],
          );
      expect(
        destinationResult.failureCount,
        0,
        reason: destinationResult.results.single.detail,
      );

      // Even a stale/malicious selected source target is rejected by the
      // send-time coordinator and never reaches a group command.
      final sourceGroup = (await harness.groups.getGroup(
        announcementSourceGroupId,
      ))!;
      final sourceResult = await harness.coordinator().deliverGroupMediaForward(
        request: harness.request(),
        caption: 'must not publish',
        targets: [ShareTargetSelection.group(sourceGroup)],
      );
      expect(sourceResult.failureCount, 1);

      final groupCommands = [
        ...harness.bridge.commandPayloads('group:publish'),
        ...harness.bridge.commandPayloads('group:sendReliable'),
        ...harness.bridge.commandPayloads('group:inboxStore'),
      ];
      expect(groupCommands, isNotEmpty);
      expect(
        groupCommands.any((payload) => payload['groupId'] == destination.id),
        isTrue,
      );
      expect(
        groupCommands.any(
          (payload) => payload['groupId'] == announcementSourceGroupId,
        ),
        isFalse,
      );
      expect(
        (await harness.groupMessages.getMessage(
          announcementSourceMessageId,
        ))?.text,
        sourceMessageBefore?.text,
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
