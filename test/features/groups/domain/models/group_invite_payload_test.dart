import 'dart:convert';

import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testGroupConfig = {
    'name': 'Book Club',
    'groupType': 'chat',
    'description': 'A test group',
    'members': [
      {
        'peerId': '12D3KooWAlice',
        'username': 'Alice',
        'role': 'admin',
        'publicKey': 'alicePubKey64',
        'mlKemPublicKey': 'aliceMlKem64',
      },
      {
        'peerId': '12D3KooWBob',
        'username': 'Bob',
        'role': 'writer',
        'publicKey': 'bobPubKey64',
        'mlKemPublicKey': 'bobMlKem64',
      },
    ],
    'createdBy': '12D3KooWAlice',
    'createdAt': '2026-03-02T00:00:00.000Z',
  };

  GroupInvitePolicy makePolicy({
    DateTime? expiresAt,
    List<String> allowedDevices = const ['12D3KooWBob'],
    String assignedRole = 'writer',
    bool? canInviteOthers = false,
    String joinMaterialKind = GroupInvitePolicy.inlineGroupKeyKind,
    int keyEpoch = 1,
    GroupInviteReusePolicy reusePolicy = GroupInviteReusePolicy.singleUse,
    String? keyPackageId,
    String? keyPackagePublicMaterialHash,
    DateTime? keyPackageExpiresAt,
  }) {
    final effectiveExpiresAt = expiresAt ?? DateTime.utc(2026, 3, 9, 12);
    return GroupInvitePolicy(
      expiresAt: effectiveExpiresAt,
      allowedDevices: allowedDevices,
      assignedRole: assignedRole,
      canInviteOthers: canInviteOthers,
      joinMaterialKind: joinMaterialKind,
      keyEpoch: keyEpoch,
      reusePolicy: reusePolicy,
      welcomeKeyPackageId: keyPackageId,
      welcomeKeyPackagePublicMaterialHash: keyPackagePublicMaterialHash,
      welcomeKeyPackageExpiresAt:
          keyPackageExpiresAt ??
          (keyPackageId == null ? null : effectiveExpiresAt),
    );
  }

  GroupInviteMembershipFreshnessProof makeFreshnessProof({
    String inviteId = 'invite-uuid-001',
    String groupId = 'grp-abc123',
    String? recipientPeerId = '12D3KooWBob',
    String? recipientDeviceId,
    String? recipientTransportPeerId,
    String? recipientMlKemPublicKey,
    String? recipientKeyPackageId,
    String? recipientKeyPackagePublicMaterial,
    int keyEpoch = 1,
    String groupConfigStateHash = 'group-config-state-hash-v1',
  }) {
    return GroupInviteMembershipFreshnessProof(
      inviteId: inviteId,
      groupId: groupId,
      recipientPeerId: recipientPeerId,
      recipientDeviceId: recipientDeviceId,
      recipientTransportPeerId: recipientTransportPeerId,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      recipientKeyPackageId: recipientKeyPackageId,
      recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
      inviterPeerId: '12D3KooWAlice',
      inviterDeviceId: null,
      inviterTransportPeerId: null,
      inviterDeviceSigningPublicKey: null,
      inviterKeyPackageId: null,
      inviterPublicKey: 'alicePubKey64',
      keyEpoch: keyEpoch,
      groupConfigStateHash: groupConfigStateHash,
      membershipWatermark: groupConfigStateHash,
      issuedAt: DateTime.utc(2026, 3, 2, 12),
      expiresAt: DateTime.utc(2026, 3, 3, 12),
      inviterMemberSnapshot: {
        'peerId': '12D3KooWAlice',
        'username': 'Alice',
        'role': 'admin',
        'publicKey': 'alicePubKey64',
        'mlKemPublicKey': 'aliceMlKem64',
      },
    );
  }

  GroupInvitePayload makePayload({
    GroupInvitePolicy? invitePolicy,
    Map<String, dynamic> groupConfig = testGroupConfig,
    String? recipientPeerId = '12D3KooWBob',
    String timestamp = '2026-03-02T12:00:00.000Z',
    int keyEpoch = 1,
    bool signed = true,
  }) {
    final payload = GroupInvitePayload(
      id: 'invite-uuid-001',
      groupId: 'grp-abc123',
      groupKey: 'base64GroupKey==',
      keyEpoch: keyEpoch,
      groupConfig: groupConfig,
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      timestamp: timestamp,
      recipientPeerId: recipientPeerId,
      invitePolicy: invitePolicy ?? makePolicy(keyEpoch: keyEpoch),
      membershipFreshnessProof: makeFreshnessProof(
        recipientPeerId: recipientPeerId,
        keyEpoch: keyEpoch,
        groupConfigStateHash:
            groupConfig['stateHash'] as String? ?? 'group-config-state-hash-v1',
      ),
    );
    return signed
        ? payload.withInviteSignature(signature: 'signed-invite-by-alice')
        : payload;
  }

  GroupWelcomeKeyPackage makeWelcomePackage({
    String inviteId = 'invite-device-001',
    String groupId = 'grp-abc123',
    int keyEpoch = 1,
    String packageId = 'kp-bob-phone',
    String publicMaterial = 'kp-pub-bob-phone-material-v1',
    DateTime? issuedAt,
    DateTime? expiresAt,
  }) {
    return GroupWelcomeKeyPackage.create(
      packageId: packageId,
      publicMaterial: publicMaterial,
      recipientPeerId: '12D3KooWBob',
      recipientDeviceId: 'bob-phone',
      recipientTransportPeerId: '12D3KooWBobPhone',
      recipientMlKemPublicKey: 'bobPhoneMlKem64',
      inviteId: inviteId,
      groupId: groupId,
      keyEpoch: keyEpoch,
      issuedAt: issuedAt ?? DateTime.utc(2026, 3, 2, 12),
      expiresAt: expiresAt ?? DateTime.utc(2026, 3, 9, 12),
    );
  }

  Map<String, dynamic> signedInnerMap(GroupInvitePayload payload) {
    final inner = jsonDecode(payload.toInnerJson()) as Map<String, dynamic>;
    final signedPayload = payload.canonicalInviteSignedPayload();
    return {
      ...inner,
      'inviteSignature': {
        'signatureAlgorithm': 'ed25519',
        'signedPayload': signedPayload,
        'signature': 'signed-invite-by-alice',
      },
    };
  }

  group('GroupInvitePayload', () {
    // --- Cycle 1.1 ---
    test('toInnerJson serializes all required fields', () {
      final payload = makePayload();
      final json = payload.toInnerJson();
      final map = jsonDecode(json) as Map<String, dynamic>;

      expect(map['id'], equals('invite-uuid-001'));
      expect(map['groupId'], equals('grp-abc123'));
      expect(map['groupKey'], equals('base64GroupKey=='));
      expect(map['keyEpoch'], equals(1));
      expect(map['senderPeerId'], equals('12D3KooWAlice'));
      expect(map['senderUsername'], equals('Alice'));
      expect(map['timestamp'], equals('2026-03-02T12:00:00.000Z'));
      expect(map['recipientPeerId'], equals('12D3KooWBob'));

      final policy = map['invitePolicy'] as Map<String, dynamic>;
      expect(policy['expiresAt'], equals('2026-03-09T12:00:00.000Z'));
      expect(policy['allowedDevices'], equals(['12D3KooWBob']));
      expect(policy['invitePermissions']['assignedRole'], equals('writer'));
      expect(policy['invitePermissions']['canInviteOthers'], isFalse);
      expect(policy['joinMaterialRef']['kind'], equals('inlineGroupKey'));
      expect(policy['joinMaterialRef']['keyEpoch'], equals(1));
      expect(policy['reusePolicy']['mode'], equals('singleUse'));
      expect(map['inviteSignature'], isA<Map<String, dynamic>>());

      final config = map['groupConfig'] as Map<String, dynamic>;
      expect(config['name'], equals('Book Club'));
      expect(config['groupType'], equals('chat'));
      expect(config['createdBy'], equals('12D3KooWAlice'));
      expect(config['createdAt'], equals('2026-03-02T00:00:00.000Z'));

      final members = config['members'] as List<dynamic>;
      expect(members, hasLength(2));
      final firstMember = members[0] as Map<String, dynamic>;
      expect(firstMember['peerId'], equals('12D3KooWAlice'));
      expect(firstMember['role'], equals('admin'));
      expect(firstMember['publicKey'], equals('alicePubKey64'));
    });

    // --- Cycle 1.2 ---
    test('fromInnerJson round-trips with toInnerJson', () {
      final original = makePayload();
      final json = original.toInnerJson();
      final parsed = GroupInvitePayload.fromInnerJson(json);

      expect(parsed, isNotNull);
      expect(parsed!.id, equals(original.id));
      expect(parsed.groupId, equals(original.groupId));
      expect(parsed.groupKey, equals(original.groupKey));
      expect(parsed.keyEpoch, equals(original.keyEpoch));
      expect(parsed.senderPeerId, equals(original.senderPeerId));
      expect(parsed.senderUsername, equals(original.senderUsername));
      expect(parsed.timestamp, equals(original.timestamp));
      expect(parsed.recipientPeerId, equals('12D3KooWBob'));
      expect(parsed.invitePolicy.assignedRole, equals('writer'));
      expect(parsed.invitePolicy.allowedDevices, equals(['12D3KooWBob']));
      expect(parsed.invitePolicy.reusePolicy, GroupInviteReusePolicy.singleUse);

      final config = parsed.groupConfig;
      expect(config['name'], equals('Book Club'));
      final members = config['members'] as List<dynamic>;
      expect(members, hasLength(2));
    });

    test('signed payload binds recipient member and device identity', () {
      final baseMembers = testGroupConfig['members'] as List<dynamic>;
      final deviceConfig = {
        ...testGroupConfig,
        'members': [
          baseMembers[0],
          {
            'peerId': '12D3KooWBob',
            'username': 'Bob',
            'role': 'writer',
            'publicKey': 'bobPubKey64',
            'mlKemPublicKey': 'bobLegacyMlKem64',
            'devices': [
              {
                'deviceId': 'bob-phone',
                'transportPeerId': '12D3KooWBobPhone',
                'deviceSigningPublicKey': 'bobPhonePk64',
                'mlKemPublicKey': 'bobPhoneMlKem64',
                'keyPackageId': 'kp-bob-phone',
                'keyPackagePublicMaterial': 'kp-pub-bob-phone-material-v1',
                'status': 'active',
              },
            ],
          },
        ],
      };
      final payload = GroupInvitePayload(
        id: 'invite-device-001',
        groupId: 'grp-abc123',
        groupKey: 'base64GroupKey==',
        keyEpoch: 1,
        groupConfig: deviceConfig,
        senderPeerId: '12D3KooWAlice',
        senderUsername: 'Alice',
        timestamp: '2026-03-02T12:00:00.000Z',
        recipientPeerId: '12D3KooWBob',
        recipientDeviceId: 'bob-phone',
        recipientTransportPeerId: '12D3KooWBobPhone',
        recipientMlKemPublicKey: 'bobPhoneMlKem64',
        recipientKeyPackageId: 'kp-bob-phone',
        recipientKeyPackagePublicMaterial: 'kp-pub-bob-phone-material-v1',
        welcomeKeyPackage: makeWelcomePackage(),
        invitePolicy: makePolicy(
          allowedDevices: const ['bob-phone'],
          keyPackageId: 'kp-bob-phone',
          keyPackagePublicMaterialHash:
              GroupWelcomeKeyPackage.hashPublicMaterial(
                'kp-pub-bob-phone-material-v1',
              ),
        ),
        membershipFreshnessProof: makeFreshnessProof(
          inviteId: 'invite-device-001',
          recipientPeerId: '12D3KooWBob',
          recipientDeviceId: 'bob-phone',
          recipientTransportPeerId: '12D3KooWBobPhone',
          recipientMlKemPublicKey: 'bobPhoneMlKem64',
          recipientKeyPackageId: 'kp-bob-phone',
          recipientKeyPackagePublicMaterial: 'kp-pub-bob-phone-material-v1',
        ),
      ).withInviteSignature(signature: 'signed-invite-by-alice');

      final parsed = GroupInvitePayload.fromInnerJson(payload.toInnerJson());

      expect(parsed, isNotNull);
      expect(parsed!.recipientDeviceId, 'bob-phone');
      expect(parsed.welcomeKeyPackage, isNotNull);
      expect(parsed.invitePolicy.welcomeKeyPackageId, 'kp-bob-phone');
      expect(
        parsed.isBoundToRecipientDevice(
          ownPeerId: '12D3KooWBob',
          ownDeviceId: 'bob-phone',
          ownTransportPeerId: '12D3KooWBobPhone',
          ownMlKemPublicKey: 'bobPhoneMlKem64',
          ownKeyPackageId: 'kp-bob-phone',
          ownKeyPackagePublicMaterial: 'kp-pub-bob-phone-material-v1',
        ),
        isTrue,
      );
      expect(
        parsed.isBoundToRecipientDevice(
          ownPeerId: '12D3KooWBob',
          ownDeviceId: 'bob-tablet',
          ownTransportPeerId: '12D3KooWBobTablet',
        ),
        isFalse,
      );
    });

    test(
      'EK011 signed payload binds first-class welcome key package metadata',
      () {
        final welcomePackage = makeWelcomePackage();
        final payload = GroupInvitePayload(
          id: 'invite-device-001',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: {
            ...testGroupConfig,
            'members': [
              (testGroupConfig['members'] as List<dynamic>)[0],
              {
                'peerId': '12D3KooWBob',
                'username': 'Bob',
                'role': 'writer',
                'publicKey': 'bobPubKey64',
                'mlKemPublicKey': 'bobLegacyMlKem64',
                'devices': [
                  {
                    'deviceId': 'bob-phone',
                    'transportPeerId': '12D3KooWBobPhone',
                    'deviceSigningPublicKey': 'bobPhonePk64',
                    'mlKemPublicKey': 'bobPhoneMlKem64',
                    'keyPackageId': 'kp-bob-phone',
                    'keyPackagePublicMaterial': 'kp-pub-bob-phone-material-v1',
                    'status': 'active',
                  },
                ],
              },
            ],
          },
          senderPeerId: '12D3KooWAlice',
          senderUsername: 'Alice',
          timestamp: '2026-03-02T12:00:00.000Z',
          recipientPeerId: '12D3KooWBob',
          recipientDeviceId: 'bob-phone',
          recipientTransportPeerId: '12D3KooWBobPhone',
          recipientMlKemPublicKey: 'bobPhoneMlKem64',
          recipientKeyPackageId: 'kp-bob-phone',
          recipientKeyPackagePublicMaterial: 'kp-pub-bob-phone-material-v1',
          welcomeKeyPackage: welcomePackage,
          invitePolicy: makePolicy(
            allowedDevices: const ['bob-phone'],
            keyPackageId: welcomePackage.packageId,
            keyPackagePublicMaterialHash: welcomePackage.publicMaterialHash,
          ),
          membershipFreshnessProof: makeFreshnessProof(
            inviteId: 'invite-device-001',
            recipientPeerId: '12D3KooWBob',
            recipientDeviceId: 'bob-phone',
            recipientTransportPeerId: '12D3KooWBobPhone',
            recipientMlKemPublicKey: 'bobPhoneMlKem64',
            recipientKeyPackageId: 'kp-bob-phone',
            recipientKeyPackagePublicMaterial: 'kp-pub-bob-phone-material-v1',
          ),
        ).withInviteSignature(signature: 'signed-invite-by-alice');

        final signedPayload =
            jsonDecode(payload.canonicalInviteSignedPayload())
                as Map<String, dynamic>;
        expect(signedPayload['welcomeKeyPackage'], welcomePackage.toJson());
        expect(
          ((signedPayload['invitePolicy']
                  as Map<String, dynamic>)['joinMaterialRef'])
              as Map<String, dynamic>,
          containsPair('welcomeKeyPackageId', 'kp-bob-phone'),
        );

        final parsed = GroupInvitePayload.fromInnerJson(payload.toInnerJson());
        expect(parsed, isNotNull);

        final tampered =
            jsonDecode(payload.toInnerJson()) as Map<String, dynamic>;
        (tampered['welcomeKeyPackage']
                as Map<String, dynamic>)['publicMaterial'] =
            'kp-pub-bob-phone-material-v2';
        expect(GroupInvitePayload.fromInnerJson(jsonEncode(tampered)), isNull);
      },
    );

    // --- Cycle 1.3 ---
    group('fromInnerJson returns null for missing required fields', () {
      test('returns null when groupId is missing', () {
        final json = jsonEncode({
          'id': 'invite-1',
          // 'groupId' omitted
          'groupKey': 'key',
          'keyEpoch': 1,
          'groupConfig': testGroupConfig,
          'senderPeerId': 'peer1',
          'senderUsername': 'Alice',
          'timestamp': '2026-01-01T00:00:00Z',
          'recipientPeerId': '12D3KooWBob',
          'invitePolicy': makePolicy().toJson(),
        });
        expect(GroupInvitePayload.fromInnerJson(json), isNull);
      });

      test('returns null when groupKey is missing', () {
        final json = jsonEncode({
          'id': 'invite-1',
          'groupId': 'grp-1',
          // 'groupKey' omitted
          'keyEpoch': 1,
          'groupConfig': testGroupConfig,
          'senderPeerId': 'peer1',
          'senderUsername': 'Alice',
          'timestamp': '2026-01-01T00:00:00Z',
          'recipientPeerId': '12D3KooWBob',
          'invitePolicy': makePolicy().toJson(),
        });
        expect(GroupInvitePayload.fromInnerJson(json), isNull);
      });

      test('returns null when groupConfig is missing', () {
        final json = jsonEncode({
          'id': 'invite-1',
          'groupId': 'grp-1',
          'groupKey': 'key',
          'keyEpoch': 1,
          // 'groupConfig' omitted
          'senderPeerId': 'peer1',
          'senderUsername': 'Alice',
          'timestamp': '2026-01-01T00:00:00Z',
          'recipientPeerId': '12D3KooWBob',
          'invitePolicy': makePolicy().toJson(),
        });
        expect(GroupInvitePayload.fromInnerJson(json), isNull);
      });

      test('returns null when input is not valid JSON', () {
        expect(GroupInvitePayload.fromInnerJson('not valid json'), isNull);
      });
    });

    // --- Cycle 1.4 ---
    test('toJson wraps payload in v1 envelope with type group_invite', () {
      final payload = makePayload();
      final json = payload.toJson();
      final map = jsonDecode(json) as Map<String, dynamic>;

      expect(map['type'], equals('group_invite'));
      expect(map['version'], equals('1'));
      expect(map['payload'], isA<Map<String, dynamic>>());

      final inner = map['payload'] as Map<String, dynamic>;
      expect(inner['id'], equals('invite-uuid-001'));
      expect(inner['groupId'], equals('grp-abc123'));
      expect(inner['groupKey'], equals('base64GroupKey=='));
      expect(inner['keyEpoch'], equals(1));
      expect(inner['groupConfig'], isA<Map<String, dynamic>>());
      expect(inner['invitePolicy'], isA<Map<String, dynamic>>());
    });

    // --- Cycle 1.5 ---
    test('fromJson parses v1 group_invite envelope', () {
      final payload = makePayload();
      final json = payload.toJson();
      final parsed = GroupInvitePayload.fromJson(json);

      expect(parsed, isNotNull);
      expect(parsed!.id, equals('invite-uuid-001'));
      expect(parsed.groupId, equals('grp-abc123'));
      expect(parsed.groupKey, equals('base64GroupKey=='));
      expect(parsed.keyEpoch, equals(1));
      expect(parsed.senderPeerId, equals('12D3KooWAlice'));
      expect(parsed.senderUsername, equals('Alice'));
      expect(parsed.invitePolicy.joinMaterialKind, equals('inlineGroupKey'));
    });

    test('IJ001 parses a first-class encrypted invite policy', () {
      final parsed = GroupInvitePayload.fromInnerJson(
        makePayload().toInnerJson(),
      );

      expect(parsed, isNotNull);
      expect(parsed!.invitePolicy.expiresAt, DateTime.utc(2026, 3, 9, 12));
      expect(parsed.invitePolicy.allowedDevices, ['12D3KooWBob']);
      expect(parsed.invitePolicy.assignedRole, 'writer');
      expect(parsed.invitePolicy.canInviteOthers, isFalse);
      expect(parsed.invitePolicy.joinMaterialKind, 'inlineGroupKey');
      expect(parsed.invitePolicy.keyEpoch, 1);
      expect(parsed.invitePolicy.reusePolicy, GroupInviteReusePolicy.singleUse);
    });

    test('IJ005 round-trips explicit multi-use reuse policy', () {
      final parsed = GroupInvitePayload.fromInnerJson(
        makePayload(
          invitePolicy: makePolicy(
            reusePolicy: GroupInviteReusePolicy.multiUse,
          ),
        ).toInnerJson(),
      );

      expect(parsed, isNotNull);
      expect(parsed!.invitePolicy.reusePolicy, GroupInviteReusePolicy.multiUse);

      final inner = jsonDecode(parsed.toInnerJson()) as Map<String, dynamic>;
      final policy = inner['invitePolicy'] as Map<String, dynamic>;
      expect(policy['reusePolicy'], {'mode': 'multiUse'});
    });

    test('IJ005 keeps reuse policy encrypted and out of v2 cleartext', () {
      final envelope = GroupInvitePayload.buildEncryptedEnvelope(
        senderPeerId: '12D3KooWAlice',
        inviteId: 'invite-uuid-001',
        groupId: 'grp-abc123',
        senderUsername: 'Alice',
        groupName: 'Book Club',
        kem: 'fakeKem64',
        ciphertext: makePayload(
          invitePolicy: makePolicy(
            reusePolicy: GroupInviteReusePolicy.multiUse,
          ),
        ).toInnerJson(),
        nonce: 'fakeNonce64',
      );

      final parsed = GroupInvitePayload.parseEncryptedEnvelope(envelope)!;
      final cleartext = Map<String, dynamic>.from(parsed)..remove('encrypted');
      expect(cleartext.toString(), isNot(contains('reusePolicy')));
      expect(cleartext.toString(), isNot(contains('multiUse')));

      final encrypted = parsed['encrypted'] as Map<String, dynamic>;
      final inner =
          jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
      expect(
        ((inner['invitePolicy'] as Map<String, dynamic>)['reusePolicy']
            as Map<String, dynamic>)['mode'],
        'multiUse',
      );
    });

    test(
      'IJ001 rejects missing or contradictory first-class invite policy',
      () {
        Map<String, dynamic> validInner() =>
            jsonDecode(makePayload().toInnerJson()) as Map<String, dynamic>;

        void expectInvalid(Map<String, dynamic> inner) {
          expect(GroupInvitePayload.fromInnerJson(jsonEncode(inner)), isNull);
        }

        final missingPolicy = validInner()..remove('invitePolicy');
        expectInvalid(missingPolicy);

        final missingRecipient = validInner()..remove('recipientPeerId');
        expectInvalid(missingRecipient);

        final emptyAllowedDevices = validInner();
        (emptyAllowedDevices['invitePolicy']
                as Map<String, dynamic>)['allowedDevices'] =
            [];
        expectInvalid(emptyAllowedDevices);

        final excludingAllowedDevice = validInner();
        (excludingAllowedDevice['invitePolicy']
            as Map<String, dynamic>)['allowedDevices'] = [
          'otherPeer',
        ];
        expectInvalid(excludingAllowedDevice);

        final missingAssignedRole = validInner();
        ((missingAssignedRole['invitePolicy']
                    as Map<String, dynamic>)['invitePermissions']
                as Map<String, dynamic>)
            .remove('assignedRole');
        expectInvalid(missingAssignedRole);

        final roleMismatch = validInner();
        (((roleMismatch['invitePolicy']
                    as Map<String, dynamic>)['invitePermissions'])
                as Map<String, dynamic>)['assignedRole'] =
            'reader';
        expectInvalid(roleMismatch);

        final missingJoinMaterial = validInner();
        (missingJoinMaterial['invitePolicy'] as Map<String, dynamic>).remove(
          'joinMaterialRef',
        );
        expectInvalid(missingJoinMaterial);

        final wrongJoinMaterialKind = validInner();
        (((wrongJoinMaterialKind['invitePolicy']
                    as Map<String, dynamic>)['joinMaterialRef'])
                as Map<String, dynamic>)['kind'] =
            'externalRef';
        expectInvalid(wrongJoinMaterialKind);

        final wrongJoinMaterialEpoch = validInner();
        (((wrongJoinMaterialEpoch['invitePolicy']
                    as Map<String, dynamic>)['joinMaterialRef'])
                as Map<String, dynamic>)['keyEpoch'] =
            2;
        expectInvalid(wrongJoinMaterialEpoch);

        final staleExpiry = validInner();
        (staleExpiry['invitePolicy'] as Map<String, dynamic>)['expiresAt'] =
            '2026-03-02T12:00:00.000Z';
        expectInvalid(staleExpiry);
      },
    );

    test(
      'IJ005 rejects missing, empty, unknown, or contradictory reuse policy',
      () {
        Map<String, dynamic> validInner() =>
            jsonDecode(makePayload().toInnerJson()) as Map<String, dynamic>;

        void expectInvalid(
          String label,
          void Function(Map<String, dynamic> policy) mutate,
        ) {
          final inner = validInner();
          final policy = inner['invitePolicy'] as Map<String, dynamic>;
          mutate(policy);
          expect(
            GroupInvitePayload.fromInnerJson(jsonEncode(inner)),
            isNull,
            reason: label,
          );
        }

        expectInvalid('missing reusePolicy', (policy) {
          policy.remove('reusePolicy');
        });
        expectInvalid('empty reusePolicy', (policy) {
          policy['reusePolicy'] = {'mode': ''};
        });
        expectInvalid('unknown reusePolicy', (policy) {
          policy['reusePolicy'] = {'mode': 'linkReusable'};
        });
        expectInvalid('contradictory reusePolicy', (policy) {
          policy['reusePolicy'] = {'mode': 'singleUse', 'maxUses': 2};
        });
      },
    );

    test(
      'IJ002 requires signed invite attestation and rejects canonical mismatch',
      () {
        final unsigned = makePayload(signed: false);
        expect(
          GroupInvitePayload.fromInnerJson(unsigned.toInnerJson()),
          isNull,
          reason: 'unsigned invites must fail closed after IJ-002',
        );

        final signed = signedInnerMap(unsigned);
        expect(GroupInvitePayload.fromInnerJson(jsonEncode(signed)), isNotNull);

        final unsupportedAlgorithm = signedInnerMap(unsigned);
        (unsupportedAlgorithm['inviteSignature']
                as Map<String, dynamic>)['signatureAlgorithm'] =
            'rsa-pss';
        expect(
          GroupInvitePayload.fromInnerJson(jsonEncode(unsupportedAlgorithm)),
          isNull,
        );

        final nonCanonicalPayload = signedInnerMap(unsigned);
        final signature =
            nonCanonicalPayload['inviteSignature'] as Map<String, dynamic>;
        signature['signedPayload'] = ' ${signature['signedPayload']} ';
        expect(
          GroupInvitePayload.fromInnerJson(jsonEncode(nonCanonicalPayload)),
          isNull,
        );

        void expectTamperRejected(
          String label,
          void Function(Map<String, dynamic> inner) mutate,
        ) {
          final tampered = signedInnerMap(unsigned);
          mutate(tampered);
          expect(
            GroupInvitePayload.fromInnerJson(jsonEncode(tampered)),
            isNull,
            reason: label,
          );
        }

        expectTamperRejected(
          'senderPeerId mismatch',
          (inner) => inner['senderPeerId'] = '12D3KooWMallory',
        );
        expectTamperRejected(
          'senderUsername mismatch',
          (inner) => inner['senderUsername'] = 'Mallory',
        );
        expectTamperRejected(
          'recipientPeerId mismatch',
          (inner) => inner['recipientPeerId'] = '12D3KooWCarol',
        );
        expectTamperRejected(
          'groupId mismatch',
          (inner) => inner['groupId'] = 'grp-tampered',
        );
        expectTamperRejected(
          'groupKey mismatch',
          (inner) => inner['groupKey'] = 'tampered-key',
        );
        expectTamperRejected(
          'keyEpoch mismatch',
          (inner) => inner['keyEpoch'] = 2,
        );
        expectTamperRejected(
          'groupConfig mismatch',
          (inner) => (inner['groupConfig'] as Map<String, dynamic>)['name'] =
              'Tampered',
        );
        expectTamperRejected(
          'invitePolicy mismatch',
          (inner) =>
              (((inner['invitePolicy']
                          as Map<String, dynamic>)['joinMaterialRef'])
                      as Map<String, dynamic>)['keyEpoch'] =
                  2,
        );
      },
    );

    test(
      'G3-003 current-time validation is opt-in for parse-only inspection',
      () {
        final staleFreshnessPayload = makePayload();

        expect(
          GroupInvitePayload.fromInnerJson(staleFreshnessPayload.toInnerJson()),
          isNotNull,
        );

        final staleFreshnessResult = GroupInvitePayload.parseInnerJsonDetailed(
          staleFreshnessPayload.toInnerJson(),
          validationTime: DateTime.utc(2026, 3, 3, 13),
        );
        expect(staleFreshnessResult.payload, isNull);
        expect(
          staleFreshnessResult.failure,
          GroupInvitePayloadParseFailure.staleMembershipFreshness,
        );

        final expiredPolicyPayload = makePayload(
          invitePolicy: makePolicy(expiresAt: DateTime.utc(2026, 3, 2, 13)),
        );

        expect(
          GroupInvitePayload.fromJson(expiredPolicyPayload.toJson()),
          isNotNull,
        );

        final expiredPolicyResult = GroupInvitePayload.parseJsonDetailed(
          expiredPolicyPayload.toJson(),
          validationTime: DateTime.utc(2026, 3, 2, 13, 1),
        );
        expect(expiredPolicyResult.payload, isNull);
        expect(
          expiredPolicyResult.failure,
          GroupInvitePayloadParseFailure.expired,
        );
      },
    );

    test(
      'PREREQ-INVITER-FRESHNESS requires signed membership freshness proof and rejects proof tampering',
      () {
        final payload = makePayload();
        final signedPayload =
            jsonDecode(payload.canonicalInviteSignedPayload())
                as Map<String, dynamic>;

        expect(
          signedPayload[groupInviteMembershipFreshnessProofField],
          isA<Map<String, dynamic>>(),
        );

        void expectTamperRejected(
          String reason,
          void Function(Map<String, dynamic> inner) tamper,
        ) {
          final inner = signedInnerMap(payload);
          tamper(inner);
          expect(
            GroupInvitePayload.fromInnerJson(jsonEncode(inner)),
            isNull,
            reason: reason,
          );
        }

        expectTamperRejected(
          'missing proof',
          (inner) => inner.remove(groupInviteMembershipFreshnessProofField),
        );
        expectTamperRejected(
          'malformed proof',
          (inner) =>
              inner[groupInviteMembershipFreshnessProofField] = 'not-a-proof',
        );
        expectTamperRejected(
          'proof invite id mismatch',
          (inner) =>
              (inner[groupInviteMembershipFreshnessProofField]
                      as Map<String, dynamic>)['inviteId'] =
                  'other-invite',
        );
        expectTamperRejected(
          'proof group id mismatch',
          (inner) =>
              (inner[groupInviteMembershipFreshnessProofField]
                      as Map<String, dynamic>)['groupId'] =
                  'other-group',
        );
        expectTamperRejected(
          'proof recipient mismatch',
          (inner) =>
              (inner[groupInviteMembershipFreshnessProofField]
                      as Map<String, dynamic>)['recipientPeerId'] =
                  '12D3KooWMallory',
        );
        expectTamperRejected(
          'proof key epoch mismatch',
          (inner) =>
              (inner[groupInviteMembershipFreshnessProofField]
                      as Map<String, dynamic>)['keyEpoch'] =
                  2,
        );
        expectTamperRejected(
          'proof group config hash mismatch',
          (inner) =>
              (inner[groupInviteMembershipFreshnessProofField]
                      as Map<String, dynamic>)['groupConfigStateHash'] =
                  'other-hash',
        );
      },
    );

    // --- Cycle 1.6 ---
    test('fromJson returns null for chat_message type', () {
      final json = jsonEncode({
        'type': 'chat_message',
        'version': '1',
        'payload': {
          'id': 'msg-1',
          'text': 'hello',
          'senderPeerId': 'peer1',
          'senderUsername': 'Alice',
          'timestamp': '2026-01-01T00:00:00Z',
        },
      });
      expect(GroupInvitePayload.fromJson(json), isNull);
    });

    // --- Cycle 1.7 ---
    test('buildEncryptedEnvelope produces v2 group_invite envelope', () {
      final envelope = GroupInvitePayload.buildEncryptedEnvelope(
        senderPeerId: '12D3KooWAlice',
        kem: 'fakeKem64',
        ciphertext: 'fakeCiphertext64',
        nonce: 'fakeNonce64',
      );

      final map = jsonDecode(envelope) as Map<String, dynamic>;
      expect(map['type'], equals('group_invite'));
      expect(map['version'], equals('2'));
      expect(map['senderPeerId'], equals('12D3KooWAlice'));

      final encrypted = map['encrypted'] as Map<String, dynamic>;
      expect(encrypted['kem'], equals('fakeKem64'));
      expect(encrypted['ciphertext'], equals('fakeCiphertext64'));
      expect(encrypted['nonce'], equals('fakeNonce64'));
    });

    // --- Cycle 1.8 ---
    group('parseEncryptedEnvelope', () {
      test('parses v2 group_invite envelope', () {
        final envelope = GroupInvitePayload.buildEncryptedEnvelope(
          senderPeerId: '12D3KooWAlice',
          kem: 'fakeKem64',
          ciphertext: 'fakeCiphertext64',
          nonce: 'fakeNonce64',
        );

        final result = GroupInvitePayload.parseEncryptedEnvelope(envelope);
        expect(result, isNotNull);
        expect(result!['type'], equals('group_invite'));
        expect(result['version'], equals('2'));
      });

      test('returns null for v2 chat_message (wrong type)', () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '2',
          'senderPeerId': 'peer1',
          'encrypted': {'kem': 'k', 'ciphertext': 'c', 'nonce': 'n'},
        });
        expect(GroupInvitePayload.parseEncryptedEnvelope(json), isNull);
      });

      test('returns null for v1 group_invite', () {
        final payload = makePayload();
        final v1 = payload.toJson();
        expect(GroupInvitePayload.parseEncryptedEnvelope(v1), isNull);
      });

      test('returns null for garbage JSON', () {
        expect(GroupInvitePayload.parseEncryptedEnvelope('not json'), isNull);
      });

      test(
        'returns null when encrypted block is missing kem/ciphertext/nonce',
        () {
          final json = jsonEncode({
            'type': 'group_invite',
            'version': '2',
            'senderPeerId': 'peer1',
            'encrypted': {
              'kem': 'k',
              // 'ciphertext' missing
              // 'nonce' missing
            },
          });
          expect(GroupInvitePayload.parseEncryptedEnvelope(json), isNull);
        },
      );
    });
  });
}
