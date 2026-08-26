import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/android_notification_payload_e2e_protocol.dart';

const String androidNotificationCapabilityId =
    'notifications.android_payload_campaign';
const String androidNotificationBuildProfileId = 'android.production_fcm';

const Set<String> androidNotificationKnownAppOpModes = <String>{
  'allow',
  'ignore',
  'deny',
  'default',
  'foreground',
  'errored',
  'ask',
};

/// Interprets `adb shell pm path <package>` without guessing through an adb
/// failure. Android 17 reports an absent package as exit 1 with no output;
/// older images commonly spell the absence as `unknown package`/`not found`.
/// Any other non-zero response remains an unobservable census and fails shut.
bool androidPackagePresentFromPmPath({
  required int exitCode,
  required String stdout,
  required String stderr,
}) {
  final hasPackagePath = stdout
      .split('\n')
      .map((line) => line.trim())
      .any((line) => line.startsWith('package:'));
  if (hasPackagePath) return true;
  if (exitCode == 0) return false;

  final output = '$stdout\n$stderr';
  final normalized = output.toLowerCase();
  if ((exitCode == 1 && output.trim().isEmpty) ||
      normalized.contains('unknown package') ||
      normalized.contains('not found')) {
    return false;
  }
  throw const FormatException('pm path package presence is not observable');
}

/// Parses the receiver's real `cmd appops get <package> POST_NOTIFICATION`
/// response into a closed Android mode. Unknown or contradictory output is a
/// probe failure, never a guessed `allow`/`default` premise.
String parseAndroidNotificationAppOpMode(String output) {
  final modes = RegExp(
    r'\bPOST_NOTIFICATION\s*:\s*([A-Za-z_]+)',
    caseSensitive: false,
  ).allMatches(output).map((match) => match.group(1)!.toLowerCase()).toSet();
  if (modes.isEmpty &&
      RegExp(r'\bno operations\b', caseSensitive: false).hasMatch(output)) {
    return 'default';
  }
  if (modes.length != 1 ||
      !androidNotificationKnownAppOpModes.contains(modes.single)) {
    throw const FormatException(
      'POST_NOTIFICATION app-op mode is absent, unknown, or contradictory',
    );
  }
  return modes.single;
}

/// Parses the explicit UID override emitted by
/// `cmd appops get --uid <package> POST_NOTIFICATION`.
///
/// Android 17 keeps the runtime-permission-backed package row at `allow` even
/// while a UID override is `ignore`. The authoritative line is therefore the
/// optional `Uid mode:` prefix. Its absence means that no UID override exists
/// (`default`); the package row is still required to be syntactically valid so
/// an unsupported/changed shell response cannot be mistaken for a baseline.
String parseAndroidNotificationUidAppOpMode(String output) {
  final uidModes = RegExp(
    r'\bUid mode\s*:\s*POST_NOTIFICATION\s*:\s*([A-Za-z_]+)',
    caseSensitive: false,
  ).allMatches(output).map((match) => match.group(1)!.toLowerCase()).toSet();
  if (uidModes.length > 1 ||
      (uidModes.isNotEmpty &&
          !androidNotificationKnownAppOpModes.contains(uidModes.single))) {
    throw const FormatException(
      'POST_NOTIFICATION UID app-op mode is unknown or contradictory',
    );
  }
  if (uidModes.isNotEmpty) return uidModes.single;

  // Validate that this was still a recognizable app-ops response. Package
  // history/effective rows are deliberately ignored when no UID override is
  // present because they do not describe the state that this harness mutates.
  parseAndroidNotificationAppOpMode(output);
  return 'default';
}

/// Maps a captured UID override state to the shell mode that reproduces it.
///
/// For the runtime-permission-backed notification op on Android 17, writing
/// UID `default` is a no-op when an `ignore` override exists. Writing UID
/// `allow` clears that override; the next UID probe has no `Uid mode:` line and
/// therefore reads back as the captured `default` state. Other closed modes
/// are written literally and still have to read back exactly.
String androidNotificationUidAppOpShellMode(String capturedMode) {
  if (!androidNotificationKnownAppOpModes.contains(capturedMode)) {
    throw const FormatException('Unknown POST_NOTIFICATION UID app-op mode');
  }
  return capturedMode == 'default' ? 'allow' : capturedMode;
}

/// Whether Android explicitly rejected the UID override needed by G24.
///
/// Some API 33+ images return exit zero and briefly expose a UID-mode row even
/// though AppOps refuses to apply that mode to the runtime-backed notification
/// permission. That receiver is not a behavior failure: it lacks the settable
/// OS boundary required by the availability-bounded G24 row.
bool androidNotificationUidAppOpMutationBlocked(String logcat) => RegExp(
  r'Blocked setUidMode call for runtime permission app op:[^\r\n]*\bPOST_NOTIFICATION\b',
  caseSensitive: false,
).hasMatch(logcat);

/// Content-safe fingerprint of the package's durable notification-channel
/// configuration. Two fields are intentionally removed:
///
/// * `mLastNotificationUpdateTimeMs` — posting and dismissing a campaign card
///   advances that counter without changing user-visible channel policy.
/// * `mUserLockedFields` — measured on `emulator-5554` (Android 17 / SDK 37)
///   for plan 380's
///   mandatory pre-authoring probe: toggling a channel OFF in Settings and
///   back ON restores `mImportance` exactly (4 -> 0 -> 4) but leaves
///   `mUserLockedFields=4` behind permanently. That residue is user-lock
///   PROVENANCE, not policy. `mImportance` stays hashed, so a leg that fails
///   to re-enable the channel still reds the end-of-campaign state verify.
///
/// The same probe measured `pm revoke` + `pm set-permission-flags user-fixed`
/// followed by `pm clear-permission-flags user-fixed` + `pm grant`: that cycle
/// leaves ZERO residue (`importance=DEFAULT userSet=false` is restored byte for
/// byte), so the permission leg needs no redaction of its own.
String androidNotificationChannelStateSha256(
  String dumpsys, {
  required String packageName,
}) {
  final lines = dumpsys.split('\n');
  final packageHeader = RegExp(
    r'^\s+AppSettings:\s+' + RegExp.escape(packageName) + r'\s+\(',
  );
  final nextPackageHeader = RegExp(r'^\s+AppSettings:\s+');
  String? header;
  final stableChildren = <String>[];
  var inPackage = false;
  for (final raw in lines) {
    if (!inPackage) {
      if (!packageHeader.hasMatch(raw)) continue;
      inPackage = true;
      header = raw.trim().replaceFirst(RegExp(r'\s+\(\d+\)'), ' (<uid>)');
      continue;
    }
    if (nextPackageHeader.hasMatch(raw)) break;
    final line = raw.trim();
    if (line.startsWith('Delegate:') ||
        line.startsWith('NotificationChannel{') ||
        line.startsWith('NotificationChannelGroup{')) {
      stableChildren.add(
        line
            .replaceAll(
              RegExp(r'mLastNotificationUpdateTimeMs=-?\d+'),
              'mLastNotificationUpdateTimeMs=<volatile>',
            )
            .replaceAll(
              RegExp(r'mUserLockedFields=-?\d+'),
              'mUserLockedFields=<user-provenance>',
            ),
      );
    }
  }
  stableChildren.sort();
  final stable = <String>[?header, ...stableChildren];
  return sha256.convert(utf8.encode(jsonEncode(stable))).toString();
}

final class AndroidStagedEnvelopeObservation {
  const AndroidStagedEnvelopeObservation({
    required this.messageId,
    required this.ciphertextSha256,
    required this.nonceSha256,
    required this.receivedAtMs,
  });

  final String messageId;
  final String ciphertextSha256;
  final String nonceSha256;
  final int receivedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'messageIdPrefix': safeNotificationIdPrefix(messageId),
    'ciphertextSha256': ciphertextSha256,
    'nonceSha256': nonceSha256,
    'receivedAtMs': receivedAtMs,
  };
}

/// Validates the exact app-private file written by the production Android FCM
/// background handler. Raw encrypted fields are reduced to hashes immediately.
AndroidStagedEnvelopeObservation parseAndroidStagedEnvelopeObservation(
  String encoded, {
  required String expectedMessageId,
  required String expectedSenderPeerId,
  required DateTime notBefore,
}) {
  final decoded = jsonDecode(encoded);
  if (decoded is! Map) {
    throw const FormatException('staged envelope root must be an object');
  }
  final value = decoded.map<String, Object?>(
    (key, item) => MapEntry('$key', item),
  );
  final kind = value['kind'];
  final kem = value['kem'];
  final ciphertext = value['ciphertext'];
  final nonce = value['nonce'];
  final senderPeerId = value['senderPeerId'];
  final messageId = value['messageId'];
  final receivedAtMs = value['receivedAtMs'];
  if (kind != 'chat' ||
      kem is! String ||
      kem.isEmpty ||
      ciphertext is! String ||
      ciphertext.isEmpty ||
      nonce is! String ||
      nonce.isEmpty ||
      senderPeerId != expectedSenderPeerId ||
      messageId != expectedMessageId ||
      receivedAtMs is! num ||
      receivedAtMs.toInt() < notBefore.millisecondsSinceEpoch) {
    throw const FormatException(
      'staged envelope does not match the real run-bound ciphertext tuple',
    );
  }
  return AndroidStagedEnvelopeObservation(
    messageId: messageId as String,
    ciphertextSha256: sha256.convert(utf8.encode(ciphertext)).toString(),
    nonceSha256: sha256.convert(utf8.encode(nonce)).toString(),
    receivedAtMs: receivedAtMs.toInt(),
  );
}

/// The two `[PUSH]` lines that mean "the provider accepted this wake".
///
/// `8d86501e4` (relay v1.8.0, production since 2026-08-16) deleted every
/// recipient-bearing `[PUSH]` line. What remains is
/// `[PUSH] outcome=success attempt=%d total_attempts=%d` (`inbox.go:626`, the
/// ordinary retry path) and `[PUSH] outcome=success fallback=strict`
/// (`inbox.go:664`, the payload-too-large strict-minimal path). Both are
/// attribution-free BY DESIGN and frozen that way by the relay's own
/// private-value closure test, so no recipient binding can be recovered from
/// the journal at all.
final RegExp _androidProviderAcceptedPattern = RegExp(
  r'\[PUSH\]\s+outcome=success\s+'
  r'(?:attempt=\d+\s+total_attempts=\d+|fallback=strict)\b',
);

/// True when the relay journal slice records a provider acceptance.
///
/// Recipient binding is the CALLER's job and is deliberately not attempted
/// here: every call site passes a slice scoped with
/// `journalctl --since <sentAt>` for a send the campaign itself just made, on
/// a topology with one receiver. Matching only `outcome=success` inside that window is the
/// strongest predicate the v1.8.0 grammar can still support.
bool relayJournalContainsAndroidProviderSend(String journal) =>
    _androidProviderAcceptedPattern.hasMatch(journal);

const String _groupMessageProviderAttemptMarker =
    '[GROUP_MESSAGE_PROVIDER_ATTEMPT]';
const Set<String> _groupMessageProviderAttemptRequiredKeys = <String>{
  'schema',
  'source',
  'provenance',
  'dispatchCorrelationSha256',
  'claimedCollapseIdentifierSha256',
  'providerAttempt',
  'attemptKind',
  'outcome',
  'firebaseResponseNameSha256',
};
const Set<String> _groupMessageProviderAttemptAllowedKeys = <String>{
  ..._groupMessageProviderAttemptRequiredKeys,
  'providerMessageIdSha256',
};
final RegExp _lowercaseSha256Pattern = RegExp(r'^[0-9a-f]{64}$');

typedef RelayAcceptedGroupMessageProviderAttempt = ({
  String source,
  String dispatchCorrelationSha256,
  String claimedCollapseIdentifierSha256,
  String? providerMessageIdSha256,
});

typedef RelayAcceptedGroupMessageProviderHashes = ({
  String dispatchCorrelationSha256,
  String? providerMessageIdSha256,
});

/// Extracts the one closed, accepted relay provider-attempt record in a
/// diagnostic journal window.
///
/// The parser exposes source and claimed-collapse hashes only for the caller's
/// transient in-memory provenance join. The full Firebase-response hash is
/// validated but never returned, and artifact-v2 persists neither transient
/// join field: it carries only the dispatch correlation and the optional
/// normalized provider-message hash.
RelayAcceptedGroupMessageProviderAttempt?
parseRelayAcceptedGroupMessageProviderAttempt(String journal) {
  final markerLines = journal
      .split('\n')
      .where((line) => line.contains(_groupMessageProviderAttemptMarker))
      .toList(growable: false);
  if (markerLines.length != 1) return null;

  final line = markerLines.single;
  final markerIndex = line.indexOf(_groupMessageProviderAttemptMarker);
  final suffixStart = markerIndex + _groupMessageProviderAttemptMarker.length;
  if (markerIndex < 0 ||
      line.indexOf(_groupMessageProviderAttemptMarker, suffixStart) >= 0 ||
      suffixStart >= line.length ||
      line[suffixStart] != ' ') {
    return null;
  }
  final encoded = line.substring(suffixStart + 1);
  if (encoded.isEmpty || encoded != encoded.trim()) return null;

  final Map<String, Object?> record;
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) return null;
    record = Map<String, Object?>.from(decoded);
  } on Object {
    return null;
  }

  final keys = record.keys.toSet();
  if (!keys.containsAll(_groupMessageProviderAttemptRequiredKeys) ||
      !_groupMessageProviderAttemptAllowedKeys.containsAll(keys)) {
    return null;
  }
  // `jsonDecode` otherwise resolves duplicate object members last-one-wins.
  // Count every decoded member token so duplicated/ambiguous records stay
  // closed without requiring a particular JSON key order.
  for (final key in keys) {
    final encodedKey = RegExp.escape(jsonEncode(key));
    if (RegExp('$encodedKey\\s*:').allMatches(encoded).length != 1) {
      return null;
    }
  }

  final source = record['source'];
  final dispatchCorrelation = record['dispatchCorrelationSha256'];
  final claimedCollapse = record['claimedCollapseIdentifierSha256'];
  final firebaseResponse = record['firebaseResponseNameSha256'];
  final providerMessage = record['providerMessageIdSha256'];
  if (record['schema'] != 'mknoon.relay.group-message-provider-attempt.v1' ||
      !const <String>{'group_inbox', 'group_content'}.contains(source) ||
      record['provenance'] != 'complete' ||
      record['providerAttempt'] != 1 ||
      record['attemptKind'] != 'primary' ||
      record['outcome'] != 'accepted' ||
      dispatchCorrelation is! String ||
      !_lowercaseSha256Pattern.hasMatch(dispatchCorrelation) ||
      claimedCollapse is! String ||
      !_lowercaseSha256Pattern.hasMatch(claimedCollapse) ||
      firebaseResponse is! String ||
      !_lowercaseSha256Pattern.hasMatch(firebaseResponse) ||
      (record.containsKey('providerMessageIdSha256') &&
          (providerMessage is! String ||
              !_lowercaseSha256Pattern.hasMatch(providerMessage)))) {
    return null;
  }

  return (
    source: source as String,
    dispatchCorrelationSha256: dispatchCorrelation,
    claimedCollapseIdentifierSha256: claimedCollapse,
    providerMessageIdSha256: providerMessage as String?,
  );
}

/// Joins one accepted journal row to this run's closed metric and card
/// provenance before its two artifact-v2 hashes may be retained.
///
/// [source] and [claimedCollapseIdentifierSha256] remain transient. A source
/// mismatch, an unclosed metric source, or a collapse hash belonging to a
/// different delivered card rejects both artifact hashes.
RelayAcceptedGroupMessageProviderHashes?
bindRelayAcceptedGroupMessageProviderAttempt({
  required RelayAcceptedGroupMessageProviderAttempt? attempt,
  required Object? relayGroupMessageDispatchSource,
  required String expectedCollapseIdentifierSha256,
}) {
  const journalSourceForMetricSource = <String, String>{
    'groupInbox': 'group_inbox',
    'groupContent': 'group_content',
  };
  if (attempt == null ||
      !_lowercaseSha256Pattern.hasMatch(expectedCollapseIdentifierSha256) ||
      journalSourceForMetricSource[relayGroupMessageDispatchSource] !=
          attempt.source ||
      attempt.claimedCollapseIdentifierSha256 !=
          expectedCollapseIdentifierSha256) {
    return null;
  }
  return (
    dispatchCorrelationSha256: attempt.dispatchCorrelationSha256,
    providerMessageIdSha256: attempt.providerMessageIdSha256,
  );
}

final RegExp _androidProviderFirstAttemptAcceptedPattern = RegExp(
  r'\[PUSH\]\s+outcome=success\s+attempt=1\s+total_attempts=\d+\b',
);

/// Proves one provider acceptance occurred on the first ordinary attempt.
///
/// This predicate must run over the raw, single-owner journal window before
/// that window is reduced to hashes. A retry, strict-size fallback, or second
/// accepted line makes attribution ambiguous and therefore fails closed.
bool relayJournalProvesSingleFirstAttemptProviderAcceptance(String journal) {
  final accepted = _androidProviderAcceptedPattern.allMatches(journal).toList();
  if (accepted.length != 1 ||
      !_androidProviderFirstAttemptAcceptedPattern.hasMatch(
        accepted.single.group(0)!,
      )) {
    return false;
  }
  return !RegExp(
    r'\[PUSH\]\s+outcome=(?:retrying|success\s+fallback=strict)\b',
  ).hasMatch(journal);
}

bool notificationWindowContainsRelayDrain(String logcat) =>
    logcat.contains('P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS');

// ---------------------------------------------------------------------------
// TC-B13 — dual-path (live bridge + real FCM) single-alert predicates.
//
// All three are pure functions over one CURSOR-SCOPED logcat window so the
// campaign never has to clear the shared device log.
// ---------------------------------------------------------------------------

/// Live 1:1 listener arrival marker, emitted immediately before the listener
/// calls `maybeShowNotification`
/// (`lib/features/conversation/application/chat_message_listener.dart:721-732`).
const String androidNotificationLivePathAttemptEvent =
    'CHAT_LISTENER_NEW_MESSAGE';

/// FCM background-isolate receipt marker, emitted at the top of the background
/// handler (`lib/features/push/application/background_message_handler.dart:611-620`).
const String androidNotificationFcmPathAttemptEvent =
    'PUSH_BACKGROUND_MESSAGE_RECEIVED';

/// Event names the LIVE path uses to record that it stood down.
///
/// The reconcile variants were originally excluded on the reading that they
/// require a `durableEffectContext` the 1:1 live listener never passes. The
/// first device run of this leg (2026-08-18, `emulator-5554`) REFUTED that:
/// the 1:1 direct path runs durable in the shipped build — its own
/// `NOTIFICATION_SHOWN` carries `{"durable":true,"producer":"direct_message"}`
/// — and the losing side emitted
/// `NOTIFICATION_LEGACY_CLAIM_RECONCILE {"reason":"message_event_already_claimed"}`
/// three times while emitting `NOTIFICATION_SUPPRESSED` zero times. Excluding
/// it made the assertion unsatisfiable on real hardware.
///
/// The REASON allow-list below is deliberately unchanged, so an unexplained or
/// novel stand-down still fails the leg.
const Set<String> androidNotificationLivePathSuppressionEvents = <String>{
  'NOTIFICATION_SUPPRESSED',
  'NOTIFICATION_DEFERRED',
  'NOTIFICATION_LEGACY_CLAIM_RECONCILE',
  'NOTIFICATION_LEGACY_DEDUPE_RECONCILE',
};

/// Reasons the LIVE path emits when it loses the race.
///
/// `message_event_claim_pending` is the background-owner-first overlap: the
/// live projection retains SQL custody while the background isolate completes
/// the exact native post. The B13 card assertion still requires that post, so a
/// stranded pending claim cannot pass as a successful dedupe.
const Set<String> androidNotificationLivePathLosingReasons = <String>{
  'recent_remote_push',
  'message_event_already_claimed',
  'message_event_claim_pending',
};

/// Reasons the FCM background isolate emits when it loses the race for a
/// `type == 'new_message'` push
/// (`background_message_handler.dart:797`, `:940`).
const Set<String> androidNotificationFcmPathLosingReasons = <String>{
  'recent_duplicate_background_push',
  'message_event_already_claimed',
};

/// True only when BOTH delivery legs demonstrably ATTEMPTED inside the window.
///
/// Without this, a run in which only one path ever fired would satisfy
/// "exactly one card" and pass as a dual-path proof.
bool notificationWindowProvesDualPathAttempt(String logcat) =>
    logcat.contains(androidNotificationLivePathAttemptEvent) &&
    logcat.contains(androidNotificationFcmPathAttemptEvent);

/// The typed suppression the LOSING delivery path emitted, as
/// `'<EVENT>:<reason>'`, or null when the window carries no such record.
///
/// A discriminator UNION is required because either path may win the race: the
/// live listener emits `NOTIFICATION_SUPPRESSED` and the background isolate
/// emits `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED`.
String? androidNotificationLosingPathSuppression(String logcat) {
  for (final line in const LineSplitter().convert(logcat)) {
    final flowIndex = line.indexOf('[FLOW] ');
    if (flowIndex < 0) continue;
    final Object? decoded;
    try {
      decoded = jsonDecode(line.substring(flowIndex + '[FLOW] '.length));
    } on FormatException {
      continue;
    }
    if (decoded is! Map) continue;
    final event = decoded['event'];
    final details = decoded['details'];
    final reason = details is Map ? details['reason'] : null;
    if (reason is! String) continue;
    if (event is String &&
        androidNotificationLivePathSuppressionEvents.contains(event) &&
        androidNotificationLivePathLosingReasons.contains(reason)) {
      return '$event:$reason';
    }
    if (event == 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED' &&
        androidNotificationFcmPathLosingReasons.contains(reason)) {
      return 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED:$reason';
    }
  }
  return null;
}

/// Markers proving a delivery path actually CALLED the native show, unioned
/// across both paths because either may win the race.
///
/// * `NOTIFICATION_SHOWN` — the live/foreground service, emitted after
///   `publishNative` (`lib/core/notifications/flutter_notification_service.dart:473-492`,
///   `:523-527`).
/// * `PUSH_BACKGROUND_NOTIFICATION_SHOWN` — the FCM background isolate,
///   emitted unconditionally after its show block
///   (`lib/features/push/application/background_message_handler.dart:1529-1543`).
///
/// Both fire even when the OS then DROPS the card, which is exactly what a
/// permission-denied or blocked-channel proof needs: the app must be shown to
/// have tried. The receipt marker
/// [androidNotificationFcmPathAttemptEvent] is NOT a substitute — it is
/// emitted at the top of the handler, upstream of staging, the display
/// eligibility gate, and every suppression return, so a wake that never
/// reached a post decision satisfies it.
const Set<String> androidNotificationPostAttemptEvents = <String>{
  'NOTIFICATION_SHOWN',
  'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
};

/// The first post-attempt marker in a cursor-scoped window, or null.
String? androidNotificationPostAttemptEvent(String logcat) {
  for (final record in androidNotificationFlowRecords(logcat)) {
    if (androidNotificationPostAttemptEvents.contains(record.event)) {
      return record.event;
    }
  }
  return null;
}

/// The `silent` flag reported by the FIRST post attempt in [logcat].
///
/// Returns null when the window records no post attempt, or when the attempt
/// reported no native show at all (the key is absent in that case). The log
/// answers whether the winning post alerted; a settled dumpsys read separately
/// verifies that a later silent same-ID reconcile preserved the primary card.
bool? androidNotificationFirstPostAttemptSilent(String logcat) {
  for (final record in androidNotificationFlowRecords(logcat)) {
    if (!androidNotificationPostAttemptEvents.contains(record.event)) continue;
    final silent = record.details['silent'];
    return silent is bool ? silent : null;
  }
  return null;
}

/// Per-record `Notification(channel=…)` for the app's active cards whose
/// `android.text` equals [body].
///
/// Reads the raw dumpsys slice directly: `ActiveNotificationCard` carries no
/// channel field, and plan 378 deliberately does NOT add one to that shared
/// parser. Mirrors the extraction in
/// `integration_test/scripts/run_notification_sound_smoke.dart:308-341`.
List<String> androidNotificationChannelsForBody(
  String dump, {
  required String packageName,
  required String body,
}) {
  final activeSection = dump.split(RegExp(r'\nRanking Config:')).first;
  final packagePattern = RegExp(r'\bpkg=' + RegExp.escape(packageName) + r'\b');
  final bodyPattern = RegExp(
    r'^\s*android\.text=(?:[A-Za-z]*String \()?' +
        RegExp.escape(body) +
        r'\)?\s*$',
    multiLine: true,
  );
  return RegExp(r'NotificationRecord\([\s\S]*?(?=\n\s*NotificationRecord\(|$)')
      .allMatches(activeSection)
      .map((match) => match.group(0)!)
      .where(packagePattern.hasMatch)
      .where(bodyPattern.hasMatch)
      .map(
        (record) =>
            RegExp(
              r'Notification\(channel=([^\s\)]+)',
            ).firstMatch(record)?.group(1) ??
            '',
      )
      .toList(growable: false);
}

/// One `[FLOW] {…}` diagnostic record recovered from a logcat window.
final class AndroidFlowRecord {
  const AndroidFlowRecord({required this.event, required this.details});

  final String event;
  final Map<String, Object?> details;

  /// True when every entry of [expected] is present with an equal value.
  /// Extra details are ignored: the coordinator's SUCCESS record also carries
  /// registration-proof digests that legs must not have to enumerate.
  bool hasDetails(Map<String, Object?> expected) =>
      expected.entries.every((entry) => details[entry.key] == entry.value);
}

/// Every `[FLOW]` record in a cursor-scoped logcat window, in emission order.
///
/// Non-JSON tails and non-object payloads are skipped rather than thrown on:
/// the window is a shared device log and carries unrelated traffic.
List<AndroidFlowRecord> androidNotificationFlowRecords(String logcat) {
  final records = <AndroidFlowRecord>[];
  for (final line in const LineSplitter().convert(logcat)) {
    final flowIndex = line.indexOf('[FLOW] ');
    if (flowIndex < 0) continue;
    final Object? decoded;
    try {
      decoded = jsonDecode(line.substring(flowIndex + '[FLOW] '.length).trim());
    } on FormatException {
      continue;
    }
    if (decoded is! Map) continue;
    final event = decoded['event'];
    if (event is! String || event.isEmpty) continue;
    final details = decoded['details'];
    records.add(
      AndroidFlowRecord(
        event: event,
        details: details is Map
            ? details.map<String, Object?>(
                (key, value) => MapEntry('$key', value),
              )
            : const <String, Object?>{},
      ),
    );
  }
  return List<AndroidFlowRecord>.unmodifiable(records);
}

/// Center point and checked state of a uiautomator node addressed by its
/// `resource-id`.
///
/// The Settings channel screen's master toggle carries no text and no
/// content-desc, so [findSemanticNodeCenter] cannot address it. Measured on
/// `emulator-5554` (Android 17 / SDK 37): the channel master switch is
/// `android:id/switch_widget`, while every secondary row on the same screen
/// uses `com.android.settings:id/switchWidget` — the two ids are distinct, so
/// an exact-id match cannot pick up "Pop on screen" or "Vibration" by mistake.
({int x, int y, bool checked})? androidUiSwitchNodeByResourceId(
  String uiXml, {
  required String resourceId,
}) {
  for (final match in RegExp(r'<node\b[^>]*/?>').allMatches(uiXml)) {
    final node = match.group(0)!;
    final id = RegExp(r'resource-id="([^"]*)"').firstMatch(node)?.group(1);
    if (id != resourceId) continue;
    final bounds = RegExp(
      r'bounds="\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]"',
    ).firstMatch(node);
    if (bounds == null) continue;
    final left = int.parse(bounds.group(1)!);
    final top = int.parse(bounds.group(2)!);
    final right = int.parse(bounds.group(3)!);
    final bottom = int.parse(bounds.group(4)!);
    if (right <= left || bottom <= top) continue;
    return (
      x: (left + right) ~/ 2,
      y: (top + bottom) ~/ 2,
      checked:
          RegExp(r'checked="([^"]*)"').firstMatch(node)?.group(1) == 'true',
    );
  }
  return null;
}

/// The `mImportance` recorded for [channelId] in the package's durable channel
/// configuration, or null when the channel is absent from the dump.
///
/// Read from the same `dumpsys notification --noredact` slice the campaign's
/// end-state fingerprint hashes, so a channel the leg failed to re-enable is
/// visible to BOTH the leg and the restoration verify.
int? androidNotificationChannelImportance(
  String dumpsys, {
  required String packageName,
  required String channelId,
}) {
  final lines = dumpsys.split('\n');
  final packageHeader = RegExp(
    r'^\s+AppSettings:\s+' + RegExp.escape(packageName) + r'\s+\(',
  );
  final nextPackageHeader = RegExp(r'^\s+AppSettings:\s+');
  var inPackage = false;
  for (final raw in lines) {
    if (!inPackage) {
      if (!packageHeader.hasMatch(raw)) continue;
      inPackage = true;
      continue;
    }
    if (nextPackageHeader.hasMatch(raw)) break;
    final line = raw.trim();
    if (!line.startsWith('NotificationChannel{')) continue;
    if (!RegExp(r"mId='" + RegExp.escape(channelId) + r"'").hasMatch(line)) {
      continue;
    }
    final importance = RegExp(r'mImportance=(-?\d+)').firstMatch(line);
    if (importance == null) return null;
    return int.parse(importance.group(1)!);
  }
  return null;
}

String safeNotificationIdPrefix(String value) =>
    value.length <= 8 ? value : value.substring(0, 8);

enum AndroidNotificationActionResultDisposition {
  accepted,
  bindingMismatch,
  boundFailure,
  invalidCompletion,
}

/// Classifies an installed-app action receipt without trusting any values from
/// that receipt for diagnostics.
///
/// Binding is checked before failure state so a stale or forged receipt cannot
/// be reported as a failure from the staged request.
AndroidNotificationActionResultDisposition
classifyAndroidNotificationActionResult({
  required Map<String, Object?> result,
  required Map<String, Object?> config,
  required String expectedStatus,
}) {
  final bindingMatches =
      result['schema'] == androidNotificationPayloadE2EResultSchema &&
      result['transport_action'] == config['transport_action'] &&
      result['scenario'] == androidNotificationPayloadE2EScenario &&
      result['stepId'] == config['stepId'] &&
      result['runId'] == config['runId'] &&
      result['nonce'] == config['nonce'];
  if (!bindingMatches) {
    return AndroidNotificationActionResultDisposition.bindingMismatch;
  }
  if (result['status'] == 'failed' && result['success'] == false) {
    return AndroidNotificationActionResultDisposition.boundFailure;
  }
  if (result['status'] != expectedStatus || result['success'] != true) {
    return AndroidNotificationActionResultDisposition.invalidCompletion;
  }
  return AndroidNotificationActionResultDisposition.accepted;
}

const Set<String> _safeAndroidNotificationActionErrorTypes = <String>{
  'FileSystemException',
  'FirebaseException',
  'FormatException',
  'PlatformException',
  'SocketException',
  'StateError',
  'TimeoutException',
};

/// Returns only an explicitly allowlisted error class from a failure receipt.
/// Raw exception messages and arbitrary receipt content are never returned.
String safeAndroidNotificationActionErrorType(Object? value) =>
    value is String && _safeAndroidNotificationActionErrorTypes.contains(value)
    ? value
    : 'unavailable';

Map<String, Object?> androidNotificationScenarioArtifact({
  required String testCase,
  required String scenario,
  required List<String> devices,
  required Iterable<String> passedChecks,
  required Map<String, Object?> evidence,
  required DateTime capturedAt,
}) => <String, Object?>{
  'testCase': testCase,
  'scenario': scenario,
  'status': 'passed',
  'platform': 'android',
  'capturedAt': capturedAt.toUtc().toIso8601String(),
  'devices': List<String>.unmodifiable(devices),
  'checks': <String, bool>{for (final check in passedChecks) check: true},
  'evidence': evidence,
};
