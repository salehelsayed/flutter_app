import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show MissingPluginException;

import '../../../core/bridge/bridge.dart';
import '../../../core/utils/flow_event_emitter.dart';
import '../application/call_scoped_media_bundle_owner.dart';

/// How one exchange with the broker ended.
enum _Exchange {
  /// Go answered (`ok: true`); the body says whether it granted or released.
  answered,

  /// The bridge or Go rejected the request (`ok: false`).
  rejected,

  /// The native method does not exist: an older binary without the broker.
  unavailable,

  /// The bridge threw or answered something that is not JSON.
  failed,
}

/// One decoded bridge answer, or the error that replaced it.
typedef _Answer = ({Map<String, dynamic>? response, Object? error});

/// Holds the Go relay recovery broker's call-media protection
/// (`call_media:protection`) for one media bundle at a time.
///
/// Wire contract, shared with Go:
///
///     acquire {held: true, generation: G}
///       -> {ok: true, held: true, generation: G, incarnation: I}
///       -> {ok: true, held: false, generation: G,
///           reason: restart_in_progress | not_started | superseded}
///     release {held: false, generation: G, incarnation: I}
///       -> {ok: true, held: false, released: true | false}
///
/// Go grants when G is at least its holder's generation, clears its holder
/// only for exactly (G, I), and moves to a new incarnation on every node
/// Stop/Reset. Generations grow for the whole process, so a lease built after
/// an earlier one (a rebuilt call graph) never asks below a hold that earlier
/// lease left behind. Every failure is absorbed and named in one bounded flow
/// event; only a missing native method lets the call run without protection.
final class BridgeCallMediaProtectionLease implements CallMediaProtectionLease {
  BridgeCallMediaProtectionLease({
    required Bridge bridge,
    this.timeout = const Duration(seconds: 1),
  }) : _bridge = bridge;

  final Bridge _bridge;

  /// Bounds one exchange. An acquire that outlives it answers refused, and
  /// the grant Go may still produce for it is handed straight back.
  final Duration timeout;

  static int _lastGeneration = 0;

  /// Lets a test file start again at generation 1.
  @visibleForTesting
  static void resetGenerations() {
    _lastGeneration = 0;
  }

  @override
  Future<CallMediaProtectionAdmission> acquire() async {
    final generation = ++_lastGeneration;
    final exchange = _exchange(held: true, generation: generation);
    final _Answer answer;
    try {
      answer = await exchange.timeout(timeout);
    } on TimeoutException {
      unawaited(exchange.then(_handBackLateGrant(generation)));
      _report(action: 'acquire', outcome: 'timeout', generation: generation);
      return const CallMediaProtectionRefused('timeout');
    }
    final admission = switch (_classify(answer)) {
      _Exchange.unavailable => const CallMediaProtectionUnavailable(),
      _Exchange.failed => const CallMediaProtectionRefused('error'),
      _Exchange.rejected => CallMediaProtectionRefused(
        _word(answer.response!['errorCode'], fallback: 'rejected'),
      ),
      _Exchange.answered => _answeredAdmission(answer.response!, generation),
    };
    switch (admission) {
      case CallMediaProtectionGranted(:final grant):
        _report(
          action: 'acquire',
          outcome: 'held',
          generation: generation,
          incarnation: grant.incarnation,
        );
      case CallMediaProtectionRefused(:final reason):
        _report(
          action: 'acquire',
          outcome: 'refused',
          generation: generation,
          reason: reason,
        );
      case CallMediaProtectionUnavailable():
        _report(
          action: 'acquire',
          outcome: 'unavailable',
          generation: generation,
        );
    }
    return admission;
  }

  @override
  Future<void> release(CallMediaProtectionGrant grant) async {
    final _Answer answer;
    try {
      answer = await _exchange(
        held: false,
        generation: grant.generation,
        incarnation: grant.incarnation,
      ).timeout(timeout);
    } on TimeoutException {
      _reportRelease(grant, 'timeout');
      return;
    }
    _reportRelease(grant, switch (_classify(answer)) {
      _Exchange.unavailable => 'unavailable',
      _Exchange.failed => 'error',
      _Exchange.rejected => 'refused',
      // `ignored`: the holder was not exactly this grant, so Go kept it.
      _Exchange.answered =>
        answer.response!['released'] == true ? 'released' : 'ignored',
    });
  }

  /// Compensates a grant that reached Dart after [acquire] stopped waiting.
  /// Nothing here ever adopted it, and the exact pair cannot clear a later
  /// grant, so handing it back is always safe.
  FutureOr<void> Function(_Answer) _handBackLateGrant(int generation) =>
      (late) {
        final grant = _grantOf(late.response, generation);
        if (grant != null) unawaited(release(grant));
      };

  static CallMediaProtectionAdmission _answeredAdmission(
    Map<String, dynamic> response,
    int generation,
  ) {
    if (response['held'] != true) {
      return CallMediaProtectionRefused(
        _word(response['reason'], fallback: 'refused'),
      );
    }
    final grant = _grantOf(response, generation);
    // Held, but not as (G, I) for this request: an answer outside the
    // contract. Protection is not confirmed, so media must not open on it.
    return grant == null
        ? const CallMediaProtectionRefused('malformed')
        : CallMediaProtectionGranted(grant);
  }

  /// The grant in an acquire answer for [generation], or null when the answer
  /// grants nothing or names a different holder.
  static CallMediaProtectionGrant? _grantOf(
    Map<String, dynamic>? response,
    int generation,
  ) {
    if (response == null ||
        response['ok'] != true ||
        response['held'] != true ||
        (response['generation'] as num?)?.toInt() != generation) {
      return null;
    }
    final incarnation = response['incarnation'];
    if (incarnation is! num) return null;
    return CallMediaProtectionGrant(
      generation: generation,
      incarnation: incarnation.toInt(),
    );
  }

  /// The bridge client's words for a native method that does not exist. Only
  /// these (and a raw MissingPluginException) mean no broker exists, which
  /// is the one fail-open case; every other refusal keeps media closed.
  static const Set<String> _missingMethodCodes = <String>{
    'MISSING_PLUGIN',
    'NOT_IMPLEMENTED',
  };

  static _Exchange _classify(_Answer answer) {
    final response = answer.response;
    if (response == null) {
      return answer.error is MissingPluginException
          ? _Exchange.unavailable
          : _Exchange.failed;
    }
    if (response['ok'] == true) return _Exchange.answered;
    return _missingMethodCodes.contains(response['errorCode'])
        ? _Exchange.unavailable
        : _Exchange.rejected;
  }

  static String _word(Object? value, {required String fallback}) =>
      value is String && value.isNotEmpty ? value : fallback;

  Future<_Answer> _exchange({
    required bool held,
    required int generation,
    int? incarnation,
  }) async {
    final request = jsonEncode(<String, Object?>{
      'cmd': 'call_media:protection',
      'payload': <String, Object?>{
        'held': held,
        'generation': generation,
        'incarnation': ?incarnation,
      },
    });
    try {
      final raw = await _bridge.send(request);
      return (response: jsonDecode(raw) as Map<String, dynamic>, error: null);
    } catch (error) {
      return (response: null, error: error);
    }
  }

  void _reportRelease(CallMediaProtectionGrant grant, String outcome) =>
      _report(
        action: 'release',
        outcome: outcome,
        generation: grant.generation,
        incarnation: grant.incarnation,
      );

  void _report({
    required String action,
    required String outcome,
    required int generation,
    int? incarnation,
    String? reason,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_MEDIA_PROTECTION',
      details: <String, Object?>{
        'action': action,
        'outcome': outcome,
        'generation': generation,
        'incarnation': ?incarnation,
        'reason': ?reason,
      },
    );
  }
}
