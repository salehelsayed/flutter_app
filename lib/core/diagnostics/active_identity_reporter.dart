import 'dart:async';
import 'dart:convert';

import '../bridge/bridge.dart';
import 'app_diagnostics.dart';
import 'engagement_chat_checkpoint_store.dart';
import 'engagement_chat_observer.dart';
import 'group_engagement_observer.dart';

/// Calendar boundaries supplied by Go's Berlin calendar, never inferred in Dart.
typedef ActiveIdentityReporterWeek = ({
  String week,
  int startMilliseconds,
  int endMilliseconds,
});

/// Opaque logical ownership captured before a producer's first await.
final class ActiveIdentityReporterCapture {
  ActiveIdentityReporterCapture._({
    required ActiveIdentityReporter reporter,
    required Bridge bridge,
    required int generation,
    required String account,
    required String binding,
    required int epoch,
    EngagementChatObserverCapture? chatOwner,
  }) : _reporter = reporter,
       _bridge = bridge,
       _generation = generation,
       _account = account,
       _binding = binding,
       _epoch = epoch,
       _chatOwner = chatOwner;

  final ActiveIdentityReporter _reporter;
  final Bridge _bridge;
  final int _generation;
  final String _account;
  final String _binding;
  final int _epoch;
  final EngagementChatObserverCapture? _chatOwner;
}

/// Coordinates the current local owner; Go owns daily state and relay work.
final class ActiveIdentityReporter {
  ActiveIdentityReporter({
    required String statePath,
    EngagementChatCheckpointStore? groupWitnessStore,
    int Function()? groupNowMilliseconds,
    EngagementChatCheckpointStore? chatWitnessStore,
    int Function()? chatNowMilliseconds,
  }) : _statePath = statePath {
    if (groupWitnessStore != null) {
      _groups = GroupEngagementObserver(
        store: groupWitnessStore,
        nowMilliseconds:
            groupNowMilliseconds ?? () => DateTime.now().millisecondsSinceEpoch,
      );
    }
    if (chatWitnessStore != null) {
      _chat = EngagementChatObserver(
        store: chatWitnessStore,
        nowMilliseconds:
            chatNowMilliseconds ?? () => DateTime.now().millisecondsSinceEpoch,
        lookupWeek: (owner) async {
          final capture = _chatNativeOwnerFor(owner);
          return capture == null ? null : weeklyProjectionCaptured(capture);
        },
        retainChat: (owner, week) async {
          final capture = _chatNativeOwnerFor(owner);
          return capture != null && await markWeeklyCaptured(
            capture,
            week: week,
            kinds: const ['chat'],
          );
        },
      );
    }
  }

  static const _budget = Duration(seconds: 2);
  final String _statePath;
  GroupEngagementObserver? _groups;
  EngagementChatObserver? _chat;
  ActiveIdentityReporterCapture? _chatNativeOwner;
  Bridge? _bridge;
  LocalDiagnosticConsent? _consent;
  LocalDiagnosticConsent? _lastConsent;
  ({String account, String root, String binding})? _identity;
  Object? _logicalProfileMarker;
  Map<String, Object?>? _owner;
  Future<void>? _configuration;
  ({ActiveIdentityReporterCapture capture, int occurredAtUnixMillis})?
  _pendingFreshRegistration;
  int _generation = 0;
  bool _retired = false;
  bool _disposed = false;

  /// Pins loaded content to its logical profile, including while unarmed.
  Object? get logicalProfileMarker => _logicalProfileMarker;

  /// Resets a mounted visibility probe when its captured owner changes.
  /// The marker carries no account identifiers and adds no independent state.
  Object get observationMarker => (this, _generation);

  void attachBridge(Bridge bridge) {
    if (_disposed) return;
    if (identical(_bridge, bridge) && _owner != null) return;
    final pending = _pendingFreshRegistration;
    final registration = pending != null &&
            identical(pending.capture._bridge, bridge) &&
            _captureCurrent(pending.capture)
        ? pending
        : null;
    _bridge = bridge;
    unawaited(_configure());
    if (registration != null) {
      final capture = captureOwner(
        expectedAccountPeerId: registration.capture._account,
      );
      if (capture != null &&
          capture._generation == registration.capture._generation + 1) {
        markCaptured(
          capture,
          occurredAtUnixMillis: registration.occurredAtUnixMillis,
        );
      }
    }
  }

  /// A fresh local identity was durably committed, before runtime may be ready.
  void freshIdentityCommitted({
    required String accountPeerId,
    required int occurredAtUnixMillis,
  }) {
    final bridge = _bridge;
    final identity = _identity;
    final consent = _consent;
    if (_disposed || _retired || bridge == null || identity == null ||
        identity.account != accountPeerId || consent == null ||
        !consent.enabled) return;
    final capture = ActiveIdentityReporterCapture._(
      reporter: this,
      bridge: bridge,
      generation: _generation,
      account: identity.account,
      binding: identity.binding,
      epoch: consent.consentEpoch,
    );
    if (bridge.isInitialized) {
      markCaptured(capture, occurredAtUnixMillis: occurredAtUnixMillis);
    } else {
      _pendingFreshRegistration = (
        capture: capture,
        occurredAtUnixMillis: occurredAtUnixMillis,
      );
    }
  }

  void observeIdentity({
    required String? accountPeerId,
    required String? rootPrivateKeyBase64,
    String? profileBinding,
  }) {
    if (_disposed) return;
    if (accountPeerId == null && rootPrivateKeyBase64 == null) {
      unawaited(retire());
      return;
    }
    final binding = profileBinding;
    final next =
        binding != null &&
            RegExp(r'^v1:[0-9a-f]{64}$').hasMatch(binding) &&
            accountPeerId != null &&
            accountPeerId.isNotEmpty &&
            rootPrivateKeyBase64 != null &&
            rootPrivateKeyBase64.isNotEmpty
        ? (
            account: accountPeerId,
            root: rootPrivateKeyBase64,
            binding: binding,
          )
        : null;
    if (next == _identity && !_retired) return;
    final replacingKnownOwner = _identity != null && next == null;
    _identity = next;
    _logicalProfileMarker = next == null ? null : Object();
    _retired = replacingKnownOwner;
    unawaited(_configure(empty: replacingKnownOwner && _consent != null));
  }

  Future<void> observeConsent(LocalDiagnosticConsent? consent) {
    if (_disposed) return Future<void>.value();
    if (consent != null &&
        (consent.consentEpoch <= 0 ||
            consent.consentEpoch > 9007199254740991)) {
      _consent = null;
      return _configure(preserve: true, empty: true);
    }
    _consent = consent;
    if (consent != null) _lastConsent = consent;
    return _configure(preserve: consent == null, empty: consent == null);
  }

  Future<void> _configure({bool preserve = false, bool empty = false}) {
    final pending = _configureNow(preserve: preserve, empty: empty);
    _configuration = pending;
    final groups = _groups;
    if (groups != null) {
      if (!preserve && (_retired || _consent?.enabled == false)) {
        groups.revoke();
      } else {
        final account = _identity?.account;
        final capture = account == null || preserve
            ? null
            : captureOwner(expectedAccountPeerId: account);
        groups.replaceOwner(
          capture == null
              ? null
              : (
                  accountPeerId: capture._account,
                  profileBinding: capture._binding,
                  consentEpoch: capture._epoch,
                  isCurrent: () => _captureCurrent(capture),
                  lookupWeek: () => weeklyProjectionCaptured(capture),
                  retain: (String week) => markWeeklyCaptured(
                    capture,
                    week: week,
                    kinds: const ['group'],
                  ),
                ),
        );
      }
    }
    _chatNativeOwner = null;
    final chat = _chat;
    if (chat != null) {
      if (!preserve && (_retired || _consent?.enabled == false)) {
        chat.revoke();
      } else {
        final account = _identity?.account;
        final capture = account == null || preserve
            ? null
            : captureOwner(expectedAccountPeerId: account);
        chat.replaceOwner(
          capture == null
              ? null
              : (
                  accountPeerId: capture._account,
                  profileBinding: capture._binding,
                  consentEpoch: capture._epoch,
                ),
        );
        _chatNativeOwner = capture;
      }
    }
    return pending;
  }

  Future<void> _configureNow({
    bool preserve = false,
    bool empty = false,
  }) async {
    _pendingFreshRegistration = null;
    // This counter is only a Dart callback fence. Native alone issues the
    // revision admitted by Go, and a late receipt never replaces a newer owner.
    final generation = ++_generation;
    _owner = null;
    final bridge = _bridge;
    final consent = _consent ?? (empty ? _lastConsent : null);
    final identity = empty ? null : _identity;
    if (bridge == null || !bridge.isInitialized || consent == null) return;
    if (consent.enabled && identity == null && !_retired && !empty) return;
    final enabled = consent.enabled;
    final request = <String, Object?>{
      'version': 1,
      'op': 'configure',
      'enabled': enabled,
      'consentEpoch': consent.consentEpoch,
      'profileBinding': identity?.binding ?? '',
      'accountPeerId': identity?.account ?? '',
      'rootPrivateKeyBase64': enabled ? identity?.root ?? '' : '',
      'statePath': _statePath,
      'preservePendingOnUnarm': preserve && enabled,
    };
    final response = await _send(bridge, request);
    if (_disposed ||
        generation != _generation ||
        !identical(bridge, _bridge) ||
        !enabled ||
        identity == null ||
        empty) {
      return;
    }
    final data = response?['data'];
    if (response?['ok'] != true ||
        response!.length != 2 ||
        data is! Map ||
        data.length != 3 ||
        data['configured'] != true ||
        data['consentEpoch'] is! int ||
        data['consentEpoch'] != consent.consentEpoch) {
      return;
    }
    final revision = data['revision'];
    if (revision is! int || revision <= 0 || revision > 9007199254740991) {
      return;
    }
    _owner = {
      'version': 1,
      'revision': revision,
      'consentEpoch': consent.consentEpoch,
      'profileBinding': identity.binding,
      'accountPeerId': identity.account,
    };
  }

  Future<Map<String, dynamic>?> _send(
    Bridge bridge,
    Map<String, Object?> payload,
  ) async {
    try {
      final raw = await bridge
          .send(
            jsonEncode({
              'cmd': 'active_identity_reporter_v1',
              'payload': payload,
            }),
          )
          .timeout(_budget);
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      // Local reporting never owns communication or logs private native text.
      return null;
    }
  }

  /// Captures logical ownership even while its native configuration is pending.
  /// Capturing alone never marks activity and retains no root secret.
  ActiveIdentityReporterCapture? captureOwner({
    required String expectedAccountPeerId,
  }) {
    final bridge = _bridge;
    final identity = _identity;
    final consent = _consent;
    if (_disposed || _retired || bridge == null || !bridge.isInitialized ||
        identity == null || consent == null || !consent.enabled ||
        identity.account != expectedAccountPeerId) {
      return null;
    }
    return ActiveIdentityReporterCapture._(
      reporter: this,
      bridge: bridge,
      generation: _generation,
      account: identity.account,
      binding: identity.binding,
      epoch: consent.consentEpoch,
      chatOwner: _chat?.captureOwner(expectedAccountPeerId: identity.account),
    );
  }

  /// Renews consent/configuration ownership only for the original loaded profile.
  ActiveIdentityReporterCapture? captureForLoadedProfile({
    required Object originalProfileMarker,
    required String expectedAccountPeerId,
  }) {
    if (!identical(originalProfileMarker, _logicalProfileMarker)) return null;
    return captureOwner(expectedAccountPeerId: expectedAccountPeerId);
  }

  bool _captureCurrent(ActiveIdentityReporterCapture capture) {
    final identity = _identity;
    final consent = _consent;
    return !_disposed && !_retired &&
        identical(capture._reporter, this) &&
        identical(capture._bridge, _bridge) &&
        capture._bridge.isInitialized && capture._generation == _generation &&
        identity != null && identity.account == capture._account &&
        identity.binding == capture._binding && consent != null &&
        consent.enabled && consent.consentEpoch == capture._epoch;
  }

  /// Marks only the logical configuration captured before producer awaits.
  void markCaptured(
    ActiveIdentityReporterCapture capture, {
    int? occurredAtUnixMillis,
  }) {
    if (!_captureCurrent(capture)) {
      return;
    }
    final owner = _owner;
    if (owner == null) {
      // This future belongs to the capture's still-current generation. Never
      // mint a new capture or spend a successor's native revision on completion.
      final configuring = _configuration;
      if (configuring != null) {
        unawaited(
          configuring.then((_) {
            if (_captureCurrent(capture) && _owner != null) {
              markCaptured(capture, occurredAtUnixMillis: occurredAtUnixMillis);
            }
          }),
        );
      }
      return;
    }
    unawaited(_send(capture._bridge, {
      ...owner,
      'op': 'mark',
      if (occurredAtUnixMillis != null)
        'occurredAtUnixMillis': occurredAtUnixMillis,
    }));
  }

  Future<Map<String, Object?>?> _weeklyOwner(
    ActiveIdentityReporterCapture capture,
  ) async {
    if (!_captureCurrent(capture)) return null;
    if (_owner == null) await _configuration;
    return _captureCurrent(capture) ? _owner : null;
  }

  Map? _weeklyReceipt(
    ActiveIdentityReporterCapture capture,
    Map<String, Object?> owner,
    Map<String, dynamic>? response,
  ) {
    if (!_captureCurrent(capture) ||
        !identical(owner, _owner) ||
        response == null ||
        response.length != 2 ||
        response['ok'] != true) {
      return null;
    }
    final data = response['data'];
    if (data is! Map ||
        data.length != 3 ||
        data['revision'] is! int ||
        data['revision'] != owner['revision'] ||
        data['consentEpoch'] is! int ||
        data['consentEpoch'] != capture._epoch) {
      return null;
    }
    return data;
  }

  /// Reads the existing local Go projection; this never marks or uploads.
  Future<ActiveIdentityReporterWeek?> weeklyProjectionCaptured(
    ActiveIdentityReporterCapture capture,
  ) async {
    final owner = await _weeklyOwner(capture);
    if (owner == null || !_captureCurrent(capture) || !identical(owner, _owner))
      return null;
    final response = await _send(capture._bridge, {
      ...owner,
      'op': 'weeklyProjection',
    });
    final data = _weeklyReceipt(capture, owner, response);
    final value = data?['weekly'];
    if (value is! Map ||
        value.length != 5 ||
        !_validWeek(value['week']) ||
        !_validMillis(value['startUnixMillis']) ||
        !_validMillis(value['endUnixMillis']) ||
        value['endUnixMillis'] <= value['startUnixMillis'] ||
        !_validWeeklyKinds(value['kinds'], allowEmpty: true)) {
      return null;
    }
    final acknowledged = value['acknowledged'];
    if (acknowledged is! List || acknowledged.length > 64) return null;
    for (final ack in acknowledged) {
      if (ack is! Map ||
          ack.length != 2 ||
          ack['relayPeerId'] is! String ||
          (ack['relayPeerId'] as String).isEmpty ||
          !_validWeeklyKinds(ack['kinds']))
        return null;
    }
    return (
      week: value['week'] as String,
      startMilliseconds: value['startUnixMillis'] as int,
      endMilliseconds: value['endUnixMillis'] as int,
    );
  }

  /// Retains only existing identity bits in Go, after a qualified local witness.
  /// A positive receipt is local persistence, never a relay delivery ACK.
  Future<bool> markWeeklyCaptured(
    ActiveIdentityReporterCapture capture, {
    required String week,
    required List<String> kinds,
  }) async {
    final ownedKinds = List<String>.of(kinds);
    if (!_validWeek(week) || !_validWeeklyKinds(ownedKinds)) return false;
    final owner = await _weeklyOwner(capture);
    if (owner == null || !_captureCurrent(capture) || !identical(owner, _owner))
      return false;
    final response = await _send(capture._bridge, {
      ...owner,
      'op': 'markWeekly',
      'week': week,
      'kinds': ownedKinds,
    });
    return _weeklyReceipt(capture, owner, response)?['accepted'] == true;
  }

  static bool _validWeek(Object? week) =>
      week is String &&
      week.length == 8 &&
      RegExp(r'^[0-9]{4}-W(0[1-9]|[1-4][0-9]|5[0-3])$').hasMatch(week);

  static bool _validMillis(Object? value) =>
      value is int &&
      value >= -9007199254740991 &&
      value <= 9007199254740991;

  static bool _validWeeklyKinds(Object? kinds, {bool allowEmpty = false}) =>
      kinds is List &&
      kinds.length <= 4 &&
      (allowEmpty || kinds.isNotEmpty) &&
      kinds.every(
        (kind) => const ['active', 'chat', 'call', 'group'].contains(kind),
      ) &&
      kinds.toSet().length == kinds.length;

  ActiveIdentityReporterCapture? _chatNativeOwnerFor(
    EngagementChatObserverCapture owner,
  ) {
    final capture = _chatNativeOwner;
    if (capture == null || !_captureCurrent(capture) ||
        !identical(
          _chat?.captureOwner(expectedAccountPeerId: capture._account),
          owner,
        )) return null;
    return capture;
  }

  bool _chatCaptureCurrent(ActiveIdentityReporterCapture capture) =>
      _captureCurrent(capture) && capture._chatOwner != null &&
      identical(
        _chat?.captureOwner(expectedAccountPeerId: capture._account),
        capture._chatOwner,
      );

  /// Reserve a fresh known initial tuple before its durable staging starts.
  EngagementChatObserverIntent? reserveChatCaptured(
    ActiveIdentityReporterCapture capture, {
    required String contactAccountPeerId,
    required String messageId,
    required String generationId,
  }) {
    if (!_chatCaptureCurrent(capture)) return null;
    return _chat?.reserve(
      capture._chatOwner!,
      contactAccount: contactAccountPeerId,
      messageId: messageId,
      generationId: generationId,
    );
  }

  /// Only a fresh typed durable applied result admits the reserved intent.
  void admitChatCaptured(
    ActiveIdentityReporterCapture capture,
    EngagementChatObserverIntent intent,
  ) {
    if (_chatCaptureCurrent(capture) &&
        identical(capture._chatOwner, intent.owner)) _chat?.admitted(intent);
  }

  void cancelChatCaptured(
    ActiveIdentityReporterCapture capture,
    EngagementChatObserverIntent intent,
  ) {
    if (_chatCaptureCurrent(capture) &&
        identical(capture._chatOwner, intent.owner)) _chat?.cancel(intent);
  }

  /// A trusted authenticated delivery must have newly committed locally.
  void chatDeliveredCaptured(
    ActiveIdentityReporterCapture capture, {
    required String contactAccountPeerId,
    required String messageId,
    required String generationId,
  }) {
    if (!_chatCaptureCurrent(capture)) return;
    _chat?.delivered(
      capture._chatOwner!,
      contactAccount: contactAccountPeerId,
      messageId: messageId,
      generationId: generationId,
    );
  }

  /// Only fresh, durably applied incoming initial content reaches this hook.
  void chatIncomingCaptured(
    ActiveIdentityReporterCapture capture, {
    required String contactAccountPeerId,
  }) {
    if (!_chatCaptureCurrent(capture)) return;
    _chat?.incoming(capture._chatOwner!, contactAccount: contactAccountPeerId);
  }

  /// Call only for a fresh, durably committed own content post.
  void groupPostCommittedCaptured(
    ActiveIdentityReporterCapture capture, {
    required String groupId,
  }) {
    if (_captureCurrent(capture)) _groups?.observe(groupId: groupId, own: true);
  }

  /// Call only after eligible other-account content was painted in active UI.
  void groupOtherPostVisibleCaptured(
    ActiveIdentityReporterCapture capture, {
    required String groupId,
    required String authorAccountPeerId,
    required int postOccurredAtUnixMillis,
  }) {
    if (!_captureCurrent(capture) ||
        !GroupEngagementObserver.validIdentifier(authorAccountPeerId) ||
        authorAccountPeerId == capture._account)
      return;
    _groups?.observe(
      groupId: groupId,
      own: false,
      postMilliseconds: postOccurredAtUnixMillis,
    );
  }

  /// Called only after a qualifying communication, never by configuration.
  void mark() {
    final owner = _owner;
    final bridge = _bridge;
    if (_disposed || bridge == null || !bridge.isInitialized) return;
    if (owner == null) {
      final configuring = _configuration;
      final generation = _generation;
      if (configuring != null &&
          _consent?.enabled == true &&
          _identity != null) {
        unawaited(
          configuring.then((_) {
            if (!_disposed && generation == _generation && _owner != null) {
              mark();
            }
          }),
        );
      }
      return;
    }
    unawaited(_send(bridge, {...owner, 'op': 'mark'}));
  }

  Future<void> retire() {
    if (_disposed) return Future<void>.value();
    _identity = null;
    _logicalProfileMarker = null;
    _retired = true;
    return _configure(empty: true);
  }

  Future<void> flush() async {
    await _groups?.flush();
    await _chat?.flush();
    final owner = _owner;
    final bridge = _bridge;
    if (_disposed || owner == null || bridge == null || !bridge.isInitialized) {
      return;
    }
    await _send(bridge, {...owner, 'op': 'flush'});
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _identity = null;
    _logicalProfileMarker = null;
    await _configure(preserve: true, empty: true);
    await _groups?.dispose();
    await _chat?.dispose();
    _chatNativeOwner = null;
    _bridge = null;
    _consent = null;
    _lastConsent = null;
  }
}
