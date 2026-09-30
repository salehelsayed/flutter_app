import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('full reaction picker exposes one actionable stable identifier', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionBar(
              onReactionSelected: (_) {},
              onPlusTap: () => opened++,
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final control = find.bySemanticsIdentifier('message_reaction_more');
      expect(control, findsOneWidget);
      expect(
        tester
            .getSemantics(control)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.tap(control);
      expect(opened, 1);
      for (final emoji in kPresetEmojis) {
        expect(find.text(emoji), findsOneWidget);
      }
    } finally {
      semantics.dispose();
    }
  });
}
