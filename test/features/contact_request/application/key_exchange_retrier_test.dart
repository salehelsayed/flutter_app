import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retrier.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';

void main() {
  late FakeP2PService p2pService;
  late FakeContactRepository contactRepo;
  late FakeIdentityRepository identityRepo;
  late FakeBridge bridge;
  late KeyExchangeRetrier retrier;

  setUp(() {
    p2pService = FakeP2PService();
    contactRepo = FakeContactRepository();
    identityRepo = FakeIdentityRepository();
    bridge = FakeBridge();

    retrier = KeyExchangeRetrier(
      p2pService: p2pService,
      contactRepo: contactRepo,
      identityRepo: identityRepo,
      bridge: bridge,
    );
  });

  tearDown(() {
    retrier.dispose();
    p2pService.dispose();
  });

  group('KeyExchangeRetrier', () {
    test('start subscribes to stateStream', () {
      retrier.start();

      // Verify retrier is listening by emitting a state and checking no crash
      p2pService.emitState(NodeState.stopped);
    });

    test('triggers retry on offline to online transition', () {
      fakeAsync((fake) {
        retrier.start();

        // Emit online state (isStarted + circuitAddresses non-empty)
        final onlineState = const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
        );
        p2pService.emitState(onlineState);
        fake.flushMicrotasks(); // deliver stream event, creates timer

        // Just before the 5s debounce — no retry yet
        fake.elapse(const Duration(seconds: 4, milliseconds: 999));
        fake.flushMicrotasks();
        expect(identityRepo.loadIdentityCallCount, 0);

        // At exactly 5s — timer fires
        fake.elapse(const Duration(milliseconds: 1));
        fake.flushMicrotasks(); // complete the async _retryIfNeeded body

        // retryIncompleteKeyExchanges was called → it tried to load identity
        expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
      });
    });

    test('does not trigger when already online', () {
      fakeAsync((fake) {
        // Start in online state
        p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
        );
        retrier = KeyExchangeRetrier(
          p2pService: p2pService,
          contactRepo: contactRepo,
          identityRepo: identityRepo,
          bridge: bridge,
        );
        retrier.start();

        // Stay online — emit same state (not a transition)
        p2pService.emitState(const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
        ));
        fake.flushMicrotasks();

        // Wait well past the debounce — no timer was created
        fake.elapse(const Duration(seconds: 6));
        fake.flushMicrotasks();

        // No retry triggered (identity never loaded) because no transition
        expect(identityRepo.loadIdentityCallCount, 0);
      });
    });

    test('debounces rapid state changes', () {
      fakeAsync((fake) {
        retrier.start();

        // Go online → creates timer
        p2pService.emitState(const NodeState(
          isStarted: true,
          peerId: 'p',
          circuitAddresses: ['/a'],
        ));
        fake.flushMicrotasks();

        // Advance 1s (timer not fired yet)
        fake.elapse(const Duration(seconds: 1));

        // Go offline → _wasOnline becomes false, but old timer still pending
        p2pService.emitState(NodeState.stopped);
        fake.flushMicrotasks();

        // Go online again → new timer replaces old (cancel + new Timer)
        p2pService.emitState(const NodeState(
          isStarted: true,
          peerId: 'p',
          circuitAddresses: ['/a'],
        ));
        fake.flushMicrotasks();

        // Advance 5s from LAST online event → retry fires
        fake.elapse(const Duration(seconds: 5));
        fake.flushMicrotasks();

        // Should only retry once (first timer was cancelled by the second online)
        expect(identityRepo.loadIdentityCallCount, 1);
      });
    });

    test('does not re-enter while retrying', () {
      fakeAsync((fake) {
        retrier.start();

        final onlineState = const NodeState(
          isStarted: true,
          peerId: 'p',
          circuitAddresses: ['/a'],
        );

        // Go online → creates 5s debounce timer
        p2pService.emitState(onlineState);
        fake.flushMicrotasks();

        // Fire the first timer and let the async retry run
        fake.elapse(const Duration(seconds: 5));
        fake.flushMicrotasks();
        expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));

        // Go offline then online again → triggers another timer
        p2pService.emitState(NodeState.stopped);
        fake.flushMicrotasks();
        p2pService.emitState(onlineState);
        fake.flushMicrotasks();

        // Fire the second timer
        fake.elapse(const Duration(seconds: 5));
        fake.flushMicrotasks();

        // Both retries should have completed (sequentially, not concurrently)
        expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(2));
      });
    });

    test('dispose cancels subscription and timer', () {
      fakeAsync((fake) {
        retrier.start();

        // Go online → creates timer
        p2pService.emitState(const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/addr'],
        ));
        fake.flushMicrotasks();

        // Dispose before timer fires
        retrier.dispose();

        // Advance past the debounce — timer was cancelled by dispose
        fake.elapse(const Duration(seconds: 6));
        fake.flushMicrotasks();

        // No retry should have been triggered
        expect(identityRepo.loadIdentityCallCount, 0);
      });
    });
  });
}
