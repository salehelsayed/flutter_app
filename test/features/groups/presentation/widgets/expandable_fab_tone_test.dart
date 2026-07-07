import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/groups/presentation/widgets/glow_fab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(BackgroundReadableColors colors) {
    return MaterialApp(
      theme: ThemeData(extensions: [colors]),
      home: Scaffold(
        body: Stack(
          children: [
            const SizedBox.expand(),
            ExpandableFab(
              items: [
                ExpandableFabItem(
                  label: 'New Group',
                  icon: Icons.group_outlined,
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('GlowFab and menu pills use Signal tones on light', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;

    await tester.pumpWidget(wrap(colors));
    await tester.pump();

    final glowFab = tester.widget<GlowFab>(find.byType(GlowFab));
    expect(glowFab.backgroundColor, colors.ctaBg);
    expect(glowFab.ringColor, colors.ctaIcon);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    final menuText = tester.widget<Text>(find.text('New Group'));
    expect(menuText.style!.color, colors.ctaMenuText);

    final menuContainer = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('New Group'),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).color ==
                      colors.ctaMenuFill,
            ),
          )
          .first,
    );
    final decoration = menuContainer.decoration as BoxDecoration;
    expect(decoration.color, colors.ctaMenuFill);
    expect((decoration.border as Border).top.color, colors.ctaMenuBorder);
  });

  testWidgets('GlowFab dark background preserves the old literal', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(BackgroundReadableColors.dark));
    await tester.pump();

    final glowFab = tester.widget<GlowFab>(find.byType(GlowFab));
    expect(glowFab.backgroundColor, const Color(0xFF1A1A2E));
    expect(glowFab.ringColor, const Color(0xFF64B5F6));
  });
}
