import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

void main() {
  test(
    'GPL-09B main wires atomic current-ordinary group bookmark qualification',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();
      final start = mainSource.indexOf(
        'final mediaAttachmentRepository = MediaAttachmentRepositoryImpl(',
      );
      expect(start, isNonNegative);
      final end = mainSource.indexOf(');', start);
      expect(end, greaterThan(start));

      final repositoryBlock = mainSource.substring(start, end);
      expect(repositoryBlock, contains('dbSetGroupMediaBookmarkedIfOrdinary:'));
      expect(
        repositoryBlock,
        contains('dbSetGroupMediaBookmarkedIfOrdinary('),
        reason:
            'production group bookmark mutation must use the exact atomic parent predicate',
      );
    },
  );

  test(
    'GPL-03B main supplies current group and identity authority to failed inbox retries',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();
      final backgroundStart = mainSource.indexOf(
        'retryFailedGroupInboxStoresFn: () => runAccountRuntimeNetworkAction(',
      );
      final backgroundEnd = mainSource.indexOf(
        'clearGroupRetryBackoffFn:',
        backgroundStart,
      );
      expect(backgroundStart, isNonNegative);
      expect(backgroundEnd, greaterThan(backgroundStart));
      final backgroundBlock = mainSource.substring(
        backgroundStart,
        backgroundEnd,
      );
      expect(backgroundBlock, contains('groupRepo: groupRepository'));
      expect(backgroundBlock, contains('identityRepo: repository'));

      final resumeStart = mainSource.lastIndexOf(
        'retryFailedGroupInboxStoresFn: () => retryFailedGroupInboxStores(',
      );
      final resumeEnd = mainSource.indexOf('      );', resumeStart);
      expect(resumeStart, isNonNegative);
      expect(resumeEnd, greaterThan(resumeStart));
      final resumeBlock = mainSource.substring(resumeStart, resumeEnd);
      expect(resumeBlock, contains('groupRepo: widget.groupRepository'));
      expect(resumeBlock, contains('identityRepo: widget.repository'));
    },
  );

  test(
    'main.dart passes mediaFileManager into direct retryIncompleteUploads on resume',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();
      final start = mainSource.indexOf(
        'retryIncompleteUploadsFn: () => runAccountRuntimeNetworkAction(',
      );

      expect(start, isNonNegative);

      final end = mainSource.indexOf(
        'final pendingPostMediaUploadRetrier = PendingPostMediaUploadRetrier(',
        start,
      );
      expect(end, greaterThan(start));

      final retryBlock = mainSource.substring(start, end);
      expect(
        retryBlock,
        contains('mediaFileManager: mediaFileManager'),
        reason:
            'resume-time 1:1 upload retry must resolve persisted pending_uploads paths',
      );
    },
  );

  test(
    'main.dart passes widget mediaFileManager into retryIncompleteUploads on app resume',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();
      final start = mainSource.lastIndexOf(
        'retryIncompleteUploadsFn: () => retryIncompleteUploads(',
      );

      expect(start, isNonNegative);

      final end = mainSource.indexOf('retryFailedMessagesFn:', start);
      expect(end, greaterThan(start));

      final retryBlock = mainSource.substring(start, end);
      expect(
        retryBlock,
        contains('mediaFileManager: widget.mediaFileManager'),
        reason:
            'app-resume 1:1 upload retry must resolve persisted pending_uploads paths',
      );
    },
  );

  test(
    'TC-17 main wires mediaFileManager through background and app-resume failed-message retry paths',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();
      final retrierStart = mainSource.indexOf(
        'final pendingMessageRetrier = PendingMessageRetrier(',
      );
      final retrierEnd = mainSource.indexOf(
        'rejoinGroupTopicsWithRecoveryAckEligibilityFn:',
        retrierStart,
      );
      expect(retrierStart, isNonNegative);
      expect(retrierEnd, greaterThan(retrierStart));
      expect(
        mainSource.substring(retrierStart, retrierEnd),
        contains('mediaFileManager: mediaFileManager'),
        reason:
            'the default PendingMessageRetrier failed-message path must receive the resolver',
      );

      final resumeStart = mainSource.lastIndexOf(
        'retryFailedMessagesFn: () => retryFailedMessages(',
      );
      final resumeEnd = mainSource.indexOf(
        'retryUnackedMessagesFn:',
        resumeStart,
      );
      expect(resumeStart, isNonNegative);
      expect(resumeEnd, greaterThan(resumeStart));
      expect(
        mainSource.substring(resumeStart, resumeEnd),
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

      final mainSource = await File('lib/main.dart').readAsString();
      final resumeStart = mainSource.lastIndexOf(
        'retryUnackedMessagesFn: () => retryUnackedMessages(',
      );
      final resumeEnd = mainSource.indexOf(
        'verifyInboxCustodyFn:',
        resumeStart,
      );
      expect(resumeStart, isNonNegative);
      expect(resumeEnd, greaterThan(resumeStart));
      expect(
        mainSource.substring(resumeStart, resumeEnd),
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
    'main.dart passes mediaFileManager into retryIncompleteGroupUploads on resume',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();
      final start = mainSource.indexOf(
        'retryIncompleteGroupUploadsFn: () => retryIncompleteGroupUploads(',
      );

      expect(start, isNonNegative);

      final end = mainSource.indexOf('retryFailedGroupMessagesFn:', start);
      expect(end, greaterThan(start));

      final retryBlock = mainSource.substring(start, end);
      expect(
        retryBlock,
        contains('mediaFileManager: widget.mediaFileManager'),
        reason:
            'resume-time group upload retry must resolve persisted pending_uploads paths',
      );
    },
  );

  test(
    'main.dart passes mediaAttachmentRepository into retryFailedGroupMessages on resume',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();
      final start = mainSource.indexOf(
        'retryFailedGroupMessagesFn: () => retryFailedGroupMessages(',
      );

      expect(start, isNonNegative);

      final end = mainSource.indexOf('retryIncompleteUploadsFn:', start);
      expect(end, greaterThan(start));

      final retryBlock = mainSource.substring(start, end);
      expect(
        retryBlock,
        contains('mediaAttachmentRepo: widget.mediaAttachmentRepository'),
        reason:
            'resume-time failed group retry must reload persisted media attachments',
      );
    },
  );

  test('main.dart wires group retry callbacks into PendingMessageRetrier', () async {
    expect(app.MyApp.navigatorKey, isNotNull);

    final mainSource = await File('lib/main.dart').readAsString();
    final start = mainSource.indexOf(
      'final pendingMessageRetrier = PendingMessageRetrier(',
    );

    expect(start, isNonNegative);

    final end = mainSource.indexOf('recoverStuckSendingMessagesFn:', start);
    expect(end, greaterThan(start));

    final retrierBlock = mainSource.substring(start, end);
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
    'main.dart binds the pending retrier overlap guard to _isResuming and the group recovery gate',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();
      expect(
        mainSource,
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
