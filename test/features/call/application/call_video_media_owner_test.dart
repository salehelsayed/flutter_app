import 'dart:async';

import 'package:flutter_app/features/call/application/call_video_media_owner.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_test/flutter_test.dart';

final _call = CallId.parse('11111111-1111-4111-8111-111111111111');
final _otherCall = CallId.parse('22222222-2222-4222-8222-222222222222');

void main() {
  group('CallVideoMediaOwner U5', () {
    test('starts closed and owns only an explicitly granted capture', () async {
      final h = _harness();
      final video = _Video();
      final intent = h.owner.beginGrantedCapture(_call)!;

      expect(h.gateOpen, isFalse);
      expect(
        await h.owner.acquireCapture(intent, () => video.handle()),
        isTrue,
      );
      expect(h.owner.captureFor(intent)?.resource, same(video));
      expect(h.gateOpen, isFalse);
      expect(await h.owner.stopCapture(), isTrue);
      expect(video.successfulReleases, 1);
      expect(h.audioStops, 0);
      expect(h.peerCloses, 0);
    });

    test(
      'a delayed capture after terminal is released without adoption',
      () async {
        final h = _harness();
        final video = _Video();
        final held = Completer<CallVideoResource>();
        final intent = h.owner.beginGrantedCapture(_call)!;
        final acquiring = h.owner.acquireCapture(intent, () => held.future);

        await h.owner.close();
        held.complete(video.handle());
        final accepted = await acquiring;
        expect(accepted, isFalse);
        expect(video.successfulReleases, 1);
        expect(h.owner.captureFor(intent), isNull);
        expect(h.gateOpen, isFalse);
        expect(h.owner.beginGrantedCapture(_call), isNull);
      },
    );

    test(
      'off invalidates pending and previously granted capture intents',
      () async {
        final h = _harness();
        final video = _Video();
        final held = Completer<CallVideoResource>();
        final intent = h.owner.beginGrantedCapture(_call)!;
        var factoryCalls = 0;
        final acquiring = h.owner.acquireCapture(intent, () {
          factoryCalls++;
          return held.future;
        });

        await h.owner.stopCapture();
        held.complete(video.handle());
        final accepted = await acquiring;
        final reused = await h.owner.acquireCapture(intent, () {
          factoryCalls++;
          return video.handle();
        });
        expect(accepted, isFalse);
        expect(reused, isFalse);
        expect(factoryCalls, 1);
        expect(video.successfulReleases, 1);
        expect(h.gateOpen, isFalse);
      },
    );

    test('late capture cannot replace a newer granted capture', () async {
      final h = _harness();
      final first = _Video();
      final second = _Video();
      final held = Completer<CallVideoResource>();
      final oldIntent = h.owner.beginGrantedCapture(_call)!;
      final oldAcquire = h.owner.acquireCapture(oldIntent, () => held.future);
      final nextIntent = h.owner.beginGrantedCapture(_call)!;
      await h.owner.acquireCapture(nextIntent, () => second.handle());
      held.complete(first.handle());

      final oldAccepted = await oldAcquire;
      expect(oldAccepted, isFalse);
      expect(first.successfulReleases, 1);
      expect(second.releaseAttempts, 0);
      expect(h.owner.captureFor(nextIntent)?.resource, same(second));
      expect(h.owner.captureFor(oldIntent), isNull);
    });

    test(
      'gate closes before cleanup and old cleanup preserves replacement',
      () async {
        final h = _harness();
        final heldRelease = Completer<void>();
        final first = _Video(releaseGate: heldRelease);
        final second = _Video();
        final oldIntent = h.owner.beginGrantedCapture(_call)!;
        await h.owner.acquireCapture(oldIntent, () => first.handle());
        h.gateOpen = true;

        final stopping = h.owner.stopCapture();
        final gateClosedImmediately = !h.gateOpen;
        final nextIntent = h.owner.beginGrantedCapture(_call)!;
        await h.owner.acquireCapture(nextIntent, () => second.handle());
        heldRelease.complete();
        await stopping;
        await h.owner.retryCleanup();

        expect(gateClosedImmediately, isTrue);
        expect(h.owner.captureFor(nextIntent)?.resource, same(second));
        expect(first.successfulReleases, 1);
        expect(second.releaseAttempts, 0);
        expect(h.gateOpen, isFalse);
      },
    );

    test('concurrent acquisition of one intent uses one factory', () async {
      final h = _harness();
      final video = _Video();
      final held = Completer<CallVideoResource>();
      final intent = h.owner.beginGrantedCapture(_call)!;
      var factories = 0;
      Future<CallVideoResource> acquire() {
        factories++;
        return held.future;
      }

      final first = h.owner.acquireCapture(intent, acquire);
      final second = h.owner.acquireCapture(intent, acquire);
      held.complete(video.handle());
      expect(await Future.wait([first, second]), [true, true]);
      expect(factories, 1);
      await h.owner.close();
      expect(video.successfulReleases, 1);
    });

    test('stale renderer preparation never binds after close', () async {
      final h = _harness();
      final slot = _Slot();
      final renderer = _Renderer(slot);
      final held = Completer<CallVideoRendererBinding>();
      final intent = h.owner.beginRenderer(_call, 'remote')!;
      final preparing = h.owner.attachRenderer(intent, () => held.future);

      await h.owner.close();
      held.complete(renderer.binding);
      final attached = await preparing;
      expect(attached, isFalse);
      expect(renderer.attaches, 0);
      expect(renderer.detaches, 0);
      expect(renderer.video.successfulReleases, 1);
      expect(slot.current, isNull);
    });

    test(
      'late renderer preparation cannot overwrite its replacement',
      () async {
        final h = _harness();
        final slot = _Slot();
        final first = _Renderer(slot);
        final second = _Renderer(slot);
        final held = Completer<CallVideoRendererBinding>();
        final oldIntent = h.owner.beginRenderer(_call, 'remote')!;
        final oldPrepare = h.owner.attachRenderer(oldIntent, () => held.future);
        final nextIntent = h.owner.beginRenderer(_call, 'remote')!;
        await h.owner.attachRenderer(nextIntent, () => second.binding);
        held.complete(first.binding);
        final oldAttached = await oldPrepare;

        expect(oldAttached, isFalse);
        expect(first.attaches, 0);
        expect(first.video.successfulReleases, 1);
        expect(second.video.releaseAttempts, 0);
        expect(slot.current, same(second));
        expect(h.owner.rendererFor(nextIntent), same(second.binding));
        expect(h.owner.rendererFor(oldIntent), isNull);
      },
    );

    test('old renderer cleanup cannot clear a replacement binding', () async {
      final h = _harness();
      final slot = _Slot();
      final releaseGate = Completer<void>();
      final first = _Renderer(slot, releaseGate: releaseGate);
      final second = _Renderer(slot);
      final oldIntent = h.owner.beginRenderer(_call, 'remote')!;
      await h.owner.attachRenderer(oldIntent, () => first.binding);

      final detaching = h.owner.detachRenderer('remote');
      final nextIntent = h.owner.beginRenderer(_call, 'remote')!;
      await h.owner.attachRenderer(nextIntent, () => second.binding);
      releaseGate.complete();
      await detaching;
      await h.owner.retryCleanup();

      expect(first.detaches, 1);
      expect(first.video.successfulReleases, 1);
      expect(second.video.releaseAttempts, 0);
      expect(slot.current, same(second));
      expect(h.owner.rendererFor(nextIntent), same(second.binding));
    });

    test(
      'camera-off retires local preview but preserves remote rendering',
      () async {
        final h = _harness();
        final capture = _Video();
        final captureIntent = h.owner.beginGrantedCapture(_call)!;
        await h.owner.acquireCapture(captureIntent, () => capture.handle());
        final preview = _Renderer(_Slot());
        final remote = _Renderer(_Slot());
        final previewIntent = h.owner.beginRenderer(
          _call,
          'preview',
          captureIntent: captureIntent,
        )!;
        final remoteIntent = h.owner.beginRenderer(_call, 'remote')!;
        await h.owner.attachRenderer(previewIntent, () => preview.binding);
        await h.owner.attachRenderer(remoteIntent, () => remote.binding);
        h.gateOpen = true;

        await h.owner.stopCapture();
        expect(h.gateOpen, isFalse);
        expect(capture.successfulReleases, 1);
        expect(preview.detaches, 1);
        expect(preview.video.successfulReleases, 1);
        expect(remote.detaches, 0);
        expect(remote.video.releaseAttempts, 0);
        expect(h.owner.rendererFor(remoteIntent), same(remote.binding));
        expect(h.owner.rendererFor(previewIntent), isNull);
      },
    );

    test(
      'a preview prepared for retired capture cannot attach later',
      () async {
        final h = _harness();
        final video = _Video();
        final captureIntent = h.owner.beginGrantedCapture(_call)!;
        await h.owner.acquireCapture(captureIntent, () => video.handle());
        final renderer = _Renderer(_Slot());
        final held = Completer<CallVideoRendererBinding>();
        final rendererIntent = h.owner.beginRenderer(
          _call,
          'preview',
          captureIntent: captureIntent,
        )!;
        final preparing = h.owner.attachRenderer(
          rendererIntent,
          () => held.future,
        );

        await h.owner.stopCapture();
        held.complete(renderer.binding);
        expect(await preparing, isFalse);
        expect(renderer.attaches, 0);
        expect(renderer.video.successfulReleases, 1);
      },
    );

    test('foreign call intents and resources remain untouched', () async {
      final h = _harness();
      final foreignOwner = _harness(callId: _otherCall);
      final foreignIntent = foreignOwner.owner.beginGrantedCapture(_otherCall)!;
      var factories = 0;
      final foreignVideo = _Video(callId: _otherCall);

      expect(h.owner.beginGrantedCapture(_otherCall), isNull);
      expect(h.owner.beginRenderer(_otherCall, 'remote'), isNull);
      expect(
        await h.owner.acquireCapture(foreignIntent, () {
          factories++;
          return foreignVideo.handle();
        }),
        isFalse,
      );
      final ownIntent = h.owner.beginGrantedCapture(_call)!;
      expect(
        await h.owner.acquireCapture(ownIntent, () => foreignVideo.handle()),
        isFalse,
      );
      final foreignRenderer = _Renderer(_Slot(), callId: _otherCall);
      final rendererIntent = h.owner.beginRenderer(_call, 'remote')!;
      expect(
        await h.owner.attachRenderer(
          rendererIntent,
          () => foreignRenderer.binding,
        ),
        isFalse,
      );
      await h.owner.close();
      expect(factories, 0);
      expect(foreignVideo.releaseAttempts, 0);
      expect(foreignRenderer.attaches, 0);
      expect(foreignRenderer.detaches, 0);
      expect(foreignRenderer.video.releaseAttempts, 0);
      expect(h.audioStops, 0);
      expect(h.peerCloses, 0);
    });

    test(
      'late alias of a current resource does not release the replacement',
      () async {
        final h = _harness();
        final video = _Video();
        final held = Completer<CallVideoResource>();
        final oldIntent = h.owner.beginGrantedCapture(_call)!;
        final oldAcquire = h.owner.acquireCapture(oldIntent, () => held.future);
        final nextIntent = h.owner.beginGrantedCapture(_call)!;
        await h.owner.acquireCapture(nextIntent, () => video.handle());
        held.complete(video.handle());

        expect(await oldAcquire, isFalse);
        expect(video.releaseAttempts, 0);
        expect(h.owner.captureFor(nextIntent)?.resource, same(video));
      },
    );

    test(
      'cleanup failure is retained for an explicit successful retry',
      () async {
        final h = _harness();
        final video = _Video(failReleases: 1);
        final intent = h.owner.beginGrantedCapture(_call)!;
        await h.owner.acquireCapture(intent, () => video.handle());

        final stopped = await h.owner.stopCapture();
        final retained = h.owner.hasPendingCleanup;
        final attemptsBeforeRetry = video.releaseAttempts;
        final retried = await h.owner.retryCleanup();
        final stillPending = h.owner.hasPendingCleanup;
        await h.owner.retryCleanup();
        await h.owner.close();

        expect(stopped, isFalse);
        expect(retained, isTrue);
        expect(attemptsBeforeRetry, 1);
        expect(retried, isTrue);
        expect(stillPending, isFalse);
        expect(video.releaseAttempts, 2);
        expect(video.successfulReleases, 1);
        expect(h.audioStops, 0);
        expect(h.peerCloses, 0);
      },
    );

    test('late terminal cleanup failure stays retained for retry', () async {
      final h = _harness();
      final video = _Video(failReleases: 1);
      final held = Completer<CallVideoResource>();
      final intent = h.owner.beginGrantedCapture(_call)!;
      final acquiring = h.owner.acquireCapture(intent, () => held.future);

      await h.owner.close();
      held.complete(video.handle());
      final accepted = await acquiring;
      final retained = h.owner.hasPendingCleanup;
      final attemptsBeforeRetry = video.releaseAttempts;
      final retried = await h.owner.retryCleanup();

      expect(accepted, isFalse);
      expect(retained, isTrue);
      expect(attemptsBeforeRetry, 1);
      expect(retried, isTrue);
      expect(video.releaseAttempts, 2);
      expect(video.successfulReleases, 1);
      expect(h.owner.hasPendingCleanup, isFalse);
      expect(h.owner.beginGrantedCapture(_call), isNull);
      expect(h.gateOpen, isFalse);
    });

    test(
      'concurrent cleanup retries share one attempt and preserve a successor',
      () async {
        final h = _harness();
        final first = _Video(failReleases: 1);
        final second = _Video();
        final firstIntent = h.owner.beginGrantedCapture(_call)!;
        await h.owner.acquireCapture(firstIntent, () => first.handle());
        await h.owner.stopCapture();
        final nextIntent = h.owner.beginGrantedCapture(_call)!;
        await h.owner.acquireCapture(nextIntent, () => second.handle());
        first.releaseGate = Completer<void>();

        final retryOne = h.owner.retryCleanup();
        final retryTwo = h.owner.retryCleanup();
        await _turn();
        final attemptsWhileHeld = first.releaseAttempts;
        first.releaseGate!.complete();
        final results = await Future.wait([retryOne, retryTwo]);

        expect(attemptsWhileHeld, 2);
        expect(results, [true, true]);
        expect(first.successfulReleases, 1);
        expect(second.releaseAttempts, 0);
        expect(h.owner.captureFor(nextIntent)?.resource, same(second));
      },
    );

    test(
      'failed exact-binding detach can retry without clearing a successor',
      () async {
        final h = _harness();
        final slot = _Slot();
        final first = _Renderer(slot, failDetaches: 1);
        final second = _Renderer(slot);
        final firstIntent = h.owner.beginRenderer(_call, 'remote')!;
        await h.owner.attachRenderer(firstIntent, () => first.binding);
        final detached = await h.owner.detachRenderer('remote');
        final retained = h.owner.hasPendingCleanup;
        final nextIntent = h.owner.beginRenderer(_call, 'remote')!;
        await h.owner.attachRenderer(nextIntent, () => second.binding);

        final retried = await h.owner.retryCleanup();
        expect(detached, isFalse);
        expect(retained, isTrue);
        expect(retried, isTrue);
        expect(first.video.successfulReleases, 1);
        expect(first.detaches, 2);
        expect(second.video.releaseAttempts, 0);
        expect(slot.current, same(second));
        expect(h.owner.rendererFor(nextIntent), same(second.binding));
      },
    );

    test(
      'cleanup is idempotent across overlapping retire and terminal calls',
      () async {
        final h = _harness();
        final releaseGate = Completer<void>();
        final video = _Video(releaseGate: releaseGate);
        final intent = h.owner.beginGrantedCapture(_call)!;
        await h.owner.acquireCapture(intent, () => video.handle());
        final first = h.owner.retireVideo();
        final second = h.owner.close();
        await _turn();
        final attemptsWhileHeld = video.releaseAttempts;
        releaseGate.complete();
        await Future.wait([first, second]);
        await h.owner.close();
        await h.owner.retryCleanup();

        expect(attemptsWhileHeld, 1);
        expect(video.successfulReleases, 1);
        expect(h.gateOpen, isFalse);
        expect(h.owner.beginGrantedCapture(_call), isNull);
      },
    );

    test(
      'optional prepare and acquisition failures preserve audio and the call',
      () async {
        final h = _harness();
        final intent = h.owner.beginGrantedCapture(_call)!;
        final captured = await h.owner.acquireCapture(
          intent,
          () => throw StateError('private camera error'),
        );
        final rendererIntent = h.owner.beginRenderer(_call, 'remote')!;
        final rendered = await h.owner.attachRenderer(
          rendererIntent,
          () => throw StateError('private renderer error'),
        );

        expect(captured, isFalse);
        expect(rendered, isFalse);
        expect(h.owner.captureFor(intent), isNull);
        expect(h.owner.rendererFor(rendererIntent), isNull);
        expect(h.gateOpen, isFalse);
        expect(h.audioStops, 0);
        expect(h.peerCloses, 0);
        expect(h.owner.beginGrantedCapture(_call), isNotNull);
      },
    );

    test(
      'partial renderer bind failure still detaches and releases its handle',
      () async {
        final h = _harness();
        final slot = _Slot();
        final renderer = _Renderer(slot, failAttach: true);
        final intent = h.owner.beginRenderer(_call, 'remote')!;

        expect(
          await h.owner.attachRenderer(intent, () => renderer.binding),
          isFalse,
        );
        expect(renderer.attaches, 1);
        expect(renderer.detaches, 1);
        expect(renderer.video.successfulReleases, 1);
        expect(slot.current, isNull);
        expect(h.owner.rendererFor(intent), isNull);
        expect(h.audioStops, 0);
        expect(h.peerCloses, 0);
      },
    );

    test(
      'abort retires video without preventing a fresh granted intent',
      () async {
        final h = _harness();
        final first = _Video();
        final firstIntent = h.owner.beginGrantedCapture(_call)!;
        await h.owner.acquireCapture(firstIntent, () => first.handle());
        final remote = _Renderer(_Slot());
        final remoteIntent = h.owner.beginRenderer(_call, 'remote')!;
        await h.owner.attachRenderer(remoteIntent, () => remote.binding);
        h.gateOpen = true;

        await h.owner.retireVideo();
        final oldAccepted = await h.owner.acquireCapture(
          firstIntent,
          () => first.handle(),
        );
        final second = _Video();
        final nextIntent = h.owner.beginGrantedCapture(_call)!;
        final nextAccepted = await h.owner.acquireCapture(
          nextIntent,
          () => second.handle(),
        );

        expect(oldAccepted, isFalse);
        expect(nextAccepted, isTrue);
        expect(first.successfulReleases, 1);
        expect(remote.video.successfulReleases, 1);
        expect(h.owner.rendererFor(remoteIntent), isNull);
        expect(h.gateOpen, isFalse);
        expect(h.audioStops, 0);
        expect(h.peerCloses, 0);
      },
    );
  });
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

_Harness _harness({CallId? callId}) {
  final harness = _Harness(callId ?? _call);
  addTearDown(() async {
    await harness.owner.close();
    await harness.owner.retryCleanup();
  });
  return harness;
}

final class _Harness {
  _Harness(CallId callId) {
    owner = CallVideoMediaOwner(
      callId: callId,
      closeLocalVideoSendGate: () {
        gateOpen = false;
      },
    );
  }

  late final CallVideoMediaOwner owner;
  bool gateOpen = true;
  int audioStops = 0;
  int peerCloses = 0;
}

final class _Video {
  _Video({CallId? callId, this.failReleases = 0, this.releaseGate})
    : callId = callId ?? _call;

  final CallId callId;
  int failReleases;
  Completer<void>? releaseGate;
  int releaseAttempts = 0;
  int successfulReleases = 0;

  CallVideoResource handle() => CallVideoResource(
    callId: callId,
    resource: this,
    dispose: () async {
      releaseAttempts++;
      if (failReleases > 0) {
        failReleases--;
        throw StateError('private release error');
      }
      if (releaseGate != null) await releaseGate!.future;
      successfulReleases++;
    },
  );
}

final class _Slot {
  _Renderer? current;
}

final class _Renderer {
  _Renderer(
    this.slot, {
    CallId? callId,
    Completer<void>? releaseGate,
    this.failDetaches = 0,
    this.failAttach = false,
  }) : video = _Video(callId: callId, releaseGate: releaseGate) {
    binding = CallVideoRendererBinding(
      resource: video.handle(),
      attach: () {
        attaches++;
        slot.current = this;
        if (failAttach) throw StateError('private bind error');
      },
      detach: () {
        detaches++;
        if (failDetaches > 0) {
          failDetaches--;
          throw StateError('private detach error');
        }
        if (identical(slot.current, this)) slot.current = null;
      },
    );
  }

  final _Slot slot;
  final _Video video;
  final bool failAttach;
  int failDetaches;
  int attaches = 0;
  int detaches = 0;
  late final CallVideoRendererBinding binding;
}
