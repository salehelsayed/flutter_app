import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
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

/// FDC-01: aggregate (serial) ceiling for the direct discover→dial→send leg.
/// Distinct from — and 3× larger than — the per-step [interactiveDirectBudget]
/// so a slow step (e.g. a ~1.9s discover) cannot starve dial+send and trip the
/// outer cap mid-send. Each step is still independently bounded at
/// [interactiveDirectBudget]; this only accrues when EVERY step makes real
/// progress (found→dialed→sending) — i.e. an online peer worth waiting for.
/// A null/failed step returns immediately at its per-step cutoff, never 6s.
/// (Proposal §4.1 / §8 P1-3: decouple, do NOT shrink the cold-relay budget.)
const Duration interactiveDirectAggregateBudget = Duration(seconds: 6);

/// Interactive send budget for the inbox store fallback path.
const Duration interactiveInboxBudget = Duration(seconds: 3);

/// FDC-08: tight bound on the presence-hint lookup so it stays OFF the
/// send-critical path. In steady state it is a 10–15s-cached read (≈0ms); a cold
/// lookup that exceeds this degrades to `RelayPresence.unknown` (today's full
/// concurrent race) while the underlying lookup still completes and warms the
/// cache for the next send. Consulted ONLY on the not-live-reachable path.
const Duration _presenceHintBudget = Duration(milliseconds: 400);

/// FDC-03: the serial relay-probe tail was REMOVED from the send path, so the
/// `NO_RESERVATION` fast-offline signal described below is no longer CONSUMED on
/// a 1:1 send — an unknown-presence offline peer now takes durable inbox custody
/// directly. This constant + `_tryRelayProbeSend` are retained (// ignore:
/// unused_element) per the FDC-03 scope guard for a later FDC plan that re-wires
/// the probe in-race; the historical rationale follows.
///
/// NET-REL-05 U-P5 (relay consolidation, Dart-only): after a successful relay
/// probe, make a SINGLE post-probe send attempt before inbox fallback.
/// Consolidated from 2 → 1: the direct race leg already invokes the same
/// relay-capable `message:send` (Go rides `WithAllowLimitedConn`), so the
/// second post-probe attempt was the redundant layer. The single retained
/// attempt still covers the online-relay-only peer whose address the direct
/// leg didn't discover (`peer_not_found` → relayProbeEligible) but who becomes
/// reachable once the probe establishes the circuit.
/// (Moving full relay ownership into Go is OUT OF SCOPE this run: it requires
/// `make all` + `pod install` and is not host-verifiable; see
/// `05-send-orchestration-IMPLEMENTATION-PLAN.md` U-P5.)
const int relayProbeSendAttempts = 1;

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

// FDC-03: the NET-REL-05 P1/P4 `kLowConfidenceWindow` (30s prior-attempt recency
// gate) is RETIRED. The concurrent durable inbox now fires for ALL unknown-
// presence sends (see the `unknownPresence` gate in `sendChatMessage`), not only
// recently-failed peers, so the recency window no longer gates anything.

/// FDC-02 §6.2a / §12 (libp2p DefaultDialRanker `RelayDelay`): the relay-LIVE
/// leg is penalized by this stagger so a viable LAN/direct leg that acks first
/// WINS and the relay-live leg is never started (suppress-on-early-win), instead
/// of relay riding the direct leg with no handicap. A warmed `/p2p-circuit` then
/// races-but-loses to a 30ms LAN hop (§6.1 by priority, not suppression).
/// Ordering invariant (TC-02-08): kRelayLegStagger > kPublicAddrTail >
/// kPrivateAddrTail.
const Duration kRelayLegStagger = Duration(milliseconds: 500);

/// FDC-02 §12 Happy-Eyeballs per-address tails. Pinned here only for the ordering
/// invariant; their PER-ADDRESS application inside a single dial is the Go host's
/// `DefaultDialRanker` (FDC-11, device-only). FDC-02 implements only the
/// leg-granularity [kRelayLegStagger] analog in Dart.
const Duration kPublicAddrTail = Duration(milliseconds: 250);
const Duration kPrivateAddrTail = Duration(milliseconds: 30);

/// FDC-02 §6.2b: a circuit-v2 LIVE relay socket is "limited" (~128KB/direction
/// before reset). Media — and any payload whose ENCRYPTED ENVELOPE
/// (`jsonString.length`) exceeds this ceiling — NEVER traverses the live relay
/// leg: it goes LAN-live, direct-live, or the durable inbox (relay-INBOX) only.
/// Headroom under the 128KB cap. (Invariant 3 / TC-02-03/04/12.)
const int kLiveRelayMaxPayloadBytes = 96 * 1024;

/// FDC-02 (latency half of P0-3): independent per-step budgets for the direct
/// discover→dial→send leg, replacing the single collective [interactiveDirectBudget]
/// cap inside `_tryDirectSendInner` so a slow step can no longer starve the
/// others. Each step stays bounded by the FDC-01 aggregate ceiling
/// [interactiveDirectAggregateBudget] (their worst-case SUM, 5000ms, is well
/// under the 6s ceiling). Discover is held at 2000ms to preserve FDC-01's landed
/// locks (a 1900ms discover succeeds; a 2100ms discover times out eligibly);
/// dial/send are tightened to 1500ms (no FDC-01 test pins them higher).
const Duration kDirectDiscoverBudget = Duration(milliseconds: 2000);
const Duration kDirectDialBudget = Duration(milliseconds: 1500);
const Duration kDirectSendBudget = Duration(milliseconds: 1500);

/// FDC-02 observability seam (C2). Production [P2PService] impls do NOT implement
/// this: the staggered relay-live leg's delivery is an ordinary
/// `sendMessageWithReply`, indistinguishable on the wire from the direct / reuse
/// / probe-tail sends. A host fake implements it so a test can attribute the
/// otherwise-identical circuit send to the relay-LIVE leg specifically — the
/// leg-attributable proof the leg did/did not start, since "sent while only a
/// circuit conn exists" over-counts the direct/reuse/probe sends. Mirrors the
/// existing [ReadinessProofRecorder] capability-interface pattern. Fired only
/// AFTER the suppress-on-early-win guard passes, so a suppressed leg is never
/// counted.
abstract interface class RelayLiveSendObserver {
  void noteRelayLiveSendStart();
}

/// Transport preference rank for the grace window: higher wins. 'reuse' ranks
/// with 'direct' (both are a non-relay live connection); unknown ranks lowest.
/// FDC-02 (C8): the staggered relay-LIVE leg reuses the existing 'relay' label
/// (Go labels a live `/p2p-circuit` send 'relay'), so it already ranks 1 < direct
/// < local with NO numeric change here — the leg granularity, not the rank, is
/// what FDC-02 adds.
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
  // 'inboxed' (relay custody, doc 115) proves transport readiness exactly as
  // the pre-115 'delivered'/'inbox' terminal did: the relay accepted a store.
  if (message.status != 'delivered' && message.status != 'inboxed') {
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

  /// 112 G5: an outbound attachment lacks complete blob-encryption
  /// metadata — the media mirror of [encryptionRequired]. Nothing was
  /// persisted or transported.
  mediaEncryptionRequired,
  peerNotFound,
  dialFailed,
  sendFailed,
}

const _uuid = Uuid();

/// 112 G5 fail-closed gate: every outbound 1:1 attachment must be
/// decryptable-with-v1 (key + nonce + whitelisted scheme — the sender
/// always writes the scheme explicitly) and carry the encrypted-blob
/// contentHash. Returns a reason code, or null when the attachments pass.
String? _sanitizeDirectMediaAttachments(List<MediaAttachment>? attachments) {
  if (attachments == null || attachments.isEmpty) {
    return null;
  }
  for (final attachment in attachments) {
    if (!attachment.hasEncryptionMetadata ||
        attachment.encryptionScheme == null) {
      return 'missing_media_encryption_metadata';
    }
    if (attachment.contentHash == null || attachment.contentHash!.isEmpty) {
      return 'missing_media_content_hash';
    }
  }
  return null;
}

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
  // F8 tier-2: a normal send stamps `dedupKey = its own id` (the default
  // below); a forward/share passes the SOURCE message's dedupKey so the
  // receiver dedups the re-minted (fresh id+timestamp) copy.
  String? dedupKey,
  String? createdAt,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
  TransportMetrics? transportMetrics,
  StoreInInboxDetailedFn? storeInInboxDetailed,
}) async {
  final sendStopwatch = Stopwatch()..start();
  final targetPrefix = targetPeerId.length > 10
      ? targetPeerId.substring(0, 10)
      : targetPeerId;
  final sanitizedText = sanitizeMessageText(text);
  final hasAttachments =
      mediaAttachments != null && mediaAttachments.isNotEmpty;
  final detailedInboxStore = p2pService is DetailedInboxStore
      ? p2pService as DetailedInboxStore
      : null;
  final effectiveStoreInInboxDetailed =
      storeInInboxDetailed ?? detailedInboxStore?.storeInInboxDetailed;
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

  // 116 EF-2 no-downgrade writer gate: a plain send under a message id whose
  // outgoing row carries editedAt or deletedAt would transmit downgraded
  // content AND poison the stored edit/deletion envelope via the pre-race
  // updateWireEnvelope below. Fail closed BEFORE encryption and before any
  // persist. All UI retry paths route through retryFailedMessage, so this
  // gate has zero legitimate trips — any field occurrence is a bug detector.
  if (action == MessagePayload.actionSend && messageId != null) {
    final existing = await messageRepo.getMessage(messageId);
    if (existing != null &&
        !existing.isIncoming &&
        (existing.editedAt != null || existing.isDeleted)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED',
        details: {
          'id': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
          'reason': existing.isDeleted
              ? 'deleted_row_plain_send'
              : 'edited_row_plain_send',
        },
      );
      emitSendTiming(outcome: 'action_downgrade_blocked');
      return (SendChatMessageResult.invalidMessage, null);
    }
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

  // 112 G5: outbound 1:1 media must carry complete blob-encryption
  // metadata — the media mirror of the encryptionRequired gate above
  // (mirror of the group path's _sanitizeGroupMediaAttachments). Fails
  // closed BEFORE any envelope is built or persisted so a plaintext blob
  // reference can never ride a v2 envelope.
  final mediaGateReason = _sanitizeDirectMediaAttachments(mediaAttachments);
  if (mediaGateReason != null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DIRECT_MEDIA_ENCRYPTION_REQUIRED',
      details: {'reason': mediaGateReason},
    );
    emitSendTiming(
      outcome: 'media_encryption_required',
      details: {'reason': mediaGateReason},
    );
    return (SendChatMessageResult.mediaEncryptionRequired, null);
  }

  // 3. Build payload
  final resolvedMessageId = messageId ?? _uuid.v4();
  final resolvedTimestamp =
      timestamp ?? DateTime.now().toUtc().toIso8601String();
  // F8 tier-2: default a normal send's dedupKey to its own id; a forward keeps
  // the propagated source key so a re-minted id+timestamp still dedups.
  final resolvedDedupKey = dedupKey ?? resolvedMessageId;
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
    dedupKey: resolvedDedupKey,
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

  // FDC-04 (RC2 / INV-2): hoisted above the reuse/sticky short-circuits so a
  // LAN-visible peer never reuses a warmed direct/relay conn (or a learned
  // direct/relay sticky transport) ahead of the LAN leg — the warmed path would
  // silently bypass a viable ~30ms LAN hop on every conversation open. (FDC-02
  // already carved out relay-ONLY circuit conns; this adds the orthogonal
  // direct-conn-to-a-LAN-peer case.) Read once here; still consumed downstream
  // by the race (unknownPresence + alreadyLocal).
  final isLocalPeer = p2pService.isLocalPeer(targetPeerId);

  // 4.5. Check for existing connected peer first (connection reuse).
  // If the peer is already connected, try to send directly without
  // rediscovering — this is the fastest interactive path.
  final isAlreadyConnected = p2pService.currentState.connections.any(
    (c) => c.peerId == targetPeerId,
  );
  // FDC-02 (C1 resolution A): a peer whose ONLY live connection is a
  // `/p2p-circuit` must NOT reuse-short-circuit ahead of the race — the warmed
  // relay would carry a send a 30ms LAN hop should win (§6.1 by latency). It
  // falls into the ranked race instead, where the staggered relay-LIVE leg is
  // the rank-aware circuit send. A peer with any direct connection still reuses.
  final isCircuitOnlyConnected = _isCircuitOnlyConnected(
    p2pService,
    targetPeerId,
  );

  if (isAlreadyConnected && !isCircuitOnlyConnected && !isLocalPeer) {
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
  // (`isLocalPeer` is read above the reuse block — FDC-04 RC2 hoist.)

  // NET-REL-05 P3 (sticky transport): the last-known-good LIVE transport for
  // this peer, or null if none/expired/stale. Returning non-null is a VALIDITY
  // guarantee, not a hint: `lastKnownGoodTransport` only survives if the entry
  // is within TTL AND (for 'local') the peer is still LAN-visible, and the
  // P2PServiceImpl invalidation paths (disconnect / relay-health transition /
  // addresses-updated) drop the entry the moment the path could have gone stale
  // (see p2p_service_learned_transport_invalidation_test.dart). That guarantee
  // is what lets the SHORT-CIRCUIT below skip discover/dial entirely. Reading it
  // never blocks: null (expired/stale/absent) degenerates to the full cold race,
  // identical to today, so a stale/dead preference can never trap the send.
  final learned = p2pService.lastKnownGoodTransport(targetPeerId);
  // FDC-04 (RC2 / INV-2): a LAN-visible peer must still race the LAN leg — only
  // a learned `'local'` may sticky-short-circuit for it; a learned
  // `'direct'`/`'relay'` would bypass the faster LAN hop, so it falls through to
  // the full race. A non-local peer keeps the unchanged sticky behavior.
  if (learned != null && (learned == 'local' || !isLocalPeer)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_STICKY_TRANSPORT',
      details: {'targetPeerId': targetPrefix, 'learned': learned},
    );

    // NET-REL-05 P3 short-circuit: a fresh+valid learned transport lets us REUSE
    // the known-good path WITHOUT re-paying discovery/dial. Send directly over
    // that transport (sendLocalMessage for 'local' — the peer is still LAN-
    // visible per the read-time revalidation; sendMessageWithReply for
    // 'direct'/'relay' — the connection-reuse path, no discover/dial). This is
    // the only place that skips discover/dial on a NON-connected peer; it is
    // gated behind the now-tested invalidation so a stale entry never reaches
    // here. On ANY miss/failure of this attempt we fall THROUGH to today's full
    // PARALLEL race (NOT a serial try-then-timeout-then-race), so the unhappy
    // path is never slower than a cold send.
    final shortCircuit = await _tryLearnedShortCircuit(
      p2pService,
      targetPeerId,
      jsonString,
      senderPeerId,
      learned: learned,
      transportMetrics: transportMetrics,
    );
    if (shortCircuit != null && shortCircuit.success) {
      sendPath = 'sticky';
      stepTimings = shortCircuit.stepTimings;
      // The sticky short-circuit reuses the learned known-good path WITHOUT
      // re-discovery/dial — the same census semantics as connection 'reuse', so
      // it lands in the 'reuse' rung. The 'sticky' label is preserved in the
      // FLOW timing/observability event below (sendPath) for diagnosis.
      recordMetrics(transport: shortCircuit.via, rung: 'reuse');
      return _completeSuccessfulSend(
        p2pService: p2pService,
        messageRepo: messageRepo,
        payload: payload,
        targetPeerId: targetPeerId,
        jsonString: jsonString,
        acknowledged: shortCircuit.acknowledged,
        via: shortCircuit.via!,
        resolvedMessageId: resolvedMessageId,
        text: sanitizedText,
        createdAt: createdAt,
        editedAt: resolvedEditedAt,
        mediaAttachmentRepo: mediaAttachmentRepo,
        attachments: normalizedAttachments,
        sendStopwatch: sendStopwatch,
        emitTimingEvent: emitTimingEvent,
        extraTimingDetails: {
          'connectionReused': false,
          'sendPath': 'sticky',
          'learned': learned,
          ...shortCircuit.stepTimings,
        },
      );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_STICKY_FALLBACK',
      details: {
        'targetPeerId': targetPrefix,
        'learned': learned,
        'reason': shortCircuit?.reason ?? 'unknown',
      },
    );
  }

  // FDC-03 (R6 / P0-2): fire the durable inbox copy CONCURRENTLY with the live
  // race for ALL "unknown presence" sends — the peer is not already-connected
  // (no reuse path), not on the LAN, AND has no live peer connection. The 30s
  // prior-attempt recency gate (the old NET-REL-05 P1/P4 "low confidence" lookup)
  // is REMOVED: a first-ever / cold notif-tap send is exactly the case that needs
  // fast durable custody, yet it is never "low confidence" (no prior failed
  // attempt exists) and so used to pay the slow serial probe→inbox tail. The
  // three STRUCTURAL guards are KEPT — a reuse/connected send and a LAN-local
  // send have their own delivery confirmation (the wire ack / the LAN nonce ack)
  // and must stay single-path: not a blanket dual-write (§6.2 "recipient cost
  // rises" honesty note). Presence-aware reachable→lazy / unreachable→inbox-first
  // emphasis (§6.3) is FDC-08; until then everything non-connected/non-local is
  // treated as UNKNOWN → concurrent inbox. Dropping the recency lookup also
  // removes one DB await from the hot send path.
  final unknownPresence =
      !isAlreadyConnected &&
      !isLocalPeer &&
      !p2pService.isConnectedToPeer(targetPeerId);

  // 187: when the 183 keepalive has latched this ACTIVE peer as dropped, the
  // direct discover/dial WAN leg to it is doomed — it burns ~1.5 s dialing a
  // peer that cannot answer while the concurrent durable inbox (fired below) has
  // already secured custody. Skip ONLY that WAN leg (Option A: the leg stays in
  // raceFutures[1], short-circuited at its top — LAN leg + inbox untouched).
  // Gated on [unknownPresence] so a connected/local/reachable peer (which took
  // the reuse fast path above or has a live conn) is NEVER skipped, keeping the
  // FDC-01/02 budget ladder intact for every non-dropped peer. Consulted via the
  // off-base [PeerDropSignal] capability so the ~31 base-P2PService fakes are
  // untouched; a service that doesn't implement it degrades to "never skip".
  final directSkipForKeepaliveDrop =
      unknownPresence &&
      p2pService is PeerDropSignal &&
      (p2pService as PeerDropSignal).isPeerSuspectedDropped(targetPeerId);

  // Fire the durable inbox copy CONCURRENTLY (fire-and-forget) for unknown-
  // presence sends. This is a parallel durability side-effect, NOT a race
  // participant: it never feeds the transport-label completer and never calls a
  // terminal `recordMetrics(rung:...)` — only `recordAttempt(leg:'inbox')`. The
  // SAME [jsonString] envelope (identical payload.id) is used, so a duplicate
  // arrival is discarded by the receiver's messageId dedup. `concurrentInbox`
  // is awaited later (race-failure tail / unacked handoff) to short-circuit the
  // redundant sequential store and avoid a double relay write.
  // 184 (INV-3): tracks whether the live race has already committed a terminal
  // 'delivered' (acked). The concurrent-inbox custody bump below must NEVER
  // regress a live 'delivered' to 'inboxed' — this flag is captured by the
  // `.then` closure and set at the race-success-acked commit point.
  var liveDelivered = false;
  Future<bool>? concurrentInbox;
  if (unknownPresence) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
      details: {
        'id': resolvedMessageId.substring(0, 8),
        'targetPeerId': targetPrefix,
      },
    );
    concurrentInbox = p2pService
        .storeInInbox(
          targetPeerId,
          jsonString,
          timeoutMs: interactiveInboxBudget.inMilliseconds,
        )
        .then((ok) async {
          transportMetrics?.recordAttempt(leg: 'inbox', succeeded: ok);
          // 184: surface the custody milestone MID-send. On a successful
          // concurrent-inbox ACK (~110 ms) advance the optimistic row's status to
          // a non-terminal 'inboxed' so the 1:1 bubble shows two ticks instead of
          // resting on the single optimistic tick until the live race resolves
          // (~1.8 s offline). A status-only update (NOT a full saveMessage): it
          // touches only the existing row's status column and re-renders via the
          // SAME messageChanges emit the screen gate already admits for
          // 'inboxed' — no new write path and no second durable row (the terminal
          // save still writes the full custody row + envelope). Guarded by
          // [liveDelivered] (INV-3) so a live 'delivered' that already won the
          // race is never regressed to 'inboxed'; fires only on ok==true (INV-4:
          // no false two-tick when custody is not secured). Status-surfacing
          // only — it never feeds the race or a terminal recordMetrics.
          if (ok && !liveDelivered) {
            await messageRepo.updateMessageStatus(resolvedMessageId, 'inboxed');
            emitFlowEvent(
              layer: 'FL',
              event: 'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
              details: {
                'id': resolvedMessageId.substring(0, 8),
                'targetPeerId': targetPrefix,
              },
            );
          }
          return ok;
        })
        .catchError((_) => false);

    // FDC-08 (§6.3) presence emphasis — consulted ONLY here on the
    // not-live-reachable path (a connected/local peer is delivered live, fast
    // path untouched). It is a HINT, NEVER a delivery gate: the durable inbox
    // copy above ALWAYS fires regardless of the hint (PRESENCE_NEVER_REPLACES_
    // INBOX / the C7 load-bearing gate). It only biases whether the live race or
    // the durable copy commits first; the FDC-02/03 race ladder below is
    // unchanged. Bounded + cache-served so it stays off the send-critical path,
    // degrading to `unknown` (today's fully-concurrent behavior) on miss/timeout.
    final presenceLookup = p2pService is RelayPresenceLookup
        ? p2pService as RelayPresenceLookup
        : null;
    var presenceEmphasis = RelayPresence.unknown;
    if (presenceLookup != null) {
      presenceEmphasis = await presenceLookup
          .lookupRelayPresence(targetPeerId)
          .timeout(
            _presenceHintBudget,
            onTimeout: () => RelayPresence.unknown,
          );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_PRESENCE_EMPHASIS',
      details: {
        'id': resolvedMessageId.substring(0, 8),
        'targetPeerId': targetPrefix,
        'presence': presenceEmphasis.name,
      },
    );

    // `unreachable` → commit the durable copy FIRST (custody + the relay's
    // store-triggered push-to-wake) before the live race builds; the live legs
    // still run afterwards (best-effort, NEVER dropped). `reachable`/`unknown`
    // keep today's fully-concurrent behavior (lazy inbox racing the live legs).
    // This is the same single storeInInbox future (non-null here — it was just
    // created above) — awaiting it here and again in the race-failure tail never
    // produces a second relay write.
    if (presenceEmphasis == RelayPresence.unreachable) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_PRESENCE_INBOX_FIRST',
        details: {'id': resolvedMessageId.substring(0, 8)},
      );
      await concurrentInbox;
    }
  }

  // FDC-02 §6.2a/b: the staggered relay-LIVE leg joins the race only when a live
  // `/p2p-circuit` exists for the peer AND the payload may ride a limited live
  // relay socket (not media, not over [kLiveRelayMaxPayloadBytes]). Otherwise the
  // race is the existing LAN+direct pair and an all-fail send falls to the
  // durable inbox (relay-INBOX, FDC-03 territory) — never the live relay socket.
  final liveRelayEligible =
      _hasLiveCircuitConnection(p2pService, targetPeerId) &&
      _liveRelayEligible(hasAttachments, jsonString.length);

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
      // 187: when set, the direct leg short-circuits BEFORE discover/dial (the
      // leg stays present so the completer's index/ directLegPending /
      // pendingCount coupling is undisturbed — Option A).
      skipForKeepaliveDrop: directSkipForKeepaliveDrop,
    ).timeout(
      // FDC-01: the OUTER cap is the aggregate (serial) ceiling, decoupled from
      // the per-step budget so a slow-but-progressing step can't be starved.
      // When it does fire the leg is genuinely stuck mid-progress on an online
      // peer, so the aggregate direct_timeout is relay-probe-eligible (the live
      // relay tail still runs instead of demoting to the durable inbox).
      interactiveDirectAggregateBudget,
      onTimeout: () =>
          _RaceResult.failed('direct_timeout', relayProbeEligible: true),
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
  // FDC-02: tracks whether the DIRECT leg (raceFutures[1], up to rank 2) is still
  // in flight. The staggered relay-live leg can commit a rank-1 ('relay') best
  // while the slower direct leg is still pending; that pending direct leg can
  // still outrank the relay best, so completion must wait (grace) for it
  // (TC-02-07). Cleared the moment the direct leg resolves (success or failure).
  var directLegPending = true;

  // FDC-02: the staggered relay-LIVE leg, added as a THIRD race future so it is
  // counted in [pendingCount] below (C4) — a fast LAN+direct DOUBLE failure
  // therefore cannot settle the race as failed before the relay penalty elapses
  // and the leg has had its chance (§6.2a / TC-02-02). It starts kRelayLegStagger
  // behind the LAN/direct legs (the penalty) and is SUPPRESSED — returns a failed
  // result WITHOUT sending — if a better-ranked leg has already committed `best`
  // by the time the stagger fires (C3: guard on `best != null`, NOT
  // `completer.isCompleted`, which stays false through a direct-leg grace window
  // and would let the leg fire spuriously after a direct win). Its result feeds
  // the SAME rank machinery at rank 1 ('relay'); an in-flight loser is not
  // cancellable (relies on receiver dedup). [best] is captured by reference, so
  // this closure must be built AFTER [best] is declared.
  if (liveRelayEligible) {
    raceFutures.add(
      Future<_RaceResult>(() async {
        await Future<void>.delayed(kRelayLegStagger);
        if (best != null) {
          return _RaceResult.failed('relay_live_suppressed');
        }
        return _tryRelayLiveSend(
          p2pService,
          targetPeerId,
          jsonString,
          transportMetrics: transportMetrics,
        );
      }),
    );
  }

  var pendingCount = raceFutures.length;

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
    final bestRank = _transportRank(best!.via);
    // A still-pending LOCAL leg (rank 3) can outrank any non-local best.
    if (localLegEligibilityPending && bestRank < 3) return false;
    // FDC-02: a still-pending DIRECT leg (up to rank 2) can outrank a rank-1
    // ('relay') best — the staggered relay-live leg committed first while the
    // slower direct leg is still in flight (TC-02-07). The relay-live leg itself
    // is rank 1 (lowest), so a pending relay-live leg never blocks completion.
    if (directLegPending && bestRank < 2) return false;
    return true;
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

  // Wire each leg. Index 0 is the local leg (see [localLegEligibilityPending]);
  // index 1 is the direct leg (see [directLegPending]); index 2 (when present)
  // is the FDC-02 staggered relay-live leg.
  for (var i = 0; i < raceFutures.length; i++) {
    final isLocalLeg = i == 0;
    final isDirectLeg = i == 1;
    void onResolved(_RaceResult result) {
      pendingCount--;
      if (!result.success) {
        failures.add(result);
        // A failed local leg can no longer produce a top-rank win.
        if (isLocalLeg) localLegEligibilityPending = false;
        // FDC-02: a failed direct leg can no longer outrank a committed relay
        // best (mirrors the local-leg clear). Cleared on the OFFER, not at
        // resolution, for the buffered-success path below — otherwise a buffered
        // rank-2 direct win could be beaten by a buffered rank-1 relay win whose
        // head-start offer fires first.
        if (isDirectLeg) directLegPending = false;
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
          if (isDirectLeg) directLegPending = false;
          offerSuccess(result);
          // After this (final) offer, if the race has fully resolved with no
          // better leg possible, commit the best now rather than wait out grace.
          if (best != null && noPendingLegCanBeatBest()) completeWithBest();
        });
      } else {
        if (isLocalLeg) localLegEligibilityPending = false;
        if (isDirectLeg) directLegPending = false;
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
    // 184 (INV-3): a live ACK commits a terminal 'delivered' below — mark it so
    // a late concurrent-inbox custody bump cannot regress it to 'inboxed'.
    if (raceResult.acknowledged) liveDelivered = true;
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
      // fired for this unknown-presence send, hand its future to the unacked
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

  // Persist a durable-custody (inbox) acceptance. Shared by the
  // concurrent-fallback short-circuit below and the sequential inbox tail so
  // the terminal `recordMetrics(rung:'inbox')` and status write stay identical
  // and fire exactly once. Relay-inbox acceptance is CUSTODY, not delivery
  // (doc 115): the row persists non-terminal 'inboxed' with the wire envelope
  // RETAINED so the custody sweep can re-store and a delivery receipt can
  // flip it to 'delivered'.
  Future<(SendChatMessageResult, ConversationMessage)> persistInboxAccepted({
    required bool recordInboxAttempt,
    int? expiresAtMs,
  }) async {
    sendPath = 'inbox';
    if (recordInboxAttempt) {
      transportMetrics?.recordAttempt(leg: 'inbox', succeeded: true);
    }
    recordMetrics(transport: 'inbox', rung: 'inbox');
    final inboxedMessage = payload
        .toConversationMessage(
          contactPeerId: targetPeerId,
          isIncoming: false,
          status: 'inboxed',
          createdAt: createdAt,
          editedAt: resolvedEditedAt,
          transport: 'inbox',
          wireEnvelope: jsonString,
        )
        .copyWith(relayExpiresAt: expiresAtMs);
    await messageRepo.saveMessage(inboxedMessage);
    await _persistOutgoingMedia(
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: normalizedAttachments,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_SUCCESS',
      details: {
        'id': resolvedMessageId.substring(0, 8),
        'status': 'inboxed',
        'via': 'inbox',
      },
    );
    emitSendTiming(
      outcome: 'success',
      details: {'status': 'inboxed', 'via': 'inbox'},
    );
    logChatOutgoing(
      messageId: resolvedMessageId,
      toPeerId: targetPeerId,
      status: 'inboxed',
      text: sanitizedText,
    );
    _recordSuccessfulSendReadinessProof(p2pService, inboxedMessage);
    return (
      SendChatMessageResult.success,
      inboxedMessage.copyWith(media: normalizedAttachments ?? const []),
    );
  }

  Future<(SendChatMessageResult, ConversationMessage)>
  persistInboxRejectedFull() async {
    sendPath = 'inbox';
    transportMetrics?.recordAttempt(leg: 'inbox', succeeded: false);
    recordMetrics(transport: null, rung: 'failed');
    final sentMessage = payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: 'sent',
      createdAt: createdAt,
      editedAt: resolvedEditedAt,
      transport: 'inbox',
      wireEnvelope: jsonString,
    );
    await messageRepo.saveMessage(sentMessage);
    await _persistOutgoingMedia(
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: normalizedAttachments,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INBOX_FULL_RETRYABLE',
      details: {'id': resolvedMessageId.substring(0, 8), 'via': 'inbox'},
    );
    emitSendTiming(
      outcome: 'retryable',
      details: {'status': 'sent', 'via': 'inbox', 'errorCode': 'INBOX_FULL'},
    );
    logChatOutgoing(
      messageId: resolvedMessageId,
      toPeerId: targetPeerId,
      status: 'sent',
      text: sanitizedText,
    );
    return (
      SendChatMessageResult.success,
      sentMessage.copyWith(media: normalizedAttachments ?? const []),
    );
  }

  // NET-REL-05 P1/P4: the live race failed. If a concurrent durable copy was
  // fired for this unknown-presence send, wait for it before paying for the
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
        details: {
          'id': resolvedMessageId.substring(0, 8),
          'reason': failureReason,
        },
      );
      return persistInboxAccepted(recordInboxAttempt: false);
    }
  }

  // FDC-03 (invariant 4 — "no serial relay-probe carrier"): the SERIAL
  // relay-probe→inbox tail is REMOVED. Live relay recovery is now FDC-02's
  // IN-RACE staggered relay-live leg (it joins the race when a live
  // `/p2p-circuit` already exists for the peer). An all-fail race for an
  // unknown-presence peer takes durable custody via the concurrent inbox copy
  // fired above (already awaited at the `concurrentInbox != null` short-circuit);
  // if that copy was null (the connected/local fall-through) or returned false,
  // the SINGLE sequential `storeInInbox` fallback below is the lone carrier —
  // preserving "exactly one relay write per message". `_tryRelayProbeSend` is
  // retained (it may be wired in-race by a later FDC plan; per the scope guard we
  // do not delete cross-plan symbols) but is no longer consumed on the send path.

  // All active paths failed — try offline inbox fallback once.
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_RACE_ALL_FAILED',
    details: {'reason': failureReason},
  );

  try {
    final inboxStopwatch = Stopwatch()..start();
    final detailedStore = effectiveStoreInInboxDetailed;
    final InboxStoreOutcome? outcome;
    final bool storedInInbox;
    if (detailedStore != null) {
      final detailedOutcome = await detailedStore(
        targetPeerId,
        jsonString,
        timeoutMs: interactiveInboxBudget.inMilliseconds,
      );
      outcome = detailedOutcome;
      storedInInbox = detailedOutcome.accepted;
    } else {
      outcome = null;
      storedInInbox = await p2pService.storeInInbox(
        targetPeerId,
        jsonString,
        timeoutMs: interactiveInboxBudget.inMilliseconds,
      );
    }
    inboxStopwatch.stop();
    stepTimings['inboxMs'] = inboxStopwatch.elapsedMilliseconds;
    if (storedInInbox) {
      return persistInboxAccepted(
        recordInboxAttempt: true,
        expiresAtMs: outcome?.expiresAtMs,
      );
    }
    if (outcome?.status == InboxStoreStatus.rejectedFull) {
      return persistInboxRejectedFull();
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
  SendMessageResult sendResult,
) {
  final actualTransport = sendResult.transport;
  if (actualTransport != null && actualTransport.isNotEmpty) {
    return actualTransport;
  }

  return _inferDirectVsRelayForConnectedPeer(p2pService, peerId);
}

/// FDC-02: true when the peer has at least one live `/p2p-circuit` connection —
/// the relay-LIVE leg's eligibility precondition.
bool _hasLiveCircuitConnection(P2PService p2pService, String peerId) {
  return p2pService.currentState.connections.any(
    (c) =>
        c.peerId == peerId &&
        c.multiaddrs.any((m) => m.contains('/p2p-circuit')),
  );
}

/// FDC-02 (C1 resolution A): true when EVERY live connection to the peer is a
/// `/p2p-circuit` (relay-backed). Such a peer must NOT take the reuse fast-path —
/// it races, so a faster LAN/direct hop can still win (§6.1 by latency, not the
/// warmed circuit). A peer with any direct (non-circuit) connection keeps the
/// reuse short-circuit; an ambiguous empty-multiaddr connection is treated as
/// direct (conservative — preserves the existing reuse path).
bool _isCircuitOnlyConnected(P2PService p2pService, String peerId) {
  final peerConns = p2pService.currentState.connections
      .where((c) => c.peerId == peerId)
      .toList();
  if (peerConns.isEmpty) return false;
  return peerConns.every(
    (c) =>
        c.multiaddrs.isNotEmpty &&
        c.multiaddrs.any((m) => m.contains('/p2p-circuit')),
  );
}

/// FDC-02 §6.2b: media and oversized (encrypted envelope > [kLiveRelayMaxPayloadBytes])
/// payloads NEVER traverse the live relay leg (the circuit-v2 socket is
/// ~128KB-limited). They fall to LAN-live / direct-live / the durable inbox.
bool _liveRelayEligible(bool hasAttachments, int payloadBytes) =>
    !hasAttachments && payloadBytes <= kLiveRelayMaxPayloadBytes;

/// FDC-02: the staggered relay-LIVE leg. Sends over the existing live connection
/// — Go selects the path (normally the `/p2p-circuit`, since this leg runs only
/// when one exists and no better leg has committed) and LABELS the result
/// (relay-opportunistic, not relay-forced). Fires the [RelayLiveSendObserver]
/// seam (no-op in production) right before the send so a host test can attribute
/// this otherwise-identical `sendMessageWithReply` to the relay-live leg (C2).
/// Reaching here means the suppress-on-early-win guard already passed, so the
/// leg actually sends.
Future<_RaceResult> _tryRelayLiveSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  TransportMetrics? transportMetrics,
}) async {
  if (p2pService case final RelayLiveSendObserver observer) {
    observer.noteRelayLiveSendStart();
  }
  try {
    final sendResult = await p2pService
        .sendMessageWithReply(
          targetPeerId,
          jsonString,
          timeoutMs: kDirectSendBudget.inMilliseconds,
        )
        .timeout(kDirectSendBudget);
    if (!sendResult.sent) {
      return _RaceResult.failed('relay_live_send_failed');
    }
    return _RaceResult.succeeded(
      via: _resolveGoSendTransport(p2pService, targetPeerId, sendResult),
      acknowledged: sendResult.acknowledged,
    );
  } on TimeoutException {
    return _RaceResult.failed('relay_live_timeout');
  } catch (e) {
    return _RaceResult.failed('relay_live_error:$e');
  }
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
  final durableLanSender = p2pService is DurableLanSender
      ? p2pService as DurableLanSender
      : null;
  final (localSent, acknowledged, ackKind) = durableLanSender != null
      ? switch (await durableLanSender.sendLocalMessageDurable(
          targetPeerId,
          jsonString,
          senderPeerId,
          timeoutMs: timeoutMs,
        )) {
          LanSendAck.committed => (true, true, 'committed'),
          LanSendAck.legacyAck => (true, false, 'legacy'),
          LanSendAck.failed => (false, false, 'failed'),
        }
      : await () async {
          final sent = await p2pService.sendLocalMessage(
            targetPeerId,
            jsonString,
            senderPeerId,
            timeoutMs: timeoutMs,
          );
          return sent
              ? (true, false, 'bool_legacy')
              : (false, false, 'bool_failed');
        }();
  localStopwatch.stop();
  final timings = {'localSendMs': localStopwatch.elapsedMilliseconds};
  transportMetrics?.recordAttempt(leg: 'local', succeeded: localSent);
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_LAN_ACK',
    details: {
      'targetPeerId': targetPeerId.length > 8
          ? targetPeerId.substring(0, 8)
          : targetPeerId,
      'kind': ackKind,
    },
  );
  if (localSent) {
    return _RaceResult.succeeded(
      via: 'local',
      acknowledged: acknowledged,
      stepTimings: timings,
    );
  }
  return _RaceResult.failed('local_send_failed', stepTimings: timings);
}

/// NET-REL-05 P3 short-circuit: attempt the LEARNED transport directly, WITHOUT
/// re-paying discovery/dial, reusing the known-good path.
///
/// - `'local'`: send over LAN via [sendLocalMessage] (no `discoverLocalPeer`).
///   The read-time revalidation in `lastKnownGoodTransport` already confirmed
///   the peer is still LAN-visible, so a fresh resolve would be redundant.
/// - `'direct'` / `'relay'`: send via [sendMessageWithReply] over the existing
///   known-good connection (no `discoverPeer` / `dialPeer`).
///
/// Returns a successful [_RaceResult] on delivery, or a FAILED result (never
/// null on a reached attempt) so the caller falls through to the full parallel
/// race. Returns null only for an unrecognized learned label (defensive — the
/// memory layer only stores local/direct/relay). Self-bounded so a stalled
/// learned path cannot make the fallback slower than a cold send.
Future<_RaceResult?> _tryLearnedShortCircuit(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
  String senderPeerId, {
  required String learned,
  TransportMetrics? transportMetrics,
}) async {
  if (learned == 'local') {
    try {
      return await _tryLocalSend(
        p2pService,
        targetPeerId,
        jsonString,
        senderPeerId,
        timeoutMs: interactiveLocalBudget.inMilliseconds,
        transportMetrics: transportMetrics,
      ).timeout(
        interactiveLocalBudget,
        onTimeout: () => _RaceResult.failed('sticky_local_timeout'),
      );
    } catch (e) {
      return _RaceResult.failed('sticky_local_error:$e');
    }
  }

  if (learned == 'direct' || learned == 'relay') {
    try {
      final sw = Stopwatch()..start();
      final sendResult = await p2pService
          .sendMessageWithReply(
            targetPeerId,
            jsonString,
            timeoutMs: interactiveDirectBudget.inMilliseconds,
          )
          .timeout(
            interactiveDirectBudget,
            onTimeout: () => const SendMessageResult(sent: false),
          );
      sw.stop();
      final timings = {
        'stickySendMs': sw.elapsedMilliseconds,
        if (sendResult.streamOpenMs != null)
          'streamOpenMs': sendResult.streamOpenMs!,
        if (sendResult.writeMs != null) 'writeMs': sendResult.writeMs!,
        if (sendResult.ackWaitMs != null) 'ackWaitMs': sendResult.ackWaitMs!,
      };
      // Sticky short-circuit = reuse of the learned known-good path; censused
      // under the 'reuse' leg (no separate sticky leg exists). The 'local'
      // branch above already recorded its own 'local' leg inside _tryLocalSend.
      transportMetrics?.recordAttempt(leg: 'reuse', succeeded: sendResult.sent);
      if (sendResult.sent) {
        return _RaceResult.succeeded(
          via: _resolveGoSendTransport(p2pService, targetPeerId, sendResult),
          acknowledged: sendResult.acknowledged,
          stepTimings: timings,
        );
      }
      return _RaceResult.failed('sticky_send_failed', stepTimings: timings);
    } catch (e) {
      transportMetrics?.recordAttempt(leg: 'reuse', succeeded: false);
      return _RaceResult.failed('sticky_send_error:$e');
    }
  }

  return null;
}

/// Try direct discover → dial → send path, recording one `direct` attempt
/// outcome for the transport census regardless of which leg ultimately wins the
/// race. Records exactly once, on the real outcome of the inner attempt.
Future<_RaceResult> _tryDirectSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  TransportMetrics? transportMetrics,
  bool skipForKeepaliveDrop = false,
}) async {
  // 187 (Option A): the 183 keepalive has latched this active peer as dropped —
  // the direct discover/dial leg would burn ~1.5 s on a peer that cannot answer
  // while the concurrent durable inbox already holds custody. Short-circuit
  // BEFORE any discover/dial AND before recording a 'direct' attempt (the leg
  // never actually attempted). The leg stays PRESENT in raceFutures[1], so the
  // completer's leg-index / directLegPending / pendingCount coupling is
  // untouched; it simply resolves fast to a NON-eligible failure —
  // relayProbeEligible:false because a keepalive-dropped peer is durably-
  // inboxed, not live-relay-recoverable, so this must NOT trigger the live relay
  // probe. The distinct discriminator event proves the skip fired for the
  // KEEPALIVE-DROP reason (not presence, not a budget timeout).
  if (skipForKeepaliveDrop) {
    final shortTarget = targetPeerId.length > 10
        ? '${targetPeerId.substring(0, 10)}…'
        : targetPeerId;
    emitFlowEvent(
      layer: 'FL',
      event: 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP',
      details: {'targetPeerId': shortTarget},
    );
    return _RaceResult.failed(
      'direct_skipped_keepalive_drop',
      relayProbeEligible: false,
    );
  }
  final result = await _tryDirectSendInner(
    p2pService,
    targetPeerId,
    jsonString,
  );
  transportMetrics?.recordAttempt(leg: 'direct', succeeded: result.success);
  return result;
}

Future<_RaceResult> _tryDirectSendInner(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
) async {
  final timings = <String, int>{};

  // FDC-02 (latency half of P0-3): each step is bounded by its OWN budget
  // ([kDirectDiscoverBudget]/[kDirectDialBudget]/[kDirectSendBudget]) instead of
  // the single collective [interactiveDirectBudget], so a slow step can no longer
  // starve the others. The worst-case serial sum stays under the FDC-01 aggregate
  // ceiling ([interactiveDirectAggregateBudget]) applied at the leg's outer
  // `.timeout` in the race assembly.
  //
  // Discover — per-step bounded so a slow-but-online discover yields an
  // *eligible* peer_not_found (the relay tail runs) instead of being swallowed
  // by the aggregate ceiling. discoverPeer returns a NULLABLE DiscoveredPeer?,
  // so onTimeout: () => null type-checks and a timed-out discover collapses into
  // the existing null-discover branch below (already eligible). Against the real
  // impl discoverPeer honors its own timeoutMs and returns null on timeout, so
  // this .timeout is a hang-guard layered atop it; against the test fake (which
  // ignores timeoutMs) it IS the deterministic cut.
  final discoverStopwatch = Stopwatch()..start();
  final peer = await p2pService
      .discoverPeer(
        targetPeerId,
        timeoutMs: kDirectDiscoverBudget.inMilliseconds,
      )
      .timeout(kDirectDiscoverBudget, onTimeout: () => null);
  discoverStopwatch.stop();
  timings['discoverMs'] = discoverStopwatch.elapsedMilliseconds;
  if (peer == null) {
    return _RaceResult.failed(
      'peer_not_found',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }

  // Dial — FDC-02 owns adding this per-step wrapper (FDC-01 left it implicit on
  // the bridge's timeoutMs). dialPeer returns Future<bool>, so onTimeout: () =>
  // false type-checks and a timed-out dial collapses into the dial_failed branch
  // below (already relay-probe-eligible). Hang-guard vs the real impl;
  // deterministic cut vs the fake (which ignores timeoutMs).
  final dialStopwatch = Stopwatch()..start();
  final dialed = await p2pService
      .dialPeer(
        targetPeerId,
        addresses: peer.addresses,
        timeoutMs: kDirectDialBudget.inMilliseconds,
      )
      .timeout(kDirectDialBudget, onTimeout: () => false);
  dialStopwatch.stop();
  timings['dialMs'] = dialStopwatch.elapsedMilliseconds;
  if (!dialed) {
    return _RaceResult.failed(
      'dial_failed',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }

  // Send — per-step bounded. A send that OVERRUNS its budget becomes an
  // *eligible* direct_timeout (the relay probe runs), distinct from a definitive
  // sent:false which stays a NON-eligible send_failed → inbox (preserved). The
  // sendTimedOut flag keeps the two failure classes separate. (Hang-guard vs the
  // real impl; deterministic cut vs the test fake — same as discover above.)
  final sendStepStopwatch = Stopwatch()..start();
  SendMessageResult? sendResult;
  var sendTimedOut = false;
  try {
    sendResult = await p2pService
        .sendMessageWithReply(
          targetPeerId,
          jsonString,
          timeoutMs: kDirectSendBudget.inMilliseconds,
        )
        .timeout(kDirectSendBudget);
  } on TimeoutException {
    sendTimedOut = true;
  }
  sendStepStopwatch.stop();
  timings['sendMs'] = sendStepStopwatch.elapsedMilliseconds;
  if (sendTimedOut || sendResult == null) {
    return _RaceResult.failed(
      sendTimedOut ? 'direct_timeout' : 'send_failed',
      relayProbeEligible: sendTimedOut,
      stepTimings: timings,
    );
  }
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

// FDC-03: no longer consumed on the send path (the serial relay-probe→inbox tail
// was removed — live relay recovery is FDC-02's in-race relay-live leg). Retained
// rather than deleted per the FDC-03 scope guard ("do not delete cross-plan
// symbols speculatively" — a later FDC plan may wire it in-race).
// ignore: unused_element
Future<_RaceResult> _tryRelayProbeSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required String failureReason,
  required String messageId,
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
        details: {'id': messageId.substring(0, 8)},
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
      owner: MediaOwnerLane.direct,
    );
    final hasStaleUploadPending = existing.any(
      (attachment) =>
          attachment.downloadStatus == 'upload_pending' &&
          !expectedIds.contains(attachment.id),
    );
    if (hasStaleUploadPending) {
      await mediaAttachmentRepo.deleteAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
    }
  }

  for (final attachment in attachments) {
    await mediaAttachmentRepo.saveAttachment(
      attachment,
      owner: MediaOwnerLane.direct,
    );
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
  // was fired for this unknown-presence send and already took custody, settle as
  // 'inboxed'/'inbox' WITHOUT a second sequential `storeInInbox` — one message
  // must never produce two relay writes (R1 guard). `concurrentInbox` resolves
  // to false on failure/timeout, in which case we fall through to the normal
  // sequential handoff below. Inbox acceptance is custody, not delivery
  // (doc 115): keep the envelope for the custody sweep / receipt flip.
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
        status: 'inboxed',
        createdAt: createdAt,
        editedAt: editedAt,
        transport: 'inbox',
        wireEnvelope: jsonString,
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
        status: 'inboxed',
        createdAt: createdAt,
        editedAt: editedAt,
        transport: 'inbox',
        wireEnvelope: jsonString,
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
