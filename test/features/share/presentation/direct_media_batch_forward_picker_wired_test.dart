import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/build_direct_media_library_batch_forward.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/share/application/direct_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/features/share/presentation/screens/direct_media_batch_forward_picker_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';

const _sourceContactPeerId = '12D3KooWPlan249SourceContactPeer';

DirectReceivedMediaActionIdentity _identity(int ordinal) =>
    DirectReceivedMediaActionIdentity(
      messageId: 'source-message-$ordinal',
      attachmentId: 'source-attachment-$ordinal',
    );

DirectMediaLibraryBatchForwardDraft _draft(int itemCount) =>
    DirectMediaLibraryBatchForwardDraft(
      items: [
        for (var index = 0; index < itemCount; index++)
          DirectMediaLibraryBatchForwardItemDraft(
            identity: _identity(index),
            resolvedPath: '/private/plan-249/source-$index.jpg',
            parentTimestamp: '2026-07-11T18:00:0$index.000Z',
            caption: 'independent caption $index',
            forwardProvenance: ForwardProvenance(
              operationDedupKey: 'opaque-operation-token-$index',
            ),
          ),
      ],
    );

ContactModel _contact(
  String peerId,
  String username, {
  bool archived = false,
  bool blocked = false,
}) => ContactModel(
  peerId: peerId,
  publicKey: 'public-key-$peerId',
  rendezvous: '/dns4/relay.invalid/tcp/443',
  username: username,
  signature: 'signature-$peerId',
  scannedAt: '2026-07-11T18:00:00.000Z',
  isArchived: archived,
  archivedAt: archived ? '2026-07-11T18:01:00.000Z' : null,
  isBlocked: blocked,
  blockedAt: blocked ? '2026-07-11T18:02:00.000Z' : null,
);

DirectMediaBatchForwardMatrix _matrix({
  required DirectMediaLibraryBatchForwardDraft draft,
  required List<String> contactPeerIds,
  required List<List<DirectMediaBatchForwardCellStatus>> statuses,
}) {
  assert(statuses.length == draft.items.length);
  return DirectMediaBatchForwardMatrix(
    cells: [
      for (var sourceIndex = 0; sourceIndex < draft.items.length; sourceIndex++)
        for (
          var contactIndex = 0;
          contactIndex < contactPeerIds.length;
          contactIndex++
        )
          DirectMediaBatchForwardCellResult(
            key: DirectMediaBatchForwardCellKey(
              sourceIdentity: draft.items[sourceIndex].identity,
              contactPeerId: contactPeerIds[contactIndex],
            ),
            status: statuses[sourceIndex][contactIndex],
          ),
    ],
  );
}

Widget _routedPickerApp({
  required DirectMediaLibraryBatchForwardDraft draft,
  required _RecordingContactRepository contactRepository,
  required DirectMediaBatchForwardDeliveryCoordinator deliveryCoordinator,
  required ValueChanged<DirectMediaBatchForwardCompletion?> onResult,
  Locale locale = const Locale('en'),
  double textScale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: FilledButton(
          key: const ValueKey('open-direct-batch-forward-picker'),
          onPressed: () async {
            final result = await Navigator.of(context)
                .push<DirectMediaBatchForwardCompletion>(
                  MaterialPageRoute<DirectMediaBatchForwardCompletion>(
                    builder: (_) => DirectMediaBatchForwardPickerWired(
                      draft: draft,
                      sourceContactPeerId: _sourceContactPeerId,
                      contactRepository: contactRepository,
                      deliveryCoordinator: deliveryCoordinator,
                    ),
                  ),
                );
            onResult(result);
          },
          child: const Text('Open batch forward'),
        ),
      ),
    ),
  ),
);

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('open-direct-batch-forward-picker')),
  );
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 12}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Finder _contactRow(String peerId) =>
    find.byKey(ValueKey('direct-batch-forward-contact-$peerId'));

Finder _captionField(int ordinal) =>
    find.byKey(ValueKey('direct-batch-forward-caption-$ordinal'));

int _builtKeyCount(String prefix) => find
    .byWidgetPredicate((widget) {
      final key = widget.key;
      final value = key is ValueKey ? key.value : null;
      return value is String && value.startsWith(prefix);
    }, skipOffstage: false)
    .evaluate()
    .length;

void main() {
  setUp(() {
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

  tearDown(() {
    UploadWakeLockController.debugReset();
    debugSetFlowEventSink(null);
  });

  testWidgets(
    'dedicated picker loads active direct contacts only and edits captions independently',
    (tester) async {
      final draft = _draft(2);
      final alice = _contact('12D3KooWRecipientAlicePeer', 'Alice');
      final blocked = _contact(
        '12D3KooWRecipientBlockedPeer',
        'Blocked Bob',
        blocked: true,
      );
      final archived = _contact(
        '12D3KooWRecipientArchivedPeer',
        'Archived Carol',
        archived: true,
      );
      final repository = _RecordingContactRepository([
        alice,
        blocked,
        archived,
      ]);
      final settled = _matrix(
        draft: draft,
        contactPeerIds: [alice.peerId],
        statuses: const [
          [DirectMediaBatchForwardCellStatus.sent],
          [DirectMediaBatchForwardCellStatus.sent],
        ],
      );
      final coordinator = _ScriptedCoordinator(
        initialScripts: [
          _AttemptScript(
            result: DirectMediaBatchForwardAttemptResult.success(
              matrix: settled,
              newlyAttemptedCellCount: 2,
            ),
          ),
        ],
      );
      final routeResults = <DirectMediaBatchForwardCompletion?>[];

      await tester.pumpWidget(
        _routedPickerApp(
          draft: draft,
          contactRepository: repository,
          deliveryCoordinator: coordinator,
          onResult: routeResults.add,
        ),
      );
      await _openPicker(tester);

      expect(repository.getActiveContactsCalls, 1);
      expect(repository.getAllContactsCalls, 0);
      expect(repository.getArchivedContactsCalls, 0);
      expect(repository.getContactCalls, 0);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Blocked Bob'), findsNothing);
      expect(find.text('Archived Carol'), findsNothing);
      expect(find.text('Groups'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget.key.toString().contains('group'),
        ),
        findsNothing,
      );

      await tester.enterText(_captionField(0), 'edited first caption');
      await tester.enterText(_captionField(1), '');
      await tester.tap(_contactRow(alice.peerId));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('direct-batch-forward-send')));
      await _pumpFrames(tester);

      expect(coordinator.initialInvocations, hasLength(1));
      final invocation = coordinator.initialInvocations.single;
      expect(invocation.contactPeerIds, [alice.peerId]);
      expect(invocation.draft.items.map((item) => item.caption).toList(), [
        'edited first caption',
        '',
      ]);
      expect(
        invocation.draft.items
            .map((item) => item.forwardProvenance.operationDedupKey)
            .toList(),
        ['opaque-operation-token-0', 'opaque-operation-token-1'],
      );
      expect(routeResults, hasLength(1));
      expect(routeResults.single, isNotNull);
      expect(routeResults.single!.fullySettledSourceIdentities.toSet(), {
        _identity(0),
        _identity(1),
      });
      expect(routeResults.single!.failedSourceIdentities, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'picker reports progress blocks live pop and releases wake lock in finally',
    (tester) async {
      final draft = _draft(1);
      final alice = _contact('12D3KooWWakeLockRecipientPeer', 'Alice');
      final sent = _matrix(
        draft: draft,
        contactPeerIds: [alice.peerId],
        statuses: const [
          [DirectMediaBatchForwardCellStatus.sent],
        ],
      );
      final failed = _matrix(
        draft: draft,
        contactPeerIds: [alice.peerId],
        statuses: const [
          [DirectMediaBatchForwardCellStatus.failed],
        ],
      );

      final cases = <_WakeLockCase>[
        _WakeLockCase(
          name: 'success',
          result: DirectMediaBatchForwardAttemptResult.success(
            matrix: sent,
            newlyAttemptedCellCount: 1,
          ),
          error: null,
          closes: true,
        ),
        _WakeLockCase(
          name: 'matrix failure',
          result: DirectMediaBatchForwardAttemptResult.success(
            matrix: failed,
            newlyAttemptedCellCount: 1,
          ),
          error: null,
          closes: false,
        ),
        _WakeLockCase(
          name: 'source denial',
          result: DirectMediaBatchForwardAttemptResult.denied(
            denial: DirectMediaBatchForwardAttemptDenial.sourceUnavailable,
          ),
          error: null,
          closes: false,
        ),
        _WakeLockCase(
          name: 'throw',
          result: null,
          error: StateError('delivery failed'),
          closes: false,
        ),
      ];

      for (final testCase in cases) {
        final wakeLockDriver = FakeUploadWakeLockDriver();
        UploadWakeLockController.debugReset(driver: wakeLockDriver);
        final gate = Completer<void>();
        final coordinator = _ScriptedCoordinator(
          initialScripts: [
            _AttemptScript(
              result: testCase.result,
              error: testCase.error,
              gate: gate,
              progressBeforeGate: const [
                DirectMediaBatchForwardProgress(
                  completedCellCount: 0,
                  totalCellCount: 1,
                  sourceOrdinal: 1,
                  sourceCount: 1,
                  phase: DirectMediaBatchForwardProgressPhase.uploading,
                ),
              ],
              progressAfterGate: const [
                DirectMediaBatchForwardProgress(
                  completedCellCount: 1,
                  totalCellCount: 1,
                  sourceOrdinal: 1,
                  sourceCount: 1,
                  phase: DirectMediaBatchForwardProgressPhase.sending,
                ),
              ],
            ),
          ],
        );
        final routeResults = <DirectMediaBatchForwardCompletion?>[];

        await tester.pumpWidget(
          _routedPickerApp(
            draft: draft,
            contactRepository: _RecordingContactRepository([alice]),
            deliveryCoordinator: coordinator,
            onResult: routeResults.add,
          ),
        );
        await _openPicker(tester);
        await tester.tap(_contactRow(alice.peerId));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('direct-batch-forward-send')),
        );
        await tester.pump();

        expect(
          coordinator.wakeLockHoldsAtInvocation,
          [1],
          reason: '${testCase.name}: acquire precedes application delivery',
        );
        expect(UploadWakeLockController.debugActiveHolds, 1);
        expect(wakeLockDriver.enableCalls, 1);
        expect(wakeLockDriver.disableCalls, 0);
        expect(
          find.byKey(const ValueKey('direct-batch-forward-progress')),
          findsOneWidget,
        );

        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('direct-batch-forward-picker')),
          findsOneWidget,
          reason: '${testCase.name}: a live attempt cannot be popped',
        );

        gate.complete();
        await _pumpFrames(tester);
        expect(
          UploadWakeLockController.debugActiveHolds,
          0,
          reason: '${testCase.name}: finally releases the hold',
        );
        expect(wakeLockDriver.disableCalls, 1);
        expect(routeResults.isNotEmpty, testCase.closes);
        expect(tester.takeException(), isNull);

        // Each case owns a fresh Navigator. Reusing an identical MaterialApp
        // here preserves the preceding route/transition in Flutter's element
        // tree and makes the next launcher tap target an offstage home route.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'picker retries the exact sparse failed cells without replaying settled cells',
    (tester) async {
      final draft = _draft(2);
      final alice = _contact('12D3KooWSparseAlicePeer', 'Alice');
      final bob = _contact('12D3KooWSparseBobPeer', 'Bob');
      final initialMatrix = _matrix(
        draft: draft,
        contactPeerIds: [alice.peerId, bob.peerId],
        statuses: const [
          [
            DirectMediaBatchForwardCellStatus.sent,
            DirectMediaBatchForwardCellStatus.failed,
          ],
          [
            DirectMediaBatchForwardCellStatus.failed,
            DirectMediaBatchForwardCellStatus.queued,
          ],
        ],
      );
      final retryMatrix = _matrix(
        draft: draft,
        contactPeerIds: [alice.peerId, bob.peerId],
        statuses: const [
          [
            DirectMediaBatchForwardCellStatus.sent,
            DirectMediaBatchForwardCellStatus.sent,
          ],
          [
            DirectMediaBatchForwardCellStatus.sent,
            DirectMediaBatchForwardCellStatus.queued,
          ],
        ],
      );
      final coordinator = _ScriptedCoordinator(
        initialScripts: [
          _AttemptScript(
            result: DirectMediaBatchForwardAttemptResult.success(
              matrix: initialMatrix,
              newlyAttemptedCellCount: 4,
            ),
          ),
        ],
        retryScripts: [
          _AttemptScript(
            result: DirectMediaBatchForwardAttemptResult.success(
              matrix: retryMatrix,
              newlyAttemptedCellCount: 2,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        _routedPickerApp(
          draft: draft,
          contactRepository: _RecordingContactRepository([alice, bob]),
          deliveryCoordinator: coordinator,
          onResult: (_) {},
        ),
      );
      await _openPicker(tester);
      await tester.tap(_contactRow(alice.peerId));
      await tester.tap(_contactRow(bob.peerId));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('direct-batch-forward-send')));
      await _pumpFrames(tester);

      final aliceSemanticsBefore = tester.getSemantics(
        _contactRow(alice.peerId),
      );
      expect(aliceSemanticsBefore.flagsCollection.isSelected, Tristate.isTrue);
      await tester.tap(_contactRow(alice.peerId), warnIfMissed: false);
      await tester.pump();
      final aliceSemanticsAfter = tester.getSemantics(
        _contactRow(alice.peerId),
      );
      expect(
        aliceSemanticsAfter.flagsCollection.isSelected,
        Tristate.isTrue,
        reason: 'a matrix-producing attempt freezes target selection',
      );

      await tester.enterText(_captionField(0), 'caption edited for retry');
      await tester.enterText(_captionField(1), '');
      await tester.tap(
        find.byKey(const ValueKey('direct-batch-forward-retry-failed')),
      );
      await _pumpFrames(tester);

      expect(coordinator.initialInvocations, hasLength(1));
      expect(coordinator.retryInvocations, hasLength(1));
      final retry = coordinator.retryInvocations.single;
      expect(identical(retry.priorMatrix, initialMatrix), isTrue);
      expect(retry.priorMatrix.failedKeys.toSet(), {
        DirectMediaBatchForwardCellKey(
          sourceIdentity: _identity(0),
          contactPeerId: bob.peerId,
        ),
        DirectMediaBatchForwardCellKey(
          sourceIdentity: _identity(1),
          contactPeerId: alice.peerId,
        ),
      });
      expect(retry.priorMatrix.sentCount, 1);
      expect(retry.priorMatrix.queuedCount, 1);
      expect(retry.draft.items.map((item) => item.caption).toList(), [
        'caption edited for retry',
        '',
      ]);
      expect(
        retry.draft.items
            .map((item) => item.forwardProvenance.operationDedupKey)
            .toList(),
        ['opaque-operation-token-0', 'opaque-operation-token-1'],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all-failed matrix freezes targets and retry denial preserves prior completion',
    (tester) async {
      final draft = _draft(2);
      final alice = _contact('12D3KooWDeniedAlicePeer', 'Alice');
      final bob = _contact('12D3KooWDeniedBobPeer', 'Bob');
      final allFailed = _matrix(
        draft: draft,
        contactPeerIds: [alice.peerId, bob.peerId],
        statuses: const [
          [
            DirectMediaBatchForwardCellStatus.failed,
            DirectMediaBatchForwardCellStatus.failed,
          ],
          [
            DirectMediaBatchForwardCellStatus.failed,
            DirectMediaBatchForwardCellStatus.failed,
          ],
        ],
      );
      final coordinator = _ScriptedCoordinator(
        initialScripts: [
          _AttemptScript(
            result: DirectMediaBatchForwardAttemptResult.success(
              matrix: allFailed,
              newlyAttemptedCellCount: 4,
            ),
          ),
        ],
        retryScripts: [
          _AttemptScript(
            result: DirectMediaBatchForwardAttemptResult.denied(
              denial: DirectMediaBatchForwardAttemptDenial.sourceUnavailable,
              priorMatrix: allFailed,
            ),
          ),
        ],
      );
      final routeResults = <DirectMediaBatchForwardCompletion?>[];

      await tester.pumpWidget(
        _routedPickerApp(
          draft: draft,
          contactRepository: _RecordingContactRepository([alice, bob]),
          deliveryCoordinator: coordinator,
          onResult: routeResults.add,
        ),
      );
      await _openPicker(tester);
      await tester.tap(_contactRow(alice.peerId));
      await tester.tap(_contactRow(bob.peerId));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('direct-batch-forward-send')));
      await _pumpFrames(tester);

      await tester.tap(_contactRow(alice.peerId), warnIfMissed: false);
      await tester.pump();
      expect(
        tester
            .getSemantics(_contactRow(alice.peerId))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
        reason: 'even an all-failed matrix freezes targets',
      );
      await tester.tap(
        find.byKey(const ValueKey('direct-batch-forward-retry-failed')),
      );
      await _pumpFrames(tester);

      expect(coordinator.retryInvocations, hasLength(1));
      expect(
        identical(coordinator.retryInvocations.single.priorMatrix, allFailed),
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('direct-batch-forward-retry-failed')),
        findsOneWidget,
        reason: 'retry denial keeps the prior failed matrix visible',
      );
      await tester.tap(_contactRow(alice.peerId), warnIfMissed: false);
      await tester.pump();
      expect(
        tester
            .getSemantics(_contactRow(alice.peerId))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
        reason: 'retry denial cannot thaw the target set',
      );

      await tester.tap(
        find.byKey(const ValueKey('direct-batch-forward-close')),
      );
      await _pumpFrames(tester);
      expect(routeResults, hasLength(1));
      expect(routeResults.single, isNotNull);
      expect(routeResults.single!.fullySettledSourceIdentities, isEmpty);
      expect(routeResults.single!.failedSourceIdentities.toSet(), {
        _identity(0),
        _identity(1),
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'initial source denial creates no matrix and leaves target selection editable',
    (tester) async {
      final draft = _draft(1);
      final alice = _contact('12D3KooWInitialDeniedAlice', 'Alice');
      final bob = _contact('12D3KooWInitialDeniedBobPeer', 'Bob');
      final bobSettled = _matrix(
        draft: draft,
        contactPeerIds: [bob.peerId],
        statuses: const [
          [DirectMediaBatchForwardCellStatus.sent],
        ],
      );
      final coordinator = _ScriptedCoordinator(
        initialScripts: [
          _AttemptScript(
            result: DirectMediaBatchForwardAttemptResult.denied(
              denial: DirectMediaBatchForwardAttemptDenial.sourceUnavailable,
            ),
          ),
          _AttemptScript(
            result: DirectMediaBatchForwardAttemptResult.success(
              matrix: bobSettled,
              newlyAttemptedCellCount: 1,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        _routedPickerApp(
          draft: draft,
          contactRepository: _RecordingContactRepository([alice, bob]),
          deliveryCoordinator: coordinator,
          onResult: (_) {},
        ),
      );
      await _openPicker(tester);
      await tester.tap(_contactRow(alice.peerId));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('direct-batch-forward-send')));
      await _pumpFrames(tester);

      expect(
        find.byKey(const ValueKey('direct-batch-forward-retry-failed')),
        findsNothing,
      );
      await tester.tap(_contactRow(alice.peerId));
      await tester.tap(_contactRow(bob.peerId));
      await tester.pump();
      expect(
        tester
            .getSemantics(_contactRow(alice.peerId))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      expect(
        tester.getSemantics(_contactRow(bob.peerId)).flagsCollection.isSelected,
        Tristate.isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('direct-batch-forward-send')));
      await _pumpFrames(tester);
      expect(coordinator.initialInvocations, hasLength(2));
      expect(coordinator.initialInvocations.first.contactPeerIds, [
        alice.peerId,
      ]);
      expect(coordinator.initialInvocations.last.contactPeerIds, [bob.peerId]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel before delivery returns null and close returns truthful completion',
    (tester) async {
      final draft = _draft(2);
      final alice = _contact('12D3KooWCloseAliceRecipient', 'Alice');
      final repository = _RecordingContactRepository([alice]);
      final noCalls = _ScriptedCoordinator();
      final cancelled = <DirectMediaBatchForwardCompletion?>[];

      await tester.pumpWidget(
        _routedPickerApp(
          draft: draft,
          contactRepository: repository,
          deliveryCoordinator: noCalls,
          onResult: cancelled.add,
        ),
      );
      await _openPicker(tester);
      await tester.tap(
        find.byKey(const ValueKey('direct-batch-forward-close')),
      );
      await _pumpFrames(tester);
      expect(cancelled, [isNull]);
      expect(noCalls.initialInvocations, isEmpty);

      // The second route is an independent scenario, not a continuation of
      // the Navigator that just completed the cancel transition.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      final partial = _matrix(
        draft: draft,
        contactPeerIds: [alice.peerId],
        statuses: const [
          [DirectMediaBatchForwardCellStatus.sent],
          [DirectMediaBatchForwardCellStatus.failed],
        ],
      );
      final coordinator = _ScriptedCoordinator(
        initialScripts: [
          _AttemptScript(
            result: DirectMediaBatchForwardAttemptResult.success(
              matrix: partial,
              newlyAttemptedCellCount: 2,
            ),
          ),
        ],
      );
      final completed = <DirectMediaBatchForwardCompletion?>[];
      await tester.pumpWidget(
        _routedPickerApp(
          draft: draft,
          contactRepository: repository,
          deliveryCoordinator: coordinator,
          onResult: completed.add,
        ),
      );
      await _openPicker(tester);
      await tester.tap(_contactRow(alice.peerId));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('direct-batch-forward-send')));
      await _pumpFrames(tester);
      await tester.tap(
        find.byKey(const ValueKey('direct-batch-forward-close')),
      );
      await _pumpFrames(tester);

      expect(completed, hasLength(1));
      expect(completed.single, isNotNull);
      expect(completed.single!.fullySettledSourceIdentities, {_identity(0)});
      expect(completed.single!.failedSourceIdentities, {_identity(1)});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'batch picker is semantic lazy and safe in small LTR and RTL viewports',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final draft = _draft(10);
      final contacts = [
        for (var index = 0; index < 40; index++)
          _contact(
            '12D3KooWViewportRecipient${index.toString().padLeft(2, '0')}',
            'Contact $index',
          ),
      ];

      for (final locale in const [Locale('en'), Locale('ar')]) {
        final retryGate = Completer<void>();
        final failed = _matrix(
          draft: draft,
          contactPeerIds: [contacts.first.peerId],
          statuses: [
            for (var index = 0; index < draft.items.length; index++)
              [DirectMediaBatchForwardCellStatus.failed],
          ],
        );
        final coordinator = _ScriptedCoordinator(
          initialScripts: [
            _AttemptScript(
              result: DirectMediaBatchForwardAttemptResult.success(
                matrix: failed,
                newlyAttemptedCellCount: draft.items.length,
              ),
            ),
          ],
          retryScripts: [
            _AttemptScript(
              gate: retryGate,
              progressBeforeGate: [
                DirectMediaBatchForwardProgress(
                  completedCellCount: 0,
                  totalCellCount: draft.items.length,
                  sourceOrdinal: 1,
                  sourceCount: draft.items.length,
                  phase: DirectMediaBatchForwardProgressPhase.uploading,
                ),
              ],
              result: DirectMediaBatchForwardAttemptResult.success(
                matrix: failed,
                newlyAttemptedCellCount: draft.items.length,
              ),
            ),
          ],
        );
        await tester.pumpWidget(
          _routedPickerApp(
            draft: draft,
            contactRepository: _RecordingContactRepository(contacts),
            deliveryCoordinator: coordinator,
            onResult: (_) {},
            locale: locale,
            textScale: 1.3,
          ),
        );
        await _openPicker(tester);

        final picker = find.byKey(
          const ValueKey('direct-batch-forward-picker'),
        );
        expect(picker, findsOneWidget);
        expect(
          Directionality.of(tester.element(picker)),
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);

        final builtSources = _builtKeyCount('direct-batch-forward-source-');
        final builtContacts = _builtKeyCount('direct-batch-forward-contact-');
        expect(builtSources, inInclusiveRange(1, 9));
        expect(builtContacts, inInclusiveRange(1, 39));

        final firstContact = _contactRow(contacts.first.peerId);
        expect(firstContact, findsOneWidget);
        await tester.tap(firstContact);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('direct-batch-forward-send')).hitTestable(),
          findsOneWidget,
          reason: '${locale.languageCode}: required send control is reachable',
        );
        final l10n = AppLocalizations.of(tester.element(picker))!;
        await tester.tap(
          find.byKey(const ValueKey('direct-batch-forward-send')),
        );
        await _pumpFrames(tester);

        final summary = find.byKey(
          const ValueKey('direct-batch-forward-summary'),
        );
        expect(summary, findsOneWidget);
        expect(
          tester.getSemantics(summary).label,
          l10n.direct_batch_forward_summary(0, 0, draft.items.length),
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('direct-batch-forward-status-sent')),
              )
              .data,
          '${l10n.direct_batch_forward_status_sent} 0',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(
                  const ValueKey('direct-batch-forward-status-queued'),
                ),
              )
              .data,
          '${l10n.direct_batch_forward_status_queued} 0',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(
                  const ValueKey('direct-batch-forward-status-failed'),
                ),
              )
              .data,
          '${l10n.direct_batch_forward_status_failed} ${draft.items.length}',
        );

        final retry = find.byKey(
          const ValueKey('direct-batch-forward-retry-failed'),
        );
        expect(
          retry.hitTestable(),
          findsOneWidget,
          reason:
              '${locale.languageCode}: localized Retry remains reachable after a failed matrix',
        );
        expect(
          find.descendant(
            of: retry,
            matching: find.text(l10n.direct_batch_forward_retry_failed),
          ),
          findsOneWidget,
        );
        await tester.tap(retry);
        await tester.pump();
        expect(coordinator.retryInvocations, hasLength(1));
        expect(
          identical(coordinator.retryInvocations.single.priorMatrix, failed),
          isTrue,
        );
        expect(
          find.byKey(const ValueKey('direct-batch-forward-progress')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('direct-batch-forward-summary')),
          findsNothing,
          reason:
              '${locale.languageCode}: live retry uses the bounded status region while retaining the matrix in state',
        );
        expect(tester.takeException(), isNull);

        retryGate.complete();
        await _pumpFrames(tester);
        expect(
          find.byKey(const ValueKey('direct-batch-forward-progress')),
          findsNothing,
        );
        expect(
          tester.getSemantics(summary).label,
          l10n.direct_batch_forward_summary(0, 0, draft.items.length),
        );
        expect(tester.takeException(), isNull);

        final semantics = tester.getSemantics(picker).toStringDeep();
        for (final item in draft.items) {
          expect(semantics, isNot(contains(item.identity.messageId)));
          expect(semantics, isNot(contains(item.identity.attachmentId)));
          expect(semantics, isNot(contains(item.resolvedPath)));
          expect(
            semantics,
            isNot(contains(item.forwardProvenance.operationDedupKey)),
          );
        }
        for (final contact in contacts) {
          expect(semantics, isNot(contains(contact.peerId)));
        }

        await tester.tap(
          find.byKey(const ValueKey('direct-batch-forward-close')),
        );
        await _pumpFrames(tester);

        // LTR and RTL are independent route fixtures. A fresh root prevents
        // the completed route transition from obscuring the next launcher.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets('picker diagnostics omit source contact and exception secrets', (
    tester,
  ) async {
    final draft = _draft(1);
    final contact = _contact(
      '12D3KooWDiagnosticRecipientSecret',
      'Secret Recipient Username',
    );
    const thrownSecret =
        'exception-secret path=/private/plan-249/source-0.jpg '
        'token=opaque-operation-token-0 nonce=secret-nonce';
    final events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);
    final oldLogging = flowEventLoggingEnabled;
    flowEventLoggingEnabled = false;
    addTearDown(() => flowEventLoggingEnabled = oldLogging);
    final coordinator = _ScriptedCoordinator(
      initialScripts: [_AttemptScript(error: StateError(thrownSecret))],
    );

    await tester.pumpWidget(
      _routedPickerApp(
        draft: draft,
        contactRepository: _RecordingContactRepository([contact]),
        deliveryCoordinator: coordinator,
        onResult: (_) {},
      ),
    );
    await _openPicker(tester);
    await tester.tap(_contactRow(contact.peerId));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('direct-batch-forward-send')));
    await _pumpFrames(tester);

    expect(events, isNotEmpty, reason: 'the failure path emits bounded state');
    final diagnostics = events.toString();
    for (final forbidden in <String>[
      thrownSecret,
      'exception-secret',
      draft.items.single.identity.messageId,
      draft.items.single.identity.attachmentId,
      draft.items.single.resolvedPath,
      draft.items.single.caption,
      draft.items.single.forwardProvenance.operationDedupKey,
      contact.peerId,
      contact.username,
      'secret-nonce',
    ]) {
      expect(diagnostics, isNot(contains(forbidden)));
    }
    expect(find.textContaining('exception-secret'), findsNothing);
    expect(UploadWakeLockController.debugActiveHolds, 0);
    expect(tester.takeException(), isNull);
  });
}

class _RecordingContactRepository extends InMemoryContactRepository {
  _RecordingContactRepository(this.pickerRows);

  final List<ContactModel> pickerRows;
  int getActiveContactsCalls = 0;
  int getAllContactsCalls = 0;
  int getArchivedContactsCalls = 0;
  int getContactCalls = 0;

  @override
  Future<List<ContactModel>> getActiveContacts() async {
    getActiveContactsCalls += 1;
    return List.unmodifiable(pickerRows);
  }

  @override
  Future<List<ContactModel>> getAllContacts() async {
    getAllContactsCalls += 1;
    return List.unmodifiable(pickerRows);
  }

  @override
  Future<List<ContactModel>> getArchivedContacts() async {
    getArchivedContactsCalls += 1;
    return pickerRows.where((contact) => contact.isArchived).toList();
  }

  @override
  Future<ContactModel?> getContact(String peerId) async {
    getContactCalls += 1;
    for (final contact in pickerRows) {
      if (contact.peerId == peerId) {
        return contact;
      }
    }
    return null;
  }
}

class _InitialInvocation {
  const _InitialInvocation({
    required this.sourceContactPeerId,
    required this.draft,
    required this.contactPeerIds,
  });

  final String sourceContactPeerId;
  final DirectMediaLibraryBatchForwardDraft draft;
  final List<String> contactPeerIds;
}

class _RetryInvocation {
  const _RetryInvocation({
    required this.sourceContactPeerId,
    required this.draft,
    required this.priorMatrix,
  });

  final String sourceContactPeerId;
  final DirectMediaLibraryBatchForwardDraft draft;
  final DirectMediaBatchForwardMatrix priorMatrix;
}

class _WakeLockCase {
  const _WakeLockCase({
    required this.name,
    required this.result,
    required this.error,
    required this.closes,
  });

  final String name;
  final DirectMediaBatchForwardAttemptResult? result;
  final Object? error;
  final bool closes;
}

class _AttemptScript {
  const _AttemptScript({
    this.result,
    this.error,
    this.gate,
    this.progressBeforeGate = const [],
    this.progressAfterGate = const [],
  });

  final DirectMediaBatchForwardAttemptResult? result;
  final Object? error;
  final Completer<void>? gate;
  final List<DirectMediaBatchForwardProgress> progressBeforeGate;
  final List<DirectMediaBatchForwardProgress> progressAfterGate;

  Future<DirectMediaBatchForwardAttemptResult> run(
    void Function(DirectMediaBatchForwardProgress)? onProgress,
  ) async {
    for (final progress in progressBeforeGate) {
      onProgress?.call(progress);
    }
    await gate?.future;
    for (final progress in progressAfterGate) {
      onProgress?.call(progress);
    }
    if (error != null) {
      throw error!;
    }
    return result!;
  }
}

class _ScriptedCoordinator
    implements DirectMediaBatchForwardDeliveryCoordinator {
  _ScriptedCoordinator({
    List<_AttemptScript> initialScripts = const [],
    List<_AttemptScript> retryScripts = const [],
  }) : _initialScripts = List.of(initialScripts),
       _retryScripts = List.of(retryScripts);

  final List<_AttemptScript> _initialScripts;
  final List<_AttemptScript> _retryScripts;
  final List<_InitialInvocation> initialInvocations = [];
  final List<_RetryInvocation> retryInvocations = [];
  final List<int> wakeLockHoldsAtInvocation = [];

  @override
  Future<DirectMediaBatchForwardAttemptResult> deliverInitial({
    required String sourceContactPeerId,
    required DirectMediaLibraryBatchForwardDraft draft,
    required List<String> contactPeerIds,
    void Function(DirectMediaBatchForwardProgress)? onProgress,
  }) {
    wakeLockHoldsAtInvocation.add(UploadWakeLockController.debugActiveHolds);
    initialInvocations.add(
      _InitialInvocation(
        sourceContactPeerId: sourceContactPeerId,
        draft: draft,
        contactPeerIds: List.unmodifiable(contactPeerIds),
      ),
    );
    return _initialScripts.removeAt(0).run(onProgress);
  }

  @override
  Future<DirectMediaBatchForwardAttemptResult> retryFailed({
    required String sourceContactPeerId,
    required DirectMediaLibraryBatchForwardDraft draft,
    required DirectMediaBatchForwardMatrix priorMatrix,
    void Function(DirectMediaBatchForwardProgress)? onProgress,
  }) {
    wakeLockHoldsAtInvocation.add(UploadWakeLockController.debugActiveHolds);
    retryInvocations.add(
      _RetryInvocation(
        sourceContactPeerId: sourceContactPeerId,
        draft: draft,
        priorMatrix: priorMatrix,
      ),
    );
    return _retryScripts.removeAt(0).run(onProgress);
  }
}
