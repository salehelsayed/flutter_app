import 'dart:io';
import 'dart:isolate';

import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'notification-id-registry-',
    );
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test(
    'P269 dedicated iOS profile forces reset-owned local id storage',
    () async {
      final support = Directory('${directory.path}/support')..createSync();
      var appGroupCalls = 0;

      final registry =
          await DurableConversationNotificationIdRegistry.openDefault(
            useIosAppGroup: true,
            installedProfileId: groupMediaIosDisposableBuildProfile,
            appGroupPathChannel: AppGroupPathChannel(
              invoker: (_, _) async {
                appGroupCalls += 1;
                return '/forbidden-production-app-group';
              },
            ),
            supportDirectory: () async => support,
          );

      expect(appGroupCalls, 0);
      expect(
        registry.directory.path,
        '${support.path}/NotificationConversationIds',
      );
      expect(
        await registry.resolve(
          'p269-local-conversation',
          activeNotificationIds: () async => const <Object?>[],
        ),
        isNonNegative,
      );
    },
  );

  test(
    'keeps the existing deterministic id as the primary candidate',
    () async {
      const key = '12D3KooWPrimaryConversation';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );

      final id = await registry.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );

      expect(id, deterministicConversationNotificationId(key));
    },
  );

  test(
    'forced collision keeps direct, group, and announcement cards distinct',
    () async {
      const keys = <String>[
        '12D3KooWDirect',
        'group:discussion-group',
        'group:announcement-group',
      ];
      final fallbackByKey = <String, int>{
        keys[0]: 101,
        keys[1]: 102,
        keys[2]: 103,
      };
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
        candidateGenerator: (key, probe) =>
            probe == 0 ? 77 : fallbackByKey[key]! + probe - 1,
      );

      final ids = <int>[];
      for (final key in keys) {
        ids.add(
          await registry.resolve(
            key,
            activeNotificationIds: () async => const <Object?>[],
          ),
        );
      }

      expect(ids.toSet(), hasLength(3));
      expect(ids.first, 77);
    },
  );

  test(
    'same conversation coalesces and survives a process-style reopen',
    () async {
      const key = 'group:restart-stable';
      final first = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await first.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );

      final reopened = DurableConversationNotificationIdRegistry(
        directory: Directory(directory.path),
      );
      final reopenedId = await reopened.resolve(
        key,
        activeNotificationIds: () async => throw StateError('must not query'),
      );

      expect(reopenedId, id);
    },
  );

  test(
    'concurrent registry instances serialize colliding allocations',
    () async {
      final fallbacks = <String, int>{'peer-a': 201, 'peer-b': 202};
      DurableConversationNotificationIdRegistry build() =>
          DurableConversationNotificationIdRegistry(
            directory: Directory(directory.path),
            candidateGenerator: (key, probe) =>
                probe == 0 ? 55 : fallbacks[key]! + probe - 1,
          );

      final ids = await Future.wait(<Future<int>>[
        build().resolve(
          'peer-a',
          activeNotificationIds: () async => const <Object?>[],
        ),
        build().resolve(
          'peer-b',
          activeNotificationIds: () async => const <Object?>[],
        ),
      ]);
      final sameOwnerIds = await Future.wait(<Future<int>>[
        build().resolve(
          'peer-a',
          activeNotificationIds: () async => throw StateError('must not query'),
        ),
        build().resolve(
          'peer-a',
          activeNotificationIds: () async => throw StateError('must not query'),
        ),
      ]);

      expect(ids.toSet(), hasLength(2));
      expect(sameOwnerIds, everyElement(ids.first));
    },
  );

  test(
    'coordinated isolates prove flock collision and same-owner stability',
    () async {
      final collisionRoot = Directory('${directory.path}/collision');
      final first = _resolveRegistryInFreshIsolate(
        collisionRoot.path,
        key: 'peer-a',
        label: 'collision-a',
      );
      final second = _resolveRegistryInFreshIsolate(
        collisionRoot.path,
        key: 'peer-b',
        label: 'collision-b',
      );
      await _waitForFile(File('${collisionRoot.path}/ready-collision-a'));
      await _waitForFile(File('${collisionRoot.path}/ready-collision-b'));
      await File('${collisionRoot.path}/start').create();
      final collidingIds = await Future.wait([first, second]);
      expect(collidingIds.toSet(), hasLength(2));
      expect(collidingIds, contains(55));

      final stableRoot = Directory('${directory.path}/same-owner');
      final stableFirst = _resolveRegistryInFreshIsolate(
        stableRoot.path,
        key: 'peer-stable',
        label: 'stable-a',
      );
      final stableSecond = _resolveRegistryInFreshIsolate(
        stableRoot.path,
        key: 'peer-stable',
        label: 'stable-b',
      );
      await _waitForFile(File('${stableRoot.path}/ready-stable-a'));
      await _waitForFile(File('${stableRoot.path}/ready-stable-b'));
      await File('${stableRoot.path}/start').create();
      final stableIds = await Future.wait([stableFirst, stableSecond]);
      expect(stableIds.toSet(), hasLength(1));
    },
  );

  test(
    'corrupt numeric owners and opaque active ids stay occupied while invalid active identifiers are ignored',
    () async {
      File('${directory.path}/77.owner').writeAsStringSync('{malformed');
      File('${directory.path}/remote-id.owner').writeAsStringSync('ignored');
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
        maxProbeAttempts: 4,
        candidateGenerator: (_, probe) => <int>[77, 88, 99, 100][probe],
      );

      final id = await registry.resolve(
        'peer-private-corruption',
        activeNotificationIds: () async => const <Object?>[
          'remote-id',
          null,
          -1,
          0x80000000,
          88,
        ],
      );

      expect(id, 99);
      expect(
        File('${directory.path}/88.owner').readAsStringSync(),
        'opaque-active',
      );
      final reopened = DurableConversationNotificationIdRegistry(
        directory: Directory(directory.path),
        candidateGenerator: (_, probe) => <int>[77, 88, 99, 100][probe],
      );
      expect(
        await reopened.resolve(
          'peer-private-corruption',
          activeNotificationIds: () async => throw StateError('must not query'),
        ),
        99,
      );
    },
  );

  test(
    'legacy active primary is opaque and receives a stable fallback',
    () async {
      const key = 'group:legacy-active';
      final primary = deterministicConversationNotificationId(key);
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );

      final allocated = await registry.resolve(
        key,
        activeNotificationIds: () async => <Object?>[primary],
      );

      expect(allocated, isNot(primary));
      expect(
        File('${directory.path}/$primary.owner').readAsStringSync(),
        'opaque-active',
      );
      expect(
        await DurableConversationNotificationIdRegistry(
          directory: Directory(directory.path),
        ).resolve(
          key,
          activeNotificationIds: () async => throw StateError('must not query'),
        ),
        allocated,
      );
    },
  );

  test(
    'active query failure fails closed only for an unassigned owner',
    () async {
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );

      await expectLater(
        registry.resolve(
          'peer-new',
          activeNotificationIds: () async => throw StateError('plugin offline'),
        ),
        throwsA(
          isA<NotificationIdAllocationException>().having(
            (error) => error.operation,
            'operation',
            'active_notification_query',
          ),
        ),
      );

      final assigned = await registry.resolve(
        'peer-new',
        activeNotificationIds: () async => const <Object?>[],
      );
      expect(
        await registry.resolve(
          'peer-new',
          activeNotificationIds: () async => throw StateError('plugin offline'),
        ),
        assigned,
      );
    },
  );

  test(
    'storage failure is redacted and never exposes the conversation',
    () async {
      final blockedPath = '${directory.path}/not-a-directory';
      File(blockedPath).writeAsStringSync('blocked');
      final registry = DurableConversationNotificationIdRegistry(
        directory: Directory(blockedPath),
      );

      late NotificationIdAllocationException failure;
      try {
        await registry.resolve(
          'peer-ultra-private',
          activeNotificationIds: () async => const <Object?>[],
        );
        fail('expected storage failure');
      } on NotificationIdAllocationException catch (error) {
        failure = error;
      }

      expect(failure.operation, 'registry_storage');
      expect(failure.toString(), isNot(contains('peer-ultra-private')));
    },
  );

  test('bounded probing reports exhaustion without reusing an owner', () async {
    final registry = DurableConversationNotificationIdRegistry(
      directory: directory,
      maxProbeAttempts: 3,
      candidateGenerator: (_, _) => 7,
    );
    expect(
      await registry.resolve(
        'first-owner',
        activeNotificationIds: () async => const <Object?>[],
      ),
      7,
    );

    await expectLater(
      registry.resolve(
        'second-owner',
        activeNotificationIds: () async => const <Object?>[],
      ),
      throwsA(
        isA<NotificationIdAllocationException>().having(
          (error) => error.operation,
          'operation',
          'candidate_exhausted',
        ),
      ),
    );
  });

  test('published owner files are atomic, hashed, and private-safe', () async {
    const key = '12D3KooWDoNotPersistThisRawPeer';
    final registry = DurableConversationNotificationIdRegistry(
      directory: directory,
    );

    await registry.resolve(
      key,
      activeNotificationIds: () async => const <Object?>[],
    );

    final entities = directory.listSync();
    expect(entities.where((entity) => entity.path.endsWith('.tmp')), isEmpty);
    final ownerFile = entities.whereType<File>().singleWhere(
      (file) => file.path.endsWith('.owner'),
    );
    final storedOwner = ownerFile.readAsStringSync();
    expect(storedOwner, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(ownerFile.path, isNot(contains(key)));
    expect(storedOwner, isNot(contains(key)));
  });
}

Future<int> _resolveRegistryInFreshIsolate(
  String path, {
  required String key,
  required String label,
}) {
  return Isolate.run(() async {
    final root = Directory(path);
    await root.create(recursive: true);
    await File('${root.path}/ready-$label').create();
    await _waitForFile(File('${root.path}/start'));
    return DurableConversationNotificationIdRegistry(
      directory: root,
      candidateGenerator: (normalizedKey, probe) {
        if (probe == 0) return 55;
        return switch (normalizedKey) {
          'peer-a' => 200 + probe,
          'peer-b' => 300 + probe,
          'peer-stable' => 400 + probe,
          _ => 500 + probe,
        };
      },
    ).resolve(key, activeNotificationIds: () async => const <Object?>[]);
  });
}

Future<void> _waitForFile(File file) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await file.exists()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('timed out waiting for ${file.path}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
