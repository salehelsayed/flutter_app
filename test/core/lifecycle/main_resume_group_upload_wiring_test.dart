import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

void main() {
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
    'main.dart binds the pending retrier overlap guard to _isResuming',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();
      expect(
        mainSource,
        contains(
          'widget.pendingMessageRetrier.setExternalRecoveryInProgressProvider(\n      () => _isResuming,\n    );',
        ),
      );
    },
  );
}
