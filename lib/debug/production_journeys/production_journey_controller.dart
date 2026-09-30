import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'foreground_group_push_control.dart';
import 'production_performance_capture.dart';
import 'sims_runtime_protocol.dart';

const foregroundGroupPushJourney = 'production.foreground_group_push';
const notificationOpenJourney = 'production.notification_open';
const notificationSoundJourney = 'production.notification_sound';
const routingSmokeJourney = 'production.routing_smoke';
const groupCatalogCreateJourney = 'production.group_catalog.private_abc_create';
const groupCatalogReactionJourney =
    'production.group_catalog.private_reaction_roundtrip';
const groupCatalogReactionToggleJourney =
    'production.group_catalog.private_reaction_toggle_convergence';
const groupCatalogRemovedReactionJourney =
    'production.group_catalog.private_removed_reaction_rejected';
const productionGroupCatalogJourneys = {
  groupCatalogCreateJourney,
  groupCatalogReactionJourney,
  groupCatalogReactionToggleJourney,
  groupCatalogRemovedReactionJourney,
};
const groupInviteJourney = 'production.group_invite_reliability';
const groupInviteMatrixJourney = 'production.group_invite_status_matrix';
const groupDeletePreservesFriendsJourney =
    'production.group_delete_preserves_friends';
/// Journeys whose topology has a third Android peer, Charlie.
const productionThreePeerJourneys = {
  ...productionGroupCatalogJourneys,
  groupDeletePreservesFriendsJourney,
};
const privateMediaJourney = 'production.private_media_local';
const performanceJourney = 'production.startup_resume_performance';
typedef ProductionJourneyAction =
    Future<Map<String, Object?>> Function(Map<String, Object?> arguments);

/// Runtime invocation and observation transport for production-created controls.
/// Command receipts describe operations; only the host scenario oracle can pass
/// a journey. There is deliberately no build or service-construction operation.
final class ProductionJourneyController {
  ProductionJourneyController({
    required this.directory,
    required this.profileId,
    required this.invocation,
  }) {
    if (invocation.scenarioId == performanceJourney) {
      performanceCapture = ProductionPerformanceCapture();
      bindDisposer(performanceCapture!.dispose);
    }
  }

  static ProductionJourneyController? forInstalledProfile({
    required Directory stateDirectory,
    required bool isDebugMode,
    required bool e2eTestMode,
    required String profileId,
  }) {
    if (!isDebugMode ||
        !e2eTestMode ||
        !{
          'android.e2e.main',
          'android.e2e.performance_relay',
          'android.production_fcm.journey',
          'ios.simulator.app',
        }.contains(profileId)) {
      return null;
    }
    final directory = Directory('${stateDirectory.path}/production-journey');
    final config = File('${directory.path}/runtime-config.json');
    if (!config.existsSync()) return null;
    final invocation = SimsRuntimeInvocation.decode(config.readAsStringSync());
    if (invocation.schema != simsRuntimeConfigSchema ||
        invocation.profileId != profileId ||
        (profileId == 'android.production_fcm.journey' &&
            (invocation.role != 'bob' ||
                !{
                  notificationOpenJourney,
                  notificationSoundJourney,
                }.contains(invocation.scenarioId))) ||
        !{
          foregroundGroupPushJourney,
          notificationOpenJourney,
          notificationSoundJourney,
          routingSmokeJourney,
          privateMediaJourney,
          groupInviteJourney,
          groupInviteMatrixJourney,
          groupDeletePreservesFriendsJourney,
          groupCatalogCreateJourney,
          groupCatalogReactionJourney,
          groupCatalogReactionToggleJourney,
          groupCatalogRemovedReactionJourney,
          performanceJourney,
        }.contains(invocation.scenarioId) ||
        !(productionThreePeerJourneys.contains(invocation.scenarioId)
                ? {'alice', 'bob', 'charlie'}
                : {'alice', 'bob'})
            .contains(invocation.role) ||
        (profileId == 'android.e2e.performance_relay') !=
            (invocation.scenarioId == performanceJourney) ||
        (invocation.scenarioId == performanceJourney &&
            invocation.role != 'alice')) {
      throw StateError('production journey invocation rejected');
    }
    return ProductionJourneyController(
      directory: directory,
      profileId: profileId,
      invocation: invocation,
    );
  }

  final Directory directory;
  final String profileId;
  final SimsRuntimeInvocation invocation;
  ProductionPerformanceCapture? performanceCapture;
  final ForegroundGroupPushControl foregroundPush =
      ForegroundGroupPushControl();
  final Map<String, ProductionJourneyAction> _actions = {};
  final List<void Function()> _disposers = [];
  Timer? _timer;
  bool _runtimeReady = false;
  bool _accepted = false;
  bool _disposed = false;
  bool _polling = false;
  int _lastSequence = 0;
  String? _lastCommand;

  void bindAction(String name, ProductionJourneyAction action) {
    if (_accepted || _disposed || _actions.containsKey(name)) {
      throw StateError('journey action binding rejected');
    }
    _actions[name] = action;
  }

  void markRuntimeReady() {
    if (_disposed) return;
    _runtimeReady = true;
  }

  void bindDisposer(void Function() dispose) {
    if (_accepted || _disposed) throw StateError('disposer binding rejected');
    _disposers.add(dispose);
  }

  Future<void> start() async {
    if (_disposed || _accepted) throw StateError('journey already started');
    await directory.create(recursive: true);
    final consumed = File('${directory.path}/consumed-nonces.json');
    final previous = consumed.existsSync()
        ? (jsonDecode(await consumed.readAsString()) as List).cast<String>()
        : <String>[];
    if (previous.contains(invocation.nonce)) {
      await _write(
        'runtime-ack.json',
        SimsRuntimeAck.reject(
          installedProfileId: profileId,
          invocation: invocation,
          detail: 'stale invocation nonce',
        ).toJson(),
      );
      throw StateError('stale invocation nonce');
    }
    await consumed.writeAsString(
      jsonEncode([...previous, invocation.nonce]),
      flush: true,
    );
    _accepted = true;
    await _write(
      'runtime-ack.json',
      SimsRuntimeAck.accept(invocation).toJson(),
    );
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      unawaited(poll());
    });
  }

  Future<Map<String, Object?>> execute(Map<String, Object?> command) async {
    if (_disposed || !_accepted) throw StateError('journey is not accepted');
    final rawIdentity = command['invocation'];
    if (rawIdentity is! Map) throw StateError('command invocation is missing');
    final received = SimsRuntimeInvocation.fromJson(
      rawIdentity.map((key, value) => MapEntry('$key', value)),
    );
    if (!validateSimsRuntimeAck(
          SimsRuntimeAck.accept(received).toJson(),
          invocation,
        ).accepted ||
        received.schema != simsRuntimeConfigSchema) {
      throw StateError('command invocation mismatch');
    }
    final sequence = command['sequence'];
    if (sequence is! int || sequence != _lastSequence + 1) {
      throw StateError('command sequence rejected');
    }
    final operation = command['operation'];
    final rawArguments = command['arguments'];
    if (operation is! String || rawArguments is! Map) {
      throw StateError('command operation or arguments missing');
    }
    final arguments = rawArguments.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    _lastSequence = sequence;
    if (operation == 'readiness') {
      return {
        'fixtureAccepted': true,
        'productionRuntimeReady': _runtimeReady,
        'foregroundPushBound': foregroundPush.isBound,
        'entrypoint': 'lib/main.dart',
        'scenarioComplete': false,
      };
    }
    if (!_runtimeReady || !foregroundPush.isBound) {
      throw StateError('production runtime is not ready');
    }
    final action = _actions[operation];
    if (action == null) throw StateError('unsupported journey operation');
    return action(arguments);
  }

  Future<void> poll() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      final commandFile = File('${directory.path}/command.json');
      if (!await commandFile.exists()) return;
      final encoded = await commandFile.readAsString();
      if (encoded == _lastCommand) return;
      _lastCommand = encoded;
      Map<String, Object?> command = {};
      try {
        command = (jsonDecode(encoded) as Map).map(
          (key, value) => MapEntry('$key', value),
        );
        final result = await execute(command);
        await _write('command-result.json', {
          'invocation': invocation.toJson(),
          'sequence': command['sequence'],
          'operation': command['operation'],
          'ok': true,
          'result': result,
        });
      } catch (_) {
        await _write('command-result.json', {
          'invocation': invocation.toJson(),
          'sequence': command['sequence'],
          'operation': command['operation'],
          'ok': false,
          'error': 'journey_command_rejected_or_failed',
        });
      }
    } on FileSystemException {
      // An interrupted atomic host staging attempt has no passing receipt.
    } finally {
      _polling = false;
    }
  }

  Future<void> _write(String name, Map<String, Object?> value) async {
    final temporary = File('${directory.path}/$name.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename('${directory.path}/$name');
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    foregroundPush.dispose();
    for (final dispose in _disposers) {
      dispose();
    }
    _disposers.clear();
    _actions.clear();
  }
}
