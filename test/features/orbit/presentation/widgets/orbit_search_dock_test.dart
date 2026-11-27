import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_dock.dart';

void main() {
  Widget wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  group('OrbitSearchDock', () {
    late TextEditingController controller;
    late FocusNode focusNode;

    setUp(() {
      controller = TextEditingController();
      focusNode = FocusNode();
    });

    tearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('renders search icon and TextField', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchDock(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) {},
        onClear: () {},
        onClose: () {},
        query: '',
      )));
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders close button', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchDock(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) {},
        onClear: () {},
        onClose: () {},
        query: '',
      )));
      // The close button has Icons.close icon (at least one in the outer close button)
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('hides clear button when query is empty', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchDock(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) {},
        onClear: () {},
        onClose: () {},
        query: '',
      )));
      // Only one close icon (the outer close button), not the clear button
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('shows clear button when query is not empty', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchDock(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) {},
        onClear: () {},
        onClose: () {},
        query: 'hello',
      )));
      // Two close icons: one for clear, one for close button
      expect(find.byIcon(Icons.close), findsNWidgets(2));
    });

    for (final direction in TextDirection.values) {
      testWidgets('BL-107 Orbit search controls use 44 pt hit targets ($direction)', (
        tester,
      ) async {
        const deadline = Duration(seconds: 3);
        final actions = <String>[];
        final isRtl = direction == TextDirection.rtl;
        await tester
            .pumpWidget(
              wrap(
                Directionality(
                  textDirection: direction,
                  child: OrbitSearchDock(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: (_) {},
                    onClear: () => actions.add('clear'),
                    onClose: () => actions.add('close'),
                    query: 'hello',
                  ),
                ),
                locale: Locale(isRtl ? 'ar' : 'en'),
              ),
            )
            .timeout(deadline);
        expect(
          find.bySemanticsLabel(isRtl ? 'مسح البحث' : 'Clear search'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(isRtl ? 'إغلاق البحث' : 'Close search'),
          findsOneWidget,
        );
        final icons = find.byIcon(Icons.close);
        expect(icons, findsNWidgets(2));
        for (var index = 0; index < 2; index++) {
          final icon = icons.at(index);
          final target = find.ancestor(
            of: icon,
            matching: find.byWidgetPredicate(
              (widget) => widget is GestureDetector && widget.onTap != null,
            ),
          ).first;
          final size = tester.getSize(target);
          expect(size.width, greaterThanOrEqualTo(44));
          expect(size.height, greaterThanOrEqualTo(44));
          expect(tester.widget<Icon>(icon).size, index == 0 ? 16 : 15);
          final point = tester.getCenter(target) + const Offset(0, 20);
          await tester.tapAt(point).timeout(deadline);
        }
        expect(actions, ['clear', 'close']);
      });
    }

    testWidgets('calls onClose when close button tapped', (tester) async {
      var closeTapped = false;
      await tester.pumpWidget(wrap(OrbitSearchDock(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) {},
        onClear: () {},
        onClose: () => closeTapped = true,
        query: '',
      )));
      await tester.tap(find.byIcon(Icons.close));
      expect(closeTapped, isTrue);
    });
  });
}
