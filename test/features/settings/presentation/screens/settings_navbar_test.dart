import 'package:flutter/material.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_orbit_nav_button.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void suppressAssetErrors(WidgetTester tester) {
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('Unable to load asset') ||
          message.contains('SvgPicture') ||
          message.contains('ImageFilter')) {
        return;
      }
      oldHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldHandler);
  }

  Widget wrap({bool showNavigationBar = true}) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SettingsScreen(
          username: 'Alice',
          peerId: '12D3KooWSettingsPeer',
          onSwitchView: (_) {},
          activeTab: 'feed',
          showNavigationBar: showNavigationBar,
        ),
      ),
    );
  }

  testWidgets('TC-226-01 settings navbar renders no Feed destination', (
    tester,
  ) async {
    suppressAssetErrors(tester);
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('Feed'), findsNothing);
    final svgPictures = tester.widgetList<SvgPicture>(find.byType(SvgPicture));
    expect(
      svgPictures.any(
        (svg) => svg.bytesLoader.toString().contains('nav_feed.svg'),
      ),
      isFalse,
    );
  });

  testWidgets('TC-226-02 settings navbar slot renders glass orbit button, not '
      'FeedNavigationBar', (tester) async {
    suppressAssetErrors(tester);
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.byType(SettingsOrbitNavButton), findsOneWidget);
    expect(find.byType(FeedNavigationBar), findsNothing);
  });

  testWidgets(
    'TC-226-03 showNavigationBar=false renders neither orbit nor bar',
    (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(showNavigationBar: false));
      await tester.pump();

      expect(find.byType(SettingsOrbitNavButton), findsNothing);
      expect(find.byType(FeedNavigationBar), findsNothing);
    },
  );
}
