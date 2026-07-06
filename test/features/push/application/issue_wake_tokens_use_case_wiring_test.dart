import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/issue_wake_tokens_use_case.dart';
import 'package:flutter_app/features/push/application/wake_token_wiring.dart';
import 'package:flutter_app/features/push/domain/wake_token_store.dart';

import '../../../core/bridge/fake_bridge.dart';

// FDC-09 §12 / CV-14 (217 §A1 §F4 / A08) — the LIVE recipient-leg wiring: the
// total register-callback wrapper degrades a throwing bridge to false (never
// throws / spams), and issueForContacts reconciles the persisted set DOWN to the
// active contact list (archived/blocked contacts lose their minted token).
class _InMemoryWakeTokenStore implements WakeTokenStore {
  Map<String, String> tokens = {};

  @override
  Future<Map<String, String>> readTokens() async =>
      Map<String, String>.from(tokens);

  @override
  Future<void> writeTokens(Map<String, String> t) async =>
      tokens = Map<String, String>.from(t);

  @override
  Future<void> clear() async => tokens = {};
}

void main() {
  late List<Map<String, dynamic>> events;

  setUp(() {
    flowEventLoggingEnabled = false;
    events = [];
    debugSetFlowEventSink((p) => events.add(Map<String, dynamic>.from(p)));
  });

  tearDown(() => debugSetFlowEventSink(null));

  List<Map<String, dynamic>> eventsNamed(String name) =>
      events.where((e) => e['event'] == name).toList();

  test(
    'total register callback: a throwing bridge ⇒ false, persists the minted '
    'tokens, emits unsupported, and NEVER throws',
    () async {
      final store = _InMemoryWakeTokenStore();
      final bridge = FakeBridge()..throwOnSend = true;

      final useCase = IssueWakeTokensUseCase(
        wakeTokenStore: store,
        registerWakeTokens: (tokens) =>
            registerWakeTokensViaBridge(bridge, tokens),
        mintToken: () => 'tok-x',
      );

      // Must NOT throw — the wrapper absorbs the bridge failure.
      final ok = await useCase.issueForContacts(['c1']);

      expect(ok, isFalse);
      expect(store.tokens['c1'], 'tok-x'); // minted + persisted regardless
      expect(eventsNamed('WAKE_TOKEN_REGISTER_UNSUPPORTED'), hasLength(1));
    },
  );

  test(
    'reconcile-down: an archived contact loses its token in the persisted map '
    'AND the re-registered set',
    () async {
      final store = _InMemoryWakeTokenStore()
        ..tokens = {'A': 'tA', 'B': 'tB', 'C': 'tC'};
      final registered = <List<String>>[];

      final useCase = IssueWakeTokensUseCase(
        wakeTokenStore: store,
        registerWakeTokens: (t) async {
          registered.add(t);
          return true;
        },
        mintToken: () => 'tok-SHOULD-NOT-BE-USED',
      );

      // B is no longer active (archived/blocked/removed).
      final ok = await useCase.issueForContacts(['A', 'C']);

      expect(ok, isTrue);
      expect(store.tokens.keys, unorderedEquals(['A', 'C']));
      expect(store.tokens.containsKey('B'), isFalse);
      // B's token is not re-registered with the relay.
      expect(registered.single.toSet(), {'tA', 'tC'});
      expect(eventsNamed('WAKE_TOKEN_PRUNED'), hasLength(1));
    },
  );
}
