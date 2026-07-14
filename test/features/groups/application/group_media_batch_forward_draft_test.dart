import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/announcement_media_forward_request.dart';
import 'package:flutter_app/features/groups/application/group_media_batch_forward.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'GBF-02 owner scoped draft output order and captions match approved contract',
    () async {
      final group = _group(GroupType.chat);
      final identities = [
        _identity('message-a', 'attachment-a'),
        _identity('message-b', 'attachment-b'),
        _identity('message-b', 'attachment-c'),
      ];
      final timestamps = {
        'message-a': DateTime.utc(2026, 7, 10),
        'message-b': DateTime.utc(2026, 7, 11),
      };
      final captions = {
        'attachment-a': 'caption A',
        'attachment-b': 'caption B',
        'attachment-c': 'caption C',
      };
      final tokens = {
        'attachment-a': 'opaque-one',
        'attachment-b': 'opaque-two',
        'attachment-c': 'opaque-three',
      };
      final verified = <String>[];
      final builder = _builder(
        group: group,
        timestamps: timestamps,
        captions: captions,
        tokens: tokens,
        onVerify: verified.add,
      );

      final result = await builder.build(
        sourceGroup: group,
        identities: identities,
      );

      expect(result.isReady, isTrue);
      final draft = result.draft!;
      expect(draft.sourceKind, GroupMediaBatchForwardSourceKind.discussion);
      expect(
        draft.items.map((item) => item.identity.attachmentId),
        ['attachment-c', 'attachment-b', 'attachment-a'],
        reason:
            'timestamp, message id, and attachment id are all DESC exactly '
            'like the accepted Plan-249 foundation',
      );
      expect(draft.items.map((item) => item.caption), [
        'caption C',
        'caption B',
        'caption A',
      ]);
      expect(
        draft.items
            .map((item) => item.request.provenance.operationDedupKey)
            .toSet(),
        {'opaque-one', 'opaque-two', 'opaque-three'},
      );
      expect(verified, ['attachment-c', 'attachment-b', 'attachment-a']);
      expect(draft.toString(), isNot(contains('message-')));
      expect(
        draft.items
            .singleWhere((item) => item.identity.attachmentId == 'attachment-a')
            .toString(),
        isNot(contains('attachment-a')),
      );
    },
  );

  test(
    'GBF-02 foundation remains 1..10 while batch route starts at two',
    () async {
      final group = _group(GroupType.chat);
      final single = _identity('message-a', 'attachment-a');
      final builder = _builder(
        group: group,
        timestamps: {'message-a': DateTime.utc(2026)},
        captions: {'attachment-a': 'caption'},
        tokens: {'attachment-a': 'opaque-one'},
      );

      final result = await builder.build(
        sourceGroup: group,
        identities: [single],
      );

      expect(result.isReady, isTrue);
      expect(kGroupMediaBatchForwardMinItems, 1);
      expect(kGroupMediaBatchForwardRouteMinItems, 2);
      expect(kGroupMediaBatchForwardMaxItems, 10);
    },
  );

  test(
    'ABF-02 announcement draft stays source typed and caption independent',
    () async {
      final group = _group(GroupType.announcement);
      final identities = [
        _identity('announcement-a', 'announcement-attachment-a'),
        _identity('announcement-b', 'announcement-attachment-b'),
      ];
      final builder = _builder(
        group: group,
        timestamps: {
          'announcement-a': DateTime.utc(2026, 7, 11),
          'announcement-b': DateTime.utc(2026, 7, 10),
        },
        captions: {
          'announcement-attachment-a': 'keep A',
          'announcement-attachment-b': 'keep B',
        },
        tokens: {
          'announcement-attachment-a': 'opaque-ann-one',
          'announcement-attachment-b': 'opaque-ann-two',
        },
      );

      final result = await builder.build(
        sourceGroup: group,
        identities: identities,
      );

      expect(
        result.draft!.sourceKind,
        GroupMediaBatchForwardSourceKind.announcement,
      );
      expect(
        result.draft!.items.every(
          (item) => item.request is AnnouncementMediaForwardRequest,
        ),
        isTrue,
      );
      final edited = result.draft!.copyWith(
        items: [
          result.draft!.items.first.copyWith(caption: 'edited independently'),
          result.draft!.items.last.copyWith(caption: ''),
        ],
      );
      expect(edited.items.map((item) => item.caption), [
        'edited independently',
        '',
      ]);
      expect(result.draft!.items.map((item) => item.caption), [
        'keep A',
        'keep B',
      ]);
    },
  );

  test(
    'GBF-02 invalid scope duplicate and source-derived token fail closed',
    () async {
      final group = _group(GroupType.chat);
      final identity = _identity('message-a', 'attachment-a');
      var verificationCalls = 0;
      final builder = _builder(
        group: group,
        timestamps: {'message-a': DateTime.utc(2026)},
        captions: {'attachment-a': 'caption'},
        tokens: {'attachment-a': 'contains-attachment-a'},
        onVerify: (_) => verificationCalls++,
      );

      final duplicate = await builder.build(
        sourceGroup: group,
        identities: [identity, identity],
      );
      expect(duplicate.denial, GroupMediaBatchForwardDenial.invalidSelection);
      expect(verificationCalls, 0);

      final wrongScope = await builder.build(
        sourceGroup: group,
        identities: [
          identity,
          const GroupSharedMediaIdentity(
            groupId: 'other-group',
            messageId: 'message-b',
            attachmentId: 'attachment-b',
          ),
        ],
      );
      expect(wrongScope.denial, GroupMediaBatchForwardDenial.invalidSelection);
      expect(verificationCalls, 0);

      final derived = await builder.build(
        sourceGroup: group,
        identities: [identity],
      );
      expect(
        derived.denial,
        GroupMediaBatchForwardDenial.invalidOperationToken,
      );
      expect(verificationCalls, 0);
    },
  );
}

GroupMediaBatchForwardDraftBuilder _builder({
  required GroupModel group,
  required Map<String, DateTime> timestamps,
  required Map<String, String> captions,
  required Map<String, String> tokens,
  void Function(String attachmentId)? onVerify,
}) => GroupMediaBatchForwardDraftBuilder(
  loadCurrentGroup: (groupId) async => groupId == group.id ? group : null,
  loadParentTimestamp: (identity) async => timestamps[identity.messageId],
  buildRequest: ({required group, required identity}) async {
    final provenance = ForwardProvenance(
      operationDedupKey: tokens[identity.attachmentId]!,
    );
    if (group.type == GroupType.announcement) {
      return AnnouncementMediaForwardRequest(
        groupId: identity.groupId,
        messageId: identity.messageId,
        attachmentId: identity.attachmentId,
        initialCaption: captions[identity.attachmentId]!,
        provenance: provenance,
      );
    }
    return GroupMediaForwardRequest(
      groupId: identity.groupId,
      messageId: identity.messageId,
      attachmentId: identity.attachmentId,
      initialCaption: captions[identity.attachmentId]!,
      provenance: provenance,
    );
  },
  verifySource: (request) async {
    onVerify?.call(request.attachmentId);
    return GroupMediaForwardSourceResult.verified(
      GroupMediaForwardVerifiedSource(
        resolvedPath: '/safe/${request.attachmentId}.jpg',
        attachment: _attachment(request),
      ),
    );
  },
  fileLength: (_) async => 128,
);

GroupSharedMediaIdentity _identity(String messageId, String attachmentId) =>
    GroupSharedMediaIdentity(
      groupId: 'source-group',
      messageId: messageId,
      attachmentId: attachmentId,
    );

MediaAttachment _attachment(GroupMediaForwardRequest request) =>
    MediaAttachment(
      id: request.attachmentId,
      messageId: request.messageId,
      mime: 'image/jpeg',
      size: 128,
      mediaType: 'image',
      localPath: 'media/source-group/${request.attachmentId}.jpg',
      downloadStatus: 'done',
      createdAt: '2026-07-10T00:00:00.000Z',
      ownerLane: MediaOwnerLane.group,
    );

GroupModel _group(GroupType type) => GroupModel(
  id: 'source-group',
  name: 'Source',
  type: type,
  topicName: 'source-topic',
  createdAt: DateTime.utc(2026),
  createdBy: 'creator',
  myRole: GroupRole.admin,
);
