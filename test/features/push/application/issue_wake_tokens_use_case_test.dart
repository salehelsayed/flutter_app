import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/issue_wake_tokens_use_case.dart';
import 'package:flutter_app/features/push/domain/wake_token_store.dart';

// FDC-09 §12 — IssueWakeTokensUseCase: mints a per-contact opaque wake-token,
// persists the {contact -> token} map, registers the SET, and degrades
// gracefully against an old relay (NET-REL-07).

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

  // TC-09-14 — mints a per-contact token, registers the SET, persists, and (on
  // reload) re-uses the persisted tokens (mints none new).
  test('TC-09-14: mints/registers/persists per-contact wake-tokens', () async {
    final store = _InMemoryWakeTokenStore();
    final registered = <List<String>>[];
    Future<bool> registrar(List<String> t) async {
      registered.add(t);
      return true;
    }

    var n = 0;
    final useCase = IssueWakeTokensUseCase(
      wakeTokenStore: store,
      registerWakeTokens: registrar,
      mintToken: () => 'tok-${n++}',
    );

    final ok = await useCase.issueForContacts(['c1', 'c2']);

    expect(ok, isTrue);
    expect(store.tokens.keys, containsAll(['c1', 'c2']));
    expect(registered.single.toSet(), {'tok-0', 'tok-1'});
    expect(eventsNamed('WAKE_TOKEN_ISSUED'), hasLength(2));

    // Reload: a fresh use-case over the SAME (persisted) store mints NO new
    // tokens and re-registers the same set.
    registered.clear();
    final reloaded = IssueWakeTokensUseCase(
      wakeTokenStore: store,
      registerWakeTokens: registrar,
      mintToken: () => 'tok-SHOULD-NOT-BE-USED',
    );
    await reloaded.issueForContacts(['c1', 'c2']);

    expect(store.tokens['c1'], 'tok-0'); // survived reload, unchanged
    expect(store.tokens['c2'], 'tok-1');
    expect(registered.single.toSet(), {'tok-0', 'tok-1'});
  });

  // TC-09-15 (NET-REL-07) — an old relay that rejects the registration degrades
  // gracefully: the minted tokens are still persisted client-side, the call
  // returns false (does not throw / retry), and emits the unsupported event.
  test(
    'TC-09-15: old relay rejects registration → graceful degrade, no throw',
    () async {
      final store = _InMemoryWakeTokenStore();
      Future<bool> oldRelayRegistrar(List<String> t) async => false;

      final useCase = IssueWakeTokensUseCase(
        wakeTokenStore: store,
        registerWakeTokens: oldRelayRegistrar,
        mintToken: () => 'tok-x',
      );

      final ok = await useCase.issueForContacts(['c1']);

      expect(ok, isFalse); // unsupported / failed
      expect(store.tokens['c1'], 'tok-x'); // minted + persisted regardless
      expect(eventsNamed('WAKE_TOKEN_REGISTER_UNSUPPORTED'), hasLength(1));
    },
  );

  test(
    'no contacts registers an empty set to revoke stale relay auth',
    () async {
      final store = _InMemoryWakeTokenStore();
      var registrarCalls = 0;
      final useCase = IssueWakeTokensUseCase(
        wakeTokenStore: store,
        registerWakeTokens: (t) async {
          registrarCalls++;
          return true;
        },
      );

      final ok = await useCase.issueForContacts([]);

      expect(ok, isTrue);
      expect(store.tokens, isEmpty);
      expect(registrarCalls, 1);
      expect(eventsNamed('WAKE_TOKEN_ISSUED'), isEmpty);
    },
  );
}
