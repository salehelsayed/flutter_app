import 'package:flutter_app/core/debug/group_notification_projection_e2e.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e_main_actions.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Plan 330 installed Android endpoint request', () {
    test('accepts the exact nonce-bound group-A media command', () {
      final config = _command();

      final request = GroupNotificationProjectionE2ERequest.fromConfig(config);

      expect(request.phase, groupNotificationProjectionSendMediaPhase);
      expect(request.role, 'physical_author');
      expect(request.groupName, 'Plan330A-Abc123');
      expect(request.kind, 'group');
      expect(request.messageIds.keys, <String>[
        'jpeg',
        'mp4',
        'voice',
        'killed_jpeg',
      ]);
      expect(request.attachmentIds.values.toSet(), hasLength(4));
      expect(request.stepId, config['stepId']);
    });

    test('rejects media mutation outside the disposable group-A fixture', () {
      final config = _command(groupName: 'Plan330B-Abc123');

      expect(
        () => GroupNotificationProjectionE2ERequest.fromConfig(config),
        throwsFormatException,
      );
    });

    test('rejects arbitrary group names and non-UUID fixture identities', () {
      final arbitrary = _command(groupName: 'ExistingGroup');
      final reused = _command();
      reused['messageIds'] = <String, String>{
        ...Map<String, String>.from(reused['messageIds']! as Map),
        'jpeg': 'not-a-uuid',
      };

      expect(
        () => GroupNotificationProjectionE2ERequest.fromConfig(arbitrary),
        throwsFormatException,
      );
      expect(
        () => GroupNotificationProjectionE2ERequest.fromConfig(reused),
        throwsFormatException,
      );
    });

    test('failure receipt exposes only bounded routing facts', () {
      final config = _command();

      final receipt = groupNotificationProjectionE2EFailureReceipt(
        config: config,
        error: StateError('secret raw group id'),
      );

      expect(receipt['success'], isFalse);
      expect(receipt['status'], 'failed');
      expect(receipt['errorType'], 'StateError');
      expect(receipt['errorCode'], 'unexpected_state');
      expect(receipt.toString(), isNot(contains('secret raw group id')));
      expect(receipt, isNot(containsPair('groupName', anything)));
      expect(receipt, isNot(containsPair('messageIds', anything)));
    });

    test('failure receipt classifies known media preconditions safely', () {
      final receipt = groupNotificationProjectionE2EFailureReceipt(
        config: _command(),
        error: StateError('Plan 330 remote transport authority is ambiguous'),
      );

      expect(receipt['errorCode'], 'remote_transport_ambiguous');
      expect(receipt.toString(), isNot(contains('transport authority')));
    });

    test('media endpoint accepts one exact account-bound remote transport', () {
      expect(
        resolvePlan330AccountBoundRemoteTransport(
          remoteAccountPeerId: 'remote-account',
          activeTransportPeerIds: const <String>['remote-account'],
        ),
        'remote-account',
      );
    });

    test('media endpoint rejects absent multiple and distinct transports', () {
      for (final transports in const <List<String>>[
        <String>[],
        <String>['remote-account', 'remote-account'],
        <String>['remote-transport'],
        <String>[''],
      ]) {
        expect(
          resolvePlan330AccountBoundRemoteTransport(
            remoteAccountPeerId: 'remote-account',
            activeTransportPeerIds: transports,
          ),
          isNull,
        );
      }
    });

    test('TC-393-09 accepts only the fixed killed JPEG phase and role', () {
      final config = _command();
      config['phase'] = groupNotificationProjectionSendKilledJpegPhase;
      config['role'] = 'emulator_author';
      config['stepId'] =
          'plan330-$groupNotificationProjectionSendKilledJpegPhase-group-'
          'run-0123456789abcdef';

      final request = GroupNotificationProjectionE2ERequest.fromConfig(config);

      expect(request.phase, groupNotificationProjectionSendKilledJpegPhase);
      expect(
        request.messageIds[groupNotificationProjectionKilledJpegFixtureKey],
        isNotEmpty,
      );
      final genericMutation = Map<String, dynamic>.from(config)
        ..['kind'] = 'jpeg'
        ..['stepId'] =
            'plan330-$groupNotificationProjectionSendKilledJpegPhase-jpeg-'
            'run-0123456789abcdef';
      expect(
        () => GroupNotificationProjectionE2ERequest.fromConfig(genericMutation),
        throwsFormatException,
      );
    });

    test('legacy media sender excludes the distinct killed JPEG fixture', () {
      final request = GroupNotificationProjectionE2ERequest.fromConfig(
        _command(),
      );

      final messageIds = groupNotificationProjectionMediaFixtureSubset(
        request.messageIds,
      );
      final attachmentIds = groupNotificationProjectionMediaFixtureSubset(
        request.attachmentIds,
      );

      expect(messageIds.keys, groupNotificationProjectionMediaFixtureKeys);
      expect(attachmentIds.keys, groupNotificationProjectionMediaFixtureKeys);
      expect(
        messageIds,
        isNot(contains(groupNotificationProjectionKilledJpegFixtureKey)),
      );
      expect(
        attachmentIds,
        isNot(contains(groupNotificationProjectionKilledJpegFixtureKey)),
      );
    });

    test('publication diagnostics disclose only a fixed result vocabulary', () {
      final receipt = groupNotificationProjectionE2EFailureReceipt(
        config: _command(),
        error: StateError(
          'group-media mp4 authorityUnavailable publication failed',
        ),
      );

      expect(receipt['errorCode'], 'media_publication_authorityUnavailable');
      expect(receipt.toString(), isNot(contains('group-media')));
    });

    test(
      'publication disposition separates persistence from delivery errors',
      () {
        final now = DateTime.utc(2026, 8, 21);
        final optimistic = GroupMessage(
          id: 'message-id',
          groupId: 'group-id',
          senderPeerId: 'sender-id',
          senderUsername: 'Sender',
          text: '',
          timestamp: now,
          status: 'sending',
          isIncoming: false,
          createdAt: now,
        );

        expect(
          groupMediaReliabilityPublicationDisposition(
            result: SendGroupMessageResult.error,
            message: null,
            expectedMessageId: optimistic.id,
          ),
          'error_no_message',
        );
        expect(
          groupMediaReliabilityPublicationDisposition(
            result: SendGroupMessageResult.error,
            message: optimistic,
            expectedMessageId: optimistic.id,
          ),
          'error_sending',
        );
        expect(
          groupMediaReliabilityPublicationDisposition(
            result: SendGroupMessageResult.error,
            message: optimistic.copyWith(status: 'failed'),
            expectedMessageId: optimistic.id,
          ),
          'error_failed',
        );
      },
    );
  });
}

Map<String, dynamic> _command({String groupName = 'Plan330A-Abc123'}) {
  const runId = 'run-0123456789abcdef';
  return <String, dynamic>{
    'schema': groupNotificationProjectionE2ECommandSchema,
    'transport_action': groupNotificationProjectionE2EAction,
    'scenario': groupNotificationProjectionScenario,
    'stepId': 'plan330-$groupNotificationProjectionSendMediaPhase-group-$runId',
    'phase': groupNotificationProjectionSendMediaPhase,
    'role': 'physical_author',
    'runId': runId,
    'nonce': 'nonce-0123456789abcdef',
    'groupName': groupName,
    'kind': 'group',
    'messageIds': const <String, String>{
      'jpeg': '11111111-1111-4111-8111-111111111111',
      'mp4': '22222222-2222-4222-8222-222222222222',
      'voice': '33333333-3333-4333-8333-333333333333',
      'killed_jpeg': '77777777-7777-4777-8777-777777777777',
    },
    'attachmentIds': const <String, String>{
      'jpeg': '44444444-4444-4444-8444-444444444444',
      'mp4': '55555555-5555-4555-8555-555555555555',
      'voice': '66666666-6666-4666-8666-666666666666',
      'killed_jpeg': '88888888-8888-4888-8888-888888888888',
    },
  };
}
