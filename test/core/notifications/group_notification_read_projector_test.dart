import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/group_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/group_notification_read_projector.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'read zero racing new message cannot erase the new group card',
    () async {
      final coordinator = GroupNotificationPresentationCoordinator();
      final readEvents = StreamController<String>();
      addTearDown(readEvents.close);
      final cards = <String, String>{
        'group:a': 'old-a',
        'group:b': 'existing-b',
        'direct:c': 'existing-c',
      };
      final cancelEntered = Completer<void>();
      final releaseCancel = Completer<void>();
      final showEntered = Completer<void>();
      final cancellation = _FakeCancellation((key) async {
        cancelEntered.complete();
        await releaseCancel.future;
        cards.remove(key);
      });
      final projector = GroupNotificationReadProjector(
        coordinator: coordinator,
        readEvents: readEvents.stream,
        unreadCountForGroup: (_) async => 0,
        cancellation: cancellation,
      )..start();
      addTearDown(() async {
        if (!releaseCancel.isCompleted) releaseCancel.complete();
        await projector.dispose();
      });

      readEvents.add('a');
      await cancelEntered.future;
      final newPresentation = coordinator.runForGroup('a', () async {
        showEntered.complete();
        cards['group:a'] = 'new-a';
      });
      await Future<void>.delayed(Duration.zero);
      expect(showEntered.isCompleted, isFalse);

      releaseCancel.complete();
      await newPresentation;
      await projector.waitForIdle();

      expect(cards['group:a'], 'new-a');
      expect(cards['group:b'], 'existing-b');
      expect(cards['direct:c'], 'existing-c');
      expect(coordinator.debugActiveKeyCount, 0);
    },
  );

  test(
    'new presentation racing read zero is cancelled after show and preserves siblings',
    () async {
      final coordinator = GroupNotificationPresentationCoordinator();
      final readEvents = StreamController<String>();
      addTearDown(readEvents.close);
      final cards = <String, String>{
        'group:b': 'existing-b',
        'direct:c': 'existing-c',
      };
      final showEntered = Completer<void>();
      final releaseShow = Completer<void>();
      final unreadChecked = Completer<void>();
      final cancellation = _FakeCancellation((key) async {
        cards.remove(key);
      });
      final projector = GroupNotificationReadProjector(
        coordinator: coordinator,
        readEvents: readEvents.stream,
        unreadCountForGroup: (_) async {
          unreadChecked.complete();
          return 0;
        },
        cancellation: cancellation,
      )..start();
      addTearDown(() async {
        if (!releaseShow.isCompleted) releaseShow.complete();
        await projector.dispose();
      });

      final presentation = coordinator.runForGroup('a', () async {
        showEntered.complete();
        await releaseShow.future;
        cards['group:a'] = 'new-a';
      });
      await showEntered.future;
      readEvents.add('a');
      await Future<void>.delayed(Duration.zero);
      expect(unreadChecked.isCompleted, isFalse);

      releaseShow.complete();
      await presentation;
      await projector.waitForIdle();

      expect(cards, isNot(contains('group:a')));
      expect(cards['group:b'], 'existing-b');
      expect(cards['direct:c'], 'existing-c');
      expect(coordinator.debugActiveKeyCount, 0);
    },
  );

  test(
    'startup zero-unread cannot cancel a headless event not yet canonical',
    () async {
      final coordinator = GroupNotificationPresentationCoordinator();
      final readEvents = StreamController<String>();
      addTearDown(readEvents.close);
      final unreadChecked = Completer<void>();
      final releaseUnreadCheck = Completer<void>();
      final cancellations = <String>[];
      final cancellation = _FakeCancellation(
        (key) async => cancellations.add(key),
        metadata: const <String, ConversationNotificationContentMetadata>{
          'group:a': ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.message,
            eventIdentity: 'new-headless-message',
            generation: 'new-headless-generation',
          ),
        },
      );
      final queriedEvents = <String>[];
      final projector = GroupNotificationReadProjector(
        coordinator: coordinator,
        readEvents: readEvents.stream,
        existingGroupIds: () async => const <String>['a'],
        unreadCountForGroup: (_) async {
          unreadChecked.complete();
          await releaseUnreadCheck.future;
          return 0;
        },
        messageEventIsRead: (groupId, eventIdentity) async {
          queriedEvents.add('$groupId:$eventIdentity');
          // A headless card can precede canonical inbox materialization. It is
          // not safe to cancel merely because the earlier aggregate was zero.
          return false;
        },
        cancellation: cancellation,
      )..start();
      addTearDown(() async {
        if (!releaseUnreadCheck.isCompleted) releaseUnreadCheck.complete();
        await projector.dispose();
      });

      await unreadChecked.future;
      releaseUnreadCheck.complete();
      await projector.waitForIdle();

      expect(queriedEvents, <String>['a:new-headless-message']);
      expect(cancellations, isEmpty);
    },
  );

  test(
    'zero-unread projection cancels the exact canonical read event',
    () async {
      final coordinator = GroupNotificationPresentationCoordinator();
      final readEvents = StreamController<String>();
      addTearDown(readEvents.close);
      final cancellations = <String>[];
      final projector = GroupNotificationReadProjector(
        coordinator: coordinator,
        readEvents: readEvents.stream,
        unreadCountForGroup: (_) async => 0,
        messageEventIsRead: (groupId, eventIdentity) async =>
            groupId == 'a' && eventIdentity == 'read-message',
        cancellation: _FakeCancellation(
          (key) async => cancellations.add(key),
          metadata: const <String, ConversationNotificationContentMetadata>{
            'group:a': ConversationNotificationContentMetadata(
              kind: ConversationNotificationContentKind.message,
              eventIdentity: 'read-message',
              generation: 'read-generation',
            ),
          },
        ),
      )..start();
      addTearDown(projector.dispose);

      readEvents.add('a');
      await projector.waitForIdle();

      expect(cancellations, <String>['group:a']);
    },
  );

  test(
    'dispose stops read events and unsupported cancellation is inert',
    () async {
      final coordinator = GroupNotificationPresentationCoordinator();
      final readEvents = StreamController<String>();
      addTearDown(readEvents.close);
      var unreadChecks = 0;
      var cancellations = 0;
      final projector = GroupNotificationReadProjector(
        coordinator: coordinator,
        readEvents: readEvents.stream,
        unreadCountForGroup: (_) async {
          unreadChecks += 1;
          return 0;
        },
        cancellation: _FakeCancellation((_) async => cancellations += 1),
      )..start();

      readEvents.add('a');
      await projector.waitForIdle();
      expect(unreadChecks, 1);
      expect(cancellations, 1);

      await projector.dispose();
      readEvents.add('a');
      await Future<void>.delayed(Duration.zero);
      expect(unreadChecks, 1);
      expect(cancellations, 1);

      final unsupportedEvents = StreamController<String>();
      addTearDown(unsupportedEvents.close);
      final unsupported = GroupNotificationReadProjector(
        coordinator: coordinator,
        readEvents: unsupportedEvents.stream,
        unreadCountForGroup: (_) async {
          unreadChecks += 1;
          return 0;
        },
        cancellation: null,
      )..start();
      unsupportedEvents.add('b');
      await unsupported.waitForIdle();
      expect(unreadChecks, 1);
      await unsupported.dispose();
    },
  );

  test(
    'startup scan recovers a missed zero-unread commit exactly once',
    () async {
      final coordinator = GroupNotificationPresentationCoordinator();
      final readEvents = StreamController<String>();
      addTearDown(readEvents.close);
      var startupScans = 0;
      final unreadChecks = <String>[];
      final cancellations = <String>[];
      final projector = GroupNotificationReadProjector(
        coordinator: coordinator,
        readEvents: readEvents.stream,
        existingGroupIds: () async {
          startupScans += 1;
          return const <String>['a', 'b', 'a', '   '];
        },
        unreadCountForGroup: (groupId) async {
          unreadChecks.add(groupId);
          return groupId == 'a' ? 0 : 2;
        },
        cancellation: _FakeCancellation((key) async {
          cancellations.add(key);
        }),
      )..start();
      addTearDown(projector.dispose);

      await projector.waitForIdle();
      projector.start();
      await projector.waitForIdle();

      expect(startupScans, 1);
      expect(unreadChecks, unorderedEquals(<String>['a', 'b']));
      expect(cancellations, <String>['group:a']);
      expect(coordinator.debugActiveKeyCount, 0);
    },
  );

  test(
    'deferred startup scan keeps live reads active and waits for complete recovery',
    () async {
      final coordinator = GroupNotificationPresentationCoordinator();
      final readEvents = StreamController<String>();
      addTearDown(readEvents.close);
      var startupScans = 0;
      final cancellations = <String>[];
      final projector = GroupNotificationReadProjector(
        coordinator: coordinator,
        readEvents: readEvents.stream,
        existingGroupIds: () async {
          startupScans++;
          return const <String>['startup'];
        },
        unreadCountForGroup: (_) async => 0,
        cancellation: _FakeCancellation((key) async {
          cancellations.add(key);
        }),
      )..start(deferStartupReconciliation: true);
      addTearDown(projector.dispose);

      readEvents.add('live');
      await projector.waitForIdle();
      expect(startupScans, 0);
      expect(cancellations, <String>['group:live']);

      projector.completeStartupCanonicalRecovery(canonicalStateComplete: false);
      await projector.waitForIdle();
      expect(startupScans, 0);

      projector.completeStartupCanonicalRecovery(canonicalStateComplete: true);
      await projector.waitForIdle();
      projector.completeStartupCanonicalRecovery(canonicalStateComplete: true);
      await projector.waitForIdle();

      expect(startupScans, 1);
      expect(cancellations, <String>['group:live', 'group:startup']);
    },
  );

  test(
    'startup preserves a reaction-only card when message unread is zero',
    () async {
      final coordinator = GroupNotificationPresentationCoordinator();
      final readEvents = StreamController<String>();
      addTearDown(readEvents.close);
      var startupScans = 0;
      final cancellations = <String>[];
      final projector = GroupNotificationReadProjector(
        coordinator: coordinator,
        readEvents: readEvents.stream,
        existingGroupIds: () async {
          startupScans += 1;
          return const <String>['reaction-only-group'];
        },
        unreadCountForGroup: (_) async => 0,
        cancellation: _FakeCancellation(
          (key) async {
            cancellations.add(key);
          },
          contentKinds: const <String, ConversationNotificationContentKind>{
            'group:reaction-only-group':
                ConversationNotificationContentKind.reaction,
          },
        ),
      )..start();
      addTearDown(projector.dispose);

      await projector.waitForIdle();

      expect(startupScans, 1);
      expect(cancellations, isEmpty);
    },
  );

  test(
    'live conversation acknowledgement retires the current reaction card',
    () async {
      final coordinator = GroupNotificationPresentationCoordinator();
      final readEvents = StreamController<String>(sync: true);
      addTearDown(readEvents.close);
      final cancellations = <String>[];
      final projector = GroupNotificationReadProjector(
        coordinator: coordinator,
        readEvents: readEvents.stream,
        unreadCountForGroup: (_) async => 0,
        contentEventIsAcknowledged: (_, metadata) async =>
            metadata.eventIdentity == 'reaction-event',
        cancellation: _FakeCancellation(
          (key) async => cancellations.add(key),
          metadata: const <String, ConversationNotificationContentMetadata>{
            'group:reaction-viewed': ConversationNotificationContentMetadata(
              kind: ConversationNotificationContentKind.reaction,
              eventIdentity: 'reaction-event',
              generation: 'reaction-generation',
            ),
          },
        ),
      )..start();
      addTearDown(projector.dispose);

      readEvents.add('reaction-viewed');
      await projector.waitForIdle();

      expect(cancellations, <String>['group:reaction-viewed']);
    },
  );

  test('live read preserves a different reaction that won after capture', () async {
    final readEvents = StreamController<String>(sync: true);
    addTearDown(readEvents.close);
    final cancellations = <String>[];
    final projector = GroupNotificationReadProjector(
      coordinator: GroupNotificationPresentationCoordinator(),
      readEvents: readEvents.stream,
      unreadCountForGroup: (_) async => 0,
      contentEventIsAcknowledged: (_, metadata) async => false,
      cancellation: _FakeCancellation(
        (key) async => cancellations.add(key),
        metadata: const <String, ConversationNotificationContentMetadata>{
          'group:new-reaction': ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.reaction,
            eventIdentity: 'event-after-read',
            generation: 'generation-after-read',
          ),
        },
      ),
    )..start();
    addTearDown(projector.dispose);

    readEvents.add('new-reaction');
    await projector.waitForIdle();

    expect(cancellations, isEmpty);
  });

  test(
    'live acknowledgement retires an unanchored message card without canonical identity',
    () async {
      final coordinator = GroupNotificationPresentationCoordinator();
      final readEvents = StreamController<String>(sync: true);
      addTearDown(readEvents.close);
      final cancellations = <String>[];
      final projector = GroupNotificationReadProjector(
        coordinator: coordinator,
        readEvents: readEvents.stream,
        unreadCountForGroup: (_) async => 0,
        messageEventIsRead: (_, _) async => false,
        cancellation: _FakeCancellation(
          (key) async => cancellations.add(key),
          metadata: const <String, ConversationNotificationContentMetadata>{
            'group:unanchored': ConversationNotificationContentMetadata(
              kind: ConversationNotificationContentKind.message,
              generation: 'unanchored-generation',
            ),
          },
        ),
      )..start();
      addTearDown(projector.dispose);

      readEvents.add('unanchored');
      await projector.waitForIdle();

      expect(cancellations, <String>['group:unanchored']);
    },
  );

  test(
    'live acknowledgement generation CAS preserves a cross-isolate replacement',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'group-read-generation-cas-',
      );
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      const conversationKey = 'group:generation-race';
      final notificationId = await registry.resolve(
        conversationKey,
        activeNotificationIds: () async => const <int>[],
      );
      await registry.recordContentMetadata(
        conversationKey: conversationKey,
        notificationId: notificationId,
        metadata: const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'old-reaction',
          generation: 'generation-old',
        ),
      );

      final snapshotCaptured = Completer<void>();
      final releaseUnreadQuery = Completer<void>();
      final nativeCancellations = <int>[];
      final cancellation = _RegistryCancellation(
        registry: registry,
        notificationId: notificationId,
        onSnapshot: snapshotCaptured.complete,
        onNativeCancel: nativeCancellations.add,
      );
      final readEvents = StreamController<String>(sync: true);
      addTearDown(readEvents.close);
      final projector = GroupNotificationReadProjector(
        coordinator: GroupNotificationPresentationCoordinator(),
        readEvents: readEvents.stream,
        unreadCountForGroup: (_) async {
          await releaseUnreadQuery.future;
          return 0;
        },
        cancellation: cancellation,
      )..start();
      addTearDown(() async {
        if (!releaseUnreadQuery.isCompleted) releaseUnreadQuery.complete();
        await projector.dispose();
      });

      readEvents.add('generation-race');
      await snapshotCaptured.future;
      await registry.recordContentMetadata(
        conversationKey: conversationKey,
        notificationId: notificationId,
        metadata: const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'new-message',
          generation: 'generation-new',
        ),
      );
      releaseUnreadQuery.complete();
      await projector.waitForIdle();

      expect(nativeCancellations, isEmpty);
      expect(
        (await registry.lookupContentMetadata(
          conversationKey: conversationKey,
          notificationId: notificationId,
        ))?.generation,
        'generation-new',
      );
    },
  );

  test('startup scan retries once after a transient query failure', () async {
    final coordinator = GroupNotificationPresentationCoordinator();
    final readEvents = StreamController<String>();
    addTearDown(readEvents.close);
    final firstAttempt = Completer<void>();
    final secondAttempt = Completer<void>();
    var startupScans = 0;
    final cancellations = <String>[];
    final projector = GroupNotificationReadProjector(
      coordinator: coordinator,
      readEvents: readEvents.stream,
      existingGroupIds: () async {
        startupScans += 1;
        if (startupScans == 1) {
          firstAttempt.complete();
          throw StateError('database temporarily unavailable');
        }
        secondAttempt.complete();
        return const <String>['a'];
      },
      unreadCountForGroup: (_) async => 0,
      cancellation: _FakeCancellation((key) async {
        cancellations.add(key);
      }),
      retryDelay: const Duration(milliseconds: 25),
    )..start();
    addTearDown(projector.dispose);

    projector.start();
    await firstAttempt.future;
    await Future<void>.delayed(Duration.zero);
    expect(startupScans, 1, reason: 'query retry must not busy-loop');

    await secondAttempt.future.timeout(const Duration(milliseconds: 250));
    await projector.waitForIdle();
    projector.start();
    await projector.waitForIdle();

    expect(startupScans, 2);
    expect(cancellations, <String>['group:a']);
    expect(coordinator.debugActiveKeyCount, 0);
  });

  test('dispose cancels a scheduled startup-scan retry', () async {
    final coordinator = GroupNotificationPresentationCoordinator();
    final readEvents = StreamController<String>();
    addTearDown(readEvents.close);
    final firstAttempt = Completer<void>();
    var startupScans = 0;
    final projector = GroupNotificationReadProjector(
      coordinator: coordinator,
      readEvents: readEvents.stream,
      existingGroupIds: () async {
        startupScans += 1;
        firstAttempt.complete();
        throw StateError('database temporarily unavailable');
      },
      unreadCountForGroup: (_) async => 0,
      cancellation: _FakeCancellation((_) async {}),
      retryDelay: const Duration(seconds: 1),
    )..start();

    await firstAttempt.future;
    await projector.waitForIdle();
    await projector.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(startupScans, 1);
    expect(coordinator.debugActiveKeyCount, 0);
  });

  test('failed exact cancellation retries after a finite delay', () async {
    final coordinator = GroupNotificationPresentationCoordinator();
    final readEvents = StreamController<String>();
    addTearDown(readEvents.close);
    final firstAttempt = Completer<void>();
    final secondAttempt = Completer<void>();
    var attempts = 0;
    final projector = GroupNotificationReadProjector(
      coordinator: coordinator,
      readEvents: readEvents.stream,
      unreadCountForGroup: (_) async => 0,
      cancellation: _FakeCancellation((_) async {
        attempts += 1;
        if (attempts == 1) {
          firstAttempt.complete();
          throw StateError('native cancel failed');
        }
        secondAttempt.complete();
      }),
      retryDelay: const Duration(milliseconds: 25),
    )..start();
    addTearDown(projector.dispose);

    readEvents.add('a');
    await firstAttempt.future;
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 1, reason: 'retry must not busy-loop');

    await secondAttempt.future.timeout(const Duration(seconds: 1));
    await projector.waitForIdle();
    expect(attempts, 2);
    expect(coordinator.debugActiveKeyCount, 0);
  });

  test('dispose cancels a scheduled exact-cancellation retry', () async {
    final coordinator = GroupNotificationPresentationCoordinator();
    final readEvents = StreamController<String>();
    addTearDown(readEvents.close);
    final firstAttempt = Completer<void>();
    var attempts = 0;
    final projector = GroupNotificationReadProjector(
      coordinator: coordinator,
      readEvents: readEvents.stream,
      unreadCountForGroup: (_) async => 0,
      cancellation: _FakeCancellation((_) async {
        attempts += 1;
        firstAttempt.complete();
        throw StateError('native cancel failed');
      }),
      retryDelay: const Duration(seconds: 1),
    )..start();

    readEvents.add('a');
    await firstAttempt.future;
    await projector.waitForIdle();
    await projector.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(attempts, 1);
    expect(coordinator.debugActiveKeyCount, 0);
  });
}

final class _FakeCancellation
    implements
        ConversationNotificationCancellation,
        ConversationNotificationGenerationCancellation {
  _FakeCancellation(
    this.onCancel, {
    this.contentKinds = const <String, ConversationNotificationContentKind>{},
    this.metadata = const <String, ConversationNotificationContentMetadata>{},
  });

  final Future<void> Function(String conversationKey) onCancel;
  final Map<String, ConversationNotificationContentKind> contentKinds;
  final Map<String, ConversationNotificationContentMetadata> metadata;

  ConversationNotificationContentMetadata _activeMetadata(
    String conversationKey,
  ) =>
      metadata[conversationKey] ??
      ConversationNotificationContentMetadata(
        kind:
            contentKinds[conversationKey] ??
            ConversationNotificationContentKind.message,
        eventIdentity: conversationKey,
        generation: 'fake-generation',
      );

  @override
  Future<ConversationNotificationContentMetadata?>
  lookupConversationNotificationContentMetadata(String conversationKey) async {
    return _activeMetadata(conversationKey);
  }

  @override
  Future<bool> cancelConversationNotificationGeneration(
    String conversationKey,
    String generation,
  ) async {
    if (_activeMetadata(conversationKey).generation != generation) return false;
    await onCancel(conversationKey);
    return true;
  }

  @override
  Future<void> cancelConversationNotification(
    String conversationKey, {
    ConversationNotificationContentKind? onlyIfContentKind,
    ConversationNotificationContentCancellationPredicate? shouldCancelContent,
  }) async {
    final activeMetadata = _activeMetadata(conversationKey);
    final activeKind = activeMetadata.kind;
    if (onlyIfContentKind != null && activeKind != onlyIfContentKind) {
      return;
    }
    if (shouldCancelContent != null &&
        !await shouldCancelContent(activeMetadata)) {
      return;
    }
    await onCancel(conversationKey);
  }
}

final class _RegistryCancellation
    implements
        ConversationNotificationCancellation,
        ConversationNotificationGenerationCancellation {
  const _RegistryCancellation({
    required this.registry,
    required this.notificationId,
    required this.onSnapshot,
    required this.onNativeCancel,
  });

  final DurableConversationNotificationIdRegistry registry;
  final int notificationId;
  final void Function() onSnapshot;
  final void Function(int notificationId) onNativeCancel;

  @override
  Future<ConversationNotificationContentMetadata?>
  lookupConversationNotificationContentMetadata(String conversationKey) async {
    final metadata = await registry.lookupContentMetadata(
      conversationKey: conversationKey,
      notificationId: notificationId,
    );
    onSnapshot();
    return metadata;
  }

  @override
  Future<bool> cancelConversationNotificationGeneration(
    String conversationKey,
    String generation,
  ) {
    return registry.cancelContentIfGeneration(
      conversationKey: conversationKey,
      notificationId: notificationId,
      generation: generation,
      cancel: () async => onNativeCancel(notificationId),
    );
  }

  @override
  Future<void> cancelConversationNotification(
    String conversationKey, {
    ConversationNotificationContentKind? onlyIfContentKind,
    ConversationNotificationContentCancellationPredicate? shouldCancelContent,
  }) async {
    if (onlyIfContentKind == null) return;
    await registry.cancelContentIfKind(
      conversationKey: conversationKey,
      notificationId: notificationId,
      kind: onlyIfContentKind,
      shouldCancel: shouldCancelContent,
      cancel: () async => onNativeCancel(notificationId),
    );
  }
}
