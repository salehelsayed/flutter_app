import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart'
    show SendChatMessageResult;
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';

// Reuse the canonical send-use-case test harness (fake p2pService + message
// repo + the sendChatMessage wrapper + flow-event capture) so these presence
// tests exercise the REAL send path. `show` avoids the duplicate `main` clash.
import 'send_chat_message_use_case_test.dart'
    show
        FakeP2PService,
        FakeMessageRepository,
        sendChatMessage,
        captureFlowEvents;

// FDC-08 C5/C6/C7 — the §6.3 presence emphasis at the send `unknownPresence`
// seam. Presence is a HINT, NEVER a delivery gate: the durable inbox ALWAYS
// fires (C5/C7); `unreachable` only commits the durable copy first (C6).

/// A send-path fake that adds a configurable [RelayPresence] (the optional
/// [RelayPresenceLookup] capability) and records inbox-vs-live ordering.
class _PresenceFake extends FakeP2PService implements RelayPresenceLookup {
  _PresenceFake({
    required this.presence,
    this.inboxDelay = Duration.zero,
    this.connected = false,
    super.sendMessageResult,
    super.storeInInboxResult,
    super.useNullDiscover,
  });

  final RelayPresence presence;
  final Duration inboxDelay;

  /// When true, the sender is already connected to the target → `unknownPresence`
  /// is false → the presence block is skipped entirely (TC-181-50 boundary).
  final bool connected;
  int presenceLookupCount = 0;

  /// Ordered completion/entry markers: 'inbox-call', 'inbox-done', 'live'.
  final List<String> order = [];

  @override
  Future<RelayPresence> lookupRelayPresence(String peerId) async {
    presenceLookupCount++;
    return presence;
  }

  @override
  bool isConnectedToPeer(String peerId) => connected;

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    order.add('inbox-call');
    final r = await super.storeInInbox(toPeerId, message, timeoutMs: timeoutMs);
    if (inboxDelay > Duration.zero) {
      await Future<void>.delayed(inboxDelay);
    }
    order.add('inbox-done');
    return r;
  }

  void _markLive() {
    if (!order.contains('live')) order.add('live');
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) {
    _markLive();
    return super.discoverPeer(peerId, timeoutMs: timeoutMs);
  }

  @override
  Future<bool> discoverLocalPeer(String peerId, {required Duration timeout}) {
    _markLive();
    return super.discoverLocalPeer(peerId, timeout: timeout);
  }
}

Map<String, dynamic>? _emphasis(List<Map<String, dynamic>> events) {
  for (final e in events) {
    if (e['event'] == 'CHAT_MSG_PRESENCE_EMPHASIS') return e;
  }
  return null;
}

bool _has(List<Map<String, dynamic>> events, String name) =>
    events.any((e) => e['event'] == name);

void main() {
  // C5 — reachable presence keeps the durable inbox deposit (lazy, NOT skipped).
  test(
    'reachable presence keeps the durable inbox deposit (lazy, not suppressed)',
    () async {
      final p2p = _PresenceFake(
        presence: RelayPresence.reachable,
        storeInInboxResult: true,
      );
      final repo = FakeMessageRepository();

      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: p2p,
          messageRepo: repo,
          targetPeerId: 'target-peer',
          text: 'hi',
          senderPeerId: 'me',
          senderUsername: 'Me',
        );
      });

      // The durable copy still fired even though the hint was reachable.
      expect(p2p.storeInInboxCallCount, greaterThanOrEqualTo(1));
      expect(p2p.presenceLookupCount, 1);
      final emphasis = _emphasis(events);
      expect(emphasis, isNotNull);
      expect((emphasis!['details'] as Map)['presence'], 'reachable');
    },
  );

  // C6 — unreachable presence commits the durable copy FIRST, then the live legs
  // (still run, best-effort).
  test(
    'unreachable presence commits inbox first then live (best-effort)',
    () async {
      final p2p = _PresenceFake(
        presence: RelayPresence.unreachable,
        inboxDelay: const Duration(milliseconds: 60),
        sendMessageResult: false, // live legs fail (peer is offline)
        storeInInboxResult: true,
      );
      final repo = FakeMessageRepository();

      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: p2p,
          messageRepo: repo,
          targetPeerId: 'target-peer',
          text: 'hi',
          senderPeerId: 'me',
          senderUsername: 'Me',
        );
      });

      final emphasis = _emphasis(events);
      expect((emphasis!['details'] as Map)['presence'], 'unreachable');
      expect(_has(events, 'CHAT_MSG_PRESENCE_INBOX_FIRST'), isTrue);

      // Ordering: the inbox deposit COMPLETED before any live leg started.
      final inboxDone = p2p.order.indexOf('inbox-done');
      final firstLive = p2p.order.indexOf('live');
      expect(inboxDone, greaterThanOrEqualTo(0));
      expect(
        firstLive,
        greaterThanOrEqualTo(0),
        reason: 'live legs must still run (best-effort), not be dropped',
      );
      expect(
        inboxDone,
        lessThan(firstLive),
        reason: 'unreachable => durable copy committed before the live race',
      );
    },
  );

  // C7 ⭐ — a WRONG `reachable` hint for an actually-offline peer STILL deposits
  // the durable copy (+ relay push-to-wake). The single load-bearing gate:
  // presence is a HINT, never a delivery gate.
  test(
    'reachable hint for an offline peer still deposits the durable copy',
    () async {
      final p2p = _PresenceFake(
        presence: RelayPresence.reachable, // WRONG hint
        sendMessageResult:
            false, // every live leg fails (peer is really offline)
        useNullDiscover: true, // direct discover yields nothing
        storeInInboxResult: true,
      );
      final repo = FakeMessageRepository();

      SendChatMessageResult? result;
      final events = await captureFlowEvents(() async {
        final (r, _) = await sendChatMessage(
          p2pService: p2p,
          messageRepo: repo,
          targetPeerId: 'target-peer',
          text: 'hi',
          senderPeerId: 'me',
          senderUsername: 'Me',
        );
        result = r;
      });

      // The hint was (wrongly) reachable...
      expect((_emphasis(events)!['details'] as Map)['presence'], 'reachable');
      // ...yet the PRESENCE-PATH durable copy STILL fired (lazy = fired, NOT
      // skipped). Asserting the concurrent BEGIN event — not just the deposit
      // count — keeps this load-bearing: it re-reds if the reachable branch ever
      // skips/defers the concurrent deposit, even though the :1172 backstop would
      // independently rescue the message. The store triggers the relay's
      // push-to-wake for the backgrounded peer.
      expect(_has(events, 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN'), isTrue);
      expect(p2p.storeInInboxCallCount, greaterThanOrEqualTo(1));
      // And the message is delivered (durable inbox custody), never lost.
      expect(result, SendChatMessageResult.success);
    },
  );

  // TC-181-32u — `unknown` presence emits EMPHASIS but NOT INBOX_FIRST: only
  // `unreachable` short-circuits; `unknown` keeps today's fully-concurrent
  // behavior. Discriminator: EMPHASIS present AND INBOX_FIRST absent (distinguishes
  // the two same-custody paths by event, not deposit count). Mutation: broaden the
  // consumer guard to include `unknown` (send_chat_message_use_case.dart:776) →
  // INBOX_FIRST appears → red.
  test('unknown presence emits EMPHASIS but not INBOX_FIRST', () async {
    final p2p = _PresenceFake(
      presence: RelayPresence.unknown,
      storeInInboxResult: true,
    );
    final repo = FakeMessageRepository();

    final events = await captureFlowEvents(() async {
      await sendChatMessage(
        p2pService: p2p,
        messageRepo: repo,
        targetPeerId: 'target-peer',
        text: 'hi',
        senderPeerId: 'me',
        senderUsername: 'Me',
      );
    });

    expect((_emphasis(events)!['details'] as Map)['presence'], 'unknown');
    expect(_has(events, 'CHAT_MSG_PRESENCE_INBOX_FIRST'), isFalse);
    // The durable copy still fires (fully-concurrent behavior unchanged).
    expect(p2p.storeInInboxCallCount, greaterThanOrEqualTo(1));
  });

  // TC-181-50 — a peer the sender is already connected to (`unknownPresence==false`)
  // NEVER enters the presence block: no EMPHASIS, presence never consulted — even
  // when the relay WOULD say `unreachable`. This is the out-of-scope stale-circuit
  // boundary (181 Known Limitation): presence wiring does not change connected-peer
  // sends. Mutation: drop the `!isConnectedToPeer` term from the unknownPresence
  // definition (send_chat_message_use_case.dart:704-707) → the connected peer
  // enters the block and emits EMPHASIS → red.
  test(
    'connected peer (unknownPresence=false) skips the presence block entirely',
    () async {
      final p2p = _PresenceFake(
        presence:
            RelayPresence.unreachable, // would short-circuit IF the block ran
        connected: true, // isConnectedToPeer => true → unknownPresence false
        storeInInboxResult: true,
      );
      final repo = FakeMessageRepository();

      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: p2p,
          messageRepo: repo,
          targetPeerId: 'target-peer',
          text: 'hi',
          senderPeerId: 'me',
          senderUsername: 'Me',
        );
      });

      // Block skipped: presence never consulted, no emphasis, no short-circuit.
      expect(_emphasis(events), isNull);
      expect(p2p.presenceLookupCount, 0);
      expect(_has(events, 'CHAT_MSG_PRESENCE_INBOX_FIRST'), isFalse);
    },
  );

  // -------------------------------------------------------------------------
  // 184 — optimistic 2-tick send-status progression: the concurrent-inbox ACK
  // surfaces a custody milestone MID-send (status:'inboxed' +
  // CHAT_MSG_SEND_CUSTODY_CONFIRMED) so the 1:1 bubble advances to two ticks at
  // ~110 ms instead of resting on the optimistic single tick until the race
  // resolves. INV-3 guards a live 'delivered' from being regressed to 'inboxed';
  // INV-4 keeps the single tick when custody is not secured.
  // -------------------------------------------------------------------------

  // TC-184-10 — the concurrent-inbox ACK persists a non-terminal 'inboxed'
  // mid-send AND emits CHAT_MSG_SEND_CUSTODY_CONFIRMED, distinct from (and
  // BEFORE) the terminal save. RED on HEAD: the `.then` only records a metric.
  test('custody-confirmed persists inboxed mid-send + emits CUSTODY_CONFIRMED '
      'before the terminal', () async {
    final p2p = _PresenceFake(
      presence: RelayPresence.unknown,
      sendMessageResult: false, // live legs fail (offline peer)
      useNullDiscover: true, // direct discover yields nothing
      storeInInboxResult: true, // the durable inbox ACKs
    );
    final repo = FakeMessageRepository();

    final events = await captureFlowEvents(() async {
      await sendChatMessage(
        p2pService: p2p,
        messageRepo: repo,
        targetPeerId: 'target-peer',
        text: 'hi',
        senderPeerId: 'me',
        senderUsername: 'Me',
      );
    });

    // The mid-send custody milestone fired...
    expect(_has(events, 'CHAT_MSG_SEND_CUSTODY_CONFIRMED'), isTrue);
    // ...and an atomic 'inboxed' settlement was applied at the ACK in addition
    // to the terminal custody settlement.
    expect(
      repo.ordinarySettlementCalls.where((call) => call.status == 'inboxed'),
      hasLength(greaterThanOrEqualTo(2)),
    );
    // Distinct-event discriminator: the custody bump STRICTLY precedes the
    // terminal timing event, so it is the mid-send milestone, not the terminal
    // 'inboxed' save (both carry status=='inboxed').
    final custodyIdx = events.indexWhere(
      (e) => e['event'] == 'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
    );
    final timingIdx = events.indexWhere(
      (e) => e['event'] == 'CHAT_MSG_SEND_TIMING',
    );
    expect(custodyIdx, greaterThanOrEqualTo(0));
    expect(timingIdx, greaterThanOrEqualTo(0));
    expect(
      custodyIdx,
      lessThan(timingIdx),
      reason:
          'custody-confirmed is the MID-send milestone — it must precede '
          'the terminal timing event',
    );
  });

  // TC-184-12 — a live 'delivered' that wins the race BEFORE the inbox ACK
  // resolves must NEVER be regressed to 'inboxed' by the late custody bump
  // (INV-3). Guard lock: passes on HEAD (no mid-send save exists),
  // mutation-verified by dropping the `!liveDelivered` guard.
  test(
    'live ack before inbox ack does not regress delivered to inboxed',
    () async {
      final p2p =
          _PresenceFake(
              presence: RelayPresence.unknown,
              inboxDelay: const Duration(
                milliseconds: 60,
              ), // ACK lands after race
              sendMessageResult: true,
              storeInInboxResult: true,
            )
            // The live leg is ACKed → terminal 'delivered' commits first.
            ..sendMessageAcked = true
            ..sendMessageTransport = 'direct';
      final repo = FakeMessageRepository();

      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: p2p,
          messageRepo: repo,
          targetPeerId: 'target-peer',
          text: 'hi',
          senderPeerId: 'me',
          senderUsername: 'Me',
        );
        // Let the delayed inbox `.then` fire — it must find liveDelivered=true
        // and skip the custody bump.
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });

      // The live delivery is the final persisted state...
      expect(repo.saved, isNotEmpty);
      expect(repo.saved.last.status, 'delivered');
      // ...and the late inbox ACK never advanced the status to 'inboxed' nor fired
      // the custody milestone (the guard suppressed it).
      expect(
        repo.ordinarySettlementCalls.any((call) => call.status == 'inboxed'),
        isFalse,
      );
      expect(_has(events, 'CHAT_MSG_SEND_CUSTODY_CONFIRMED'), isFalse);
    },
  );

  // TC-184-13 — an offline send (live legs fail) RESTS at 'inboxed' custody, and
  // the custody bump lands MID-send (an ADDITIONAL 'inboxed' write on top of the
  // terminal persist) so the bubble shows two ticks from ~110 ms, not after the
  // full race. RED on HEAD: only the single terminal 'inboxed' write exists.
  test('offline send rests at inboxed with a mid-send custody bump', () async {
    final p2p = _PresenceFake(
      presence: RelayPresence.unknown,
      sendMessageResult: false,
      useNullDiscover: true,
      storeInInboxResult: true,
    );
    final repo = FakeMessageRepository();

    final events = await captureFlowEvents(() async {
      await sendChatMessage(
        p2pService: p2p,
        messageRepo: repo,
        targetPeerId: 'target-peer',
        text: 'hi',
        senderPeerId: 'me',
        senderUsername: 'Me',
      );
    });

    // The bubble rests at custody (two ticks): the terminal persist writes the
    // full 'inboxed' custody row...
    expect(repo.saved.last.status, 'inboxed');
    // ...AND the mid-send bump advanced the status to 'inboxed' through an
    // additional atomic settlement before the terminal custody settlement.
    expect(
      repo.ordinarySettlementCalls.where((call) => call.status == 'inboxed'),
      hasLength(greaterThanOrEqualTo(2)),
    );
    expect(_has(events, 'CHAT_MSG_SEND_CUSTODY_CONFIRMED'), isTrue);
  });

  // TC-184-14 — if custody is NOT secured (inbox store returns false) the
  // mid-send bump must NOT fire: no false two-tick (INV-4). Guard lock: passes
  // on HEAD; mutation-verified by removing the `ok==true` guard.
  test(
    'inbox store failure keeps the single tick — no false custody bump',
    () async {
      final p2p = _PresenceFake(
        presence: RelayPresence.unknown,
        sendMessageResult: false,
        useNullDiscover: true,
        storeInInboxResult: false, // custody NOT secured
      );
      final repo = FakeMessageRepository();

      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: p2p,
          messageRepo: repo,
          targetPeerId: 'target-peer',
          text: 'hi',
          senderPeerId: 'me',
          senderUsername: 'Me',
        );
      });

      expect(_has(events, 'CHAT_MSG_SEND_CUSTODY_CONFIRMED'), isFalse);
      expect(
        repo.ordinarySettlementCalls.any((call) => call.status == 'inboxed'),
        isFalse,
      );
    },
  );
}
