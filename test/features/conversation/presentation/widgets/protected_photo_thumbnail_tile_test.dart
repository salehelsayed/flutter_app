import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:flutter_app/features/conversation/presentation/widgets/protected_photo_thumbnail_tile.dart';
import 'package:flutter_app/shared/widgets/media/ios_capture_protected_image.dart';

void main() {
  late Directory tempDir;
  late String imagePath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('protected_thumb_tile_');
    final file = File(p.join(tempDir.path, 'thumb.jpg'));
    file.writeAsBytesSync(img.encodeJpg(img.Image(width: 8, height: 8)));
    imagePath = file.path;
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> pumpTile(
    WidgetTester tester, {
    VoidCallback? onOpen,
    String semanticsLabel = 'Protected photo',
    String? semanticsValue,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ProtectedPhotoThumbnailTile(
                imagePath: imagePath,
                semanticsLabel: semanticsLabel,
                semanticsValue: semanticsValue,
                onOpen: onOpen ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<SemanticsNode> nodesWhere(
    WidgetTester tester,
    bool Function(SemanticsData data) predicate,
  ) {
    final matches = <SemanticsNode>[];
    bool visit(SemanticsNode node) {
      if (predicate(node.getSemanticsData())) {
        matches.add(node);
      }
      node.visitChildren(visit);
      return true;
    }

    visit(
      tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
    );
    return matches;
  }

  testWidgets(
    'ios thumbnail renders through the capture-protected view and android through image file',
    (tester) async {
      // Android: plain Image.file inside the FLAG_SECURE-protected window.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pumpTile(tester);
        final tile = find.byKey(ProtectedPhotoThumbnailTile.tileKey);
        expect(tile, findsOneWidget);
        final image = find.descendant(of: tile, matching: find.byType(Image));
        expect(image, findsOneWidget);
        var provider = tester.widget<Image>(image).image;
        if (provider is ResizeImage) provider = provider.imageProvider;
        expect(provider, isA<FileImage>());
        expect((provider as FileImage).file.path, imagePath);
        expect(
          find.descendant(
            of: tile,
            matching: find.byType(IosCaptureProtectedImage),
          ),
          findsNothing,
        );

        // iOS: the promoted capture-protected platform view, never a plain
        // Image widget.
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        await pumpTile(tester);
        final iosTile = find.byKey(ProtectedPhotoThumbnailTile.tileKey);
        expect(iosTile, findsOneWidget);
        expect(
          find.descendant(
            of: iosTile,
            matching: find.byType(IosCaptureProtectedImage),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: iosTile, matching: find.byType(Image)),
          findsNothing,
        );
        // Dispose while still overridden so the platform-view watchdog timer
        // is cancelled before the test ends.
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('badge and label share one semantics node exposing the only tap action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var opens = 0;
    await pumpTile(
      tester,
      onOpen: () => opens++,
      semanticsLabel: 'Protected photo',
      semanticsValue: 'You can reopen it once here after sending.',
    );

    final tile = find.byKey(ProtectedPhotoThumbnailTile.tileKey);
    expect(tile, findsOneWidget);
    expect(
      find.descendant(of: tile, matching: find.byIcon(Icons.lock_outline_rounded)),
      findsOneWidget,
    );

    // Button + label + value are co-located on ONE node…
    final labelled = nodesWhere(
      tester,
      (data) => data.label.contains('Protected photo'),
    );
    expect(labelled, hasLength(1),
        reason: 'the label and button action must be co-located on one node');
    final data = labelled.single.getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.value, 'You can reopen it once here after sending.');

    // …and that node exposes the tile's ONLY action: no other tappable or
    // button descendant exists anywhere in the tile.
    final tappable = nodesWhere(
      tester,
      (data) => data.hasAction(SemanticsAction.tap),
    );
    expect(tappable, hasLength(1),
        reason: 'a rogue in-tile action would add a second tappable node');
    final buttons = nodesWhere(
      tester,
      (data) => data.flagsCollection.isButton,
    );
    expect(buttons, hasLength(1));
    expect(
      find.descendant(of: tile, matching: find.byType(IconButton)),
      findsNothing,
    );

    await tester.tap(tile);
    expect(opens, 1);

    // Long-press must NOT be swallowed by the tile: no internal long-press
    // recognizer exists, so the gesture bubbles to the bubble's ancestors.
    final gestures = tester
        .widgetList<GestureDetector>(
          find.descendant(of: tile, matching: find.byType(GestureDetector)),
        )
        .toList();
    for (final gesture in gestures) {
      expect(gesture.onLongPress, isNull,
          reason: 'the tile must never swallow the ancestor long-press');
    }
    handle.dispose();
  });
}
