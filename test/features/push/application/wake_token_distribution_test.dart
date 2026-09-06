import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/wake_token_pending_marker.dart';
import 'package:flutter_app/features/push/application/issue_wake_tokens_use_case.dart';
import 'package:flutter_app/features/push/application/wake_token_reissue_coalescer.dart';
import 'package:flutter_app/features/push/infrastructure/wake_token_store_impl.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  test('startup and contact-change issuance cannot overwrite newer authorization', () async {
    final secure = FakeSecureKeyStore();
    final tokens = WakeTokenStoreImpl(secureKeyStore: secure);
    final firstRegistered = Completer<void>();
    final releaseFirst = Completer<void>();
    final registered = <List<String>>[];
    var minted = 0;
    final issue = IssueWakeTokensUseCase(
      wakeTokenStore: tokens,
      mintToken: () => 'token-${++minted}',
      registerWakeTokens: (value) async {
        registered.add(List.of(value));
        if (registered.length == 1) {
          firstRegistered.complete();
          await releaseFirst.future;
        }
        return true;
      },
    );
    final startup = issue.issueForContacts(['A']);
    await firstRegistered.future;
    final contactAdded = issue.issueForContacts(['A', 'B']);
    await Future<void>.delayed(Duration.zero);
    expect(registered, hasLength(1));
    releaseFirst.complete();
    await Future.wait([startup, contactAdded]);
    expect(await tokens.readTokens(), {'A': 'token-1', 'B': 'token-2'});
    expect(registered.last, ['token-1', 'token-2']);
    expect(minted, 2);
  });

  test('coalesced storage failure is bounded and a later trigger recovers', () async {
    final recovered = Completer<void>();
    var attempts = 0;
    final coalescer = WakeTokenReissueCoalescer(
      window: Duration.zero,
      reissue: () async {
        if (++attempts == 1) throw StateError('storage unavailable');
        recovered.complete();
      },
    );
    addTearDown(coalescer.dispose);
    coalescer.trigger();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(attempts, 1);
    coalescer.trigger();
    await recovered.future;
    expect(attempts, 2);
  });

  test(
    'registered legacy tokens backfill once and survive a restart',
    () async {
      final secure = FakeSecureKeyStore();
      final tokens = WakeTokenStoreImpl(secureKeyStore: secure);
      await tokens.writeTokens({'existing-contact': 'recipient-issued-token'});
      Future<bool> issue() => IssueWakeTokensUseCase(
        wakeTokenStore: WakeTokenStoreImpl(secureKeyStore: secure),
        registerWakeTokens: (_) async => true,
        onTokensRegistered: (tokens) async {
          await reconcileWakeTokenDistribution(
            secureKeyStore: secure,
            registeredTokens: tokens,
          );
        },
      ).issueForContacts(['existing-contact']);

      await issue();
      expect(await readWakeTokenPendingMarker(secure), ['existing-contact']);
      // Restart before delivery keeps the obligation.
      await issue();
      expect(await readWakeTokenPendingMarker(secure), ['existing-contact']);
      await completeWakeTokenDistribution(
        secureKeyStore: secure,
        peerId: 'existing-contact',
        token: 'recipient-issued-token',
      );
      // Restart after successful authenticated delivery does not send again.
      await issue();
      expect(await readWakeTokenPendingMarker(secure), isEmpty);
      expect(
        await secure.read(kWakeTokenDistributionScheduledKey),
        isNot(contains('recipient-issued-token')),
      );
    },
  );

  test(
    'failed registration leaves token persisted for later backfill',
    () async {
      final secure = FakeSecureKeyStore();
      final tokens = WakeTokenStoreImpl(secureKeyStore: secure);
      var accepted = false;
      var scheduled = 0;
      final issue = IssueWakeTokensUseCase(
        wakeTokenStore: tokens,
        mintToken: () => 'token',
        registerWakeTokens: (_) async => accepted,
        onTokensRegistered: (tokens) async {
          scheduled++;
          await reconcileWakeTokenDistribution(
            secureKeyStore: secure,
            registeredTokens: tokens,
          );
        },
      );
      expect(await issue.issueForContacts(['contact']), isFalse);
      expect(await tokens.readTokens(), {'contact': 'token'});
      expect(scheduled, 0);
      accepted = true;
      expect(await issue.issueForContacts(['contact']), isTrue);
      expect(await readWakeTokenPendingMarker(secure), ['contact']);
    },
  );

  test('an older send cannot retire a newly rotated token', () async {
    final secure = FakeSecureKeyStore();
    await reconcileWakeTokenDistribution(
      secureKeyStore: secure,
      registeredTokens: {'contact': 'old-token'},
    );
    await reconcileWakeTokenDistribution(
      secureKeyStore: secure,
      registeredTokens: {'contact': 'new-token', 'new-contact': 'other-token'},
    );
    await completeWakeTokenDistribution(
      secureKeyStore: secure,
      peerId: 'contact',
      token: 'old-token',
    );
    expect(await readWakeTokenPendingMarker(secure), [
      'contact',
      'new-contact',
    ]);
    await completeWakeTokenDistribution(
      secureKeyStore: secure,
      peerId: 'contact',
      token: 'new-token',
    );
    expect(await readWakeTokenPendingMarker(secure), ['new-contact']);
  });

  test(
    'inactive contacts and empty tokens never become backfill targets',
    () async {
      final secure = FakeSecureKeyStore();
      await reconcileWakeTokenDistribution(
        secureKeyStore: secure,
        registeredTokens: {'removed': 'token'},
      );
      await reconcileWakeTokenDistribution(
        secureKeyStore: secure,
        registeredTokens: {'active': 'token', 'empty-token': ''},
      );
      expect(await readWakeTokenPendingMarker(secure), ['active']);
    },
  );
}
