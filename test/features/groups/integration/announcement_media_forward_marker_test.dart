import 'dart:convert';

import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../share/application/announcement_forward_test_harness.dart';

void main() {
  test(
    'announcement source forward reaches group destination with boolean marker and no source attribution',
    () async {
      final harness = AnnouncementForwardHarness();
      await harness.setUp();
      addTearDown(harness.dispose);
      final destination = harness.group('marker-destination-group');
      await harness.seedWritableGroup(destination);

      final result = await harness.coordinator().deliverGroupMediaForward(
        request: harness.request(),
        caption: 'forwarded caption',
        targets: [ShareTargetSelection.group(destination)],
      );
      expect(result.failureCount, 0, reason: result.results.single.detail);

      final publish = harness.bridge.commandPayloads('group:publish').single;
      final reliable = harness.bridge.commandPayloads('group:sendReliable');
      final saved = (await harness.groupMessages.getMessagesPage(
        destination.id,
      )).single;
      expect(publish['isForwarded'], isTrue);
      expect(saved.isForwarded, isTrue);
      expect(saved.inboxRetryPayload, isNotNull);

      final retry =
          jsonDecode(saved.inboxRetryPayload!) as Map<String, dynamic>;
      final retryEnvelope =
          jsonDecode(retry['message'] as String) as Map<String, dynamic>;
      final replayPlaintext =
          jsonDecode(retryEnvelope['ciphertext'] as String)
              as Map<String, dynamic>;
      expect(replayPlaintext['isForwarded'], isTrue);

      // The live event surface is the real destination publish map produced
      // by sendGroupMessage; the durable inbox/replay surface is the retained
      // encrypted plaintext above. Both carry only the boolean marker.
      final surfaces = <Object?>[
        publish,
        ...reliable,
        retry,
        retryEnvelope,
        replayPlaintext,
        {
          'groupId': destination.id,
          'messageId': saved.id,
          'isForwarded': saved.isForwarded,
        },
      ];
      for (final surface in surfaces) {
        final serialized = jsonEncode(surface);
        for (final source in const [
          announcementSourceGroupId,
          announcementSourceMessageId,
          announcementSourceAttachmentId,
          announcementSourceSenderId,
          announcementSourceKey,
          announcementSourceNonce,
          'sourceGroupId',
          'sourceMessageId',
          'originalSender',
          'forwardedFrom',
        ]) {
          expect(serialized, isNot(contains(source)));
        }
      }
    },
  );
}
