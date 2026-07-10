import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_test/flutter_test.dart';

// 236 TC-236-13: internal Forward is distinct from OS Share and ordinary
// send. Only an explicit ACCEPTED internal forward mints ForwardProvenance
// (and thus the destination marker); every other entry point stays null so
// nothing downstream can ever infer "forwarded" from media presence or from
// merely opening the share lane.

void main() {
  group('GroupMediaForwardIntent', () {
    test('GMF-13 only explicit internal forward sets forwarded provenance', () {
      String token() => 'op-token-1';

      // Ordinary composer send: never forwarded, even when "accepted".
      expect(
        groupMediaForwardProvenanceFor(
          entryPoint: GroupMediaSendEntryPoint.ordinarySend,
          accepted: true,
          operationTokenFactory: token,
        ),
        isNull,
        reason: 'ordinary send never mints forward provenance',
      );

      // Inbound/outbound OS share: never forwarded.
      expect(
        groupMediaForwardProvenanceFor(
          entryPoint: GroupMediaSendEntryPoint.osShare,
          accepted: true,
          operationTokenFactory: token,
        ),
        isNull,
        reason: 'an OS share entry point never mints forward provenance',
      );

      // Internal forward whose picker was CANCELED: no provenance.
      expect(
        groupMediaForwardProvenanceFor(
          entryPoint: GroupMediaSendEntryPoint.internalForward,
          accepted: false,
          operationTokenFactory: token,
        ),
        isNull,
        reason: 'a canceled forward picker mints nothing',
      );

      // Explicit accepted internal forward: exactly this mints provenance.
      final provenance = groupMediaForwardProvenanceFor(
        entryPoint: GroupMediaSendEntryPoint.internalForward,
        accepted: true,
        operationTokenFactory: token,
      );
      expect(provenance, isNotNull);
      expect(provenance!.operationDedupKey, 'op-token-1');

      // Fail closed on a blank operation token.
      expect(
        groupMediaForwardProvenanceFor(
          entryPoint: GroupMediaSendEntryPoint.internalForward,
          accepted: true,
          operationTokenFactory: () => '   ',
        ),
        isNull,
        reason: 'a blank dedup token cannot create a forward operation',
      );

      // The typed request carries ONLY the stable source identity, the
      // editable seed caption, and the minted provenance — no source sender,
      // hash, key, or access metadata exists on the type at all.
      final request = GroupMediaForwardRequest(
        groupId: 'group-1',
        messageId: 'msg-1',
        attachmentId: 'att-1',
        initialCaption: 'original caption',
        provenance: provenance,
      );
      expect(request.groupId, 'group-1');
      expect(request.messageId, 'msg-1');
      expect(request.attachmentId, 'att-1');
      expect(request.initialCaption, 'original caption');
      expect(request.provenance.operationDedupKey, 'op-token-1');
    });
  });
}
