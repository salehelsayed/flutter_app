import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'main runtime shares one group presentation lane and background does not',
    () {
      final bootstrap = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final appRoot = File('lib/app/application_root.dart').readAsStringSync();
      final foregroundFallback = File(
        'lib/features/push/application/background_push_notification_fallback.dart',
      ).readAsStringSync();
      final backgroundHandler = File(
        'lib/features/push/application/background_message_handler.dart',
      ).readAsStringSync();
      final groupMessageListener = File(
        'lib/features/groups/application/group_message_listener.dart',
      ).readAsStringSync();

      expect(
        bootstrap,
        contains(
          'final groupNotificationPresentationCoordinator =\n'
          '        GroupNotificationPresentationCoordinator();',
        ),
      );
      expect(
        bootstrap,
        contains(
          'notificationPresentationCoordinator:\n'
          '          groupNotificationPresentationCoordinator,',
        ),
        reason: 'the listener/read projector must own the shared instance',
      );
      expect(
        bootstrap,
        contains(
          'groupNotificationPresentationCoordinator:\n'
          '            groupNotificationPresentationCoordinator,',
        ),
        reason: 'the foreground push fallback must receive that same instance',
      );
      expect(
        RegExp(
          r'presentationCoordinator\.runForGroup\(groupId, present\)',
        ).allMatches(foregroundFallback),
        hasLength(2),
        reason:
            'one unified anchored/unanchored message path and the reaction '
            'path share the key lane',
      );
      expect(
        appRoot,
        contains(
          'groupNotificationPresentationCoordinator:\n'
          '            widget.groupNotificationPresentationCoordinator,',
        ),
      );
      expect(
        appRoot,
        contains('evaluateGroupReactionNotificationDisplayPolicy'),
      );
      expect(appRoot, contains('target?.privateMediaPolicy.requiresRedaction'));
      expect(
        appRoot,
        contains('owner: MediaOwnerLane.group'),
        reason: 'reaction target kind must come only from group-owned media',
      );
      expect(
        backgroundHandler,
        isNot(contains('GroupNotificationPresentationCoordinator')),
        reason: 'the headless background isolate keeps durable-only authority',
      );
      expect(
        groupMessageListener,
        contains(
          'existingGroupIds: () async =>\n'
          '                (await groupRepo.getAllGroups()).map((group) => group.id),',
        ),
        reason: 'startup must reconcile exact zero-unread group cards once',
      );
    },
  );

  test(
    'receiver activation brackets projection rebuild with canonical recovery',
    () {
      final appRoot = File('lib/app/application_root.dart').readAsStringSync();

      expect(
        appRoot,
        contains(
          'widget.groupMessageListener.beginCanonicalNotificationRecovery',
        ),
      );
      expect(
        appRoot,
        contains(
          'widget.groupMessageListener.endCanonicalNotificationRecovery',
        ),
      );
      expect(
        appRoot.indexOf('await rebuildRecipientProjection();'),
        lessThan(appRoot.indexOf('await endCanonicalNotificationRecovery(')),
      );
    },
  );

  test('foreground FCM rechecks exact canonical read state inside the lane', () {
    final appRoot = File('lib/app/application_root.dart').readAsStringSync();
    final productionBootstrap = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final foregroundFallback = File(
      'lib/features/push/application/background_push_notification_fallback.dart',
    ).readAsStringSync();

    expect(
      appRoot,
      contains(
        'groupNotificationReadAcknowledgementResolver:\n'
        '            _isForegroundGroupNotificationReadAcknowledged,',
      ),
    );
    expect(appRoot, contains('currentReactionId: currentReaction?.id'));
    expect(
      appRoot,
      contains(
        'currentReactionAcknowledged:\n'
        '            currentReaction?.notificationAcknowledgedAt != null',
      ),
    );
    expect(
      foregroundFallback,
      contains('await readAcknowledgementResolver('),
      reason: 'the fresh exact read must occur in the keyed present callback',
    );
    expect(
      appRoot,
      contains('widget.groupNotificationPendingReadAcknowledgementResolver'),
      reason: 'canonical absence is not proof against push-before-inbox read',
    );
    expect(
      productionBootstrap,
      contains('dbLoadExactGroupNotificationReadAcknowledgement('),
      reason: 'production must inject the exact SQLCipher pending-read lookup',
    );
  });
}
