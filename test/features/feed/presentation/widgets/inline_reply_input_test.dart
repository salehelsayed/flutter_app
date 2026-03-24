import 'dart:ui' show TextDirection;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/inline_reply_input.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/voice_record_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('InlineReplyInput', () {
    testWidgets('renders TextField with hint text', (tester) async {
      await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Reply...'), findsOneWidget);
    });

    testWidgets('shows attach button when onAttach is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(InlineReplyInput(onSend: (_) {}, onAttach: () {})),
      );
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('hides attach button when onAttach is null', (tester) async {
      await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));
      expect(find.byIcon(Icons.add_rounded), findsNothing);
    });

    testWidgets('shows send button when text is entered', (tester) async {
      await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    group('BiDi input direction', () {
      testWidgets('TextField defaults to LTR when empty', (tester) async {
        await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));
        await tester.pump();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, TextDirection.ltr);
      });

      testWidgets('TextField uses RTL for hydrated mixed initialText', (
        tester,
      ) async {
        const initialText = 'مرحبا Hello 123';

        await tester.pumpWidget(
          wrap(InlineReplyInput(onSend: (_) {}, initialText: initialText)),
        );
        await tester.pump();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.controller?.text, initialText);
        expect(textField.textDirection, TextDirection.rtl);
      });

      testWidgets('TextField switches to RTL when Arabic is typed', (
        tester,
      ) async {
        await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));

        await tester.enterText(find.byType(TextField), 'مرحبا');
        await tester.pump();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, TextDirection.rtl);
      });

      testWidgets('TextField stays LTR when English is typed', (tester) async {
        await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));

        await tester.enterText(find.byType(TextField), 'Hello');
        await tester.pump();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, TextDirection.ltr);
      });

      testWidgets('TextField switches back to LTR after clearing text', (
        tester,
      ) async {
        await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));

        await tester.enterText(find.byType(TextField), 'مرحبا');
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).textDirection,
          TextDirection.rtl,
        );

        await tester.enterText(find.byType(TextField), 'Hello');
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).textDirection,
          TextDirection.ltr,
        );
      });
    });

    testWidgets('calls onSend with text when send button tapped', (
      tester,
    ) async {
      String? sentText;
      await tester.pumpWidget(
        wrap(InlineReplyInput(onSend: (text) => sentText = text)),
      );
      await tester.enterText(find.byType(TextField), 'Hello world');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      expect(sentText, 'Hello world');
    });

    testWidgets('renders with custom hint text', (tester) async {
      await tester.pumpWidget(
        wrap(InlineReplyInput(onSend: (_) {}, hintText: 'Type here...')),
      );
      expect(find.text('Type here...'), findsOneWidget);
    });

    testWidgets('send button is 36x36', (tester) async {
      await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));
      await tester.enterText(find.byType(TextField), 'Hi');
      await tester.pumpAndSettle();

      final sendContainer = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.arrow_upward_rounded),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(sendContainer.constraints?.maxWidth, 36);
      expect(sendContainer.constraints?.maxHeight, 36);
    });

    testWidgets('attach button is 36x36 when shown', (tester) async {
      await tester.pumpWidget(
        wrap(InlineReplyInput(onSend: (_) {}, onAttach: () {})),
      );

      final attachContainer = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.add_rounded),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(attachContainer.constraints?.maxWidth, 36);
      expect(attachContainer.constraints?.maxHeight, 36);
    });

    testWidgets('shows mic button when voice callbacks provided and no text', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          InlineReplyInput(
            onSend: (_) {},
            onRecordStart: () {},
            onRecordStop: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    });

    testWidgets('shows send button instead of mic when text is present', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          InlineReplyInput(
            onSend: (_) {},
            onRecordStart: () {},
            onRecordStop: () {},
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
    });

    testWidgets('no mic button when voice callbacks are null', (tester) async {
      await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      // Send button still shown (dimmed)
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('mic button forwards record start and stop callbacks', (
      tester,
    ) async {
      var started = false;
      var stopped = false;

      await tester.pumpWidget(
        wrap(
          InlineReplyInput(
            onSend: (_) {},
            onRecordStart: () => started = true,
            onRecordStop: () => stopped = true,
          ),
        ),
      );

      final button = tester.widget<VoiceRecordButton>(
        find.byType(VoiceRecordButton),
      );
      button.onTapDown();
      button.onTapUp();

      expect(started, isTrue);
      expect(stopped, isTrue);
    });
  });
}
