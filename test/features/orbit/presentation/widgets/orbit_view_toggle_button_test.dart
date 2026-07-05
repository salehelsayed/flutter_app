import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_view_toggle_button.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../screens/orbit_screen_pump_harness.dart';

/// 211 — the view-toggle glyphs adopt the 207-mockup chrome vocabulary:
/// bullet-list on the Inner-Circle view (destination = all-chats list),
/// dot-in-dashed-ring on the all-chats view (destination = inner circle).
/// Container chrome stays TOKEN-driven (INV-211-2 — never hardcode the mockup
/// rgba; the dark tokens already equal it and the light tone must keep
/// resolving) and the key/semantics contract is unchanged (INV-211-1).
void main() {
  Widget wrap(
    OrbitViewMode viewMode, {
    BackgroundReadableColors tone = BackgroundReadableColors.dark,
  }) =>
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [tone]),
        home: Scaffold(
          body: Stack(
            children: [
              OrbitViewToggleButton(viewMode: viewMode, onToggle: () {}),
            ],
          ),
        ),
      );

  Container toggleContainer(WidgetTester tester) => tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('orbit-view-toggle')),
          matching: find.byType(Container),
        ),
      );

  testWidgets('TC-211-01/02 glyphs match the 207 vocabulary', (tester) async {
    // Inner-Circle view: destination is the all-chats LIST → bullet-list glyph.
    await tester.pumpWidget(wrap(OrbitViewMode.innerCircle));
    await tester.pump();
    expect(find.byIcon(Icons.format_list_bulleted), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);

    // All-chats view: destination is the inner CIRCLE → dot-in-ring glyph.
    await tester.pumpWidget(wrap(OrbitViewMode.allChats));
    await tester.pump();
    expect(find.byIcon(Icons.motion_photos_on), findsOneWidget);
    expect(find.byIcon(Icons.blur_on), findsNothing);
  });

  testWidgets('TC-211-03/04 container chrome stays token-driven (dark tone)',
      (tester) async {
    await tester.pumpWidget(wrap(OrbitViewMode.innerCircle));
    await tester.pump();

    final decoration = toggleContainer(tester).decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xBF101218),
        reason: 'fill = dark surfaceSubtle token (== 207 mockup rgba)');
    expect((decoration.border! as Border).top.color, const Color(0x80FFFFFF),
        reason: 'hairline = dark border token (== 207 mockup rgba)');
  });

  testWidgets(
      'TC-211-03/04 container chrome stays token-driven (light tone) — '
      'guards against hardcoding the dark mockup rgba', (tester) async {
    await tester.pumpWidget(
      wrap(
        OrbitViewMode.innerCircle,
        tone: BackgroundReadableColors.representativeLight,
      ),
    );
    await tester.pump();

    final decoration = toggleContainer(tester).decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xE8EEF2F7),
        reason: 'fill must resolve the LIGHT surfaceSubtle token');
    expect((decoration.border! as Border).top.color, const Color(0x8A101318),
        reason: 'hairline must resolve the LIGHT border token');
  });

  testWidgets('TC-211-05/08 key + destination semantics unchanged',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(wrap(OrbitViewMode.innerCircle));
    await tester.pump();
    expect(find.byKey(const ValueKey('orbit-view-toggle')), findsOneWidget);
    expect(find.bySemanticsLabel('Show all chats'), findsOneWidget);

    await tester.pumpWidget(wrap(OrbitViewMode.allChats));
    await tester.pump();
    expect(find.byKey(const ValueKey('orbit-view-toggle')), findsOneWidget);
    expect(find.bySemanticsLabel('Show inner circle'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('TC-211-10 no toggle handler → no button', (tester) async {
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('Unable to load asset') ||
          msg.contains('SvgPicture') ||
          msg.contains('ImageFilter')) {
        return;
      }
      old?.call(details);
    };
    addTearDown(() => FlutterError.onError = old);

    await tester.pumpWidget(
      buildOrbitScreenHarness(viewMode: OrbitViewMode.innerCircle),
    );
    await tester.pump(const Duration(milliseconds: 90));

    expect(find.byKey(const ValueKey('orbit-view-toggle')), findsNothing);
  });
}
