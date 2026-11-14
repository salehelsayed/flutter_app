import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/swipe_action_buttons.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget wrap(
    Widget child, {
    Locale locale = const Locale('en'),
    double? textScale,
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => textScale == null
        ? child!
        : MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
    home: Scaffold(body: child),
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('GERMAN-OVERFLOW unarchive action scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var unarchived = false;
      await tester.pumpWidget(
        wrap(
          Center(
            // Same finite slot as archived SwipeableFriendRow._actionWidth.
            child: SizedBox(
              width: 180,
              child: UnarchiveActionButton(onTap: () => unarchived = true),
            ),
          ),
          locale: const Locale('de'),
          textScale: scale,
        ),
      );
      await tester.pump();
      final label = find.text('Aus Archiv holen');
      expect(label, findsOneWidget);
      expect(tester.takeException(), isNull);
      final labelBounds = tester.getRect(label);
      final buttonBounds = tester.getRect(find.byType(UnarchiveActionButton));
      expect(labelBounds.width, greaterThan(0));
      expect(labelBounds.left, greaterThanOrEqualTo(buttonBounds.left));
      expect(labelBounds.right, lessThanOrEqualTo(buttonBounds.right));
      expect(labelBounds.top, greaterThanOrEqualTo(buttonBounds.top));
      expect(labelBounds.bottom, lessThanOrEqualTo(buttonBounds.bottom));
      final paragraph = tester.renderObject<RenderParagraph>(label);
      if (paragraph.didExceedMaxLines) {
        expect(paragraph.overflow, TextOverflow.ellipsis);
      }
      await tester.tap(label);
      expect(unarchived, isTrue);
    });
  }

  group('BlockActionButton', () {
    testWidgets('renders block icon and "Block" text', (tester) async {
      await tester.pumpWidget(wrap(BlockActionButton(onTap: () {})));
      expect(find.byIcon(Icons.block), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(BlockActionButton(onTap: () => tapped = true)),
      );
      await tester.tap(find.byType(BlockActionButton));
      expect(tapped, isTrue);
    });
  });

  group('UnblockActionButton', () {
    testWidgets('renders replay icon and "Unblock" text', (tester) async {
      await tester.pumpWidget(wrap(UnblockActionButton(onTap: () {})));
      expect(find.byIcon(Icons.replay), findsOneWidget);
      expect(find.text('Unblock'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(UnblockActionButton(onTap: () => tapped = true)),
      );
      await tester.tap(find.byType(UnblockActionButton));
      expect(tapped, isTrue);
    });
  });

  group('DeleteActionButton', () {
    testWidgets('renders delete icon and "Delete" text', (tester) async {
      await tester.pumpWidget(wrap(DeleteActionButton(onTap: () {})));
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(DeleteActionButton(onTap: () => tapped = true)),
      );
      await tester.tap(find.byType(DeleteActionButton));
      expect(tapped, isTrue);
    });
  });

  group('ArchiveActionButton', () {
    testWidgets('renders archive icon and "Archive" text', (tester) async {
      await tester.pumpWidget(wrap(ArchiveActionButton(onTap: () {})));
      expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(ArchiveActionButton(onTap: () => tapped = true)),
      );
      await tester.tap(find.byType(ArchiveActionButton));
      expect(tapped, isTrue);
    });
  });

  group('UnarchiveActionButton', () {
    testWidgets('renders unarchive icon and "Unarchive" text', (tester) async {
      await tester.pumpWidget(wrap(UnarchiveActionButton(onTap: () {})));
      expect(find.byIcon(Icons.unarchive_outlined), findsOneWidget);
      expect(find.text('Unarchive'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(UnarchiveActionButton(onTap: () => tapped = true)),
      );
      await tester.tap(find.byType(UnarchiveActionButton));
      expect(tapped, isTrue);
    });
  });
}
