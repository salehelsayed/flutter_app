import 'dart:io';

import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/features/groups/application/group_media_deletion_journal_reconciler.dart';
import 'package:flutter_app/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';

import '../secure_storage/fake_secure_key_store.dart';

// 235 (TC-235-10): production wiring proof. A directly instantiated
// reconciler is NOT production wiring — these tests anchor the real bootstrap
// and application-root call sites (cold start after DB/repo construction, resume before the
// network gate, real coordinator injection) plus the reconciler's own
// per-invocation error isolation.

void main() {
  test(
    'GMA-10 cold start and resume invoke local cleanup with error isolation',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);
      final productionSource = await File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsString();
      final applicationRootSource = await File(
        'lib/app/application_root.dart',
      ).readAsString();

      // ---- Cold start: the unawaited bounded reconcile runs after runApp
      // (DB + repositories are constructed) with an isolating catchError.
      final coldStart = productionSource.indexOf(
        'groupMediaDeletionReconciler.runBounded().catchError(',
      );
      expect(
        coldStart,
        isNonNegative,
        reason: 'cold start must run one bounded reconciliation pass',
      );
      final runAppMark = productionSource.indexOf(
        "StartupTiming.instance.mark('run_app_called')",
      );
      expect(runAppMark, isNonNegative);
      expect(
        coldStart,
        greaterThan(runAppMark),
        reason: 'the cold-start pass is fired after runApp, unawaited',
      );
      final coldStartBlock = productionSource.substring(
        coldStart,
        coldStart + 600,
      );
      expect(
        coldStartBlock,
        contains('GROUP_MEDIA_DELETION_STARTUP_RECONCILE_ERROR'),
        reason: 'startup reconcile errors are isolated, never rethrown',
      );

      // ---- The real reconciler is constructed over the identity DB helpers
      // and the real secure key store.
      final reconcilerCtor = productionSource.indexOf(
        'final groupMediaDeletionReconciler = GroupMediaDeletionJournalReconciler(',
      );
      expect(reconcilerCtor, isNonNegative);
      final reconcilerBlock = productionSource.substring(
        reconcilerCtor,
        productionSource.indexOf(
          'final deleteGroupMediaForMeUseCase = DeleteGroupMediaForMeUseCase(',
          reconcilerCtor,
        ),
      );
      expect(reconcilerBlock, contains('dbLoadGroupMediaDeletionJournalPage('));
      expect(
        reconcilerBlock,
        contains('dbFinalizeGroupMediaDeletionJournalEntry('),
      );
      expect(reconcilerBlock, contains('secureKeyStore: secureKeyStore'));

      // ---- The real coordinator (prepare + cleanup) is injected: as the
      // process-wide default AND into MyApp for the notification route.
      expect(
        productionSource,
        contains(
          'defaultGroupMediaDeleteForMeCoordinator = deleteGroupMediaForMeUseCase;',
        ),
        reason: 'every group-conversation entry path gets the coordinator',
      );
      expect(
        productionSource,
        contains(
          'groupMediaDeleteForMeCoordinator: deleteGroupMediaForMeUseCase,',
        ),
      );
      expect(
        applicationRootSource,
        contains(
          'mediaDeleteForMeCoordinator:\n                  widget.groupMediaDeleteForMeCoordinator,',
        ),
        reason: 'the notification route passes the real coordinator',
      );

      // ---- Resume: _onResumed passes the cleanup closure into
      // handleAppResumed (ordering vs the gate is proven behaviorally in
      // handle_app_resumed_group_media_cleanup_test.dart).
      final resumeCall = applicationRootSource.indexOf(
        'await handleAppResumed(',
      );
      expect(resumeCall, isNonNegative);
      final resumeBlock = applicationRootSource.substring(
        resumeCall,
        resumeCall + 1200,
      );
      expect(
        resumeBlock,
        contains(
          'groupMediaDeletionCleanupFn: widget.groupMediaDeletionCleanup',
        ),
      );

      // ---- Error isolation inside one pass: a failing item is retained
      // without aborting the run or its siblings.
      final reconciler = GroupMediaDeletionJournalReconciler(
        loadJournalPage:
            ({
              required int limit,
              String? afterCreatedAt,
              String? afterAttachmentId,
            }) async => afterCreatedAt == null
            ? [
                GroupMediaDeletionJournalEntry(
                  attachmentId: 'att-throws',
                  operationId: 'op-1',
                  messageId: 'msg-1',
                  groupId: 'group-1',
                  operationIntent: kGroupMediaDeletionIntentDeleteForMe,
                  normalizedMime: 'image/jpeg',
                  canonicalRelativePath: null,
                  createdAt: '2026-07-10T00:00:00.000Z',
                ),
                GroupMediaDeletionJournalEntry(
                  attachmentId: 'att-zz-ok',
                  operationId: 'op-1',
                  messageId: 'msg-1',
                  groupId: 'group-1',
                  operationIntent: kGroupMediaDeletionIntentDeleteForMe,
                  normalizedMime: 'image/jpeg',
                  canonicalRelativePath: null,
                  createdAt: '2026-07-10T00:00:00.000Z',
                ),
              ]
            : <GroupMediaDeletionJournalEntry>[],
        loadAttachmentRow: (attachmentId) async => null,
        loadLocalDeletionGroupId: (messageId) async => 'group-1',
        parentExists:
            ({required String messageId, required String groupId}) async =>
                false,
        finalizeEntry:
            ({required String attachmentId, required String messageId}) async =>
                true,
        resolveStoredPath: (relativePath) async => relativePath,
        secureKeyStore: _SelectivelyThrowingKeyStore(),
        lifecycleLock: MediaAttachmentLifecycleLock(),
      );
      final stats = await reconciler.runBounded(pageSize: 2);
      expect(stats.retained, 1, reason: 'the throwing item is retained');
      expect(stats.completed, 1, reason: 'its sibling still completes');
    },
  );
}

class _SelectivelyThrowingKeyStore extends FakeSecureKeyStore {
  @override
  Future<void> delete(String key) async {
    if (key.contains('att-throws')) {
      throw StateError('injected per-item failure');
    }
    await super.delete(key);
  }
}
