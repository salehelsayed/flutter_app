import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'private route protection enter exit and capture events settle exactly once',
    () async {
      final calls = <({String method, Map<String, Object?>? arguments})>[];
      final events = StreamController<Object?>();
      final coordinator = PrivateMediaProtectionCoordinator(
        invokeMethod: (method, arguments) async {
          calls.add((method: method, arguments: arguments));
          return <String, Object?>{
            'ok': true,
            'protectionActive': method == 'enter',
          };
        },
        nativeEvents: events.stream,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await events.close();
      });

      final observed = <PrivateMediaProtectionEvent>[];
      final subscription = coordinator.events.listen(observed.add);
      addTearDown(subscription.cancel);

      final owner = await coordinator.enter();
      expect(owner, isNotNull);
      expect(coordinator.coverActive, isFalse);
      events.add(<String, Object?>{'event': 'screenshot'});
      await Future<void>.delayed(Duration.zero);
      expect(observed, [PrivateMediaProtectionEvent.screenshot]);

      expect(await coordinator.exit(owner!), isTrue);
      expect(
        await coordinator.exit(owner),
        isFalse,
        reason: 'exit is idempotent',
      );
      expect(calls.map((call) => call.method), ['enter', 'exit']);
    },
  );

  test(
    'nested duplicate late and dispose ownership restores ordinary routes fail closed',
    () async {
      final pendingEnter = Completer<Object?>();
      final events = StreamController<Object?>();
      var calls = 0;
      final coordinator = PrivateMediaProtectionCoordinator(
        invokeMethod: (method, arguments) {
          calls++;
          if (method == 'enter') return pendingEnter.future;
          return Future<Object?>.value(<String, Object?>{
            'ok': true,
            'protectionActive': false,
          });
        },
        nativeEvents: events.stream,
      );

      final entering = coordinator.enter();
      expect(coordinator.coverActive, isTrue);
      pendingEnter.complete(<String, Object?>{
        'ok': true,
        'protectionActive': true,
      });
      final owner = await entering;
      expect(owner, isNotNull);
      expect(coordinator.coverActive, isFalse);

      await coordinator.dispose();
      expect(
        coordinator.coverActive,
        isTrue,
        reason: 'disposed state fails covered',
      );
      expect(await coordinator.exit(owner!), isFalse);
      expect(await coordinator.enter(), isNull);
      expect(
        calls,
        2,
        reason: 'dispose releases the one live owner exactly once',
      );
      await events.close();

      final lateEnter = Completer<Object?>();
      final lateEvents = StreamController<Object?>();
      final lateCalls = <String>[];
      final lateCoordinator = PrivateMediaProtectionCoordinator(
        invokeMethod: (method, arguments) async {
          lateCalls.add(method);
          if (method == 'enter') return lateEnter.future;
          return <String, Object?>{'ok': true, 'protectionActive': false};
        },
        nativeEvents: lateEvents.stream,
      );
      final enteringLate = lateCoordinator.enter();
      final disposingLate = lateCoordinator.dispose();
      lateEnter.complete(<String, Object?>{
        'ok': true,
        'protectionActive': true,
      });
      expect(await enteringLate, isNull);
      await disposingLate;
      expect(lateCalls, ['enter', 'exit']);
      await lateEvents.close();
    },
  );

  test(
    'channel payloads diagnostics and failures expose no private metadata',
    () async {
      final payloads = <Map<String, Object?>?>[];
      final nativeEvents = StreamController<Object?>();
      final coordinator = PrivateMediaProtectionCoordinator(
        invokeMethod: (method, arguments) async {
          payloads.add(arguments);
          return <String, Object?>{
            'ok': true,
            'protectionActive': method == 'enter',
          };
        },
        nativeEvents: nativeEvents.stream,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await nativeEvents.close();
      });

      final owner = await coordinator.enter();
      expect(owner, isNotNull);
      expect(owner.toString(), 'PrivateMediaProtectionOwner(redacted)');
      expect(await coordinator.exit(owner!), isTrue);

      final encoded = jsonEncode(payloads);
      for (final forbidden in <String>[
        '/private/path',
        'image/jpeg',
        'caption',
        'duration',
        'expiry',
        'viewOnce',
        'nonce',
        'key',
        'messageId',
        'attachmentId',
      ]) {
        expect(encoded, isNot(contains(forbidden)));
      }
      expect(payloads, hasLength(2));
      expect(
        payloads.every(
          (payload) =>
              payload?.keys.toSet().containsAll({'ownerToken'}) ?? false,
        ),
        isTrue,
      );

      final malformed = PrivateMediaProtectionCoordinator(
        invokeMethod: (method, arguments) async => <String, Object?>{
          'ok': 'yes',
        },
        nativeEvents: StreamController<Object?>().stream,
      );
      addTearDown(malformed.dispose);
      expect(await malformed.enter(), isNull);
      expect(malformed.coverActive, isTrue);
      expect(malformed.toString(), isNot(contains('ownerToken')));
    },
  );

  test(
    'enter and exit require exact result envelopes with no missing or extra fields',
    () async {
      for (final result in <Object?>[
        <String, Object?>{'ok': true},
        <String, Object?>{'ok': true, 'protectionActive': true, 'extra': true},
        <String, Object?>{'ok': true, 'protectionActive': false},
      ]) {
        final coordinator = PrivateMediaProtectionCoordinator(
          invokeMethod: (_, _) async => result,
          nativeEvents: StreamController<Object?>().stream,
        );
        addTearDown(coordinator.dispose);
        expect(await coordinator.enter(), isNull);
        expect(coordinator.coverActive, isTrue);
      }

      var active = false;
      final exact = PrivateMediaProtectionCoordinator(
        invokeMethod: (method, arguments) async {
          active = method == 'enter';
          return <String, Object?>{'ok': true, 'protectionActive': active};
        },
        nativeEvents: StreamController<Object?>().stream,
      );
      addTearDown(exact.dispose);
      final owner = await exact.enter();
      expect(owner, isNotNull);
      expect(active, isTrue);
      expect(await exact.exit(owner!), isTrue);
      expect(active, isFalse);

      for (final malformedExit in <Object?>[
        <String, Object?>{'ok': true},
        <String, Object?>{'ok': true, 'protectionActive': false, 'extra': true},
        <String, Object?>{'ok': true, 'protectionActive': true},
        <String, Object?>{'ok': false, 'protectionActive': false},
      ]) {
        final events = StreamController<Object?>();
        final coordinator = PrivateMediaProtectionCoordinator(
          invokeMethod: (method, arguments) async => method == 'enter'
              ? <String, Object?>{'ok': true, 'protectionActive': true}
              : malformedExit,
          nativeEvents: events.stream,
        );
        final malformedOwner = await coordinator.enter();
        expect(malformedOwner, isNotNull);
        expect(await coordinator.exit(malformedOwner!), isFalse);
        expect(coordinator.coverActive, isTrue);
        await coordinator.dispose();
        await events.close();
      }
    },
  );

  test(
    'capture during enter balances the unpublished owner and a later enter recovers',
    () async {
      final firstEnter = Completer<Object?>();
      final events = StreamController<Object?>();
      final calls = <String>[];
      var enterCount = 0;
      final coordinator = PrivateMediaProtectionCoordinator(
        invokeMethod: (method, arguments) {
          calls.add(method);
          if (method == 'enter') {
            enterCount++;
            if (enterCount == 1) return firstEnter.future;
            return Future<Object?>.value(<String, Object?>{
              'ok': true,
              'protectionActive': true,
            });
          }
          return Future<Object?>.value(<String, Object?>{
            'ok': true,
            'protectionActive': false,
          });
        },
        nativeEvents: events.stream,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await events.close();
      });

      final deniedEnter = coordinator.enter();
      events.add(<String, Object?>{'event': 'captureStarted'});
      await Future<void>.delayed(Duration.zero);
      firstEnter.complete(<String, Object?>{
        'ok': true,
        'protectionActive': true,
      });
      expect(await deniedEnter, isNull);
      expect(coordinator.latchedCriticalEvent, isNull);

      final recoveredOwner = await coordinator.enter();
      expect(recoveredOwner, isNotNull);
      expect(await coordinator.exit(recoveredOwner!), isTrue);
      expect(calls, ['enter', 'exit', 'enter', 'exit']);
    },
  );

  test(
    'unpublished balance validates its invocation snapshot while a published owner exits',
    () async {
      final pendingEnter = Completer<Object?>();
      final unpublishedExit = Completer<Object?>();
      final publishedExit = Completer<Object?>();
      final unpublishedExitInvoked = Completer<void>();
      final events = StreamController<Object?>();
      var enterCount = 0;
      var exitCount = 0;
      final coordinator = PrivateMediaProtectionCoordinator(
        invokeMethod: (method, arguments) {
          if (method == 'enter') {
            enterCount++;
            if (enterCount == 2) return pendingEnter.future;
            return Future<Object?>.value(<String, Object?>{
              'ok': true,
              'protectionActive': true,
            });
          }
          exitCount++;
          if (exitCount == 1) {
            unpublishedExitInvoked.complete();
            return unpublishedExit.future;
          }
          if (exitCount == 2) return publishedExit.future;
          return Future<Object?>.value(<String, Object?>{
            'ok': true,
            'protectionActive': false,
          });
        },
        nativeEvents: events.stream,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await events.close();
      });

      final publishedOwner = (await coordinator.enter())!;
      final deniedEnter = coordinator.enter();
      events.add(<String, Object?>{'event': 'captureStarted'});
      await Future<void>.delayed(Duration.zero);
      pendingEnter.complete(<String, Object?>{
        'ok': true,
        'protectionActive': true,
      });
      await unpublishedExitInvoked.future;

      final exitingPublished = coordinator.exit(publishedOwner);
      unpublishedExit.complete(<String, Object?>{
        'ok': true,
        'protectionActive': true,
      });
      publishedExit.complete(<String, Object?>{
        'ok': true,
        'protectionActive': false,
      });

      expect(await deniedEnter, isNull);
      expect(await exitingPublished, isTrue);
      expect(coordinator.latchedCriticalEvent, isNull);
      expect(
        coordinator.coverActive,
        isFalse,
        reason:
            'the unpublished native exit reported the published owner that '
            'was active at its invocation boundary',
      );

      final recoveredOwner = await coordinator.enter();
      expect(recoveredOwner, isNotNull);
      expect(await coordinator.exit(recoveredOwner!), isTrue);
    },
  );

  test(
    'overlapping unpublished enters serialize native ownership before balance',
    () async {
      final events = StreamController<Object?>(sync: true);
      final nativeOwners = <String>{};
      final balancedStates = <bool>[];
      var maximumNativeOwnerCount = 0;
      final coordinator = PrivateMediaProtectionCoordinator(
        invokeMethod: (method, arguments) {
          final token = arguments!['ownerToken']! as String;
          if (method == 'enter') {
            nativeOwners.add(token);
            if (nativeOwners.length > maximumNativeOwnerCount) {
              maximumNativeOwnerCount = nativeOwners.length;
            }
            return Future<Object?>.value(<String, Object?>{
              'ok': true,
              'protectionActive': true,
            });
          }
          nativeOwners.remove(token);
          final protectionActive = nativeOwners.isNotEmpty;
          balancedStates.add(protectionActive);
          return Future<Object?>.value(<String, Object?>{
            'ok': true,
            'protectionActive': protectionActive,
          });
        },
        nativeEvents: events.stream,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await events.close();
      });

      final first = coordinator.enter();
      final second = coordinator.enter();
      events.add(<String, Object?>{'event': 'captureStarted'});

      expect(
        await Future.wait(<Future<PrivateMediaProtectionOwner?>>[
          first,
          second,
        ]),
        <PrivateMediaProtectionOwner?>[null, null],
      );
      expect(
        maximumNativeOwnerCount,
        lessThanOrEqualTo(1),
        reason:
            'one ownership transaction must settle before another native '
            'enter can become active',
      );
      expect(
        balancedStates,
        everyElement(isFalse),
        reason:
            'any owner that reached native is balanced before the next enter, '
            'so strict result validation sees exact native truth',
      );
      expect(coordinator.latchedCriticalEvent, isNull);
      expect(coordinator.coverActive, isFalse);

      final recoveredOwner = await coordinator.enter();
      expect(recoveredOwner, isNotNull);
      expect(await coordinator.exit(recoveredOwner!), isTrue);
    },
  );

  test(
    'overlapping exits validate the native state at their invocation boundary',
    () async {
      final firstExit = Completer<Object?>();
      final secondExit = Completer<Object?>();
      final events = StreamController<Object?>();
      var exitCount = 0;
      final coordinator = PrivateMediaProtectionCoordinator(
        invokeMethod: (method, arguments) {
          if (method == 'enter') {
            return Future<Object?>.value(<String, Object?>{
              'ok': true,
              'protectionActive': true,
            });
          }
          exitCount++;
          return exitCount == 1 ? firstExit.future : secondExit.future;
        },
        nativeEvents: events.stream,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await events.close();
      });

      final firstOwner = (await coordinator.enter())!;
      final secondOwner = (await coordinator.enter())!;
      final exitingFirst = coordinator.exit(firstOwner);
      final exitingSecond = coordinator.exit(secondOwner);
      firstExit.complete(<String, Object?>{
        'ok': true,
        'protectionActive': true,
      });
      secondExit.complete(<String, Object?>{
        'ok': true,
        'protectionActive': false,
      });
      expect(await Future.wait(<Future<bool>>[exitingFirst, exitingSecond]), [
        isTrue,
        isTrue,
      ]);
      expect(coordinator.coverActive, isFalse);
    },
  );

  test(
    'overlapping pending enters keep cover sticky and dispose awaits balanced late ownership',
    () async {
      final firstEnter = Completer<Object?>();
      final secondEnter = Completer<Object?>();
      final calls = <String>[];
      final nativeOwners = <String>{};
      var enterCount = 0;
      final coordinator = PrivateMediaProtectionCoordinator(
        invokeMethod: (method, arguments) {
          calls.add(method);
          final token = arguments!['ownerToken']! as String;
          if (method == 'enter') {
            nativeOwners.add(token);
            enterCount++;
            return enterCount == 1 ? firstEnter.future : secondEnter.future;
          }
          nativeOwners.remove(token);
          return Future<Object?>.value(<String, Object?>{
            'ok': true,
            'protectionActive': nativeOwners.isNotEmpty,
          });
        },
        nativeEvents: StreamController<Object?>().stream,
      );

      var firstSettlements = 0;
      var secondSettlements = 0;
      final first = coordinator.enter().whenComplete(() => firstSettlements++);
      final second = coordinator.enter().whenComplete(
        () => secondSettlements++,
      );
      expect(coordinator.coverActive, isTrue);

      firstEnter.complete(<String, Object?>{
        'ok': true,
        'protectionActive': true,
      });
      final firstOwner = await first;
      expect(firstOwner, isNotNull);
      expect(
        coordinator.coverActive,
        isTrue,
        reason: 'the second unresolved native enter still requires a cover',
      );

      var disposeCompleted = false;
      final disposing = coordinator.dispose().whenComplete(
        () => disposeCompleted = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        disposeCompleted,
        isFalse,
        reason: 'dispose must not outrun an overlapping native enter',
      );

      secondEnter.complete(<String, Object?>{
        'ok': true,
        'protectionActive': true,
      });
      expect(await second, isNull);
      await disposing;
      expect(firstSettlements, 1);
      expect(secondSettlements, 1);
      expect(calls.where((method) => method == 'enter'), hasLength(2));
      expect(calls.where((method) => method == 'exit'), hasLength(2));
      expect(coordinator.coverActive, isTrue);
    },
  );
}
