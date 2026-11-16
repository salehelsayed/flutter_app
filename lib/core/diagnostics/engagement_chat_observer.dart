import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'engagement_chat_checkpoint_store.dart';
import 'engagement_chat_witness.dart';

typedef EngagementChatObserverOwner = ({
  String accountPeerId,
  String profileBinding,
  int consentEpoch,
});

/// Supplied by the canonical Go calendar; no event timestamps are sent to it.
typedef EngagementChatWeekInterval = ({
  String week,
  int startMilliseconds,
  int endMilliseconds,
});

typedef EngagementChatWeekLookup =
    Future<EngagementChatWeekInterval?> Function(
      EngagementChatObserverCapture owner,
    );
typedef EngagementChatLocalRetention =
    Future<bool> Function(EngagementChatObserverCapture owner, String week);

final class EngagementChatObserverCapture {
  EngagementChatObserverCapture._(this.owner);

  final EngagementChatObserverOwner owner;
}

final class EngagementChatObserverIntent {
  EngagementChatObserverIntent._({
    required this.owner,
    required this.contactAccount,
    required this.messageId,
    required this.generationId,
    required int observedMilliseconds,
  }) : _observedMilliseconds = observedMilliseconds;

  final EngagementChatObserverCapture owner;
  final String contactAccount;
  final String messageId;
  final String generationId;
  final int _observedMilliseconds;
  bool _admissionSubmitted = false;
  bool _cancelled = false;
  EngagementChatIntent? _witnessIntent;
}

/// Producer callbacks capture facts synchronously and never join optional I/O.
/// The trusted pure witness owns qualification and its private snapshot schema.
final class EngagementChatObserver {
  EngagementChatObserver({
    required this.store,
    required this.lookupWeek,
    required this.retainChat,
    required this.nowMilliseconds,
  });

  static const _deadline = Duration(seconds: 1);
  final EngagementChatCheckpointStore store;
  final EngagementChatWeekLookup lookupWeek;
  final EngagementChatLocalRetention retainChat;
  final int Function() nowMilliseconds;
  final Queue<_ChatFact> _facts = Queue<_ChatFact>();
  final Set<EngagementChatObserverIntent> _intents = {};
  final Map<_Tuple, EngagementChatObserverIntent> _tuples = {};
  EngagementChatObserverCapture? _capture;
  EngagementChatObserverCapture? _contextOwner;
  EngagementChatWeekInterval? _week;
  EngagementChatWitness? _witness;
  EngagementChatCapture? _witnessCapture;
  Future<void>? _worker;
  int _generation = 0;
  bool _inFlight = false;
  bool _initialize = false;
  bool _clear = false;
  bool _disposed = false;
  bool _attemptedRetention = false;
  bool _storageFailed = false;
  EngagementChatObserverCapture? _calendarFailed;

  EngagementChatPhase get phase =>
      _witness?.phase ?? EngagementChatPhase.collecting;

  /// Null temporarily unarms observation without clearing the private checkpoint.
  void replaceOwner(EngagementChatObserverOwner? owner) {
    if (_disposed) {
      return;
    }
    _invalidate();
    if (owner != null &&
        _identifier(owner.accountPeerId) &&
        _identifier(owner.profileBinding) && owner.consentEpoch > 0) {
      _capture = EngagementChatObserverCapture._(owner);
      _initialize = true;
    }
    _start();
  }

  /// A diagnostics OFF decision also requests private witness removal.
  void revoke() {
    if (_disposed) {
      return;
    }
    _invalidate();
    _clear = true;
    _start();
  }

  void _invalidate() {
    _generation++;
    _capture = null;
    _contextOwner = null;
    _week = null;
    _witness?.revoke();
    _witness = null;
    _witnessCapture = null;
    _facts.clear();
    _intents.clear();
    _tuples.clear();
    _initialize = false;
    _clear = false;
  }

  bool _current(EngagementChatObserverCapture capture) =>
      !_disposed && identical(_capture, capture);

  EngagementChatObserverCapture? captureOwner({
    required String expectedAccountPeerId,
  }) {
    final capture = _capture;
    if (capture == null ||
        capture.owner.accountPeerId != expectedAccountPeerId) {
      return null;
    }
    return capture;
  }

  bool get _room => _facts.length + (_inFlight ? 1 : 0) < 64;

  int? _observe(EngagementChatObserverCapture capture) {
    if (!_current(capture) || !_room) {
      return null;
    }
    try {
      return nowMilliseconds();
    } catch (_) {
      return null;
    }
  }

  EngagementChatObserverIntent? reserve(
    EngagementChatObserverCapture capture, {
    required String contactAccount,
    required String messageId,
    required String generationId,
  }) {
    if (_contextCurrent(capture) && phase != EngagementChatPhase.collecting) {
      return null;
    }
    final observed = _observe(capture);
    final tuple = (contact: contactAccount, message: messageId, generation: generationId);
    if (observed == null || _intents.length >= 256 ||
        !_identifier(contactAccount) || !_identifier(messageId) ||
        !_identifier(generationId) || _tuples.containsKey(tuple)) {
      return null;
    }
    final intent = EngagementChatObserverIntent._(
      owner: capture,
      contactAccount: contactAccount,
      messageId: messageId,
      generationId: generationId,
      observedMilliseconds: observed,
    );
    _intents.add(intent);
    _tuples[tuple] = intent;
    _enqueue(_Reserved(capture, observed, intent));
    return intent;
  }

  void admitted(EngagementChatObserverIntent intent) {
    final observed = _observe(intent.owner);
    if (observed == null || !_intents.contains(intent) ||
        intent._cancelled || intent._admissionSubmitted) {
      return;
    }
    // Admission is already durable at this callback. A subsequent cancellation
    // cannot erase it while the optional calendar worker is still waiting.
    intent._admissionSubmitted = true;
    _enqueue(_Admitted(intent.owner, observed, intent));
  }

  void cancel(EngagementChatObserverIntent intent) {
    final observed = _observe(intent.owner);
    if (observed == null || !_intents.contains(intent) ||
        intent._cancelled || intent._admissionSubmitted) {
      return;
    }
    intent._cancelled = true;
    _removeTuple(intent);
    _enqueue(_Cancelled(intent.owner, observed, intent));
  }

  void delivered(
    EngagementChatObserverCapture capture, {
    required String contactAccount,
    required String messageId,
    required String generationId,
  }) {
    final observed = _observe(capture);
    if (observed == null || !_identifier(contactAccount) ||
        !_identifier(messageId) || !_identifier(generationId)) {
      return;
    }
    _enqueue(_Delivered(capture, observed,
      (contact: contactAccount, message: messageId, generation: generationId)));
  }

  void incoming(
    EngagementChatObserverCapture capture, {
    required String contactAccount,
  }) {
    final observed = _observe(capture);
    if (observed == null || !_identifier(contactAccount)) {
      return;
    }
    _enqueue(_Incoming(capture, observed, contactAccount));
  }

  void _enqueue(_ChatFact fact) {
    _facts.add(fact);
    _start();
  }

  void _start() {
    if (_worker != null || _disposed) {
      return;
    }
    _worker = Future<void>(() async {
      _attemptedRetention = false;
      _storageFailed = false;
      _calendarFailed = null;
      try {
        await _drain();
      } catch (_) {
        // A failed optional observer operation never escapes into communication.
      } finally {
        _worker = null;
        if (_clear || _initialize || _facts.isNotEmpty) {
          _start();
        }
      }
    });
  }

  Future<void> _drain() async {
    while (!_disposed) {
      if (_clear) {
        _clear = false;
        final generation = _generation;
        await _storeCall(
          (guard) => store.clear(isCurrent: guard),
          () => !_disposed && _generation == generation && _capture == null,
        );
        continue;
      }
      if (_initialize) {
        _initialize = false;
        final capture = _capture;
        if (capture != null) {
          await _prepare(capture);
        }
        continue;
      }
      if (_facts.isEmpty) {
        final capture = _capture;
        if (capture != null && _contextCurrent(capture) &&
            phase == EngagementChatPhase.qualifiedPending &&
            !_attemptedRetention && !_storageFailed) {
          await _checkpoint(capture);
          continue;
        }
        break;
      }
      final fact = _facts.removeFirst();
      _inFlight = true;
      try {
        if (await _prepare(fact.owner) &&
            _contextCurrent(fact.owner) &&
            _contains(_week!, fact.observedMilliseconds)) {
          _apply(fact);
          await _checkpoint(fact.owner);
        } else if (fact is _Reserved) {
          _removeIntent(fact.intent);
        }
      } catch (_) {
        // Optional witness work must never affect the communication caller.
      } finally {
        _inFlight = false;
      }
    }
  }

  Future<bool> _prepare(EngagementChatObserverCapture capture) async {
    if (!_current(capture) || identical(_calendarFailed, capture)) {
      return false;
    }
    final interval = _week;
    if (interval != null && _contextCurrent(capture)) {
      return true;
    }
    EngagementChatWeekInterval? resolved;
    try {
      resolved = await lookupWeek(capture).timeout(_deadline);
      if (!_current(capture)) {
        return false;
      }
      if (resolved == null || resolved.startMilliseconds >= resolved.endMilliseconds ||
          !RegExp(r'^\d{4}-W(?:0[1-9]|[1-4]\d|5[0-3])$').hasMatch(resolved.week) ||
          !_contains(resolved, nowMilliseconds())) {
        _calendarFailed = capture;
        return false;
      }
    } catch (_) {
      _calendarFailed = capture;
      return false;
    }
    final witness = EngagementChatWitness(scope: (
      profileBinding: capture.owner.profileBinding,
      consentEpoch: capture.owner.consentEpoch,
      week: resolved.week,
    ));
    _contextOwner = capture;
    _attemptedRetention = false;
    _storageFailed = false;
    _week = resolved;
    _witness = witness;
    _witnessCapture = witness.captureOwner();
    for (final intent in _intents.toList()) {
      intent._witnessIntent = null;
      if (!_contains(resolved, intent._observedMilliseconds)) {
        _removeIntent(intent);
      }
    }
    var waiting = true;
    try {
      final bytes = await store.read(
        isCurrent: () => waiting && _contextCurrent(capture, witness),
      ).timeout(_deadline, onTimeout: () => null);
      if (bytes != null && _contextCurrent(capture, witness)) {
        witness.restoreSnapshot(_witnessCapture!, bytes);
        _discardConsumedIntents(witness.encodeSnapshot());
      }
    } catch (_) {
      // A missing, corrupt or unavailable checkpoint supplies no evidence.
    } finally {
      waiting = false;
    }
    return _contextCurrent(capture, witness);
  }

  bool _contextCurrent(EngagementChatObserverCapture capture,
      [EngagementChatWitness? witness]) {
    try {
      final interval = _week;
      return _current(capture) && identical(_contextOwner, capture) &&
          (witness == null || identical(_witness, witness)) && interval != null &&
          _contains(interval, nowMilliseconds());
    } catch (_) {
      return false;
    }
  }

  void _apply(_ChatFact fact) {
    final witness = _witness!;
    final capture = _witnessCapture!;
    switch (fact) {
      case _Reserved(:final intent):
        intent._witnessIntent = witness.reserve(capture,
          contactAccount: intent.contactAccount, messageId: intent.messageId,
          generationId: intent.generationId);
        if (intent._witnessIntent == null) {
          _removeIntent(intent);
        }
      case _Admitted(:final intent):
        final reserved = intent._witnessIntent;
        if (reserved != null) {
          witness.admitted(reserved);
        }
      case _Cancelled(:final intent):
        final reserved = intent._witnessIntent;
        if (reserved != null) {
          witness.cancel(reserved);
        }
        _removeIntent(intent);
      case _Delivered(:final tuple):
        witness.delivered(capture, contactAccount: tuple.contact,
          messageId: tuple.message, generationId: tuple.generation);
      case _Incoming(:final contact):
        witness.incoming(capture, contactAccount: contact);
    }
  }

  Future<void> _checkpoint(EngagementChatObserverCapture capture) async {
    final witness = _witness!;
    if (!_contextCurrent(capture, witness)) {
      return;
    }
    final bytes = witness.encodeSnapshot();
    _discardConsumedIntents(bytes);
    final pending = witness.phase == EngagementChatPhase.qualifiedPending;
    if (_storageFailed || (pending && _attemptedRetention)) {
      return;
    }
    if (pending) {
      _attemptedRetention = true;
    }
    final committed = await _storeCall(
      (guard) => store.replace(bytes, isCurrent: guard),
      () => _contextCurrent(capture, witness),
    );
    if (!committed) {
      _storageFailed = true;
      return;
    }
    if (!pending || !_contextCurrent(capture, witness)) {
      return;
    }
    bool retained;
    try {
      retained = await retainChat(capture, _week!.week)
          .timeout(_deadline, onTimeout: () => false);
    } catch (_) {
      retained = false;
    }
    // A local durable ACK belongs to this exact runtime owner, not merely to
    // an equal profile/epoch/week tuple or a relay acknowledgement.
    if (!retained || !_contextCurrent(capture, witness)) {
      return;
    }
    witness.confirmRetained(_witnessCapture!);
    await _storeCall(
      (guard) => store.replace(witness.encodeSnapshot(), isCurrent: guard),
      () => _contextCurrent(capture, witness),
    );
  }

  Future<bool> _storeCall(
    Future<bool> Function(bool Function()) operation,
    bool Function() current,
  ) async {
    var waiting = true;
    try {
      return await operation(() => waiting && current())
          .timeout(_deadline, onTimeout: () => false);
    } catch (_) {
      return false;
    } finally {
      // The store's physical writer remains fenced after this optional wait.
      waiting = false;
    }
  }

  void _discardConsumedIntents(Uint8List snapshot) {
    if (phase != EngagementChatPhase.collecting) {
      _intents.clear();
      _tuples.clear();
      _facts.clear();
      return;
    }
    // Read only our trusted, bounded codec output to release routing handles
    // when the leaf has collapsed exact references to a per-contact bit.
    final root = jsonDecode(utf8.decode(snapshot)) as Map<String, dynamic>;
    final delivered = <String>{
      for (final contact in root['contacts'] as List<dynamic>)
        if ((contact as Map<String, dynamic>)['deliveredOutgoingSeen'] == true)
          contact['account'] as String,
    };
    for (final intent in _intents.toList()) {
      if (delivered.contains(intent.contactAccount)) {
        _removeIntent(intent);
      }
    }
  }

  void _removeIntent(EngagementChatObserverIntent intent) {
    _intents.remove(intent);
    _removeTuple(intent);
    intent._witnessIntent = null;
  }

  void _removeTuple(EngagementChatObserverIntent intent) {
    final tuple = (contact: intent.contactAccount, message: intent.messageId,
      generation: intent.generationId);
    if (identical(_tuples[tuple], intent)) {
      _tuples.remove(tuple);
    }
  }

  static bool _contains(EngagementChatWeekInterval interval, int milliseconds) =>
      milliseconds >= interval.startMilliseconds && milliseconds < interval.endMilliseconds;

  static bool _identifier(String value) {
    if (value.isEmpty || value.length > 256) {
      return false;
    }
    final bytes = utf8.encode(value);
    return bytes.length <= 256 && utf8.decode(bytes) == value;
  }

  /// Joins accepted work and permits one bounded retry of retained pending work.
  Future<void> flush() async {
    if (_disposed) {
      return;
    }
    final capture = _capture;
    if (capture != null && !_contextCurrent(capture)) {
      _initialize = true;
    }
    _start();
    while (_worker != null) {
      await _worker;
    }
  }

  Future<void> dispose() async {
    if (!_disposed) {
      _invalidate();
      _disposed = true;
    }
    await _worker;
    // The supplied store is externally owned and remains usable on restart.
  }
}

typedef _Tuple = ({String contact, String message, String generation});

sealed class _ChatFact {
  const _ChatFact(this.owner, this.observedMilliseconds);
  final EngagementChatObserverCapture owner;
  final int observedMilliseconds;
}

final class _Reserved extends _ChatFact {
  const _Reserved(super.owner, super.observedMilliseconds, this.intent);
  final EngagementChatObserverIntent intent;
}

final class _Admitted extends _ChatFact {
  const _Admitted(super.owner, super.observedMilliseconds, this.intent);
  final EngagementChatObserverIntent intent;
}

final class _Cancelled extends _ChatFact {
  const _Cancelled(super.owner, super.observedMilliseconds, this.intent);
  final EngagementChatObserverIntent intent;
}

final class _Delivered extends _ChatFact {
  const _Delivered(super.owner, super.observedMilliseconds, this.tuple);
  final _Tuple tuple;
}

final class _Incoming extends _ChatFact {
  const _Incoming(super.owner, super.observedMilliseconds, this.contact);
  final String contact;
}
