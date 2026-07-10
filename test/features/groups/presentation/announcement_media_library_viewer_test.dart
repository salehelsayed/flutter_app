import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared_media_test_fakes.dart';

void main() {
  testWidgets(
    'AML-04 typed viewer crosses incoming parents while clear stays grid only',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = Directory.systemTemp.createTempSync('announcement-viewer-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final image = File('${temp.path}/one.png')..writeAsBytesSync(_tinyPng);
      final repository = StrictGroupMediaLibraryRepository(
        expectedGroupId: 'announcement-a',
        entries: [
          for (var i = 0; i < 51; i++)
            groupMediaEntry(
              'a$i',
              messageId: 'm$i',
              downloadStatus: 'done',
              localPath: image.path,
            ),
        ],
      );
      await tester.pumpWidget(_app(repository));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.drag(
        find.byKey(const ValueKey('group-shared-media-grid')),
        const Offset(0, -5000),
      );
      await tester.pump(const Duration(milliseconds: 500));
      tester
          .widget<GestureDetector>(
            find.byKey(const ValueKey('media-grid-cell-m49-a49')),
          )
          .onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final viewer = tester.widget<FullScreenTypedMediaViewer>(
        find.byType(FullScreenTypedMediaViewer),
      );
      expect(viewer.items, hasLength(51));
      expect(viewer.items[49].messageId, 'm49');
      expect(viewer.items[50].messageId, 'm50');
      expect(
        viewer.items.every(
          (item) =>
              !item.capabilities.allowed.contains(MediaViewerAction.reply),
        ),
        isTrue,
      );
      expect(repository.requests.every((r) => r.filter.incomingOnly), isTrue);
    },
  );
}

Widget _app(StrictGroupMediaLibraryRepository repository) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: GroupSharedMediaLibraryScreen(
    groupId: 'announcement-a',
    incomingOnly: true,
    libraryRepository: repository,
    stateRepository: repository,
  ),
);

const _tinyPng = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  8,
  215,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  5,
  0,
  1,
  255,
  137,
  153,
  61,
  29,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];
