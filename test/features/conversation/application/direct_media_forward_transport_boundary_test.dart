import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'direct forwarding imports no go bridge routing inbox or group payload implementation',
    () {
      const paths = [
        'lib/features/conversation/application/build_received_media_forward.dart',
        'lib/core/services/share_intent_model.dart',
        'lib/features/share/application/share_batch_delivery_coordinator.dart',
        'lib/features/conversation/domain/models/message_payload.dart',
      ];
      final source = paths
          .map((path) => File(path).readAsStringSync())
          .join('\n');

      for (final forbidden in const [
        'go-mknoon',
        'go-relay-server',
        'group_message_payload.dart',
        'GroupMessagePayload',
        "'cmd': 'forward",
        'relayForward',
        'forwardInbox',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(source, contains('sendChatMessage('));
      expect(source, contains('sendGroupMessage('));
    },
  );
}
