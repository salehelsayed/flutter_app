import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

const _ownerHold = Duration(milliseconds: 1700);
const _boundedCompletionCeiling = Duration(milliseconds: 1400);
const _ownerCompletionFloor = Duration(milliseconds: 1400);
// This is only a harness deadlock guard. Owner-completion semantics are
// intentionally unbounded after native lock ownership, while the contender
// acquisition bound remains asserted independently above. Leave enough room
// for isolate scheduling during the batched host-all lane.
const _outerWatchdog = Duration(seconds: 15);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('bounded-posix-flock-');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test(
    'event claim contender times out before a literal owner releases',
    () async {
      final lock = File(
        '${directory.path}${Platform.pathSeparator}'
        '.${DurableNotificationToneLease.eventClaimsDirectoryName}.lock',
      );
      final held = await _HeldNativeFlock.acquire(lock, holdFor: _ownerHold);
      try {
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
          claimTokenFactory: () => 'contender-must-not-own',
        );
        final stopwatch = Stopwatch()..start();
        final outcome = await coordinator
            .acquireMessageEventClaim(
              type: 'new_message',
              eventIdentity: 'bounded-event-claim',
            )
            .timeout(_outerWatchdog);
        stopwatch.stop();

        expect(
          outcome.disposition,
          DurableNotificationClaimDisposition.committedOrUnavailable,
        );
        expect(outcome.claim, isNull);
        expect(
          stopwatch.elapsed,
          lessThan(_boundedCompletionCeiling),
          reason: 'Android lock acquisition, not the action, owns the bound',
        );
        expect(held.released, isFalse);
        expect(
          File(
            '${directory.path}${Platform.pathSeparator}'
            '${DurableNotificationToneLease.eventClaimsDirectoryName}'
            '${Platform.pathSeparator}new_message-bounded-event-claim',
          ).existsSync(),
          isFalse,
          reason: 'a timed-out contender must not create a provisional claim',
        );

        await held.waitUntilReleased().timeout(_outerWatchdog);
        final later = await coordinator.acquireMessageEventClaim(
          type: 'new_message',
          eventIdentity: 'bounded-event-claim',
        );
        expect(later.disposition, DurableNotificationClaimDisposition.acquired);
        expect(await later.claim!.commit(), isTrue);
      } finally {
        await held.dispose();
      }
    },
  );

  test(
    'tone contender times out without a lease before literal owner releases',
    () async {
      final toneDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.toneLeasesDirectoryName}',
      );
      final lock = File(
        '${toneDirectory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.toneCoordinationLockFileName}',
      );
      final held = await _HeldNativeFlock.acquire(lock, holdFor: _ownerHold);
      try {
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingToneReservationWait: Duration.zero,
          claimTokenFactory: () => 'contender-must-not-reserve',
        );
        final stopwatch = Stopwatch()..start();
        final reservation = await coordinator
            .reserveTone('peer-bounded-tone')
            .timeout(_outerWatchdog);
        stopwatch.stop();

        expect(reservation, isNull);
        expect(stopwatch.elapsed, lessThan(_boundedCompletionCeiling));
        expect(held.released, isFalse);
        expect(
          toneDirectory
              .listSync(followLinks: false)
              .whereType<File>()
              .where(
                (file) =>
                    file.path.endsWith('.lease') ||
                    file.path.endsWith(
                      DurableNotificationToneLease
                          .tonePendingReservationFileSuffix,
                    ),
              ),
          isEmpty,
          reason: 'unavailable acquisition must enter no tone action',
        );

        await held.waitUntilReleased().timeout(_outerWatchdog);
        final later = await coordinator.reserveTone('peer-bounded-tone');
        expect(later, isNotNull);
        expect(await later!.release(), isTrue);
      } finally {
        await held.dispose();
      }
    },
  );

  test(
    'shown event claim waits for the real lock owner and commits permanently',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingClaimWait: Duration.zero,
        claimTokenFactory: () => 'shown-event-owner',
      );
      final acquisition = await coordinator.acquireMessageEventClaim(
        type: 'new_message',
        eventIdentity: 'shown-event-commit',
      );
      expect(
        acquisition.disposition,
        DurableNotificationClaimDisposition.acquired,
      );
      final claim = acquisition.claim!;
      final lock = File(
        '${directory.path}${Platform.pathSeparator}'
        '.${DurableNotificationToneLease.eventClaimsDirectoryName}.lock',
      );
      final held = await _HeldNativeFlock.acquire(lock, holdFor: _ownerHold);
      try {
        final stopwatch = Stopwatch()..start();
        final committed = await claim.commit().timeout(_outerWatchdog);
        stopwatch.stop();

        expect(committed, isTrue);
        expect(held.released, isTrue);
        expect(stopwatch.elapsed, greaterThan(_ownerCompletionFloor));
        final claimFile = File(
          '${directory.path}${Platform.pathSeparator}'
          '${DurableNotificationToneLease.eventClaimsDirectoryName}'
          '${Platform.pathSeparator}'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'shown-event-commit')}',
        );
        expect(
          jsonDecode(await claimFile.readAsString()),
          containsPair('state', 'committed'),
        );

        now = now.add(const Duration(seconds: 61));
        final duplicate = await coordinator.acquireMessageEventClaim(
          type: 'new_message',
          eventIdentity: 'shown-event-commit',
        );
        expect(
          duplicate.disposition,
          DurableNotificationClaimDisposition.committedOrUnavailable,
        );
      } finally {
        await held.dispose();
      }
    },
  );

  test(
    'shown tone owner waits for the real lock owner and commits its window',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        toneWindow: const Duration(minutes: 5),
        pendingToneReservationWait: Duration.zero,
        claimTokenFactory: () => 'shown-tone-owner',
      );
      final reservation = await coordinator.reserveTone('peer-shown-tone');
      expect(reservation, isNotNull);
      final toneDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.toneLeasesDirectoryName}',
      );
      final lock = File(
        '${toneDirectory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.toneCoordinationLockFileName}',
      );
      final held = await _HeldNativeFlock.acquire(lock, holdFor: _ownerHold);
      try {
        final stopwatch = Stopwatch()..start();
        final committed = await reservation!.commit().timeout(_outerWatchdog);
        stopwatch.stop();

        expect(committed, isTrue);
        expect(held.released, isTrue);
        expect(stopwatch.elapsed, greaterThan(_ownerCompletionFloor));
        expect(
          toneDirectory
              .listSync(followLinks: false)
              .whereType<File>()
              .where(
                (file) => file.path.endsWith(
                  DurableNotificationToneLease.tonePendingReservationFileSuffix,
                ),
              ),
          isEmpty,
        );

        now = now.add(const Duration(seconds: 61));
        expect(await coordinator.reserveTone('peer-shown-tone'), isNull);
      } finally {
        await held.dispose();
      }
    },
  );

  test(
    'shown exact claim commits while the tone lock is held past claim TTL',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingClaimWait: Duration.zero,
        pendingToneReservationWait: Duration.zero,
        claimTokenFactory: () => 'cross-lock-tone-owner',
      );
      final claim = (await coordinator.acquireMessageEventClaim(
        type: 'new_message',
        eventIdentity: 'cross-lock-tone-event',
      )).claim!;
      final reservation = await coordinator.reserveTone(
        'cross-lock-tone-conversation',
      );
      expect(reservation, isNotNull);
      final toneDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.toneLeasesDirectoryName}',
      );
      final held = await _HeldNativeFlock.acquire(
        File(
          '${toneDirectory.path}${Platform.pathSeparator}'
          '${DurableNotificationToneLease.toneCoordinationLockFileName}',
        ),
        holdFor: _ownerHold,
      );
      final claimFile = File(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.eventClaimsDirectoryName}'
        '${Platform.pathSeparator}'
        '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'cross-lock-tone-event')}',
      );
      var commitsCompleted = false;
      try {
        final commits = commitShownNotificationOwners(
          messageClaim: claim,
          toneReservation: reservation,
        )..then((_) => commitsCompleted = true);
        await _waitForFileContents(
          claimFile,
          '"state":"committed"',
        ).timeout(const Duration(seconds: 1));
        expect(held.released, isFalse);
        expect(commitsCompleted, isFalse);

        now = now.add(const Duration(seconds: 61));
        final duplicate = await coordinator.acquireMessageEventClaim(
          type: 'new_message',
          eventIdentity: 'cross-lock-tone-event',
        );
        expect(
          duplicate.disposition,
          DurableNotificationClaimDisposition.committedOrUnavailable,
        );

        final result = await commits.timeout(_outerWatchdog);
        expect(result.messageClaimCommitted, isTrue);
        expect(result.toneReservationCommitted, isTrue);
      } finally {
        await held.dispose();
      }
    },
  );

  test(
    'audible publication retains its exact tone token past provisional TTL',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        claimTokenFactory: () => 'audible-publication-owner',
      );
      final reservation = await coordinator.reserveTone(
        'same-conversation-audible-publication',
      );
      expect(reservation, isNotNull);
      final publicationEntered = Completer<void>();
      final releasePublication = Completer<void>();
      var audiblePublications = 0;
      final publication = reservation!.publishAndCommit(() async {
        audiblePublications += 1;
        publicationEntered.complete();
        await releasePublication.future;
      });

      await publicationEntered.future.timeout(_outerWatchdog);
      now = now.add(const Duration(seconds: 61));
      final competingReservation = await DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        claimTokenFactory: () => 'second-event-tone-owner',
      ).reserveTone('same-conversation-audible-publication');
      expect(
        competingReservation,
        isNull,
        reason:
            'a different event must publish silently while the audible owner '
            'is inside native publication',
      );

      releasePublication.complete();
      final result = await publication.timeout(_outerWatchdog);
      expect(result.publishedAudibly, isTrue);
      expect(result.toneCommitted, isTrue);
      expect(audiblePublications, 1);
      expect(
        await coordinator.reserveTone('same-conversation-audible-publication'),
        isNull,
      );
    },
  );

  test(
    'pre-native tone storage failure falls back silent without poisoning event',
    () async {
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        pendingClaimWait: Duration.zero,
        pendingToneReservationWait: Duration.zero,
        claimTokenFactory: () => 'pre-native-storage-owner',
      );
      final claim = (await coordinator.acquireMessageEventClaim(
        type: 'new_message',
        eventIdentity: 'pre-native-storage-event',
      )).claim!;
      final reservation = await coordinator.reserveTone(
        'pre-native-storage-conversation',
      );
      expect(reservation, isNotNull);

      final toneDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.toneLeasesDirectoryName}',
      );
      await toneDirectory.delete(recursive: true);
      await File(toneDirectory.path).create();

      var audibleShows = 0;
      var silentShows = 0;
      DurableNotificationTonePublicationResult? toneResult;
      final eventResult = await claim.publishAndCommit(() async {
        toneResult = await reservation!.publishAndCommit(() async {
          audibleShows += 1;
        });
        if (!toneResult!.publishedAudibly) silentShows += 1;
      });

      expect(toneResult?.publishedAudibly, isFalse);
      expect(audibleShows, 0);
      expect(silentShows, 1);
      expect(eventResult.published, isTrue);
      expect(eventResult.claimCommitted, isTrue);
    },
  );

  test(
    'ambiguous aged audible attempt repairs into a silent tone window',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        pendingToneReservationTtl: const Duration(seconds: 60),
        toneWindow: const Duration(seconds: 30),
        claimTokenFactory: () => 'ambiguous-audible-owner',
      );
      final reservation = await coordinator.reserveTone(
        'ambiguous-audible-conversation',
      );
      expect(reservation, isNotNull);
      final pendingFile =
          Directory(
                '${directory.path}${Platform.pathSeparator}'
                '${DurableNotificationToneLease.toneLeasesDirectoryName}',
              )
              .listSync(followLinks: false)
              .whereType<File>()
              .singleWhere(
                (file) => file.path.endsWith(
                  DurableNotificationToneLease.tonePendingReservationFileSuffix,
                ),
              );

      // Model an owner that spent longer than its provisional TTL in earlier
      // storage work, then reached NotificationManager.notify before the Dart
      // acknowledgement failed.
      now = now.add(const Duration(seconds: 61));
      var audibleAttempts = 0;
      try {
        await reservation!.publishAndCommit(() async {
          audibleAttempts += 1;
          throw StateError('native acknowledgement lost after audible attempt');
        });
      } catch (_) {
        // The error may propagate, but the attempted native side effect is
        // ambiguous and its durable tone owner must remain fail-closed.
      }
      final stateBeforeRepair =
          (jsonDecode(await pendingFile.readAsString()) as Map)['state'];

      final repairAttempt = await DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        pendingToneReservationTtl: const Duration(seconds: 60),
        toneWindow: const Duration(seconds: 30),
        claimTokenFactory: () => 'must-not-sound-during-repair',
      ).reserveTone('ambiguous-audible-conversation');
      final pendingExistsAfterRepair = pendingFile.existsSync();

      // Capture the full desired window even on the current RED path.
      if (repairAttempt != null) await repairAttempt.release();
      now = now.add(const Duration(seconds: 29));
      final beforeWindowExpiry = await DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        toneWindow: const Duration(seconds: 30),
      ).reserveTone('ambiguous-audible-conversation');
      if (beforeWindowExpiry != null) await beforeWindowExpiry.release();
      now = now.add(const Duration(seconds: 1));
      final atWindowExpiry = await DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        toneWindow: const Duration(seconds: 30),
      ).reserveTone('ambiguous-audible-conversation');

      expect(audibleAttempts, 1);
      expect(
        stateBeforeRepair,
        'publishing',
        reason:
            'an attempted audible native call is effect-unknown, not pending',
      );
      expect(
        repairAttempt,
        isNull,
        reason: 'the first observer repairs the ambiguous attempt silently',
      );
      expect(pendingExistsAfterRepair, isFalse);
      expect(beforeWindowExpiry, isNull);
      expect(atWindowExpiry, isNotNull);
      await atWindowExpiry?.release();
    },
  );

  test('same tone owner cannot replay an ambiguous native attempt', () async {
    final coordinator = DurableNotificationToneLease(
      directory: directory,
      pendingToneReservationWait: Duration.zero,
      claimTokenFactory: () => 'same-tone-owner',
    );
    final reservation = await coordinator.reserveTone(
      'same-tone-owner-conversation',
    );
    expect(reservation, isNotNull);
    final ownedReservation = reservation!;
    var nativeAttempts = 0;

    await expectLater(
      ownedReservation.publishAndCommit(() async {
        nativeAttempts += 1;
        throw StateError('native acknowledgement lost after tone attempt');
      }),
      throwsA(isA<DurableNotificationPublicationAttemptedException>()),
    );
    final replay = await ownedReservation.publishAndCommit(() async {
      nativeAttempts += 1;
    });

    expect(nativeAttempts, 1);
    expect(replay.publishedAudibly, isFalse);
    expect(replay.toneCommitted, isFalse);
  });

  test(
    'ambiguous native event attempt cannot be released or reclaimed',
    () async {
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        pendingClaimWait: Duration.zero,
        claimTokenFactory: () => 'ambiguous-event-owner',
      );
      final acquisition = await coordinator.acquireMessageEventClaim(
        type: 'new_message',
        eventIdentity: 'ambiguous-native-event',
      );
      expect(
        acquisition.disposition,
        DurableNotificationClaimDisposition.acquired,
      );
      final claim = acquisition.claim!;
      final claimFile = File(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.eventClaimsDirectoryName}'
        '${Platform.pathSeparator}'
        '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'ambiguous-native-event')}',
      );
      var nativeAttempts = 0;

      try {
        await claim.publishAndCommit(() async {
          nativeAttempts += 1;
          throw StateError('native acknowledgement lost after attempt');
        });
      } catch (_) {
        // The callback was entered, so its native side effect is unknowable.
      }
      final released = await claim.release();
      final duplicate = await coordinator.acquireMessageEventClaim(
        type: 'new_message',
        eventIdentity: 'ambiguous-native-event',
      );

      expect(nativeAttempts, 1);
      expect(
        released,
        isFalse,
        reason: 'only a pre-publication pending claim may be released',
      );
      expect(
        duplicate.disposition,
        DurableNotificationClaimDisposition.pending,
      );
      expect(duplicate.claim, isNull);
      expect(await claimFile.readAsString(), contains('"state":"publishing"'));
    },
  );

  test('same event owner cannot replay an ambiguous native attempt', () async {
    final coordinator = DurableNotificationToneLease(
      directory: directory,
      pendingClaimWait: Duration.zero,
      claimTokenFactory: () => 'same-event-owner',
    );
    final acquisition = await coordinator.acquireMessageEventClaim(
      type: 'new_message',
      eventIdentity: 'same-event-owner-event',
    );
    expect(
      acquisition.disposition,
      DurableNotificationClaimDisposition.acquired,
    );
    final claim = acquisition.claim!;
    var nativeAttempts = 0;

    await expectLater(
      claim.publishAndCommit(() async {
        nativeAttempts += 1;
        throw StateError('native acknowledgement lost after event attempt');
      }),
      throwsA(isA<DurableNotificationPublicationAttemptedException>()),
    );
    final replay = await claim.publishAndCommit(() async {
      nativeAttempts += 1;
    });

    expect(nativeAttempts, 1);
    expect(replay.published, isFalse);
    expect(replay.claimCommitted, isFalse);
  });

  test('aged Android publishing event residue is terminal fail-closed', () async {
    var now = DateTime.utc(2026, 8, 3, 20);
    final coordinator = DurableNotificationToneLease(
      directory: directory,
      now: () => now,
      pendingClaimWait: Duration.zero,
      pendingMessageClaimTtl: const Duration(seconds: 60),
      claimTokenFactory: () => 'crashed-publication-owner',
    );
    final acquisition = await coordinator.acquireMessageEventClaim(
      type: 'new_message',
      eventIdentity: 'crashed-publication-event',
    );
    expect(
      acquisition.disposition,
      DurableNotificationClaimDisposition.acquired,
    );
    final claim = acquisition.claim!;
    final claimFile = File(
      '${directory.path}${Platform.pathSeparator}'
      '${DurableNotificationToneLease.eventClaimsDirectoryName}'
      '${Platform.pathSeparator}'
      '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'crashed-publication-event')}',
    );

    try {
      await claim.publishAndCommit(() async {
        throw StateError('process lost after native publication attempt');
      });
    } catch (_) {
      // Simulate process loss: no in-memory owner remains to CAS-release or
      // finalize this effect-unknown publication record.
    }
    expect(await claimFile.readAsString(), contains('"state":"publishing"'));

    now = now.add(const Duration(milliseconds: 59999));
    final beforeBoundary = await coordinator.acquireMessageEventClaim(
      type: 'new_message',
      eventIdentity: 'crashed-publication-event',
    );
    expect(
      beforeBoundary.disposition,
      DurableNotificationClaimDisposition.pending,
    );

    now = now.add(const Duration(milliseconds: 1));
    final duplicate =
        await DurableNotificationToneLease(
          directory: directory,
          now: () => now,
          pendingClaimWait: Duration.zero,
          pendingMessageClaimTtl: const Duration(seconds: 60),
          claimTokenFactory: () => 'must-not-reclaim-crash-residue',
        ).acquireMessageEventClaim(
          type: 'new_message',
          eventIdentity: 'crashed-publication-event',
        );

    expect(
      duplicate.disposition,
      DurableNotificationClaimDisposition.committedOrUnavailable,
      reason:
          'an orphaned effect-unknown publication is terminal fail-closed, '
          'not a pending owner that keeps the live outbox retrying forever',
    );
    expect(duplicate.claim, isNull);
    expect(
      await claimFile.readAsString(),
      allOf(contains('"state":"committed"'), isNot(contains('"token"'))),
      reason: 'terminal repair must remove retryable publication ownership',
    );
  });

  for (final postShowField in <String>[
    'publishingAtMs',
    'committedAtMs',
    'publicationOutcome',
  ]) {
    test(
      'pending event record carrying $postShowField is never reclaimed',
      () async {
        var now = DateTime.utc(2026, 8, 3, 20);
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          now: () => now,
          pendingClaimWait: Duration.zero,
          pendingMessageClaimTtl: const Duration(seconds: 60),
          claimTokenFactory: () => 'corrupt-event-owner-$postShowField',
        );
        final acquisition = await coordinator.acquireMessageEventClaim(
          type: 'new_message',
          eventIdentity: 'corrupt-event-$postShowField',
        );
        expect(
          acquisition.disposition,
          DurableNotificationClaimDisposition.acquired,
        );
        final claimFile = File(
          '${directory.path}${Platform.pathSeparator}'
          '${DurableNotificationToneLease.eventClaimsDirectoryName}'
          '${Platform.pathSeparator}'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'corrupt-event-$postShowField')}',
        );
        final record =
            jsonDecode(await claimFile.readAsString()) as Map<String, dynamic>;
        record[postShowField] = postShowField == 'publicationOutcome'
            ? 'unknown'
            : now.millisecondsSinceEpoch;
        await claimFile.writeAsString(jsonEncode(record), flush: true);

        now = now.add(const Duration(seconds: 60));
        final duplicate =
            await DurableNotificationToneLease(
              directory: directory,
              now: () => now,
              pendingClaimWait: Duration.zero,
              pendingMessageClaimTtl: const Duration(seconds: 60),
              claimTokenFactory: () => 'must-not-reclaim-$postShowField',
            ).acquireMessageEventClaim(
              type: 'new_message',
              eventIdentity: 'corrupt-event-$postShowField',
            );

        expect(
          duplicate.disposition,
          DurableNotificationClaimDisposition.committedOrUnavailable,
          reason:
              'post-show evidence must make malformed ownership fail closed',
        );
        expect(duplicate.claim, isNull);
        expect(await acquisition.claim!.release(), isFalse);
        expect(claimFile.existsSync(), isTrue);
      },
    );
  }

  test('invalid Android tone state shapes repair silently', () async {
    final startedAt = DateTime.utc(2026, 8, 3, 20);
    final invalidShapes = <String, void Function(Map<String, dynamic>)>{
      'publishing-without-timestamp': (record) {
        record['state'] = 'publishing';
      },
      'publishing-with-commit-evidence': (record) {
        record['state'] = 'publishing';
        record['publishingAtMs'] = startedAt.millisecondsSinceEpoch;
        record['committedAtMs'] = startedAt.millisecondsSinceEpoch;
      },
      'committed-without-timestamp': (record) {
        record['state'] = 'committed';
      },
      'committed-with-publishing-evidence': (record) {
        record['state'] = 'committed';
        record['publishingAtMs'] = startedAt.millisecondsSinceEpoch;
        record['committedAtMs'] = startedAt.millisecondsSinceEpoch;
      },
    };

    for (final invalidShape in invalidShapes.entries) {
      var now = startedAt;
      final fixtureDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}${invalidShape.key}',
      );
      final coordinator = DurableNotificationToneLease(
        directory: fixtureDirectory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        pendingToneReservationTtl: const Duration(seconds: 60),
        toneWindow: const Duration(seconds: 30),
      );
      expect(await coordinator.reserveTone(invalidShape.key), isNotNull);
      final toneDirectory = Directory(
        '${fixtureDirectory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.toneLeasesDirectoryName}',
      );
      final pendingFile = toneDirectory
          .listSync(followLinks: false)
          .whereType<File>()
          .singleWhere(
            (file) => file.path.endsWith(
              DurableNotificationToneLease.tonePendingReservationFileSuffix,
            ),
          );
      final leaseFile = toneDirectory
          .listSync(followLinks: false)
          .whereType<File>()
          .singleWhere((file) => file.path.endsWith('.lease'));
      final record =
          jsonDecode(await pendingFile.readAsString()) as Map<String, dynamic>;
      invalidShape.value(record);
      await pendingFile.writeAsString(jsonEncode(record), flush: true);

      now = now.add(const Duration(seconds: 61));
      expect(
        await coordinator.reserveTone(invalidShape.key),
        isNull,
        reason: '${invalidShape.key} must fail closed at first observation',
      );
      expect(pendingFile.existsSync(), isFalse);
      expect(
        await leaseFile.readAsString(),
        (now.millisecondsSinceEpoch / Duration.millisecondsPerSecond)
            .toStringAsFixed(3),
      );
      now = now.add(const Duration(seconds: 29));
      expect(await coordinator.reserveTone(invalidShape.key), isNull);
      now = now.add(const Duration(seconds: 1));
      final afterWindow = await coordinator.reserveTone(invalidShape.key);
      expect(afterWindow, isNotNull);
      await afterWindow?.release();
    }
  });

  test(
    'failed stale publication repair stays fail-closed and preserves owner',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingClaimWait: Duration.zero,
        pendingMessageClaimTtl: const Duration(seconds: 60),
        claimTokenFactory: () => 'failed-terminal-repair-owner',
      );
      final claim = (await coordinator.acquireMessageEventClaim(
        type: 'new_message',
        eventIdentity: 'failed-terminal-repair-event',
      )).claim!;
      try {
        await claim.publishAndCommit(() async {
          throw StateError('native result lost');
        });
      } catch (_) {
        // The durable record is now a valid effect-unknown publishing owner.
      }
      final claimFile = File(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.eventClaimsDirectoryName}'
        '${Platform.pathSeparator}'
        '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'failed-terminal-repair-event')}',
      );
      await Directory('${claimFile.path}.replacement.tmp').create();

      now = now.add(const Duration(seconds: 60));
      final duplicate = await coordinator.acquireMessageEventClaim(
        type: 'new_message',
        eventIdentity: 'failed-terminal-repair-event',
      );

      expect(
        duplicate.disposition,
        DurableNotificationClaimDisposition.committedOrUnavailable,
      );
      expect(duplicate.claim, isNull);
      expect(await claimFile.readAsString(), contains('"state":"publishing"'));
    },
  );

  test(
    'failed atomic tone publishing transition never enters native callback',
    () async {
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        pendingToneReservationWait: Duration.zero,
        claimTokenFactory: () => 'failed-publishing-transition-owner',
      );
      final reservation = await coordinator.reserveTone(
        'failed-publishing-transition-conversation',
      );
      expect(reservation, isNotNull);
      final pendingFile =
          Directory(
                '${directory.path}${Platform.pathSeparator}'
                '${DurableNotificationToneLease.toneLeasesDirectoryName}',
              )
              .listSync(followLinks: false)
              .whereType<File>()
              .singleWhere(
                (file) => file.path.endsWith(
                  DurableNotificationToneLease.tonePendingReservationFileSuffix,
                ),
              );
      final pendingBefore = await pendingFile.readAsString();
      await Directory('${pendingFile.path}.replacement.tmp').create();
      var nativeAttempts = 0;

      final publication = await reservation!.publishAndCommit(() async {
        nativeAttempts += 1;
      });

      expect(publication.publishedAudibly, isFalse);
      expect(publication.toneCommitted, isFalse);
      expect(nativeAttempts, 0);
      expect(await pendingFile.readAsString(), pendingBefore);
      expect(await reservation.release(), isTrue);
    },
  );

  test(
    'failed atomic tone commit preserves publishing and repairs silently',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        pendingToneReservationTtl: const Duration(seconds: 60),
        toneWindow: const Duration(seconds: 30),
        claimTokenFactory: () => 'failed-atomic-tone-owner',
      );
      final reservation = await coordinator.reserveTone(
        'failed-atomic-tone-conversation',
      );
      expect(reservation, isNotNull);
      final pendingFile =
          Directory(
                '${directory.path}${Platform.pathSeparator}'
                '${DurableNotificationToneLease.toneLeasesDirectoryName}',
              )
              .listSync(followLinks: false)
              .whereType<File>()
              .singleWhere(
                (file) => file.path.endsWith(
                  DurableNotificationToneLease.tonePendingReservationFileSuffix,
                ),
              );
      now = now.add(const Duration(seconds: 61));
      var audibleShows = 0;
      final publication = await reservation!.publishAndCommit(() async {
        audibleShows += 1;
        await Directory('${pendingFile.path}.replacement.tmp').create();
      });
      expect(publication.publishedAudibly, isTrue);
      expect(publication.toneCommitted, isFalse);
      expect(audibleShows, 1);
      expect(
        await pendingFile.readAsString(),
        contains('"state":"publishing"'),
      );

      final repair = await DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        toneWindow: const Duration(seconds: 30),
      ).reserveTone('failed-atomic-tone-conversation');
      expect(repair, isNull);
      expect(pendingFile.existsSync(), isFalse);

      now = now.add(const Duration(seconds: 29));
      expect(
        await coordinator.reserveTone('failed-atomic-tone-conversation'),
        isNull,
      );
      now = now.add(const Duration(seconds: 1));
      final afterWindow = await coordinator.reserveTone(
        'failed-atomic-tone-conversation',
      );
      expect(afterWindow, isNotNull);
      await afterWindow?.release();
    },
  );

  test(
    'malformed post-show tone residue repairs into a silent window',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        toneWindow: const Duration(seconds: 30),
      );
      expect(
        await coordinator.reserveTone('malformed-post-show-tone'),
        isNotNull,
      );
      final pendingFile =
          Directory(
                '${directory.path}${Platform.pathSeparator}'
                '${DurableNotificationToneLease.toneLeasesDirectoryName}',
              )
              .listSync(followLinks: false)
              .whereType<File>()
              .singleWhere(
                (file) => file.path.endsWith(
                  DurableNotificationToneLease.tonePendingReservationFileSuffix,
                ),
              );
      await pendingFile.writeAsString('{', flush: true);

      now = now.add(const Duration(seconds: 61));
      expect(await coordinator.reserveTone('malformed-post-show-tone'), isNull);
      expect(pendingFile.existsSync(), isFalse);
      now = now.add(const Duration(seconds: 29));
      expect(await coordinator.reserveTone('malformed-post-show-tone'), isNull);
    },
  );

  test(
    'unknown valid post-show tone state repairs into a silent window',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        toneWindow: const Duration(seconds: 30),
      );
      expect(
        await coordinator.reserveTone('unknown-post-show-tone-state'),
        isNotNull,
      );
      final pendingFile =
          Directory(
                '${directory.path}${Platform.pathSeparator}'
                '${DurableNotificationToneLease.toneLeasesDirectoryName}',
              )
              .listSync(followLinks: false)
              .whereType<File>()
              .singleWhere(
                (file) => file.path.endsWith(
                  DurableNotificationToneLease.tonePendingReservationFileSuffix,
                ),
              );
      final record =
          jsonDecode(await pendingFile.readAsString()) as Map<String, dynamic>;
      record['state'] = 'publishin';
      record['publishingAtMs'] = record['reservedAtMs'];
      await pendingFile.writeAsString(jsonEncode(record), flush: true);

      now = now.add(const Duration(seconds: 61));
      expect(
        await coordinator.reserveTone('unknown-post-show-tone-state'),
        isNull,
        reason: 'unknown durable state must never be reclaimed audibly',
      );
      expect(pendingFile.existsSync(), isFalse);
      now = now.add(const Duration(seconds: 29));
      expect(
        await coordinator.reserveTone('unknown-post-show-tone-state'),
        isNull,
      );
      now = now.add(const Duration(seconds: 1));
      final afterSilentWindow = await coordinator.reserveTone(
        'unknown-post-show-tone-state',
      );
      expect(afterSilentWindow, isNotNull);
      await afterSilentWindow?.release();
    },
  );

  for (final postShowField in <String>['publishingAtMs', 'committedAtMs']) {
    test(
      'pending tone record carrying $postShowField repairs silently',
      () async {
        var now = DateTime.utc(2026, 8, 3, 20);
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          now: () => now,
          pendingToneReservationWait: Duration.zero,
          pendingToneReservationTtl: const Duration(seconds: 60),
          toneWindow: const Duration(seconds: 30),
        );
        expect(
          await coordinator.reserveTone('corrupt-tone-$postShowField'),
          isNotNull,
        );
        final pendingFile =
            Directory(
                  '${directory.path}${Platform.pathSeparator}'
                  '${DurableNotificationToneLease.toneLeasesDirectoryName}',
                )
                .listSync(followLinks: false)
                .whereType<File>()
                .singleWhere(
                  (file) => file.path.endsWith(
                    DurableNotificationToneLease
                        .tonePendingReservationFileSuffix,
                  ),
                );
        final record =
            jsonDecode(await pendingFile.readAsString())
                as Map<String, dynamic>;
        record[postShowField] = now.millisecondsSinceEpoch;
        await pendingFile.writeAsString(jsonEncode(record), flush: true);

        now = now.add(const Duration(seconds: 61));
        expect(
          await coordinator.reserveTone('corrupt-tone-$postShowField'),
          isNull,
          reason: 'post-show evidence must never be reclaimed audibly',
        );
        expect(pendingFile.existsSync(), isFalse);
        now = now.add(const Duration(seconds: 29));
        expect(
          await coordinator.reserveTone('corrupt-tone-$postShowField'),
          isNull,
        );
        now = now.add(const Duration(seconds: 1));
        final afterSilentWindow = await coordinator.reserveTone(
          'corrupt-tone-$postShowField',
        );
        expect(afterSilentWindow, isNotNull);
        await afterSilentWindow?.release();
      },
    );
  }

  test(
    'committed tone repair anchors a fresh silent window at observation',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        toneWindow: const Duration(seconds: 30),
      );
      expect(
        await coordinator.reserveTone('committed-repair-observation-anchor'),
        isNotNull,
      );
      final pendingFile =
          Directory(
                '${directory.path}${Platform.pathSeparator}'
                '${DurableNotificationToneLease.toneLeasesDirectoryName}',
              )
              .listSync(followLinks: false)
              .whereType<File>()
              .singleWhere(
                (file) => file.path.endsWith(
                  DurableNotificationToneLease.tonePendingReservationFileSuffix,
                ),
              );
      final record =
          jsonDecode(await pendingFile.readAsString()) as Map<String, dynamic>;
      record['state'] = 'committed';
      record['committedAtMs'] = now.millisecondsSinceEpoch;
      await pendingFile.writeAsString(jsonEncode(record), flush: true);

      now = now.add(const Duration(seconds: 61));
      expect(
        await coordinator.reserveTone('committed-repair-observation-anchor'),
        isNull,
      );
      expect(pendingFile.existsSync(), isFalse);
      now = now.add(const Duration(seconds: 29));
      expect(
        await coordinator.reserveTone('committed-repair-observation-anchor'),
        isNull,
      );
      now = now.add(const Duration(seconds: 1));
      final afterSilentWindow = await coordinator.reserveTone(
        'committed-repair-observation-anchor',
      );
      expect(afterSilentWindow, isNotNull);
      await afterSilentWindow?.release();
    },
  );

  for (final repairCase
      in <
        ({
          String name,
          Duration numericOffset,
          Duration postShowOffset,
          Duration expectedOffset,
        })
      >[
        (
          name: 'newer numeric lease',
          numericOffset: const Duration(minutes: 4),
          postShowOffset: const Duration(minutes: 3),
          expectedOffset: const Duration(minutes: 4),
        ),
        (
          name: 'newer post-show timestamp',
          numericOffset: const Duration(minutes: 3),
          postShowOffset: const Duration(minutes: 4),
          expectedOffset: const Duration(minutes: 4),
        ),
      ]) {
    test('publishing tone repair preserves ${repairCase.name}', () async {
      final startedAt = DateTime.utc(2026, 8, 3, 20);
      var now = startedAt;
      final conversation = 'publishing-repair-${repairCase.name}';
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        toneWindow: const Duration(seconds: 30),
      );
      expect(await coordinator.reserveTone(conversation), isNotNull);
      final toneDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.toneLeasesDirectoryName}',
      );
      final pendingFile = toneDirectory
          .listSync(followLinks: false)
          .whereType<File>()
          .singleWhere(
            (file) => file.path.endsWith(
              DurableNotificationToneLease.tonePendingReservationFileSuffix,
            ),
          );
      final leaseFile = toneDirectory
          .listSync(followLinks: false)
          .whereType<File>()
          .singleWhere((file) => file.path.endsWith('.lease'));
      final record =
          jsonDecode(await pendingFile.readAsString()) as Map<String, dynamic>;
      record['state'] = 'publishing';
      record['publishingAtMs'] = startedAt
          .add(repairCase.postShowOffset)
          .millisecondsSinceEpoch;
      await pendingFile.writeAsString(jsonEncode(record), flush: true);
      await leaseFile.writeAsString(
        (startedAt.add(repairCase.numericOffset).millisecondsSinceEpoch /
                Duration.millisecondsPerSecond)
            .toStringAsFixed(3),
        flush: true,
      );

      now = now.add(const Duration(seconds: 61));
      expect(await coordinator.reserveTone(conversation), isNull);
      expect(pendingFile.existsSync(), isFalse);
      final repairedAtMs =
          (double.parse(await leaseFile.readAsString()) *
                  Duration.millisecondsPerSecond)
              .round();
      expect(
        repairedAtMs,
        startedAt.add(repairCase.expectedOffset).millisecondsSinceEpoch,
      );
    });
  }

  test(
    'committed tone repair failure remains silent and retains sidecar',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
      );
      expect(
        await coordinator.reserveTone('committed-repair-failure'),
        isNotNull,
      );
      final toneDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.toneLeasesDirectoryName}',
      );
      final pendingFile = toneDirectory
          .listSync(followLinks: false)
          .whereType<File>()
          .singleWhere(
            (file) => file.path.endsWith(
              DurableNotificationToneLease.tonePendingReservationFileSuffix,
            ),
          );
      final leaseFile = toneDirectory
          .listSync(followLinks: false)
          .whereType<File>()
          .singleWhere((file) => file.path.endsWith('.lease'));
      final record =
          Map<String, Object?>.from(
              jsonDecode(await pendingFile.readAsString()) as Map,
            )
            ..['state'] = 'committed'
            ..['committedAtMs'] = now.millisecondsSinceEpoch;
      await pendingFile.writeAsString(jsonEncode(record), flush: true);
      await leaseFile.delete();
      await Directory(leaseFile.path).create();

      now = now.add(const Duration(seconds: 61));
      expect(await coordinator.reserveTone('committed-repair-failure'), isNull);
      expect(pendingFile.existsSync(), isTrue);
      expect(await pendingFile.readAsString(), contains('"state":"committed"'));
    },
  );

  test(
    'Android tone repair atomically replaces numeric lease before sidecar',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingToneReservationWait: Duration.zero,
        toneWindow: const Duration(seconds: 30),
      );
      expect(await coordinator.reserveTone('atomic-numeric-repair'), isNotNull);
      final toneDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.toneLeasesDirectoryName}',
      );
      final pendingFile = toneDirectory
          .listSync(followLinks: false)
          .whereType<File>()
          .singleWhere(
            (file) => file.path.endsWith(
              DurableNotificationToneLease.tonePendingReservationFileSuffix,
            ),
          );
      final leaseFile = toneDirectory
          .listSync(followLinks: false)
          .whereType<File>()
          .singleWhere((file) => file.path.endsWith('.lease'));
      final originalLeaseBytes = await leaseFile.readAsString();
      final publishing =
          jsonDecode(await pendingFile.readAsString()) as Map<String, dynamic>
            ..['state'] = 'publishing'
            ..['publishingAtMs'] = now.millisecondsSinceEpoch;
      await pendingFile.writeAsString(jsonEncode(publishing), flush: true);
      final replacementBlocker = Directory('${leaseFile.path}.replacement.tmp');
      await replacementBlocker.create();

      now = now.add(const Duration(seconds: 61));
      expect(await coordinator.reserveTone('atomic-numeric-repair'), isNull);
      expect(pendingFile.existsSync(), isTrue);
      expect(await leaseFile.readAsString(), originalLeaseBytes);

      await replacementBlocker.delete();
      expect(await coordinator.reserveTone('atomic-numeric-repair'), isNull);
      expect(pendingFile.existsSync(), isFalse);
      expect(
        await leaseFile.readAsString(),
        (now.millisecondsSinceEpoch / Duration.millisecondsPerSecond)
            .toStringAsFixed(3),
      );
    },
  );

  test(
    'successful native event show has bounded fail-closed finalization',
    () async {
      var now = DateTime.utc(2026, 8, 3, 20);
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        now: () => now,
        pendingClaimWait: Duration.zero,
        pendingMessageClaimTtl: const Duration(seconds: 60),
        claimTokenFactory: () => 'bounded-finalization-owner',
      );
      final claim = (await coordinator.acquireMessageEventClaim(
        type: 'new_message',
        eventIdentity: 'bounded-finalization-event',
      )).claim!;
      final claimFile = File(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.eventClaimsDirectoryName}'
        '${Platform.pathSeparator}'
        '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'bounded-finalization-event')}',
      );
      final nativeEntered = Completer<void>();
      final releaseNative = Completer<void>();
      final publication = claim.publishAndCommit(() async {
        nativeEntered.complete();
        await releaseNative.future;
      });
      await nativeEntered.future.timeout(_outerWatchdog);

      final held = await _HeldNativeFlock.acquire(
        File(
          '${directory.path}${Platform.pathSeparator}'
          '.${DurableNotificationToneLease.eventClaimsDirectoryName}.lock',
        ),
        holdFor: _ownerHold,
      );
      try {
        final stopwatch = Stopwatch()..start();
        releaseNative.complete();
        final result = await publication.timeout(_outerWatchdog);
        stopwatch.stop();

        expect(result.published, isTrue);
        expect(result.claimCommitted, isFalse);
        expect(stopwatch.elapsed, lessThan(_boundedCompletionCeiling));
        expect(held.released, isFalse);
        expect(
          await claimFile.readAsString(),
          contains('"state":"publishing"'),
        );

        await held.waitUntilReleased().timeout(_outerWatchdog);
        now = now.add(const Duration(seconds: 61));
        final duplicate = await coordinator.acquireMessageEventClaim(
          type: 'new_message',
          eventIdentity: 'bounded-finalization-event',
        );
        expect(
          duplicate.disposition,
          DurableNotificationClaimDisposition.committedOrUnavailable,
        );
        expect(
          await claimFile.readAsString(),
          allOf(
            contains('"state":"committed"'),
            contains('"publicationOutcome":"unknown"'),
            isNot(contains('"token"')),
          ),
        );
      } finally {
        await held.dispose();
      }
    },
  );

  test(
    'shown tone commits independently while the event lock is held',
    () async {
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        pendingClaimWait: Duration.zero,
        pendingToneReservationWait: Duration.zero,
        claimTokenFactory: () => 'cross-lock-event-owner',
      );
      final claim = (await coordinator.acquireMessageEventClaim(
        type: 'new_message',
        eventIdentity: 'cross-lock-event',
      )).claim!;
      final reservation = await coordinator.reserveTone(
        'cross-lock-event-conversation',
      );
      expect(reservation, isNotNull);
      final pendingTone =
          Directory(
                '${directory.path}${Platform.pathSeparator}'
                '${DurableNotificationToneLease.toneLeasesDirectoryName}',
              )
              .listSync(followLinks: false)
              .whereType<File>()
              .singleWhere(
                (file) => file.path.endsWith(
                  DurableNotificationToneLease.tonePendingReservationFileSuffix,
                ),
              );
      final held = await _HeldNativeFlock.acquire(
        File(
          '${directory.path}${Platform.pathSeparator}'
          '.${DurableNotificationToneLease.eventClaimsDirectoryName}.lock',
        ),
        holdFor: _ownerHold,
      );
      var commitsCompleted = false;
      try {
        final commits = commitShownNotificationOwners(
          messageClaim: claim,
          toneReservation: reservation,
        )..then((_) => commitsCompleted = true);
        await _waitForFileRemoval(
          pendingTone,
        ).timeout(const Duration(seconds: 1));
        expect(held.released, isFalse);
        expect(commitsCompleted, isFalse);

        final result = await commits.timeout(_outerWatchdog);
        expect(result.messageClaimCommitted, isTrue);
        expect(result.toneReservationCommitted, isTrue);
      } finally {
        await held.dispose();
      }
    },
  );

  test(
    'notification-id contender fails closed with no prepared or plugin effect',
    () async {
      const conversationKey = 'group:bounded-id-contender';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        conversationKey,
        activeNotificationIds: () async => const <Object?>[],
      );
      const original = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: 'message-original',
        generation: 'generation-original',
      );
      await registry.recordContentMetadata(
        conversationKey: conversationKey,
        notificationId: id,
        metadata: original,
      );
      final ownerFilesBefore = directory
          .listSync(followLinks: false)
          .whereType<File>()
          .where(
            (file) => file.path.endsWith(
              DurableConversationNotificationIdRegistry.ownerFileSuffix,
            ),
          )
          .map((file) => file.path)
          .toSet();

      final lock = File(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableConversationNotificationIdRegistry.coordinationLockFileName}',
      );
      final held = await _HeldNativeFlock.acquire(lock, holdFor: _ownerHold);
      final effects = <String>[];
      Object? contenderError;
      final stopwatch = Stopwatch()..start();
      try {
        await registry
            .replaceContent(
              conversationKey: conversationKey,
              notificationId: id,
              metadata: const ConversationNotificationContentMetadata(
                kind: ConversationNotificationContentKind.reaction,
                eventIdentity: 'reaction-must-not-prepare',
                generation: 'generation-must-not-show',
              ),
              retireCurrent: () async => effects.add('cancel'),
              replace: () async => effects.add('show'),
            )
            .timeout(_outerWatchdog);
      } catch (error) {
        contenderError = error;
      } finally {
        stopwatch.stop();
      }

      final completedBeforeOwnerRelease = !held.released;
      final metadata = await registry.lookupContentMetadata(
        conversationKey: conversationKey,
        notificationId: id,
      );
      final temporaryFiles = directory
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.tmp'))
          .toList(growable: false);
      final ownerFilesAfter = directory
          .listSync(followLinks: false)
          .whereType<File>()
          .where(
            (file) => file.path.endsWith(
              DurableConversationNotificationIdRegistry.ownerFileSuffix,
            ),
          )
          .map((file) => file.path)
          .toSet();
      await held.dispose();

      expect(contenderError, isA<NotificationIdAllocationException>());
      expect(stopwatch.elapsed, lessThan(_boundedCompletionCeiling));
      expect(completedBeforeOwnerRelease, isTrue);
      expect(effects, isEmpty);
      expect(temporaryFiles, isEmpty);
      expect(ownerFilesAfter, ownerFilesBefore, reason: 'no remap is allowed');
      expect(await registry.lookup(conversationKey), id);
      expect(metadata, original);
    },
  );

  test(
    'acquired notification-id owner is not timeout-released and newer generation survives',
    () async {
      const conversationKey = 'group:acquired-id-owner';
      final registry = DurableConversationNotificationIdRegistry(
        directory: directory,
      );
      final id = await registry.resolve(
        conversationKey,
        activeNotificationIds: () async => const <Object?>[],
      );
      await registry.recordContentMetadata(
        conversationKey: conversationKey,
        notificationId: id,
        metadata: const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'message-before-owner',
          generation: 'generation-before-owner',
        ),
      );

      final ownerEntered = File('${directory.path}/owner-entered');
      final ownerCompleted = File('${directory.path}/owner-completed');
      final unexpectedCancel = File('${directory.path}/unexpected-cancel');
      final rootPath = directory.path;
      final owner = Isolate.run(() async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final isolated = DurableConversationNotificationIdRegistry(
            directory: Directory(rootPath),
          );
          return await isolated.replaceContent(
            conversationKey: conversationKey,
            notificationId: id,
            metadata: const ConversationNotificationContentMetadata(
              kind: ConversationNotificationContentKind.reaction,
              eventIdentity: 'reaction-new-owner',
              generation: 'generation-new-owner',
            ),
            retireCurrent: () async {},
            replace: () async {
              await File(ownerEntered.path).create();
              await Future<void>.delayed(_ownerHold);
              await File(ownerCompleted.path).create();
            },
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
      await _waitForFile(ownerEntered).timeout(_outerWatchdog);

      Object? contenderError;
      bool? contenderResult;
      final stopwatch = Stopwatch()..start();
      try {
        contenderResult = await registry
            .cancelContentIfGeneration(
              conversationKey: conversationKey,
              notificationId: id,
              generation: 'generation-new-owner',
              cancel: () async => unexpectedCancel.create(),
            )
            .timeout(_outerWatchdog);
      } catch (error) {
        contenderError = error;
      } finally {
        stopwatch.stop();
      }

      final ownerWasStillRunning = !ownerCompleted.existsSync();
      final ownerResult = await owner.timeout(_outerWatchdog);
      final finalMetadata = await registry.lookupContentMetadata(
        conversationKey: conversationKey,
        notificationId: id,
      );

      expect(contenderError, isA<NotificationIdAllocationException>());
      expect(contenderResult, isNull);
      expect(stopwatch.elapsed, lessThan(_boundedCompletionCeiling));
      expect(ownerWasStillRunning, isTrue);
      expect(unexpectedCancel.existsSync(), isFalse);
      expect(
        ownerResult,
        ConversationNotificationContentReplacementResult.shownAndRecorded,
      );
      expect(ownerCompleted.existsSync(), isTrue);
      expect(
        finalMetadata,
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'reaction-new-owner',
          generation: 'generation-new-owner',
        ),
      );
    },
  );

  test(
    'android overlay contender is bounded and owner state survives',
    () async {
      final secureStore = _MemorySecureKeyStore();
      final store = PendingConversationNotificationOverlayStore(
        directory: directory,
        resolveBinding: () async => 'v1:bounded-overlay',
        secureStore: secureStore,
      );
      final ownerProjection = await store.project(
        conversationKey: 'peer-overlay',
        canonicalSnapshot: null,
        currentMessage: const PendingConversationNotificationMessage(
          eventId: 'event-existing-owner',
          line: 'existing owner',
          occurredAtMicros: 1,
        ),
      );
      expect(ownerProjection?.totalUnreadMessageCount, 1);
      final ownerState = secureStore
          .values[PendingConversationNotificationOverlayStore.secureStorageKey];
      final lock = File(
        '${directory.path}${Platform.pathSeparator}'
        '${PendingConversationNotificationOverlayStore.lockFileName}',
      );
      final held = await _HeldNativeFlock.acquire(lock, holdFor: _ownerHold);

      ConversationNotificationSnapshot? contenderResult;
      Object? contenderError;
      final stopwatch = Stopwatch()..start();
      try {
        contenderResult = await store
            .project(
              conversationKey: 'peer-overlay',
              canonicalSnapshot: null,
              currentMessage: const PendingConversationNotificationMessage(
                eventId: 'event-must-not-write',
                line: 'must not write',
                occurredAtMicros: 2,
              ),
            )
            .timeout(_outerWatchdog);
      } catch (error) {
        contenderError = error;
      } finally {
        stopwatch.stop();
      }

      final completedBeforeOwnerRelease = !held.released;
      final stateBeforeRelease = secureStore
          .values[PendingConversationNotificationOverlayStore.secureStorageKey];
      await held.waitUntilReleased().timeout(_outerWatchdog);
      final afterRelease = await store.project(
        conversationKey: 'peer-overlay',
        canonicalSnapshot: null,
        currentMessage: const PendingConversationNotificationMessage(
          eventId: 'event-after-release',
          line: 'after release',
          occurredAtMicros: 3,
        ),
      );
      await held.dispose();

      expect(
        contenderError != null || contenderResult == null,
        isTrue,
        reason: 'the unavailable contender must fail closed',
      );
      expect(stopwatch.elapsed, lessThan(_boundedCompletionCeiling));
      expect(completedBeforeOwnerRelease, isTrue);
      expect(stateBeforeRelease, ownerState);
      expect(afterRelease?.totalUnreadMessageCount, 2);
      expect(afterRelease?.historyLines, <String>[
        'existing owner',
        'after release',
      ]);
    },
  );

  test('android overlay same-process coordination is lossless', () async {
    final secureStore = _InterleavingSecureKeyStore();
    PendingConversationNotificationOverlayStore buildStore() =>
        PendingConversationNotificationOverlayStore(
          directory: directory,
          resolveBinding: () async => 'v1:lossless-overlay',
          secureStore: secureStore,
        );

    final first = buildStore().project(
      conversationKey: 'group:overlay-race',
      canonicalSnapshot: null,
      currentMessage: const PendingConversationNotificationMessage(
        eventId: 'event-a',
        line: 'line A',
        occurredAtMicros: 1,
      ),
    );
    await secureStore.firstStateReadStarted.future.timeout(_outerWatchdog);
    final second = buildStore().project(
      conversationKey: 'group:overlay-race',
      canonicalSnapshot: null,
      currentMessage: const PendingConversationNotificationMessage(
        eventId: 'event-b',
        line: 'line B',
        occurredAtMicros: 2,
      ),
    );
    await Future.wait(<Future<Object?>>[first, second]).timeout(_outerWatchdog);

    final raw = secureStore
        .values[PendingConversationNotificationOverlayStore.secureStorageKey];
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, Object?>;
    final conversations = decoded['conversations']! as Map<String, Object?>;
    final entries = conversations.values.single as List<Object?>;
    expect(entries, hasLength(2));
    expect(raw, contains('line A'));
    expect(raw, contains('line B'));
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    test('$platform tone sidecars retain legacy reclaim bytes', () async {
      debugDefaultTargetPlatformOverride = platform;
      final startedAt = DateTime.utc(2026, 8, 3, 20);
      final fixtures = <String>[
        'malformed',
        'unknown-state',
        'pending-publishing-timestamp',
        'pending-committed-timestamp',
      ];

      for (final fixture in fixtures) {
        var now = startedAt;
        var tokenIndex = 0;
        final fixtureDirectory = Directory(
          '${directory.path}${Platform.pathSeparator}$fixture',
        );
        final coordinator = DurableNotificationToneLease(
          directory: fixtureDirectory,
          now: () => now,
          platform: platform,
          pendingToneReservationWait: Duration.zero,
          pendingToneReservationTtl: const Duration(seconds: 60),
          toneWindow: const Duration(seconds: 30),
          claimTokenFactory: () => tokenIndex++ == 0
              ? 'legacy-initial-$fixture'
              : 'legacy-replacement-$fixture',
        );
        expect(await coordinator.reserveTone('legacy-$fixture'), isNotNull);
        final toneDirectory = Directory(
          '${fixtureDirectory.path}${Platform.pathSeparator}'
          '${DurableNotificationToneLease.toneLeasesDirectoryName}',
        );
        final pendingFile = toneDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .singleWhere(
              (file) => file.path.endsWith(
                DurableNotificationToneLease.tonePendingReservationFileSuffix,
              ),
            );
        final leaseFile = toneDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .singleWhere((file) => file.path.endsWith('.lease'));
        if (fixture == 'malformed') {
          await pendingFile.writeAsString('{', flush: true);
        } else {
          final record =
              jsonDecode(await pendingFile.readAsString())
                  as Map<String, dynamic>;
          if (fixture == 'unknown-state') {
            record['state'] = 'publishin';
            record['publishingAtMs'] = startedAt.millisecondsSinceEpoch;
          } else if (fixture == 'pending-publishing-timestamp') {
            record['publishingAtMs'] = startedAt.millisecondsSinceEpoch;
          } else {
            record['committedAtMs'] = startedAt.millisecondsSinceEpoch;
          }
          await pendingFile.writeAsString(jsonEncode(record), flush: true);
        }

        now = now.add(const Duration(seconds: 61));
        final replacement = await coordinator.reserveTone('legacy-$fixture');
        expect(
          replacement,
          isNotNull,
          reason:
              '$platform must keep the legacy reclaim decision for $fixture',
        );
        final nowMs = now.millisecondsSinceEpoch;
        expect(
          await pendingFile.readAsString(),
          jsonEncode(<String, Object>{
            'state': 'pending',
            'token': 'legacy-replacement-$fixture',
            'reservedAtMs': nowMs,
            'createdAtMs': nowMs,
          }),
        );
        expect(
          await leaseFile.readAsString(),
          (nowMs / Duration.millisecondsPerSecond).toStringAsFixed(3),
        );
        expect(await replacement!.release(), isTrue);
      }
    });

    test(
      '$platform committed tone repair keeps historical and in-place bytes',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final startedAt = DateTime.utc(2026, 8, 3, 20);

        var now = startedAt;
        final repairDirectory = Directory(
          '${directory.path}${Platform.pathSeparator}legacy-repair',
        );
        final repairCoordinator = DurableNotificationToneLease(
          directory: repairDirectory,
          now: () => now,
          platform: platform,
          pendingToneReservationWait: Duration.zero,
          toneWindow: const Duration(seconds: 30),
        );
        expect(
          await repairCoordinator.reserveTone('legacy-committed-repair'),
          isNotNull,
        );
        final repairToneDirectory = Directory(
          '${repairDirectory.path}${Platform.pathSeparator}'
          '${DurableNotificationToneLease.toneLeasesDirectoryName}',
        );
        final repairPending = repairToneDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .singleWhere(
              (file) => file.path.endsWith(
                DurableNotificationToneLease.tonePendingReservationFileSuffix,
              ),
            );
        final repairLease = repairToneDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .singleWhere((file) => file.path.endsWith('.lease'));
        final committedAt = startedAt.add(const Duration(seconds: 5));
        final repairRecord =
            jsonDecode(await repairPending.readAsString())
                  as Map<String, dynamic>
              ..['state'] = 'committed'
              ..['committedAtMs'] = committedAt.millisecondsSinceEpoch;
        await repairPending.writeAsString(
          jsonEncode(repairRecord),
          flush: true,
        );

        now = startedAt.add(const Duration(seconds: 6));
        expect(
          await repairCoordinator.reserveTone('legacy-committed-repair'),
          isNull,
        );
        expect(repairPending.existsSync(), isFalse);
        expect(
          await repairLease.readAsString(),
          (committedAt.millisecondsSinceEpoch / Duration.millisecondsPerSecond)
              .toStringAsFixed(3),
        );

        now = startedAt;
        final commitDirectory = Directory(
          '${directory.path}${Platform.pathSeparator}legacy-commit',
        );
        final commitCoordinator = DurableNotificationToneLease(
          directory: commitDirectory,
          now: () => now,
          platform: platform,
          pendingToneReservationWait: Duration.zero,
        );
        final reservation = await commitCoordinator.reserveTone(
          'legacy-in-place-commit',
        );
        expect(reservation, isNotNull);
        final commitToneDirectory = Directory(
          '${commitDirectory.path}${Platform.pathSeparator}'
          '${DurableNotificationToneLease.toneLeasesDirectoryName}',
        );
        final commitPending = commitToneDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .singleWhere(
              (file) => file.path.endsWith(
                DurableNotificationToneLease.tonePendingReservationFileSuffix,
              ),
            );
        final commitLease = commitToneDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .singleWhere((file) => file.path.endsWith('.lease'));
        final pendingBlocker = Directory(
          '${commitPending.path}.replacement.tmp',
        );
        final leaseBlocker = Directory('${commitLease.path}.replacement.tmp');
        await pendingBlocker.create();
        await leaseBlocker.create();

        now = startedAt.add(const Duration(seconds: 1));
        expect(await reservation!.commit(), isTrue);
        expect(commitPending.existsSync(), isFalse);
        expect(pendingBlocker.existsSync(), isTrue);
        expect(leaseBlocker.existsSync(), isTrue);
        expect(
          await commitLease.readAsString(),
          (now.millisecondsSinceEpoch / Duration.millisecondsPerSecond)
              .toStringAsFixed(3),
        );
      },
    );
  }

  for (final platform in <TargetPlatform>[
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    test('$platform tone flock keeps blocking non-Android behavior', () async {
      debugDefaultTargetPlatformOverride = platform;
      final toneDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        '${DurableNotificationToneLease.toneLeasesDirectoryName}',
      );
      final held = await _HeldNativeFlock.acquire(
        File(
          '${toneDirectory.path}${Platform.pathSeparator}'
          '${DurableNotificationToneLease.toneCoordinationLockFileName}',
        ),
        holdFor: const Duration(milliseconds: 350),
      );
      try {
        final stopwatch = Stopwatch()..start();
        final reservation = await DurableNotificationToneLease(
          directory: directory,
          pendingToneReservationWait: Duration.zero,
        ).reserveTone('peer-non-android');
        stopwatch.stop();

        expect(reservation, isNotNull);
        expect(
          stopwatch.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 250)),
        );
        expect(await reservation!.release(), isTrue);
      } finally {
        await held.dispose();
      }
    });
  }

  test('finite literal and non-Android source policy are preserved', () {
    final helper = File('lib/core/notifications/bounded_posix_flock.dart');
    expect(
      helper.existsSync(),
      isTrue,
      reason: 'notification lock users must share one reviewed primitive',
    );
    final helperSource = helper.readAsStringSync();
    final toneSource = File(
      'lib/core/notifications/durable_notification_tone_lease.dart',
    ).readAsStringSync();
    final idSource = File(
      'lib/core/notifications/'
      'durable_conversation_notification_id_registry.dart',
    ).readAsStringSync();
    final overlaySource = File(
      'lib/features/push/application/'
      'pending_conversation_notification_overlay.dart',
    ).readAsStringSync();
    final backgroundHandlerSource = File(
      'lib/features/push/application/background_message_handler.dart',
    ).readAsStringSync();
    final foregroundShowSource = File(
      'lib/features/push/application/show_notification_use_case.dart',
    ).readAsStringSync();

    expect(helperSource, contains('const Duration(seconds: 1)'));
    expect(
      helperSource,
      contains('defaultTargetPlatform == TargetPlatform.android'),
    );
    expect(helperSource, matches(RegExp(r'lockNonBlocking\s*=\s*4')));
    expect(
      helperSource,
      matches(RegExp(r'lockExclusive\s*\|\s*lockNonBlocking')),
    );
    final retryDeadlineFence =
        RegExp(
          r'if \(!ownerCompletion\s*&&\s*!firstAttempt\s*&&\s*'
          r'stopwatch\.elapsed >= acquisitionTimeout\)',
        ).firstMatch(helperSource)?.start ??
        -1;
    final nonBlockingAttempt = helperSource.indexOf(
      '_api.flock(descriptor, lockExclusive | lockNonBlocking)',
    );
    expect(retryDeadlineFence, greaterThanOrEqualTo(0));
    expect(
      retryDeadlineFence,
      lessThan(nonBlockingAttempt),
      reason: 'a delayed retry must be rejected before another flock attempt',
    );
    expect(
      helperSource,
      matches(RegExp(r'flock\([^;]+lockExclusive\)')),
      reason: 'iOS/macOS retain the existing blocking BSD-flock protocol',
    );
    expect(toneSource, contains('bounded_posix_flock.dart'));
    expect(helperSource, contains('withExclusiveOwnerCompletion'));
    expect(toneSource, contains('_PosixFlock.withExclusiveOwnerCompletion'));
    expect(toneSource, contains('commitShownNotificationOwners'));
    expect(
      backgroundHandlerSource,
      contains('currentEventClaim.publishAndCommit('),
    );
    expect(backgroundHandlerSource, contains('reservation.publishAndCommit('));
    expect(
      foregroundShowSource,
      contains('messageClaim.publishAndCommit(publishWithExactToneOwner)'),
    );
    expect(foregroundShowSource, contains('reservation.publishAndCommit('));
    expect(idSource, contains('bounded_posix_flock.dart'));
    expect(overlaySource, contains('bounded_posix_flock.dart'));
    expect(
      overlaySource,
      contains('lock(FileLock.exclusive)'),
      reason: 'the non-Android overlay record-lock branch remains unchanged',
    );
    expect(overlaySource, isNot(contains('FileLock.blockingExclusive')));
  });
}

final class _HeldNativeFlock {
  _HeldNativeFlock._({
    required Isolate isolate,
    required ReceivePort messages,
    required Future<void> releasedFuture,
    required bool Function() isReleased,
  }) : _isolate = isolate,
       _messages = messages,
       _releasedFuture = releasedFuture,
       _isReleased = isReleased;

  final Isolate _isolate;
  final ReceivePort _messages;
  final Future<void> _releasedFuture;
  final bool Function() _isReleased;
  bool _disposed = false;

  bool get released => _isReleased();

  static Future<_HeldNativeFlock> acquire(
    File file, {
    required Duration holdFor,
  }) async {
    await file.parent.create(recursive: true);
    await file.create(recursive: true);
    final messages = ReceivePort();
    final acquired = Completer<void>();
    final released = Completer<void>();
    var isReleased = false;
    late final StreamSubscription<Object?> subscription;
    subscription = messages.listen((message) {
      if (message == 'acquired') {
        if (!acquired.isCompleted) acquired.complete();
        return;
      }
      if (message == 'released') {
        isReleased = true;
        if (!released.isCompleted) released.complete();
        return;
      }
      final error = StateError('native flock holder failed: $message');
      if (!acquired.isCompleted) acquired.completeError(error);
      if (!released.isCompleted) released.completeError(error);
    });
    final isolate = await Isolate.spawn<List<Object?>>(
      _holdNativeFlock,
      <Object?>[file.path, holdFor.inMicroseconds, messages.sendPort],
      onError: messages.sendPort,
      errorsAreFatal: true,
    );
    try {
      await acquired.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      await subscription.cancel();
      messages.close();
      rethrow;
    }
    released.future.whenComplete(subscription.cancel);
    return _HeldNativeFlock._(
      isolate: isolate,
      messages: messages,
      releasedFuture: released.future,
      isReleased: () => isReleased,
    );
  }

  Future<void> waitUntilReleased() => _releasedFuture;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _releasedFuture.timeout(const Duration(seconds: 3));
    } catch (_) {
      _isolate.kill(priority: Isolate.immediate);
    } finally {
      _messages.close();
    }
  }
}

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _FlockNative = Int32 Function(Int32, Int32);
typedef _FlockDart = int Function(int, int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

Future<void> _holdNativeFlock(List<Object?> message) async {
  const openReadWrite = 2;
  const lockExclusive = 2;
  const lockUnlock = 8;
  final path = message[0]! as String;
  final holdMicros = message[1]! as int;
  final response = message[2]! as SendPort;
  final library = Platform.isAndroid
      ? DynamicLibrary.open('libc.so')
      : DynamicLibrary.process();
  final open = library.lookupFunction<_OpenNative, _OpenDart>('open');
  final flock = library.lookupFunction<_FlockNative, _FlockDart>('flock');
  final close = library.lookupFunction<_CloseNative, _CloseDart>('close');
  final nativePath = path.toNativeUtf8();
  late final int descriptor;
  try {
    descriptor = open(nativePath, openReadWrite);
  } finally {
    malloc.free(nativePath);
  }
  if (descriptor < 0) {
    response.send('open failed');
    return;
  }
  if (flock(descriptor, lockExclusive) != 0) {
    close(descriptor);
    response.send('flock failed');
    return;
  }
  response.send('acquired');
  try {
    await Future<void>.delayed(Duration(microseconds: holdMicros));
  } finally {
    flock(descriptor, lockUnlock);
    close(descriptor);
    response.send('released');
  }
}

Future<void> _waitForFile(File file) async {
  while (!await file.exists()) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _waitForFileContents(File file, String expected) async {
  while (!await file.exists() ||
      !(await file.readAsString()).contains(expected)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _waitForFileRemoval(File file) async {
  while (await file.exists()) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _InterleavingSecureKeyStore extends _MemorySecureKeyStore {
  final Completer<void> firstStateReadStarted = Completer<void>();
  var _stateReads = 0;

  @override
  Future<String?> read(String key) async {
    if (key != PendingConversationNotificationOverlayStore.secureStorageKey) {
      return super.read(key);
    }
    final snapshot = values[key];
    _stateReads += 1;
    if (_stateReads == 1) {
      firstStateReadStarted.complete();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return snapshot;
  }
}
