import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/push/application/wake_token_wiring.dart';
import 'package:flutter_app/features/push/domain/wake_token_store.dart';

// FDC-09 §12 / CV-14 (217 §C1b / A17) — INV-2 ship-order lock, proven against the
// REAL wiring (not a test-local copy): with MKNOON_EMIT_WAKE_TOKEN unset, the
// production emission factory is false AND the production resolver yields null
// even for a peer that HAS a minted token — so sendContactRequest emits no `wt`.
//
// Mutation: flip the PRODUCTION factory's defaultValue (wake_token_wiring.dart)
// to true → both assertions red. If the mutation is applied and this still
// passes, it is a FAKE LOCK (asserting a copy, not the production seam).
class _SeededWakeTokenStore implements WakeTokenStore {
  _SeededWakeTokenStore(this._tokens);
  final Map<String, String> _tokens;

  @override
  Future<Map<String, String>> readTokens() async =>
      Map<String, String>.from(_tokens);

  @override
  Future<void> writeTokens(Map<String, String> tokens) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  test(
    'the REAL wake-token wiring emits nothing when MKNOON_EMIT_WAKE_TOKEN is unset',
    () async {
      // The PRODUCTION factory — imported, never reconstructed locally.
      expect(shouldEmitWakeToken(), isFalse);

      // The real resolver yields null for a peer that HAS a minted token,
      // because emission is gated OFF (the dark-landing default).
      final store = _SeededWakeTokenStore({'peerB': 'tok-B'});
      final resolver = buildWakeTokenResolver(store);
      expect(await resolver('peerB'), isNull);
    },
  );
}
