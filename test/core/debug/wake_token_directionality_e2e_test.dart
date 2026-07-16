import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/wake_token_directionality_e2e.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';
import 'package:flutter_app/features/push/domain/wake_token_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _rawToken = 'opaque-wake-token-must-never-enter-evidence';

void main() {
  test(
    'issuer hashes the exact member of a relay-accepted register set',
    () async {
      final store = _WakeStore();
      List<String>? registered;
      final receipt = await runWakeTokenIssuerE2EAction(
        config: _request(role: wakeTokenIssuerRole),
        wakeTokenStore: store,
        registerWakeTokens: (tokens) async {
          registered = List<String>.from(tokens);
          return true;
        },
        mintToken: () => _rawToken,
        debugModeOverride: true,
        e2eModeOverride: true,
        emissionEnabledOverride: true,
        installedProfileOverride: wakeTokenDirectionalityProfileId,
      );

      expect(registered, const <String>[_rawToken]);
      expect(
        receipt['registeredTokenSha256'],
        sha256.convert(utf8.encode(_rawToken)).toString(),
      );
      expect(receipt['registerRelayAccepted'], isTrue);
      expect(jsonEncode(receipt), isNot(contains(_rawToken)));
    },
  );

  test(
    'issuer refuses unsupported relay registration and secret-safe failure',
    () async {
      final config = _request(role: wakeTokenIssuerRole);
      Object? failure;
      try {
        await runWakeTokenIssuerE2EAction(
          config: config,
          wakeTokenStore: _WakeStore(),
          registerWakeTokens: (_) async => false,
          mintToken: () => _rawToken,
          debugModeOverride: true,
          e2eModeOverride: true,
          emissionEnabledOverride: true,
          installedProfileOverride: wakeTokenDirectionalityProfileId,
          maxRegistrationAttempts: 1,
        );
      } on Object catch (error) {
        failure = error;
      }

      expect(failure, isA<StateError>());
      final receipt = wakeTokenE2EFailureReceipt(
        config: config,
        error: failure!,
      );
      expect(receipt['status'], 'failed');
      expect(receipt, isNot(contains('error')));
      expect(jsonEncode(receipt), isNot(contains(_rawToken)));
    },
  );

  test(
    'issuer retries relay readiness without reminting the contact token',
    () async {
      final store = _WakeStore();
      final registered = <List<String>>[];
      var mintCount = 0;
      var waitCycles = 0;

      final receipt = await runWakeTokenIssuerE2EAction(
        config: _request(role: wakeTokenIssuerRole),
        wakeTokenStore: store,
        registerWakeTokens: (tokens) async {
          registered.add(List<String>.from(tokens));
          return registered.length == 2;
        },
        mintToken: () {
          mintCount++;
          return _rawToken;
        },
        onWaitCycle: () async => waitCycles++,
        registrationRetryInterval: Duration.zero,
        maxRegistrationAttempts: 3,
        debugModeOverride: true,
        e2eModeOverride: true,
        emissionEnabledOverride: true,
        installedProfileOverride: wakeTokenDirectionalityProfileId,
      );

      expect(mintCount, 1);
      expect(waitCycles, 1);
      expect(registered, const <List<String>>[
        <String>[_rawToken],
        <String>[_rawToken],
      ]);
      expect(receipt['registerRelayAccepted'], isTrue);
      expect(
        receipt['registeredTokenSha256'],
        sha256.convert(utf8.encode(_rawToken)).toString(),
      );
      expect(jsonEncode(receipt), isNot(contains(_rawToken)));
    },
  );

  test(
    'presenter independently hashes production store and attachment',
    () async {
      final observer = WakeTokenAcceptedAttachmentObserver();
      final received = _ReceivedStore(_rawToken);
      final inbox = _ObservedInboxStore(observer, attachedToken: _rawToken);
      final receipt = await runWakeTokenPresenterE2EAction(
        config: _request(role: wakeTokenPresenterRole),
        receivedWakeTokenStore: received,
        detailedInboxStore: inbox,
        attachmentObserver: observer,
        pollInterval: Duration.zero,
        debugModeOverride: true,
        e2eModeOverride: true,
        emissionEnabledOverride: true,
        installedProfileOverride: wakeTokenDirectionalityProfileId,
      );

      final digest = sha256.convert(utf8.encode(_rawToken)).toString();
      expect(receipt['storedTokenSha256'], digest);
      expect(receipt['attachedTokenSha256'], digest);
      expect(receipt['inboxStoreAccepted'], isTrue);
      expect(inbox.messages, <String>[
        wakeTokenAttachmentMessage('run-wake-1', 'nonce-wake-1'),
      ]);
      expect(jsonEncode(receipt), isNot(contains(_rawToken)));
      expect(observer.isArmed, isFalse);
    },
  );

  test(
    'presenter preserves a direction inversion for the final gate to reject',
    () async {
      final observer = WakeTokenAcceptedAttachmentObserver();
      final receipt = await runWakeTokenPresenterE2EAction(
        config: _request(role: wakeTokenPresenterRole),
        receivedWakeTokenStore: _ReceivedStore('stored-from-A'),
        detailedInboxStore: _ObservedInboxStore(
          observer,
          attachedToken: 'wrong-own-token',
        ),
        attachmentObserver: observer,
        pollInterval: Duration.zero,
        debugModeOverride: true,
        e2eModeOverride: true,
        emissionEnabledOverride: true,
        installedProfileOverride: wakeTokenDirectionalityProfileId,
      );

      expect(
        receipt['storedTokenSha256'],
        isNot(receipt['attachedTokenSha256']),
      );
    },
  );

  test('attachment observer ignores unrelated accepted stores', () async {
    final observer = WakeTokenAcceptedAttachmentObserver();
    final capture = await observer.capture(
      expectedPeerId: 'peer-A',
      expectedMessage: 'exact-message',
      timeout: const Duration(seconds: 1),
      dispatch: () async {
        observer.observeAccepted(
          toPeerIdSha256: _digest('peer-other'),
          messageSha256: _digest('exact-message'),
          wakeTokenSha256: _digest('wrong'),
        );
        observer.observeAccepted(
          toPeerIdSha256: _digest('peer-A'),
          messageSha256: _digest('other-message'),
          wakeTokenSha256: _digest('wrong'),
        );
        observer.observeAccepted(
          toPeerIdSha256: _digest('peer-A'),
          messageSha256: _digest('exact-message'),
          wakeTokenSha256: _digest(_rawToken),
        );
        return const InboxStoreOutcome(status: InboxStoreStatus.stored);
      },
    );

    expect(capture.wakeTokenSha256, _digest(_rawToken));
    expect(observer.isArmed, isFalse);
  });

  test('action rejects a non-attested profile and disabled emission', () async {
    final args = (
      config: _request(role: wakeTokenIssuerRole),
      store: _WakeStore(),
    );
    expect(
      () => runWakeTokenIssuerE2EAction(
        config: args.config,
        wakeTokenStore: args.store,
        registerWakeTokens: (_) async => true,
        debugModeOverride: true,
        e2eModeOverride: true,
        emissionEnabledOverride: true,
        installedProfileOverride: 'android.e2e.main',
      ),
      throwsStateError,
    );
    expect(
      () => runWakeTokenIssuerE2EAction(
        config: args.config,
        wakeTokenStore: args.store,
        registerWakeTokens: (_) async => true,
        debugModeOverride: true,
        e2eModeOverride: true,
        emissionEnabledOverride: false,
        installedProfileOverride: wakeTokenDirectionalityProfileId,
      ),
      throwsStateError,
    );
  });
}

Map<String, dynamic> _request({required String role}) => <String, dynamic>{
  'schema': role == wakeTokenIssuerRole
      ? wakeTokenIssuerRequestSchema
      : wakeTokenPresenterRequestSchema,
  'profileId': wakeTokenDirectionalityProfileId,
  'transport_action': role == wakeTokenIssuerRole
      ? wakeTokenIssuerAction
      : wakeTokenPresenterAction,
  'scenario': wakeTokenDirectionalityScenarioId,
  'role': role,
  'stepId': role == wakeTokenIssuerRole
      ? wakeTokenIssuerStepId('run-wake-1')
      : wakeTokenPresenterStepId('run-wake-1'),
  'runId': 'run-wake-1',
  'nonce': 'nonce-wake-1',
  'contactPeerId': 'peer-A',
  'timeoutMs': 5000,
};

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

final class _WakeStore implements WakeTokenStore {
  Map<String, String> values = <String, String>{};

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<Map<String, String>> readTokens() async => Map.from(values);

  @override
  Future<void> writeTokens(Map<String, String> tokens) async {
    values = Map.from(tokens);
  }
}

final class _ReceivedStore implements ReceivedWakeTokenStore {
  _ReceivedStore(this.token);

  final String token;

  @override
  Future<void> clear() async {}

  @override
  Future<Map<String, String>?> readTokenFor(String peerId) async =>
      <String, String>{'tok': token, 'ts': '2026-07-15T00:00:00.000Z'};

  @override
  Future<void> removeTokenFor(String peerId) async {}

  @override
  Future<void> writeTokenFor(String peerId, String token, String ts) async {}
}

final class _ObservedInboxStore implements DetailedInboxStore {
  _ObservedInboxStore(this.observer, {required this.attachedToken});

  final WakeTokenAcceptedAttachmentObserver observer;
  final String attachedToken;
  final List<String> messages = <String>[];

  @override
  Future<InboxStoreOutcome> storeInInboxDetailed(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    messages.add(message);
    observer.observeAccepted(
      toPeerIdSha256: _digest(toPeerId),
      messageSha256: _digest(message),
      wakeTokenSha256: _digest(attachedToken),
    );
    return const InboxStoreOutcome(status: InboxStoreStatus.stored);
  }
}
