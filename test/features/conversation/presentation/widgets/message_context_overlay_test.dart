import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  Widget buildTestWidget({
    Rect anchorRect = const Rect.fromLTWH(40, 240, 280, 80),
    Size size = const Size(400, 800),
    EdgeInsets viewPadding = EdgeInsets.zero,
    Locale locale = const Locale('en'),
    Widget? selectedMessage,
    bool showEditAction = false,
    bool showCopyAction = true,
    bool showDeleteAction = false,
    VoidCallback? onDismiss,
    void Function(String emoji)? onReactionSelected,
    VoidCallback? onPlusTap,
    VoidCallback? onReplyTap,
    VoidCallback? onEditTap,
    VoidCallback? onCopyTap,
    VoidCallback? onDeleteTap,
    ThemeData? theme,
  }) {
    return MaterialApp(
      locale: locale,
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size, viewPadding: viewPadding),
        child: Scaffold(
          body: MessageContextOverlay(
            anchorRect: anchorRect,
            selectedMessage: selectedMessage,
            showEditAction: showEditAction,
            showCopyAction: showCopyAction,
            showDeleteAction: showDeleteAction,
            onDismiss: onDismiss ?? () {},
            onReactionSelected: onReactionSelected ?? (_) {},
            onPlusTap: onPlusTap ?? () {},
            onReplyTap: onReplyTap ?? () {},
            onEditTap: onEditTap,
            onCopyTap: onCopyTap,
            onDeleteTap: onDeleteTap,
          ),
        ),
      ),
    );
  }

  Widget buildSelectedMessage(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.08),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(text),
    );
  }

  group('MessageContextOverlay', () {
    testWidgets(
      'renders reaction bar plus reply and copy actions when copy is enabled',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(onCopyTap: () {}));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(
          find.byKey(MessageContextOverlay.reactionBarKey),
          findsOneWidget,
        );
        expect(
          find.byKey(MessageContextOverlay.replyActionKey),
          findsOneWidget,
        );
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
        expect(find.text('👍'), findsOneWidget);
        expect(find.text('Reply'), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);
      },
    );

    testWidgets(
      'renders the selected message between the reaction bar and menu',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            selectedMessage: buildSelectedMessage('Selected message'),
            onCopyTap: () {},
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(MessageContextOverlay.selectedMessageKey),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(MessageContextOverlay.selectedMessageKey),
            matching: find.text('Selected message'),
          ),
          findsOneWidget,
        );

        final reactionRect = tester.getRect(
          find.byKey(MessageContextOverlay.reactionBarKey),
        );
        final selectedRect = tester.getRect(
          find.byKey(MessageContextOverlay.selectedMessageKey),
        );
        final menuRect = tester.getRect(
          find.byKey(MessageContextOverlay.menuKey),
        );

        expect(reactionRect.bottom, lessThanOrEqualTo(selectedRect.top));
        expect(selectedRect.bottom, lessThanOrEqualTo(menuRect.top));
      },
    );

    testWidgets('clamps the selected message stack near the top edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          anchorRect: const Rect.fromLTWH(40, 12, 280, 80),
          viewPadding: const EdgeInsets.only(top: 20),
          selectedMessage: buildSelectedMessage('Top edge'),
          onCopyTap: () {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      final reactionRect = tester.getRect(
        find.byKey(MessageContextOverlay.reactionBarKey),
      );
      final selectedRect = tester.getRect(
        find.byKey(MessageContextOverlay.selectedMessageKey),
      );
      final menuRect = tester.getRect(
        find.byKey(MessageContextOverlay.menuKey),
      );

      expect(reactionRect.top, greaterThanOrEqualTo(28));
      expect(selectedRect.top, greaterThanOrEqualTo(100));
      expect(reactionRect.bottom, lessThanOrEqualTo(selectedRect.top));
      expect(selectedRect.bottom, lessThanOrEqualTo(menuRect.top));
    });

    testWidgets('clamps the selected message stack near the bottom edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          anchorRect: const Rect.fromLTWH(40, 720, 280, 80),
          viewPadding: const EdgeInsets.only(bottom: 20),
          selectedMessage: buildSelectedMessage('Bottom edge'),
          onCopyTap: () {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      final selectedRect = tester.getRect(
        find.byKey(MessageContextOverlay.selectedMessageKey),
      );
      final menuRect = tester.getRect(
        find.byKey(MessageContextOverlay.menuKey),
      );

      expect(selectedRect.bottom, lessThanOrEqualTo(menuRect.top));
      expect(menuRect.bottom, lessThanOrEqualTo(772));
    });

    testWidgets('renders edit action when enabled', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(showEditAction: true, onEditTap: () {}),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.editActionKey), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('renders delete action as the danger action when enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(showDeleteAction: true, onDeleteTap: () {}),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.deleteActionKey), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets(
      'renders reply, edit, copy, then delete in stable keyed order when all actions are enabled',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            showEditAction: true,
            showDeleteAction: true,
            onEditTap: () {},
            onCopyTap: () {},
            onDeleteTap: () {},
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));

        final replyFinder = find.byKey(MessageContextOverlay.replyActionKey);
        final editFinder = find.byKey(MessageContextOverlay.editActionKey);
        final copyFinder = find.byKey(MessageContextOverlay.copyActionKey);
        final deleteFinder = find.byKey(MessageContextOverlay.deleteActionKey);

        expect(replyFinder, findsOneWidget);
        expect(editFinder, findsOneWidget);
        expect(copyFinder, findsOneWidget);
        expect(deleteFinder, findsOneWidget);

        final replyTop = tester.getTopLeft(replyFinder).dy;
        final editTop = tester.getTopLeft(editFinder).dy;
        final copyTop = tester.getTopLeft(copyFinder).dy;
        final deleteTop = tester.getTopLeft(deleteFinder).dy;

        expect(replyTop, lessThan(editTop));
        expect(editTop, lessThan(copyTop));
        expect(copyTop, lessThan(deleteTop));
      },
    );

    testWidgets('hides copy action when message text is unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(showCopyAction: false));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.copyActionKey), findsNothing);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('fires onEditTap when the edit action is pressed', (
      tester,
    ) async {
      var edited = false;
      await tester.pumpWidget(
        buildTestWidget(showEditAction: true, onEditTap: () => edited = true),
      );
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
      await tester.pump();

      expect(edited, isTrue);
    });

    testWidgets('fires onDeleteTap when the delete action is pressed', (
      tester,
    ) async {
      var deleted = false;
      await tester.pumpWidget(
        buildTestWidget(
          showDeleteAction: true,
          onDeleteTap: () => deleted = true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
      await tester.pump();

      expect(deleted, isTrue);
    });

    testWidgets('double tapping copy only invokes the callback once', (
      tester,
    ) async {
      var copyCount = 0;
      await tester.pumpWidget(buildTestWidget(onCopyTap: () => copyCount++));
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.byKey(MessageContextOverlay.copyActionKey));
      await tester.pump();
      await tester.tap(find.byKey(MessageContextOverlay.copyActionKey));
      await tester.pump();

      expect(copyCount, 1);
    });

    testWidgets('double tapping a preset reaction only emits once', (
      tester,
    ) async {
      var reactionCount = 0;
      String? selectedEmoji;
      await tester.pumpWidget(
        buildTestWidget(
          onReactionSelected: (emoji) {
            reactionCount++;
            selectedEmoji = emoji;
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.text('👍'));
      await tester.pump();
      await tester.tap(find.text('👍'));
      await tester.pump();

      expect(reactionCount, 1);
      expect(selectedEmoji, '👍');
    });

    testWidgets('dismisses when the blurred backdrop is tapped', (
      tester,
    ) async {
      var dismissed = false;
      await tester.pumpWidget(
        buildTestWidget(onDismiss: () => dismissed = true),
      );
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.byKey(MessageContextOverlay.backdropKey));
      await tester.pump();

      expect(dismissed, isTrue);
    });

    testWidgets('localizes the overlay in Arabic RTL without layout exceptions', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          locale: const Locale('ar'),
          size: const Size(320, 360),
          viewPadding: const EdgeInsets.only(top: 24, bottom: 16),
          anchorRect: const Rect.fromLTWH(24, 268, 272, 92),
          selectedMessage: buildSelectedMessage(
            'هذا نص عربي طويل جدا مع رموز تعبيرية 😄 وسطر إضافي للتأكد من بقاء المعاينة داخل حدود الشاشة.',
          ),
          showEditAction: true,
          showDeleteAction: true,
          onEditTap: () {},
          onCopyTap: () {},
          onDeleteTap: () {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('رد'), findsOneWidget);
      expect(find.text('تعديل'), findsOneWidget);
      expect(find.text('نسخ'), findsOneWidget);
      expect(find.text('حذف'), findsOneWidget);

      final directionality = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.text('رد'),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(directionality.textDirection, TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses readable light-background roles for overlay actions', (
      tester,
    ) async {
      const colors = BackgroundReadableColors.representativeLight;
      await tester.pumpWidget(
        buildTestWidget(
          showDeleteAction: true,
          onCopyTap: () {},
          onDeleteTap: () {},
          theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[colors]),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      final menuBackground = Color.alphaBlend(
        colors.glassSurface,
        colors.surfaceBase,
      );
      final replyText = tester.widget<Text>(find.text('Reply'));
      final copyText = tester.widget<Text>(find.text('Copy'));
      final deleteText = tester.widget<Text>(find.text('Delete'));

      expectTextContrast(replyText.style!.color!, menuBackground);
      expectTextContrast(copyText.style!.color!, menuBackground);
      expectTextContrast(deleteText.style!.color!, menuBackground);
    });
  });
}
