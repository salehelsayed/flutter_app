import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_batch_actions.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/features/share/application/group_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared_media_test_fakes.dart';

void main() {
  testWidgets(
    'batch forward eligibility is bounded and preserves single item and library actions',
    (tester) async {
      final repository = StrictGroupMediaLibraryRepository(
        expectedGroupId: 'announcement-a',
        entries: [groupMediaEntry('a'), groupMediaEntry('b')],
      );
      final singles = <GroupSharedMediaIdentity>[];
      final batches = <List<GroupSharedMediaIdentity>>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupSharedMediaLibraryScreen(
            groupId: 'announcement-a',
            incomingOnly: true,
            libraryRepository: repository,
            stateRepository: repository,
            dispatchForward: (identity) async {
              singles.add(identity);
              return true;
            },
            launchBatchForward: (identities) async {
              batches.add(List.unmodifiable(identities));
              return const GroupMediaBatchForwardLibraryLaunchResult.cancelled();
            },
            dispatchEgress: (_, _) async => const GroupSharedMediaBatchResult(
              items: [],
              egressResult: null,
            ),
            dispatchDelete: (_) async =>
                const GroupSharedMediaBatchDeleteOutcome(
                  deletedMessageIds: {},
                  failedMessageIds: {},
                  deletedAttachmentIds: {},
                  failedAttachmentIds: {},
                ),
            capabilitiesForEntry: (_) => const {
              GroupSharedMediaAction.save,
              GroupSharedMediaAction.share,
              GroupSharedMediaAction.bookmark,
              GroupSharedMediaAction.delete,
              GroupSharedMediaAction.forward,
              GroupSharedMediaAction.goToMessage,
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.longPress(
        find.byKey(const ValueKey('group-shared-media-tile-a')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('group-shared-media-action-forward')),
        findsOneWidget,
        reason: 'one item remains the accepted Plan-240 route',
      );
      await tester.tap(
        find.byKey(const ValueKey('group-shared-media-action-forward')),
      );
      await tester.pump();
      expect(singles, hasLength(1));

      await tester.longPress(
        find.byKey(const ValueKey('group-shared-media-tile-b')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('group-shared-media-action-batch-forward')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('group-shared-media-action-save')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('group-shared-media-action-share')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('group-shared-media-action-bookmark')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('group-shared-media-action-delete')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('group-shared-media-action-batch-forward')),
      );
      await tester.pump();
      expect(batches, hasLength(1));
      expect(singles, hasLength(1));
    },
  );
}
