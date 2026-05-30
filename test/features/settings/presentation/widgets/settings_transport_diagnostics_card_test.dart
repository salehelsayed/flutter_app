import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart';

void main() {
  Widget wrap(TransportMetrics metrics) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF101010),
        body: SingleChildScrollView(
          child: SettingsTransportDiagnosticsCard(metrics: metrics),
        ),
      ),
    );
  }

  testWidgets('refreshes rendered aggregate transport diagnostics', (
    tester,
  ) async {
    final metrics = TransportMetrics();

    await tester.pumpWidget(wrap(metrics));

    expect(find.text('TRANSPORT DIAGNOSTICS (SESSION)'), findsOneWidget);
    expect(find.text('Transport mix (N=0)'), findsOneWidget);
    expect(find.textContaining('Transport mix (N=0): no data'), findsOneWidget);

    metrics
      ..recordTransport('direct')
      ..recordTransport('relay')
      ..recordTransport('wifi')
      ..recordTransport('inbox')
      ..recordTransport('unknown')
      ..recordRung('reuse')
      ..recordRung('local')
      ..recordRung('direct')
      ..recordRung('relay')
      ..recordRung('inbox')
      ..recordRung('failed')
      ..recordSendLatency(transport: 'direct', latencyMs: 10)
      ..recordSendLatency(transport: 'direct', latencyMs: 20)
      ..recordSendLatency(transport: 'direct', latencyMs: 30)
      ..recordSendLatency(transport: 'relay', latencyMs: 80)
      ..updateLanAvailability(
        const LanAvailabilitySnapshot(
          discoveryActive: true,
          discoveredPeerCount: 2,
        ),
      )
      ..recordHolePunchAttempt()
      ..recordHolePunchAttempt()
      ..recordHolePunchSuccess()
      ..recordHolePunchFailure()
      ..recordRelayToDirectUpgrade();

    await tester.tap(
      find.byKey(const ValueKey('settings-transport-debug-refresh')),
    );
    await tester.pump();

    expect(find.text('Transport mix (N=5)'), findsOneWidget);
    expect(find.text('Fallback rungs'), findsOneWidget);
    expect(find.text('Latency (median / p95)'), findsOneWidget);
    expect(find.text('LAN'), findsOneWidget);
    expect(find.text('active'), findsOneWidget);
    expect(find.text('20ms / 30ms (n=3)'), findsOneWidget);
    expect(find.text('80ms / 80ms (n=1)'), findsOneWidget);

    final reportFinder = find.byKey(
      const ValueKey('settings-transport-debug-report'),
    );
    expect(reportFinder, findsOneWidget);
    final report = tester.widget<SelectableText>(reportFinder).data!;

    expect(
      report,
      contains(
        'Transport mix (N=5): 20% direct, 20% relay, 20% wifi, '
        '20% inbox, 20% unknown',
      ),
    );
    expect(
      report,
      contains(
        'Fallback rungs: reuse 1, local_race 1, direct_race 1, '
        'relay_probe 1, inbox_fallback 1, failed 1',
      ),
    );
    expect(report, contains('Median latency: direct 20ms, relay 80ms'));
    expect(report, contains('LAN: discovery active, 2 peers'));
    expect(
      report,
      contains(
        'Hole punch (attempt/success/fail): 2/1/1, '
        'relay->direct upgrades: 1',
      ),
    );

    const rawPeerId =
        '12D3KooWSettingsDiagnosticPeerIdAbcdefghijklmnop1234567890';
    const conversationId = 'conversation-settings-dcutr-secret';
    const multiaddr = '/ip4/10.2.0.1/tcp/4001/p2p/12D3KooWSettingsRelayNode';
    const messageText = 'settings diagnostic private message';
    expect(report, isNot(contains(rawPeerId)));
    expect(report, isNot(contains(conversationId)));
    expect(report, isNot(contains(multiaddr)));
    expect(report, isNot(contains(messageText)));
  });

  testWidgets('renders LAN permission row as ok by default (P4)', (
    tester,
  ) async {
    final metrics = TransportMetrics();
    await tester.pumpWidget(wrap(metrics));

    // Third LAN row is always present; defaults to "ok" (no suspicion).
    expect(find.text('permission'), findsOneWidget);
    expect(find.text('ok'), findsOneWidget);
    expect(find.text('suspected-denied'), findsNothing);
  });

  testWidgets('renders suspected-denied when the P4 flag is set', (
    tester,
  ) async {
    final metrics = TransportMetrics();
    await tester.pumpWidget(wrap(metrics));

    metrics.updateLanAvailability(
      const LanAvailabilitySnapshot(
        discoveryActive: true,
        discoveredPeerCount: 0,
        suspectedPermissionDenied: true,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('settings-transport-debug-refresh')),
    );
    await tester.pump();

    expect(find.text('permission'), findsOneWidget);
    expect(find.text('suspected-denied'), findsOneWidget);

    final report = tester
        .widget<SelectableText>(
          find.byKey(const ValueKey('settings-transport-debug-report')),
        )
        .data!;
    expect(
      report,
      contains('LAN: discovery active, 0 peers, perm: suspected-denied'),
    );
  });
}
