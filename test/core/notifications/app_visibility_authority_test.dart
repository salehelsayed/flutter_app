import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'TC-371-02a lifecycle generation and projection failure are fail-notify',
    () async {
      const channel = MethodChannel(appVisibilityPlatformChannelName);
      final methodCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methodCalls.add(call);
            if (call.method == appVisibilityReadSnapshotMethod) {
              expect(call.arguments, isNull);
              return <String, Object?>{
                'snapshot': _snapshot(
                  revision: 1,
                  generation: 1,
                  digest: null,
                ).toJson(),
                'currentMonotonicMs': 1001,
                'currentBootSession': 'test:boot-1',
              };
            }
            if (call.method == appVisibilityPublishVisibleConversationMethod) {
              expect(call.arguments, <String, Object?>{
                'visibleConversationDigest': _directA.digest,
                'lifecycleGeneration': 1,
              });
              return <String, Object?>{
                'committed': true,
                'snapshot': _snapshot(
                  revision: 2,
                  generation: 1,
                  digest: _directA.digest,
                  updatedMonotonicMs: 1002,
                ).toJson(),
                'currentMonotonicMs': 1002,
                'currentBootSession': 'test:boot-1',
              };
            }
            throw MissingPluginException(call.method);
          });
      try {
        final channelBridge = MethodChannelAppVisibilityPlatformBridge(
          channel: channel,
        );
        expect((await channelBridge.readSnapshot())?.snapshot.revision, 1);
        final channelWrite = await channelBridge.publishVisibleConversation(
          visibleConversationDigest: _directA.digest,
          lifecycleGeneration: 1,
        );
        expect(channelWrite?.committed, isTrue);
        expect(
          channelWrite?.snapshot?.visibleConversationDigest,
          _directA.digest,
        );
        expect(methodCalls.map((call) => call.method), <String>[
          appVisibilityReadSnapshotMethod,
          appVisibilityPublishVisibleConversationMethod,
        ]);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }

      final bridge = _FakeAppVisibilityPlatformBridge();
      final authority = AppVisibilityAuthority(platformBridge: bridge);
      expect(await authority.synchronize(), isTrue);
      expect(authority.lifecycleGeneration, 1);
      expect(await authority.publishVisibleConversation(_directA), isTrue);
      expect(await authority.refreshVisibleConversation(), isTrue);
      expect(bridge.publishCalls.last.digest, _directA.digest);

      final exact = await authority.evaluate(_directA);
      expect(exact.isForegroundActive, isTrue);
      expect(exact.maySuppress, isTrue);
      final other = await authority.evaluate(_directB);
      expect(other.isForegroundActive, isTrue);
      expect(other.maySuppress, isFalse);

      // Bridge operations are FIFO. A later route cannot overtake a blocked
      // clear and leave the wrong top route persisted.
      final blockedClear = bridge.blockNextPublish();
      final clear = authority.clearVisibleConversation();
      await blockedClear.started.future;
      final publishB = authority.publishVisibleConversation(_directB);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.publishCalls.last.digest, isNull);
      final callCountWhileBlocked = bridge.publishCalls.length;
      blockedClear.release.complete();
      expect(await clear, isTrue);
      expect(await publishB, isTrue);
      expect(bridge.publishCalls, hasLength(callCountWhileBlocked + 1));
      expect(bridge.publishCalls.last.digest, _directB.digest);

      // A read/I/O failure immediately drops the cached active generation.
      bridge.throwNextRead = true;
      expect(
        await authority.evaluate(_directB),
        AppVisibilityEvaluation.failNotify,
      );
      expect(authority.lifecycleGeneration, isNull);
      bridge.transition(AppVisibilityLifecycle.foregroundActive);
      expect(await authority.synchronize(), isTrue);

      // A committed response with mismatched readback is not success and no
      // cached active value survives as a fallback.
      bridge.mismatchNextWriteReadback = true;
      expect(await authority.publishVisibleConversation(_directA), isFalse);
      expect(authority.lifecycleGeneration, isNull);
      expect(
        await authority.evaluate(_directA),
        AppVisibilityEvaluation.failNotify,
      );

      // Re-enter active state, then hold a route write while native pause wins.
      bridge.transition(AppVisibilityLifecycle.foregroundActive);
      expect(await authority.synchronize(), isTrue);
      final blockedRoute = bridge.blockNextPublish();
      final staleRoute = authority.publishVisibleConversation(_directA);
      await blockedRoute.started.future;
      authority.invalidateSynchronously();
      bridge.transition(AppVisibilityLifecycle.background);
      blockedRoute.release.complete();
      expect(await staleRoute, isFalse);
      final afterPause = await authority.evaluate(_directA);
      expect(afterPause.isForegroundActive, isFalse);
      expect(afterPause.maySuppress, isFalse);
      expect(afterPause.lifecycle, AppVisibilityLifecycle.background);
      expect(afterPause.hasExactSnapshotMetadata, isTrue);
      expect(bridge.snapshot.lifecycle, AppVisibilityLifecycle.background);
      expect(bridge.snapshot.visibleConversationDigest, isNull);

      // Queued work captured before synchronous invalidation never reaches the
      // bridge, and dispose preserves the same fail-notify behavior.
      final callsBeforeDispose = bridge.publishCalls.length;
      authority.dispose();
      expect(await authority.publishVisibleConversation(_directB), isFalse);
      expect(bridge.publishCalls, hasLength(callsBeforeDispose));
      expect(
        await authority.evaluate(_directB),
        AppVisibilityEvaluation.failNotify,
      );
    },
  );
}

final AppVisibilityConversationIdentity _directA =
    AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.direct,
      value: 'peer-A',
    )!;
final AppVisibilityConversationIdentity _directB =
    AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.direct,
      value: 'peer-B',
    )!;

AppVisibilitySnapshotV1 _snapshot({
  required int revision,
  required int generation,
  required String? digest,
  int updatedMonotonicMs = 1000,
  AppVisibilityLifecycle lifecycle = AppVisibilityLifecycle.foregroundActive,
}) => AppVisibilitySnapshotV1(
  schemaVersion: appVisibilitySnapshotSchemaVersion,
  revision: revision,
  lifecycleGeneration: generation,
  lifecycle: lifecycle,
  visibleConversationDigest: digest,
  updatedMonotonicMs: updatedMonotonicMs,
  bootSession: 'test:boot-1',
);

final class _PublishCall {
  const _PublishCall({required this.digest, required this.generation});

  final String? digest;
  final int generation;
}

final class _BlockedPublish {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
}

final class _FakeAppVisibilityPlatformBridge
    implements AppVisibilityPlatformBridge {
  AppVisibilitySnapshotV1 snapshot = _snapshot(
    revision: 1,
    generation: 1,
    digest: null,
  );
  int nowMs = 1001;
  bool throwNextRead = false;
  bool mismatchNextWriteReadback = false;
  _BlockedPublish? _blockedPublish;
  final List<_PublishCall> publishCalls = <_PublishCall>[];

  _BlockedPublish blockNextPublish() {
    final blocked = _BlockedPublish();
    _blockedPublish = blocked;
    return blocked;
  }

  void transition(AppVisibilityLifecycle lifecycle) {
    nowMs++;
    snapshot = _snapshot(
      revision: snapshot.revision + 1,
      generation: snapshot.lifecycleGeneration + 1,
      digest: null,
      lifecycle: lifecycle,
      updatedMonotonicMs: nowMs,
    );
  }

  @override
  Future<AppVisibilityPlatformRead?> readSnapshot() async {
    if (throwNextRead) {
      throwNextRead = false;
      throw PlatformException(code: 'read_failed');
    }
    return AppVisibilityPlatformRead(
      snapshot: snapshot,
      currentMonotonicMs: nowMs,
      currentBootSession: 'test:boot-1',
    );
  }

  @override
  Future<AppVisibilityPlatformWrite?> publishVisibleConversation({
    required String? visibleConversationDigest,
    required int lifecycleGeneration,
  }) async {
    publishCalls.add(
      _PublishCall(
        digest: visibleConversationDigest,
        generation: lifecycleGeneration,
      ),
    );
    final blocked = _blockedPublish;
    if (blocked != null) {
      _blockedPublish = null;
      blocked.started.complete();
      await blocked.release.future;
    }
    if (snapshot.lifecycle != AppVisibilityLifecycle.foregroundActive ||
        snapshot.lifecycleGeneration != lifecycleGeneration) {
      return AppVisibilityPlatformWrite(
        committed: false,
        snapshot: snapshot,
        currentMonotonicMs: nowMs,
        currentBootSession: 'test:boot-1',
      );
    }
    nowMs++;
    snapshot = _snapshot(
      revision: snapshot.revision + 1,
      generation: snapshot.lifecycleGeneration,
      digest: visibleConversationDigest,
      updatedMonotonicMs: nowMs,
    );
    final readback = mismatchNextWriteReadback
        ? _snapshot(
            revision: snapshot.revision,
            generation: snapshot.lifecycleGeneration,
            digest: visibleConversationDigest == _directA.digest
                ? _directB.digest
                : _directA.digest,
            updatedMonotonicMs: nowMs,
          )
        : snapshot;
    mismatchNextWriteReadback = false;
    return AppVisibilityPlatformWrite(
      committed: true,
      snapshot: readback,
      currentMonotonicMs: nowMs,
      currentBootSession: 'test:boot-1',
    );
  }
}
