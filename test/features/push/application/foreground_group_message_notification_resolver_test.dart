import 'dart:convert';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_app/features/push/application/foreground_group_message_notification_resolver.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';

const _groupId = 'group-team';
const _localPeerId = 'peer-local';
const _senderPeerId = 'peer-alice';
const _senderTransportPeerId = 'transport-alice-phone';
const _messageId = 'message-7';
final _now = DateTime.utc(2026, 8, 4, 9);

GroupModel _group({
  String name = 'Trusted Team',
  GroupType type = GroupType.chat,
}) => GroupModel(
  id: _groupId,
  name: name,
  type: type,
  topicName: 'group-topic',
  createdAt: _now,
  createdBy: _localPeerId,
  myRole: GroupRole.member,
);

GroupMemberDeviceIdentity _device({
  String transportPeerId = _senderTransportPeerId,
  GroupMemberDeviceStatus status = GroupMemberDeviceStatus.active,
  DateTime? revokedAt,
}) => GroupMemberDeviceIdentity(
  deviceId: 'device-$transportPeerId',
  transportPeerId: transportPeerId,
  deviceSigningPublicKey: 'signing-key-$transportPeerId',
  status: status,
  revokedAt: revokedAt,
);

GroupMember _member({
  required String peerId,
  required String? username,
  required MemberRole role,
  List<GroupMemberDeviceIdentity> devices = const [],
  String? publicKey = 'legacy-signing-key',
}) => GroupMember(
  groupId: _groupId,
  peerId: peerId,
  username: username,
  role: role,
  devices: devices,
  publicKey: publicKey,
  joinedAt: _now,
);

RemoteMessage _encryptedPush({
  String senderPeerId = _senderPeerId,
  String senderTransportPeerId = _senderTransportPeerId,
  String? messageId = _messageId,
  Map<String, dynamic> extra = const {},
}) => RemoteMessage(
  data: <String, dynamic>{
    'type': 'group_message',
    'groupId': _groupId,
    'sender_id': senderPeerId,
    'sender_transport_peer_id': senderTransportPeerId,
    'message_id': ?messageId,
    'keyEpoch': '7',
    'ciphertext': 'ciphertext-7',
    'nonce': 'nonce-7',
    'title': 'ATTACKER GROUP',
    'body': 'ATTACKER: leaked provider copy',
    ...extra,
  },
);

Future<InMemoryGroupRepository> _trustedRepository({
  String groupName = 'Trusted Team',
  GroupType groupType = GroupType.chat,
  String senderPeerId = _senderPeerId,
  String? senderUsername = 'Local Alice',
  MemberRole senderRole = MemberRole.writer,
  List<GroupMemberDeviceIdentity>? senderDevices,
  bool saveKeys = true,
}) async {
  final repository = InMemoryGroupRepository();
  await repository.saveGroup(_group(name: groupName, type: groupType));
  await repository.saveMember(
    _member(
      peerId: _localPeerId,
      username: 'Local Bob',
      role: MemberRole.writer,
      devices: <GroupMemberDeviceIdentity>[
        _device(transportPeerId: 'transport-local-phone'),
      ],
    ),
  );
  await repository.saveMember(
    _member(
      peerId: senderPeerId,
      username: senderUsername,
      role: senderRole,
      devices: senderDevices ?? <GroupMemberDeviceIdentity>[_device()],
    ),
  );
  if (saveKeys) {
    for (final entry in const <(int, String)>[
      (6, 'group-key-generation-6'),
      (7, 'group-key-generation-7'),
      (8, 'group-key-generation-8'),
    ]) {
      await repository.saveKey(
        GroupKeyInfo(
          groupId: _groupId,
          keyGeneration: entry.$1,
          encryptedKey: entry.$2,
          createdAt: _now.add(Duration(minutes: entry.$1)),
        ),
      );
    }
  }
  return repository;
}

void main() {
  group('resolveForegroundGroupMessageNotification', () {
    test(
      'trusted roster transport and decrypted payload produce Signal-style copy',
      () async {
        final repository = await _trustedRepository();
        String? capturedKey;
        String? capturedCiphertext;
        String? capturedNonce;

        final resolved = await resolveForegroundGroupMessageNotification(
          message: _encryptedPush(),
          localPeerId: _localPeerId,
          groupRepository: repository,
          decryptGroup:
              ({required groupKey, required ciphertext, required nonce}) async {
                capturedKey = groupKey;
                capturedCiphertext = ciphertext;
                capturedNonce = nonce;
                return jsonEncode(<String, Object?>{
                  'groupId': _groupId,
                  'messageId': _messageId,
                  'senderPeerId': _senderPeerId,
                  'groupName': 'DECRYPTED ATTACKER GROUP',
                  'senderUsername': 'DECRYPTED ATTACKER SENDER',
                  'text': 'Hello secret',
                });
              },
          locale: const Locale('en'),
        );

        expect(capturedKey, 'group-key-generation-7');
        expect(capturedCiphertext, 'ciphertext-7');
        expect(capturedNonce, 'nonce-7');
        expect(resolved, isNotNull);
        expect(resolved!.title, 'Trusted Team');
        expect(resolved.body, 'Local Alice: Hello secret');
        expect(resolved.payload, 'group:group-team|message:message-7');
        expect(
          '${resolved.title}|${resolved.body}',
          isNot(contains('ATTACKER')),
        );
        expect(
          resolved.resolvedEventIdentity,
          const ResolvedPushEventIdentity.outerAndAuthenticated(
            kind: ConversationNotificationContentKind.message,
            canonicalEventId: _messageId,
          ),
        );
        final comparand =
            resolved.groupComparand
                as BackgroundGroupMessageNotificationComparand;
        expect(comparand.groupId, _groupId);
        expect(comparand.messageId, _messageId);
        expect(comparand.senderPeerId, _senderPeerId);
        expect(comparand.senderTransportPeerId, _senderTransportPeerId);
      },
    );

    test(
      'untrusted sender bindings roles and attribution fail closed before decrypt',
      () async {
        final scenarios = <String, Future<_UntrustedFixture> Function()>{
          'unknown transport': () async => _UntrustedFixture(
            repository: await _trustedRepository(
              senderDevices: <GroupMemberDeviceIdentity>[
                _device(transportPeerId: 'other-transport'),
              ],
            ),
            message: _encryptedPush(),
          ),
          'ambiguous transport': () async {
            final repository = await _trustedRepository();
            await repository.saveMember(
              _member(
                peerId: 'peer-eve',
                username: 'Local Eve',
                role: MemberRole.admin,
                devices: <GroupMemberDeviceIdentity>[_device()],
              ),
            );
            return _UntrustedFixture(
              repository: repository,
              message: _encryptedPush(),
            );
          },
          'revoked transport': () async => _UntrustedFixture(
            repository: await _trustedRepository(
              senderDevices: <GroupMemberDeviceIdentity>[
                _device(
                  status: GroupMemberDeviceStatus.revoked,
                  revokedAt: _now,
                ),
              ],
            ),
            message: _encryptedPush(),
          ),
          'self sender': () async => _UntrustedFixture(
            repository: await _trustedRepository(
              senderPeerId: _localPeerId,
              senderUsername: 'Local Bob',
              senderRole: MemberRole.admin,
            ),
            message: _encryptedPush(senderPeerId: _localPeerId),
          ),
          'reader in chat': () async => _UntrustedFixture(
            repository: await _trustedRepository(senderRole: MemberRole.reader),
            message: _encryptedPush(),
          ),
          'writer in announcement': () async => _UntrustedFixture(
            repository: await _trustedRepository(
              groupType: GroupType.announcement,
              senderRole: MemberRole.writer,
            ),
            message: _encryptedPush(),
          ),
          'blank group name': () async => _UntrustedFixture(
            repository: await _trustedRepository(groupName: '   '),
            message: _encryptedPush(),
          ),
          'missing sender name': () async => _UntrustedFixture(
            repository: await _trustedRepository(senderUsername: null),
            message: _encryptedPush(),
          ),
          'blank sender name': () async => _UntrustedFixture(
            repository: await _trustedRepository(senderUsername: '   '),
            message: _encryptedPush(),
          ),
        };

        for (final scenario in scenarios.entries) {
          final fixture = await scenario.value();
          var decryptCalls = 0;
          final resolved = await resolveForegroundGroupMessageNotification(
            message: fixture.message,
            localPeerId: _localPeerId,
            groupRepository: fixture.repository,
            decryptGroup:
                ({
                  required groupKey,
                  required ciphertext,
                  required nonce,
                }) async {
                  decryptCalls += 1;
                  return '{}';
                },
          );

          expect(resolved, isNull, reason: scenario.key);
          expect(decryptCalls, 0, reason: scenario.key);
        }
      },
    );

    test(
      'preview unavailable keeps trusted group and sender attribution',
      () async {
        final contentFreeRepository = await _trustedRepository(saveKeys: false);
        var decryptCalls = 0;
        final resolved = await resolveForegroundGroupMessageNotification(
          message: const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': _groupId,
              'sender_id': _senderPeerId,
              'sender_transport_peer_id': _senderTransportPeerId,
              'message_id': 'message-oversized',
              'preview_unavailable': '1',
            },
          ),
          localPeerId: _localPeerId,
          groupRepository: contentFreeRepository,
          decryptGroup:
              ({required groupKey, required ciphertext, required nonce}) async {
                decryptCalls += 1;
                return '{}';
              },
          locale: const Locale('de'),
        );

        expect(resolved?.title, 'Trusted Team');
        expect(resolved?.body, 'Local Alice: Nachricht');
        expect(decryptCalls, 0);

        final malformedRepository = await _trustedRepository();
        final malformed = await resolveForegroundGroupMessageNotification(
          message: const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': _groupId,
              'sender_id': _senderPeerId,
              'sender_transport_peer_id': _senderTransportPeerId,
              'message_id': 'message-malformed',
              'preview_unavailable': '1',
              'keyEpoch': '7',
              'ciphertext': 'partial-ciphertext',
            },
          ),
          localPeerId: _localPeerId,
          groupRepository: malformedRepository,
          decryptGroup:
              ({required groupKey, required ciphertext, required nonce}) async {
                decryptCalls += 1;
                return '{}';
              },
        );
        expect(malformed, isNull);
        expect(decryptCalls, 0);
      },
    );

    test('private media remains generic through foreground resolver', () async {
      final repository = await _trustedRepository();
      final resolved = await resolveForegroundGroupMessageNotification(
        message: _encryptedPush(messageId: 'private-message'),
        localPeerId: _localPeerId,
        groupRepository: repository,
        decryptGroup:
            ({required groupKey, required ciphertext, required nonce}) async =>
                jsonEncode(<String, Object?>{
                  'groupId': _groupId,
                  'messageId': 'private-message',
                  'senderPeerId': _senderPeerId,
                  'groupName': 'SECRET DECRYPTED GROUP',
                  'senderUsername': 'SECRET DECRYPTED SENDER',
                  'text': 'SECRET private caption',
                  'mediaPolicyVersion': 1,
                  'mediaLifecycle': 'viewOnce',
                  'mediaDurationSeconds': null,
                  'mediaProtected': true,
                }),
        locale: const Locale('en'),
      );

      expect(resolved, isNotNull);
      expect(resolved!.title, 'Mknoon');
      expect(resolved.body, 'New private media');
      final visibleCopy = '${resolved.title}|${resolved.body}';
      for (final forbidden in const <String>[
        'Trusted Team',
        'Local Alice',
        'SECRET',
        'caption',
        'viewOnce',
      ]) {
        expect(visibleCopy, isNot(contains(forbidden)));
      }
    });
  });
}

class _UntrustedFixture {
  const _UntrustedFixture({required this.repository, required this.message});

  final InMemoryGroupRepository repository;
  final RemoteMessage message;
}
