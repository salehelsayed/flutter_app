import 'dart:io';

import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late String? binding;
  late DateTime now;
  late _MemorySecureKeyStore secureStore;

  PendingConversationNotificationOverlayStore buildStore({
    Duration ttl = const Duration(hours: 1),
    int maxEntries = 256,
  }) => PendingConversationNotificationOverlayStore(
    directory: directory,
    resolveBinding: () async => binding,
    secureStore: secureStore,
    now: () => now,
    ttl: ttl,
    maxEntries: maxEntries,
  );

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'pending-conversation-notification-overlay-',
    );
    binding = 'v1:account-a';
    now = DateTime.utc(2026, 8, 3, 10);
    secureStore = _MemorySecureKeyStore();
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test(
    'unions distinct pre-materialization pushes and deduplicates exact id',
    () async {
      final store = buildStore();
      final canonical = _snapshot(<({String id, String line, int order})>[
        (id: 'old-a', line: 'old A', order: 1),
        (id: 'old-b', line: 'old B', order: 2),
      ]);

      final first = await store.project(
        conversationKey: 'peer-alice',
        canonicalSnapshot: canonical,
        currentMessage: const PendingConversationNotificationMessage(
          eventId: 'push-a',
          line: 'push A',
          occurredAtMicros: 3,
        ),
      );
      final second = await store.project(
        conversationKey: 'peer-alice',
        canonicalSnapshot: canonical,
        currentMessage: const PendingConversationNotificationMessage(
          eventId: 'push-b',
          line: 'push B',
          occurredAtMicros: 4,
        ),
      );
      final duplicate = await store.project(
        conversationKey: 'peer-alice',
        canonicalSnapshot: canonical,
        currentMessage: const PendingConversationNotificationMessage(
          eventId: 'push-b',
          line: 'push B duplicate transport',
          occurredAtMicros: 99,
        ),
      );

      expect(first?.totalUnreadMessageCount, 3);
      expect(first?.historyLines, <String>['old A', 'old B', 'push A']);
      expect(second?.totalUnreadMessageCount, 4);
      expect(second?.historyLines, <String>[
        'old A',
        'old B',
        'push A',
        'push B',
      ]);
      expect(duplicate?.totalUnreadMessageCount, 4);
      expect(duplicate?.historyLines, <String>[
        'old A',
        'old B',
        'push A',
        'push B duplicate transport',
      ]);
    },
  );

  test(
    'materialized ids retire pending entries without double counting',
    () async {
      final store = buildStore();
      await store.project(
        conversationKey: 'group:team',
        canonicalSnapshot: null,
        currentMessage: const PendingConversationNotificationMessage(
          eventId: 'message-a',
          line: 'Alice: A',
          occurredAtMicros: 10,
        ),
      );
      await store.project(
        conversationKey: 'group:team',
        canonicalSnapshot: null,
        currentMessage: const PendingConversationNotificationMessage(
          eventId: 'message-b',
          line: 'Bob: B',
          occurredAtMicros: 20,
        ),
      );

      final projected = await store.project(
        conversationKey: 'group:team',
        canonicalSnapshot: _snapshot(<({String id, String line, int order})>[
          (id: 'message-a', line: 'Alice: canonical A', order: 10),
        ]),
      );

      expect(projected?.totalUnreadMessageCount, 2);
      expect(projected?.historyLines, <String>['Alice: canonical A', 'Bob: B']);

      final reopened = buildStore();
      final afterRestart = await reopened.project(
        conversationKey: 'group:team',
        canonicalSnapshot: _snapshot(<({String id, String line, int order})>[
          (id: 'message-a', line: 'Alice: canonical A', order: 10),
          (id: 'message-b', line: 'Bob: canonical B', order: 20),
        ]),
      );
      expect(afterRestart?.totalUnreadMessageCount, 2);
      expect(afterRestart?.historyLines, <String>[
        'Alice: canonical A',
        'Bob: canonical B',
      ]);
    },
  );

  test(
    'renders newest five while retaining full canonical plus pending count',
    () async {
      final store = buildStore();
      for (var index = 0; index < 7; index++) {
        await store.project(
          conversationKey: 'peer-burst',
          canonicalSnapshot: null,
          currentMessage: PendingConversationNotificationMessage(
            eventId: 'event-$index',
            line: 'line $index',
            occurredAtMicros: index + 1,
          ),
        );
      }

      final projected = await store.project(
        conversationKey: 'peer-burst',
        canonicalSnapshot: null,
      );
      expect(projected?.totalUnreadMessageCount, 7);
      expect(projected?.historyLines, <String>[
        'line 2',
        'line 3',
        'line 4',
        'line 5',
        'line 6',
      ]);
    },
  );

  test(
    'reaction-style read does not add or increment an overlay event',
    () async {
      final store = buildStore();
      await store.project(
        conversationKey: 'group:reaction',
        canonicalSnapshot: null,
        currentMessage: const PendingConversationNotificationMessage(
          eventId: 'message-a',
          line: 'Alice: message',
          occurredAtMicros: 1,
        ),
      );

      final reactionProjection = await store.project(
        conversationKey: 'group:reaction',
        canonicalSnapshot: null,
      );
      expect(reactionProjection?.totalUnreadMessageCount, 1);
      expect(reactionProjection?.historyLines, <String>['Alice: message']);
    },
  );

  test(
    'explicit and lazy account cutover retire prior-account content',
    () async {
      final store = buildStore();
      await store.project(
        conversationKey: 'peer-account',
        canonicalSnapshot: null,
        currentMessage: const PendingConversationNotificationMessage(
          eventId: 'account-a-message',
          line: 'account A',
          occurredAtMicros: 1,
        ),
      );

      await store.rebind('v1:account-b');
      binding = 'v1:account-b';
      expect(
        await store.project(
          conversationKey: 'peer-account',
          canonicalSnapshot: null,
        ),
        isNull,
      );

      await store.project(
        conversationKey: 'peer-account',
        canonicalSnapshot: null,
        currentMessage: const PendingConversationNotificationMessage(
          eventId: 'account-b-message',
          line: 'account B',
          occurredAtMicros: 2,
        ),
      );
      binding = 'v1:account-c';
      expect(
        await store.project(
          conversationKey: 'peer-account',
          canonicalSnapshot: null,
        ),
        isNull,
      );
    },
  );

  test('TTL, maximum-entry pruning, and corrupt state fail safely', () async {
    final store = buildStore(ttl: const Duration(seconds: 1), maxEntries: 2);
    for (var index = 0; index < 3; index++) {
      await store.project(
        conversationKey: 'peer-prune',
        canonicalSnapshot: null,
        currentMessage: PendingConversationNotificationMessage(
          eventId: 'event-$index',
          line: 'line $index',
          occurredAtMicros: index + 1,
        ),
      );
    }
    final bounded = await store.project(
      conversationKey: 'peer-prune',
      canonicalSnapshot: null,
    );
    expect(bounded?.totalUnreadMessageCount, 2);
    expect(bounded?.historyLines, <String>['line 1', 'line 2']);

    now = now.add(const Duration(seconds: 2));
    expect(
      await store.project(
        conversationKey: 'peer-prune',
        canonicalSnapshot: null,
      ),
      isNull,
    );

    await secureStore.write(
      PendingConversationNotificationOverlayStore.secureStorageKey,
      '{ definitely not json',
    );
    final recovered = await store.project(
      conversationKey: 'peer-prune',
      canonicalSnapshot: null,
      currentMessage: const PendingConversationNotificationMessage(
        eventId: 'after-corruption',
        line: 'safe line',
        occurredAtMicros: 3,
      ),
    );
    expect(recovered?.totalUnreadMessageCount, 1);
    expect(recovered?.historyLines, <String>['safe line']);
  });

  test('secure write readback mismatch fails closed', () async {
    final store = buildStore();
    secureStore.corruptNextReadback = true;

    await expectLater(
      store.project(
        conversationKey: 'peer-readback',
        canonicalSnapshot: null,
        currentMessage: const PendingConversationNotificationMessage(
          eventId: 'event-a',
          line: 'private normalized line',
          occurredAtMicros: 1,
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'plaintext filesystem contains only an empty coordination lock',
    () async {
      final store = buildStore();
      await store.project(
        conversationKey: 'peer-filesystem',
        canonicalSnapshot: null,
        currentMessage: const PendingConversationNotificationMessage(
          eventId: 'event-filesystem',
          line: 'must remain in encrypted secure storage',
          occurredAtMicros: 1,
        ),
      );

      final entities = directory.listSync();
      expect(entities, hasLength(1));
      expect(
        entities.single.path,
        endsWith(PendingConversationNotificationOverlayStore.lockFileName),
      );
      expect((entities.single as File).readAsBytesSync(), isEmpty);
      final encryptedAuthorityBlob = await secureStore.read(
        PendingConversationNotificationOverlayStore.secureStorageKey,
      );
      expect(encryptedAuthorityBlob, contains('must remain in encrypted'));
    },
  );

  test('source contract never writes projection copy to a filesystem file', () {
    final source = File(
      'lib/features/push/application/'
      'pending_conversation_notification_overlay.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('writeAsString')));
    expect(source, isNot(contains('stateFileName')));
    expect(source, contains('_secureStore.write(secureStorageKey, encoded)'));
    expect(source, contains('_secureStore.read(secureStorageKey)'));
  });

  test(
    'production composition projects every notification path and account rebind',
    () {
      final background = File(
        'lib/features/push/application/background_message_handler.dart',
      ).readAsStringSync();
      final foreground = File(
        'lib/app/application_root.dart',
      ).readAsStringSync();
      final bootstrap = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final directProjection = File(
        'lib/app/bootstrap/'
        'production_canonical_direct_projection_composition.dart',
      ).readAsStringSync();
      final directReplay = File(
        'lib/app/bootstrap/'
        'production_canonical_direct_replay_composition.dart',
      ).readAsStringSync();
      final groupListener = File(
        'lib/features/groups/application/group_message_listener.dart',
      ).readAsStringSync();
      final directSnapshot = File(
        'lib/features/conversation/application/'
        'direct_conversation_notification_snapshot.dart',
      ).readAsStringSync();
      final groupSnapshot = File(
        'lib/features/groups/application/'
        'group_conversation_notification_snapshot.dart',
      ).readAsStringSync();
      final runtimeBinding = File(
        'lib/core/notifications/canonical_runtime_lease.dart',
      ).readAsStringSync();

      expect(
        background,
        contains(
          '_backgroundPendingConversationNotificationOverlayResolver =\n'
          '    PendingConversationNotificationOverlayStore.openDefault',
        ),
      );
      expect(
        foreground,
        contains('PendingConversationNotificationOverlayStore.openDefault()'),
      );
      expect(
        RegExp(
          r'pendingNotificationOverlay:\s*'
          r'pendingNotificationOverlayBindingPublisher',
        ).allMatches(bootstrap),
        hasLength(3),
        reason:
            'foreground must pass one overlay instance to each remaining owner',
      );
      // The stale-correlation repair consolidated the durable-materialization
      // and canonical-replacement snapshot paths behind one canonical-state
      // helper that projects the overlay exactly once; the two live paths
      // still pass the shared overlay directly. Coverage stays four paths.
      expect(
        RegExp(
          r'pendingNotificationOverlay:\s*'
          r'dependencies\.pendingNotificationOverlay',
        ).allMatches(directProjection),
        hasLength(2),
        reason:
            'both live snapshot paths must pass the shared overlay directly',
      );
      expect(
        RegExp(
          r'final overlay = dependencies\.pendingNotificationOverlay;',
        ).allMatches(directProjection),
        hasLength(1),
        reason: 'the canonical-state helper must read the one shared overlay',
      );
      expect(
        RegExp(r'await overlay\.project\(').allMatches(directProjection),
        hasLength(1),
        reason: 'the canonical-state helper projects the overlay exactly once',
      );
      expect(
        RegExp(
          r'await loadDirectCanonicalMessageState\(',
        ).allMatches(directProjection),
        hasLength(2),
        reason:
            'durable materialization and canonical replacement must both '
            'consume the overlay-projected canonical state',
      );
      expect(
        RegExp(
          r'pendingNotificationOverlay:\s*pendingNotificationOverlay',
        ).allMatches(directReplay),
        hasLength(1),
        reason: 'the shared direct replay owner must project reaction replay',
      );
      expect(
        RegExp(
          r'\bbuildProductionCanonicalDirectProjectionComposition\(',
        ).allMatches(bootstrap),
        hasLength(1),
      );
      expect(
        RegExp(
          r'\bProductionCanonicalDirectReplayComposition\(',
        ).allMatches(bootstrap),
        hasLength(1),
      );
      expect(
        bootstrap,
        contains(
          'pendingConversationNotificationOverlay:\n'
          '          pendingNotificationOverlayBindingPublisher',
        ),
      );
      expect(
        bootstrap,
        contains(
          'rebindPendingNotificationOverlay:\n'
          '                pendingNotificationOverlayBindingPublisher?.rebind',
        ),
      );
      expect(
        groupListener,
        contains(
          'pendingNotificationOverlay: '
          '_pendingConversationNotificationOverlay',
        ),
      );
      expect(directSnapshot, contains('pendingNotificationOverlay.project('));
      expect(groupSnapshot, contains('pendingNotificationOverlay.project('));
      expect(runtimeBinding, contains("operation: 'startup_bind'"));
      expect(runtimeBinding, contains("operation: 'startup_retire'"));
      expect(runtimeBinding, contains("operation: 'publish_account'"));
      expect(runtimeBinding, contains("operation: 'retire_account'"));
    },
  );

  test('shared overlay suite is pinned once in both curated lanes', () {
    final gates = File('scripts/run_test_gates.sh').readAsStringSync();
    const path =
        'test/features/push/application/'
        'pending_conversation_notification_overlay_test.dart';

    for (final lane in const <String>['ONE_TO_ONE_TESTS', 'GROUP_TESTS']) {
      expect(
        RegExp(RegExp.escape(path)).allMatches(_shellArray(gates, lane)),
        hasLength(1),
        reason: '$path must occur once in $lane',
      );
    }
  });
}

String _shellArray(String source, String name) {
  final startMarker = 'readonly $name=(';
  final start = source.indexOf(startMarker);
  if (start < 0) throw StateError('missing $name');
  final end = source.indexOf('\n)', start + startMarker.length);
  if (end < 0) throw StateError('unterminated $name');
  return source.substring(start + startMarker.length, end);
}

ConversationNotificationSnapshot _snapshot(
  List<({String id, String line, int order})> entries,
) => ConversationNotificationSnapshot(
  historyLines: entries.map((entry) => entry.line),
  totalUnreadMessageCount: entries.length,
  canonicalEventIds: entries.map((entry) => entry.id),
  orderedHistory: entries.map(
    (entry) => ConversationNotificationHistoryEntry(
      eventId: entry.id,
      line: entry.line,
      occurredAtMicros: entry.order,
    ),
  ),
);

final class _MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = <String, String>{};
  bool corruptNextReadback = false;

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    final value = values[key];
    if (corruptNextReadback && value != null) {
      corruptNextReadback = false;
      return '$value-corrupt';
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
