import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/debug/notification_dual_path_e2e_sender.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

Map<String, dynamic> config() => {
  'transport_action': notificationDualPathSenderAction,
  'stepId': 'dual-step',
  'runId': 'run-1',
  'nonce': 'nonce-1',
  'targetPeerId': 'receiver',
  'text': 'real fixture text',
  'timeoutMs': 180000,
};
const stored = InboxStoreOutcome(
  status: InboxStoreStatus.stored,
  storeStatus: 'stored',
  custodyContract: ackOrExpiryInboxCustodyContract,
);
const live = SendMessageResult(sent: true, acked: true, transport: 'relay');
Matcher failure(String code) =>
    isA<NotificationDualPathFailure>().having((e) => e.code, 'code', code);

class Rig {
  Duration clock = Duration.zero;
  String authority = 'original';
  int encryptions = 0, cleanups = 0;
  final events = <String>[];
  Map<String, Object?>? prepared;
  Map<String, dynamic>? control;
  String? storedWire, liveWire;
  Future<InboxStoreOutcome> Function()? onStore;
  Future<SendMessageResult> Function()? onLive;
  Future<void> Function()? onPrepared;
  Future<void> Function()? onRead;
  Future<void> Function()? onCleanup;
  late final sender = NotificationDualPathSender(
    enabled: true,
    elapsed: () => clock,
    wallNow: () => DateTime.utc(2026, 9, 18),
    newMessageId: () => 'd15a4346-9b27-4ee0-bc56-76aeff58930a',
    readAuthority: (_) async => NotificationDualPathAuthority(
      senderPeerId: 'sender',
      senderUsername: 'sender',
      recipientMlKemKey: 'key',
      fingerprint: authority,
    ),
    encrypt: (key, plaintext, budget) async {
      encryptions++;
      events.add('encrypt');
      expect(jsonDecode(plaintext)['text'], 'real fixture text');
      return {
        'ok': true,
        'kem': 'kem',
        'ciphertext': 'cipher',
        'nonce': 'crypto-nonce',
      };
    },
    store: (peer, wire, budget) async {
      events.add('store');
      storedWire = wire;
      return onStore == null ? stored : await onStore!();
    },
    sendLive: (peer, wire, budget) async {
      events.add('live');
      liveWire = wire;
      return onLive == null ? live : await onLive!();
    },
  );
  Future<Map<String, Object?>> run([NotificationDualPathRequest? request]) =>
      sender.run(
        request: request ?? NotificationDualPathRequest.fromConfig(config()),
        writePrepared: (value) async {
          events.add('prepared');
          prepared = value;
          await onPrepared?.call();
        },
        readControl: () async {
          await onRead?.call();
          return control;
        },
        cleanupControl: (_) async {
          cleanups++;
          await onCleanup?.call();
          control = null;
        },
      );
  void release() {
    final p = prepared!;
    control = {
      for (final k in [
        'schema',
        'stepId',
        'runId',
        'nonce',
        'messageId',
        'wireSha256',
      ])
        k: p[k],
    };
  }

  void cancel() {
    control = {
      ...NotificationDualPathRequest.fromConfig(config()).binding,
      'decision': 'cancel',
    };
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

void main() {
  test(
    'real store completes before prepared; live waits exact release and reuses one envelope',
    () async {
      final r = Rig();
      final gate = Completer<InboxStoreOutcome>();
      r.onStore = () => gate.future;
      final result = r.run();
      await until(() => r.events.contains('store'));
      expect(r.prepared, isNull);
      expect(r.liveWire, isNull);
      gate.complete(stored);
      await until(() => r.prepared != null);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(r.liveWire, isNull);
      r.release();
      final complete = await result;
      expect(r.events, ['encrypt', 'store', 'prepared', 'live']);
      expect(r.encryptions, 1);
      expect(r.liveWire, r.storedWire);
      expect(complete['acked'], isTrue);
      expect(
        complete['wireSha256'],
        sha256.convert(utf8.encode(r.liveWire!)).toString(),
      );
      expect(
        complete['ciphertextSha256'],
        sha256.convert(utf8.encode('cipher')).toString(),
      );
      expect(r.cleanups, 1);
      expect(r.control, isNull);
    },
  );
  for (final key in ['nonce', 'stepId', 'runId', 'messageId', 'wireSha256']) {
    test('wrong $key never authorizes live', () async {
      final r = Rig();
      r.onPrepared = () async {
        r.release();
        r.control![key] = 'wrong';
      };
      await expectLater(r.run(), throwsA(failure('control_binding')));
      expect(r.liveWire, isNull);
      expect(r.cleanups, 1);
    });
  }
  test('extra release fields fail closed', () async {
    final r = Rig();
    r.onPrepared = () async {
      r.release();
      r.control!['accepted'] = true;
    };
    await expectLater(r.run(), throwsA(failure('control_binding')));
    expect(r.liveWire, isNull);
  });
  test('release cannot precede preparation', () async {
    final r = Rig();
    r.control = {
      ...NotificationDualPathRequest.fromConfig(config()).binding,
      'messageId': 'old',
      'wireSha256': 'old',
    };
    await expectLater(r.run(), throwsA(failure('control_binding')));
    expect(r.events, isEmpty);
  });
  test('deadline after held read rejects otherwise matching release', () async {
    final r = Rig();
    r.onPrepared = () async {
      r.release();
      r.onRead = () async {
        r.clock = const Duration(minutes: 3);
      };
    };
    await expectLater(r.run(), throwsA(failure('deadline')));
    expect(r.liveWire, isNull);
  });
  test('account cutover after provider preparation prevents live', () async {
    final r = Rig();
    r.onPrepared = () async {
      r.authority = 'successor';
      r.release();
    };
    await expectLater(r.run(), throwsA(failure('authority_changed')));
    expect(r.liveWire, isNull);
  });
  test(
    'cancel while real store pending retires and late completion cannot publish or send',
    () async {
      final r = Rig();
      final gate = Completer<InboxStoreOutcome>();
      r.onStore = () => gate.future;
      final result = r.run();
      final checked = expectLater(result, throwsA(failure('canceled')));
      await until(() => r.events.contains('store'));
      r.cancel();
      await checked;
      gate.complete(stored);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(r.prepared, isNull);
      expect(r.liveWire, isNull);
      expect(r.cleanups, 1);
    },
  );
  test('poller shutdown cancels pending release', () async {
    final r = Rig();
    final result = r.run();
    final checked = expectLater(result, throwsA(failure('canceled')));
    await until(() => r.prepared != null);
    r.sender.close();
    await checked;
    expect(r.liveWire, isNull);
  });
  test('same action cannot replay after success', () async {
    final r = Rig();
    r.onPrepared = () async {
      r.release();
    };
    await r.run();
    await expectLater(r.run(), throwsA(failure('replayed_or_busy')));
    expect(r.events.where((e) => e == 'live'), hasLength(1));
  });
  test('same action cannot replay after cancellation', () async {
    final r = Rig();
    r.onPrepared = () async {
      r.cancel();
    };
    await expectLater(r.run(), throwsA(failure('canceled')));
    await expectLater(r.run(), throwsA(failure('replayed_or_busy')));
    expect(r.liveWire, isNull);
  });
  for (final outcome in [
    const InboxStoreOutcome(status: InboxStoreStatus.failed),
    const InboxStoreOutcome(
      status: InboxStoreStatus.stored,
      storeStatus: 'stored',
    ),
    const InboxStoreOutcome(
      status: InboxStoreStatus.duplicate,
      storeStatus: 'duplicate',
      custodyContract: ackOrExpiryInboxCustodyContract,
    ),
  ]) {
    test(
      'nonfresh or unauthenticated custody does not publish ${outcome.status}',
      () async {
        final r = Rig();
        r.onStore = () async => outcome;
        await expectLater(r.run(), throwsA(failure('custody_not_fresh')));
        expect(r.prepared, isNull);
        expect(r.liveWire, isNull);
      },
    );
  }
  for (final result in [
    const SendMessageResult(sent: true, acked: false, transport: 'relay'),
    const SendMessageResult(sent: true, acked: true, transport: 'inbox'),
    const SendMessageResult(sent: false, acked: true, transport: 'direct'),
  ]) {
    test(
      'live requires actual ack and live transport ${result.transport}/${result.sent}/${result.acked}',
      () async {
        final r = Rig();
        r.onPrepared = () async {
          r.release();
        };
        r.onLive = () async => result;
        await expectLater(r.run(), throwsA(failure('live_not_acked')));
        expect(r.events.where((e) => e == 'live'), hasLength(1));
      },
    );
  }
  test('late native send success cannot pass original deadline', () async {
    final r = Rig();
    r.onPrepared = () async {
      r.release();
    };
    r.onLive = () async {
      r.clock = const Duration(minutes: 3);
      return live;
    };
    await expectLater(r.run(), throwsA(failure('deadline')));
  });
  test('successful slow cleanup cannot extend original deadline', () async {
    final r = Rig();
    r.onPrepared = () async {
      r.release();
    };
    r.onCleanup = () async {
      r.clock = const Duration(minutes: 3);
    };
    await expectLater(r.run(), throwsA(failure('deadline')));
  });
  test(
    'original custody failure survives a separate cleanup failure',
    () async {
      final r = Rig();
      r.onStore = () async =>
          const InboxStoreOutcome(status: InboxStoreStatus.failed);
      r.onCleanup = () async => throw StateError('private cleanup detail');
      await expectLater(
        r.run(),
        throwsA(
          isA<NotificationDualPathFailure>()
              .having((e) => e.code, 'code', 'custody_not_fresh')
              .having(
                (e) => e.cleanupErrorCode,
                'cleanupErrorCode',
                'control_cleanup_failed',
              ),
        ),
      );
      expect(r.liveWire, isNull);
      await expectLater(r.run(), throwsA(failure('disabled')));
    },
  );
  test(
    'shutdown retires a held control read without awaiting its return',
    () async {
      final r = Rig();
      final held = Completer<void>();
      r.onRead = () => held.future;
      final result = r.run();
      final checked = expectLater(result, throwsA(failure('canceled')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      r.sender.close();
      await checked.timeout(const Duration(seconds: 1));
      held.complete();
      expect(r.events, isEmpty);
    },
  );
  test(
    'shutdown during successful control cleanup stays cancellation',
    () async {
      final r = Rig();
      r.onPrepared = () async {
        r.release();
      };
      r.onCleanup = () async {
        r.sender.close();
      };
      await expectLater(
        r.run(),
        throwsA(
          isA<NotificationDualPathFailure>()
              .having((e) => e.code, 'code', 'canceled')
              .having((e) => e.cleanupErrorCode, 'cleanupErrorCode', isNull),
        ),
      );
    },
  );
  test(
    'disabled helper produces no crypto, custody, or live side effects',
    () async {
      final r = Rig();
      r.sender.close();
      await expectLater(r.run(), throwsA(failure('disabled')));
      expect(r.events, isEmpty);
    },
  );
}
