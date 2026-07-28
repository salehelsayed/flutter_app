import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/account_migration/application/migration_group_manifest_builder.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_group_manifest.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('MigrationGroupManifestBuilder', () {
    late FakeSecureKeyStore primaryStore;
    late FakeSecureKeyStore sharedStore;

    setUp(() {
      primaryStore = FakeSecureKeyStore();
      sharedStore = FakeSecureKeyStore();
    });

    test(
      'builds retained group key, device roster, sender metadata, and preview manifest without serializing key bytes',
      () async {
        final committedRows = <Map<String, Object?>>[];
        for (var generation = 3; generation <= 10; generation++) {
          final value = 'base64-key-$generation';
          final primaryKey = groupKeyMaterialStoreName('group-1', generation);
          await primaryStore.write(primaryKey, value);
          await sharedStore.write(
            sharedGroupPushKeyName('group-1', generation),
            value,
          );
          committedRows.add({
            'group_id': 'group-1',
            'key_generation': generation,
            'encrypted_key': secureStoreReferenceForKey(primaryKey),
            'created_at': '2026-06-01T12:0${generation % 10}:00.000Z',
          });
        }

        final draftKey = groupKeyMaterialStoreName('group-1', 11);
        await primaryStore.write(draftKey, 'base64-draft-11');

        final builder = MigrationGroupManifestBuilder(
          primaryStore: primaryStore,
          sharedStore: sharedStore,
          movedAccountPeerId: 'peer-alice',
        );

        final manifest = await builder.build(
          groupRows: [
            {'id': 'group-1', 'name': 'Team Chat'},
          ],
          committedGroupKeyRows: committedRows,
          pendingGroupKeyRows: [
            {
              'group_id': 'group-1',
              'key_generation': 11,
              'encrypted_key': secureStoreReferenceForKey(draftKey),
              'created_at': '2026-06-01T12:11:00.000Z',
            },
          ],
          groupMemberRows: [
            {
              'group_id': 'group-1',
              'peer_id': 'peer-alice',
              'role': 'admin',
              'devices_json': GroupMemberDeviceIdentity.listToJsonString([
                const GroupMemberDeviceIdentity(
                  deviceId: 'alice-phone',
                  transportPeerId: '12D3KooWAlicePhone',
                  deviceSigningPublicKey: 'alice-device-signing-pk',
                  mlKemPublicKey: 'alice-mlkem-pk',
                  keyPackageId: 'kp-alice-phone',
                  keyPackagePublicMaterial: 'kp-public-alice-phone',
                ),
              ]),
              'joined_at': '2026-06-01T12:00:00.000Z',
            },
            {
              'group_id': 'group-1',
              'peer_id': 'peer-bob',
              'role': 'writer',
              'devices_json': GroupMemberDeviceIdentity.listToJsonString([
                const GroupMemberDeviceIdentity(
                  deviceId: 'bob-phone',
                  transportPeerId: '12D3KooWBobPhone',
                  deviceSigningPublicKey: 'bob-device-signing-pk',
                  mlKemPublicKey: 'bob-mlkem-pk',
                  keyPackageId: 'kp-bob-phone',
                  keyPackagePublicMaterial: 'kp-public-bob-phone',
                ),
                GroupMemberDeviceIdentity(
                  deviceId: 'bob-old-phone',
                  transportPeerId: '12D3KooWBobOld',
                  deviceSigningPublicKey: 'bob-old-signing-pk',
                  status: GroupMemberDeviceStatus.revoked,
                  revokedAt: DateTime.utc(2026, 6, 1, 11),
                ),
              ]),
              'joined_at': '2026-06-01T12:00:00.000Z',
            },
          ],
          groupMessageRows: [
            {
              'id': 'msg-9',
              'group_id': 'group-1',
              'sender_peer_id': 'peer-bob',
              'transport_peer_id': '12D3KooWBobPhone',
              'key_generation': 9,
              'logical_delivery_id': 'logical-msg-9',
              'status': 'pending_key',
            },
          ],
          groupMessageReceiptRows: [
            {
              'group_id': 'group-1',
              'message_id': 'msg-9',
              'receipt_type': 'delivered',
              'member_peer_id': 'peer-alice',
              'sender_device_id': 'alice-phone',
              'receipt_at': '2026-06-01T12:12:00.000Z',
              'source_event_id': 'sync-event-1',
              'created_at': '2026-06-01T12:12:01.000Z',
              'updated_at': '2026-06-01T12:12:02.000Z',
            },
          ],
          welcomeKeyPackageRows: [
            {
              'group_id': 'group-1',
              'package_id': 'kp-bob-phone',
              'invite_id': 'invite-bob',
              'recipient_peer_id': 'peer-bob',
              'recipient_device_id': 'bob-phone',
              'recipient_transport_peer_id': '12D3KooWBobPhone',
              'recipient_ml_kem_public_key': 'bob-mlkem-pk',
              'public_material_hash': 'public-hash-bob-phone',
              'key_epoch': 9,
              'issued_at': '2026-06-01T12:09:00.000Z',
              'expires_at': '2026-06-02T12:09:00.000Z',
            },
          ],
          pendingKeyRepairRows: [
            {
              'id': 'repair-msg-9',
              'group_id': 'group-1',
              'message_id': 'msg-9',
              'sender_peer_id': 'peer-bob',
              'transport_peer_id': '12D3KooWBobPhone',
              'payload_type': 'group_message',
              'key_epoch': 9,
              'replay_envelope_json':
                  '{"ciphertext":"serialized-private-key-material"}',
              'status': 'pending_key',
              'trigger_count': 2,
              'attempts': 1,
              'last_error': 'not serialized',
              'created_at': '2026-06-01T12:13:00.000Z',
              'updated_at': '2026-06-01T12:14:00.000Z',
            },
          ],
          pendingMembershipMessageRows: [
            {
              'id': 'membership-msg-1',
              'group_id': 'group-1',
              'sender_peer_id': 'peer-carol',
              'message_id': 'membership-wire-1',
              'payload_json':
                  '{"kind":"members_added","privateKey":"PRIVATE-MATERIAL"}',
              'received_at': '2026-06-01T12:15:00.000Z',
              'created_at': '2026-06-01T12:15:01.000Z',
              'updated_at': '2026-06-01T12:15:02.000Z',
            },
          ],
          welcomeKeyPackageTombstoneRows: [
            {
              'group_id': 'group-1',
              'package_id': 'kp-bob-phone',
              'recipient_device_id': 'bob-phone',
              'invite_id': 'invite-bob',
              'public_material_hash': 'public-hash-bob-phone',
              'consumed_at': '2026-06-01T12:16:00.000Z',
              'expires_at': '2026-06-02T12:16:00.000Z',
            },
          ],
          groupInboxCursorRows: [
            {
              'group_id': 'group-1',
              'cursor': 'cursor-page-2',
              'created_at': '2026-06-01T12:17:00.000Z',
              'updated_at': '2026-06-01T12:18:00.000Z',
            },
          ],
        );

        expect(manifest.isValid, isTrue);
        final group = manifest.groups.single;
        expect(group.groupId, 'group-1');
        expect(
          group.retainedGenerationRange,
          const MigrationGroupRetainedGenerationRange(
            minGeneration: 3,
            latestGeneration: 10,
          ),
        );
        expect(group.committedKeys.map((key) => key.keyGeneration), [
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
        ]);
        expect(
          group.committedKeys.every(
            (key) => key.primaryKeySha256 == key.sharedKeySha256,
          ),
          isTrue,
        );
        expect(
          group.committedKeys.first.primaryKeySha256,
          sha256.convert(utf8.encode('base64-key-3')).toString(),
        );
        expect(group.pendingDrafts.single.keyGeneration, 11);
        expect(group.pendingDrafts.single.requiresSharedMirror, isFalse);
        expect(group.pushPreviewReady, isTrue);
        expect(group.movedAccountActiveDeviceId, 'alice-phone');
        expect(group.devicePolicy, MigrationGroupDevicePolicy.preserveExisting);
        expect(
          group.members
              .singleWhere((member) => member.peerId == 'peer-bob')
              .devices,
          hasLength(2),
        );
        expect(
          group.members
              .singleWhere((member) => member.peerId == 'peer-alice')
              .devices
              .single
              .keyPackagePublicMaterialSha256,
          sha256.convert(utf8.encode('kp-public-alice-phone')).toString(),
        );
        expect(group.senderMetadata.single.transportPeerId, '12D3KooWBobPhone');
        expect(group.senderMetadata.single.logicalDeliveryId, 'logical-msg-9');
        expect(group.senderMetadata.single.keyGeneration, 9);
        expect(group.receiptMetadata.single.senderDeviceId, 'alice-phone');
        expect(group.receiptMetadata.single.receiptType, 'delivered');
        expect(group.receiptMetadata.single.sourceEventId, 'sync-event-1');
        expect(
          group.welcomePackageMetadata.single.recipientDeviceId,
          'bob-phone',
        );
        expect(
          group.welcomePackageMetadata.single.publicMaterialHash,
          'public-hash-bob-phone',
        );
        expect(group.pendingKeyRepairs.single.id, 'repair-msg-9');
        expect(group.pendingKeyRepairs.single.messageId, 'msg-9');
        expect(group.pendingKeyRepairs.single.keyEpoch, 9);
        expect(
          group.pendingKeyRepairs.single.replayEnvelopeSha256,
          sha256
              .convert(
                utf8.encode('{"ciphertext":"serialized-private-key-material"}'),
              )
              .toString(),
        );
        expect(group.pendingMembershipMessages.single.id, 'membership-msg-1');
        expect(
          group.pendingMembershipMessages.single.payloadSha256,
          sha256
              .convert(
                utf8.encode(
                  '{"kind":"members_added","privateKey":"PRIVATE-MATERIAL"}',
                ),
              )
              .toString(),
        );
        expect(
          group.welcomePackageTombstones.single.publicMaterialHash,
          'public-hash-bob-phone',
        );
        expect(group.inboxCursors.single.cursor, 'cursor-page-2');

        final encoded = jsonEncode(manifest.toJson());
        expect(encoded, isNot(contains('base64-key-')));
        expect(encoded, isNot(contains('base64-draft-11')));
        expect(encoded, isNot(contains('kp-public-alice-phone')));
        expect(encoded, isNot(contains('kp-public-bob-phone')));
        expect(encoded, isNot(contains('serialized-private-key-material')));
        expect(encoded, isNot(contains('PRIVATE-MATERIAL')));
        expect(encoded, isNot(contains('privateKey')));
      },
    );
  });
}
