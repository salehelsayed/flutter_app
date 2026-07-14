import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';

void main() {
  test(
    'GPL-16 policy uses encrypted extras only and changes no node relay or announcement authority',
    () async {
      for (final command in const ['group:publish', 'group:sendReliable']) {
        final bridge = FakeBridge();
        if (command == 'group:publish') {
          await callGroupPublish(
            bridge,
            groupId: 'group-1',
            text: '',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            media: const [
              {'id': 'blob-1', 'mime': 'image/jpeg', 'size': 42},
            ],
            privateMediaPolicy: const GroupPrivateMediaPolicy.protected()
                .toWireExtras(),
          );
        } else {
          await callGroupSendReliable(
            bridge,
            groupId: 'group-1',
            text: '',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            media: const [
              {'id': 'blob-1', 'mime': 'image/jpeg', 'size': 42},
            ],
            privateMediaPolicy: const GroupPrivateMediaPolicy.protected()
                .toWireExtras(),
          );
        }

        final sent =
            jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
        expect(sent['cmd'], command);
        final payload = sent['payload'] as Map<String, dynamic>;
        expect(payload['mediaPolicyVersion'], 1);
        expect(payload['mediaLifecycle'], 'standard');
        expect(payload.containsKey('mediaDurationSeconds'), isTrue);
        expect(payload['mediaDurationSeconds'], isNull);
        expect(payload['mediaProtected'], isTrue);
        expect(payload.containsKey('consumeReceipt'), isFalse);
        expect(payload.containsKey('relayRevocation'), isFalse);
      }

      final bridge = FakeBridge();
      await expectLater(
        callGroupPublish(
          bridge,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          media: const [
            {'id': 'blob-1', 'mime': 'image/jpeg', 'size': 42},
          ],
          privateMediaPolicy: const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'viewOnce',
            'mediaProtected': true,
          },
        ),
        throwsArgumentError,
      );
      expect(bridge.sendCallCount, 0);
    },
  );
}
