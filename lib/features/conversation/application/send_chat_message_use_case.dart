import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/chat_console_logger.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

/// Interactive send budget for local WiFi attempts.
const Duration interactiveLocalBudget = Duration(milliseconds: 1500);

/// Interactive send budget for the overall direct send path.
const Duration interactiveDirectBudget = Duration(seconds: 2);

/// Interactive send budget for the inbox store fallback path.
const Duration interactiveInboxBudget = Duration(seconds: 3);

/// NET-REL-05 U-P5 (relay consolidation, Dart-only): after a successful relay
/// probe, make a SINGLE post-probe send attempt before inbox fallback.
/// Consolidated from 2 → 1: the direct race leg already invokes the same
/// relay-capable `message:send` (Go rides `WithAllowLimitedConn`), so the
/// second post-probe attempt was the redundant layer. The single retained
/// attempt still covers the online-relay-only peer whose address the direct
/// leg didn't discover (`peer_not_found` → relayProbeEligible) but who becomes
/// reachable once the probe establishes the circuit. The probe's unique value
/// — the `NO_RESERVATION` fast offline signal — is preserved.
/// (Moving full relay ownership into Go is OUT OF SCOPE this run: it requires
/// `make all` + `pod install` and is not host-verifiable; see
/// `05-send-orchestration-IMPLEMENTATION-PLAN.md` U-P5.)
const int relayProbeSendAttempts = 1;

/// Inter-attempt backoff for the post-probe send loop. With
/// [relayProbeSendAttempts] == 1 this is no longer exercised (the loop's
/// `attempt < relayProbeSendAttempts` guard skips it); retained so a future
/// re-widening of the loop keeps a defined backoff.
const Duration relayProbeRetryBackoff = Duration(milliseconds: 250);

/// NET-REL-05 P2 (grace window): after a non-preferred leg succeeds, wait this
/// long for a better-ranked transport (local > direct > relay) to land before
/// committing the worse one. Modest because the front race already starts both
/// legs simultaneously — only the ack-timing crossover matters. Hard-capped by
/// [interactiveDirectBudget] so the grace can never push past the direct budget.
const Duration transportGraceWindow = Duration(milliseconds: 150);

/// NET-REL-05 P3 head-start (consumed here in U-P2): hold a NON-learned leg's
/// win-eligibility this long so a recently-good (learned) transport tends to win
/// close ties without re-paying full discovery. Delays WIN-eligibility only —
/// never the leg's actual transport work — so a dead learned leg cannot stall
/// the send (the other leg still completes the race after the grace window).
/// Slightly under [transportGraceWindow] so a genuinely-alive learned leg wins
/// before the grace fires.
const Duration kStickyHeadStart = Duration(milliseconds: 120);

/// NET-REL-05 P1/P4 (concurrent durable fallback): a send is "low confidence"
/// when the most recent OUTGOING message to this peer terminally failed or was
/// only delivered via the inbox (peer was offline) within this window. For such
/// sends we fire [P2PService.storeInInbox] CONCURRENTLY with the live race (as
/// the group path does) so durable custody lands fast instead of waiting out the
/// sequential tail — receive-side messageId dedup discards the duplicate. Shares
/// the 30s horizon of NET-REL-01 `LocalPeer.ttl` so the reliability layers agree
/// on "recently failed/offline".
const Duration kLowConfidenceWindow = Duration(seconds: 30);

/// Transport preference rank for the grace window: higher wins. 'reuse' ranks
/// with 'direct' (both are a non-relay live connection); unknown ranks lowest.
int _transportRank(String? via) => switch (via) {
  'local' => 3,
  'direct' => 2,
  'reuse' => 2,
  'relay' => 1,
  _ => 0,
};

void _recordSuccessfulSendReadinessProof(
  P2PService p2pService,
  ConversationMessage message,
) {
  if (message.status != 'delivered') {
    return;
  }

  if (p2pService case final ReadinessProofRecorder recorder) {
    final sendPath = switch (message.transport) {
      'local' => 'local',
      'relay' => 'relay',
      'inbox' => 'inbox',
      'reuse' => 'direct',
      _ => 'direct',
    };
    final source = switch (sendPath) {
      'local' => 'chat_send_local',
      'relay' => 'chat_send_relay',
      'inbox' => 'chat_send_inbox',
      _ => 'chat_send_direct',
    };
    recorder.recordSuccessfulSendProof(
      source: source,
      trigger: 'user_action',
      sendPath: sendPath,
    );
  }
}

/// Result of sending a chat message.
enum SendChatMessageResult {
  success,
  nodeNotRunning,
  invalidMessage,
  encryptionRequired,
  peerNotFound,
  dialFailed,
  sendFailed,
}

const _uuid = Uuid();

/// Sends a chat message to a contact via P2P and persists it locally.
///
/// 1. Validates text is non-empty
/// 2. Checks P2P node is running
/// 3. Builds MessagePayload with UUID
/// 4. Serializes to a v2 encrypted JSON envelope
/// 5. Persists wireEnvelope to DB row (Section 4: crash-safe retryability)
/// 6. Reuses an existing connection, races local WiFi with direct relay send,
///    and probes the relay only when discoverability is stale
/// 7. Persists final status via messageRepo.saveMessage()
///
/// A live send that writes to the peer but does not receive an ACK attempts an
/// immediate durable inbox handoff. If the inbox handoff also fails, the
/// message is kept as truthful local `sent` state with the wire envelope
/// retained for later retry.
///
/// The wireEnvelope persist at step 5 ensures that if the app crashes during
/// the transport race (step 6), Section 1's PendingMessageRetrier can replay
/// the message without re-serializing or re-encrypting.
///
/// Returns (result, ConversationMessage?) — message is non-null on success or failure (persisted).
Future<(SendChatMessageResult, ConversationMessage?)> sendChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String action = MessagePayload.actionSend,
  String? editedAt,
  String? messageId,
  String? timestamp,
  String? createdAt,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
  TransportMetrics? transportMetrics,
}) async {
  final sendStopwatch = Stopwatch()..start();
  final targetPrefix = targetPeerId.length > 10
      ? targetPeerId.substring(0, 10)
      : targetPeerId;
  final sanitizedText = sanitizeMessageText(text);
  final hasAttachments =
      mediaAttachments != null && mediaAttachments.isNotEmpty;
  var connectionReused = false;
  var sendPath = 'unknown';
  Map<String, int> stepTimings = {};
  void emitSendTiming({
    required String outcome,
    Map<String, dynamic> details = const {},
  }) {
    if (!emitTimingEvent) return;
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_TIMING',
      details: {
        'elapsedMs': sendStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'hasAttachments': hasAttachments,
        'connectionReused': connectionReused,
        'sendPath': sendPath,
        ...stepTimings,
        ...details,
      },
    );
  }

  // NET-REL-04: record aggregate-only transport diagnostics at each terminal
  // send exit. Called exactly once per invocation (one rung per send).
  void recordMetrics({required String? transport, required String rung}) {
    transportMetrics?.recordRung(rung);
    transportMetrics?.recordSendLatency(
      transport: transport,
      latencyMs: sendStopwatch.elapsedMilliseconds,
    );
    if (transport != null) transportMetrics?.recordTransport(transport);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_START',
    details: {'targetPeerId': targetPrefix},
  );

  // 1. Validate
  if (sanitizedText.trim().isEmpty && !hasAttachments) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {'reason': 'empty_text'},
    );
    emitSendTiming(outcome: 'invalid_message');
    return (SendChatMessageResult.invalidMessage, null);
  }

  if (action == MessagePayload.actionEdit &&
      (messageId == null || timestamp == null || createdAt == null)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {'reason': 'edit_requires_existing_message_contract'},
    );
    emitSendTiming(outcome: 'invalid_message');
    return (SendChatMessageResult.invalidMessage, null);
  }

  // 2. Check P2P node
  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_NODE_NOT_RUNNING',
      details: {},
    );
    emitSendTiming(outcome: 'node_not_running');
    return (SendChatMessageResult.nodeNotRunning, null);
  }

  final recipientKey = recipientMlKemPublicKey?.trim();
  if (bridge == null || recipientKey == null || recipientKey.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_ENCRYPTION_REQUIRED',
      details: {
        'reason': bridge == null ? 'missing_bridge' : 'missing_recipient_key',
      },
    );
    emitSendTiming(
      outcome: 'encryption_required',
      details: {
        'reason': bridge == null ? 'missing_bridge' : 'missing_recipient_key',
      },
    );
    return (SendChatMessageResult.encryptionRequired, null);
  }

  // 3. Build payload
  final resolvedMessageId = messageId ?? _uuid.v4();
  final resolvedTimestamp =
      timestamp ?? DateTime.now().toUtc().toIso8601String();
  final resolvedEditedAt = action == MessagePayload.actionEdit
      ? (editedAt ?? DateTime.now().toUtc().toIso8601String())
      : null;
  final normalizedAttachments = mediaAttachments
      ?.map(
        (attachment) => attachment.copyWith(
          messageId: resolvedMessageId,
          createdAt: attachment.createdAt.isEmpty
              ? resolvedTimestamp
              : attachment.createdAt,
        ),
      )
      .toList();

  final payload = MessagePayload(
    id: resolvedMessageId,
    text: sanitizedText,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    timestamp: resolvedTimestamp,
    action: action,
    editedAt: resolvedEditedAt,
    quotedMessageId: quotedMessageId,
    media: normalizedAttachments
        ?.map((attachment) => attachment.toJson())
        .toList(),
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'queued',
    text: sanitizedText,
  );

  // 4. Serialize as v2 encrypted envelope.
  String jsonString;
  try {
    final innerJson = payload.toInnerJson();
    final encryptStopwatch = Stopwatch()..start();
    final encryptResult = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: recipientKey,
      plaintext: innerJson,
    );
    encryptStopwatch.stop();
    stepTimings['encryptMs'] = encryptStopwatch.elapsedMilliseconds;
    if (encryptResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_ENCRYPT_FAILED',
        details: {
          'errorCode': encryptResult['errorCode'],
          'errorMessage': encryptResult['errorMessage'],
        },
      );
      emitSendTiming(
        outcome: 'encrypt_failed',
        details: {'errorCode': encryptResult['errorCode']},
      );
      return (SendChatMessageResult.sendFailed, null);
    }
    jsonString = MessagePayload.buildEncryptedEnvelope(
      id: resolvedMessageId,
      senderPeerId: senderPeerId,
      senderUsername: senderUsername,
      kem: encryptResult['kem'] as String,
      ciphertext: encryptResult['ciphertext'] as String,
      nonce: encryptResult['nonce'] as String,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_ENCRYPT_ERROR',
      details: {'error': e.toString()},
    );
    emitSendTiming(outcome: 'encrypt_error');
    return (SendChatMessageResult.sendFailed, null);
  }

  logChatWireEnvelope(
    direction: 'OUT',
    messageId: resolvedMessageId,
    wireJson: jsonString,
  );

  // SECTION 4 CONTRACT: wireEnvelope is persisted BEFORE the transport race.
  // If the app crashes after this point, the DB row has wireEnvelope != null
  // and Section 1's PendingMessageRetrier can replay the message without
  // re-serializing or re-encrypting.
  if (messageId != null) {
    await messageRepo.updateWireEnvelope(messageId, jsonString);
  }

  // 4.5. Check for existing connected peer first (connection reuse).
  // If the peer is already connected, try to send directly without
  // rediscovering — this is the fastest interactive path.
  final isAlreadyConnected = p2pService.currentState.connections.any(
    (c) => c.peerId == targetPeerId,
  );

  if (isAlreadyConnected) {
    connectionReused = true;
    sendPath = 'reuse';
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_REUSE_CONNECTION',
      details: {'targetPeerId': targetPrefix},
    );
    try {
      final reuseSendStopwatch = Stopwatch()..start();
      final sendResult = await p2pService.sendMessageWithReply(
        targetPeerId,
        jsonString,
        timeoutMs: interactiveDirectBudget.inMilliseconds,
      );
      reuseSendStopwatch.stop();
      stepTimings = {
        'sendMs': reuseSendStopwatch.elapsedMilliseconds,
        if (sendResult.streamOpenMs != null)
          'streamOpenMs': sendResult.streamOpenMs!,
        if (sendResult.writeMs != null) 'writeMs': sendResult.writeMs!,
        if (sendResult.ackWaitMs != null) 'ackWaitMs': sendResult.ackWaitMs!,
      };
      if (sendResult.sent) {
        final reuseVia = _resolveGoSendTransport(
          p2pService,
          targetPeerId,
          sendResult,
          preserveLocalPeerLabel: true,
        );
        transportMetrics?.recordAttempt(leg: 'reuse', succeeded: true);
        recordMetrics(transport: reuseVia, rung: 'reuse');
        return _completeSuccessfulSend(
          p2pService: p2pService,
          messageRepo: messageRepo,
          payload: payload,
          targetPeerId: targetPeerId,
          jsonString: jsonString,
          acknowledged: sendResult.acknowledged,
          via: reuseVia,
          resolvedMessageId: resolvedMessageId,
          text: sanitizedText,
          createdAt: createdAt,
          editedAt: resolvedEditedAt,
          mediaAttachmentRepo: mediaAttachmentRepo,
          attachments: normalizedAttachments,
          sendStopwatch: sendStopwatch,
          emitTimingEvent: emitTimingEvent,
          extraTimingDetails: {
            'connectionReused': true,
            'sendPath': 'reuse',
            ...stepTimings,
          },
        );
      }
    } catch (_) {
      // Connection reuse failed — fall through to race
    }
    transportMetrics?.recordAttempt(leg: 'reuse', succeeded: false);
    connectionReused = false;
    sendPath = 'unknown';
    stepTimings = {};
  }

  // 5. Race: local WiFi and direct discover/dial/send in parallel.
  // The first successful path wins and is the only one to persist.
  final isLocalPeer = p2pService.isLocalPeer(targetPeerId);

  // NET-REL-05 P3 (sticky transport): the last-known-good LIVE transport for
  // this peer, or null if none/expired/stale. U-P3 lands only this MEMORY layer
  // (read + record + TTL/invalidate); the race-WEIGHTING that consumes [learned]
  // as a head-start is implemented in U-P2 where the completer is rewritten, so
  // here [learned] is read and surfaced for observability but does not yet
  // reorder the completer. Reading it never blocks: it returns null (full race,
  // identical to today) when expired or — for 'local' — no longer LAN-visible,
  // so a stale/dead preference can never trap the send.
  final learned = p2pService.lastKnownGoodTransport(targetPeerId);
  if (learned != null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_STICKY_TRANSPORT',
      details: {'targetPeerId': targetPrefix, 'learned': learned},
    );
  }

  // NET-REL-05 P1/P4 (concurrent durable fallback): decide whether this send is
  // "low confidence" — the peer is not connected (no live or reuse path), not on
  // the LAN, AND the most recent PRIOR outgoing message to this peer terminally
  // failed or only landed via the inbox within [kLowConfidenceWindow]. Such a
  // peer was recently unreachable, so we fire the durable inbox copy in parallel
  // with the live race below (instead of waiting out the sequential tail).
  //
  // Trap guarded: the optimistic 'sending' row for THIS message already exists
  // (created by the UI). The `last.id != resolvedMessageId` check plus the
  // terminal-status requirement ensure we inspect the PRIOR attempt, never the
  // in-flight row. High-confidence sends skip this entirely and stay single-path.
  var lowConfidence = false;
  if (!isAlreadyConnected &&
      !isLocalPeer &&
      !p2pService.isConnectedToPeer(targetPeerId)) {
    try {
      final last = await messageRepo.getLatestMessageForContact(targetPeerId);
      if (last != null &&
          !last.isIncoming &&
          last.id != resolvedMessageId &&
          (last.status == 'failed' || last.transport == 'inbox')) {
        final lastAt = DateTime.tryParse(last.createdAt);
        if (lastAt != null) {
          final age = DateTime.now().toUtc().difference(lastAt.toUtc());
          lowConfidence = !age.isNegative && age < kLowConfidenceWindow;
        }
      }
    } catch (_) {
      // A failed recency lookup must never block the send: stay high-confidence
      // (single-path) and let the live race + sequential tail carry it.
      lowConfidence = false;
    }
  }

  // Fire the durable inbox copy CONCURRENTLY (fire-and-forget) for low-confidence
  // sends only. This is a parallel durability side-effect, NOT a race
  // participant: it never feeds the transport-label completer and never calls a
  // terminal `recordMetrics(rung:...)` — only `recordAttempt(leg:'inbox')`. The
  // SAME [jsonString] envelope (identical payload.id) is used, so a duplicate
  // arrival is discarded by the receiver's messageId dedup. `concurrentInboxOk`
  // is awaited later (race-failure tail / unacked handoff) to short-circuit the
  // redundant sequential store and avoid a double relay write.
  Future<bool>? concurrentInbox;
  if (lowConfidence) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
      details: {'targetPeerId': targetPrefix},
    );
    concurrentInbox = p2pService
        .storeInInbox(
          targetPeerId,
          jsonString,
          timeoutMs: interactiveInboxBudget.inMilliseconds,
        )
        .then((ok) {
          transportMetrics?.recordAttempt(leg: 'inbox', succeeded: ok);
          return ok;
        })
        .catchError((_) => false);
  }

  // Build race futures
  final raceFutures = <Future<_RaceResult>>[];

  // Local WiFi path (bounded by interactiveLocalBudget). Added unconditionally:
  // when the peer is not yet in the discovered map we run a bounded
  // discover-on-send resolve first, so a cold-open same-WiFi peer can still
  // join the race within budget. If the peer is genuinely not on the LAN the
  // resolve times out to false and the parallel direct leg carries the message
  // (negative control: transport never becomes 'local').
  raceFutures.add(
    _tryLocalSendWithDiscovery(
      p2pService,
      targetPeerId,
      jsonString,
      senderPeerId,
      alreadyLocal: isLocalPeer,
      budget: interactiveLocalBudget,
      transportMetrics: transportMetrics,
    ).timeout(
      interactiveLocalBudget,
      onTimeout: () => _RaceResult.failed('local_discover_timeout'),
    ),
  );

  // Direct discover/dial/send path (bounded by interactiveDirectBudget).
  // Records its own attempt outcome inside the helper (at each terminal
  // return): the race completes on the first success, so a losing direct leg
  // may still be pending here and the caller cannot observe its result. The
  // outer timeout below does not record — the inner future resolves via its own
  // per-step budgets and records the real outcome exactly once (slightly later
  // on a slow path, which is fine for an aggregate session counter).
  raceFutures.add(
    _tryDirectSend(
      p2pService,
      targetPeerId,
      jsonString,
      transportMetrics: transportMetrics,
    ).timeout(
      interactiveDirectBudget,
      onTimeout: () => _RaceResult.failed('direct_timeout'),
    ),
  );

  // Race: best successful result within a grace window wins (NET-REL-05 P2).
  //
  // Unlike a pure first-wins completer, we prefer a better-ranked transport
  // (local > direct > relay) when it lands within [transportGraceWindow] of a
  // worse one: the front race already starts both legs simultaneously, so the
  // only window where a "worse" leg beats a "better" one is the few-ms
  // ack-timing crossover. On the first non-top success we arm a single grace
  // timer and commit the best result seen when it fires (or immediately on a
  // top-rank success / once all legs have resolved).
  //
  // U-P3 head-start consumption (P3 weighting): when [learned] names a
  // transport, the matching leg's success is offered to `best` immediately
  // while the OTHER leg's success is held back by [kStickyHeadStart] so a
  // genuinely-alive learned transport tends to win close ties. The head-start
  // gates WIN-eligibility only — the leg's transport work always proceeds — so
  // a dead learned leg can never stall the send (the other leg still completes
  // the race after the grace window). When [learned] is null every leg is
  // immediately eligible (degenerates to grace-only behavior).
  final completer = Completer<_RaceResult>();
  var pendingCount = raceFutures.length;
  final failures = <_RaceResult>[];
  _RaceResult? best;
  Timer? graceTimer;
  // Tracks whether a leg with WIN-eligibility strictly better than the current
  // [best] could still arrive. The local leg (raceFutures[0], rank 3) is the
  // only transport that can outrank a 'direct'/'reuse' best; while its
  // head-start delay is in flight a local win is still possible, so we keep it
  // "pending" until that delay (or its failure) resolves.
  var localLegEligibilityPending = true;
  // Number of SUCCESSFUL leg results that have resolved but whose win-offer is
  // still buffered behind a [kStickyHeadStart] delay. A leg counts here once it
  // has decremented [pendingCount] but not yet been offered to [best]. The
  // failure path must NOT settle the race as a failure while such a buffered
  // success exists — otherwise a learned-leg failure that resolves first would
  // drop a genuinely-alive non-learned success (U-N2: dead learned leg must not
  // trap the send).
  var deferredSuccessOffers = 0;

  void completeWithBest() {
    if (best != null && !completer.isCompleted) {
      graceTimer?.cancel();
      completer.complete(best);
    }
  }

  void completeWithFailure() {
    if (completer.isCompleted) return;
    var failureReason = failures.isNotEmpty
        ? failures.first.reason ?? 'unknown'
        : 'unknown';
    var relayProbeEligible = false;
    for (final failure in failures) {
      if (failure.relayProbeEligible) {
        failureReason = failure.reason ?? failureReason;
        relayProbeEligible = true;
        break;
      }
    }
    graceTimer?.cancel();
    completer.complete(
      _RaceResult.failed(failureReason, relayProbeEligible: relayProbeEligible),
    );
  }

  // True when no still-eligible leg could outrank the current [best].
  bool noPendingLegCanBeatBest() {
    if (best == null) return false;
    if (pendingCount <= 0 && !localLegEligibilityPending) return true;
    // The only transport that can exceed 'direct'/'reuse'/'relay' is local.
    return !localLegEligibilityPending || _transportRank(best!.via) >= 3;
  }

  // Offers a successful leg result (now WIN-eligible) to the best-within-grace
  // accumulator. May be invoked after a [kStickyHeadStart] head-start delay;
  // guards against a completer that already settled (e.g. grace fired, or a
  // learned-leg win already committed).
  void offerSuccess(_RaceResult result) {
    if (completer.isCompleted) return;
    if (best == null ||
        _transportRank(result.via) > _transportRank(best!.via)) {
      best = result;
    }
    // A learned-transport win is decisive: it is both the preferred transport
    // and confirmed alive, so commit it immediately (the head-start delayed the
    // other leg's eligibility precisely so this can win the close tie).
    final isLearnedWin = learned != null && best!.via == learned;
    if (isLearnedWin || noPendingLegCanBeatBest()) {
      completeWithBest();
      return;
    }
    // A worse leg landed first and a better-ranked leg is still in play: arm a
    // single grace timer, hard-capped so the total never exceeds the direct
    // budget (fire immediately if the budget is nearly spent).
    if (graceTimer == null) {
      final remaining = interactiveDirectBudget - sendStopwatch.elapsed;
      final graceDuration = remaining <= Duration.zero
          ? Duration.zero
          : (remaining < transportGraceWindow
                ? remaining
                : transportGraceWindow);
      graceTimer = Timer(graceDuration, completeWithBest);
    }
  }

  // Wire each leg. Index 0 is the local leg (see [localLegEligibilityPending]).
  for (var i = 0; i < raceFutures.length; i++) {
    final isLocalLeg = i == 0;
    void onResolved(_RaceResult result) {
      pendingCount--;
      if (!result.success) {
        failures.add(result);
        // A failed local leg can no longer produce a top-rank win.
        if (isLocalLeg) localLegEligibilityPending = false;
        if (best != null) {
          if (noPendingLegCanBeatBest()) completeWithBest();
        } else if (pendingCount <= 0 && deferredSuccessOffers <= 0) {
          // Only a failure when no leg succeeded AND none is buffered behind a
          // head-start. A buffered success will offer itself (and complete the
          // race) when its delay fires.
          completeWithFailure();
        }
        return;
      }

      // Head-start (U-P3 consumption): the learned leg's success is WIN-eligible
      // immediately; a non-learned leg is held back by [kStickyHeadStart] so a
      // genuinely-alive learned transport wins close ties. The head-start gates
      // WIN-eligibility ONLY — the leg's transport work already completed — so a
      // dead learned leg can never stall the send (the surviving leg becomes
      // eligible after the delay and the race proceeds normally). When
      // [learned] is null every leg is immediately eligible (grace-only).
      final isLearnedLeg = learned != null && result.via == learned;
      if (learned != null && !isLearnedLeg) {
        // Buffer this success behind the head-start. Tracked so a concurrent
        // failure of the other leg cannot prematurely settle the race as failed
        // and drop this still-alive success.
        deferredSuccessOffers++;
        Future<void>.delayed(kStickyHeadStart, () {
          deferredSuccessOffers--;
          if (isLocalLeg) localLegEligibilityPending = false;
          offerSuccess(result);
          // After this (final) offer, if the race has fully resolved with no
          // better leg possible, commit the best now rather than wait out grace.
          if (best != null && noPendingLegCanBeatBest()) completeWithBest();
        });
      } else {
        if (isLocalLeg) localLegEligibilityPending = false;
        offerSuccess(result);
      }
    }

    raceFutures[i]
        .then(onResolved)
        .catchError((Object e) => onResolved(_RaceResult.failed(e.toString())));
  }

  final raceResult = await completer.future;
  graceTimer?.cancel();

  if (raceResult.success) {
    sendPath = raceResult.via == 'local' ? 'local' : 'direct';
    stepTimings = raceResult.stepTimings;
    recordMetrics(transport: raceResult.via, rung: sendPath);
    return _completeSuccessfulSend(
      p2pService: p2pService,
      messageRepo: messageRepo,
      payload: payload,
      targetPeerId: targetPeerId,
      jsonString: jsonString,
      acknowledged: raceResult.acknowledged,
      via: raceResult.via!,
      resolvedMessageId: resolvedMessageId,
      text: sanitizedText,
      createdAt: createdAt,
      editedAt: resolvedEditedAt,
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: normalizedAttachments,
      sendStopwatch: sendStopwatch,
      emitTimingEvent: emitTimingEvent,
      // A live leg won the transport label. If a concurrent inbox copy was
      // fired for this low-confidence send, hand its future to the unacked
      // branch so the sequential unacked->inbox handoff is skipped when the
      // durable copy already succeeded (avoids a second relay write for one
      // message). When acked, the future is ignored (no handoff runs).
      concurrentInbox: concurrentInbox,
      extraTimingDetails: {
        'connectionReused': false,
        'sendPath': sendPath,
        ...stepTimings,
      },
    );
  }

  var failureReason = raceResult.reason ?? 'unknown';

  // Persist a durable-custody (inbox) success. Shared by the concurrent-fallback
  // short-circuit below and the sequential inbox tail so the terminal
  // `recordMetrics(rung:'inbox')` and status write stay identical and fire
  // exactly once.
  Future<(SendChatMessageResult, ConversationMessage)> persistInboxDelivered({
    required bool recordInboxAttempt,
  }) async {
    sendPath = 'inbox';
    if (recordInboxAttempt) {
      transportMetrics?.recordAttempt(leg: 'inbox', succeeded: true);
    }
    recordMetrics(transport: 'inbox', rung: 'inbox');
    final deliveredMessage = payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: 'delivered',
      createdAt: createdAt,
      editedAt: resolvedEditedAt,
      transport: 'inbox',
    );
    await messageRepo.saveMessage(deliveredMessage);
    await _persistOutgoingMedia(
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: normalizedAttachments,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_SUCCESS',
      details: {
        'id': resolvedMessageId.substring(0, 8),
        'status': 'delivered',
        'via': 'inbox',
      },
    );
    emitSendTiming(
      outcome: 'success',
      details: {'status': 'delivered', 'via': 'inbox'},
    );
    logChatOutgoing(
      messageId: resolvedMessageId,
      toPeerId: targetPeerId,
      status: 'delivered',
      text: sanitizedText,
    );
    _recordSuccessfulSendReadinessProof(p2pService, deliveredMessage);
    return (
      SendChatMessageResult.success,
      deliveredMessage.copyWith(media: normalizedAttachments ?? const []),
    );
  }

  // NET-REL-05 P1/P4: the live race failed. If a concurrent durable copy was
  // fired for this low-confidence send, wait for it before paying for the
  // sequential relay-probe + inbox tail. If it already took custody, commit
  // 'delivered'/'inbox' and SKIP the redundant tail entirely (no relay probe,
  // no second `storeInInbox`) — this is the latency win: durable custody lands
  // at ~inbox budget instead of after the full sequential tail. The inbox
  // `recordAttempt` already fired inside the concurrent future, so we do NOT
  // record it again here.
  if (concurrentInbox != null) {
    final concurrentOk = await concurrentInbox;
    if (concurrentOk) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY',
        details: {'reason': failureReason},
      );
      return persistInboxDelivered(recordInboxAttempt: false);
    }
  }

  if (raceResult.relayProbeEligible) {
    final relayProbeResult = await _tryRelayProbeSend(
      p2pService,
      targetPeerId,
      jsonString,
      failureReason: failureReason,
    );
    transportMetrics?.recordAttempt(
      leg: 'relay_probe',
      succeeded: relayProbeResult.success,
    );
    if (relayProbeResult.success) {
      sendPath = 'relay';
      stepTimings = {...stepTimings, ...relayProbeResult.stepTimings};
      recordMetrics(transport: relayProbeResult.via, rung: 'relay');
      return _completeSuccessfulSend(
        p2pService: p2pService,
        messageRepo: messageRepo,
        payload: payload,
        targetPeerId: targetPeerId,
        jsonString: jsonString,
        acknowledged: relayProbeResult.acknowledged,
        via: relayProbeResult.via!,
        resolvedMessageId: resolvedMessageId,
        text: sanitizedText,
        createdAt: createdAt,
        editedAt: resolvedEditedAt,
        mediaAttachmentRepo: mediaAttachmentRepo,
        attachments: normalizedAttachments,
        sendStopwatch: sendStopwatch,
        emitTimingEvent: emitTimingEvent,
        concurrentInbox: concurrentInbox,
        extraTimingDetails: {
          'connectionReused': false,
          'sendPath': 'relay',
          ...stepTimings,
        },
      );
    }
    failureReason = relayProbeResult.reason ?? failureReason;
  }

  // All active paths failed — try offline inbox fallback once.
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_RACE_ALL_FAILED',
    details: {'reason': failureReason},
  );

  try {
    final inboxStopwatch = Stopwatch()..start();
    final storedInInbox = await p2pService.storeInInbox(
      targetPeerId,
      jsonString,
      timeoutMs: interactiveInboxBudget.inMilliseconds,
    );
    inboxStopwatch.stop();
    stepTimings['inboxMs'] = inboxStopwatch.elapsedMilliseconds;
    if (storedInInbox) {
      return persistInboxDelivered(recordInboxAttempt: true);
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INBOX_FALLBACK_ERROR',
      details: {'error': e.toString()},
    );
  }

  // Inbox fallback failed — persist with failed status.
  final failedMessage = payload.toConversationMessage(
    contactPeerId: targetPeerId,
    isIncoming: false,
    status: 'failed',
    createdAt: createdAt,
    editedAt: resolvedEditedAt,
    wireEnvelope: jsonString,
  );
  await messageRepo.saveMessage(failedMessage);
  await _persistOutgoingMedia(
    mediaAttachmentRepo: mediaAttachmentRepo,
    attachments: normalizedAttachments,
  );

  // Reached only after an inbox store attempt that did not succeed (returned
  // false or threw): count the failed inbox attempt before the terminal rung.
  transportMetrics?.recordAttempt(leg: 'inbox', succeeded: false);
  recordMetrics(transport: null, rung: 'failed');

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_FAILED',
    details: {'id': resolvedMessageId.substring(0, 8), 'reason': failureReason},
  );
  emitSendTiming(
    outcome: 'failed',
    details: {
      'reason': failureReason,
      'result': _resultForFailureReason(failureReason).name,
    },
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'failed',
    text: sanitizedText,
  );
  return (
    _resultForFailureReason(failureReason),
    failedMessage.copyWith(media: normalizedAttachments ?? const []),
  );
}

Future<(SendChatMessageResult, ConversationMessage?)> editChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage originalMessage,
  required String updatedText,
  required String senderUsername,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
  TransportMetrics? transportMetrics,
}) {
  if (originalMessage.isIncoming) {
    return Future.value((SendChatMessageResult.invalidMessage, null));
  }
  if (originalMessage.status == 'failed') {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_EDIT_INVALID',
      details: {'reason': 'failed_message_requires_retry'},
    );
    return Future.value((SendChatMessageResult.invalidMessage, null));
  }

  return sendChatMessage(
    p2pService: p2pService,
    messageRepo: messageRepo,
    targetPeerId: originalMessage.contactPeerId,
    text: updatedText,
    senderPeerId: originalMessage.senderPeerId,
    senderUsername: senderUsername,
    action: MessagePayload.actionEdit,
    messageId: originalMessage.id,
    timestamp: originalMessage.timestamp,
    createdAt: originalMessage.createdAt,
    quotedMessageId: originalMessage.quotedMessageId,
    mediaAttachments: originalMessage.media,
    mediaAttachmentRepo: mediaAttachmentRepo,
    bridge: bridge,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    emitTimingEvent: emitTimingEvent,
    transportMetrics: transportMetrics,
  );
}

/// Internal result of a single send path in the race.
class _RaceResult {
  final bool success;
  final bool acknowledged;
  final String? via;
  final String? reason;
  final bool relayProbeEligible;
  final Map<String, int> stepTimings;

  const _RaceResult._({
    required this.success,
    this.acknowledged = false,
    this.via,
    this.reason,
    this.relayProbeEligible = false,
    this.stepTimings = const {},
  });

  factory _RaceResult.succeeded({
    required String via,
    bool acknowledged = false,
    Map<String, int> stepTimings = const {},
  }) => _RaceResult._(
    success: true,
    acknowledged: acknowledged,
    via: via,
    stepTimings: stepTimings,
  );

  factory _RaceResult.failed(
    String reason, {
    bool relayProbeEligible = false,
    Map<String, int> stepTimings = const {},
  }) => _RaceResult._(
    success: false,
    reason: reason,
    relayProbeEligible: relayProbeEligible,
    stepTimings: stepTimings,
  );
}

String _inferTransportForConnectedPeer(P2PService p2pService, String peerId) {
  if (p2pService.isLocalPeer(peerId)) {
    return 'local';
  }

  return _inferDirectVsRelayForConnectedPeer(p2pService, peerId);
}

String _inferDirectVsRelayForConnectedPeer(
  P2PService p2pService,
  String peerId,
) {
  final hasRelayConnection = p2pService.currentState.connections.any(
    (connection) =>
        connection.peerId == peerId &&
        connection.multiaddrs.any(
          (multiaddr) => multiaddr.contains('/p2p-circuit'),
        ),
  );
  return hasRelayConnection ? 'relay' : 'direct';
}

String _resolveGoSendTransport(
  P2PService p2pService,
  String peerId,
  SendMessageResult sendResult, {
  bool preserveLocalPeerLabel = false,
}) {
  if (preserveLocalPeerLabel && p2pService.isLocalPeer(peerId)) {
    return 'local';
  }

  final actualTransport = sendResult.transport;
  if (actualTransport != null && actualTransport.isNotEmpty) {
    return actualTransport;
  }

  if (preserveLocalPeerLabel) {
    return _inferTransportForConnectedPeer(p2pService, peerId);
  }

  return _inferDirectVsRelayForConnectedPeer(p2pService, peerId);
}

/// Try sending via local WiFi, running a bounded discover-on-send resolve first
/// when the peer was not already in the discovered map.
///
/// Self-bounded to [budget] (the caller also `.timeout`-wraps it), so this leg
/// can never delay the unconditional direct leg beyond the local budget. A peer
/// genuinely not on the LAN resolves to false and returns a failed result —
/// the direct leg then wins and transport is never `local`.
Future<_RaceResult> _tryLocalSendWithDiscovery(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
  String senderPeerId, {
  required bool alreadyLocal,
  required Duration budget,
  TransportMetrics? transportMetrics,
}) async {
  final sw = Stopwatch()..start();
  if (!alreadyLocal) {
    final found = await p2pService.discoverLocalPeer(
      targetPeerId,
      timeout: budget,
    );
    if (!found) {
      transportMetrics?.recordAttempt(leg: 'local', succeeded: false);
      return _RaceResult.failed(
        'local_not_discovered',
        stepTimings: {'localDiscoverMs': sw.elapsedMilliseconds},
      );
    }
  }
  final remaining = budget.inMilliseconds - sw.elapsedMilliseconds;
  return _tryLocalSend(
    p2pService,
    targetPeerId,
    jsonString,
    senderPeerId,
    timeoutMs: remaining > 0 ? remaining : 1,
    transportMetrics: transportMetrics,
  );
}

/// Try sending via local WiFi.
Future<_RaceResult> _tryLocalSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
  String senderPeerId, {
  required int timeoutMs,
  TransportMetrics? transportMetrics,
}) async {
  final localStopwatch = Stopwatch()..start();
  final localSent = await p2pService.sendLocalMessage(
    targetPeerId,
    jsonString,
    senderPeerId,
    timeoutMs: timeoutMs,
  );
  localStopwatch.stop();
  final timings = {'localSendMs': localStopwatch.elapsedMilliseconds};
  transportMetrics?.recordAttempt(leg: 'local', succeeded: localSent);
  if (localSent) {
    return _RaceResult.succeeded(
      via: 'local',
      acknowledged: true,
      stepTimings: timings,
    );
  }
  return _RaceResult.failed('local_send_failed', stepTimings: timings);
}

/// Try direct discover → dial → send path, recording one `direct` attempt
/// outcome for the transport census regardless of which leg ultimately wins the
/// race. Records exactly once, on the real outcome of the inner attempt.
Future<_RaceResult> _tryDirectSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  TransportMetrics? transportMetrics,
}) async {
  final result = await _tryDirectSendInner(p2pService, targetPeerId, jsonString);
  transportMetrics?.recordAttempt(leg: 'direct', succeeded: result.success);
  return result;
}

Future<_RaceResult> _tryDirectSendInner(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
) async {
  final budgetMs = interactiveDirectBudget.inMilliseconds;
  final timings = <String, int>{};

  // Discover
  final discoverStopwatch = Stopwatch()..start();
  final peer = await p2pService.discoverPeer(targetPeerId, timeoutMs: budgetMs);
  discoverStopwatch.stop();
  timings['discoverMs'] = discoverStopwatch.elapsedMilliseconds;
  if (peer == null) {
    return _RaceResult.failed(
      'peer_not_found',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }

  // Dial
  final dialStopwatch = Stopwatch()..start();
  final dialed = await p2pService.dialPeer(
    targetPeerId,
    addresses: peer.addresses,
    timeoutMs: budgetMs,
  );
  dialStopwatch.stop();
  timings['dialMs'] = dialStopwatch.elapsedMilliseconds;
  if (!dialed) {
    return _RaceResult.failed(
      'dial_failed',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }

  // Send
  final sendStepStopwatch = Stopwatch()..start();
  final sendResult = await p2pService.sendMessageWithReply(
    targetPeerId,
    jsonString,
    timeoutMs: budgetMs,
  );
  sendStepStopwatch.stop();
  timings['sendMs'] = sendStepStopwatch.elapsedMilliseconds;
  if (sendResult.streamOpenMs != null) {
    timings['streamOpenMs'] = sendResult.streamOpenMs!;
  }
  if (sendResult.writeMs != null) {
    timings['writeMs'] = sendResult.writeMs!;
  }
  if (sendResult.ackWaitMs != null) {
    timings['ackWaitMs'] = sendResult.ackWaitMs!;
  }
  if (!sendResult.sent) {
    return _RaceResult.failed('send_failed', stepTimings: timings);
  }

  return _RaceResult.succeeded(
    via: _resolveGoSendTransport(p2pService, targetPeerId, sendResult),
    acknowledged: sendResult.acknowledged,
    stepTimings: timings,
  );
}

Future<_RaceResult> _tryRelayProbeSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required String failureReason,
}) async {
  final relayProbeStopwatch = Stopwatch()..start();
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_RELAY_PROBE_BEGIN',
    details: {'reason': failureReason},
  );

  RelayProbeResult probeResult;
  try {
    probeResult = await p2pService.probeRelay(targetPeerId);
  } catch (e) {
    relayProbeStopwatch.stop();
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_RELAY_PROBE_ERROR',
      details: {'error': e.toString()},
    );
    return _RaceResult.failed(
      failureReason,
      stepTimings: {'relayProbeMs': relayProbeStopwatch.elapsedMilliseconds},
    );
  }

  switch (probeResult) {
    case RelayProbeResult.connected:
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_RELAY_PROBE_CONNECTED',
        details: {},
      );
      try {
        final dialed = await p2pService.dialPeer(
          targetPeerId,
          timeoutMs: interactiveDirectBudget.inMilliseconds,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_RELAY_PROBE_DIAL',
          details: {'dialed': dialed},
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_RELAY_PROBE_DIAL_ERROR',
          details: {'error': e.toString()},
        );
      }
      for (var attempt = 1; attempt <= relayProbeSendAttempts; attempt++) {
        try {
          final sendResult = await p2pService.sendMessageWithReply(
            targetPeerId,
            jsonString,
            timeoutMs: interactiveDirectBudget.inMilliseconds,
          );
          if (sendResult.sent) {
            relayProbeStopwatch.stop();
            return _RaceResult.succeeded(
              via: _resolveGoSendTransport(
                p2pService,
                targetPeerId,
                sendResult,
              ),
              acknowledged: sendResult.acknowledged,
              stepTimings: {
                'relayProbeMs': relayProbeStopwatch.elapsedMilliseconds,
                if (sendResult.streamOpenMs != null)
                  'streamOpenMs': sendResult.streamOpenMs!,
                if (sendResult.writeMs != null) 'writeMs': sendResult.writeMs!,
                if (sendResult.ackWaitMs != null)
                  'ackWaitMs': sendResult.ackWaitMs!,
              },
            );
          }

          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_SEND_RELAY_PROBE_SEND_RETRY',
            details: {
              'attempt': attempt,
              'maxAttempts': relayProbeSendAttempts,
            },
          );
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_SEND_RELAY_PROBE_SEND_ERROR',
            details: {
              'attempt': attempt,
              'maxAttempts': relayProbeSendAttempts,
              'error': e.toString(),
            },
          );
        }

        if (attempt < relayProbeSendAttempts) {
          await Future<void>.delayed(relayProbeRetryBackoff);
        }
      }
      relayProbeStopwatch.stop();
      return _RaceResult.failed(
        'send_failed',
        stepTimings: {'relayProbeMs': relayProbeStopwatch.elapsedMilliseconds},
      );
    case RelayProbeResult.noReservation:
      relayProbeStopwatch.stop();
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_RELAY_PROBE_NO_RESERVATION',
        details: {},
      );
      return _RaceResult.failed(
        'peer_not_found',
        stepTimings: {'relayProbeMs': relayProbeStopwatch.elapsedMilliseconds},
      );
    case RelayProbeResult.error:
      relayProbeStopwatch.stop();
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_RELAY_PROBE_FALLBACK',
        details: {'reason': failureReason},
      );
      return _RaceResult.failed(
        failureReason,
        stepTimings: {'relayProbeMs': relayProbeStopwatch.elapsedMilliseconds},
      );
  }
}

Future<void> _persistOutgoingMedia({
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<MediaAttachment>? attachments,
}) async {
  if (mediaAttachmentRepo == null ||
      attachments == null ||
      attachments.isEmpty) {
    return;
  }

  final messageIds = attachments
      .map((attachment) => attachment.messageId)
      .where((messageId) => messageId.isNotEmpty)
      .toSet();
  if (messageIds.length == 1) {
    final messageId = messageIds.first;
    final expectedIds = attachments.map((attachment) => attachment.id).toSet();
    final existing = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
    );
    final hasStaleUploadPending = existing.any(
      (attachment) =>
          attachment.downloadStatus == 'upload_pending' &&
          !expectedIds.contains(attachment.id),
    );
    if (hasStaleUploadPending) {
      await mediaAttachmentRepo.deleteAttachmentsForMessage(messageId);
    }
  }

  for (final attachment in attachments) {
    await mediaAttachmentRepo.saveAttachment(attachment);
  }
}

Future<(SendChatMessageResult, ConversationMessage)> _completeSuccessfulSend({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required MessagePayload payload,
  required String targetPeerId,
  required String jsonString,
  required bool acknowledged,
  required String via,
  required String resolvedMessageId,
  required String text,
  required String? createdAt,
  required String? editedAt,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<MediaAttachment>? attachments,
  required Stopwatch sendStopwatch,
  required bool emitTimingEvent,
  Future<bool>? concurrentInbox,
  Map<String, dynamic> extraTimingDetails = const {},
}) async {
  final message = await _persistOutgoingSendResult(
    p2pService: p2pService,
    payload: payload,
    targetPeerId: targetPeerId,
    jsonString: jsonString,
    acknowledged: acknowledged,
    createdAt: createdAt,
    editedAt: editedAt,
    via: via,
    concurrentInbox: concurrentInbox,
  );
  await messageRepo.saveMessage(message);
  await _persistOutgoingMedia(
    mediaAttachmentRepo: mediaAttachmentRepo,
    attachments: attachments,
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_SUCCESS',
    details: {
      'id': resolvedMessageId.substring(0, 8),
      'status': message.status,
      'via': message.transport,
    },
  );
  if (emitTimingEvent) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_TIMING',
      details: {
        'elapsedMs': sendStopwatch.elapsedMilliseconds,
        'outcome': 'success',
        'messageId': resolvedMessageId.substring(0, 8),
        'hasAttachments': attachments != null && attachments.isNotEmpty,
        'status': message.status,
        'via': message.transport,
        ...extraTimingDetails,
      },
    );
  }
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: message.status,
    text: text,
  );
  _recordSuccessfulSendReadinessProof(p2pService, message);
  // NET-REL-05 P3 (sticky transport): remember the LIVE transport that just
  // delivered so a repeat send to this peer can be weighted toward it (head-
  // start consumed in U-P2). Only acked LIVE deliveries qualify — 'inbox' is a
  // custody handoff, not a live transport, and `recordSuccessfulTransport`
  // ignores it anyway. This single success funnel covers connection reuse,
  // race-win, and relay-probe-win; the dedicated inbox tail and the
  // unacked->inbox handoff intentionally do not record.
  if (message.status == 'delivered' && message.transport != 'inbox') {
    p2pService.recordSuccessfulTransport(targetPeerId, message.transport ?? '');
  }
  return (
    SendChatMessageResult.success,
    message.copyWith(media: attachments ?? const []),
  );
}

SendChatMessageResult _resultForFailureReason(String? reason) {
  return switch (reason) {
    'peer_not_found' => SendChatMessageResult.peerNotFound,
    'dial_failed' => SendChatMessageResult.dialFailed,
    _ => SendChatMessageResult.sendFailed,
  };
}

Future<ConversationMessage> _persistOutgoingSendResult({
  required P2PService p2pService,
  required MessagePayload payload,
  required String targetPeerId,
  required String jsonString,
  required bool acknowledged,
  required String? createdAt,
  required String? editedAt,
  required String via,
  Future<bool>? concurrentInbox,
}) async {
  if (acknowledged) {
    return payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: 'delivered',
      createdAt: createdAt,
      editedAt: editedAt,
      transport: via,
    );
  }

  // NET-REL-05 P1/P4: the live write was unacked. If a concurrent durable copy
  // was fired for this low-confidence send and already took custody, settle as
  // 'delivered'/'inbox' WITHOUT a second sequential `storeInInbox` — one message
  // must never produce two relay writes (R1 guard). `concurrentInbox` resolves
  // to false on failure/timeout, in which case we fall through to the normal
  // sequential handoff below.
  if (concurrentInbox != null) {
    final concurrentOk = await concurrentInbox;
    if (concurrentOk) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_UNACKED_CONCURRENT_INBOX_CUSTODY',
        details: {'via': via},
      );
      return payload.toConversationMessage(
        contactPeerId: targetPeerId,
        isIncoming: false,
        status: 'delivered',
        createdAt: createdAt,
        editedAt: editedAt,
        transport: 'inbox',
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_BEGIN',
    details: {'via': via},
  );
  try {
    final storedInInbox = await p2pService.storeInInbox(
      targetPeerId,
      jsonString,
      timeoutMs: interactiveInboxBudget.inMilliseconds,
    );
    if (storedInInbox) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_SUCCESS',
        details: {'via': via},
      );
      return payload.toConversationMessage(
        contactPeerId: targetPeerId,
        isIncoming: false,
        status: 'delivered',
        createdAt: createdAt,
        editedAt: editedAt,
        transport: 'inbox',
      );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_FAILED',
      details: {'via': via, 'reason': 'store_returned_false'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_ERROR',
      details: {'via': via, 'error': e.toString()},
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_UNACKED_PENDING_RETRY',
    details: {'via': via},
  );
  return payload.toConversationMessage(
    contactPeerId: targetPeerId,
    isIncoming: false,
    status: 'sent',
    createdAt: createdAt,
    editedAt: editedAt,
    transport: via,
    wireEnvelope: jsonString,
  );
}
