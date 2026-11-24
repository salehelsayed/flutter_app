import 'dart:async';

import 'package:flutter_app/features/contact_request/application/mlkem_reannounce_marker.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/qr_code/application/launch_qr_contact_request.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

const _deadline = Duration(seconds: 3);
const _peerId = 'invitation-peer';

void main() {
  test(
    'retains retry custody before eligibility and marked transmission',
    () async {
      final store = _MarkerStore();
      final effects = <String>[];

      final result = await launchQrContactRequest(
        secureKeyStore: store,
        peerId: _peerId,
        shouldMarkContactRequest: (peerId) async {
          expect(peerId, _peerId);
          expect(await readMlKemReannounceMarker(store).timeout(_deadline), [
            _peerId,
          ]);
          effects.add('eligibility');
          return true;
        },
        send: (marked) async {
          expect(marked, isTrue);
          expect(await readMlKemReannounceMarker(store).timeout(_deadline), [
            _peerId,
          ]);
          effects.add('send');
          return SendContactRequestResult.success;
        },
      ).timeout(_deadline);

      expect(result.retryRetained, isTrue);
      expect(result.transmission, isNotNull);
      expect(
        await result.transmission!.timeout(_deadline),
        SendContactRequestResult.success,
      );
      expect(effects, ['eligibility', 'send']);
      expect(store.markerWrites, 1);
    },
  );

  test(
    'existing custody allows a resend without rewriting its marker',
    () async {
      final store = _MarkerStore();
      const pending = ['another-peer', _peerId];
      await writeMlKemReannounceMarker(store, pending).timeout(_deadline);
      final beforeLaunch = store.markerWrites;
      var sends = 0;

      final result = await launchQrContactRequest(
        secureKeyStore: store,
        peerId: _peerId,
        shouldMarkContactRequest: (_) async => false,
        send: (marked) async {
          expect(marked, isFalse);
          sends++;
          return SendContactRequestResult.success;
        },
      ).timeout(_deadline);

      expect(result.retryRetained, isTrue);
      expect(result.transmission, isNotNull);
      expect(
        await result.transmission!.timeout(_deadline),
        SendContactRequestResult.success,
      );
      expect(sends, 1);
      expect(store.markerWrites, beforeLaunch);
      expect(
        await readMlKemReannounceMarker(store).timeout(_deadline),
        pending,
      );
    },
  );

  test(
    'launch returns a detached future while transmission is pending',
    () async {
      final store = _MarkerStore();
      final transport = Completer<SendContactRequestResult>();
      var started = false;
      late QrContactRequestLaunch result;

      try {
        result = await launchQrContactRequest(
          secureKeyStore: store,
          peerId: _peerId,
          shouldMarkContactRequest: (_) async => false,
          send: (_) {
            started = true;
            return transport.future.timeout(_deadline);
          },
        ).timeout(_deadline);
        expect(result.retryRetained, isTrue);
        expect(result.transmission, isNotNull);
        expect(started, isTrue);
        expect(transport.isCompleted, isFalse);
      } finally {
        transport.complete(SendContactRequestResult.success);
      }

      expect(
        await result.transmission!.timeout(_deadline),
        SendContactRequestResult.success,
      );
    },
  );

  test(
    'retirement during the marker read prevents persistence and send',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final store = _MarkerStore(
        beforeMarkerRead: () async {
          if (entered.isCompleted) return;
          entered.complete();
          await release.future.timeout(_deadline);
        },
      );
      var live = true;
      var eligibilityChecks = 0;
      var sends = 0;
      final pending = launchQrContactRequest(
        secureKeyStore: store,
        peerId: _peerId,
        canQueue: () => live,
        shouldMarkContactRequest: (_) async {
          eligibilityChecks++;
          return false;
        },
        send: (_) async {
          sends++;
          return SendContactRequestResult.success;
        },
      ).timeout(_deadline);

      try {
        final reachedRead = await Future.any([
          entered.future.then((_) => true),
          pending.then((_) => false),
        ]).timeout(_deadline);
        expect(
          reachedRead,
          isTrue,
          reason: 'secure-store marker read was skipped',
        );
        live = false;
      } finally {
        release.complete();
      }

      expect(await pending, (retryRetained: false, transmission: null));
      expect(store.markerWrites, 0);
      expect(
        await store.containsKey(kMlKemReannouncePendingKey).timeout(_deadline),
        isFalse,
      );
      expect(eligibilityChecks, 0);
      expect(sends, 0);
    },
  );

  test(
    'retirement during the marker write hides and rolls back new custody',
    () async {
      final written = Completer<void>();
      final release = Completer<void>();
      final store = _MarkerStore(
        afterMarkerWrite: (value) async {
          if (!value.contains(_peerId)) return;
          written.complete();
          await release.future.timeout(_deadline);
        },
      );
      const previousPeers = ['previous-peer'];
      await writeMlKemReannounceMarker(store, previousPeers).timeout(_deadline);
      var live = true;
      var eligibilityChecks = 0;
      var sends = 0;
      final pending = launchQrContactRequest(
        secureKeyStore: store,
        peerId: _peerId,
        canQueue: () => live,
        shouldMarkContactRequest: (_) async {
          eligibilityChecks++;
          return false;
        },
        send: (_) async {
          sends++;
          return SendContactRequestResult.success;
        },
      ).timeout(_deadline);

      late Future<List<String>> retryRead;
      try {
        final reachedWrite = await Future.any([
          written.future.then((_) => true),
          pending.then((_) => false),
        ]).timeout(_deadline);
        expect(reachedWrite, isTrue, reason: 'secure write was skipped');
        live = false;
        retryRead = readMlKemReannounceMarker(store).timeout(_deadline);
      } finally {
        release.complete();
      }

      final result = await pending;
      expect(await retryRead, previousPeers);
      expect(result, (retryRetained: false, transmission: null));
      expect(
        await readMlKemReannounceMarker(store).timeout(_deadline),
        previousPeers,
      );
      expect(eligibilityChecks, 0);
      expect(sends, 0);
    },
  );

  test(
    'an actual send failure leaves the existing retry owner retained',
    () async {
      final store = _MarkerStore();
      var sends = 0;

      final result = await launchQrContactRequest(
        secureKeyStore: store,
        peerId: _peerId,
        shouldMarkContactRequest: (_) async => false,
        send: (_) async {
          sends++;
          return SendContactRequestResult.sendFailed;
        },
      ).timeout(_deadline);

      expect(result.retryRetained, isTrue);
      expect(result.transmission, isNotNull);
      expect(
        await result.transmission!.timeout(_deadline),
        SendContactRequestResult.sendFailed,
      );
      expect(sends, 1);
      expect(await readMlKemReannounceMarker(store).timeout(_deadline), [
        _peerId,
      ]);
    },
  );
}

final class _MarkerStore extends FakeSecureKeyStore {
  _MarkerStore({this.beforeMarkerRead, this.afterMarkerWrite});

  final Future<void> Function()? beforeMarkerRead;
  final Future<void> Function(String value)? afterMarkerWrite;
  var markerWrites = 0;

  @override
  Future<String?> read(String key) async {
    if (key == kMlKemReannouncePendingKey) {
      await beforeMarkerRead?.call().timeout(_deadline);
    }
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    if (key == kMlKemReannouncePendingKey) {
      markerWrites++;
      await afterMarkerWrite?.call(value).timeout(_deadline);
    }
  }
}
