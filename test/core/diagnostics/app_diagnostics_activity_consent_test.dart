import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

const _limit = Duration(seconds: 2);
const _privateError = 'b294-consent-observer-account-root-signature-sentinel';
Future<T> _bounded<T>(Future<T> future) => future.timeout(_limit);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await _bounded(Directory.systemTemp.createTemp('b294-consent-'));
  });

  tearDown(() async {
    await _bounded(AppDiagnostics.instance.setLocalConsentObserver(null));
    await _bounded(AppDiagnostics.instance.dispose());
    await _bounded(directory.delete(recursive: true));
  });

  Future<AppDiagnostics> install({
    LocalConsentObserver? observer,
    AppDiagnosticPersist? persist,
    Future<bool> Function()? networkAllowed,
  }) => _bounded(AppDiagnostics.installForTesting(
    directory: directory,
    useNative: false,
    enabled: null,
    now: () => DateTime.utc(2026, 11, 15, 12),
    consentObserver: observer,
    persist: persist,
    networkAllowed: networkAllowed,
  ));

  test('before-init registration publishes only final default-ON consent', () async {
    final seen = <LocalDiagnosticConsent?>[];
    final diagnostics = await install(observer: (consent) async => seen.add(consent));
    expect(diagnostics.enabled, isTrue,
        reason: 'Positive existing beta default-ON control must succeed first');
    expect((await _bounded(diagnostics.status()))['storageHealthy'], isTrue);
    expect(seen, hasLength(1));
    expect(seen.single, isNotNull);
    expect(seen.single!.enabled, isTrue);
    expect(seen.single!.consentEpoch, greaterThan(0));
    expect(seen, isNot(contains(isNull)), reason: 'No synthetic pre-init retirement');
  });

  test('after-init registration immediately replays valid current consent', () async {
    final diagnostics = await install();
    expect(diagnostics.enabled, isTrue);
    final seen = <LocalDiagnosticConsent?>[];
    await _bounded(diagnostics.setLocalConsentObserver((consent) async => seen.add(consent)));
    expect(seen, hasLength(1));
    expect(seen.single!.enabled, isTrue);
    expect(seen.single!.consentEpoch, greaterThan(0));
  });

  test('OFF notifies before first persistence await and awaits disable attempt', () async {
    final snapshots = <LocalDiagnosticConsent?>[];
    final writes = <String>[];
    final observerRelease = Completer<void>();
    final persistRelease = Completer<void>();
    var hold = false;
    Future<void>? disabling;
    final diagnostics = await install(persist: (_, state) async {
      if (hold) {
        writes.add('persist');
        await _bounded(persistRelease.future);
      }
    });
    await _bounded(diagnostics.setLocalConsentObserver((consent) async {
      snapshots.add(consent);
      if (hold && consent?.enabled == false) {
        writes.add('observer');
        await _bounded(observerRelease.future);
      }
    }));
    expect(snapshots, hasLength(1), reason: 'Positive replay control');
    final initialEpoch = snapshots.single!.consentEpoch;
    hold = true;
    try {
      var complete = false;
      disabling = diagnostics.setEnabled(false).whenComplete(() => complete = true);
      expect(snapshots.last?.enabled, isFalse,
          reason: 'Notification must execute before setEnabled reaches its first await');
      expect(snapshots.last!.consentEpoch, greaterThan(initialEpoch));
      expect(writes.first, 'observer');
      expect(complete, isFalse);
      observerRelease.complete();
      persistRelease.complete();
      await _bounded(disabling);
      expect(complete, isTrue);
    } finally {
      hold = false;
      if (!observerRelease.isCompleted) observerRelease.complete();
      if (!persistRelease.isCompleted) persistRelease.complete();
      if (disabling != null) await _bounded(disabling);
    }
  });

  test('clear publishes a new epoch synchronously although enabled is unchanged', () async {
    final seen = <LocalDiagnosticConsent?>[];
    final diagnostics = await install(observer: (consent) async => seen.add(consent));
    expect(diagnostics.enabled, isTrue);
    expect(seen, hasLength(1));
    final initialEpoch = seen.single!.consentEpoch;
    var booleanChanges = 0;
    void onBooleanChange() => booleanChanges++;
    diagnostics.enabledListenable.addListener(onBooleanChange);
    Future<void>? clearing;
    try {
      clearing = diagnostics.clear();
      expect(seen, hasLength(2));
      expect(seen.last!.enabled, isTrue);
      expect(seen.last!.consentEpoch, greaterThan(initialEpoch));
      expect(booleanChanges, 0);
      await _bounded(clearing);
    } finally {
      diagnostics.enabledListenable.removeListener(onBooleanChange);
      if (clearing != null) await _bounded(clearing);
    }
  });

  test('OFF then ON advances epochs even under a fixed clock and offline gate', () async {
    final seen = <LocalDiagnosticConsent?>[];
    final diagnostics = await install(
      observer: (consent) async => seen.add(consent),
      networkAllowed: () async => false,
    );
    expect(seen, hasLength(1));
    await _bounded(diagnostics.setEnabled(false));
    await _bounded(diagnostics.setEnabled(true));
    expect(seen.map((s) => s!.enabled), [true, false, true]);
    expect(seen[1]!.consentEpoch, greaterThan(seen[0]!.consentEpoch));
    expect(seen[2]!.consentEpoch, greaterThan(seen[1]!.consentEpoch));
  });

  test('replacement observer owns future changes and removal detaches it', () async {
    final first = <LocalDiagnosticConsent?>[];
    final second = <LocalDiagnosticConsent?>[];
    final diagnostics = await install(observer: (consent) async => first.add(consent));
    expect(first, hasLength(1));
    await _bounded(diagnostics.setLocalConsentObserver((consent) async => second.add(consent)));
    expect(second, hasLength(1));
    await _bounded(diagnostics.setEnabled(false));
    expect(first, hasLength(1));
    expect(second.last!.enabled, isFalse);
    final count = second.length;
    await _bounded(diagnostics.setLocalConsentObserver(null));
    await _bounded(diagnostics.setEnabled(true));
    expect(second, hasLength(count));
  });

  test('dispose publishes null before awaiting the unarm attempt', () async {
    final seen = <LocalDiagnosticConsent?>[];
    final release = Completer<void>();
    Future<void>? disposing;
    final diagnostics = await install(observer: (consent) async {
      seen.add(consent);
      if (consent == null) await _bounded(release.future);
    });
    expect(seen, hasLength(1));
    final initial = seen.single;
    try {
      var complete = false;
      disposing = diagnostics.dispose().whenComplete(() => complete = true);
      expect(seen, [initial, isNull]);
      expect(complete, isFalse);
      release.complete();
      await _bounded(disposing);
      expect(complete, isTrue);
      expect(seen.whereType<LocalDiagnosticConsent>(), [initial]);
    } finally {
      if (!release.isCompleted) release.complete();
      if (disposing != null) await _bounded(disposing);
    }
  });

  test('throwing or rejected observer cannot change diagnostics or leak text', () async {
    final captured = <Map<String, dynamic>>[];
    final lease = installScopedE2EFlowEventSink(captured.add);
    final diagnostics = await install();
    var calls = 0;
    try {
      await _bounded(diagnostics.setLocalConsentObserver((_) {
        calls++;
        throw StateError(_privateError);
      }));
      expect(calls, 1, reason: 'Observer must run before isolation/privacy assertions');
      expect(diagnostics.enabled, isTrue);
      await _bounded(diagnostics.clear());
      await _bounded(diagnostics.setLocalConsentObserver((_) async {
        calls++;
        throw TimeoutException(_privateError);
      }));
      await _bounded(diagnostics.setEnabled(false));
      expect(calls, greaterThan(2));
      expect(diagnostics.enabled, isFalse);
      final preview = await _bounded(diagnostics.exportPreview());
      expect('${jsonEncode(captured)}$preview', isNot(contains(_privateError)));
    } finally {
      await _bounded(diagnostics.setLocalConsentObserver(null));
      lease.release();
    }
  });

  test('never-finishing registration observer is bounded by two seconds', () async {
    final diagnostics = await install();
    final release = Completer<void>();
    Future<void>? registering;
    var calls = 0;
    try {
      fakeAsync((clock) {
        try {
          var complete = false;
          registering = diagnostics.setLocalConsentObserver((_) {
            calls++;
            return release.future;
          }).whenComplete(() => complete = true);
          clock.flushMicrotasks();
          expect(calls, 1, reason: 'Positive invocation before timeout control');
          expect(complete, isFalse);
          clock.elapse(_limit);
          clock.flushMicrotasks();
          expect(complete, isTrue);
        } finally {
          if (!release.isCompleted) release.complete();
          clock.flushMicrotasks();
        }
      });
    } finally {
      if (!release.isCompleted) release.complete();
      if (registering != null) await _bounded(registering!);
      await _bounded(diagnostics.setLocalConsentObserver(null));
    }
  });
}
