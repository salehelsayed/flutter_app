import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/app/bootstrap/active_identity_reporter_bootstrap.dart';
import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/core/diagnostics/engagement_chat_checkpoint_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/groups/application/b6_daily_activity_test_support.dart';

const _budget = Duration(seconds: 3);
Future<T> _bounded<T>(Future<T> future) => future.timeout(_budget);

Future<void> _arm(
  ActiveIdentityReporter reporter,
  B6ActivityBridge bridge,
) async {
  bridge.activityAnswer = (request, revision) async {
    if (request['op'] != 'weeklyProjection' && request['op'] != 'markWeekly') {
      return B6ActivityBridge.reply(request, revision);
    }
    return jsonEncode({
      'ok': true,
      'data': {
        'revision': revision,
        'consentEpoch': request['consentEpoch'],
        if (request['op'] == 'markWeekly') 'accepted': true,
        if (request['op'] == 'weeklyProjection')
          'weekly': {
            'week': '2026-W47',
            'startUnixMillis': b15GroupWeekStart,
            'endUnixMillis': b15GroupWeekStart + 7 * 24 * 60 * 60 * 1000,
            'kinds': <String>[],
            'acknowledged': <Object>[],
          },
      },
    });
  };
  reporter.attachBridge(bridge);
  reporter.observeIdentity(
    accountPeerId: 'peer-1',
    rootPrivateKeyBase64: base64Encode(List<int>.filled(64, 17)),
    profileBinding: b6Binding,
  );
  await _bounded(reporter.observeConsent((enabled: true, consentEpoch: 7)));
  await _bounded(reporter.flush());
  expect(bridge.marks, isEmpty);
  expect(bridge.requests.where((r) => r['op'] == 'markWeekly'), isEmpty);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final stores = <EngagementChatCheckpointStore>[];
  final disposals = <Future<void> Function()>[];
  final releases = <void Function()>[];

  setUp(() async {
    stores.clear();
    disposals.clear();
    releases.clear();
    directory = await _bounded(
      Directory.systemTemp.createTemp('b15-bootstrap-'),
    );
  });

  tearDown(() async {
    for (final release in releases) {
      release();
    }
    for (final dispose in disposals.reversed) {
      await _bounded(dispose());
    }
    for (final store in stores.reversed) {
      await _bounded(store.close());
    }
    await _bounded(directory.delete(recursive: true));
  });

  Future<EngagementChatCheckpointStore> open({
    String? path,
    EngagementChatBeforeCommit? beforeCommit,
    EngagementChatRename? rename,
  }) async {
    final store = await _bounded(
      EngagementChatCheckpointStore.open(
        path ?? '${directory.path}/active_identity/group',
        beforeCommit: beforeCommit,
        rename: rename,
      ),
    );
    stores.add(store);
    return store;
  }

  Future<({ActiveIdentityReporter reporter, Future<void> Function() dispose})>
  ready({
    required String documentsPath,
    Future<EngagementChatCheckpointStore> Function(String)?
    openGroupWitnessStore,
    int Function()? groupNowMilliseconds,
  }) async {
    final owner = prepareProductionActiveIdentityReporter(
      documentsPath: documentsPath,
      openGroupWitnessStore: openGroupWitnessStore,
      groupNowMilliseconds: groupNowMilliseconds,
    );
    disposals.add(owner.dispose);
    final reporter = await _bounded(owner.reporter);
    expect(reporter, isNotNull);
    return (reporter: reporter!, dispose: owner.dispose);
  }

  test(
    'B15BS-001 production owner supplies its private group checkpoint',
    () async {
      String? openedPath;
      final owner = await _bounded(
        ready(
          documentsPath: directory.path,
          openGroupWitnessStore: (path) {
            openedPath = path;
            return open(path: path);
          },
          groupNowMilliseconds: () => b15GroupWeekStart + 10000,
        ),
      );
      final bridge = B6ActivityBridge();
      await _bounded(_arm(owner.reporter, bridge));
      final capture = owner.reporter.captureOwner(
        expectedAccountPeerId: 'peer-1',
      )!;
      owner.reporter.groupPostCommittedCaptured(
        capture,
        groupId: 'private-group',
      );
      owner.reporter.groupOtherPostVisibleCaptured(
        capture,
        groupId: 'private-group',
        authorAccountPeerId: 'peer-other',
        postOccurredAtUnixMillis: b15GroupWeekStart + 1000,
      );
      await _bounded(owner.reporter.flush());
      expect(
        bridge.requests.where((r) => r['op'] == 'markWeekly'),
        hasLength(1),
      );
      expect(openedPath, '${directory.path}/active_identity/group');
      expect(bridge.marks, isEmpty);
      expect(jsonEncode(bridge.requests), isNot(contains('private-group')));
    },
  );

  test(
    'B15BS-002 overlapping disposal joins one owned writer completion',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      releases.add(() {
        if (!release.isCompleted) release.complete();
      });
      final store = await _bounded(
        open(
          beforeCommit: (_) async {
            if (!entered.isCompleted) entered.complete();
            await _bounded(release.future);
          },
        ),
      );
      final owner = await _bounded(
        ready(
          documentsPath: directory.path,
          openGroupWitnessStore: (_) async => store,
          groupNowMilliseconds: () => b15GroupWeekStart + 10000,
        ),
      );
      await _bounded(_arm(owner.reporter, B6ActivityBridge()));
      final writing = store.replace(
        Uint8List.fromList([1, 2]),
        isCurrent: () => true,
      );
      await _bounded(entered.future);
      var firstFinished = false;
      var secondFinished = false;
      final first = owner.dispose().whenComplete(() => firstFinished = true);
      final second = owner.dispose().whenComplete(() => secondFinished = true);
      expect(
        owner.reporter.captureOwner(expectedAccountPeerId: 'peer-1'),
        isNull,
      );
      await _bounded(Future<void>.delayed(Duration.zero));
      expect(firstFinished || secondFinished, isFalse);
      release.complete();
      await _bounded(writing);
      await _bounded(Future.wait([first, second]));
      expect(
        await _bounded(store.replace(Uint8List(1), isCurrent: () => true)),
        isFalse,
      );
      expect(
        owner.reporter.captureOwner(expectedAccountPeerId: 'peer-1'),
        isNull,
      );
    },
  );

  test('B15BS-005 bounded disposal preserves an issued writer fence', () async {
    final issued = Completer<void>();
    final release = Completer<void>();
    releases.add(() {
      if (!release.isCompleted) release.complete();
    });
    final store = await _bounded(
      open(
        rename: (temporary, checkpoint) async {
          if (!issued.isCompleted) issued.complete();
          await _bounded(release.future);
          await _bounded(File(temporary).rename(checkpoint));
        },
      ),
    );
    final owner = await _bounded(
      ready(
        documentsPath: directory.path,
        openGroupWitnessStore: (_) async => store,
        groupNowMilliseconds: () => b15GroupWeekStart + 10000,
      ),
    );
    await _bounded(_arm(owner.reporter, B6ActivityBridge()));
    final writing = store.replace(
      Uint8List.fromList([1]),
      isCurrent: () => true,
    );
    await _bounded(issued.future);
    var disposed = false;
    final disposal = owner.dispose().whenComplete(() => disposed = true);
    await _bounded(Future<void>.delayed(Duration.zero));
    expect(disposed, isFalse);
    await _bounded(disposal);
    final successor = await _bounded(open());
    var successorFinished = false;
    final successorWrite = successor
        .replace(Uint8List.fromList([2]), isCurrent: () => true)
        .whenComplete(() => successorFinished = true);
    await _bounded(Future<void>.delayed(Duration.zero));
    expect(successorFinished, isFalse);
    release.complete();
    await _bounded(writing);
    expect(await _bounded(successorWrite), isTrue);
    expect(await _bounded(File(successor.checkpointPath).readAsBytes()), [2]);
  });

  test('B15BS-003 failed optional open preserves daily reporting', () async {
    final owner = await _bounded(
      ready(
        documentsPath: directory.path,
        openGroupWitnessStore: (_) async =>
            throw StateError('fixture storage unavailable'),
      ),
    );
    final bridge = B6ActivityBridge();
    await _bounded(_arm(owner.reporter, bridge));
    final capture = owner.reporter.captureOwner(
      expectedAccountPeerId: 'peer-1',
    )!;
    owner.reporter.markCaptured(capture);
    await _bounded(owner.reporter.flush());
    expect(bridge.marks, hasLength(1));
    expect(bridge.requests.where((r) => r['op'] == 'markWeekly'), isEmpty);
    expect(
      bridge.requests.where((r) => r['op'] == 'configure').last['statePath'],
      '${directory.path}/active_identity/state.json',
    );
  });

  test('B15BS-004 late optional open is closed after owner disposal', () async {
    final store = await _bounded(open());
    final lateOpen = Completer<EngagementChatCheckpointStore>();
    releases.add(() {
      if (!lateOpen.isCompleted) lateOpen.complete(store);
    });
    final owner = await _bounded(
      ready(
        documentsPath: directory.path,
        openGroupWitnessStore: (_) => lateOpen.future,
      ),
    );
    await _bounded(owner.dispose());
    lateOpen.complete(store);
    await _bounded(Future<void>.delayed(Duration.zero));
    expect(
      await _bounded(store.replace(Uint8List(1), isCurrent: () => true)),
      isFalse,
    );
  });

  test(
    'B15BS-006 retirement before readiness never publishes a reporter',
    () async {
      final store = await _bounded(open());
      final lateOpen = Completer<EngagementChatCheckpointStore>();
      releases.add(() {
        if (!lateOpen.isCompleted) lateOpen.complete(store);
      });
      final owner = prepareProductionActiveIdentityReporter(
        documentsPath: directory.path,
        openGroupWitnessStore: (_) => lateOpen.future,
      );
      disposals.add(owner.dispose);
      final disposing = owner.dispose();
      lateOpen.complete(store);
      expect(await _bounded(owner.reporter), isNull);
      await _bounded(disposing);
      expect(
        await _bounded(store.replace(Uint8List(1), isCurrent: () => true)),
        isFalse,
      );
    },
  );
}
