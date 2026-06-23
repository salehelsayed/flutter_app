import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  late Directory tempDir;
  late List<File> testFiles;
  late File gifFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('strip_test_');
    testFiles = [];
    for (var i = 0; i < 3; i++) {
      final file = File('${tempDir.path}/image_$i.jpg');
      // Write a minimal valid JPEG header (2 bytes) so Image.file doesn't crash
      await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]);
      testFiles.add(file);
    }
    gifFile = File('${tempDir.path}/funny.gif');
    await gifFile.writeAsBytes(const [
      0x47,
      0x49,
      0x46,
      0x38,
      0x39,
      0x61,
      0x01,
      0x00,
      0x01,
      0x00,
      0x80,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0xFF,
      0xFF,
      0xFF,
      0x21,
      0xF9,
      0x04,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x2C,
      0x00,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x00,
      0x02,
      0x02,
      0x44,
      0x01,
      0x00,
      0x3B,
    ]);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildTestWidget({
    required List<File> attachments,
    BackgroundReadableColors readableColors = BackgroundReadableColors.dark,
    bool isUploading = false,
    bool isProcessing = false,
    double processingProgress = 0.0,
    int processingCurrent = 0,
    int processingTotal = 0,
    Set<int> invalidIndices = const {},
    Map<int, String> invalidReasons = const {},
    bool hasTotalSizeOverflow = false,
    ValueChanged<int>? onRemove,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[readableColors]),
      home: Scaffold(
        body: AttachmentPreviewStrip(
          attachments: attachments,
          isUploading: isUploading,
          isProcessing: isProcessing,
          processingProgress: processingProgress,
          processingCurrent: processingCurrent,
          processingTotal: processingTotal,
          invalidIndices: invalidIndices,
          invalidReasons: invalidReasons,
          hasTotalSizeOverflow: hasTotalSizeOverflow,
          onRemove: onRemove,
        ),
      ),
    );
  }

  group('AttachmentPreviewStrip', () {
    testWidgets('renders correct number of thumbnails', (tester) async {
      await tester.pumpWidget(buildTestWidget(attachments: testFiles));
      await tester.pump();

      // Each thumbnail is a ClipRRect wrapping an Image.file
      expect(find.byType(Image), findsNWidgets(3));
    });

    testWidgets('shows remove buttons when not uploading', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(attachments: testFiles, onRemove: (_) {}),
      );
      await tester.pump();

      expect(find.byIcon(Icons.close), findsNWidgets(3));
    });

    testWidgets('hides remove buttons during upload', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          attachments: testFiles,
          isUploading: true,
          onRemove: (_) {},
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('shows upload overlay spinner during upload', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(attachments: testFiles, isUploading: true),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNWidgets(3));
    });

    testWidgets('no spinner when not uploading', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(attachments: testFiles, isUploading: false),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('onRemove fires with correct index', (tester) async {
      int? removedIndex;
      await tester.pumpWidget(
        buildTestWidget(
          attachments: testFiles,
          onRemove: (index) => removedIndex = index,
        ),
      );
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
      await tester.pumpWidget(buildTestWidget(attachments: []));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('single attachment renders one thumbnail', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(attachments: [testFiles[0]], onRemove: (_) {}),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('GIF thumbnail shows a GIF badge', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(attachments: [gifFile], onRemove: (_) {}),
      );
      await tester.pump();

      expect(find.text('GIF'), findsOneWidget);
    });

    testWidgets('JPEG thumbnail does not show a GIF badge', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(attachments: [testFiles.first], onRemove: (_) {}),
      );
      await tester.pump();

      expect(find.text('GIF'), findsNothing);
    });

    testWidgets('GIF badge is hidden during upload', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          attachments: [gifFile],
          isUploading: true,
          onRemove: (_) {},
        ),
      );
      await tester.pump();

      expect(find.text('GIF'), findsNothing);
    });

    testWidgets('no remove buttons when onRemove is null', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(attachments: testFiles, onRemove: null),
      );
      await tester.pump();

      expect(find.byIcon(Icons.close), findsNothing);
    });

    // 149 TC-01: a size-rejected attachment renders an inline red chip
    // (keyed red-bordered container + warning icon + short caption) AND keeps
    // its remove X, distinct from the uploading spinner state.
    testWidgets(
      'invalid attachment renders a red border, a warning icon, a short '
      'caption, and keeps its remove X',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            attachments: [testFiles.first],
            invalidIndices: const {0},
            invalidReasons: const {0: 'too_large'},
            onRemove: (_) {},
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        // Short chip caption (NOT the long snackbar sentence).
        expect(find.text('Too large'), findsOneWidget);
        // The remove X must NOT be suppressed by the invalid branch.
        expect(find.byIcon(Icons.close), findsOneWidget);
        // Distinct from the uploading state — no spinner.
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    // 149 TC-01b: a GIF-too-large rejection renders the GIF-specific caption.
    testWidgets('invalid GIF attachment renders the GIF-specific caption', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          attachments: [gifFile],
          invalidIndices: const {0},
          invalidReasons: const {0: 'gif_too_large'},
          onRemove: (_) {},
        ),
      );
      await tester.pump();

      expect(find.text('GIF too big'), findsOneWidget);
      expect(find.text('Too large'), findsNothing);
      expect(
        find.byKey(const ValueKey('attachment-invalid-0')),
        findsOneWidget,
      );
    });

    // 149 TC-02: a valid attachment shows no invalid styling. The compile-red
    // is shared with TC-01; the behavioral lock is the mutation (making the red
    // branch unconditional re-reds this).
    testWidgets('valid attachment shows no invalid styling', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          attachments: testFiles,
          invalidIndices: const {},
          invalidReasons: const {},
          onRemove: (_) {},
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('attachment-invalid-0')), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byIcon(Icons.close), findsNWidgets(3));
    });

    // 149 TC-01/INV-2: only the marked index is styled invalid in a mixed strip.
    testWidgets('only the marked index is styled invalid in a mixed strip', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          attachments: testFiles,
          invalidIndices: const {1},
          invalidReasons: const {1: 'too_large'},
          onRemove: (_) {},
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('attachment-invalid-0')), findsNothing);
      expect(
        find.byKey(const ValueKey('attachment-invalid-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('attachment-invalid-2')), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      // X kept on every chip including the invalid one.
      expect(find.byIcon(Icons.close), findsNWidgets(3));
    });

    // 149 follow-up: whole-message total overflow (no owning index) renders a
    // keyed strip-level note above the thumbnails — NOT a per-chip border.
    testWidgets(
      'total-size overflow renders a keyed strip-level note above the '
      'thumbnails (no per-chip border)',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            attachments: testFiles,
            hasTotalSizeOverflow: true,
            onRemove: (_) {},
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('attachment-total-overflow')),
          findsOneWidget,
        );
        expect(
          find.text('Attachments too large — remove some to send.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        // Thumbnails + their remove X are still rendered alongside the note.
        expect(find.byType(Image), findsNWidgets(3));
        expect(find.byIcon(Icons.close), findsNWidgets(3));
        // No per-attachment border — the overflow owns no single index.
        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsNothing,
        );
      },
    );

    // 149 follow-up: the note is absent when not overflowing (default false).
    testWidgets('no strip-level overflow note when not overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(attachments: testFiles, onRemove: (_) {}),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('attachment-total-overflow')),
        findsNothing,
      );
      expect(
        find.text('Attachments too large — remove some to send.'),
        findsNothing,
      );
    });

    // 149 follow-up: the strip-level overflow note coexists with a per-index
    // invalid chip (both states can be live at once).
    testWidgets(
      'total-size overflow note coexists with a per-index invalid chip',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            attachments: testFiles,
            invalidIndices: const {1},
            invalidReasons: const {1: 'too_large'},
            hasTotalSizeOverflow: true,
            onRemove: (_) {},
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('attachment-total-overflow')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('attachment-invalid-1')),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows processing thumbnail when isProcessing is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          attachments: [],
          isProcessing: true,
          processingProgress: 0.5,
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Processing'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets(
      'processing thumbnail uses representative light readable text',
      (tester) async {
        const colors = BackgroundReadableColors.representativeLight;

        await tester.pumpWidget(
          buildTestWidget(
            attachments: [],
            readableColors: colors,
            isProcessing: true,
            processingProgress: 0.5,
          ),
        );
        await tester.pump();

        final label = tester.widget<Text>(find.text('Processing'));
        expectTextContrast(label.style!.color!, colors.surfaceSubtle);
        final percent = tester.widget<Text>(find.text('50%'));
        expectTextContrast(percent.style!.color!, colors.surfaceSubtle);
      },
    );

    testWidgets(
      'shows batch processing label when multiple videos are active',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            attachments: [],
            isProcessing: true,
            processingProgress: 0.5,
            processingCurrent: 2,
            processingTotal: 4,
          ),
        );
        await tester.pump();

        expect(find.text('Processing (2/4)'), findsOneWidget);
        expect(find.text('50%'), findsOneWidget);
      },
    );

    testWidgets('processing thumbnail displays correct percentage', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          attachments: [],
          isProcessing: true,
          processingProgress: 0.73,
        ),
      );
      await tester.pump();

      expect(find.text('73%'), findsOneWidget);
    });

    testWidgets(
      'processing thumbnail shows determinate CircularProgressIndicator',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            attachments: [],
            isProcessing: true,
            processingProgress: 0.42,
          ),
        );
        await tester.pump();

        final cpi = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        expect(cpi.value, 0.42);
      },
    );

    testWidgets(
      'does not show processing thumbnail when isProcessing is false',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(attachments: [], isProcessing: false),
        );
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('shows processing tile alongside existing attachments', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          attachments: testFiles,
          isProcessing: true,
          processingProgress: 0.25,
          processingCurrent: 2,
          processingTotal: 3,
        ),
      );
      await tester.pump();

      // 3 image thumbnails + 1 processing tile
      expect(find.byType(Image), findsNWidgets(3));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Processing (2/3)'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
    });
  });
}
