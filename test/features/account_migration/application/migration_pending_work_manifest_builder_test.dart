import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_pending_work_manifest_builder.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_pending_work_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MigrationPendingWorkManifestBuilder', () {
    test(
      'classifies valid pending work to resume only on the new phone after commit',
      () {
        final manifest = const MigrationPendingWorkManifestBuilder().build(
          fileManifestRelativePaths: const [
            'pending_uploads/msg-media/photo.jpg',
            'post_media/post-1/raw.jpg',
          ],
          oneToOneMessageRows: [
            _messageRow(id: 'msg-failed', status: 'failed'),
            _messageRow(id: 'msg-sending', status: 'sending'),
          ],
          oneToOneUnackedMessageRows: [
            _messageRow(
              id: 'msg-unacked',
              status: 'sent',
              wireEnvelope: '{"kind":"wire-envelope","message":"msg-unacked"}',
            ),
          ],
          chatMediaRows: const [
            {
              'id': 'media-upload-1',
              'message_id': 'msg-media',
              'local_path': 'pending_uploads/msg-media/photo.jpg',
              'download_status': 'upload_pending',
              'created_at': '2026-06-01T12:00:00.000Z',
            },
          ],
          postMediaUploadRows: const [
            {
              'post_id': 'post-1',
              'position': 0,
              'local_file_path': 'post_media/post-1/raw.jpg',
              'mime': 'image/jpeg',
              'kind': 'image',
              'created_at': '2026-06-01T12:01:00.000Z',
            },
          ],
          postRows: const [
            {
              'post_id': 'post-1',
              'event_id': 'post-event-1',
              'sender_peer_id': 'peer-alice',
              'delivery_status': 'failed',
              'is_incoming': 0,
              'post_created_at': '2026-06-01T12:02:00.000Z',
            },
          ],
          postRecipientDeliveryRows: const [
            {
              'post_id': 'post-1',
              'recipient_peer_id': 'peer-bob',
              'delivery_status': 'failed',
              'delivery_path': 'failed',
              'delivery_owner_kind': 'post',
              'delivery_owner_id': 'post-1',
              'created_at': '2026-06-01T12:03:00.000Z',
              'updated_at': '2026-06-01T12:03:00.000Z',
            },
          ],
          postFollowOnEventRows: const [
            {
              'event_id': 'follow-1',
              'event_type': 'reaction',
              'post_id': 'post-1',
              'comment_id': 'comment-1',
              'sender_peer_id': 'peer-alice',
              'raw_envelope': '{"kind":"post-reaction","event":"follow-1"}',
              'created_at': '2026-06-01T12:04:00.000Z',
            },
          ],
          postFollowOnRecipientDeliveryRows: const [
            {
              'event_id': 'follow-1',
              'recipient_peer_id': 'peer-bob',
              'delivery_status': 'failed',
              'delivery_path': 'failed',
              'created_at': '2026-06-01T12:05:00.000Z',
              'updated_at': '2026-06-01T12:05:00.000Z',
            },
          ],
          introductionOutboxRows: const [
            {
              'delivery_id': 'intro-delivery-1',
              'introduction_id': 'intro-1',
              'action': 'introduce',
              'target_peer_id': 'peer-bob',
              'sender_peer_id': 'peer-alice',
              'raw_envelope': '{"kind":"introduction","id":"intro-1"}',
              'delivery_status': 'failed',
              'delivery_path': 'failed',
              'created_at': '2026-06-01T12:06:00.000Z',
              'updated_at': '2026-06-01T12:06:00.000Z',
            },
          ],
          pendingIntroductionResponseRows: const [
            {
              'response_key': 'intro-1::peer-carol::accept',
              'introduction_id': 'intro-1',
              'action': 'accept',
              'responder_id': 'peer-carol',
              'transport_sender_peer_id': '12D3KooWCarolPhone',
              'created_at': '2026-06-01T12:07:00.000Z',
            },
          ],
          groupMessageRows: const [
            {
              'id': 'group-message-1',
              'group_id': 'group-1',
              'sender_peer_id': 'peer-alice',
              'status': 'failed',
              'is_incoming': 0,
              'key_generation': 9,
              'logical_delivery_id': 'logical-group-message-1',
              'created_at': '2026-06-01T12:08:00.000Z',
            },
          ],
          groupInboxRetryRows: const [
            {
              'id': 'group-message-inbox-1',
              'group_id': 'group-1',
              'sender_peer_id': 'peer-alice',
              'status': 'sent',
              'is_incoming': 0,
              'inbox_stored': 0,
              'inbox_retry_payload': '{"kind":"group-inbox","id":"inbox-1"}',
              'created_at': '2026-06-01T12:09:00.000Z',
            },
          ],
          groupPendingKeyRepairRows: const [
            {
              'id': 'repair-1',
              'group_id': 'group-1',
              'message_id': 'group-message-key-1',
              'sender_peer_id': 'peer-bob',
              'transport_peer_id': '12D3KooWBobPhone',
              'payload_type': 'group_message',
              'key_epoch': 9,
              'replay_envelope_json': '{"kind":"group_offline_replay"}',
              'status': 'pending_key',
              'created_at': '2026-06-01T12:10:00.000Z',
              'updated_at': '2026-06-01T12:10:00.000Z',
            },
          ],
          groupPendingMembershipRows: const [
            {
              'id': 'membership-1',
              'group_id': 'group-1',
              'sender_peer_id': 'peer-carol',
              'message_id': 'membership-wire-1',
              'payload_json': '{"kind":"members_added"}',
              'received_at': '2026-06-01T12:11:00.000Z',
              'created_at': '2026-06-01T12:11:00.000Z',
              'updated_at': '2026-06-01T12:11:00.000Z',
            },
          ],
          groupReactionReplayRows: const [
            {
              'reaction_id': 'reaction-1',
              'group_id': 'group-1',
              'message_id': 'group-message-1',
              'sender_peer_id': 'peer-alice',
              'emoji': 'heart',
              'action': 'add',
              'inbox_retry_payload': '{"kind":"group-reaction"}',
              'delivery_status': 'failed',
              'created_at': '2026-06-01T12:12:00.000Z',
              'updated_at': '2026-06-01T12:12:00.000Z',
            },
          ],
        );

        expect(manifest.isValid, isTrue);
        expect(
          manifest.items.map((item) => item.kind).toSet(),
          containsAll(MigrationPendingWorkItemKind.values),
        );
        expect(
          manifest.items.every(
            (item) =>
                item.resumePolicy ==
                MigrationPendingWorkResumePolicy.resumeOnNewPhoneAfterCommit,
          ),
          isTrue,
        );
        expect(
          manifest.items.every(
            (item) => !item.resumePolicy.name.toLowerCase().contains('old'),
          ),
          isTrue,
        );

        final unacked = manifest.items.singleWhere(
          (item) => item.sourceId == 'msg-unacked',
        );
        expect(
          unacked.kind,
          MigrationPendingWorkItemKind.oneToOneUnackedInboxStore,
        );
        expect(unacked.relatedIds['target_peer_id'], 'peer-bob');
        expect(
          unacked.metadata['payload_sha256'],
          sha256
              .convert(
                utf8.encode('{"kind":"wire-envelope","message":"msg-unacked"}'),
              )
              .toString(),
        );

        final followOn = manifest.items.singleWhere(
          (item) => item.sourceId == 'follow-1:peer-bob',
        );
        expect(followOn.kind, MigrationPendingWorkItemKind.postFollowOn);
        expect(followOn.relatedIds['post_id'], 'post-1');
        expect(followOn.relatedIds['comment_id'], 'comment-1');
        expect(followOn.relatedIds['recipient_peer_id'], 'peer-bob');

        final reaction = manifest.items.singleWhere(
          (item) => item.sourceId == 'reaction-1',
        );
        expect(reaction.kind, MigrationPendingWorkItemKind.groupReactionReplay);
        expect(reaction.relatedIds['group_id'], 'group-1');
        expect(reaction.relatedIds['message_id'], 'group-message-1');

        final encoded = jsonEncode(manifest.toJson());
        expect(encoded, isNot(contains('wire-envelope')));
        expect(encoded, isNot(contains('group-inbox')));
        expect(encoded, isNot(contains('group_offline_replay')));
        expect(encoded, isNot(contains('oldPhone')));
        expect(encoded, isNot(contains('old_phone')));
      },
    );

    test('excludes rows outside the pending-work surface', () {
      final manifest = const MigrationPendingWorkManifestBuilder().build(
        oneToOneMessageRows: [
          _messageRow(id: 'msg-delivered', status: 'delivered'),
          _messageRow(id: 'msg-incoming', status: 'failed', isIncoming: true),
        ],
        chatMediaRows: const [
          {
            'id': 'media-done',
            'message_id': 'msg-delivered',
            'local_path': 'media/peer-bob/photo.jpg',
            'download_status': 'done',
          },
        ],
        groupReactionReplayRows: const [
          {
            'reaction_id': 'reaction-stored',
            'group_id': 'group-1',
            'message_id': 'group-message-1',
            'sender_peer_id': 'peer-alice',
            'inbox_retry_payload': '{"kind":"stored"}',
            'delivery_status': 'stored',
          },
        ],
      );

      expect(manifest.items, isEmpty);
      expect(manifest.issues, isEmpty);
    });

    // 210b: a group message durably queued while the sender was offline
    // ('queued_offline', publish-without-custody) is pending work a Move must
    // carry — both as a re-drivable message row and, when its repush payload
    // is present, as an inbox-store retry.
    test('queued_offline group rows classify as pending work (210b)', () {
      final manifest = const MigrationPendingWorkManifestBuilder().build(
        groupMessageRows: const [
          {
            'id': 'group-message-queued-offline',
            'group_id': 'group-1',
            'sender_peer_id': 'peer-alice',
            'status': 'queued_offline',
            'is_incoming': 0,
            'key_generation': 9,
            'logical_delivery_id': 'logical-queued-offline',
            'created_at': '2026-07-05T12:00:00.000Z',
          },
        ],
        groupInboxRetryRows: const [
          {
            'id': 'group-message-queued-offline',
            'group_id': 'group-1',
            'sender_peer_id': 'peer-alice',
            'status': 'queued_offline',
            'is_incoming': 0,
            'inbox_stored': 0,
            'inbox_retry_payload': '{"kind":"group-inbox","id":"qo-1"}',
            'created_at': '2026-07-05T12:00:00.000Z',
          },
        ],
      );

      expect(manifest.issues, isEmpty);
      expect(
        manifest.items
            .where(
              (item) =>
                  item.kind == MigrationPendingWorkItemKind.groupMessageRetry,
            )
            .map((item) => item.sourceId),
        ['group-message-queued-offline'],
      );
      expect(
        manifest.items
            .where(
              (item) =>
                  item.kind ==
                  MigrationPendingWorkItemKind.groupInboxStoreRetry,
            )
            .map((item) => item.sourceId),
        ['group-message-queued-offline'],
      );
    });
  });
}

Map<String, Object?> _messageRow({
  required String id,
  required String status,
  bool isIncoming = false,
  String? wireEnvelope,
}) {
  return <String, Object?>{
    'id': id,
    'contact_peer_id': 'peer-bob',
    'sender_peer_id': 'peer-alice',
    'text': 'hello',
    'timestamp': '2026-06-01T12:00:00.000Z',
    'status': status,
    'is_incoming': isIncoming ? 1 : 0,
    'created_at': '2026-06-01T12:00:00.000Z',
    'wire_envelope': wireEnvelope,
  };
}
