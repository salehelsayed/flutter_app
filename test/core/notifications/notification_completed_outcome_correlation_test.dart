import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TC-369-04 wake correlation byte contract is canonical and installation local',
    () async {
      final fixture =
          jsonDecode(
                await File(
                  'test/shared/fixtures/wake_outcome_correlation_v1.json',
                ).readAsString(),
              )
              as Map<String, Object?>;
      expect(fixture['version'], 1);
      expect(fixture['domain'], notificationCompletedOutcomeCorrelationDomain);
      final vectors = (fixture['vectors'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(vectors, hasLength(4));
      expect(
        vectors.map((vector) => vector['installationRole']).toSet(),
        <Object?>{'primary', 'linked'},
      );

      for (final vector in vectors) {
        final kind = NotificationCompletedOutcomeProducerKind.tryParse(
          vector['producerKind'] as String,
        );
        expect(kind, isNotNull, reason: vector['name'] as String);
        expect(kind!.kindByte, vector['kindByte']);
        final envelope = (vector['envelope'] as Map<String, Object?>);
        final selectedEventKey = trySelectNotificationCompletedOutcomeEventKey(
          producerKind: kind,
          authenticatedEnvelope: envelope,
        );
        expect(
          selectedEventKey,
          vector['eventKey'],
          reason: vector['name'] as String,
        );
        final correlation = tryBuildNotificationCompletedOutcomeCorrelation(
          physicalPeerId: vector['physicalPeerId'] as String,
          producerKind: kind,
          eventKey: selectedEventKey!,
        );
        expect(correlation, isNotNull, reason: vector['name'] as String);
        expect(_hex(correlation!.preimage), vector['preimageHex']);
        expect(correlation.digest, vector['digest']);

        final bounded = vector['boundedLocalIdentity'] as String?;
        if (bounded != null) {
          expect(boundedReactionEventIdentity(selectedEventKey), bounded);
          expect(selectedEventKey, isNot(bounded));
          expect(
            tryComputeNotificationCompletedOutcomeCorrelation(
              physicalPeerId: vector['physicalPeerId'] as String,
              producerKind: kind,
              eventKey: bounded,
            ),
            isNot(vector['digest']),
            reason: 'the raw authenticated reaction ID is the hash authority',
          );
        }
      }

      final alias = vectors.singleWhere(
        (vector) => vector['name'] == 'group_message_alias_primary',
      );
      final aliasEnvelope = alias['envelope'] as Map<String, Object?>;
      expect(aliasEnvelope['messageId'], isNot(alias['eventKey']));
      expect(
        tryComputeNotificationCompletedOutcomeCorrelation(
          physicalPeerId: alias['physicalPeerId'] as String,
          producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
          eventKey: aliasEnvelope['messageId'] as String,
        ),
        isNot(alias['digest']),
      );
      expect(
        trySelectNotificationCompletedOutcomeEventKey(
          producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
          authenticatedEnvelope: <String, Object?>{
            'messageId': 'legacy-exact-message-id',
          },
        ),
        'legacy-exact-message-id',
      );
      expect(
        trySelectNotificationCompletedOutcomeEventKey(
          producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
          authenticatedEnvelope: <String, Object?>{
            'messageId': 'must-not-fallback',
            'logicalDeliveryId': '',
          },
        ),
        isNull,
      );

      final first = vectors.first;
      expect(
        tryComputeNotificationCompletedOutcomeCorrelation(
          physicalPeerId: '${first['physicalPeerId']}sibling',
          producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
          eventKey: first['eventKey'] as String,
        ),
        isNot(first['digest']),
        reason: 'a sibling physical installation owns a different namespace',
      );
      for (final invalid in <String>[
        '',
        ' leading',
        'trailing ',
        'contains\u0000control',
        'x' * (notificationCompletedOutcomeMaxEventKeyBytes + 1),
        String.fromCharCode(0xd800),
      ]) {
        expect(
          tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: first['physicalPeerId'] as String,
            producerKind:
                NotificationCompletedOutcomeProducerKind.directMessage,
            eventKey: invalid,
          ),
          isNull,
          reason: 'invalid exact event authority: ${invalid.length}',
        );
      }
      expect(
        tryComputeNotificationCompletedOutcomeCorrelation(
          physicalPeerId:
              'p' * (notificationCompletedOutcomeMaxPhysicalPeerIdBytes + 1),
          producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
          eventKey: first['eventKey'] as String,
        ),
        isNull,
      );

      const accountPublicKey = 'xXheGGW3CJOK/4Fh1XMAZJZmOxqhCDTjltxWaGmixmo=';
      const accountPeerId =
          '12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj';
      const transportPublicKey = 'xvKsVZiXDHljNxTT61w017/D6S2ljHNUs3mW2aSvOrI=';
      const transportPeerId =
          '12D3KooWPCyWnZCXR3VGdrQjLr5d8TBaAHD956XZvo6xoCXYB5AR';
      const primaryAuthority = LinkedInstallationAuthoritySnapshot(
        disposition: LinkedInstallationDisposition.primary,
        credential: null,
        failClosedReason: null,
      );
      const activeCredential = LinkedTransportCredential(
        state: LinkedTransportCredentialState.active,
        accountPeerId: accountPeerId,
        accountPublicKey: accountPublicKey,
        deviceId: 'installation-2',
        transportPeerId: transportPeerId,
        transportPublicKey: transportPublicKey,
        transportPrivateKey: 'test-private-key',
        createdAt: '2026-01-01T00:00:00.000Z',
        activatedAt: '2026-01-01T00:00:01.000Z',
      );
      const linkedAuthority = LinkedInstallationAuthoritySnapshot(
        disposition: LinkedInstallationDisposition.active,
        credential: activeCredential,
        failClosedReason: null,
      );
      expect(
        selectNotificationCompletedOutcomePhysicalPeerId(
          accountPeerId: accountPeerId,
          accountPublicKey: accountPublicKey,
          authority: primaryAuthority,
        ),
        accountPeerId,
      );
      expect(
        selectNotificationCompletedOutcomePhysicalPeerId(
          accountPeerId: accountPeerId,
          accountPublicKey: accountPublicKey,
          authority: linkedAuthority,
        ),
        transportPeerId,
        reason: 'a linked installation uses its physical transport namespace',
      );

      final invalidAuthorities = <LinkedInstallationAuthoritySnapshot>[
        const LinkedInstallationAuthoritySnapshot(
          disposition: LinkedInstallationDisposition.active,
          credential: null,
          failClosedReason: null,
        ),
        LinkedInstallationAuthoritySnapshot(
          disposition: LinkedInstallationDisposition.active,
          credential: LinkedTransportCredential(
            state: LinkedTransportCredentialState.active,
            accountPeerId: '${accountPeerId}sibling',
            accountPublicKey: accountPublicKey,
            deviceId: 'installation-2',
            transportPeerId: transportPeerId,
            transportPublicKey: transportPublicKey,
            transportPrivateKey: 'test-private-key',
            createdAt: '2026-01-01T00:00:00.000Z',
            activatedAt: '2026-01-01T00:00:01.000Z',
          ),
          failClosedReason: null,
        ),
        LinkedInstallationAuthoritySnapshot(
          disposition: LinkedInstallationDisposition.active,
          credential: LinkedTransportCredential(
            state: LinkedTransportCredentialState.active,
            accountPeerId: accountPeerId,
            accountPublicKey: transportPublicKey,
            deviceId: 'installation-2',
            transportPeerId: transportPeerId,
            transportPublicKey: transportPublicKey,
            transportPrivateKey: 'test-private-key',
            createdAt: '2026-01-01T00:00:00.000Z',
            activatedAt: '2026-01-01T00:00:01.000Z',
          ),
          failClosedReason: null,
        ),
        LinkedInstallationAuthoritySnapshot(
          disposition: LinkedInstallationDisposition.active,
          credential: LinkedTransportCredential(
            state: LinkedTransportCredentialState.active,
            accountPeerId: accountPeerId,
            accountPublicKey: accountPublicKey,
            deviceId: 'installation-2',
            transportPeerId: accountPeerId,
            transportPublicKey: transportPublicKey,
            transportPrivateKey: 'test-private-key',
            createdAt: '2026-01-01T00:00:00.000Z',
            activatedAt: '2026-01-01T00:00:01.000Z',
          ),
          failClosedReason: null,
        ),
        LinkedInstallationAuthoritySnapshot(
          disposition: LinkedInstallationDisposition.active,
          credential: LinkedTransportCredential(
            state: LinkedTransportCredentialState.active,
            accountPeerId: accountPeerId,
            accountPublicKey: accountPublicKey,
            deviceId: 'installation-2',
            transportPeerId: accountPeerId,
            transportPublicKey: accountPublicKey,
            transportPrivateKey: 'test-private-key',
            createdAt: '2026-01-01T00:00:00.000Z',
            activatedAt: '2026-01-01T00:00:01.000Z',
          ),
          failClosedReason: null,
        ),
      ];
      for (final invalidAuthority in invalidAuthorities) {
        expect(
          selectNotificationCompletedOutcomePhysicalPeerId(
            accountPeerId: accountPeerId,
            accountPublicKey: accountPublicKey,
            authority: invalidAuthority,
          ),
          isNull,
        );
      }
      for (final invalidAccount in <(String, String)>[
        ('${accountPeerId}sibling', accountPublicKey),
        (accountPeerId, transportPublicKey),
        (' $accountPeerId', accountPublicKey),
        (accountPeerId, 'not-base64'),
      ]) {
        expect(
          selectNotificationCompletedOutcomePhysicalPeerId(
            accountPeerId: invalidAccount.$1,
            accountPublicKey: invalidAccount.$2,
            authority: primaryAuthority,
          ),
          isNull,
        );
      }
    },
  );
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
