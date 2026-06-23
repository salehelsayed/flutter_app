import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/orbit3/orbit3_prototype.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  void suppressAssetErrors(WidgetTester tester) {
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('Unable to load asset') ||
          msg.contains('SvgPicture') ||
          msg.contains('ImageFilter')) {
        return;
      }
      oldHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldHandler);
  }

  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      );

  test('AppShellTab.orbit3 is valid and in values', () {
    expect(AppShellTab.orbit3, 'orbit3');
    expect(AppShellTab.isValid('orbit3'), isTrue);
    expect(AppShellTab.values.contains('orbit3'), isTrue);
  });

  testWidgets('FeedNavigationBar shows the Orbit3 button and taps switch to it',
      (tester) async {
    suppressAssetErrors(tester);
    expect(kOrbit3PrototypeEnabled, isTrue,
        reason: 'the wiring test assumes the prototype tab is enabled');

    String? tapped;
    await tester.pumpWidget(
      wrap(FeedNavigationBar(activeTab: 'feed', onSwitchView: (t) => tapped = t)),
    );
    await tester.pump();

    expect(find.text('Orbit3'), findsOneWidget);
    await tester.tap(find.text('Orbit3'));
    expect(tapped, AppShellTab.orbit3);
  });
}
