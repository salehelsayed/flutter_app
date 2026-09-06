import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/push/application/wake_token_wiring.dart';
import 'package:flutter_app/features/push/domain/wake_token_store.dart';

// Ordinary builds must distribute the recipient-issued token needed by the
// reaction-push capability they advertise. Explicit rollback remains supported.
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
  const rollback =
      bool.hasEnvironment('MKNOON_EMIT_WAKE_TOKEN') &&
      !bool.fromEnvironment('MKNOON_EMIT_WAKE_TOKEN');
  test('ordinary builds resolve the recipient-issued wake token', () async {
    expect(shouldEmitWakeToken(), isTrue);
    final store = _SeededWakeTokenStore({'peerB': 'tok-B'});
    final resolver = buildWakeTokenResolver(store);
    expect(await resolver('peerB'), 'tok-B');
    expect(await resolver('missing-peer'), isNull);
  }, skip: rollback);
  test('explicit emission rollback does not distribute tokens', () async {
    expect(shouldEmitWakeToken(), isFalse);
    final resolver = buildWakeTokenResolver(
      _SeededWakeTokenStore({'peerB': 'tok-B'}),
    );
    expect(await resolver('peerB'), isNull);
  }, skip: !rollback);
}
