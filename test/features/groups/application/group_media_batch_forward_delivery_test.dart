import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_media_batch_forward.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/share/application/group_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'GBF-07 partial retry is idempotent at the source-target cell',
    () async {
      final draft = _draft();
      final contact = ShareTargetSelection.contact(_contact());
      final group = ShareTargetSelection.group(_group());
      final calls = <_DeliveryCall>[];
      var retrying = false;
      final coordinator = GroupMediaBatchForwardDeliveryCoordinator(
        revalidateForDispatch: (candidate) async =>
            GroupMediaBatchForwardBuildResult.ready(candidate),
        deliverSingle: ({required request, caption, required targets}) async {
          calls.add(
            _DeliveryCall(
              attachmentId: request.attachmentId,
              token: request.provenance.operationDedupKey,
              caption: caption,
              targetKeys: targets.map((target) => target.key).toList(),
            ),
          );
          return ShareBatchDeliveryResult(
            results: [
              for (final target in targets)
                ShareBatchTargetResult(
                  target: target,
                  status:
                      request.attachmentId == 'attachment-a' &&
                          target.key == group.key &&
                          !retrying
                      ? ShareBatchTargetStatus.failed
                      : request.attachmentId == 'attachment-b' &&
                            target.key == contact.key
                      ? ShareBatchTargetStatus.queued
                      : ShareBatchTargetStatus.sent,
                  detail: 'settled',
                ),
            ],
          );
        },
      );

      final initial = await coordinator.deliverInitial(
        draft: draft,
        targets: [contact, group],
      );

      expect(initial.isDenied, isFalse);
      expect(initial.matrix!.cells, hasLength(4));
      expect(initial.matrix!.sentCount, 2);
      expect(initial.matrix!.queuedCount, 1);
      expect(initial.matrix!.failedCount, 1);
      expect(calls.map((call) => call.attachmentId), [
        'attachment-b',
        'attachment-a',
      ]);
      expect(calls.every((call) => call.targetKeys.length == 2), isTrue);

      final immutableBeforeRetry = {
        for (final cell in initial.matrix!.cells)
          if (cell.status != GroupMediaBatchForwardCellStatus.failed)
            cell.key: cell.status,
      };
      retrying = true;
      final retried = await coordinator.retryFailed(
        draft: draft,
        priorMatrix: initial.matrix!,
      );

      expect(retried.newlyAttemptedCellCount, 1);
      expect(retried.matrix!.failedCount, 0);
      expect(retried.matrix!.sentCount, 3);
      expect(retried.matrix!.queuedCount, 1);
      expect(calls, hasLength(3));
      expect(calls.last.attachmentId, 'attachment-a');
      expect(calls.last.targetKeys, [group.key]);
      expect(calls.last.token, 'opaque-unit-one');
      expect(calls.last.caption, 'caption A');
      for (final cell in retried.matrix!.cells) {
        final priorStatus = immutableBeforeRetry[cell.key];
        if (priorStatus != null) expect(cell.status, priorStatus);
      }
    },
  );

  test(
    'GBF-03 dispatch source preflight is atomic and side effect free',
    () async {
      final draft = _draft();
      var deliveryCalls = 0;
      final coordinator = GroupMediaBatchForwardDeliveryCoordinator(
        revalidateForDispatch: (_) async =>
            const GroupMediaBatchForwardBuildResult.denied(
              GroupMediaBatchForwardDenial.sourceUnavailable,
            ),
        deliverSingle: ({required request, caption, required targets}) async {
          deliveryCalls++;
          return const ShareBatchDeliveryResult(results: []);
        },
      );

      final result = await coordinator.deliverInitial(
        draft: draft,
        targets: [ShareTargetSelection.contact(_contact())],
      );

      expect(
        result.denial,
        GroupMediaBatchForwardAttemptDenial.sourceUnavailable,
      );
      expect(result.matrix, isNull);
      expect(deliveryCalls, 0);
    },
  );

  test(
    'GBF-07 absent or skipped target outcomes remain failed truthfully',
    () async {
      final draft = _draft();
      final contact = ShareTargetSelection.contact(_contact());
      final group = ShareTargetSelection.group(_group());
      final coordinator = GroupMediaBatchForwardDeliveryCoordinator(
        revalidateForDispatch: (candidate) async =>
            GroupMediaBatchForwardBuildResult.ready(candidate),
        deliverSingle: ({required request, caption, required targets}) async =>
            ShareBatchDeliveryResult(
              results: [
                ShareBatchTargetResult(
                  target: contact,
                  status: ShareBatchTargetStatus.sent,
                  detail: 'must be discarded with skipped media',
                ),
              ],
              skippedOversizedGifCount: 1,
            ),
      );

      final result = await coordinator.deliverInitial(
        draft: draft,
        targets: [contact, group],
      );

      expect(result.matrix!.sentCount, 0);
      expect(result.matrix!.failedCount, 4);
    },
  );

  test(
    'GBF-07 duplicate ordinary outcomes fail closed per requested cell',
    () async {
      final draft = _draft();
      final contact = ShareTargetSelection.contact(_contact());
      final foreign = ShareTargetSelection.contact(
        _contact().copyWith(peerId: 'foreign-contact', username: 'Foreign'),
      );
      final coordinator = GroupMediaBatchForwardDeliveryCoordinator(
        revalidateForDispatch: (candidate) async =>
            GroupMediaBatchForwardBuildResult.ready(candidate),
        deliverSingle: ({required request, caption, required targets}) async =>
            ShareBatchDeliveryResult(
              results: [
                ShareBatchTargetResult(
                  target: contact,
                  status: ShareBatchTargetStatus.sent,
                  detail: 'first contradictory result',
                ),
                ShareBatchTargetResult(
                  target: contact,
                  status: ShareBatchTargetStatus.queued,
                  detail: 'duplicate contradictory result',
                ),
                ShareBatchTargetResult(
                  target: foreign,
                  status: ShareBatchTargetStatus.sent,
                  detail: 'foreign result',
                ),
              ],
            ),
      );

      final result = await coordinator.deliverInitial(
        draft: draft,
        targets: [contact],
      );

      expect(result.matrix!.cells, hasLength(2));
      expect(result.matrix!.failedCount, 2);
      expect(result.matrix!.sentCount, 0);
      expect(result.matrix!.queuedCount, 0);
    },
  );
}

GroupMediaBatchForwardDraft _draft() => GroupMediaBatchForwardDraft(
  sourceGroupId: 'source-group',
  sourceKind: GroupMediaBatchForwardSourceKind.discussion,
  items: [
    _item(
      messageId: 'message-b',
      attachmentId: 'attachment-b',
      token: 'opaque-unit-two',
      caption: 'caption B',
      timestamp: DateTime.utc(2026, 7, 11),
    ),
    _item(
      messageId: 'message-a',
      attachmentId: 'attachment-a',
      token: 'opaque-unit-one',
      caption: 'caption A',
      timestamp: DateTime.utc(2026, 7, 10),
    ),
  ],
);

GroupMediaBatchForwardItemDraft _item({
  required String messageId,
  required String attachmentId,
  required String token,
  required String caption,
  required DateTime timestamp,
}) {
  final identity = GroupSharedMediaIdentity(
    groupId: 'source-group',
    messageId: messageId,
    attachmentId: attachmentId,
  );
  return GroupMediaBatchForwardItemDraft(
    identity: identity,
    request: GroupMediaForwardRequest(
      groupId: identity.groupId,
      messageId: messageId,
      attachmentId: attachmentId,
      initialCaption: caption,
      provenance: ForwardProvenance(operationDedupKey: token),
    ),
    resolvedPath: '/safe/$attachmentId.jpg',
    parentTimestamp: timestamp,
    mime: 'image/jpeg',
    sizeBytes: 128,
    caption: caption,
  );
}

ContactModel _contact() => const ContactModel(
  peerId: 'contact-peer',
  publicKey: 'contact-key',
  rendezvous: '/dns4/relay/tcp/443',
  username: 'Contact',
  signature: 'signature',
  scannedAt: '2026-07-10T00:00:00.000Z',
  mlKemPublicKey: 'mlkem',
);

GroupModel _group() => GroupModel(
  id: 'target-group',
  name: 'Target',
  type: GroupType.chat,
  topicName: 'target-topic',
  createdAt: DateTime.utc(2026),
  createdBy: 'creator',
  myRole: GroupRole.member,
);

class _DeliveryCall {
  const _DeliveryCall({
    required this.attachmentId,
    required this.token,
    required this.caption,
    required this.targetKeys,
  });

  final String attachmentId;
  final String token;
  final String? caption;
  final List<String> targetKeys;
}
