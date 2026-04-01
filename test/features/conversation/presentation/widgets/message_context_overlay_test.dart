import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget({
    Rect anchorRect = const Rect.fromLTWH(40, 240, 280, 80),
    Size size = const Size(400, 800),
    EdgeInsets viewPadding = EdgeInsets.zero,
    Widget? selectedMessage,
    bool showEditAction = false,
    bool showCopyAction = true,
    bool showDeleteAction = false,
    VoidCallback? onDismiss,
    VoidCallback? onReplyTap,
    VoidCallback? onEditTap,
    VoidCallback? onCopyTap,
    VoidCallback? onDeleteTap,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
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
            onReactionSelected: (_) {},
            onPlusTap: () {},
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
  });
}
