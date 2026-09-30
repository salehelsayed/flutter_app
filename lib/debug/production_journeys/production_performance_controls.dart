import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/debug/e2e_test_mode.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import 'production_journey_controller.dart';

/// Read-only production timing/state observations and the original benchmarks'
/// explicit hot-node-start and relay-disconnect protocol operations. Ordinary
/// launch/background/resume remain OS UI actions. Never calls lifecycle owners.
void bindProductionPerformanceControls({
  required ProductionJourneyController controller,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
}) {
  if (controller.invocation.scenarioId != performanceJourney) return;
  final capture = controller.performanceCapture!;
  final used = <String>{};
  String? window;
  var recoveryDisconnectCompleted = false;
  var recoveryLossObserved = false;
  Map<String, Object?> snapshot() {
    // Retain the host-observed loss prerequisite across autonomous recovery.
    // M-Sim-2 observes loss once, then calls health/inbox even if the relay
    // reconnects before those calls. An unobserved fault is never sufficient.
    if (window == 'recovery' &&
        recoveryDisconnectCompleted &&
        p2pService.currentState.badgeReadinessState !=
            BadgeReadinessState.onlineDotted) {
      recoveryLossObserved = true;
    }
    return {
      ...capture.snapshot(),
      'profileId': controller.profileId,
      'localDiscoveryDisabled': kDisableLocalDiscovery,
      'runId': controller.invocation.runId,
      'role': controller.invocation.role,
      'nonce': controller.invocation.nonce,
      'nodeStarted': p2pService.currentState.isStarted,
      'nodePeerId': p2pService.currentState.peerId,
      'sendReady': p2pService.currentState.sendCapabilityReady,
      'inboxReady': p2pService.currentState.inboxCapabilityReady,
      'badge': p2pService.currentState.badgeReadinessState.name,
    };
  }

  capture.bindPausedObserver(snapshot);
  controller.bindAction('performance_snapshot', (_) async => snapshot());
  controller.bindAction('performance_paused_snapshot', (_) async {
    if (window != 'healthy') {
      throw StateError('healthy resume observation prerequisite rejected');
    }
    return capture.pausedSnapshot();
  });
  controller.bindAction('performance_begin', (args) async {
    final name = args['window'];
    if (name is! String ||
        !{
          'hot-core',
          'hot-node',
          'healthy',
          'degraded',
          'extended',
          'recovery',
        }.contains(name) ||
        !used.add(name) ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        p2pService.currentState.badgeReadinessState !=
            BadgeReadinessState.onlineDotted) {
      throw StateError('performance window prerequisite rejected');
    }
    window = name;
    recoveryDisconnectCompleted = false;
    recoveryLossObserved = false;
    capture.clearPausedSnapshot();
    return snapshot();
  });
  controller.bindAction('performance_hot_start', (_) async {
    final current = window;
    if (!{'hot-core', 'hot-node'}.contains(current) ||
        !used.add('operation-$current') ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      throw StateError('hot-start protocol prerequisite rejected');
    }
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity missing');
    final started = current == 'hot-core'
        ? await p2pService.startNodeCore(identity.privateKey, identity.peerId)
        : await p2pService.startNode(identity.privateKey, identity.peerId);
    return {'started': started, ...snapshot()};
  });
  controller.bindAction('performance_disconnect_relay', (_) async {
    if (!{'degraded', 'recovery'}.contains(window) ||
        !used.add('disconnect-$window') ||
        WidgetsBinding.instance.lifecycleState !=
            (window == 'degraded'
                ? AppLifecycleState.paused
                : AppLifecycleState.resumed) ||
        p2pService.currentState.badgeReadinessState !=
            BadgeReadinessState.onlineDotted) {
      throw StateError('paused healthy relay prerequisite rejected');
    }
    final relays = p2pService.currentState.connections
        .where((c) => c.isRelay && c.status == 'connected')
        .map((c) => c.peerId)
        .toSet();
    if (relays.isEmpty) throw StateError('no actual connected relay');
    for (final peer in relays) {
      await bridge.send(
        jsonEncode({
          'cmd': 'peer:disconnect',
          'payload': {'peerId': peer},
        }),
      );
    }
    if (window == 'recovery') recoveryDisconnectCompleted = true;
    return {'disconnectedRelayCount': relays.length, ...snapshot()};
  });
  controller.bindAction('performance_recover', (_) async {
    if (window != 'recovery' ||
        !used.contains('disconnect-recovery') ||
        !recoveryLossObserved ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        !used.add('recover')) {
      throw StateError('degraded foreground recovery prerequisite rejected');
    }
    await p2pService.performImmediateHealthCheck();
    await p2pService.drainOfflineInbox();
    return snapshot();
  });
}
