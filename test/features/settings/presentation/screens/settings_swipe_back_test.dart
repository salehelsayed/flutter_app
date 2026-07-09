import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/settings/presentation/navigation/settings_route_transition.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_orbit_nav_button.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  void suppressAssetErrors(WidgetTester tester) {
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('Unable to load asset') ||
          message.contains('SvgPicture') ||
          message.contains('ImageFilter') ||
          message.contains('overflowed')) {
        return;
      }
      oldHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldHandler);
  }

  IdentityModel makeIdentity() => IdentityModel(
    peerId: '12D3KooWMyPeer123',
    publicKey: 'pub',
    privateKey: 'priv',
    mnemonic12:
        'abandon ability able about above absent absorb abstract absurd abuse access accident',
    username: 'Alice',
    createdAt: '2026-07-09T00:00:00.000Z',
    updatedAt: '2026-07-09T00:00:00.000Z',
  );

  ImageProcessor imageProcessor() =>
      ImageProcessor(compressFile: _noOpCompress);

  Future<_Harness> pumpHarness(
    WidgetTester tester, {
    bool showNavigationBar = true,
    Locale locale = const Locale('en'),
    NavigatorObserver? observer,
  }) async {
    suppressAssetErrors(tester);
    final identityRepo = FakeIdentityRepository()..seed(makeIdentity());
    final controller = AppShellController(initialTab: AppShellTab.feed);
    addTearDown(controller.dispose);
    final privacyRepo = InMemoryPostsPrivacySettingsRepository();
    addTearDown(privacyRepo.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: observer == null
            ? const <NavigatorObserver>[]
            : <NavigatorObserver>[observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    buildSettingsSlideUpRoute<void>(
                      builder: (_) => SettingsWired(
                        identityRepo: identityRepo,
                        bridge: FakeBridge(),
                        contactRepo: FakeContactRepository(),
                        p2pService: FakeP2PService(),
                        secureKeyStore: FakeSecureKeyStore(),
                        imageProcessor: imageProcessor(),
                        appShellController: controller,
                        postsPrivacySettingsRepository: privacyRepo,
                        showNavigationBar: showNavigationBar,
                      ),
                    ),
                  );
                },
                child: const Text('Open Settings'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Settings'));
    await pumpFrames(tester);
    expect(find.byType(SettingsWired), findsOneWidget);
    expect(controller.activeTab, AppShellTab.feed);

    return _Harness(controller: controller);
  }

  Future<void> flingRight(
    WidgetTester tester, {
    bool warnIfMissed = true,
  }) async {
    await tester.fling(
      find.byType(SettingsScreen),
      const Offset(300, 0),
      1200,
      warnIfMissed: warnIfMissed,
    );
    await pumpFrames(tester);
  }

  Future<void> dragRightSlow(WidgetTester tester, double dx) async {
    await tester.timedDrag(
      find.byType(SettingsScreen),
      Offset(dx, 0),
      const Duration(milliseconds: 600),
    );
    await pumpFrames(tester);
  }

  testWidgets(
    'TC-226-07 tapping the glass orbit button switches shell to orbit and '
    'pops Settings',
    (tester) async {
      final harness = await pumpHarness(tester);

      await tester.tap(find.byType(SettingsOrbitNavButton));
      await pumpFrames(tester);

      expect(harness.controller.activeTab, AppShellTab.orbit);
      expect(find.byType(SettingsWired), findsNothing);
    },
  );

  testWidgets(
    'TC-226-08 fast rightward fling pops Settings and lands on orbit',
    (tester) async {
      final harness = await pumpHarness(tester);

      await flingRight(tester);

      expect(harness.controller.activeTab, AppShellTab.orbit);
      expect(find.byType(SettingsWired), findsNothing);
    },
  );

  testWidgets('TC-226-09 slow long rightward drag pops Settings', (
    tester,
  ) async {
    final harness = await pumpHarness(tester);

    await dragRightSlow(tester, 360);

    expect(harness.controller.activeTab, AppShellTab.orbit);
    expect(find.byType(SettingsWired), findsNothing);
  });

  testWidgets('TC-226-10 leftward fling does not pop', (tester) async {
    final harness = await pumpHarness(tester);

    await tester.fling(
      find.byType(SettingsScreen),
      const Offset(-300, 0),
      1200,
    );
    await pumpFrames(tester);

    expect(harness.controller.activeTab, AppShellTab.feed);
    expect(find.byType(SettingsWired), findsOneWidget);
  });

  testWidgets('TC-226-11 short under-threshold rightward drag does not pop', (
    tester,
  ) async {
    final harness = await pumpHarness(tester);

    await dragRightSlow(tester, 80);

    expect(harness.controller.activeTab, AppShellTab.feed);
    expect(find.byType(SettingsWired), findsOneWidget);
  });

  testWidgets('TC-226-12 vertical scroll still scrolls and does not pop', (
    tester,
  ) async {
    final harness = await pumpHarness(tester);
    final scrollable = find.byType(Scrollable).first;
    final before = tester.state<ScrollableState>(scrollable).position.pixels;

    await tester.drag(scrollable, const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    final after = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(after, greaterThan(before));
    expect(harness.controller.activeTab, AppShellTab.feed);
    expect(find.byType(SettingsWired), findsOneWidget);
  });

  testWidgets('TC-226-13 showNavigationBar=false disables the swipe surface', (
    tester,
  ) async {
    final harness = await pumpHarness(tester, showNavigationBar: false);

    await flingRight(tester, warnIfMissed: false);

    expect(harness.controller.activeTab, AppShellTab.feed);
    expect(find.byType(SettingsWired), findsOneWidget);
  });

  testWidgets('TC-226-14 RTL physical rightward fling still pops', (
    tester,
  ) async {
    final harness = await pumpHarness(tester, locale: const Locale('ar'));

    await flingRight(tester, warnIfMissed: false);

    expect(harness.controller.activeTab, AppShellTab.orbit);
    expect(find.byType(SettingsWired), findsNothing);
  });

  testWidgets('TC-226-15 one qualifying gesture fires exactly one pop', (
    tester,
  ) async {
    final observer = _RecordingNavigatorObserver();
    final harness = await pumpHarness(tester, observer: observer);

    await dragRightSlow(tester, 360);
    final second = await tester.startGesture(const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 20));
    await second.moveBy(const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await second.up();
    await pumpFrames(tester);

    expect(harness.controller.activeTab, AppShellTab.orbit);
    expect(observer.popCount, 1);
    expect(find.byType(SettingsWired), findsNothing);
  });

  testWidgets('TC-226-17 swipe is inert while a Settings sub-flow is topmost', (
    tester,
  ) async {
    final harness = await pumpHarness(tester);

    showModalBottomSheet<void>(
      context: tester.element(find.byType(SettingsScreen)),
      builder: (_) => const SizedBox(height: 180, child: Text('Sheet on top')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await flingRight(tester, warnIfMissed: false);
    expect(find.text('Sheet on top'), findsOneWidget);
    expect(find.byType(SettingsWired), findsOneWidget);
    expect(harness.controller.activeTab, AppShellTab.feed);

    Navigator.of(tester.element(find.text('Sheet on top'))).pop();
    await pumpFrames(tester);

    Navigator.of(tester.element(find.byType(SettingsScreen))).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: null,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const IgnorePointer(
              child: SizedBox.expand(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text('Transparent sub-route'),
                ),
              ),
            ),
      ),
    );
    await pumpFrames(tester);

    await flingRight(tester, warnIfMissed: false);

    expect(find.text('Transparent sub-route'), findsOneWidget);
    expect(find.byType(SettingsWired), findsOneWidget);
    expect(harness.controller.activeTab, AppShellTab.feed);
  });
}

class _Harness {
  final AppShellController controller;

  const _Harness({required this.controller});
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<XFile?> _noOpCompress({
  required String path,
  required int quality,
  required bool keepExif,
  int minWidth = 1920,
  int minHeight = 1080,
}) async {
  return XFile('${path}_compressed.jpg');
}
