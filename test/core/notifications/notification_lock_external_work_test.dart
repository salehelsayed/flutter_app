import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/bounded_posix_flock.dart';
import 'package:flutter_app/core/notifications/notification_lock_transaction.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';

const channel = MethodChannel('com.mknoon/go_bridge');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  var live = true;
  var checks = 0;
  var ends = 0;
  var admission = true;
  setUp(() {
    root = Directory.systemTemp.createTempSync(
      'notification-expiration-audit-',
    );
    live = true;
    checks = 0;
    ends = 0;
    admission = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    BoundedPosixFlock.debugUseIosBackgroundTasks = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'notificationLockBegin':
              return admission ? 41 : null;
            case 'notificationLockIsActive':
              checks++;
              return live;
            case 'notificationLockEnd':
              ends++;
              return null;
          }
          throw MissingPluginException(call.method);
        });
  });

  test(
    'refusal before admission enters neither callback nor disk action',
    () async {
      final file = File('${root.path}/.coordination.lock')..createSync();
      admission = false;
      var entered = false;
      await expectLater(
        BoundedPosixFlock.withNotificationTransaction(file, () async {
          entered = true;
        }),
        throwsA(isA<BoundedPosixFlockUnavailableException>()),
      );
      expect(entered, isFalse);
      expect(checks, 0);
      expect(ends, 0);
      expect(canAcquire(file), isTrue);
      expect(NotificationLockTransaction.marker(file).existsSync(), isFalse);
    },
  );

  test(
    'live logical owner excludes another caller while the kernel lock is free',
    () async {
      final file = File('${root.path}/.coordination.lock')..createSync();
      final entered = Completer<void>();
      final complete = Completer<void>();
      final pending = BoundedPosixFlock.withNotificationTransaction(
        file,
        () async {
          await NotificationLockTransaction.outside(() async {
            entered.complete();
            await complete.future;
          });
          expect(canAcquire(file), isFalse);
        },
      );
      await entered.future;
      expect(canAcquire(file), isTrue);
      expect(ends, 1);
      expect(
        await NotificationLockTransaction.ownerIsAlive(
          NotificationLockTransaction.readMarker(file)!,
        ),
        isTrue,
      );
      // Different acquisition key, same kernel inode: model another isolate's
      // admission without queueing behind this isolate's completion future.
      final alias = File('${root.path}/./.coordination.lock');
      var competingEffect = false;
      await expectLater(
        BoundedPosixFlock.withExclusive(alias, () async {
          competingEffect = true;
        }),
        throwsA(isA<BoundedPosixFlockUnavailableException>()),
      );
      expect(competingEffect, isFalse);
      complete.complete();
      await pending;
      expect(NotificationLockTransaction.marker(file).existsSync(), isFalse);
      expect(canAcquire(file), isTrue);
    },
  );

  test(
    'changed operation token refuses late completion without deleting the successor',
    () async {
      final file = File('${root.path}/.coordination.lock')..createSync();
      var settled = false;
      final successor = await NotificationLockTransaction.beginOwner();
      final successorBytes = jsonEncode(successor);
      await expectLater(
        BoundedPosixFlock.withNotificationTransaction(file, () async {
          await NotificationLockTransaction.outside(() async {
            NotificationLockTransaction.marker(
              file,
            ).writeAsStringSync(successorBytes);
          });
          settled = true;
        }),
        throwsA(isA<BoundedPosixFlockUnavailableException>()),
      );
      expect(settled, isFalse);
      expect(NotificationLockTransaction.readMarker(file), successorBytes);
      expect(canAcquire(file), isTrue);
      await NotificationLockTransaction.endOwner(successor);
    },
  );

  test('abandoned owner is cleared only under newly admitted flock', () async {
    final file = File('${root.path}/.coordination.lock')..createSync();
    final owner = await NotificationLockTransaction.beginOwner();
    final marker = NotificationLockTransaction.marker(file);
    marker.writeAsStringSync(jsonEncode(owner));
    await NotificationLockTransaction.endOwner(owner);
    admission = false;
    await expectLater(
      BoundedPosixFlock.withExclusive(file, () async {}),
      throwsA(isA<BoundedPosixFlockUnavailableException>()),
    );
    expect(marker.existsSync(), isTrue);
    admission = true;
    await BoundedPosixFlock.withExclusive(file, () async {
      expect(marker.existsSync(), isFalse);
      expect(canAcquire(file), isFalse);
    });
    expect(canAcquire(file), isTrue);
  });

  test('callback and denied reacquisition errors remain observable', () async {
    final file = File('${root.path}/.coordination.lock')..createSync();
    final original = StateError('external effect failed');
    await expectLater(
      BoundedPosixFlock.withNotificationTransaction(file, () async {
        await NotificationLockTransaction.outside(() async {
          admission = false;
          throw original;
        });
      }),
      throwsA(
        isA<NotificationLockReacquisitionException>()
            .having((e) => e.originalError, 'original error', same(original))
            .having(
              (e) => e.reacquisitionError,
              'reacquisition',
              isA<BoundedPosixFlockUnavailableException>(),
            ),
      ),
    );
    expect(canAcquire(file), isTrue);
    admission = true;
    await BoundedPosixFlock.withExclusive(file, () async {});
    expect(NotificationLockTransaction.marker(file).existsSync(), isFalse);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    BoundedPosixFlock.debugUseIosBackgroundTasks = null;
    debugDefaultTargetPlatformOverride = null;
    root.deleteSync(recursive: true);
  });

  test(
    'iOS inventory waits outside flock and expired reacquisition preserves allocation custody',
    () async {
      final registry = DurableConversationNotificationIdRegistry(
        directory: root,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final result = registry.resolve(
        'audit-peer',
        activeNotificationIds: () async {
          entered.complete();
          await release.future;
          return <Object?>[123];
        },
      );
      await entered.future;
      final lock = File('${root.path}/.coordination.lock');
      expect(canAcquire(lock), isTrue);
      live = false;
      await Future<void>.delayed(Duration.zero);
      expect(canAcquire(lock), isTrue);
      expect(ends, 1);
      final checksAtExpiry = checks;
      release.complete();
      await expectLater(
        result,
        throwsA(isA<NotificationIdAllocationException>()),
      );
      expect(checks, greaterThan(checksAtExpiry));
      expect(canAcquire(lock), isTrue);
      expect(ends, 2);
      expect(File('${root.path}/123.owner').existsSync(), isFalse);
    },
  );

  test(
    'native barrier authorization reacquires and releases around nested authority reads',
    () async {
      final file = File('${root.path}/.coordination.lock')..createSync();
      await BoundedPosixFlock.withNotificationTransaction(file, () async {
        await NotificationLockTransaction.outside(() async {
          expect(canAcquire(file), isTrue);
          await NotificationLockTransaction.inside(() async {
            expect(canAcquire(file), isFalse);
            await NotificationLockTransaction.outside(() async {
              expect(canAcquire(file), isTrue);
            });
            expect(canAcquire(file), isFalse);
          });
          expect(canAcquire(file), isTrue);
        });
        expect(canAcquire(file), isFalse);
      });
      expect(canAcquire(file), isTrue);
      expect(ends, 4);
    },
  );

  for (final operation in ['replace', 'cancel']) {
    test(
      'late $operation never overwrites a changed content generation',
      () async {
        final registry = DurableConversationNotificationIdRegistry(
          directory: root,
        );
        final id = await registry.resolve(
          'audit-peer',
          activeNotificationIds: () async => <Object?>[],
        );
        const original = ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'original',
          generation: 'original',
        );
        const successor = ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'successor',
          generation: 'successor',
        );
        await registry.recordContentMetadata(
          conversationKey: 'audit-peer',
          notificationId: id,
          metadata: original,
        );
        Future<void> callback() async {
          expect(canAcquire(File('${root.path}/.coordination.lock')), isTrue);
          // A controlled noncooperating writer models corrupted/stale authority.
          // Cooperating Runner/NSE writes are already fenced by the live marker.
          File(
            '${root.path}/$id.content-kind',
          ).writeAsStringSync(jsonEncode(successor.toJson()));
        }

        final accepted = operation == 'replace'
            ? await registry.replaceContentIfGeneration(
                conversationKey: 'audit-peer',
                notificationId: id,
                expectedGeneration: 'original',
                metadata: original,
                replace: callback,
              )
            : await registry.cancelContentIfGeneration(
                conversationKey: 'audit-peer',
                notificationId: id,
                generation: 'original',
                cancel: callback,
              );
        expect(accepted, isFalse);
        expect(
          await registry.lookupContentMetadata(
            conversationKey: 'audit-peer',
            notificationId: id,
          ),
          successor,
        );
      },
    );
  }

  for (final slowPoint in ['canonical', 'native', 'native claim drift']) {
    test(
      'iOS $slowPoint wait releases flock and rejected settlement retains PUBLISHING',
      () async {
        var clockOffset = Duration.zero;
        DateTime now() => DateTime.now().toUtc().add(clockOffset);
        final store = LocalNotificationLedgerStore(
          directory: root,
          nowUtc: now,
        );
        final registry = DurableConversationNotificationIdRegistry(
          directory: root,
          localNotificationEffectCoordinator:
              DurableLocalNotificationEffectCoordinator(
                ledgerStore: store,
                nowUtc: now,
              ),
        );
        final id = await registry.resolve(
          'audit-peer',
          activeNotificationIds: () async => <Object?>[],
        );
        final binding = 'v1:${'a' * 64}';
        await store.initializeOrRebind(currentOpaqueBinding: binding);
        final identity = AppVisibilityConversationIdentity.tryParse(
          lane: AppVisibilityConversationLane.direct,
          value: 'audit-peer',
        )!;
        final entered = Completer<void>();
        final release = Completer<void>();
        var nativeCalls = 0;
        var retired = 0;
        var suspendCallback = true;
        var denyInventoryReacquisition = false;
        DurableLocalNotificationEffectContext context(String correlation) =>
            DurableLocalNotificationEffectContext(
              currentOpaqueBinding: binding,
              eventCorrelation: correlation,
              conversationDigest: identity.digest,
              producerKind: LocalNotificationProducerKind.directMessage,
              sourceCustody: LocalNotificationSourceCustody.sqlReady,
              presentationOwner: LocalNotificationPresentationOwner.mainApp,
              readFinalCanonicalDisposition: () async {
                if (suspendCallback && slowPoint == 'canonical') {
                  entered.complete();
                  await release.future;
                }
                return DurableLocalNotificationCanonicalDisposition.eligible;
              },
            );
        Future<DurableLocalNotificationEffectResult> run(String correlation) =>
            registry.runFinalEffect(
              context: context(correlation),
              appVisibility: BackgroundVisibility(),
              conversationIdentity: identity,
              conversationKey: 'audit-peer',
              notificationId: id,
              metadata: ConversationNotificationContentMetadata(
                kind: ConversationNotificationContentKind.message,
                eventIdentity: correlation,
                generation: 'ledger:$correlation',
              ),
              retireCurrent: () async {
                retired++;
              },
              publishNative: () async {
                nativeCalls++;
                if (suspendCallback && slowPoint.startsWith('native')) {
                  entered.complete();
                  await release.future;
                }
              },
              activeNotificationIds: () async {
                if (denyInventoryReacquisition) admission = false;
                return <Object?>[id];
              },
            );
        // Preserve an existing settled event while exercising a different event.
        suspendCallback = false;
        final seed = await run('b' * 64);
        await registry.settleSqlReadyEffect(
          currentOpaqueBinding: binding,
          eventCorrelation: 'b' * 64,
          expectedRevision: seed.receipt!.recordRevision,
        );
        final seedBytes = (await store.read(
          currentOpaqueBinding: binding,
        ))!.records['b' * 64]!.toJson();
        nativeCalls = 0;
        retired = 0;
        suspendCallback = true;
        final pending = run('c' * 64);
        await entered.future;
        final raw = jsonDecode(store.ledgerFile.readAsStringSync()) as Map;
        expect((raw['records'] as Map)['c' * 64]['effectPhase'], 'PUBLISHING');
        expect(canAcquire(store.coordinationLockFile), isTrue);
        final drifting = slowPoint == 'native claim drift';
        if (drifting) {
          await store.mutateLockHeld(
            currentOpaqueBinding: binding,
            mutation: (envelope) {
              final record = envelope.records['c' * 64]!;
              return envelope.copyWith(
                storeRevision: envelope.storeRevision + 1,
                records: {
                  ...envelope.records,
                  record.eventCorrelation: record.copyWith(
                    revision: record.revision + 1,
                    updatedAtUtc: DateTime.now().toUtc().toIso8601String(),
                  ),
                },
              );
            },
          );
        } else {
          live = false;
        }
        await Future<void>.delayed(Duration.zero);
        expect(canAcquire(store.coordinationLockFile), isTrue);
        final checksAtExpiry = checks;
        final endsAtExpiry = ends;
        expect(nativeCalls, slowPoint.startsWith('native') ? 1 : 0);
        release.complete();
        if (slowPoint.startsWith('native')) {
          expect(
            (await pending).disposition,
            DurableLocalNotificationEffectDisposition.ambiguous,
          );
        } else {
          await expectLater(
            pending,
            throwsA(isA<NotificationIdAllocationException>()),
          );
        }
        expect(checks, greaterThan(checksAtExpiry));
        expect(ends, endsAtExpiry + 1);
        expect(nativeCalls, slowPoint.startsWith('native') ? 1 : 0);
        expect(retired, 0);
        expect(canAcquire(store.coordinationLockFile), isTrue);
        live = true;
        suspendCallback = false;
        final reopened = await store.read(currentOpaqueBinding: binding);
        expect(
          reopened!.records['c' * 64]!.effectPhase,
          LocalNotificationEffectPhase.publishing,
        );
        expect(reopened.records['b' * 64]!.toJson(), seedBytes);
        expect(
          (await run('c' * 64)).disposition,
          DurableLocalNotificationEffectDisposition.ambiguous,
        );
        expect(
          nativeCalls,
          slowPoint.startsWith('native') ? 1 : 0,
          reason: 'fresh ambiguous residue must not repeat native effect',
        );
        if (slowPoint == 'native') {
          clockOffset = const Duration(seconds: 66);
          denyInventoryReacquisition = true;
          expect(
            (await run('c' * 64)).disposition,
            DurableLocalNotificationEffectDisposition.ambiguous,
          );
          expect(canAcquire(store.coordinationLockFile), isTrue);
          expect(nativeCalls, 1);
          final raw = jsonDecode(store.ledgerFile.readAsStringSync()) as Map;
          expect(
            (raw['records'] as Map)['c' * 64]['effectPhase'],
            'PUBLISHING',
            reason:
                'inventory uncertainty must not swallow denied admission and settle',
          );
          expect((raw['records'] as Map)['b' * 64], seedBytes);
        }
      },
    );
  }
}

class BackgroundVisibility extends AppVisibilitySuppressionReader {
  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async => const AppVisibilityEvaluation(
    isForegroundActive: false,
    maySuppress: false,
    lifecycle: AppVisibilityLifecycle.background,
    revision: 8,
    lifecycleGeneration: 12,
  );
}

typedef OpenN = Int32 Function(Pointer<Utf8>, Int32);
typedef OpenD = int Function(Pointer<Utf8>, int);
typedef FlockN = Int32 Function(Int32, Int32);
typedef FlockD = int Function(int, int);
typedef CloseN = Int32 Function(Int32);
typedef CloseD = int Function(int);
bool canAcquire(File file) {
  final lib = DynamicLibrary.process();
  final open = lib.lookupFunction<OpenN, OpenD>('open');
  final flock = lib.lookupFunction<FlockN, FlockD>('flock');
  final close = lib.lookupFunction<CloseN, CloseD>('close');
  final path = file.path.toNativeUtf8();
  final fd = open(path, 2);
  malloc.free(path);
  if (fd < 0) throw StateError('cannot open fixture lock');
  try {
    if (flock(fd, 2 | 4) != 0) return false;
    flock(fd, 8);
    return true;
  } finally {
    close(fd);
  }
}
