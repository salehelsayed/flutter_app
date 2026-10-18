import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/features/update_check/application/update_check_controller.dart';
import 'package:flutter_app/features/update_check/application/update_check_service.dart';
import 'package:flutter_app/features/update_check/application/update_check_switch.dart';
import 'package:flutter_app/features/update_check/background/update_check_background_runner.dart';
import 'package:flutter_app/features/update_check/background/update_check_notifier.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/infrastructure/update_check_state_store.dart';

import 'production_journey_controller.dart';
import 'sims_runtime_protocol.dart';

/// Signed-file and controlled-clock fixtures around the production controller.
/// The host still navigates, resumes, dismisses and taps through the suite's UI
/// driver. A controlled background run does not certify a real six-hour wait.
final class ProductionUpdateCheckControls {
  ProductionUpdateCheckControls._() {
    service = UpdateCheckService(store: store, clock: () => _now);
    controller = UpdateCheckController(service: service, clock: () => _now);
  }

  static ProductionUpdateCheckControls? tryCreate() =>
      UpdateCheckSwitch.fromEnvironment().testProfileEnabled
      ? ProductionUpdateCheckControls._()
      : null;

  final store = UpdateCheckStateStore();
  Duration _offset = Duration.zero;
  DateTime get _now => DateTime.now().add(_offset);
  late final UpdateCheckService service;
  late final UpdateCheckController controller;
  bool Function()? readInCall;

  void bind(ProductionJourneyController journey) {
    if (!productionUpdateCheckJourneys.contains(
      journey.invocation.scenarioId,
    )) {
      return;
    }
    journey.bindAction('se41.snapshot', (_) => snapshot());
    journey.bindAction('se41.advance_clock', (arguments) async {
      final seconds = arguments['seconds'];
      if (seconds is! int || seconds < 0 || seconds > 172800) {
        throw ArgumentError('SE41 fixture advance must be 0..172800 seconds.');
      }
      _offset += Duration(seconds: seconds);
      return {'clockMs': _now.millisecondsSinceEpoch};
    });
    journey.bindAction('se41.background', (arguments) async {
      final budgetMs = arguments['budgetMs'];
      if (budgetMs is! int || budgetMs < 0 || budgetMs > 18000) {
        throw ArgumentError('SE41 fixture budget must be 0..18000 ms.');
      }
      final reason = arguments['reason'];
      if (reason is! String || !updateCheckPushReasons.contains(reason)) {
        throw ArgumentError('SE41 fixture requires an exact push reason.');
      }
      final visibility = AppVisibilityAuthority(
        platformBridge: MethodChannelAppVisibilityPlatformBridge(),
      );
      final result =
          await UpdateCheckBackgroundRunner(
            service: service,
            store: store,
            poster: const MethodChannelUpdateNotificationPoster(),
            isForeground: visibility.isForegroundActive,
            // Unbound call state fails closed; Android binds the canonical view.
            isInCall: () async => readInCall?.call() ?? true,
            clock: () => _now,
          ).run(
            reason: reason,
            budget: Duration(milliseconds: budgetMs),
          );
      return result.toWire();
    });
  }

  Future<Map<String, Object?>> snapshot() async {
    final state = await store.load();
    return {
      ...switch (controller.value) {
        UpdateDecisionHard(:final minBuild) => {
          'kind': 'hard',
          'minBuild': minBuild,
        },
        UpdateDecisionSoft(:final latestBuild) => {
          'kind': 'soft',
          'latestBuild': latestBuild,
        },
        UpdateDecisionNone() => {'kind': 'none'},
      },
      'installedBuild': await service.installedBuildNumber(),
      'platform': service.platform?.name,
      'sequence': state.sequence,
      'rank': state.highestAcceptedRank,
      if (state.lastEnvelope != null)
        'acceptedEnvelopeSha256': sha256
            .convert(state.lastEnvelope!)
            .toString(),
      'clockMs': _now.millisecondsSinceEpoch,
      'lastCheckAtMs': state.lastCheckAt?.millisecondsSinceEpoch,
      'notifiedSoftLatestBuild': state.notifiedSoftLatestBuild,
      'notifiedHardMinBuild': state.notifiedHardMinBuild,
      'hardReminderCount': state.hardReminderCount,
      'inCall': readInCall?.call() ?? true,
    };
  }

  void dispose() => controller.dispose();
}
