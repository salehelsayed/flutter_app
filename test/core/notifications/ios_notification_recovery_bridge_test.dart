import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/database/helpers/canonical_notification_badge_state_db_helpers.dart';
import 'package:flutter_app/core/notifications/ios_notification_recovery_bridge.dart';
import 'package:flutter_app/core/notifications/ios_notification_recovery_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(iosNotificationRecoveryChannelName);
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'beginReconciliation' => <String, Object?>{
              'token': 'begin-token',
              'watermark': 17,
              'mailboxAlertLease': null,
            },
            _ => <String, Object?>{'ok': true},
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'channel sends raw identities and validates every native response',
    () async {
      final bridge = MethodChannelIosNotificationRecoveryBridge(
        channel: channel,
      );
      final begin = await bridge.beginReconciliation(' account-a ');
      expect(begin.token, 'begin-token');
      expect(begin.watermark, 17);

      await bridge.commitReconciliation(
        begin: begin,
        accountPeerId: 'account-a',
        canonicalState: CanonicalNotificationBadgeState(
          unreadCount: 1,
          identities: const <CanonicalNotificationIdentity>[
            CanonicalNotificationIdentity(
              lane: CanonicalNotificationLane.group,
              conversationId: 'group-a',
              eventId: 'event-a',
            ),
          ],
        ),
        canonicalStateComplete: false,
      );
      await bridge.retireConversation(
        accountPeerId: 'account-a',
        lane: CanonicalNotificationLane.direct,
        conversationId: 'peer-a',
      );
      await bridge.clearAccount();

      expect(calls.map((call) => call.method), <String>[
        'beginReconciliation',
        'commitReconciliation',
        'retireConversation',
        'clearAccount',
      ]);
      expect(calls.first.arguments, <String, Object?>{
        'accountPeerId': 'account-a',
      });
      final commit = calls[1].arguments as Map<Object?, Object?>;
      expect(commit['token'], 'begin-token');
      expect(commit['watermark'], 17);
      expect(commit['canonicalStateComplete'], isFalse);
      expect(commit['canonicalBadgeCount'], 1);
      expect(commit['identities'], <Map<String, Object?>>[
        <String, Object?>{
          'lane': 'group',
          'conversationId': 'group-a',
          'eventId': 'event-a',
        },
      ]);
      expect(calls[2].arguments, <String, Object?>{
        'accountPeerId': 'account-a',
        'lane': 'direct',
        'conversationId': 'peer-a',
      });
      expect(calls[3].arguments, isEmpty);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => <String, Object?>{
              'token': 'token',
              'watermark': 1,
              'mailboxAlertLease': null,
              'unexpected': true,
            },
          );
      await expectLater(
        bridge.beginReconciliation('account-a'),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'mailbox lease rejects edge whitespace and control-domain drift',
    () async {
      final bridge = MethodChannelIosNotificationRecoveryBridge(
        channel: channel,
      );
      for (final malformed in <Map<String, Object?>>[
        <String, Object?>{
          'token': ' begin-token',
          'watermark': 1,
          'mailboxAlertLease': null,
        },
        <String, Object?>{
          'token': 'begin-token',
          'watermark': 1,
          'mailboxAlertLease': <String, Object?>{
            'token': 'lease-token',
            'accountHash': List<String>.filled(64, 'a').join(),
            'bindingHash': List<String>.filled(64, 'b').join(),
            'requestIdentifier': 'request-with-edge-space ',
            'generation': 1,
            'sequence': 1,
            'phase': 'PREPARED',
          },
        },
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => malformed);
        await expectLater(
          bridge.beginReconciliation('account-a'),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );

  test(
    'coordinator captures begin before load and forwards incomplete state',
    () async {
      final events = <String>[];
      final bridge = _FakeBridge(events: events);
      final coordinator = IosNotificationRecoveryCoordinator(
        platformEnabled: true,
        bridge: bridge,
        loadActiveAccountPeerId: () async {
          events.add('account');
          return 'account-a';
        },
        loadCanonicalState: () async {
          events.add('load');
          return _emptyState;
        },
      );

      await coordinator.reconcile(canonicalStateComplete: false);

      expect(events, <String>['account', 'begin', 'load', 'account', 'commit']);
      expect(bridge.completeness, <bool>[false]);
    },
  );

  test('concurrent triggers coalesce into exactly one final rerun', () async {
    final events = <String>[];
    final firstBegin = Completer<void>();
    final bridge = _FakeBridge(
      events: events,
      firstBeginBarrier: firstBegin.future,
    );
    var loads = 0;
    final coordinator = IosNotificationRecoveryCoordinator(
      platformEnabled: true,
      bridge: bridge,
      loadActiveAccountPeerId: () async => 'account-a',
      loadCanonicalState: () async {
        loads += 1;
        return _emptyState;
      },
    );

    final first = coordinator.reconcile(canonicalStateComplete: false);
    await bridge.firstBeginEntered.future;
    final second = coordinator.reconcile(canonicalStateComplete: false);
    final third = coordinator.reconcile(canonicalStateComplete: true);
    expect(identical(first, second), isTrue);
    expect(identical(first, third), isTrue);
    firstBegin.complete();
    await Future.wait(<Future<void>>[first, second, third]);

    expect(bridge.beginCount, 2);
    expect(loads, 2);
    expect(
      bridge.completeness,
      <bool>[false, false],
      reason: 'a non-exhaustive callback cannot clear sticky incompleteness',
    );
  });

  test(
    'canonical mutation scope defers settlement callbacks until exact close',
    () async {
      final bridge = _FakeBridge(events: <String>[]);
      final coordinator = IosNotificationRecoveryCoordinator(
        platformEnabled: true,
        bridge: bridge,
        loadActiveAccountPeerId: () async => 'account-a',
        loadCanonicalState: () async => _emptyState,
      );

      final scope = await coordinator.beginCanonicalMutation();
      await coordinator.reconcile();
      expect(
        bridge.beginCount,
        1,
        reason: 'the native watermark is captured before canonical mutation',
      );
      expect(
        bridge.completeness,
        isEmpty,
        reason: 'a settlement callback must not commit during ingress',
      );

      await coordinator.endCanonicalMutation(
        scope,
        canonicalStateComplete: false,
      );

      expect(bridge.beginCount, 1);
      expect(bridge.completeness, <bool>[false]);

      await coordinator.reconcile();
      expect(
        bridge.completeness,
        <bool>[false, false],
        reason: 'an ordinary settlement cannot clear sticky incompleteness',
      );

      final exhaustive = await coordinator.beginCanonicalMutation(
        globallyExhaustive: true,
      );
      await coordinator.endCanonicalMutation(
        exhaustive,
        canonicalStateComplete: true,
      );
      expect(bridge.completeness, <bool>[false, false, true]);
    },
  );

  test('scope captures its native watermark before mutation work', () async {
    final events = <String>[];
    final bridge = _FakeBridge(events: events);
    final coordinator = IosNotificationRecoveryCoordinator(
      platformEnabled: true,
      bridge: bridge,
      loadActiveAccountPeerId: () async {
        events.add('account');
        return 'account-a';
      },
      loadCanonicalState: () async {
        events.add('load');
        return _emptyState;
      },
    );

    final scope = await coordinator.beginCanonicalMutation();
    events.add('mutation');
    await coordinator.endCanonicalMutation(scope, canonicalStateComplete: true);

    expect(events, <String>[
      'account',
      'begin',
      'mutation',
      'account',
      'load',
      'account',
      'commit',
    ]);
    expect(bridge.beginCount, 1);
  });

  test('a queued final rerun survives a first-pass failure', () async {
    final firstLoadEntered = Completer<void>();
    final releaseFirstLoad = Completer<void>();
    final bridge = _FakeBridge(events: <String>[]);
    var loads = 0;
    final coordinator = IosNotificationRecoveryCoordinator(
      platformEnabled: true,
      bridge: bridge,
      loadActiveAccountPeerId: () async => 'account-a',
      loadCanonicalState: () async {
        loads += 1;
        if (loads == 1) {
          firstLoadEntered.complete();
          await releaseFirstLoad.future;
          throw StateError('first pass failed');
        }
        return _emptyState;
      },
    );

    final first = coordinator.reconcile(canonicalStateComplete: false);
    await firstLoadEntered.future;
    final queued = coordinator.reconcile(
      canonicalStateComplete: true,
      globallyExhaustive: true,
    );
    releaseFirstLoad.complete();
    await Future.wait(<Future<void>>[first, queued]);

    expect(loads, 2);
    expect(bridge.beginCount, 2);
    expect(
      bridge.completeness,
      <bool>[false, true],
      reason: 'the failed SQL pass consumes its token without completeness',
    );
  });

  test(
    'a mutation overlapping an active pass invalidates that pass monotonically',
    () async {
      final loadEntered = Completer<void>();
      final releaseLoad = Completer<void>();
      final bridge = _FakeBridge(events: <String>[]);
      var loads = 0;
      final coordinator = IosNotificationRecoveryCoordinator(
        platformEnabled: true,
        bridge: bridge,
        loadActiveAccountPeerId: () async => 'account-a',
        loadCanonicalState: () async {
          loads += 1;
          if (loads == 1) {
            loadEntered.complete();
            await releaseLoad.future;
          }
          return _emptyState;
        },
      );

      final activePass = coordinator.reconcile();
      await loadEntered.future;
      final scopeFuture = coordinator.beginCanonicalMutation();
      releaseLoad.complete();
      final scope = await scopeFuture;
      await activePass;

      expect(bridge.completeness, <bool>[false]);

      await coordinator.endCanonicalMutation(
        scope,
        canonicalStateComplete: true,
      );
      expect(bridge.completeness, <bool>[false, true]);
    },
  );

  test(
    'absent account clears native ownership without loading SQLite',
    () async {
      final bridge = _FakeBridge(events: <String>[]);
      var loaded = false;
      final coordinator = IosNotificationRecoveryCoordinator(
        platformEnabled: true,
        bridge: bridge,
        loadActiveAccountPeerId: () async => null,
        loadCanonicalState: () async {
          loaded = true;
          return _emptyState;
        },
      );

      await coordinator.reconcile();

      expect(bridge.clearCount, 1);
      expect(bridge.beginCount, 0);
      expect(loaded, isFalse);
    },
  );

  test('account clear fences callbacks until explicit reactivation', () async {
    final bridge = _FakeBridge(events: <String>[]);
    var accountLoads = 0;
    var activeAccountPeerId = 'account-a';
    final coordinator = IosNotificationRecoveryCoordinator(
      platformEnabled: true,
      bridge: bridge,
      loadActiveAccountPeerId: () async {
        accountLoads += 1;
        return activeAccountPeerId;
      },
      loadCanonicalState: () async => _emptyState,
    );

    await coordinator.clearAccount();
    await coordinator.reconcile();
    final fencedScope = await coordinator.beginCanonicalMutation();
    await coordinator.endCanonicalMutation(
      fencedScope,
      canonicalStateComplete: true,
    );
    expect(bridge.clearCount, 1);
    expect(accountLoads, 1, reason: 'clear remembers the outgoing account');

    final sameAccountScope = await coordinator.beginCanonicalMutation(
      globallyExhaustive: true,
      canReactivateAfterAccountClear: true,
    );
    await coordinator.endCanonicalMutation(
      sameAccountScope,
      canonicalStateComplete: true,
    );
    expect(bridge.beginCount, 0, reason: 'the erased account stays fenced');

    activeAccountPeerId = 'account-b';
    final reactivated = await coordinator.beginCanonicalMutation(
      globallyExhaustive: true,
      canReactivateAfterAccountClear: true,
    );
    await coordinator.endCanonicalMutation(
      reactivated,
      canonicalStateComplete: true,
    );
    expect(accountLoads, 6);
    expect(bridge.beginCount, 1);
  });

  test('concurrent account reactivations join one mutation batch', () async {
    final bridge = _FakeBridge(events: <String>[]);
    final bothReactivationsLoaded = Completer<void>();
    final releaseReactivations = Completer<void>();
    var accountLoads = 0;
    var blockedReactivationLoads = 0;
    var activeAccountPeerId = 'account-a';
    final coordinator = IosNotificationRecoveryCoordinator(
      platformEnabled: true,
      bridge: bridge,
      loadActiveAccountPeerId: () async {
        accountLoads += 1;
        if (accountLoads == 2 || accountLoads == 3) {
          blockedReactivationLoads += 1;
          if (blockedReactivationLoads == 2) {
            bothReactivationsLoaded.complete();
          }
          await releaseReactivations.future;
        }
        return activeAccountPeerId;
      },
      loadCanonicalState: () async => _emptyState,
    );

    await coordinator.clearAccount();
    activeAccountPeerId = 'account-b';
    final first = coordinator.beginCanonicalMutation(
      globallyExhaustive: true,
      canReactivateAfterAccountClear: true,
    );
    final second = coordinator.beginCanonicalMutation(
      globallyExhaustive: true,
      canReactivateAfterAccountClear: true,
    );
    await bothReactivationsLoaded.future;
    releaseReactivations.complete();
    final scopes = await Future.wait([first, second]);

    expect(bridge.beginCount, 1);
    await coordinator.endCanonicalMutation(
      scopes.first,
      canonicalStateComplete: true,
    );
    expect(bridge.completeness, isEmpty);
    await coordinator.endCanonicalMutation(
      scopes.last,
      canonicalStateComplete: true,
    );

    expect(bridge.beginCount, 1);
    expect(bridge.completeness, <bool>[true]);
  });

  test('account clear waits for an already-returned mutation scope', () async {
    final bridge = _FakeBridge(events: <String>[]);
    final coordinator = IosNotificationRecoveryCoordinator(
      platformEnabled: true,
      bridge: bridge,
      loadActiveAccountPeerId: () async => 'account-a',
      loadCanonicalState: () async => _emptyState,
    );

    final scope = await coordinator.beginCanonicalMutation();
    final clear = coordinator.clearAccount();
    await Future<void>.microtask(() {});
    expect(bridge.clearCount, 0);

    await coordinator.endCanonicalMutation(
      scope,
      canonicalStateComplete: false,
    );
    await clear;
    await coordinator.endCanonicalMutation(
      scope,
      canonicalStateComplete: false,
    );

    expect(bridge.clearCount, 1);
    expect(bridge.completeness, isEmpty);
  });

  test(
    'account clear aborts a scope still acquiring its native token',
    () async {
      final releaseBegin = Completer<void>();
      final bridge = _FakeBridge(
        events: <String>[],
        firstBeginBarrier: releaseBegin.future,
      );
      final coordinator = IosNotificationRecoveryCoordinator(
        platformEnabled: true,
        bridge: bridge,
        loadActiveAccountPeerId: () async => 'account-a',
        loadCanonicalState: () async => _emptyState,
      );

      final acquiring = coordinator.beginCanonicalMutation();
      await bridge.firstBeginEntered.future;
      final clear = coordinator.clearAccount();
      releaseBegin.complete();

      await expectLater(acquiring, throwsStateError);
      await clear;
      expect(bridge.clearCount, 1);
      expect(bridge.completeness, isEmpty);
    },
  );

  test(
    'conversation retirement stays exact and Android-disabled is a no-op',
    () async {
      final bridge = _FakeBridge(events: <String>[]);
      final enabled = IosNotificationRecoveryCoordinator(
        platformEnabled: true,
        bridge: bridge,
        loadActiveAccountPeerId: () async => 'account-a',
        loadCanonicalState: () async => _emptyState,
      );
      await enabled.retireConversation(
        lane: CanonicalNotificationLane.group,
        conversationId: 'group-a',
      );
      expect(bridge.retired, <String>['account-a|group|group-a']);

      var accountLoads = 0;
      final disabled = IosNotificationRecoveryCoordinator(
        platformEnabled: false,
        bridge: bridge,
        loadActiveAccountPeerId: () async {
          accountLoads += 1;
          return 'account-a';
        },
        loadCanonicalState: () async => _emptyState,
      );
      await disabled.reconcile();
      final disabledScope = await disabled.beginCanonicalMutation(
        globallyExhaustive: true,
      );
      await disabled.endCanonicalMutation(
        disabledScope,
        canonicalStateComplete: true,
      );
      await disabled.retireConversation(
        lane: CanonicalNotificationLane.direct,
        conversationId: 'peer-a',
      );
      await disabled.clearAccount();
      expect(accountLoads, 0);
      expect(bridge.retired, hasLength(1));
      expect(bridge.clearCount, 0);
    },
  );
}

final _emptyState = CanonicalNotificationBadgeState(
  unreadCount: 0,
  identities: const <CanonicalNotificationIdentity>[],
);

final class _FakeBridge implements IosNotificationRecoveryBridge {
  _FakeBridge({required this.events, this.firstBeginBarrier});

  final List<String> events;
  final Future<void>? firstBeginBarrier;
  final Completer<void> firstBeginEntered = Completer<void>();
  final List<bool> completeness = <bool>[];
  final List<String> retired = <String>[];
  int beginCount = 0;
  int clearCount = 0;

  @override
  Future<IosNotificationReconciliationToken> beginReconciliation(
    String accountPeerId,
  ) async {
    events.add('begin');
    beginCount += 1;
    if (beginCount == 1) {
      if (!firstBeginEntered.isCompleted) firstBeginEntered.complete();
      await firstBeginBarrier;
    }
    return IosNotificationReconciliationToken(
      token: 'token-$beginCount',
      watermark: beginCount,
    );
  }

  @override
  Future<void> commitReconciliation({
    required IosNotificationReconciliationToken begin,
    required String accountPeerId,
    required CanonicalNotificationBadgeState canonicalState,
    required bool canonicalStateComplete,
  }) async {
    events.add('commit');
    completeness.add(canonicalStateComplete);
  }

  @override
  Future<void> consumeMailboxAlertLease({
    required IosNotificationReconciliationToken begin,
    required IosMailboxAlertLease lease,
  }) async {}

  @override
  Future<void> retireConversation({
    required String accountPeerId,
    required CanonicalNotificationLane lane,
    required String conversationId,
  }) async {
    retired.add('$accountPeerId|${lane.name}|$conversationId');
  }

  @override
  Future<void> clearAccount() async {
    clearCount += 1;
  }
}
