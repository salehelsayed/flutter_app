/// Plan 375 (GAP-N08) — TC-375-06 / TC-375-07.
///
/// One live Android binding/role-epoch readiness resolver gates the paired
/// `opaque_wake_v1`/`wake_outcome_v1` capabilities, the completed-outcome
/// producer and the outcome drainer together; primary and active-linked
/// Android registration use exact capability sets and one coordinator through
/// every retry. The pair is indivisible and default false.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/notifications/android_opaque_wake_readiness.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';
import 'package:flutter_app/core/notifications/ios_nse_inbox_projection.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_drainer.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

/// Mutable native/secure state driving the live resolver; the "epoch" is the
/// exact (native binding, secure binding, enabled, version) tuple.
final class _AndroidConsumerState {
  String? nativeBinding = 'v1:binding-a';
  String? secureBinding = 'v1:binding-a';
  bool recoveryWorkEnabled = true;
  bool mutationInProgress = false;
  int version = androidFixedWakeConsumerReadinessVersion;
  bool throwOnSnapshotRead = false;
  bool throwOnSecureRead = false;
  int snapshotReads = 0;
  int secureReads = 0;

  Future<AndroidOpaqueWakeConsumerSnapshot?> readSnapshot() async {
    snapshotReads++;
    if (throwOnSnapshotRead) throw StateError('native read failed');
    final binding = nativeBinding;
    return AndroidOpaqueWakeConsumerSnapshot(
      currentBinding: binding,
      recoveryWorkEnabled: recoveryWorkEnabled,
      authorityMutationInProgress: mutationInProgress,
      fixedWakeConsumerVersion: version,
    );
  }

  Future<String?> readSecureBinding() async {
    secureReads++;
    if (throwOnSecureRead) throw StateError('secure read failed');
    return secureBinding;
  }

  AndroidOpaqueWakeReadiness resolver({required bool admissionEnabled}) =>
      AndroidOpaqueWakeReadiness(
        admissionEnabled: admissionEnabled,
        readConsumerSnapshot: readSnapshot,
        readCurrentSecureBinding: readSecureBinding,
      );
}

/// Any touch proves the drain passed the readiness gate.
final class _ExplodingDatabase implements Database {
  int touches = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    touches++;
    throw StateError('drain touched the database while gated');
  }
}

class _FakeBridge extends Bridge {
  _FakeBridge({this.nodePeerId = 'linked-physical-peer'});

  final String nodePeerId;
  final List<Map<String, dynamic>> registerFrames = [];
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final cmd = request['cmd'] as String;
    if (cmd == 'inbox:register_token') {
      registerFrames.add(
        (request['payload'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      );
      return jsonEncode({'ok': true, 'status': 'registered'});
    }
    if (cmd == 'node:status' || cmd == 'node:start') {
      return jsonEncode({
        'ok': true,
        'peerId': nodePeerId,
        'isStarted': true,
        'listenAddresses': <String>[],
        'circuitAddresses': <String>[],
        'connections': <dynamic>[],
        'relayState': 'online',
        'healthyRelayCount': 1,
        'watchdogRestartCount': 0,
      });
    }
    if (cmd == 'inbox:retrieve_pending') {
      return jsonEncode({'ok': true, 'messages': [], 'hasMore': false});
    }
    return jsonEncode({'ok': true});
  }
}

void main() {
  test(
    'TC-375-06 live Android readback enables and retires one paired admission epoch',
    () async {
      final state = _AndroidConsumerState();

      // The pair is default false: without the one build admission no read
      // ever qualifies, and the qualified state is never even consulted.
      final defaultOff = state.resolver(admissionEnabled: false);
      expect(await defaultOff.isConsumerReady(), isFalse);
      expect(state.snapshotReads, 0);

      // One resolver instance backs the platform readiness; producer, drainer
      // and registration all read it live through the same closures the
      // production bootstrap composes.
      final resolver = state.resolver(admissionEnabled: true);
      final readiness = OpaqueWakePlatformConsumerReadiness(
        admissionEnabled: true,
        readAndroidConsumer: resolver.isConsumerReady,
      );
      Future<bool> producerRead() => readiness.isReadyFor('android');
      Future<bool> drainerRead() => readiness.isReadyFor('android');
      Future<bool> registrationRead() => readiness.isReadyFor('android');

      // Construct while UNREADY (native disabled), then qualify later: all
      // three enable together with no reconstruction — the resolver is live,
      // not a constructor boolean.
      state.recoveryWorkEnabled = false;
      expect(await producerRead(), isFalse);
      expect(await drainerRead(), isFalse);
      expect(await registrationRead(), isFalse);
      state.recoveryWorkEnabled = true;
      expect(await producerRead(), isTrue);
      expect(await drainerRead(), isTrue);
      expect(await registrationRead(), isTrue);

      // Binding rotation and read failure disable all three together.
      state.nativeBinding = 'v1:binding-b';
      expect(await producerRead(), isFalse);
      expect(await drainerRead(), isFalse);
      expect(await registrationRead(), isFalse);
      state.secureBinding = 'v1:binding-b';
      expect(await registrationRead(), isTrue);
      state.throwOnSnapshotRead = true;
      expect(await producerRead(), isFalse);
      expect(await drainerRead(), isFalse);
      expect(await registrationRead(), isFalse);
      state.throwOnSnapshotRead = false;
      state.throwOnSecureRead = true;
      expect(await registrationRead(), isFalse);
      state.throwOnSecureRead = false;

      // A stale/future consumer version or an in-flight authority mutation is
      // never ready: a binary without the exact fixed ingress family cannot
      // qualify the pair.
      state.version = androidFixedWakeConsumerReadinessVersion + 1;
      expect(await registrationRead(), isFalse);
      state.version = androidFixedWakeConsumerReadinessVersion;
      state.mutationInProgress = true;
      expect(await registrationRead(), isFalse);
      state.mutationInProgress = false;
      expect(await registrationRead(), isTrue);

      // Drain kicks read the same epoch live: while unready the drain returns
      // without touching durable custody; once ready the same composition
      // proceeds into the repository (proven by the guarded fake database).
      final database = _ExplodingDatabase();
      final drain = NotificationCompletedOutcomeDrainComposition(
        database: database as Database,
        sendOutcome: ({required correlation}) async => <String, dynamic>{},
        admissionEnabled: true,
        readPlatformConsumerReady: drainerRead,
      ).drain;
      expect(drain, isNotNull);
      state.recoveryWorkEnabled = false;
      await drain!();
      expect(database.touches, 0);
      state.recoveryWorkEnabled = true;
      await drain().then<void>((_) {}, onError: (Object _) {});
      expect(database.touches, greaterThan(0));

      // Registration reads the live epoch immediately before the bridge send:
      // the same service emits the pair only while the current read is ready.
      final bridge = _FakeBridge();
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        readOpaqueWakePlatformConsumerReadiness: readiness.isReadyFor,
      );
      addTearDown(service.dispose);
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'primary-peer');
      state.recoveryWorkEnabled = false;
      expect(await service.registerPushToken('token-1', 'android'), isTrue);
      expect(
        bridge.registerFrames.last['capabilities'],
        [directReactionPushCapability, groupReactionPushCapability],
        reason: 'an unready epoch never advertises a half or full pair',
      );
      state.recoveryWorkEnabled = true;
      expect(await service.registerPushToken('token-1', 'android'), isTrue);
      expect(
        bridge.registerFrames.last['capabilities'],
        [
          directReactionPushCapability,
          groupReactionPushCapability,
          opaqueWakePushCapability,
          wakeOutcomePushCapability,
        ],
        reason: 'the pair is indivisible and rides one admitted frame',
      );

      // A held bridge send crossing a binding/role cutover: the coordinator
      // fences the old epoch, joins the in-flight attempt, and the accepted
      // ambiguous A frame is replaced by one current-policy B frame before
      // the new epoch reports healthy.
      final holdA = Completer<void>();
      final attempts = <String>[];
      var epoch = 'A';
      final coordinator = PushRegistrationCoordinator(
        requestPermission: () async => true,
        registerPushToken: () async {
          final attemptEpoch = epoch;
          attempts.add(attemptEpoch);
          if (attemptEpoch == 'A') await holdA.future;
          return RegisterPushTokenResult.success;
        },
        tokenRefreshStream: const Stream<String>.empty(),
      );
      addTearDown(coordinator.dispose);
      final started = coordinator.ensureStarted();
      await Future<void>.delayed(Duration.zero);
      expect(attempts, ['A'], reason: 'the A frame is dispatched and held');
      // The cutover fences the old authority BEFORE identity replacement...
      coordinator.beginAccountBindingCutover();
      epoch = 'B';
      final cutover = coordinator.completeAccountBindingCutover();
      // ...and the held A send is joined, never treated as cancellable: only
      // after it settles does the replacement B frame go out.
      await Future<void>.delayed(Duration.zero);
      expect(attempts, ['A'], reason: 'B must join, not overtake, the held A');
      holdA.complete();
      await started;
      await cutover;
      expect(
        attempts,
        ['A', 'B'],
        reason:
            'the stale accepted route is withdrawn/replaced by exactly '
            'one current-policy frame before the new epoch reports healthy',
      );
    },
  );

  test(
    'TC-375-07 primary and linked Android serialize one qualified physical route through every retry',
    () async {
      final state = _AndroidConsumerState()
        ..nativeBinding = 'v1:binding-linked'
        ..secureBinding = 'v1:binding-linked';
      final resolver = state.resolver(admissionEnabled: true);
      final readiness = OpaqueWakePlatformConsumerReadiness(
        admissionEnabled: true,
        readAndroidConsumer: resolver.isConsumerReady,
      );

      // Active-linked route: the physical relay route must be the qualified
      // linked transport peer. A node running any other peer sends zero
      // frames and never falls back to the primary key.
      final wrongPeerBridge = _FakeBridge(nodePeerId: 'some-other-peer');
      final wrongPeerService = P2PServiceImpl(
        bridge: wrongPeerBridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        requiredTransportPeerId: () => 'linked-physical-peer',
        logicalAccountPeerId: () => 'account-peer',
        readOpaqueWakePlatformConsumerReadiness: readiness.isReadyFor,
      );
      addTearDown(wrongPeerService.dispose);
      await wrongPeerService.startNodeCore(
        'cHJpdmF0ZWtleXRlc3Q=',
        'some-other-peer',
      );
      expect(
        await wrongPeerService.registerPushToken('token-l', 'android'),
        isFalse,
      );
      expect(wrongPeerBridge.registerFrames, isEmpty);

      // Qualified linked route with a ready pair: the exact capability set is
      // the pair only — never the inherited primary reaction defaults.
      final linkedBridge = _FakeBridge();
      final linkedService = P2PServiceImpl(
        bridge: linkedBridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        requiredTransportPeerId: () => 'linked-physical-peer',
        logicalAccountPeerId: () => 'account-peer',
        readOpaqueWakePlatformConsumerReadiness: readiness.isReadyFor,
      );
      addTearDown(linkedService.dispose);
      await linkedService.startNodeCore(
        'cHJpdmF0ZWtleXRlc3Q=',
        'linked-physical-peer',
      );
      expect(
        await linkedService.registerPushToken('token-l', 'android'),
        isTrue,
      );
      expect(linkedBridge.registerFrames, hasLength(1));
      expect(
        linkedBridge.registerFrames.single['capabilities'],
        [opaqueWakePushCapability, wakeOutcomePushCapability],
        reason: 'linked Android registers exactly the pair, nothing else',
      );

      // An unready pair on the linked route registers zero times: a linked
      // frame with no usable capability must never be sent, and reaction
      // capability is never silently advertised to widen fixed selection.
      state.recoveryWorkEnabled = false;
      expect(
        await linkedService.registerPushToken('token-l', 'android'),
        isFalse,
      );
      expect(linkedBridge.registerFrames, hasLength(1));
      state.recoveryWorkEnabled = true;

      // Every retry funnels through the one installed coordinator owner and
      // re-reads the live policy: the linked frame after re-qualification is
      // again exactly the pair on the same physical route.
      var coordinatorRetries = 0;
      linkedService.installPushRegistrationRetryNow(() async {
        coordinatorRetries++;
        await linkedService.registerPushToken('token-l', 'android');
      });
      linkedBridge.onRelayStateChanged?.call({
        'relayState': 'degraded',
        'healthyRelayCount': 0,
        'watchdogRestartCount': 0,
      });
      linkedBridge.onRelayStateChanged?.call({
        'relayState': 'online',
        'healthyRelayCount': 1,
        'watchdogRestartCount': 0,
      });
      for (var i = 0; i < 100 && coordinatorRetries == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(coordinatorRetries, 1);
      expect(linkedBridge.registerFrames, hasLength(2));
      expect(linkedBridge.registerFrames.last['capabilities'], [
        opaqueWakePushCapability,
        wakeOutcomePushCapability,
      ]);

      // Ordinary primary startup/refresh keeps the incumbent admitted set:
      // direct+group reactions, plus the pair only while admitted-and-ready.
      final primaryBridge = _FakeBridge();
      final primaryService = P2PServiceImpl(
        bridge: primaryBridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        readOpaqueWakePlatformConsumerReadiness: readiness.isReadyFor,
      );
      addTearDown(primaryService.dispose);
      await primaryService.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'primary');
      expect(
        await primaryService.registerPushToken('token-p', 'android'),
        isTrue,
      );
      expect(primaryBridge.registerFrames.single['capabilities'], [
        directReactionPushCapability,
        groupReactionPushCapability,
        opaqueWakePushCapability,
        wakeOutcomePushCapability,
      ]);

      // The default-off production seam admits nothing: with no injected
      // readiness the incumbent reaction pair is the entire primary set.
      final darkBridge = _FakeBridge();
      final darkService = P2PServiceImpl(
        bridge: darkBridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );
      addTearDown(darkService.dispose);
      await darkService.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'primary');
      expect(await darkService.registerPushToken('token-d', 'android'), isTrue);
      expect(darkBridge.registerFrames.single['capabilities'], [
        directReactionPushCapability,
        groupReactionPushCapability,
      ]);
      expect(kWakeOutcomeCoordinatorAdmissionEnabled, isFalse);
    },
  );
}
