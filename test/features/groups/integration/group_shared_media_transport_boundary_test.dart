import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared_media_test_fakes.dart';

void main() {
  testWidgets(
    'GML-13 local library actions make zero transport or internal delivery calls',
    (tester) async {
      const productionPaths = [
        'lib/features/groups/application/group_shared_media_library_controller.dart',
        'lib/features/groups/application/group_shared_media_batch_actions.dart',
        'lib/features/groups/application/group_shared_media_navigation.dart',
        'lib/features/groups/presentation/screens/group_shared_media_library_screen.dart',
      ];
      for (final path in productionPaths) {
        final source = File(path).readAsStringSync();
        for (final forbidden in const [
          'core/bridge/',
          'P2PService',
          'publishGroup',
          'send_group_message_use_case',
          'ShareBatchDeliveryCoordinator',
          'share_batch_delivery_coordinator',
          'storeInInbox',
          'go-mknoon',
          'go-relay-server',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason: '$path: $forbidden',
          );
        }
      }

      final repository = StrictGroupMediaLibraryRepository(
        expectedGroupId: 'group-a',
        entries: [groupMediaEntry('a')],
      );
      final controller = GroupSharedMediaLibraryController(
        groupId: 'group-a',
        libraryRepository: repository,
        stateRepository: repository,
      );
      await controller.loadNextPage();
      expect(controller.toggleSelection('a'), isTrue);
      expect(await controller.setBookmarked('a', bookmarked: true), isTrue);
      expect(repository.bookmarkWrites, [('a', true)]);

      repository.replaceEntries([groupMediaEntry('a'), groupMediaEntry('b')]);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupSharedMediaLibraryScreen(
            groupId: 'group-a',
            libraryRepository: repository,
            stateRepository: repository,
            capabilitiesForEntry: (_) => const {
              GroupSharedMediaAction.bookmark,
              GroupSharedMediaAction.delete,
              GroupSharedMediaAction.goToMessage,
            },
            dispatchEgress: (_, destination) =>
                throw StateError('egress bypass'),
            dispatchDelete: (_) => throw StateError('delete bypass'),
            dispatchEviction: (_) => throw StateError('eviction bypass'),
            dispatchForward: (_) => throw StateError('forward bypass'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      for (final id in const ['a', 'b']) {
        await tester.longPress(
          find.byKey(ValueKey('group-shared-media-tile-$id')),
        );
        await tester.pump();
      }
      expect(
        find.byKey(const ValueKey('group-shared-media-action-forward')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('group-shared-media-action-save')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('group-shared-media-action-bookmark')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        repository.bookmarkWrites,
        containsAll([('a', true), ('b', true)]),
      );
    },
  );
}
