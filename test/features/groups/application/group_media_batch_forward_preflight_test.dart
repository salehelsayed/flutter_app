import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_media_batch_forward.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'GBF-03 preflight is bounded fail closed and side effect free',
    () async {
      final identities = [
        _identity('message-a', 'attachment-a'),
        _identity('message-b', 'attachment-b'),
        _identity('message-c', 'attachment-c'),
      ];
      var deliveryCalls = 0;
      final builder = _builder(
        mime: 'video/mp4',
        fileLength: (_) async => 200 * 1024 * 1024,
      );

      final result = await builder.build(
        sourceGroup: _group(),
        identities: identities,
      );
      if (result.isReady) deliveryCalls++;

      expect(result.denial, GroupMediaBatchForwardDenial.sizeLimitExceeded);
      expect(deliveryCalls, 0);
      expect(kGroupMediaBatchForwardMaxTotalBytes, 500 * 1024 * 1024);
    },
  );

  test(
    'GBF-03 current MIME cap rejects before target or delivery work',
    () async {
      var deliveryCalls = 0;
      final builder = _builder(
        mime: 'image/jpeg',
        fileLength: (_) async => kGroupMediaImageLimitBytes + 1,
      );

      final result = await builder.build(
        sourceGroup: _group(),
        identities: [
          _identity('message-a', 'attachment-a'),
          _identity('message-b', 'attachment-b'),
        ],
      );
      if (result.isReady) deliveryCalls++;

      expect(result.denial, GroupMediaBatchForwardDenial.sizeLimitExceeded);
      expect(deliveryCalls, 0);
    },
  );
}

GroupMediaBatchForwardDraftBuilder _builder({
  required String mime,
  required GroupMediaBatchForwardFileLength fileLength,
}) => GroupMediaBatchForwardDraftBuilder(
  loadCurrentGroup: (_) async => _group(),
  loadParentTimestamp: (identity) async => DateTime.utc(
    2026,
    7,
    10,
    identity.messageId.codeUnitAt(identity.messageId.length - 1),
  ),
  buildRequest: ({required group, required identity}) async =>
      GroupMediaForwardRequest(
        groupId: identity.groupId,
        messageId: identity.messageId,
        attachmentId: identity.attachmentId,
        initialCaption: '',
        provenance: ForwardProvenance(
          operationDedupKey: switch (identity.attachmentId) {
            'attachment-a' => 'opaque-one',
            'attachment-b' => 'opaque-two',
            _ => 'opaque-three',
          },
        ),
      ),
  verifySource: (request) async => GroupMediaForwardSourceResult.verified(
    GroupMediaForwardVerifiedSource(
      resolvedPath: '/safe/${request.attachmentId}',
      attachment: MediaAttachment(
        id: request.attachmentId,
        messageId: request.messageId,
        mime: mime,
        size: 1,
        mediaType: mime.startsWith('video/') ? 'video' : 'image',
        downloadStatus: 'done',
        createdAt: '2026-07-10T00:00:00.000Z',
      ),
    ),
  ),
  fileLength: fileLength,
);

GroupSharedMediaIdentity _identity(String messageId, String attachmentId) =>
    GroupSharedMediaIdentity(
      groupId: 'source-group',
      messageId: messageId,
      attachmentId: attachmentId,
    );

GroupModel _group() => GroupModel(
  id: 'source-group',
  name: 'Source',
  type: GroupType.chat,
  topicName: 'source-topic',
  createdAt: DateTime.utc(2026),
  createdBy: 'creator',
  myRole: GroupRole.member,
);
