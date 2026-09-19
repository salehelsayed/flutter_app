import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/notification_android_payload_campaign.dart'
    as driver;
import '../../integration_test/support/android_notification_payload_campaign.dart';

const _request = <String, Object?>{
  'stepId': 'notification-dual-run',
  'runId': 'run',
  'nonce': 'nonce',
  'targetPeerId': 'paired-receiver',
};
final _prepared = <String, Object?>{
  'schema': 'mknoon.notification-dual-path.v1',
  'status': 'prepared',
  'success': true,
  ..._request,
  'messageId': '00000000-0000-4000-8000-000000000001',
  'wireSha256': 'a' * 64,
  'ciphertextSha256': 'b' * 64,
  'expiresAtMs': 1900000180000,
};
Map<String, Object?> get _complete => {
  ..._prepared,
  'status': 'complete',
  'transport': 'relay',
  'acked': true,
};

final class _Fixture {
  final calls = <String>[];
  final cleanupFailures = <Object>[];
  Duration elapsed = Duration.zero;
  bool providerWasAccepted = false;
  Future<void> Function()? provider;
  Future<void> Function()? corroboration;
  Future<void> Function()? beforeLive;
  Future<void> Function()? beforePrepared;
  Future<void> Function()? beforeComplete;
  Future<void> Function()? beforeCleanup;
  Map<String, Object?> prepared = {..._prepared};
  Map<String, Object?> complete = _complete;
  Object? cancelError;
  Object? cleanupError;

  Future<AndroidNotificationDualPathSendProof> run() =>
      coordinateAndroidNotificationDualPathSend(
        request: _request,
        stage: () async => calls.add('stage'),
        prepared: (remaining) async {
          calls.add('prepared');
          await beforePrepared?.call();
          return prepared;
        },
        providerAccepted: (binding, remaining) async {
          calls.add('provider');
          expect(binding['messageId'], _prepared['messageId']);
          expect(remaining, lessThanOrEqualTo(const Duration(minutes: 2)));
          await provider?.call();
          providerWasAccepted = true;
        },
        beforeLiveRelease: () async {
          calls.add('pin');
          await beforeLive?.call();
          return 'live-release-cursor';
        },
        release: (binding) async {
          calls.add('live');
          // Model the retained B13 failure: an early live delivery makes the
          // later custody store intentionally no-notification. A provider
          // wait after that send can never establish the requested overlap.
          if (!providerWasAccepted) {
            throw StateError('live ACK preceded provider admission');
          }
          expect(binding['wireSha256'], _prepared['wireSha256']);
        },
        completed: (remaining) async {
          calls.add('complete');
          await beforeComplete?.call();
          return complete;
        },
        providerCorroborated: (binding, remaining) async {
          calls.add('corroborate');
          expect(binding['wireSha256'], _prepared['wireSha256']);
          expect(remaining, lessThanOrEqualTo(const Duration(minutes: 3)));
          await corroboration?.call();
        },
        cancel: (binding) async {
          calls.add('cancel');
          if (cancelError != null) throw cancelError!;
        },
        cleanup: () async {
          calls.add('cleanup');
          await beforeCleanup?.call();
          if (cleanupError != null) throw cleanupError!;
        },
        recordCleanupFailure: cleanupFailures.add,
        elapsed: () => elapsed,
      );
}

void main() {
  test('diagnostic projection counts malformed FLOW without retaining it', () {
    const window =
        'unrelated text\n[FLOW] broken secret\n[FLOW] []\n'
        '[FLOW] {"event":"event","details":null}\n';
    final projection = driver.androidNotificationDualPathWindowDiagnostic(
      window,
      messageId: _prepared['messageId']! as String,
    );
    expect(projection['malformedFlowRows'], 3);
    expect(
      projection['sha256'],
      sha256.convert(utf8.encode(window)).toString(),
    );
    expect(projection['utf8Bytes'], utf8.encode(window).length);
    expect(jsonEncode(projection), isNot(contains('secret')));
  });

  test('diagnostic projection has closed transport counters and no raw values', () {
    final id = _prepared['messageId']! as String;
    final prefix = safeNotificationIdPrefix(id);
    final window = ['local', 'direct', 'relay', 'inbox', 'secret-dynamic-route']
        .map(
          (transport) =>
              '[FLOW] ${jsonEncode({
                'event': 'CHAT_MSG_RECEIVE_STORED',
                'details': {'id': prefix, 'transport': transport, 'body': 'secret-body'},
              })}',
        )
        .join('\n');
    final projection = driver.androidNotificationDualPathWindowDiagnostic(
      window,
      messageId: id,
    );
    expect(projection['storedTransportCounts'], {
      'local': 1,
      'direct': 1,
      'relay': 1,
      'inbox': 1,
      'other': 1,
    });
    expect(
      projection.keys,
      unorderedEquals([
        'sha256',
        'utf8Bytes',
        'malformedFlowRows',
        'fcmReceipts',
        'listeners',
        'storedTransportCounts',
      ]),
    );
    for (final privateValue in [
      id,
      prefix,
      'secret-body',
      'secret-dynamic-route',
    ]) {
      expect(jsonEncode(projection), isNot(contains(privateValue)));
    }
  });

  test('diagnostic projection counts only the exact message prefix', () {
    final id = _prepared['messageId']! as String;
    final prefix = safeNotificationIdPrefix(id);
    final rows = <String>[];
    for (final candidate in [prefix, '${prefix}suffix', 'unrelated']) {
      for (final event in [
        androidNotificationFcmPathAttemptEvent,
        androidNotificationLivePathAttemptEvent,
        'CHAT_MSG_RECEIVE_STORED',
      ]) {
        rows.add(
          '[FLOW] ${jsonEncode({
            'event': event,
            'details': {'id': candidate, 'messageIdPrefix': candidate, 'transport': 'direct'},
          })}',
        );
      }
    }
    final projection = driver.androidNotificationDualPathWindowDiagnostic(
      rows.join('\n'),
      messageId: id,
    );
    expect(projection['fcmReceipts'], 1);
    expect(projection['listeners'], 1);
    expect((projection['storedTransportCounts']! as Map)['direct'], 1);
  });

  test('provider acceptance precedes exact same-wire live release', () async {
    final f = _Fixture();
    final proof = await f.run();
    expect(f.calls, [
      'stage',
      'prepared',
      'provider',
      'pin',
      'live',
      'complete',
      'corroborate',
      'cleanup',
    ]);
    expect(proof.liveCursor, 'live-release-cursor');
    expect(proof.completed['acked'], isTrue);
  });

  test(
    'held SSH corroboration cannot delay live but still prevents PASS',
    () async {
      final held = Completer<void>();
      final f = _Fixture()..corroboration = () => held.future;
      var completed = false;
      final running = f.run().then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      try {
        expect(
          f.calls,
          containsAllInOrder(['provider', 'live', 'complete', 'corroborate']),
        );
        expect(completed, isFalse);
      } finally {
        held.complete();
        await running;
      }
    },
  );

  test('post-release provider corroboration failure remains failure', () async {
    final failure = StateError('relay corroboration unavailable');
    final f = _Fixture()..corroboration = () async => throw failure;
    await expectLater(f.run(), throwsA(same(failure)));
    expect(
      f.calls,
      containsAllInOrder([
        'live',
        'complete',
        'corroborate',
        'cancel',
        'cleanup',
      ]),
    );
  });

  test('late corroboration cannot extend the original sender budget', () async {
    final f = _Fixture();
    f.corroboration = () async => f.elapsed = const Duration(seconds: 180);
    await expectLater(f.run(), throwsA(isA<TimeoutException>()));
    expect(
      f.calls,
      containsAllInOrder([
        'live',
        'complete',
        'corroborate',
        'cancel',
        'cleanup',
      ]),
    );
  });

  test('invalid live completion cannot reach provider corroboration', () async {
    final f = _Fixture()..complete['transport'] = 'inbox';
    await expectLater(f.run(), throwsFormatException);
    expect(f.calls, isNot(contains('corroborate')));
  });

  test('held provider acceptance cannot release a live message', () async {
    final held = Completer<void>();
    final f = _Fixture()..provider = () => held.future;
    final running = f.run();
    await Future<void>.delayed(Duration.zero);
    expect(f.calls, ['stage', 'prepared', 'provider']);
    held.complete();
    await running;
  });

  test(
    'provider failure cancels exact sender and preserves first error',
    () async {
      final failure = StateError('provider unavailable');
      final f = _Fixture()
        ..provider = (() async => throw failure)
        ..cancelError = StateError('cancel observation failed')
        ..cleanupError = StateError('cleanup failed');
      await expectLater(f.run(), throwsA(same(failure)));
      expect(f.calls, ['stage', 'prepared', 'provider', 'cancel', 'cleanup']);
      expect(f.cleanupFailures, hasLength(2));
    },
  );

  test('late provider result never receives release authority', () async {
    final f = _Fixture();
    f.provider = () async => f.elapsed = const Duration(seconds: 181);
    await expectLater(f.run(), throwsA(isA<TimeoutException>()));
    expect(f.calls, isNot(contains('live')));
    expect(f.calls.last, 'cleanup');
  });

  test('late receiver pin never receives release authority', () async {
    final f = _Fixture();
    f.beforeLive = () async => f.elapsed = const Duration(seconds: 180);
    await expectLater(f.run(), throwsA(isA<TimeoutException>()));
    expect(f.calls, isNot(contains('live')));
  });

  test(
    'receiver observation cannot overrun its two-minute sub-budget',
    () async {
      final f = _Fixture();
      f.provider = () async => f.elapsed = const Duration(seconds: 120);
      await expectLater(f.run(), throwsA(isA<TimeoutException>()));
      expect(f.calls, isNot(contains('live')));
      expect(f.calls.last, 'cleanup');
    },
  );

  test('held preparation cannot obtain a new provider budget', () async {
    final f = _Fixture();
    f.beforePrepared = () async => f.elapsed = const Duration(seconds: 181);
    await expectLater(f.run(), throwsA(isA<TimeoutException>()));
    expect(f.calls, isNot(contains('provider')));
    expect(f.calls, isNot(contains('live')));
  });

  test('late complete receipt remains failure', () async {
    final f = _Fixture();
    f.beforeComplete = () async => f.elapsed = const Duration(seconds: 181);
    await expectLater(f.run(), throwsA(isA<TimeoutException>()));
    expect(f.calls.last, 'cleanup');
  });

  test('late successful cleanup cannot extend sender success budget', () async {
    final f = _Fixture();
    f.beforeCleanup = () async => f.elapsed = const Duration(seconds: 181);
    await expectLater(f.run(), throwsA(isA<TimeoutException>()));
  });

  test('prepared receipt with extra authority fields rejects', () async {
    final f = _Fixture()..prepared['release'] = true;
    await expectLater(f.run(), throwsFormatException);
    expect(f.calls, isNot(contains('provider')));
  });

  for (final key in ['nonce', 'targetPeerId', 'wireSha256', 'messageId']) {
    test('prepared $key mismatch cannot release', () async {
      final f = _Fixture()..prepared[key] = 'wrong';
      await expectLater(f.run(), throwsFormatException);
      expect(f.calls, isNot(contains('live')));
    });
  }

  for (final entry in <String, Object?>{
    'nonce': 'other',
    'messageId': '00000000-0000-4000-8000-000000000002',
    'wireSha256': 'c' * 64,
    'acked': false,
    'transport': 'inbox',
  }.entries) {
    test('completion ${entry.key} cannot certify another live send', () async {
      final f = _Fixture()..complete[entry.key] = entry.value;
      await expectLater(f.run(), throwsFormatException);
      expect(f.calls.last, 'cleanup');
    });
  }

  test('receiver must have an observable foreign resumed activity', () {
    expect(
      androidNotificationReceiverBackgrounded(
        'topResumedActivity=ActivityRecord{a u0 com.android.launcher/.Home}',
        packageName: 'com.mknoon.sims.notifications',
      ),
      isTrue,
    );
    expect(
      androidNotificationReceiverBackgrounded(
        'mResumedActivity: ActivityRecord{a u0 com.mknoon.sims.notifications/com.mknoon.app.MainActivity}',
        packageName: 'com.mknoon.sims.notifications',
      ),
      isFalse,
    );
    expect(
      () => androidNotificationReceiverBackgrounded(
        'unavailable',
        packageName: 'com.mknoon.sims.notifications',
      ),
      throwsFormatException,
    );
  });

  String flow(String event, Map<String, Object?> details) =>
      '[FLOW] ${jsonEncode({'event': event, 'details': details})}\n';
  const id = '00000000-0000-4000-8000-000000000001';
  const prefix = '00000000';
  test(
    'silent inbox arrival cannot masquerade as the released live contender',
    () {
      final listener = flow('CHAT_LISTENER_NEW_MESSAGE', {'id': prefix});
      for (final transport in ['inbox', 'unknown']) {
        expect(
          androidNotificationReleasedLivePathObserved(
            flow('CHAT_MSG_RECEIVE_STORED', {
                  'id': prefix,
                  'transport': transport,
                }) +
                listener,
            messageId: id,
          ),
          isFalse,
        );
      }
      expect(
        androidNotificationReleasedLivePathObserved(listener, messageId: id),
        isFalse,
      );
      expect(
        androidNotificationReleasedLivePathObserved(
          flow('CHAT_MSG_RECEIVE_STORED', {
                'id': 'other',
                'transport': 'relay',
              }) +
              listener,
          messageId: id,
        ),
        isFalse,
      );
    },
  );

  test('released real transport storage must precede the exact listener', () {
    final store = flow('CHAT_MSG_RECEIVE_STORED', {
      'id': prefix,
      'transport': 'relay',
    });
    final listener = flow('CHAT_LISTENER_NEW_MESSAGE', {'id': prefix});
    expect(
      androidNotificationReleasedLivePathObserved(
        store + listener,
        messageId: id,
      ),
      isTrue,
    );
    expect(
      androidNotificationReleasedLivePathObserved(
        listener + store,
        messageId: id,
      ),
      isFalse,
    );
  });

  test('retained 03 real FLOW shape proves the live callback', () {
    // notifications03 receiver log lines58208/58212; identity and content
    // replaced with fixed fixture values, timestamps/fields/events preserved.
    const actualShape =
        '[FLOW] {"ts":"2026-09-18T11:08:42.296878Z",'
        '"milestone":"M1_IDENTITY_INIT","layer":"FL","event":"CHAT_MSG_RECEIVE_STORED",'
        '"details":{"id":"00000000","from":"sender",'
        '"transport":"relay","textPreview":"fixture"}}\n'
        '[FLOW] {"ts":"2026-09-18T11:08:42.312441Z",'
        '"milestone":"M1_IDENTITY_INIT","layer":"FL","event":"CHAT_LISTENER_NEW_MESSAGE",'
        '"details":{"id":"00000000","from":"sender"}}\n';
    expect(
      androidNotificationReleasedLivePathObserved(actualShape, messageId: id),
      isTrue,
    );
    for (final corrupt in [
      '[FLOW] {',
      '[FLOW] {}',
      '[FLOW]',
      '[FLOW] {"event":"x","details":[]}',
    ]) {
      expect(
        androidNotificationReleasedLivePathObserved(
          actualShape + corrupt,
          messageId: id,
        ),
        isFalse,
      );
    }
    expect(
      androidNotificationReleasedLivePathObserved(
        actualShape +
            flow('CHAT_MSG_RECEIVE_STORED', {
              'id': prefix,
              'transport': 'relay',
            }),
        messageId: id,
      ),
      isFalse,
    );
    expect(
      androidNotificationReleasedLivePathObserved(
        actualShape.substring(0, actualShape.length - 4),
        messageId: id,
      ),
      isFalse,
    );
  });

  test(
    'global relay success alone cannot release an unrelated message',
    () async {
      const cipher = 'real-ciphertext-fixture';
      final binding = {
        ..._prepared,
        'ciphertextSha256': sha256.convert(utf8.encode(cipher)).toString(),
      };
      final staged = <String, Object?>{
        'kind': 'chat',
        'kem': 'real-kem-fixture',
        'ciphertext': cipher,
        'nonce': 'real-nonce-fixture',
        'senderPeerId': 'paired-sender',
        'messageId': id,
        'receivedAtMs': 1900000000100,
      };
      final receipt = flow('PUSH_BACKGROUND_MESSAGE_RECEIVED', {
        'messageIdPrefix': prefix,
      });
      const success =
          '2026/09/18 11:03:01 [PUSH] outcome=success attempt=1 total_attempts=3';
      bool qualified({
        Map<String, Object?>? frame,
        String? log,
        String? journal,
        bool absent = false,
      }) => androidNotificationPreparedProviderObserved(
        prepared: binding,
        stagedEnvelope: absent ? null : jsonEncode(frame ?? staged),
        expectedSenderPeerId: 'paired-sender',
        notBefore: DateTime.fromMillisecondsSinceEpoch(
          1900000000000,
          isUtc: true,
        ),
        receiverLog: log ?? receipt,
        relayJournal: journal ?? success,
      );
      bool receiverQualified({Map<String, Object?>? frame, String? log}) =>
          androidNotificationPreparedReceiverObserved(
            prepared: binding,
            stagedEnvelope: jsonEncode(frame ?? staged),
            expectedSenderPeerId: 'paired-sender',
            notBefore: DateTime.fromMillisecondsSinceEpoch(
              1900000000000,
              isUtc: true,
            ),
            receiverLog: log ?? receipt,
          );
      expect(receiverQualified(), isTrue);
      expect(receiverQualified(log: ''), isFalse);
      expect(qualified(), isTrue);
      expect(qualified(absent: true), isFalse);
      expect(qualified(log: ''), isFalse);
      expect(qualified(journal: ''), isFalse);
      expect(
        qualified(
          log: flow('PUSH_BACKGROUND_MESSAGE_RECEIVED', {
            'messageIdPrefix': 'different',
          }),
        ),
        isFalse,
      );
      for (final entry in <String, Object?>{
        'senderPeerId': 'other-sender',
        'messageId': '00000000-0000-4000-8000-000000000002',
        'ciphertext': 'other-ciphertext',
        'receivedAtMs': 1899999999999,
      }.entries) {
        expect(qualified(frame: {...staged, entry.key: entry.value}), isFalse);
        expect(
          receiverQualified(frame: {...staged, entry.key: entry.value}),
          isFalse,
        );
      }
      final f = _Fixture();
      f.provider = () async {
        if (!qualified(absent: true)) {
          throw TimeoutException('exact FCM missing');
        }
      };
      await expectLater(f.run(), throwsA(isA<TimeoutException>()));
      expect(f.calls, isNot(contains('live')));
    },
  );
}
