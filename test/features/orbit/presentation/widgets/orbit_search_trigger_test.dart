import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child, {BackgroundReadableColors? readableColors}) =>
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          extensions: [readableColors ?? BackgroundReadableColors.dark],
        ),
        home: Scaffold(body: child),
      );

  group('OrbitSearchTrigger', () {
    testWidgets(
        'TC-212-08 renders a 52px glass circle with icon 24, border, blur '
        'and shadow, and an opaque hit square', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(OrbitSearchTrigger(onSearchTap: () => tapped = true)),
      );

      expect(tester.getSize(find.byType(OrbitSearchTrigger)),
          const Size(52, 52));

      // Outer shell carries the drop shadow OUTSIDE the ClipOval (a clipped
      // shadow is invisible).
      final outer = tester.widget<Container>(find
          .descendant(
            of: find.byType(OrbitSearchTrigger),
            matching: find.byType(Container),
          )
          .first);
      final outerDecoration = outer.decoration as BoxDecoration;
      expect(outerDecoration.boxShadow, isNotNull);
      expect(outerDecoration.boxShadow, isNotEmpty);

      // The glass vocabulary is kept: blur 12 behind a bordered surface.
      expect(
        find.descendant(
          of: find.byType(OrbitSearchTrigger),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
      final inner = tester.widget<Container>(find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.byType(Container),
      ));
      final innerDecoration = inner.decoration as BoxDecoration;
      expect((innerDecoration.border as Border).top.color,
          BackgroundReadableColors.dark.glassBorder);
      expect(innerDecoration.color, BackgroundReadableColors.dark.glassSurface);

      final icon = tester.widget<Icon>(find.byIcon(Icons.search));
      expect(icon.size, 24, reason: '212 visual upgrade: 22 → 24');

      // Opaque hit square: a corner tap (outside the drawn circle) fires —
      // deferToChild inside ClipOval would leave dead corners.
      final rect = tester.getRect(find.byType(OrbitSearchTrigger));
      await tester.tapAt(rect.topLeft + const Offset(2, 2));
      expect(tapped, isTrue, reason: 'the full 52px square is tappable');
    });

    testWidgets('TC-212-09 exposes a Semantics button label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(OrbitSearchTrigger(onSearchTap: () {})));

      final labelF = find.bySemanticsLabel('Search chats');
      expect(labelF, findsOneWidget);
      expect(tester.getSemantics(labelF), isSemantics(isButton: true));
      handle.dispose();
    });

    testWidgets('renders search icon', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchTrigger(onSearchTap: () {})));
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('calls onSearchTap when tapped', (tester) async {
      var searchTapped = false;
      await tester.pumpWidget(
        wrap(OrbitSearchTrigger(onSearchTap: () => searchTapped = true)),
      );
      await tester.tap(find.byType(OrbitSearchTrigger));
      expect(searchTapped, isTrue);
    });

    testWidgets('uses readable glass and icon color on daylight', (
      tester,
    ) async {
      const colors = BackgroundReadableColors.representativeLight;

      await tester.pumpWidget(
        wrap(OrbitSearchTrigger(onSearchTap: () {}), readableColors: colors),
      );

      final container = tester.widget<Container>(find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.byType(Container),
      ));
      final decoration = container.decoration as BoxDecoration;
      final icon = tester.widget<Icon>(find.byIcon(Icons.search));

      expect(decoration.color, colors.glassSurface);
      expect((decoration.border as Border).top.color, colors.glassBorder);
      expect(icon.color, colors.iconPrimary);
    });
  });
}
