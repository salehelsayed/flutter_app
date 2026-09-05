import 'dart:async';

import 'package:flutter_app/features/call/infrastructure/android_call_token_coordinator.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// The relay wakes an Android callee only through a `standard_call` token
/// record. Nothing published one before 2026-09-05, so a Pixel whose live
/// connection had dropped could not be called at all (verified on the
/// production relay: four `ios_voip` records, no `standard` record).
void main() {
  final start = DateTime.utc(2026, 9, 5, 12);

  test('publishes the FCM token as the relay standard call token', () async {
    final authority = _Authority();
    final outcomes = <String>[];
    final coordinator = _coordinator(
      authority,
      clock: () => start,
      readToken: () async => 'fcm-token-1',
      onResult: outcomes.add,
    );

    expect(await coordinator.ensurePublished(), isTrue);

    final record = authority.publications.single;
    expect(record.kind, CallTokenKind.standardCall);
    expect(record.platform, CallEndpointPlatform.android);
    expect(record.token, 'fcm-token-1');
    expect(
      record.expiresAtMs,
      start.add(const Duration(days: 30)).millisecondsSinceEpoch,
    );
    expect(record.environment, isNull);
    expect(record.topic, isNull);
    expect(record.capabilityVersion, isNull);
    expect(record.refreshEpoch, isNull);
    expect(outcomes, ['published']);
  });

  test('a missing token publishes nothing and reports no_token', () async {
    final authority = _Authority();
    final outcomes = <String>[];
    final coordinator = _coordinator(
      authority,
      clock: () => start,
      readToken: () async => null,
      onResult: outcomes.add,
    );

    expect(await coordinator.ensurePublished(), isFalse);
    expect(authority.publications, isEmpty);
    expect(outcomes, ['no_token']);
  });

  test(
    'the same token is republished only once half its registration elapsed',
    () async {
      final authority = _Authority();
      final outcomes = <String>[];
      var now = start;
      final coordinator = _coordinator(
        authority,
        clock: () => now,
        readToken: () async => 'fcm-token-1',
        onResult: outcomes.add,
      );

      expect(await coordinator.ensurePublished(), isTrue);
      expect(await coordinator.ensurePublished(), isTrue);
      expect(authority.publications, hasLength(1));
      expect(outcomes, ['published', 'unchanged']);

      now = start.add(const Duration(days: 16));
      expect(await coordinator.ensurePublished(), isTrue);
      expect(authority.publications, hasLength(2));
      expect(
        authority.publications.last.expiresAtMs,
        now.add(const Duration(days: 30)).millisecondsSinceEpoch,
      );
    },
  );

  test(
    'a rejected or failing publication is reported and retried next time',
    () async {
      final authority = _Authority()
        ..acceptNext = false
        ..failures.add(StateError('relay unreachable'));
      final outcomes = <String>[];
      final coordinator = _coordinator(
        authority,
        clock: () => start,
        readToken: () async => 'fcm-token-1',
        onResult: outcomes.add,
      );

      expect(await coordinator.ensurePublished(), isFalse, reason: 'failed');
      expect(await coordinator.ensurePublished(), isFalse, reason: 'rejected');
      expect(await coordinator.ensurePublished(), isTrue);
      expect(outcomes, ['failed', 'rejected', 'published']);
      expect(authority.publications, hasLength(2));
    },
  );

  test('a token refresh publishes the new token', () async {
    final authority = _Authority();
    final outcomes = <String>[];
    final refreshes = StreamController<String>.broadcast();
    addTearDown(refreshes.close);
    final coordinator = _coordinator(
      authority,
      clock: () => start,
      readToken: () async => 'fcm-token-1',
      tokenRefreshes: refreshes.stream,
      onResult: outcomes.add,
    );

    await coordinator.start();
    refreshes.add('fcm-token-2');
    await coordinator.settled;

    expect(authority.publications.map((record) => record.token), [
      'fcm-token-1',
      'fcm-token-2',
    ]);
    expect(outcomes, ['published', 'published']);
  });

  test('publication waits for the network gate', () async {
    final authority = _Authority();
    final outcomes = <String>[];
    var allowed = false;
    final coordinator = _coordinator(
      authority,
      clock: () => start,
      readToken: () async => 'fcm-token-1',
      publicationAllowed: () async => allowed,
      onResult: outcomes.add,
    );

    expect(await coordinator.ensurePublished(), isFalse);
    expect(authority.publications, isEmpty);
    allowed = true;
    expect(await coordinator.ensurePublished(), isTrue);
    expect(outcomes, ['deferred', 'published']);
  });

  test(
    'a refresh stream that throws on listen is tolerated and retried later',
    () async {
      // On a host without Firebase, FirebaseMessaging.instance throws inside
      // listen (seen in the composition suite: [core/no-app]). The token
      // publication must survive it and the subscription must be retried.
      final authority = _Authority();
      final outcomes = <String>[];
      final refreshes = StreamController<String>.broadcast();
      addTearDown(refreshes.close);
      final stream = _ThrowsOnFirstListen(refreshes.stream);
      final coordinator = _coordinator(
        authority,
        clock: () => start,
        readToken: () async => 'fcm-token-1',
        tokenRefreshes: stream,
        onResult: outcomes.add,
      );

      await coordinator.start();
      expect(outcomes, ['published']);
      expect(stream.listens, 1);
      expect(refreshes.hasListener, isFalse);

      expect(await coordinator.ensurePublished(), isTrue);
      expect(stream.listens, 2, reason: 'the subscription is retried');
      expect(refreshes.hasListener, isTrue);

      refreshes.add('fcm-token-2');
      await coordinator.settled;
      expect(authority.publications.map((record) => record.token), [
        'fcm-token-1',
        'fcm-token-2',
      ]);
    },
  );

  test('close stops listening and never revokes the token', () async {
    final authority = _Authority();
    final refreshes = StreamController<String>.broadcast();
    addTearDown(refreshes.close);
    final coordinator = _coordinator(
      authority,
      clock: () => start,
      readToken: () async => 'fcm-token-1',
      tokenRefreshes: refreshes.stream,
    );

    await coordinator.start();
    await coordinator.close();
    refreshes.add('fcm-token-2');
    await coordinator.settled;
    expect(await coordinator.ensurePublished(), isFalse);

    expect(authority.publications.map((record) => record.token), [
      'fcm-token-1',
    ]);
    expect(
      authority.revocations,
      isEmpty,
      reason: 'the relay must keep waking a closed app',
    );
    expect(refreshes.hasListener, isFalse);
  });
}

AndroidCallTokenCoordinator _coordinator(
  _Authority authority, {
  required DateTime Function() clock,
  required AndroidCallTokenReader readToken,
  Stream<String>? tokenRefreshes,
  CallTokenPublicationAllowed? publicationAllowed,
  AndroidCallTokenResultObserver? onResult,
}) => AndroidCallTokenCoordinator(
  authorityClient: authority,
  clock: clock,
  readToken: readToken,
  tokenRefreshes: tokenRefreshes ?? const Stream<String>.empty(),
  publicationAllowed: publicationAllowed ?? () async => true,
  onResult: onResult,
);

final class _Authority implements CallAuthorityClient {
  final List<CallTokenRecord> publications = <CallTokenRecord>[];
  final List<CallTokenKind> revocations = <CallTokenKind>[];
  final List<Object> failures = <Object>[];
  bool acceptNext = true;

  @override
  Future<CallTokenPublication> publishToken(CallTokenRecord record) async {
    if (failures.isNotEmpty) throw failures.removeAt(0);
    publications.add(record);
    final accepted = acceptNext;
    acceptNext = true;
    return CallTokenPublication(accepted: accepted);
  }

  @override
  Future<bool> setToken(CallTokenRecord record) async =>
      (await publishToken(record)).accepted;

  @override
  Future<bool> revokeToken(CallTokenKind kind, {int? refreshEpoch}) async {
    revocations.add(kind);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Throws synchronously from the first `listen`, like a Firebase stream on a
/// host where Firebase was never initialised, then forwards the real stream.
final class _ThrowsOnFirstListen extends Stream<String> {
  _ThrowsOnFirstListen(this._inner);

  final Stream<String> _inner;
  int listens = 0;

  @override
  StreamSubscription<String> listen(
    void Function(String event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listens++;
    if (listens == 1) throw StateError('[core/no-app] no Firebase app');
    return _inner.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
