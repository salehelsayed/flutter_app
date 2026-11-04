import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_test/flutter_test.dart';

List<TextSpan> spansOf(WidgetTester tester) {
  final rich = tester.widget<RichText>(find.byType(RichText).first);
  final spans = <TextSpan>[];
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.text != null) spans.add(span);
    return true;
  });
  return spans;
}

void main() {
  const mark = TextStyle(backgroundColor: Color(0xFF1DB954));

  testWidgets('matches are drawn in the mark style, the rest as usual', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LinkableText(
          text: 'Dahab, then back to dahab',
          markQuery: 'dahab',
          markStyle: mark,
        ),
      ),
    );
    final marked = [
      for (final span in spansOf(tester))
        if (span.style?.backgroundColor == mark.backgroundColor) span.text,
    ];
    expect(marked, ['Dahab', 'dahab']);
    expect(
      spansOf(tester).map((span) => span.text).join(),
      'Dahab, then back to dahab',
    );
  });

  testWidgets('a match inside a link stays a tinted link', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LinkableText(
          text: 'see dahab.com',
          markQuery: 'dahab',
          markStyle: mark,
        ),
      ),
    );
    final marked = spansOf(
      tester,
    ).where((span) => span.style?.backgroundColor == mark.backgroundColor);
    expect(marked.map((span) => span.text), ['dahab']);
    expect(marked.single.recognizer, isNotNull);
  });

  testWidgets('without a query nothing is marked', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LinkableText(text: 'back to dahab', markStyle: mark),
      ),
    );
    expect(
      spansOf(
        tester,
      ).where((span) => span.style?.backgroundColor == mark.backgroundColor),
      isEmpty,
    );
  });
}
