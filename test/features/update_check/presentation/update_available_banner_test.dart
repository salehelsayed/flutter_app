import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/update_check/application/update_check_controller.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/update_store_urls.dart';
import 'package:flutter_app/features/update_check/presentation/update_available_banner.dart';
import 'package:flutter_app/features/update_check/presentation/update_required_gate.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_update_check_service.dart';

const _banner = ValueKey('update-available-banner');
const _soft120 = UpdateDecisionSoft(
  latestBuild: 120,
  reasonCode: UpdateReasonCode.general,
);
const _soft121 = UpdateDecisionSoft(
  latestBuild: 121,
  reasonCode: UpdateReasonCode.security,
);

void main() {
  late FakeUpdateCheckService service;
  late UpdateCheckController controller;
  late List<Uri> launches;

  void useDecisions(List<UpdateDecision> decisions) {
    service = FakeUpdateCheckService(decisions: decisions, due: true);
    controller = UpdateCheckController(service: service);
    addTearDown(controller.dispose);
  }

  setUp(() => launches = <Uri>[]);

  Widget app({Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => UpdateRequiredGate(
      controller: controller,
      callCapability: null,
      launchStore: (url) async {
        launches.add(url);
        return true;
      },
      child: child!,
    ),
    home: Scaffold(
      body: UpdateAvailableBannerHost(
        launchStore: (url) async {
          launches.add(url);
          return true;
        },
        child: const _OrbitStandIn(),
      ),
    ),
  );

  Future<void> resume(WidgetTester tester) async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  group('AC15', () {
    testWidgets('shows for soft only', (tester) async {
      useDecisions([
        const UpdateDecisionNone(),
        const UpdateDecisionHard(
          minBuild: 120,
          reasonCode: UpdateReasonCode.general,
        ),
        _soft120,
      ]);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byKey(_banner), findsNothing);

      await resume(tester);
      expect(controller.value, isA<UpdateDecisionHard>());
      expect(find.byKey(_banner), findsNothing);
      expect(find.byKey(const ValueKey('update-required-overlay')), findsOne);

      await resume(tester);
      expect(find.byKey(_banner), findsOneWidget);
      expect(find.text('A new version of Mknoon is ready.'), findsOne);
      expect(
        find.byKey(const ValueKey('update-required-overlay')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('update-available-banner-update')),
      );
      await tester.pump();
      expect(launches, [Uri.parse(updateStoreUrlIos)]);
    });

    testWidgets('a dismissal holds for the same latestBuild and the banner '
        'returns for a higher one', (tester) async {
      useDecisions([_soft120, _soft120, _soft121]);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byKey(_banner), findsOneWidget);

      // Orbit keeps its state while the banner comes and goes.
      await tester.tap(find.byKey(const ValueKey('orbit-stand-in')));
      await tester.pump();
      expect(find.text('taps 1'), findsOneWidget);

      await tester.tap(find.byTooltip('Not now'));
      await tester.pumpAndSettle();
      expect(find.byKey(_banner), findsNothing);
      expect(service.dismissed, [120]);
      expect(find.text('taps 1'), findsOneWidget);

      await resume(tester);
      expect(service.checks, 2);
      expect(find.byKey(_banner), findsNothing);

      await resume(tester);
      expect(service.checks, 3);
      expect(find.byKey(_banner), findsOneWidget);
      expect(find.text('A security update for Mknoon is ready.'), findsOne);
      expect(find.text('taps 1'), findsOneWidget);
    });

    testWidgets('the banner sits under the status bar and the content below '
        'it', (tester) async {
      useDecisions([_soft120]);
      tester.view.padding = const FakeViewPadding(top: 60);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      final banner = tester.getRect(find.byKey(_banner));
      final orbit = tester.getRect(
        find.byKey(const ValueKey('orbit-stand-in')),
      );
      expect(banner.top, 0);
      expect(orbit.top, greaterThanOrEqualTo(banner.bottom));
      // The banner already took the top inset.
      final orbitPadding = MediaQuery.paddingOf(
        tester.element(find.byKey(const ValueKey('orbit-stand-in'))),
      );
      expect(orbitPadding.top, 0);
    });

    testWidgets('Arabic banner reads right to left', (tester) async {
      useDecisions([_soft120]);
      await tester.pumpWidget(app(locale: const Locale('ar')));
      await tester.pumpAndSettle();
      final text = find.text('يتوفر إصدار جديد من مكنون.');
      expect(text, findsOneWidget);
      expect(Directionality.of(tester.element(text)), TextDirection.rtl);
      expect(find.byTooltip('ليس الآن'), findsOneWidget);
      expect(find.text('تحديث'), findsOneWidget);
    });

    testWidgets('without the app scope the host is a plain pass-through', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UpdateAvailableBannerHost(child: _OrbitStandIn()),
        ),
      );
      expect(find.byKey(_banner), findsNothing);
      expect(find.byKey(const ValueKey('orbit-stand-in')), findsOneWidget);
    });
  });

  test('OrbitScreen mounts the banner host (source check)', () {
    final orbit = File(
      'lib/features/orbit/presentation/screens/orbit_screen.dart',
    ).readAsStringSync();
    expect(
      orbit,
      contains(
        'final scaffold = UpdateAvailableBannerHost(child: orbitScaffold);',
      ),
    );
  });
}

class _OrbitStandIn extends StatefulWidget {
  const _OrbitStandIn();

  @override
  State<_OrbitStandIn> createState() => _OrbitStandInState();
}

class _OrbitStandInState extends State<_OrbitStandIn> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('orbit-stand-in'),
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _taps += 1),
    child: Center(child: Text('taps $_taps')),
  );
}
