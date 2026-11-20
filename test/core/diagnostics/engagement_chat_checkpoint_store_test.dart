import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/core/diagnostics/engagement_chat_checkpoint_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _wait = Duration(seconds: 2);
const _signalWait = Duration(seconds: 1);

Future<T> _within<T>(Future<T> future) => future.timeout(_wait);

final class _Barrier {
  final entered = Completer<void>();
  final released = Completer<void>();

  Future<void> hold() {
    if (!entered.isCompleted) {
      entered.complete();
    }
    return released.future.timeout(_wait);
  }

  void open() {
    if (!released.isCompleted) {
      released.complete();
    }
  }
}

Future<void> _entered(_Barrier barrier) async {
  final arrived = await barrier.entered.future
      .then((_) => true)
      .timeout(_signalWait, onTimeout: () => false);
  expect(arrived, isTrue, reason: 'the owned filesystem operation must start');
}

void main() {
  late Directory directory;
  final stores = <EngagementChatCheckpointStore>[];
  final barriers = <_Barrier>[];

  Future<EngagementChatCheckpointStore> open({
    String? path,
    EngagementChatBeforeCommit? beforeCommit,
    EngagementChatRename? rename,
  }) async {
    final store = await _within(
      EngagementChatCheckpointStore.open(
        path ?? directory.path,
        beforeCommit: beforeCommit,
        rename: rename,
      ),
    );
    stores.add(store);
    return store;
  }

  _Barrier barrier() {
    final result = _Barrier();
    barriers.add(result);
    return result;
  }

  setUp(() async {
    directory = await _within(
      Directory.systemTemp.createTemp('engagement-chat-checkpoint-'),
    );
  });

  tearDown(() async {
    for (final gate in barriers) {
      gate.open();
    }
    for (final store in stores) {
      await _within(store.close());
    }
    stores.clear();
    barriers.clear();
    if (await _within(directory.exists())) {
      await _within(directory.delete(recursive: true));
    }
  });

  test('E2S-001 private checkpoint accepts its byte limit and rejects overflow', () async {
    final store = await open();
    final boundary = Uint8List(256 * 1024);
    boundary[0] = 17;
    boundary[boundary.length - 1] = 29;
    expect(
      await _within(store.replace(boundary, isCurrent: () => true)),
      isTrue,
    );
    expect(
      await _within(store.read(isCurrent: () => true)),
      orderedEquals(boundary),
    );
    expect(
      await _within(
        store.replace(Uint8List(256 * 1024 + 1), isCurrent: () => true),
      ),
      isFalse,
    );
    expect(
      await _within(File(store.checkpointPath).readAsBytes()),
      orderedEquals(boundary),
    );
    expect(await _within(store.clear(isCurrent: () => true)), isTrue);
    expect(await _within(File(store.checkpointPath).exists()), isFalse);
  });

  test('E2S-002 stale prepared temp cannot commit or delete foreign files', () async {
    final gate = barrier();
    String? temporaryPath;
    var current = true;
    final store = await open(
      beforeCommit: (path) async {
        temporaryPath = path;
        await _within(gate.hold());
      },
    );
    final checkpoint = File(store.checkpointPath);
    final foreign = File('${store.checkpointPath}.foreign.tmp');
    await _within(checkpoint.writeAsBytes([11], flush: true));
    await _within(foreign.writeAsBytes([97], flush: true));
    final replacing = store.replace(
      Uint8List.fromList([22]),
      isCurrent: () => current,
    );
    await _entered(gate);
    expect(temporaryPath, isNotNull);
    expect(await _within(File(temporaryPath!).exists()), isTrue);
    current = false;
    gate.open();
    expect(await _within(replacing), isFalse);
    expect(await _within(checkpoint.readAsBytes()), orderedEquals([11]));
    expect(await _within(foreign.readAsBytes()), orderedEquals([97]));
    expect(await _within(File(temporaryPath!).exists()), isFalse);
    final paths = await _within(
      directory.list().asyncMap((entry) => entry.resolveSymbolicLinks()).toList(),
    );
    expect(paths, unorderedEquals([checkpoint.path, foreign.path]));
  });

  test('E2S-003 issued rename stays fenced across close and successor open', () async {
    final gate = barrier();
    var oldCurrent = true;
    final oldStore = await open(
      rename: (temporaryPath, checkpointPath) async {
        await _within(gate.hold());
        await _within(File(temporaryPath).rename(checkpointPath));
      },
    );
    final oldWrite = oldStore.replace(
      Uint8List.fromList([31]),
      isCurrent: () => oldCurrent,
    );
    await _entered(gate);
    oldCurrent = false;
    final closing = oldStore.close();
    final opening = open(path: '${directory.path}/.');
    var successorFinished = false;
    final successorWrite = opening
        .then(
          (store) => store.replace(
            Uint8List.fromList([42]),
            isCurrent: () => true,
          ),
        )
        .then((result) {
          successorFinished = true;
          return result;
        });
    await _within(Future<void>.value());
    expect(successorFinished, isFalse);
    // Both open and replace may wait for the already issued physical rename.
    gate.open();
    expect(await _within(oldWrite), isFalse);
    await _within(closing);
    expect(await _within(successorWrite), isTrue);
    final successor = await _within(opening);
    expect(successor.checkpointPath, oldStore.checkpointPath);
    expect(
      await _within(File(successor.checkpointPath).readAsBytes()),
      orderedEquals([42]),
    );
  });

  test('E2S-004 failed rename preserves the previous complete checkpoint', () async {
    var renameCalls = 0;
    final store = await open(
      rename: (_, _) async {
        renameCalls++;
        throw const FileSystemException('controlled rename failure');
      },
    );
    final checkpoint = File(store.checkpointPath);
    await _within(checkpoint.writeAsBytes([51], flush: true));
    expect(
      await _within(
        store.replace(Uint8List.fromList([62]), isCurrent: () => true),
      ),
      isFalse,
    );
    expect(renameCalls, 1);
    expect(await _within(checkpoint.readAsBytes()), orderedEquals([51]));
    final paths = await _within(
      directory.list().asyncMap((entry) => entry.resolveSymbolicLinks()).toList(),
    );
    expect(paths, [checkpoint.path]);
  });

  test('E2S-005 stale guards cannot read replace or clear private data', () async {
    final store = await open();
    final checkpoint = File(store.checkpointPath);
    await _within(checkpoint.writeAsBytes([73], flush: true));
    expect(await _within(store.read(isCurrent: () => false)), isNull);
    expect(
      await _within(
        store.replace(Uint8List.fromList([84]), isCurrent: () => false),
      ),
      isFalse,
    );
    expect(await _within(store.clear(isCurrent: () => false)), isFalse);
    expect(await _within(checkpoint.readAsBytes()), orderedEquals([73]));
  });

  test('E2S-006 queued replacements snapshot caller bytes before awaiting', () async {
    final gate = barrier();
    final first = await open(
      rename: (temporaryPath, checkpointPath) async {
        await _within(gate.hold());
        await _within(File(temporaryPath).rename(checkpointPath));
      },
    );
    final second = await open();
    final firstWrite = first.replace(
      Uint8List.fromList([91]),
      isCurrent: () => true,
    );
    await _entered(gate);
    final mutable = Uint8List.fromList([102]);
    final secondWrite = second.replace(mutable, isCurrent: () => true);
    mutable[0] = 113;
    gate.open();
    expect(await _within(firstWrite), isTrue);
    expect(await _within(secondWrite), isTrue);
    expect(
      await _within(File(second.checkpointPath).readAsBytes()),
      orderedEquals([102]),
    );
  });
}
