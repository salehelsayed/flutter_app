import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/tap_outside_hides_keyboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget body) => TapOutsideHidesKeyboard(
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: body),
    ),
  );

  bool fieldFocused(WidgetTester tester) => tester
      .widget<EditableText>(find.byType(EditableText).first)
      .focusNode
      .hasFocus;

  Future<void> focusField(WidgetTester tester) async {
    await tester.showKeyboard(find.byType(TextField).first);
    await tester.pump();
    expect(fieldFocused(tester), isTrue);
  }

  final mobile = TargetPlatformVariant.mobile();

  testWidgets('a tap outside the field hides the keyboard', variant: mobile, (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Column(
          children: [
            TextField(),
            Expanded(child: SizedBox.expand(key: ValueKey('empty'))),
          ],
        ),
      ),
    );
    await focusField(tester);

    await tester.tap(find.byKey(const ValueKey('empty')));
    await tester.pump();

    expect(fieldFocused(tester), isFalse);
  });

  testWidgets(
    'scrolling or long-pressing outside keeps the keyboard',
    variant: mobile,
    (tester) async {
      await tester.pumpWidget(
        app(
          Column(
            children: [
              const TextField(),
              Expanded(
                child: ListView(
                  key: const ValueKey('list'),
                  children: [
                    for (var i = 0; i < 40; i++)
                      SizedBox(height: 60, child: Text('row $i')),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      await focusField(tester);

      await tester.drag(
        find.byKey(const ValueKey('list')),
        const Offset(0, -300),
      );
      await tester.pump();
      expect(fieldFocused(tester), isTrue);

      await tester.longPress(find.text('row 8'));
      await tester.pump();
      expect(fieldFocused(tester), isTrue);
    },
  );

  testWidgets(
    'the chat composer keeps the keyboard when Send is tapped',
    variant: mobile,
    (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(
        app(
          Column(
            children: [
              const Expanded(child: SizedBox.expand(key: ValueKey('chat'))),
              ComposeArea(onSend: sent.add),
            ],
          ),
        ),
      );
      await focusField(tester);
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      expect(sent, ['Hello']);
      expect(fieldFocused(tester), isTrue);

      await tester.tap(find.byKey(const ValueKey('chat')));
      await tester.pump();
      expect(fieldFocused(tester), isFalse);
    },
  );

  testWidgets(
    'the Thought composer hides the keyboard on a tap outside',
    variant: mobile,
    (tester) async {
      await tester.pumpWidget(
        app(
          ComposePostSheet(
            thoughtsOnly: true,
            eligibleContacts: const [],
            onSubmitWithOutcome: (_) async =>
                ComposePostSubmitOutcome.keepSheetOpen,
          ),
        ),
      );
      await focusField(tester);

      await tester.tap(find.text('All your friends see this for 24 hours'));
      await tester.pump();

      expect(fieldFocused(tester), isFalse);
    },
  );
}
