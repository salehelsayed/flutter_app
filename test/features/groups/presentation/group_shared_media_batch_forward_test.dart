import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/application/group_media_batch_forward.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/features/share/application/group_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared_media_test_fakes.dart';

void main() {
  testWidgets(
    'GBF-01 batch forward visibility follows approved selection and cap matrix',
    (tester) async {
      final repository = StrictGroupMediaLibraryRepository(
        expectedGroupId: 'group-a',
        entries: [groupMediaEntry('a'), groupMediaEntry('b')],
      );
      final singleCalls = <GroupSharedMediaIdentity>[];
      final batchCalls = <List<GroupSharedMediaIdentity>>[];
      await tester.pumpWidget(
        _app(
          repository,
          dispatchForward: (identity) async {
            singleCalls.add(identity);
            return true;
          },
          launchBatchForward: (identities) async {
            batchCalls.add(List.unmodifiable(identities));
            return const GroupMediaBatchForwardLibraryLaunchResult.cancelled();
          },
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
      );
      expect(
        find.byKey(const ValueKey('group-shared-media-action-batch-forward')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('group-shared-media-action-forward')),
      );
      await tester.pump();
      expect(singleCalls, hasLength(1));
      expect(batchCalls, isEmpty);

      await tester.longPress(
        find.byKey(const ValueKey('group-shared-media-tile-b')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('group-shared-media-action-forward')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('group-shared-media-action-batch-forward')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('group-shared-media-action-batch-forward')),
      );
      await tester.pump();
      expect(batchCalls, hasLength(1));
      expect(
        batchCalls.single.map((identity) => identity.attachmentId).toSet(),
        {'a', 'b'},
      );
      expect(singleCalls, hasLength(1));
    },
  );

  testWidgets('GBF-10 batch forwarding remains opt-in and discussion scoped', (
    tester,
  ) async {
    final repository = StrictGroupMediaLibraryRepository(
      expectedGroupId: 'group-a',
      entries: [groupMediaEntry('a'), groupMediaEntry('b')],
    );
    await tester.pumpWidget(_app(repository));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.longPress(
      find.byKey(const ValueKey('group-shared-media-tile-a')),
    );
    await tester.longPress(
      find.byKey(const ValueKey('group-shared-media-tile-b')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('group-shared-media-action-batch-forward')),
      findsNothing,
      reason: 'no launcher means Plan-237/241 surfaces remain unchanged',
    );
  });

  testWidgets('GBF-03 size denial stays typed and never opens delivery', (
    tester,
  ) async {
    final repository = StrictGroupMediaLibraryRepository(
      expectedGroupId: 'group-a',
      entries: [groupMediaEntry('a'), groupMediaEntry('b')],
    );
    var launchCalls = 0;
    await tester.pumpWidget(
      _app(
        repository,
        dispatchForward: (_) async => true,
        launchBatchForward: (_) async {
          launchCalls++;
          return const GroupMediaBatchForwardLibraryLaunchResult.denied(
            GroupMediaBatchForwardDenial.sizeLimitExceeded,
          );
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.longPress(
      find.byKey(const ValueKey('group-shared-media-tile-a')),
    );
    await tester.longPress(
      find.byKey(const ValueKey('group-shared-media-tile-b')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('group-shared-media-action-batch-forward')),
    );
    await tester.pump();

    expect(launchCalls, 1);
    expect(
      find.byKey(const ValueKey('group-batch-forward-size-limit')),
      findsOneWidget,
    );
    expect(
      find.text('Attachments too large — remove some to send.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('group-batch-forward-picker')),
      findsNothing,
      reason: 'preflight denial cannot open target or delivery work',
    );
  });
}

Widget _app(
  StrictGroupMediaLibraryRepository repository, {
  GroupSharedMediaForwardDispatch? dispatchForward,
  GroupMediaBatchForwardLibraryLaunch? launchBatchForward,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: GroupSharedMediaLibraryScreen(
    groupId: 'group-a',
    libraryRepository: repository,
    stateRepository: repository,
    dispatchForward: dispatchForward,
    launchBatchForward: launchBatchForward,
    capabilitiesForEntry: (_) => const {
      GroupSharedMediaAction.bookmark,
      GroupSharedMediaAction.goToMessage,
      GroupSharedMediaAction.forward,
    },
  ),
);
