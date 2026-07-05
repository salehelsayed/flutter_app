import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

/// 209 — the My QR / Scan tiles hosted on the Settings page (migrated from the
/// retired Orbit top chrome). Tiles are a host-capability PAIR: they mount only
/// when the host supplies BOTH callbacks (INV-209-1, spec §7.1 posts-entry
/// parity), carry visible l10n labels (not semantics-only), mirror with ambient
/// directionality (unlike the forced-LTR orbit chrome), and the wired host
/// single-flights the pushes via the `_qrRouteActive` latch (TC-209-05).
const _myQrTileKey = ValueKey('settings-my-qr-tile');
const _scanTileKey = ValueKey('settings-scan-tile');

void main() {
  Widget wrapScreen({
    VoidCallback? onMyQr,
    VoidCallback? onScan,
    Locale locale = const Locale('en'),
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SettingsScreen(
          username: 'Alice',
          peerId: '12D3KooWTestPeer123',
          onMyQr: onMyQr,
          onScan: onScan,
          onSwitchView: (_) {},
          activeTab: 'feed',
        ),
      ),
    );
  }

  testWidgets('T1 renders My QR and Scan tiles with visible labels', (
    tester,
  ) async {
    await tester.pumpWidget(wrapScreen(onMyQr: () {}, onScan: () {}));

    expect(find.byKey(_myQrTileKey), findsOneWidget);
    expect(find.byKey(_scanTileKey), findsOneWidget);
    // Visible text labels — NOT semantics-only (the orbit chrome regression).
    expect(find.text('My QR'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });

  testWidgets('T2 labels localize and mirror under ar RTL', (tester) async {
    await tester.pumpWidget(
      wrapScreen(onMyQr: () {}, onScan: () {}, locale: const Locale('ar')),
    );

    expect(find.text('رمزي'), findsOneWidget);
    expect(find.text('مسح'), findsOneWidget);

    // Ambient directionality: under RTL the My QR tile sits physically RIGHT
    // of Scan (the retired orbit chrome pinned TextDirection.ltr instead).
    final myQrLeft = tester.getTopLeft(find.byKey(_myQrTileKey));
    final scanLeft = tester.getTopLeft(find.byKey(_scanTileKey));
    expect(myQrLeft.dx, greaterThan(scanLeft.dx));

    // Both remain tappable under RTL.
    await tester.tap(find.byKey(_myQrTileKey));
    await tester.tap(find.byKey(_scanTileKey));
  });

  testWidgets('T2b LTR keeps My QR physically left of Scan', (tester) async {
    await tester.pumpWidget(wrapScreen(onMyQr: () {}, onScan: () {}));

    final myQrLeft = tester.getTopLeft(find.byKey(_myQrTileKey));
    final scanLeft = tester.getTopLeft(find.byKey(_scanTileKey));
    expect(myQrLeft.dx, lessThan(scanLeft.dx));
  });

  testWidgets('T3 tiles expose button semantics with l10n labels', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrapScreen(onMyQr: () {}, onScan: () {}));

    expect(
      tester.getSemantics(find.byKey(_myQrTileKey)),
      matchesSemantics(label: 'My QR', isButton: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.byKey(_scanTileKey)),
      matchesSemantics(label: 'Scan', isButton: true, hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('T4 taps fire host callbacks exactly once, no cross-fire', (
    tester,
  ) async {
    var myQrCalls = 0;
    var scanCalls = 0;
    await tester.pumpWidget(
      wrapScreen(onMyQr: () => myQrCalls++, onScan: () => scanCalls++),
    );

    await tester.tap(find.byKey(_myQrTileKey));
    expect(myQrCalls, 1);
    expect(scanCalls, 0);

    await tester.tap(find.byKey(_scanTileKey));
    expect(myQrCalls, 1);
    expect(scanCalls, 1);
  });

  testWidgets('T5 rapid double-tap fires the host entry once (latch)', (
    tester,
  ) async {
    final identityRepo = FakeIdentityRepository()
      ..seed(FakeIdentityRepository.makeIdentity(peerId: 'latch-peer'));
    final shell = AppShellController();
    addTearDown(shell.dispose);
    final privacyRepo = InMemoryPostsPrivacySettingsRepository();
    addTearDown(privacyRepo.dispose);
    final myQrGate = Completer<void>();
    var myQrCalls = 0;
    var scanCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsWired(
          identityRepo: identityRepo,
          bridge: FakeBridge(),
          contactRepo: FakeContactRepository(),
          p2pService: FakeP2PService(),
          secureKeyStore: FakeSecureKeyStore(),
          imageProcessor: ImageProcessor(),
          appShellController: shell,
          postsPrivacySettingsRepository: privacyRepo,
          onMyQrRequested: () {
            myQrCalls++;
            return myQrGate.future;
          },
          onScanQrRequested: () async {
            scanCalls++;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Two taps within one frame budget: the un-completed Future holds the
    // `_qrRouteActive` latch, so the second tap is swallowed.
    await tester.tap(find.byKey(_myQrTileKey));
    await tester.tap(find.byKey(_myQrTileKey));
    await tester.pump();
    expect(myQrCalls, 1);

    // The latch also guards the sibling entry while a QR route is in flight.
    await tester.tap(find.byKey(_scanTileKey));
    await tester.pump();
    expect(scanCalls, 0);

    // Route pops (future completes) → latch releases → next tap fires.
    myQrGate.complete();
    await tester.pump();
    await tester.tap(find.byKey(_myQrTileKey));
    await tester.pump();
    expect(myQrCalls, 2);
  });

  testWidgets('T6 tiles absent when host callbacks are null (pair gating)', (
    tester,
  ) async {
    // No callbacks at all — the posts-entry / degraded-host variant (§7.1).
    await tester.pumpWidget(wrapScreen());
    expect(find.byKey(_myQrTileKey), findsNothing);
    expect(find.byKey(_scanTileKey), findsNothing);

    // A half-supplied pair must not render an asymmetric single tile.
    await tester.pumpWidget(wrapScreen(onMyQr: () {}));
    expect(find.byKey(_myQrTileKey), findsNothing);
    expect(find.byKey(_scanTileKey), findsNothing);

    await tester.pumpWidget(wrapScreen(onScan: () {}));
    expect(find.byKey(_myQrTileKey), findsNothing);
    expect(find.byKey(_scanTileKey), findsNothing);
  });

  testWidgets('T7 tile hit targets are at least 44x44', (tester) async {
    await tester.pumpWidget(wrapScreen(onMyQr: () {}, onScan: () {}));

    final myQrSize = tester.getSize(find.byKey(_myQrTileKey));
    final scanSize = tester.getSize(find.byKey(_scanTileKey));
    expect(myQrSize.width, greaterThanOrEqualTo(44));
    expect(myQrSize.height, greaterThanOrEqualTo(44));
    expect(scanSize.width, greaterThanOrEqualTo(44));
    expect(scanSize.height, greaterThanOrEqualTo(44));
  });
}
