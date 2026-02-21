import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';

void main() {
  late Directory tempDir;
  late List<File> testFiles;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('strip_test_');
    testFiles = [];
    for (var i = 0; i < 3; i++) {
      final file = File('${tempDir.path}/image_$i.jpg');
      // Write a minimal valid JPEG header (2 bytes) so Image.file doesn't crash
      await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]);
      testFiles.add(file);
    }
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildTestWidget({
    required List<File> attachments,
    bool isUploading = false,
    bool isProcessing = false,
    double processingProgress = 0.0,
    ValueChanged<int>? onRemove,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: AttachmentPreviewStrip(
          attachments: attachments,
          isUploading: isUploading,
          isProcessing: isProcessing,
          processingProgress: processingProgress,
          onRemove: onRemove,
        ),
      ),
    );
  }

  group('AttachmentPreviewStrip', () {
    testWidgets('renders correct number of thumbnails', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: testFiles,
      ));
      await tester.pump();

      // Each thumbnail is a ClipRRect wrapping an Image.file
      expect(find.byType(Image), findsNWidgets(3));
    });

    testWidgets('shows remove buttons when not uploading', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: testFiles,
        onRemove: (_) {},
      ));
      await tester.pump();

      expect(find.byIcon(Icons.close), findsNWidgets(3));
    });

    testWidgets('hides remove buttons during upload', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: testFiles,
        isUploading: true,
        onRemove: (_) {},
      ));
      await tester.pump();

      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('shows upload overlay spinner during upload', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: testFiles,
        isUploading: true,
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNWidgets(3));
    });

    testWidgets('no spinner when not uploading', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: testFiles,
        isUploading: false,
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('onRemove fires with correct index', (tester) async {
      int? removedIndex;
      await tester.pumpWidget(buildTestWidget(
        attachments: testFiles,
        onRemove: (index) => removedIndex = index,
      ));
      await tester.pump();

      // Tap the first remove button
      final closeIcons = find.byIcon(Icons.close);
      await tester.tap(closeIcons.first);
      expect(removedIndex, 0);

      // Tap the last remove button
      await tester.tap(closeIcons.last);
      expect(removedIndex, 2);
    });

    testWidgets('renders nothing when empty list given', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: [],
      ));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('single attachment renders one thumbnail', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: [testFiles[0]],
        onRemove: (_) {},
      ));
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('no remove buttons when onRemove is null', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: testFiles,
        onRemove: null,
      ));
      await tester.pump();

      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('shows processing thumbnail when isProcessing is true',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: [],
        isProcessing: true,
        processingProgress: 0.5,
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('processing thumbnail displays correct percentage',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: [],
        isProcessing: true,
        processingProgress: 0.73,
      ));
      await tester.pump();

      expect(find.text('73%'), findsOneWidget);
    });

    testWidgets('processing thumbnail shows determinate CircularProgressIndicator',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: [],
        isProcessing: true,
        processingProgress: 0.42,
      ));
      await tester.pump();

      final cpi = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(cpi.value, 0.42);
    });

    testWidgets('does not show processing thumbnail when isProcessing is false',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: [],
        isProcessing: false,
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows processing tile alongside existing attachments',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        attachments: testFiles,
        isProcessing: true,
        processingProgress: 0.25,
      ));
      await tester.pump();

      // 3 image thumbnails + 1 processing tile
      expect(find.byType(Image), findsNWidgets(3));
      expect(find.text('25%'), findsOneWidget);
    });
  });
}
