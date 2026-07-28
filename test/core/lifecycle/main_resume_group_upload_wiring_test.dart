import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

void main() {
  test(
    'GPL-09B production wires atomic current-ordinary bookmark qualification',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final productionSource = await File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsString();
      final start = productionSource.indexOf(
        'final mediaAttachmentRepository = MediaAttachmentRepositoryImpl(',
      );
      expect(start, isNonNegative);
      final end = productionSource.indexOf(');', start);
      expect(end, greaterThan(start));

      final repositoryBlock = productionSource.substring(start, end);
      expect(repositoryBlock, contains('dbSetGroupMediaBookmarkedIfOrdinary:'));
      expect(
        repositoryBlock,
        contains('dbSetGroupMediaBookmarkedIfOrdinary('),
        reason:
            'production group bookmark mutation must use the exact atomic parent predicate',
      );
    },
  );

  test('GPL-03B production and root supply retry authority', () async {
    expect(app.MyApp.navigatorKey, isNotNull);

    final productionSource = await File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsString();
    final applicationRootSource = await File(
      'lib/app/application_root.dart',
    ).readAsString();
    final backgroundStart = productionSource.indexOf(
      'retryFailedGroupInboxStoresFn: () => runAccountRuntimeNetworkAction(',
    );
    final backgroundEnd = productionSource.indexOf(
      'clearGroupRetryBackoffFn:',
      backgroundStart,
    );
    expect(backgroundStart, isNonNegative);
    expect(backgroundEnd, greaterThan(backgroundStart));
    final backgroundBlock = productionSource.substring(
      backgroundStart,
      backgroundEnd,
    );
    expect(backgroundBlock, contains('groupRepo: groupRepository'));
    expect(backgroundBlock, contains('identityRepo: repository'));

    final resumeStart = applicationRootSource.lastIndexOf(
      'retryFailedGroupInboxStoresFn: () => retryFailedGroupInboxStores(',
    );
    final resumeEnd = applicationRootSource.indexOf('      );', resumeStart);
    expect(resumeStart, isNonNegative);
    expect(resumeEnd, greaterThan(resumeStart));
    final resumeBlock = applicationRootSource.substring(resumeStart, resumeEnd);
    expect(resumeBlock, contains('groupRepo: widget.groupRepository'));
    expect(resumeBlock, contains('identityRepo: widget.repository'));
  });

  test(
    'production passes mediaFileManager into background direct upload retries',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final productionSource = await File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsString();
      final start = productionSource.indexOf(
        'retryIncompleteUploadsFn: () => runAccountRuntimeNetworkAction(',
      );

      expect(start, isNonNegative);

      final end = productionSource.indexOf(
        'final pendingPostMediaUploadRetrier = PendingPostMediaUploadRetrier(',
        start,
      );
      expect(end, greaterThan(start));

      final retryBlock = productionSource.substring(start, end);
      expect(
        retryBlock,
        contains('mediaFileManager: mediaFileManager'),
        reason:
            'resume-time 1:1 upload retry must resolve persisted pending_uploads paths',
      );
    },
  );

  test(
    'application root passes mediaFileManager into direct uploads on resume',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final applicationRootSource = await File(
        'lib/app/application_root.dart',
      ).readAsString();
      final start = applicationRootSource.lastIndexOf(
        'retryIncompleteUploadsFn: () => retryIncompleteUploads(',
      );

      expect(start, isNonNegative);

      final end = applicationRootSource.indexOf(
        'retryFailedMessagesFn:',
        start,
      );
      expect(end, greaterThan(start));

      final retryBlock = applicationRootSource.substring(start, end);
      expect(
        retryBlock,
        contains('mediaFileManager: widget.mediaFileManager'),
        reason:
            'app-resume 1:1 upload retry must resolve persisted pending_uploads paths',
      );
    },
  );

  test(
    'TC-17 production and root wire mediaFileManager through retry paths',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final productionSource = await File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsString();
      final applicationRootSource = await File(
        'lib/app/application_root.dart',
      ).readAsString();
      final retrierStart = productionSource.indexOf(
        'final pendingMessageRetrier = PendingMessageRetrier(',
      );
      final retrierEnd = productionSource.indexOf(
        'rejoinGroupTopicsWithRecoveryAckEligibilityFn:',
        retrierStart,
      );
      expect(retrierStart, isNonNegative);
      expect(retrierEnd, greaterThan(retrierStart));
      expect(
        productionSource.substring(retrierStart, retrierEnd),
        contains('mediaFileManager: mediaFileManager'),
        reason:
            'the default PendingMessageRetrier failed-message path must receive the resolver',
      );

      final resumeStart = applicationRootSource.lastIndexOf(
        'retryFailedMessagesFn: () => retryFailedMessages(',
      );
      final resumeEnd = applicationRootSource.indexOf(
        'retryUnackedMessagesFn:',
        resumeStart,
      );
      expect(resumeStart, isNonNegative);
      expect(resumeEnd, greaterThan(resumeStart));
      expect(
        applicationRootSource.substring(resumeStart, resumeEnd),
        contains('mediaFileManager: widget.mediaFileManager'),
        reason:
            'the explicit app-resume failed-message path must receive the resolver',
      );
    },
  );

  test(
    'Plan 262 wires private settlement authority through both unacked retry entry points',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final applicationRootSource = await File(
        'lib/app/application_root.dart',
      ).readAsString();
      final resumeStart = applicationRootSource.lastIndexOf(
        'retryUnackedMessagesFn: () => retryUnackedMessages(',
      );
      final resumeEnd = applicationRootSource.indexOf(
        'verifyInboxCustodyFn:',
        resumeStart,
      );
      expect(resumeStart, isNonNegative);
      expect(resumeEnd, greaterThan(resumeStart));
      expect(
        applicationRootSource.substring(resumeStart, resumeEnd),
        contains('mediaAttachmentRepo: widget.mediaAttachmentRepository'),
        reason:
            'app-resume unacked replay must receive the private mutation coordinator',
      );

      final retrierSource = await File(
        'lib/core/services/pending_message_retrier.dart',
      ).readAsString();
      final retrierStart = retrierSource.indexOf(
        'Future<int> _retryUnackedMessagesNow({Duration? olderThan})',
      );
      final retrierEnd = retrierSource.indexOf('\n  }', retrierStart);
      expect(retrierStart, isNonNegative);
      expect(retrierEnd, greaterThan(retrierStart));
      expect(
        retrierSource.substring(retrierStart, retrierEnd),
        contains('mediaAttachmentRepo: mediaAttachmentRepo'),
        reason:
            'background unacked replay must receive the private mutation coordinator',
      );
    },
  );

  test(
    'application root passes mediaFileManager into group uploads on resume',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final applicationRootSource = await File(
        'lib/app/application_root.dart',
      ).readAsString();
      final start = applicationRootSource.indexOf(
        'retryIncompleteGroupUploadsFn: () => retryIncompleteGroupUploads(',
      );

      expect(start, isNonNegative);

      final end = applicationRootSource.indexOf(
        'retryFailedGroupMessagesFn:',
        start,
      );
      expect(end, greaterThan(start));

      final retryBlock = applicationRootSource.substring(start, end);
      expect(
        retryBlock,
        contains('mediaFileManager: widget.mediaFileManager'),
        reason:
            'resume-time group upload retry must resolve persisted pending_uploads paths',
      );
    },
  );

  test(
    'application root passes media repository into failed groups on resume',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final applicationRootSource = await File(
        'lib/app/application_root.dart',
      ).readAsString();
      final start = applicationRootSource.indexOf(
        'retryFailedGroupMessagesFn: () => retryFailedGroupMessages(',
      );

      expect(start, isNonNegative);

      final end = applicationRootSource.indexOf(
        'retryIncompleteUploadsFn:',
        start,
      );
      expect(end, greaterThan(start));

      final retryBlock = applicationRootSource.substring(start, end);
      expect(
        retryBlock,
        contains('mediaAttachmentRepo: widget.mediaAttachmentRepository'),
        reason:
            'resume-time failed group retry must reload persisted media attachments',
      );
    },
  );

  test('production wires group retry callbacks into PendingMessageRetrier', () async {
    expect(app.MyApp.navigatorKey, isNotNull);

    final productionSource = await File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsString();
    final start = productionSource.indexOf(
      'final pendingMessageRetrier = PendingMessageRetrier(',
    );

    expect(start, isNonNegative);

    final end = productionSource.indexOf(
      'recoverStuckSendingMessagesFn:',
      start,
    );
    expect(end, greaterThan(start));

    final retrierBlock = productionSource.substring(start, end);
    expect(
      retrierBlock,
      contains('rejoinGroupTopicsWithRecoveryAckEligibilityFn: () async {'),
    );
    expect(
      retrierBlock,
      contains(
        'acknowledgeGroupRecoveryFn: () => runAccountRuntimeNetworkVoidAction(',
      ),
    );
    expect(
      retrierBlock,
      contains('action: () => callGroupAcknowledgeRecovery(bridge),'),
    );
    expect(retrierBlock, contains('rejoinResult.canAcknowledgeGroupRecovery'));
    expect(retrierBlock, contains('drainGroupOfflineInboxFn: () async {'));
    expect(
      retrierBlock,
      contains('final identity = await repository.loadIdentity();'),
    );
    expect(retrierBlock, contains('return drainGroupOfflineInbox('));
    expect(retrierBlock, contains('selfPeerId: identity?.peerId,'));
    expect(
      retrierBlock,
      contains(
        'recoverStuckSendingGroupMessagesFn: () => runAccountRuntimeNetworkAction(',
      ),
    );
    expect(
      retrierBlock,
      contains('action: () => recoverStuckSendingGroupMessages('),
    );
    expect(
      retrierBlock,
      contains(
        'retryIncompleteGroupUploadsFn: () => runAccountRuntimeNetworkAction(',
      ),
    );
    expect(
      retrierBlock,
      contains('action: () => retryIncompleteGroupUploads('),
    );
    expect(
      retrierBlock,
      contains(
        'retryFailedGroupMessagesFn: () => runAccountRuntimeNetworkAction(',
      ),
    );
    expect(retrierBlock, contains('action: () => retryFailedGroupMessages('));
    expect(
      retrierBlock,
      contains(
        'retryFailedGroupInboxStoresFn: () => runAccountRuntimeNetworkAction(',
      ),
    );
    expect(
      retrierBlock,
      contains('action: () => retryFailedGroupInboxStores('),
    );
  });

  test(
    'application root binds retrier overlap to resume and group recovery',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final applicationRootSource = await File(
        'lib/app/application_root.dart',
      ).readAsString();
      expect(
        applicationRootSource,
        contains(
          'widget.pendingMessageRetrier.setExternalRecoveryInProgressProvider(\n      () => _isResuming || isGroupRecoveryInProgress(),\n    );',
        ),
        reason:
            'the retrier overlap guard must also observe the group recovery '
            'gate so the startup fire-and-forget recovery pass suppresses '
            'retrier sweeps, not just the _isResuming app-resume path',
      );
    },
  );
}
