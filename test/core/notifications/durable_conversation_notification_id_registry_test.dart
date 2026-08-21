import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';
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
    'lookup finds an existing owner without allocating and missing or corrupt owners stay null',
    () async {
      const key = 'group:lookup-existing';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );
      final before = directory
          .listSync(followLinks: false)
          .map((entity) => entity.path)
          .toSet();

      expect(await registry.lookup(key), id);
      expect(await registry.lookup('group:lookup-missing'), isNull);
      expect(
        directory
            .listSync(followLinks: false)
            .map((entity) => entity.path)
            .toSet(),
        before,
        reason: 'lookup must never publish an owner or coordination file',
      );

      File('${directory.path}/$id.owner').writeAsStringSync('{corrupt-owner');
      expect(await registry.lookup(key), isNull);

      final absent = Directory('${directory.path}/never-created');
      expect(
        await DurableConversationNotificationIdRegistry(
          directory: absent,
        ).lookup('group:absent-directory'),
        isNull,
      );
      expect(absent.existsSync(), isFalse);
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

  test(
    'content kind is owner-bound durable and clears without releasing the id',
    () async {
      const key = 'group:content-kind-owner';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );

      await registry.recordContentKind(
        conversationKey: key,
        notificationId: id,
        kind: ConversationNotificationContentKind.reaction,
      );

      expect(
        await registry.lookupContentKind(
          conversationKey: key,
          notificationId: id,
        ),
        ConversationNotificationContentKind.reaction,
      );
      expect(
        await registry.lookupContentKind(
          conversationKey: 'group:different-owner',
          notificationId: id,
        ),
        isNull,
      );

      await registry.clearContentKind(conversationKey: key, notificationId: id);

      expect(
        await registry.lookupContentKind(
          conversationKey: key,
          notificationId: id,
        ),
        isNull,
      );
      expect(await registry.lookup(key), id);
    },
  );

  test('malformed content kind fails closed as unknown', () async {
    const key = 'group:malformed-content-kind';
    final registry = DurableConversationNotificationIdRegistry(
      directory: directory,
    );
    final id = await registry.resolve(
      key,
      activeNotificationIds: () async => const <Object?>[],
    );
    File(
      '${directory.path}/$id'
      '${DurableConversationNotificationIdRegistry.contentKindFileSuffix}',
    ).writeAsStringSync('message\nreaction');

    expect(
      await registry.lookupContentKind(
        conversationKey: key,
        notificationId: id,
      ),
      isNull,
    );
  });

  test('content metadata survives a fresh registry reopen', () async {
    const key = 'group:content-metadata-reopen';
    final first = DurableConversationNotificationIdRegistry(
      directory: directory,
    );
    final id = await first.resolve(
      key,
      activeNotificationIds: () async => const <Object?>[],
    );
    const expected = ConversationNotificationContentMetadata(
      kind: ConversationNotificationContentKind.message,
      eventIdentity: 'message-reopen',
      generation: 'generation-reopen',
    );

    await first.recordContentMetadata(
      conversationKey: key,
      notificationId: id,
      metadata: expected,
    );

    final reopened = DurableConversationNotificationIdRegistry(
      directory: directory,
    );
    expect(
      await reopened.lookupContentMetadata(
        conversationKey: key,
        notificationId: id,
      ),
      expected,
    );
    expect(
      await reopened.lookupContentKind(
        conversationKey: key,
        notificationId: id,
      ),
      ConversationNotificationContentKind.message,
    );
  });

  test(
    'replacement proves metadata storage before retiring or showing a card',
    () async {
      const key = 'group:metadata-preflight';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );
      Directory(
        '${directory.path}/$id'
        '${DurableConversationNotificationIdRegistry.contentKindFileSuffix}',
      ).createSync();
      var showCalls = 0;

      await expectLater(
        registry.replaceContent(
          conversationKey: key,
          notificationId: id,
          metadata: const ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.message,
            eventIdentity: 'message-preflight',
            generation: 'generation-preflight',
          ),
          replace: () async => showCalls += 1,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(showCalls, 0);
    },
  );

  test(
    'failed native replacement preserves the visible card metadata',
    () async {
      const key = 'group:failed-native-replacement';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );
      await registry.recordContentMetadata(
        conversationKey: key,
        notificationId: id,
        metadata: const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'reaction-before',
          generation: 'generation-before',
        ),
      );
      await expectLater(
        registry.replaceContent(
          conversationKey: key,
          notificationId: id,
          metadata: const ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.message,
            eventIdentity: 'message-after',
            generation: 'generation-after',
          ),
          replace: () async => throw StateError('native show failed'),
        ),
        throwsStateError,
      );

      expect(
        await registry.lookupContentMetadata(
          conversationKey: key,
          notificationId: id,
        ),
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'reaction-before',
          generation: 'generation-before',
        ),
      );
    },
  );

  test(
    'generation replacement is atomic and a stale generation cannot overwrite it',
    () async {
      const key = 'group:canonical-rebuild';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );
      await registry.recordContentMetadata(
        conversationKey: key,
        notificationId: id,
        metadata: const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'removed-reaction',
          generation: 'generation-before',
        ),
      );
      final operations = <String>[];

      expect(
        await registry.replaceContentIfGeneration(
          conversationKey: key,
          notificationId: id,
          expectedGeneration: 'generation-before',
          metadata: const ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.message,
            eventIdentity: 'older-unread-message',
            generation: 'generation-after',
          ),
          replace: () async => operations.add('replace'),
        ),
        isTrue,
      );
      expect(operations, <String>['replace']);
      expect(
        await registry.lookupContentMetadata(
          conversationKey: key,
          notificationId: id,
        ),
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'older-unread-message',
          generation: 'generation-after',
        ),
      );

      expect(
        await registry.replaceContentIfGeneration(
          conversationKey: key,
          notificationId: id,
          expectedGeneration: 'generation-before',
          metadata: const ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.message,
            eventIdentity: 'stale-message',
            generation: 'stale-generation',
          ),
          replace: () async => operations.add('stale-replace'),
        ),
        isFalse,
      );
      expect(operations, <String>['replace']);
    },
  );

  test(
    'same-kind conditional cancellation validates the current event under lock',
    () async {
      const key = 'group:same-kind-event-race';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );
      const current = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: 'new-unread-message',
        generation: 'new-generation',
      );
      await registry.recordContentMetadata(
        conversationKey: key,
        notificationId: id,
        metadata: current,
      );
      var cancelCalls = 0;

      final staleReadCancelled = await registry.cancelContentIfKind(
        conversationKey: key,
        notificationId: id,
        kind: ConversationNotificationContentKind.message,
        shouldCancel: (metadata) async =>
            metadata.eventIdentity == 'old-read-message',
        cancel: () async => cancelCalls += 1,
      );

      expect(staleReadCancelled, isFalse);
      expect(cancelCalls, 0);
      expect(
        await registry.lookupContentMetadata(
          conversationKey: key,
          notificationId: id,
        ),
        current,
      );

      final exactReadCancelled = await registry.cancelContentIfKind(
        conversationKey: key,
        notificationId: id,
        kind: ConversationNotificationContentKind.message,
        shouldCancel: (metadata) async =>
            metadata.eventIdentity == 'new-unread-message',
        cancel: () async => cancelCalls += 1,
      );

      expect(exactReadCancelled, isTrue);
      expect(cancelCalls, 1);
      expect(
        await registry.lookupContentMetadata(
          conversationKey: key,
          notificationId: id,
        ),
        isNull,
      );
      expect(await registry.lookup(key), id);
    },
  );

  test(
    'tap cancellation matches an exact generation and no older one',
    () async {
      const key = 'group:tap-generation';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );
      await registry.recordContentMetadata(
        conversationKey: key,
        notificationId: id,
        metadata: const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'reaction-current',
          generation: 'generation-current',
        ),
      );
      var cancelCalls = 0;

      expect(
        await registry.cancelContentIfGeneration(
          conversationKey: key,
          notificationId: id,
          generation: 'generation-old',
          cancel: () async => cancelCalls += 1,
        ),
        isFalse,
      );
      expect(cancelCalls, 0);
      expect(
        await registry.cancelContentIfGeneration(
          conversationKey: key,
          notificationId: id,
          generation: 'generation-current',
          cancel: () async => cancelCalls += 1,
        ),
        isTrue,
      );
      expect(cancelCalls, 1);
    },
  );

  test(
    'eligibility snapshot loses CAS when a newer same-kind generation arrives',
    () async {
      const key = 'group:same-kind-cas';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );
      await registry.recordContentMetadata(
        conversationKey: key,
        notificationId: id,
        metadata: const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'message-g1',
          generation: 'generation-g1',
        ),
      );
      final eligibilityEntered = Completer<void>();
      final releaseEligibility = Completer<void>();
      var nativeCancelCalls = 0;
      final cancellation = registry.cancelContentIfKind(
        conversationKey: key,
        notificationId: id,
        kind: ConversationNotificationContentKind.message,
        shouldCancel: (_) async {
          eligibilityEntered.complete();
          await releaseEligibility.future;
          return true;
        },
        cancel: () async => nativeCancelCalls += 1,
      );
      await eligibilityEntered.future;

      await registry.replaceContent(
        conversationKey: key,
        notificationId: id,
        metadata: const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'message-g2',
          generation: 'generation-g2',
        ),
        replace: () async {},
      );
      releaseEligibility.complete();

      expect(await cancellation, isFalse);
      expect(nativeCancelCalls, 0);
      expect(
        await registry.lookupContentMetadata(
          conversationKey: key,
          notificationId: id,
        ),
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'message-g2',
          generation: 'generation-g2',
        ),
      );
    },
  );

  test(
    'fresh isolates serialize native cancel before reaction replacement show',
    () async {
      const key = 'group:isolate-cancel-first';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );
      await registry.recordContentMetadata(
        conversationKey: key,
        notificationId: id,
        metadata: const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'message-isolate',
          generation: 'generation-message-isolate',
        ),
      );
      final rootPath = directory.path;
      final cancelEnteredPath = '$rootPath/cancel-entered';
      final releaseCancelPath = '$rootPath/release-cancel';
      final replacementShownPath = '$rootPath/replacement-shown';
      final cancelEntered = File(cancelEnteredPath);
      final releaseCancel = File(releaseCancelPath);
      final replacementShown = File(replacementShownPath);

      final cancel = Isolate.run(() async {
        final isolated = DurableConversationNotificationIdRegistry(
          directory: Directory(rootPath),
        );
        return isolated.cancelContentIfKind(
          conversationKey: key,
          notificationId: id,
          kind: ConversationNotificationContentKind.message,
          shouldCancel: (_) async => true,
          cancel: () async {
            await File(cancelEnteredPath).create();
            await _waitForFile(File(releaseCancelPath));
          },
        );
      });
      await _waitForFile(cancelEntered);

      final replacement = Isolate.run(() async {
        final isolated = DurableConversationNotificationIdRegistry(
          directory: Directory(rootPath),
        );
        return isolated.replaceContent(
          conversationKey: key,
          notificationId: id,
          metadata: const ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.reaction,
            eventIdentity: 'reaction-isolate',
            generation: 'generation-reaction-isolate',
          ),
          replace: () async => File(replacementShownPath).create(),
        );
      });
      await Future<void>.delayed(const Duration(milliseconds: 75));
      expect(replacementShown.existsSync(), isFalse);

      await releaseCancel.create();
      expect(await cancel, isTrue);
      await replacement;
      expect(replacementShown.existsSync(), isTrue);
      expect(
        await registry.lookupContentKind(
          conversationKey: key,
          notificationId: id,
        ),
        ConversationNotificationContentKind.reaction,
      );
    },
  );

  test(
    'fresh isolate message cancellation preserves in-flight reaction replacement',
    () async {
      const key = 'group:isolate-replace-first';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );
      await registry.recordContentMetadata(
        conversationKey: key,
        notificationId: id,
        metadata: const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'message-before-reaction',
          generation: 'generation-before-reaction',
        ),
      );
      final rootPath = directory.path;
      final showEnteredPath = '$rootPath/show-entered';
      final releaseShowPath = '$rootPath/release-show';
      final nativeCancelPath = '$rootPath/unexpected-native-cancel';
      final showEntered = File(showEnteredPath);
      final releaseShow = File(releaseShowPath);
      final nativeCancel = File(nativeCancelPath);

      final replacement = Isolate.run(() async {
        final isolated = DurableConversationNotificationIdRegistry(
          directory: Directory(rootPath),
        );
        return isolated.replaceContent(
          conversationKey: key,
          notificationId: id,
          metadata: const ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.reaction,
            eventIdentity: 'reaction-current',
            generation: 'generation-reaction-current',
          ),
          replace: () async {
            await File(showEnteredPath).create();
            await _waitForFile(File(releaseShowPath));
          },
        );
      });
      await _waitForFile(showEntered);

      final cancellation = Isolate.run(() async {
        final isolated = DurableConversationNotificationIdRegistry(
          directory: Directory(rootPath),
        );
        return isolated.cancelContentIfKind(
          conversationKey: key,
          notificationId: id,
          kind: ConversationNotificationContentKind.message,
          cancel: () async => File(nativeCancelPath).create(),
        );
      });

      var cancellationCompleted = false;
      unawaited(cancellation.whenComplete(() => cancellationCompleted = true));
      await Future<void>.delayed(const Duration(milliseconds: 75));
      expect(cancellationCompleted, isFalse);
      expect(nativeCancel.existsSync(), isFalse);
      await releaseShow.create();
      await replacement;
      expect(await cancellation, isFalse);
      expect(
        await registry.lookupContentKind(
          conversationKey: key,
          notificationId: id,
        ),
        ConversationNotificationContentKind.reaction,
      );
    },
  );

  test(
    'TC-372-05b one coordination lock rejects reentrant and inverse acquisition',
    () async {
      const key = 'peer-final-effect-reentrant';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        key,
        activeNotificationIds: () async => const <Object?>[],
      );
      final identity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: key,
      )!;
      final context = DurableLocalNotificationEffectContext(
        currentOpaqueBinding: 'v1:${'a' * 64}',
        eventCorrelation: 'b' * 64,
        conversationDigest: identity.digest,
        producerKind: LocalNotificationProducerKind.directMessage,
        sourceCustody: LocalNotificationSourceCustody.sqlReady,
        presentationOwner: LocalNotificationPresentationOwner.mainApp,
        readFinalCanonicalDisposition: () async {
          // Public registry entry while runFinalEffect owns the same lock must
          // fail immediately. Waiting on the isolate tail would deadlock.
          await registry.recordContentMetadata(
            conversationKey: key,
            notificationId: id,
            metadata: const ConversationNotificationContentMetadata(
              kind: ConversationNotificationContentKind.message,
              eventIdentity: 'reentrant-event',
              generation: 'reentrant-generation',
            ),
          );
          return DurableLocalNotificationCanonicalDisposition.eligible;
        },
      );
      expect(
        await LocalNotificationLedgerStore(
          directory: directory,
        ).initializeOrRebind(
          currentOpaqueBinding: context.currentOpaqueBinding,
        ),
        isNotNull,
      );

      await expectLater(
        registry.runFinalEffect(
          context: context,
          appVisibility: _FixedVisibility(),
          conversationIdentity: identity,
          conversationKey: key,
          notificationId: id,
          metadata: const ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.message,
            eventIdentity:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            generation: 'final-effect-generation',
          ),
          retireCurrent: () async {},
          publishNative: () async => fail('native must not be entered'),
        ),
        throwsA(
          isA<NotificationIdAllocationException>().having(
            (error) => error.operation,
            'operation',
            'registry_lock_reentrant',
          ),
        ),
      );

      // The rejected nested acquisition did not poison the registry tail.
      expect(await registry.lookup(key), id);

      // A direct ledger owner and the registry share the same isolate-level
      // serializer on Darwin. The second blocking flock must be queued in
      // Dart so the first asynchronous callback can resume and release it.
      final contentionDirectory = Directory('${directory.path}/contention');
      final storeEntered = Completer<void>();
      final releaseStore = Completer<void>();
      final contenderCompleted = Completer<void>();
      final originalPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final blockingStore = LocalNotificationLedgerStore(
          directory: contentionDirectory,
          beforeRename: (prepared, target) async {
            storeEntered.complete();
            await releaseStore.future;
          },
        );
        final storeOwner = blockingStore.initializeOrRebind(
          currentOpaqueBinding: context.currentOpaqueBinding,
        );
        await storeEntered.future.timeout(const Duration(seconds: 2));

        final contendingRegistry = DurableConversationNotificationIdRegistry(
          directory: contentionDirectory,
        );
        final contender = contendingRegistry
            .resolve(
              'peer-store-registry-contention',
              activeNotificationIds: () async => const <Object?>[],
            )
            .whenComplete(contenderCompleted.complete);
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(contenderCompleted.isCompleted, isFalse);

        releaseStore.complete();
        expect(await storeOwner.timeout(const Duration(seconds: 2)), isNotNull);
        expect(await contender.timeout(const Duration(seconds: 2)), isNotNull);
      } finally {
        debugDefaultTargetPlatformOverride = originalPlatform;
        if (!releaseStore.isCompleted) releaseStore.complete();
      }
    },
  );
}

final class _FixedVisibility extends AppVisibilitySuppressionReader {
  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async => const AppVisibilityEvaluation(
    isForegroundActive: false,
    maySuppress: false,
    lifecycle: AppVisibilityLifecycle.background,
    revision: 1,
    lifecycleGeneration: 1,
  );
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
