import 'dart:async';

import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/ios_voip_token_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 8, 31, 9);
final _tokenA = List<String>.filled(64, 'a').join();
final _tokenB = List<String>.filled(64, 'b').join();

Map<String, Object?> _snapshot({
  required String token,
  required int refreshEpoch,
  bool invalidated = false,
  String environment = 'development',
}) => <String, Object?>{
  'version': 1,
  'token': token,
  'environment': environment,
  'topic': 'com.mknoon.app.voip',
  'capabilityVersion': 1,
  'refreshEpoch': refreshEpoch,
  'invalidated': invalidated,
};

void main() {
  test('publishes, suppresses duplicate events, rotates with prior-epoch CAS, '
      'and invalidates only iOS VoIP', () async {
    final native = _TokenNative()
      ..current = _snapshot(token: _tokenA, refreshEpoch: 11);
    final authority = _Authority();
    final coordinator = _coordinator(native, authority);
    final invalidations = <void>[];
    final invalidationSubscription = coordinator.authorityInvalidations.listen(
      invalidations.add,
    );

    expect(await coordinator.publishForAuthenticatedGraph(), isTrue);
    expect(authority.publications, hasLength(1));
    expect(authority.publications.single.kind, CallTokenKind.iosVoip);
    expect(authority.publications.single.platform, CallEndpointPlatform.ios);
    expect(authority.publications.single.environment, 'sandbox');
    expect(authority.publications.single.refreshEpoch, 11);
    expect(
      authority.publications.single.expiresAtMs,
      _now.add(const Duration(days: 30)).millisecondsSinceEpoch,
    );

    native.events.add(_snapshot(token: _tokenA, refreshEpoch: 11));
    await _settle();
    expect(authority.publications, hasLength(1));

    native.events.add(_snapshot(token: _tokenB, refreshEpoch: 12));
    await _until(() => authority.publications.length == 2);
    expect(authority.publications.last.refreshEpoch, 12);
    expect(authority.revocations, <({CallTokenKind kind, int? epoch})>[
      (kind: CallTokenKind.iosVoip, epoch: 11),
    ]);

    native.events.add(
      _snapshot(token: '', refreshEpoch: 12, invalidated: true),
    );
    await _until(() => invalidations.length == 1);
    expect(authority.revocations, <({CallTokenKind kind, int? epoch})>[
      (kind: CallTokenKind.iosVoip, epoch: 11),
      (kind: CallTokenKind.iosVoip, epoch: 12),
    ]);
    expect(
      authority.revocations.any(
        (revoke) => revoke.kind == CallTokenKind.standardCall,
      ),
      isFalse,
    );
    expect(await coordinator.publishForAuthenticatedGraph(), isFalse);

    await coordinator.close();
    await invalidationSubscription.cancel();
    await native.events.close();
    expect(authority.revocations, hasLength(2));
  });

  test(
    'authenticated resume refreshes expiry without rotating epoch',
    () async {
      final native = _TokenNative()
        ..current = _snapshot(
          token: _tokenA,
          refreshEpoch: 21,
          environment: 'production',
        );
      final authority = _Authority();
      var now = _now;
      final coordinator = IosVoipTokenCoordinator(
        invokeMethod: native.invoke,
        nativeEvents: native.events.stream,
        authorityClient: authority,
        clock: () => now,
      );

      expect(await coordinator.publishForAuthenticatedGraph(), isTrue);
      now = now.add(const Duration(days: 1));
      expect(await coordinator.publishForAuthenticatedGraph(), isTrue);

      expect(authority.publications, hasLength(2));
      expect(
        authority.publications.map((record) => record.refreshEpoch),
        <int?>[21, 21],
      );
      expect(
        authority.publications.last.expiresAtMs,
        greaterThan(authority.publications.first.expiresAtMs),
      );
      expect(authority.revocations, isEmpty);

      await coordinator.close();
      await native.events.close();
    },
  );

  test('no native token keeps endpoint publication fail closed', () async {
    final native = _TokenNative();
    final authority = _Authority();
    final coordinator = IosVoipTokenCoordinator(
      invokeMethod: native.invoke,
      nativeEvents: native.events.stream,
      authorityClient: authority,
      clock: () => _now,
      waitForInitialSnapshotTimeout: (_) async {},
    );

    expect(await coordinator.publishForAuthenticatedGraph(), isFalse);
    expect(authority.publications, isEmpty);
    expect(authority.revocations, isEmpty);

    await coordinator.close();
    await native.events.close();
  });

  test(
    'first authenticated publication waits for the asynchronous PushKit snapshot',
    () async {
      final native = _TokenNative();
      final authority = _Authority();
      final timeout = Completer<void>();
      final coordinator = IosVoipTokenCoordinator(
        invokeMethod: native.invoke,
        nativeEvents: native.events.stream,
        authorityClient: authority,
        clock: () => _now,
        initialSnapshotWait: const Duration(seconds: 5),
        waitForInitialSnapshotTimeout: (_) => timeout.future,
      );

      var completed = false;
      final publication = coordinator.publishForAuthenticatedGraph().then((
        result,
      ) {
        completed = true;
        return result;
      });
      await _until(() => native.calls.isNotEmpty);
      await _settle();
      expect(completed, isFalse);
      expect(authority.publications, isEmpty);

      native.events.add(_snapshot(token: _tokenA, refreshEpoch: 23));

      expect(await publication, isTrue);
      expect(authority.publications, hasLength(1));
      expect(authority.publications.single.refreshEpoch, 23);

      if (!timeout.isCompleted) timeout.complete();
      await coordinator.close();
      await native.events.close();
    },
  );

  test(
    'first snapshot wait is bounded and timeout stays fail closed',
    () async {
      final native = _TokenNative();
      final authority = _Authority();
      final timeout = Completer<void>();
      final waitStarted = Completer<void>();
      final coordinator = IosVoipTokenCoordinator(
        invokeMethod: native.invoke,
        nativeEvents: native.events.stream,
        authorityClient: authority,
        clock: () => _now,
        initialSnapshotWait: const Duration(seconds: 5),
        waitForInitialSnapshotTimeout: (_) {
          if (!waitStarted.isCompleted) waitStarted.complete();
          return timeout.future;
        },
      );

      final publication = coordinator.publishForAuthenticatedGraph();
      await waitStarted.future;
      timeout.complete();
      native.events.add(_snapshot(token: _tokenA, refreshEpoch: 24));

      expect(await publication, isFalse);
      await _settle();
      expect(authority.publications, isEmpty);

      await coordinator.close();
      await native.events.close();
    },
  );

  test(
    'first publication waits past a persisted invalidation for a newer token',
    () async {
      final native = _TokenNative()
        ..current = _snapshot(token: '', refreshEpoch: 25, invalidated: true);
      final authority = _Authority();
      final timeout = Completer<void>();
      final coordinator = IosVoipTokenCoordinator(
        invokeMethod: native.invoke,
        nativeEvents: native.events.stream,
        authorityClient: authority,
        clock: () => _now,
        initialSnapshotWait: const Duration(seconds: 5),
        waitForInitialSnapshotTimeout: (_) => timeout.future,
      );

      var completed = false;
      final publication = coordinator.publishForAuthenticatedGraph().then((
        result,
      ) {
        completed = true;
        return result;
      });
      await _until(() => native.calls.isNotEmpty);
      await _settle();
      expect(completed, isFalse);
      expect(authority.publications, isEmpty);
      expect(authority.revocations, isEmpty);

      native.events.add(_snapshot(token: _tokenA, refreshEpoch: 26));

      expect(await publication, isTrue);
      expect(authority.publications, hasLength(1));
      expect(authority.publications.single.refreshEpoch, 26);
      expect(authority.revocations, isEmpty);

      if (!timeout.isCompleted) timeout.complete();
      await coordinator.close();
      await native.events.close();
    },
  );

  test(
    'persisted invalidation timeout revokes its epoch and rejects a late token',
    () async {
      final native = _TokenNative()
        ..current = _snapshot(token: '', refreshEpoch: 27, invalidated: true);
      final authority = _Authority();
      final timeout = Completer<void>();
      final waitStarted = Completer<void>();
      final coordinator = IosVoipTokenCoordinator(
        invokeMethod: native.invoke,
        nativeEvents: native.events.stream,
        authorityClient: authority,
        clock: () => _now,
        initialSnapshotWait: const Duration(seconds: 5),
        waitForInitialSnapshotTimeout: (_) {
          if (!waitStarted.isCompleted) waitStarted.complete();
          return timeout.future;
        },
      );

      final publication = coordinator.publishForAuthenticatedGraph();
      await waitStarted.future;
      timeout.complete();
      native.events.add(_snapshot(token: _tokenA, refreshEpoch: 28));

      expect(await publication, isFalse);
      await _settle();
      expect(authority.publications, isEmpty);
      expect(authority.revocations, <({CallTokenKind kind, int? epoch})>[
        (kind: CallTokenKind.iosVoip, epoch: 27),
      ]);

      await coordinator.close();
      await native.events.close();
    },
  );

  test(
    'pre-publication invalidation resets an earlier callable snapshot signal',
    () async {
      final native = _TokenNative()
        ..current = _snapshot(token: _tokenA, refreshEpoch: 29);
      final authority = _Authority();
      final timeout = Completer<void>();
      final coordinator = IosVoipTokenCoordinator(
        invokeMethod: native.invoke,
        nativeEvents: native.events.stream,
        authorityClient: authority,
        clock: () => _now,
        initialSnapshotWait: const Duration(seconds: 5),
        waitForInitialSnapshotTimeout: (_) => timeout.future,
      );

      await coordinator.start();
      native.events.add(
        _snapshot(token: '', refreshEpoch: 29, invalidated: true),
      );
      await _settle();

      var completed = false;
      final publication = coordinator.publishForAuthenticatedGraph().then((
        result,
      ) {
        completed = true;
        return result;
      });
      await _settle();
      expect(completed, isFalse);
      expect(authority.publications, isEmpty);
      expect(authority.revocations, isEmpty);

      native.events.add(_snapshot(token: _tokenB, refreshEpoch: 30));

      expect(await publication, isTrue);
      expect(authority.publications, hasLength(1));
      expect(authority.publications.single.refreshEpoch, 30);
      expect(authority.revocations, isEmpty);

      if (!timeout.isCompleted) timeout.complete();
      await coordinator.close();
      await native.events.close();
    },
  );

  test(
    'concurrent first publications share one token reconciliation',
    () async {
      final native = _TokenNative()
        ..current = _snapshot(token: _tokenA, refreshEpoch: 22);
      final authority = _Authority();
      final coordinator = _coordinator(native, authority);

      final first = coordinator.publishForAuthenticatedGraph();
      final second = coordinator.publishForAuthenticatedGraph();

      expect(await Future.wait(<Future<bool>>[first, second]), <bool>[
        true,
        true,
      ]);
      expect(authority.publications, hasLength(1));

      await coordinator.close();
      await native.events.close();
    },
  );

  test('close releases a hung initial native read', () async {
    final readCurrent = Completer<Object?>();
    final timeout = Completer<void>();
    final native = _TokenNative()..readResponse = readCurrent.future;
    final authority = _Authority();
    final coordinator = IosVoipTokenCoordinator(
      invokeMethod: native.invoke,
      nativeEvents: native.events.stream,
      authorityClient: authority,
      clock: () => _now,
      waitForInitialReadTimeout: (_) => timeout.future,
    );

    final publication = coordinator.publishForAuthenticatedGraph();
    final publicationExpectation = expectLater(
      publication,
      throwsA(
        isA<IosVoipTokenException>().having(
          (error) => error.code,
          'code',
          IosVoipTokenErrorCode.closed,
        ),
      ),
    );
    await _until(() => native.calls.isNotEmpty);
    await coordinator.close();

    await publicationExpectation;
    expect(authority.publications, isEmpty);

    if (!timeout.isCompleted) timeout.complete();
    if (!readCurrent.isCompleted) readCurrent.complete(null);
    await native.events.close();
  });

  test('timeout bounds a hung initial native read and fails closed', () async {
    final readCurrent = Completer<Object?>();
    final timeout = Completer<void>();
    final native = _TokenNative()..readResponse = readCurrent.future;
    final authority = _Authority();
    final coordinator = IosVoipTokenCoordinator(
      invokeMethod: native.invoke,
      nativeEvents: native.events.stream,
      authorityClient: authority,
      clock: () => _now,
      waitForInitialReadTimeout: (_) => timeout.future,
    );

    final publication = coordinator.publishForAuthenticatedGraph();
    await _until(() => native.calls.isNotEmpty);
    timeout.complete();

    await expectLater(
      publication,
      throwsA(
        isA<IosVoipTokenException>().having(
          (error) => error.code,
          'code',
          IosVoipTokenErrorCode.nativeFailure,
        ),
      ),
    );
    expect(authority.publications, isEmpty);

    if (!readCurrent.isCompleted) readCurrent.complete(null);
    await coordinator.close();
    await native.events.close();
  });

  test(
    'initial native stream error releases a hung read fail closed',
    () async {
      final readCurrent = Completer<Object?>();
      final timeout = Completer<void>();
      final native = _TokenNative()..readResponse = readCurrent.future;
      final authority = _Authority();
      final coordinator = IosVoipTokenCoordinator(
        invokeMethod: native.invoke,
        nativeEvents: native.events.stream,
        authorityClient: authority,
        clock: () => _now,
        waitForInitialReadTimeout: (_) => timeout.future,
      );

      final publication = coordinator.publishForAuthenticatedGraph();
      await _until(() => native.calls.isNotEmpty);
      native.events.addError(StateError('redacted native failure'));

      await expectLater(
        publication,
        throwsA(
          isA<IosVoipTokenException>().having(
            (error) => error.code,
            'code',
            IosVoipTokenErrorCode.nativeFailure,
          ),
        ),
      );
      expect(authority.publications, isEmpty);

      if (!timeout.isCompleted) timeout.complete();
      if (!readCurrent.isCompleted) readCurrent.complete(null);
      await coordinator.close();
      await native.events.close();
    },
  );

  test(
    'close while publication gate waits cannot publish afterwards',
    () async {
      final native = _TokenNative()
        ..current = _snapshot(token: _tokenA, refreshEpoch: 29);
      final authority = _Authority();
      final gateEntered = Completer<void>();
      final gate = Completer<bool>();
      final coordinator = IosVoipTokenCoordinator(
        invokeMethod: native.invoke,
        nativeEvents: native.events.stream,
        authorityClient: authority,
        clock: () => _now,
        publicationAllowed: () {
          if (!gateEntered.isCompleted) gateEntered.complete();
          return gate.future;
        },
      );

      final publication = coordinator.publishForAuthenticatedGraph();
      await gateEntered.future;
      final closing = coordinator.close();
      gate.complete(true);

      expect(await publication, isFalse);
      await closing;
      expect(authority.publications, isEmpty);
      await native.events.close();
    },
  );

  test('gate-false close still confirms the exact VoIP epoch revoke', () async {
    final native = _TokenNative()
      ..current = _snapshot(token: _tokenA, refreshEpoch: 24);
    final authority = _Authority();
    var publicationAllowed = true;
    final coordinator = IosVoipTokenCoordinator(
      invokeMethod: native.invoke,
      nativeEvents: native.events.stream,
      authorityClient: authority,
      clock: () => _now,
      publicationAllowed: () async => publicationAllowed,
    );

    expect(await coordinator.publishForAuthenticatedGraph(), isTrue);
    publicationAllowed = false;
    await coordinator.close();

    expect(authority.revocations, <({CallTokenKind kind, int? epoch})>[
      (kind: CallTokenKind.iosVoip, epoch: 24),
    ]);
    await native.events.close();
  });

  test('unconfirmed revoke is not memoized and a later CAS retries', () async {
    final native = _TokenNative()
      ..current = _snapshot(token: _tokenA, refreshEpoch: 25);
    final authority = _Authority()..revokeResults.addAll(<bool>[false, true]);
    final coordinator = _coordinator(native, authority);
    expect(await coordinator.publishForAuthenticatedGraph(), isTrue);

    await expectLater(
      coordinator.revokeForCallabilityRollback(),
      throwsA(
        isA<IosVoipTokenException>().having(
          (error) => error.code,
          'code',
          IosVoipTokenErrorCode.authorityFailure,
        ),
      ),
    );
    await coordinator.revokeForCallabilityRollback();

    expect(authority.revocations, <({CallTokenKind kind, int? epoch})>[
      (kind: CallTokenKind.iosVoip, epoch: 25),
      (kind: CallTokenKind.iosVoip, epoch: 25),
    ]);
    await coordinator.close();
    await native.events.close();
  });

  test(
    'cold invalidated snapshot performs only its persisted epoch CAS',
    () async {
      final native = _TokenNative()
        ..current = _snapshot(token: '', refreshEpoch: 26, invalidated: true);
      final authority = _Authority();
      final coordinator = IosVoipTokenCoordinator(
        invokeMethod: native.invoke,
        nativeEvents: native.events.stream,
        authorityClient: authority,
        clock: () => _now,
        waitForInitialSnapshotTimeout: (_) async {},
      );

      expect(await coordinator.publishForAuthenticatedGraph(), isFalse);

      expect(authority.publications, isEmpty);
      expect(authority.revocations, <({CallTokenKind kind, int? epoch})>[
        (kind: CallTokenKind.iosVoip, epoch: 26),
      ]);
      await coordinator.close();
      await native.events.close();
    },
  );

  test(
    'rotation event buffered during stale readCurrent wins in order',
    () async {
      final readCurrent = Completer<Object?>();
      final native = _TokenNative()..readResponse = readCurrent.future;
      final authority = _Authority();
      final coordinator = _coordinator(native, authority);

      final publish = coordinator.publishForAuthenticatedGraph();
      await _until(() => native.calls.isNotEmpty);
      native.events.add(_snapshot(token: _tokenB, refreshEpoch: 28));
      readCurrent.complete(_snapshot(token: _tokenA, refreshEpoch: 27));

      expect(await publish, isTrue);
      expect(authority.publications, hasLength(1));
      expect(authority.publications.single.token, _tokenB);
      expect(authority.publications.single.refreshEpoch, 28);
      expect(authority.revocations, isEmpty);

      await coordinator.close();
      await native.events.close();
    },
  );

  test('strict malformed read and event snapshots fail closed', () async {
    final malformedRead = _TokenNative()
      ..current = <String, Object?>{
        ..._snapshot(token: _tokenA, refreshEpoch: 31),
        'unexpected': true,
      };
    final readAuthority = _Authority();
    final readCoordinator = _coordinator(malformedRead, readAuthority);

    await expectLater(
      readCoordinator.start(),
      throwsA(
        isA<IosVoipTokenException>().having(
          (error) => error.code,
          'code',
          IosVoipTokenErrorCode.malformedSnapshot,
        ),
      ),
    );
    expect(readAuthority.publications, isEmpty);
    await readCoordinator.close();
    await malformedRead.events.close();

    final malformedEvent = _TokenNative()
      ..current = _snapshot(token: _tokenA, refreshEpoch: 32);
    final eventAuthority = _Authority();
    final eventCoordinator = _coordinator(malformedEvent, eventAuthority);
    final invalidated = Completer<void>();
    final subscription = eventCoordinator.authorityInvalidations.listen((_) {
      if (!invalidated.isCompleted) invalidated.complete();
    });
    expect(await eventCoordinator.publishForAuthenticatedGraph(), isTrue);

    malformedEvent.events.add(
      _snapshot(token: _tokenB.toUpperCase(), refreshEpoch: 33),
    );
    await invalidated.future;

    expect(eventAuthority.revocations.single.kind, CallTokenKind.iosVoip);
    expect(eventAuthority.revocations.single.epoch, 32);
    expect(await eventCoordinator.publishForAuthenticatedGraph(), isFalse);

    await eventCoordinator.close();
    await subscription.cancel();
    await malformedEvent.events.close();
  });
}

IosVoipTokenCoordinator _coordinator(
  _TokenNative native,
  _Authority authority,
) => IosVoipTokenCoordinator(
  invokeMethod: native.invoke,
  nativeEvents: native.events.stream,
  authorityClient: authority,
  clock: () => _now,
);

final class _TokenNative {
  final StreamController<Object?> events = StreamController<Object?>();
  final List<({String method, Map<String, Object?> arguments})> calls =
      <({String method, Map<String, Object?> arguments})>[];
  Object? current;
  Future<Object?>? readResponse;

  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    calls.add((method: method, arguments: arguments));
    if (method == 'readCurrent') {
      return await (readResponse ?? Future.value(current));
    }
    throw StateError('unsupported token method');
  }
}

final class _Authority implements CallAuthorityClient {
  final List<CallTokenRecord> publications = <CallTokenRecord>[];
  final List<({CallTokenKind kind, int? epoch})> revocations =
      <({CallTokenKind kind, int? epoch})>[];
  final Map<int, int> _generations = <int, int>{};
  final List<bool> revokeResults = <bool>[];

  @override
  Future<CallTokenPublication> publishToken(CallTokenRecord record) async {
    publications.add(record);
    final epoch = record.refreshEpoch!;
    final generation = _generations.putIfAbsent(
      epoch,
      () => _generations.length + 1,
    );
    return CallTokenPublication(
      accepted: true,
      serverGeneration: generation,
      refreshEpoch: epoch,
    );
  }

  @override
  Future<bool> setToken(CallTokenRecord record) async =>
      (await publishToken(record)).accepted;

  @override
  Future<bool> revokeToken(CallTokenKind kind, {int? refreshEpoch}) async {
    revocations.add((kind: kind, epoch: refreshEpoch));
    return revokeResults.isEmpty ? true : revokeResults.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle() async {
  for (var index = 0; index < 4; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('condition was not reached');
}
