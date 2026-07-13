import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late DateTime now;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('reaction-tone-lease-');
    now = DateTime.utc(2026, 7, 12, 10);
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  DurableNotificationToneLease lease({
    Duration window = const Duration(seconds: 30),
    Duration ttl = const Duration(hours: 12),
    int maxClaims = 256,
    Duration pendingWait = const Duration(milliseconds: 50),
    Duration messagePendingTtl = const Duration(seconds: 60),
    Duration tonePendingWait = const Duration(milliseconds: 50),
    Duration tonePendingTtl = const Duration(seconds: 60),
    NotificationClaimTokenFactory? claimTokenFactory,
    ExclusiveNotificationClaimWriter? exclusiveClaimWriter,
  }) => DurableNotificationToneLease(
    directory: directory,
    now: () => now,
    toneWindow: window,
    eventTtl: ttl,
    maxEventClaims: maxClaims,
    pendingClaimWait: pendingWait,
    pendingMessageClaimTtl: messagePendingTtl,
    pendingToneReservationWait: tonePendingWait,
    pendingToneReservationTtl: tonePendingTtl,
    claimTokenFactory: claimTokenFactory,
    exclusiveClaimWriter: exclusiveClaimWriter,
  );

  test('simultaneous event claims have exactly one winner', () async {
    final coordinatorA = lease();
    final coordinatorB = lease();

    final results = await Future.wait([
      coordinatorA.claimEvent('reaction:event-1'),
      coordinatorB.claimEvent('reaction:event-1'),
    ]);

    expect(results.where((won) => won), hasLength(1));
  });

  test(
    'typed message claim uses exact NSE filename and token-matched commit',
    () async {
      final coordinator = lease(claimTokenFactory: () => 'owner-token');
      final claim = await coordinator.claimMessageEvent(
        type: 'group_message',
        eventIdentity: 'message:/with spaces',
      );

      expect(claim, isNotNull);
      expect(claim!.token, 'owner-token');
      final file = File(
        '${directory.path}/NotificationServiceDedupe/'
        'group_message-message__with_spaces',
      );
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('"state":"pending"'));
      expect(file.readAsStringSync(), contains('"token":"owner-token"'));

      expect(await claim.commit(), isTrue);
      expect(file.readAsStringSync(), contains('"state":"committed"'));
      expect(await claim.release(), isFalse);
      expect(file.existsSync(), isTrue);
    },
  );

  test('a stale token cannot release a newer pending owner', () async {
    final coordinator = lease(claimTokenFactory: () => 'first-token');
    final claim = await coordinator.claimMessageEvent(
      type: 'new_message',
      eventIdentity: 'message-1',
    );
    expect(claim, isNotNull);
    final file = File(
      '${directory.path}/NotificationServiceDedupe/new_message-message-1',
    );
    await file.writeAsString(
      '{"state":"pending","token":"replacement-token","createdAtMs":1}',
      flush: true,
    );

    expect(await claim!.release(), isFalse);
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), contains('replacement-token'));
  });

  test('pending contender waits once and wins after owner release', () async {
    var nextToken = 0;
    final first = lease(
      pendingWait: const Duration(milliseconds: 50),
      claimTokenFactory: () => 'token-${nextToken++}',
    );
    final second = lease(
      pendingWait: const Duration(milliseconds: 50),
      claimTokenFactory: () => 'token-${nextToken++}',
    );
    final owner = await first.claimMessageEvent(
      type: 'new_message',
      eventIdentity: 'message-retry',
    );
    expect(owner, isNotNull);

    final contender = second.claimMessageEvent(
      type: 'new_message',
      eventIdentity: 'message-retry',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(await owner!.release(), isTrue);

    final winner = await contender;
    expect(winner, isNotNull);
    expect(winner!.token, isNot(owner.token));
    expect(await winner.commit(), isTrue);
  });

  test('fresh pending message owner suppresses until its short TTL', () async {
    final owner = await lease(
      pendingWait: Duration.zero,
      messagePendingTtl: const Duration(seconds: 60),
      claimTokenFactory: () => 'fresh-owner',
    ).claimMessageEvent(type: 'new_message', eventIdentity: 'message-fresh');
    expect(owner, isNotNull);

    now = now.add(const Duration(seconds: 59));
    final contender = await lease(
      pendingWait: Duration.zero,
      messagePendingTtl: const Duration(seconds: 60),
      claimTokenFactory: () => 'must-not-own',
    ).claimMessageEvent(type: 'new_message', eventIdentity: 'message-fresh');

    expect(contender, isNull);
    expect(await owner!.commit(), isTrue);
  });

  test(
    'stale pending message owner is atomically replaced and loses CAS authority',
    () async {
      final stale =
          await lease(
            pendingWait: Duration.zero,
            messagePendingTtl: const Duration(seconds: 60),
            claimTokenFactory: () => 'stale-owner',
          ).claimMessageEvent(
            type: 'group_message',
            eventIdentity: 'message-stale',
          );
      expect(stale, isNotNull);

      now = now.add(const Duration(seconds: 60));
      final recovered =
          await lease(
            pendingWait: Duration.zero,
            messagePendingTtl: const Duration(seconds: 60),
            claimTokenFactory: () => 'replacement-owner',
          ).claimMessageEvent(
            type: 'group_message',
            eventIdentity: 'message-stale',
          );

      expect(recovered, isNotNull);
      expect(recovered!.token, 'replacement-owner');
      expect(await stale!.commit(), isFalse);
      expect(await stale.release(), isFalse);
      expect(await recovered.commit(), isTrue);
    },
  );

  test('committed, NSE, and malformed claims retain the long event TTL', () async {
    final committed =
        await lease(
          pendingWait: Duration.zero,
          messagePendingTtl: const Duration(seconds: 1),
        ).claimMessageEvent(
          type: 'new_message',
          eventIdentity: 'message-committed',
        );
    expect(committed, isNotNull);
    expect(await committed!.commit(), isTrue);

    final eventDirectory = Directory(
      '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}',
    );
    final nseFile = File(
      '${eventDirectory.path}/'
      '${DurableNotificationToneLease.messageEventClaimFileName(type: 'group_message', eventIdentity: 'message-nse')}',
    );
    await nseFile.writeAsString('', flush: true);
    final malformedFile = File(
      '${eventDirectory.path}/'
      '${DurableNotificationToneLease.messageEventClaimFileName(type: 'group_message', eventIdentity: 'message-malformed')}',
    );
    await malformedFile.writeAsBytes(<int>[0xff, 0xfe], flush: true);
    now = now.add(const Duration(seconds: 2));

    expect(
      await lease(
        pendingWait: Duration.zero,
        messagePendingTtl: const Duration(seconds: 1),
      ).claimMessageEvent(
        type: 'new_message',
        eventIdentity: 'message-committed',
      ),
      isNull,
    );
    expect(
      await lease(
        pendingWait: Duration.zero,
        messagePendingTtl: const Duration(seconds: 1),
      ).claimMessageEvent(type: 'group_message', eventIdentity: 'message-nse'),
      isNull,
    );
    expect(
      await lease(
        pendingWait: Duration.zero,
        messagePendingTtl: const Duration(seconds: 1),
      ).claimMessageEvent(
        type: 'group_message',
        eventIdentity: 'message-malformed',
      ),
      isNull,
    );
  });

  test(
    'post-create write failure removes only self-created residue and remains retryable',
    () async {
      final failing = lease(
        pendingWait: Duration.zero,
        exclusiveClaimWriter: (file, contents) async {
          await file.writeAsString('{partial', flush: true);
          throw const FileSystemException(
            'synthetic post-create write failure',
          );
        },
      );
      final claimFile = File(
        '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/'
        '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'message-write-failure')}',
      );

      await expectLater(
        failing.claimMessageEvent(
          type: 'new_message',
          eventIdentity: 'message-write-failure',
        ),
        throwsA(
          isA<DurableNotificationStorageException>().having(
            (error) => error.operation,
            'operation',
            'exclusive_claim_write',
          ),
        ),
      );
      expect(claimFile.existsSync(), isFalse);

      final retry = await lease(pendingWait: Duration.zero).claimMessageEvent(
        type: 'new_message',
        eventIdentity: 'message-write-failure',
      );
      expect(retry, isNotNull);
      expect(await retry!.commit(), isTrue);
    },
  );

  test(
    'proven exclusive-create collision never invokes writer or deletes owner',
    () async {
      final existing = await lease(pendingWait: Duration.zero)
          .claimMessageEvent(
            type: 'new_message',
            eventIdentity: 'message-existing-owner',
          );
      expect(existing, isNotNull);
      expect(await existing!.commit(), isTrue);
      var writerCalls = 0;

      final contender =
          await lease(
            pendingWait: Duration.zero,
            exclusiveClaimWriter: (file, contents) async {
              writerCalls++;
              throw StateError('must not overwrite an existing claim');
            },
          ).claimMessageEvent(
            type: 'new_message',
            eventIdentity: 'message-existing-owner',
          );

      expect(contender, isNull);
      expect(writerCalls, 0);
      final existingFile = File(
        '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/'
        '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'message-existing-owner')}',
      );
      expect(existingFile.readAsStringSync(), contains('"state":"committed"'));
    },
  );

  test('exact message claims have one coordinated isolate winner', () async {
    final first = _claimMessageInFreshIsolate(directory.path, 'isolate-a');
    final second = _claimMessageInFreshIsolate(directory.path, 'isolate-b');
    await _waitForFile(File('${directory.path}/claim-ready-isolate-a'));
    await _waitForFile(File('${directory.path}/claim-ready-isolate-b'));
    await File('${directory.path}/claim-start').create();

    final tokens = await Future.wait([first, second]);
    expect(tokens.whereType<String>(), hasLength(1));
  });

  test('different typed message ids claim independently', () async {
    final claims = await Future.wait([
      lease().claimMessageEvent(type: 'new_message', eventIdentity: 'direct-1'),
      lease().claimMessageEvent(
        type: 'group_message',
        eventIdentity: 'group-1',
      ),
    ]);

    expect(claims, everyElement(isNotNull));
    expect(
      DurableNotificationToneLease.messageEventClaimFileName(
        type: 'new_message',
        eventIdentity: 'id:/? unicode-ä',
      ),
      'new_message-id____unicode-_',
    );
  });

  test(
    'tone lease survives restart and expires without extending on silence',
    () async {
      expect(await lease().acquireTone('peer-alice'), isTrue);

      now = now.add(const Duration(seconds: 10));
      expect(await lease().acquireTone('peer-alice'), isFalse);

      now = now.add(const Duration(seconds: 20));
      expect(await lease().acquireTone('peer-alice'), isTrue);
    },
  );

  test('tone window starts when the reservation commits', () async {
    final coordinator = lease(tonePendingTtl: const Duration(minutes: 1));
    final reservation = await coordinator.reserveTone('peer-commit-window');
    expect(reservation, isNotNull);

    now = now.add(const Duration(seconds: 20));
    expect(await reservation!.commit(), isTrue);

    now = now.add(const Duration(seconds: 29));
    expect(await lease().reserveTone('peer-commit-window'), isNull);

    now = now.add(const Duration(seconds: 1));
    final next = await lease().reserveTone('peer-commit-window');
    expect(next, isNotNull);
    expect(await next!.release(), isTrue);
  });

  test('release keeps a redelivery audible', () async {
    final first = await lease().reserveTone('peer-show-failed');
    expect(first, isNotNull);
    expect(await first!.release(), isTrue);

    final redelivery = await lease().reserveTone('peer-show-failed');
    expect(redelivery, isNotNull);
    expect(await redelivery!.commit(), isTrue);
    expect(await lease().reserveTone('peer-show-failed'), isNull);
  });

  test('pending contender retries once after the owner releases', () async {
    var nextToken = 0;
    DurableNotificationToneLease coordinator() => lease(
      tonePendingWait: const Duration(milliseconds: 50),
      claimTokenFactory: () => 'tone-token-${nextToken++}',
    );
    final owner = await coordinator().reserveTone('peer-pending-retry');
    expect(owner, isNotNull);

    final contender = coordinator().reserveTone('peer-pending-retry');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(await owner!.release(), isTrue);

    final winner = await contender;
    expect(winner, isNotNull);
    expect(winner!.token, isNot(owner.token));
    expect(await winner.commit(), isTrue);
  });

  test('wrong token cannot commit or release another tone owner', () async {
    final reservation = await lease(
      claimTokenFactory: () => 'original-tone-owner',
    ).reserveTone('peer-wrong-token');
    expect(reservation, isNotNull);

    final pendingFile = _onlyPendingToneFile(directory);
    final record = Map<String, Object?>.from(
      jsonDecode(pendingFile.readAsStringSync()) as Map,
    );
    record['token'] = 'replacement-tone-owner';
    await pendingFile.writeAsString(jsonEncode(record), flush: true);

    expect(await reservation!.commit(), isFalse);
    expect(await reservation.release(), isFalse);
    expect(pendingFile.existsSync(), isTrue);
    expect(pendingFile.readAsStringSync(), contains('replacement-tone-owner'));
  });

  test(
    'stale pending tone owner is recovered without stale-token mutation',
    () async {
      var nextToken = 0;
      DurableNotificationToneLease coordinator() => lease(
        tonePendingWait: Duration.zero,
        tonePendingTtl: const Duration(seconds: 1),
        claimTokenFactory: () => 'stale-token-${nextToken++}',
      );
      final stale = await coordinator().reserveTone('peer-stale-pending');
      expect(stale, isNotNull);

      now = now.add(const Duration(seconds: 2));
      final recovered = await coordinator().reserveTone('peer-stale-pending');
      expect(recovered, isNotNull);
      expect(recovered!.token, isNot(stale!.token));

      expect(await stale.commit(), isFalse);
      expect(await stale.release(), isFalse);
      expect(await recovered.commit(), isTrue);
    },
  );

  test('expired crash residue is reclaimed and claims stay bounded', () async {
    final first = lease(ttl: const Duration(seconds: 5), maxClaims: 2);
    expect(await first.claimEvent('event-old'), isTrue);
    now = now.add(const Duration(seconds: 6));
    expect(await first.claimEvent('event-new-1'), isTrue);
    expect(await first.claimEvent('event-new-2'), isTrue);
    expect(await first.claimEvent('event-new-3'), isTrue);

    final files = Directory(
      '${directory.path}/NotificationServiceDedupe',
    ).listSync().whereType<File>().toList();
    expect(files.length, lessThanOrEqualTo(2));
    expect(await first.claimEvent('event-old'), isTrue);
  });

  test('distinct conversations acquire independent tone leases', () async {
    final coordinator = lease();
    expect(await coordinator.acquireTone('peer-a'), isTrue);
    expect(await coordinator.acquireTone('peer-b'), isTrue);
    expect(await coordinator.acquireTone('peer-a'), isFalse);
  });

  test(
    'simultaneous tone attempts use one shared coordination winner',
    () async {
      final results = await Future.wait([
        lease().acquireTone('peer-same'),
        lease().acquireTone('peer-same'),
      ]);

      expect(results.where((won) => won), hasLength(1));
      expect(
        File(
          '${directory.path}/NotificationToneLeases/'
          '${DurableNotificationToneLease.toneCoordinationLockFileName}',
        ).existsSync(),
        isTrue,
      );
    },
  );

  test('concurrent isolates reserve at most one audible right', () async {
    final holderEntered = File('${directory.path}/reservation-holder-entered');
    final holderRelease = File('${directory.path}/reservation-holder-release');
    final contenderStarted = File(
      '${directory.path}/reservation-contender-started',
    );
    final holder = _holdToneReservationInFreshIsolate(directory.path);
    await _waitForFile(holderEntered);

    final contender = _contendForToneReservationInFreshIsolate(directory.path);
    await _waitForFile(contenderStarted);
    expect(
      await contender.timeout(const Duration(seconds: 2)),
      isFalse,
      reason: 'the pending owner must be the sole audible reservation',
    );

    await holderRelease.create();
    expect(await holder.timeout(const Duration(seconds: 5)), isTrue);
  });

  test('foreground and background isolates have one tone winner', () async {
    final holderEntered = File('${directory.path}/tone-holder-entered');
    final holderRelease = File('${directory.path}/tone-holder-release');
    final contenderStarted = File('${directory.path}/tone-contender-started');
    final holder = _holdToneLockInFreshIsolate(directory.path);
    await _waitForFile(holderEntered);

    var contenderCompleted = false;
    final contender = _contendForToneInFreshIsolate(
      directory.path,
    ).whenComplete(() => contenderCompleted = true);
    await _waitForFile(contenderStarted);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final completedBeforeHolderRelease = contenderCompleted;

    await holderRelease.create();
    final results = await Future.wait([
      holder,
      contender,
    ]).timeout(const Duration(seconds: 10));

    expect(completedBeforeHolderRelease, isFalse);
    expect(results.where((won) => won), hasLength(1));
    expect(results, [isTrue, isFalse]);
  });

  test('uses the exact NSE claim and tone filesystem contract', () async {
    const identity =
        'reaction:813117a606a0d109f3414152f6092e5c33da6c311a4a7736';
    final coordinator = lease();

    expect(await coordinator.claimEvent(identity), isTrue);
    final claim = File(
      '${directory.path}/NotificationServiceDedupe/'
      'message_reaction-reaction_813117a606a0d109f3414152f6092e5c33da6c311a4a7736',
    );
    expect(claim.existsSync(), isTrue);

    final groupIdentity = boundedReactionEventIdentity(
      'group-reaction-event-1',
    );
    expect(
      groupIdentity,
      'reaction:bfa7b4002bed4b9fb3a1f537c29b03b7bab67234bfe72d2f',
    );
    expect(await coordinator.claimEvent(groupIdentity), isTrue);
    final groupClaim = File(
      '${directory.path}/NotificationServiceDedupe/'
      'message_reaction-reaction_bfa7b4002bed4b9fb3a1f537c29b03b7bab67234bfe72d2f',
    );
    expect(groupClaim.existsSync(), isTrue);

    expect(await coordinator.acquireTone('peer-alice'), isTrue);
    final toneName = '${sha256.convert('peer-alice'.codeUnits)}.lease';
    final tone = File('${directory.path}/NotificationToneLeases/$toneName');
    expect(tone.existsSync(), isTrue);
    expect(
      File(
        '${directory.path}/NotificationToneLeases/'
        '${DurableNotificationToneLease.toneCoordinationLockFileName}',
      ).existsSync(),
      isTrue,
    );
    final swiftTimeInterval = double.parse(tone.readAsStringSync());
    expect(swiftTimeInterval, now.millisecondsSinceEpoch / 1000);

    expect(await coordinator.acquireTone('group:group-team'), isTrue);
    final groupTone = File(
      '${directory.path}/NotificationToneLeases/'
      '8a1bd335a82c0a3727c776f654f2a1b37a5bbc43cf12a88fd8dbf293b1335203.lease',
    );
    expect(groupTone.existsSync(), isTrue);
    expect(
      double.parse(groupTone.readAsStringSync()),
      now.millisecondsSinceEpoch / 1000,
    );
  });

  test('honors claim and tone files written by the Swift NSE', () async {
    const identity = 'reaction:swift-first';
    final claim = File(
      '${directory.path}/NotificationServiceDedupe/'
      '${DurableNotificationToneLease.eventClaimFileName(identity)}',
    );
    await claim.parent.create(recursive: true);
    await claim.writeAsString('');

    final toneName = '${sha256.convert('peer-alice'.codeUnits)}.lease';
    final tone = File('${directory.path}/NotificationToneLeases/$toneName');
    await tone.parent.create(recursive: true);
    await tone.writeAsString((now.millisecondsSinceEpoch / 1000).toString());

    final coordinator = lease();
    expect(await coordinator.claimEvent(identity), isFalse);
    expect(await coordinator.acquireTone('peer-alice'), isFalse);
    now = now.add(const Duration(seconds: 31));
    expect(await coordinator.acquireTone('peer-alice'), isTrue);
  });

  test(
    'legacy tone timestamps in seconds and milliseconds remain compatible',
    () async {
      final toneDirectory = Directory(
        '${directory.path}/NotificationToneLeases',
      );
      await toneDirectory.create(recursive: true);
      final secondsFile = File(
        '${toneDirectory.path}/${sha256.convert('legacy-seconds'.codeUnits)}.lease',
      );
      final millisecondsFile = File(
        '${toneDirectory.path}/${sha256.convert('legacy-milliseconds'.codeUnits)}.lease',
      );
      await secondsFile.writeAsString(
        (now.millisecondsSinceEpoch / 1000).toString(),
      );
      await millisecondsFile.writeAsString(
        now.millisecondsSinceEpoch.toString(),
      );

      expect(await lease().reserveTone('legacy-seconds'), isNull);
      expect(await lease().reserveTone('legacy-milliseconds'), isNull);

      now = now.add(const Duration(seconds: 30));
      final secondsReservation = await lease().reserveTone('legacy-seconds');
      final millisecondsReservation = await lease().reserveTone(
        'legacy-milliseconds',
      );
      expect(secondsReservation, isNotNull);
      expect(millisecondsReservation, isNotNull);
      expect(await secondsReservation!.release(), isTrue);
      expect(await millisecondsReservation!.release(), isTrue);
    },
  );

  test('iOS default resolves the App Group root and persists it', () async {
    final support = await Directory.systemTemp.createTemp('reaction-support-');
    final appGroup = await Directory.systemTemp.createTemp(
      'reaction-app-group-',
    );
    addTearDown(() {
      if (support.existsSync()) support.deleteSync(recursive: true);
      if (appGroup.existsSync()) appGroup.deleteSync(recursive: true);
    });

    final coordinator = await DurableNotificationToneLease.openDefault(
      useIosAppGroup: true,
      appGroupPathChannel: AppGroupPathChannel(
        invoker: (_, _) async => appGroup.path,
      ),
      supportDirectory: () async => support,
    );

    expect(coordinator.directory.path, appGroup.path);
    expect(await coordinator.claimEvent('reaction:app-group'), isTrue);
    expect(
      Directory('${appGroup.path}/NotificationServiceDedupe').existsSync(),
      isTrue,
    );
    expect(
      File('${support.path}/mknoon_app_group_path').readAsStringSync(),
      appGroup.path,
    );
  });
}

Future<bool> _holdToneLockInFreshIsolate(String path) {
  return Isolate.run(() async {
    final root = Directory(path);
    return DurableNotificationToneLease(
      directory: root,
      now: () => DateTime.utc(2026, 7, 12, 10),
      beforeToneWrite: () async {
        await File('${root.path}/tone-holder-entered').create();
        final release = File('${root.path}/tone-holder-release');
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!await release.exists()) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('timed out waiting to release tone holder');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      },
    ).acquireTone('peer-cross-isolate');
  });
}

Future<bool> _contendForToneInFreshIsolate(String path) {
  return Isolate.run(() async {
    final root = Directory(path);
    await File('${root.path}/tone-contender-started').create();
    return DurableNotificationToneLease(
      directory: root,
      now: () => DateTime.utc(2026, 7, 12, 10),
    ).acquireTone('peer-cross-isolate');
  });
}

Future<bool> _holdToneReservationInFreshIsolate(String path) {
  return Isolate.run(() async {
    final root = Directory(path);
    final reservation = await DurableNotificationToneLease(
      directory: root,
      now: () => DateTime.utc(2026, 7, 12, 10),
      pendingToneReservationWait: const Duration(milliseconds: 50),
    ).reserveTone('peer-cross-isolate-reservation');
    if (reservation == null) return false;

    await File('${root.path}/reservation-holder-entered').create();
    final release = File('${root.path}/reservation-holder-release');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!await release.exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('timed out waiting to commit tone reservation');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return reservation.commit();
  });
}

Future<bool> _contendForToneReservationInFreshIsolate(String path) {
  return Isolate.run(() async {
    final root = Directory(path);
    await File('${root.path}/reservation-contender-started').create();
    final reservation = await DurableNotificationToneLease(
      directory: root,
      now: () => DateTime.utc(2026, 7, 12, 10),
      pendingToneReservationWait: const Duration(milliseconds: 50),
    ).reserveTone('peer-cross-isolate-reservation');
    if (reservation == null) return false;
    return reservation.commit();
  });
}

Future<String?> _claimMessageInFreshIsolate(String path, String label) {
  return Isolate.run(() async {
    final root = Directory(path);
    await File('${root.path}/claim-ready-$label').create();
    await _waitForFile(File('${root.path}/claim-start'));
    final claim =
        await DurableNotificationToneLease(
          directory: root,
          now: () => DateTime.utc(2026, 7, 12, 10),
          pendingClaimWait: Duration.zero,
          claimTokenFactory: () => label,
        ).claimMessageEvent(
          type: 'group_message',
          eventIdentity: 'cross-isolate-message',
        );
    return claim?.token;
  });
}

File _onlyPendingToneFile(Directory root) {
  final files = Directory('${root.path}/NotificationToneLeases')
      .listSync()
      .whereType<File>()
      .where(
        (file) => file.path.endsWith(
          DurableNotificationToneLease.tonePendingReservationFileSuffix,
        ),
      );
  return files.single;
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
