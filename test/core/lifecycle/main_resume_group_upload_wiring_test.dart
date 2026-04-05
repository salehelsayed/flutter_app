import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

void main() {
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
        contains('mediaFileManager: mediaFileManager'),
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
        contains('mediaAttachmentRepo: mediaAttachmentRepository'),
        reason:
            'resume-time failed group retry must reload persisted media attachments',
      );
    },
  );

  test(
    'main.dart wires group retry callbacks into PendingMessageRetrier',
    () async {
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
          'acknowledgeGroupRecoveryFn: () => callGroupAcknowledgeRecovery(bridge),',
        ),
      );
      expect(
        retrierBlock,
        contains('drainGroupOfflineInboxFn: () => drainGroupOfflineInbox('),
      );
      expect(
        retrierBlock,
        contains(
          'recoverStuckSendingGroupMessagesFn: () =>\n        recoverStuckSendingGroupMessages(',
        ),
      );
      expect(
        retrierBlock,
        contains(
          'retryIncompleteGroupUploadsFn: () => retryIncompleteGroupUploads(',
        ),
      );
      expect(
        retrierBlock,
        contains('retryFailedGroupMessagesFn: () => retryFailedGroupMessages('),
      );
      expect(
        retrierBlock,
        contains(
          'retryFailedGroupInboxStoresFn: () => retryFailedGroupInboxStores(',
        ),
      );
    },
  );

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
