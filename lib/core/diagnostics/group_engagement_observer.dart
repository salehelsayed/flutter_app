import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'engagement_chat_checkpoint_store.dart';

typedef _Week = ({String week, int startMilliseconds, int endMilliseconds});
typedef GroupEngagementOwner = ({
  String accountPeerId,
  String profileBinding,
  int consentEpoch,
  bool Function() isCurrent,
  Future<_Week?> Function() lookupWeek,
  Future<bool> Function(String week) retain,
});

enum _Phase { collecting, pending, retained }

/// Optional private group evidence. Native receives only a qualified weekly bit.
final class GroupEngagementObserver {
  GroupEngagementObserver({required this.store, required this.nowMilliseconds});

  static const _deadline = Duration(seconds: 1);
  static const _bound = 64;
  final EngagementChatCheckpointStore store;
  final int Function() nowMilliseconds;
  final _facts = Queue<({String group, int bit, int observed, int? post})>();
  final _groups = <String, int>{};
  GroupEngagementOwner? _owner;
  ({String account, String binding, int epoch})? _lastScope;
  _Week? _week;
  _Phase _phase = _Phase.collecting;
  Future<void>? _worker;
  int _generation = 0;
  int _wake = 0;
  int _handledWake = 0;
  bool _clear = false;
  bool _disposed = false;
  bool _inFlight = false;
  bool _attempted = false;
  bool _storageFailed = false;
  bool _calendarFailed = false;
  bool _dirty = false;

  /// A temporary unarm preserves the checkpoint; replacement scopes erase it.
  void replaceOwner(GroupEngagementOwner? owner) {
    if (_disposed) return;
    _invalidate();
    if (owner != null) {
      final scope = (
        account: owner.accountPeerId,
        binding: owner.profileBinding,
        epoch: owner.consentEpoch,
      );
      if (_lastScope != null && _lastScope != scope) _clear = true;
      _lastScope = scope;
      _owner = owner;
    }
    _start();
  }

  void revoke() {
    if (_disposed) return;
    _invalidate();
    _clear = true;
    _start();
  }

  void _invalidate() {
    _generation++;
    _wake++;
    _owner = null;
    _week = null;
    _phase = _Phase.collecting;
    _dirty = false;
    _groups.clear();
    _facts.clear();
  }

  bool _live(GroupEngagementOwner owner) =>
      !_disposed && owner == _owner && owner.isCurrent();

  bool _context(GroupEngagementOwner owner, _Week week) =>
      _live(owner) && week == _week && _contains(week, nowMilliseconds());

  void observe({
    required String groupId,
    required bool own,
    int? postMilliseconds,
  }) {
    final owner = _owner;
    if (owner == null ||
        !_live(owner) ||
        !validIdentifier(groupId) ||
        _facts.length + (_inFlight ? 1 : 0) >= _bound) {
      return;
    }
    final observed = nowMilliseconds();
    if (!own &&
        (postMilliseconds == null ||
            postMilliseconds > observed ||
            postMilliseconds.abs() > 9007199254740991)) {
      return;
    }
    _facts.add((
      group: groupId,
      bit: own ? 1 : 2,
      observed: observed,
      post: postMilliseconds,
    ));
    _wake++;
    _start();
  }

  void _start() {
    if (_disposed || _worker != null) return;
    _worker = Future<void>(() async {
      _handledWake = _wake;
      _attempted = false;
      _storageFailed = false;
      _calendarFailed = false;
      try {
        await _drain();
      } catch (_) {
        // Diagnostics never owns the communication caller's success.
      } finally {
        _worker = null;
        // A new external wake may retry; a failed optional operation cannot spin.
        if (!_disposed && _handledWake != _wake) _start();
      }
    });
  }

  Future<void> _drain() async {
    while (!_disposed) {
      _handledWake = _wake;
      if (_clear) {
        final generation = _generation;
        final cleared = await _storeCall(
          (guard) => store.clear(isCurrent: guard),
          () => !_disposed && generation == _generation,
        );
        if (generation != _generation) continue;
        if (!cleared) return;
        _clear = false;
      }
      final owner = _owner;
      if (owner == null || !_live(owner)) return;
      if (!await _prepare(owner)) return;
      final week = _week!;
      if (_facts.isEmpty) {
        if ((_dirty || _phase == _Phase.pending) &&
            !_attempted &&
            !_storageFailed) {
          await _checkpoint(owner, week);
        }
        return;
      }
      final fact = _facts.removeFirst();
      _inFlight = true;
      try {
        if (!_context(owner, week) ||
            !_contains(week, fact.observed) ||
            (fact.post != null && !_contains(week, fact.post!))) {
          continue;
        }
        if (_phase != _Phase.collecting) continue;
        if (!_groups.containsKey(fact.group) && _groups.length >= _bound) {
          continue;
        }
        final bits = (_groups[fact.group] ?? 0) | fact.bit;
        _groups[fact.group] = bits;
        _dirty = true;
        if (bits == 3) {
          _phase = _Phase.pending;
          _groups.clear();
          _facts.clear();
        }
        await _checkpoint(owner, week);
      } finally {
        _inFlight = false;
      }
    }
  }

  Future<bool> _prepare(GroupEngagementOwner owner) async {
    if (!_live(owner) || _calendarFailed) return false;
    final previous = _week;
    if (previous != null && _context(owner, previous)) return true;
    final generation = _generation;
    _Week? resolved;
    try {
      resolved = await owner.lookupWeek().timeout(_deadline);
    } catch (_) {
      _calendarFailed = true;
      return false;
    }
    if (!_live(owner) || generation != _generation) return false;
    if (resolved == null || !_contains(resolved, nowMilliseconds())) {
      _calendarFailed = true;
      return false;
    }
    _week = resolved;
    _phase = _Phase.collecting;
    _groups.clear();
    _attempted = false;
    var waiting = true;
    try {
      final bytes = await store
          .read(isCurrent: () => waiting && _context(owner, resolved!))
          .timeout(_deadline, onTimeout: () => null);
      if (bytes != null && _context(owner, resolved)) {
        _dirty = true;
        _restore(bytes, owner, resolved);
      }
    } catch (_) {
      // Missing, foreign or corrupt bytes never supply qualifying evidence.
    } finally {
      waiting = false;
    }
    return _context(owner, resolved);
  }

  Map<String, Object> _scope(GroupEngagementOwner owner, _Week week) => {
    'accountPeerId': owner.accountPeerId,
    'profileBinding': owner.profileBinding,
    'consentEpoch': owner.consentEpoch,
    'week': week.week,
  };

  Uint8List _encode(GroupEngagementOwner owner, _Week week) =>
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'scope': _scope(owner, week),
            'phase': _phase.name,
            'groups': _groups,
          }),
        ),
      );

  void _restore(Uint8List bytes, GroupEngagementOwner owner, _Week week) {
    final root = jsonDecode(utf8.decode(bytes));
    if (root is! Map || root.length != 4 || root['version'] != 1) return;
    final scope = root['scope'];
    final expected = _scope(owner, week);
    if (scope is! Map ||
        scope.length != expected.length ||
        expected.entries.any((e) => scope[e.key] != e.value)) {
      return;
    }
    final phases = _Phase.values.where((p) => p.name == root['phase']);
    if (phases.length != 1) return;
    final phase = phases.single;
    final groups = root['groups'];
    if (groups is! Map ||
        groups.length > _bound ||
        (phase != _Phase.collecting && groups.isNotEmpty)) {
      return;
    }
    final restored = <String, int>{};
    for (final entry in groups.entries) {
      if (entry.key is! String ||
          !validIdentifier(entry.key as String) ||
          entry.value is! int ||
          (entry.value != 1 && entry.value != 2)) {
        return;
      }
      restored[entry.key as String] = entry.value as int;
    }
    _phase = phase;
    _dirty = false;
    _groups.addAll(restored);
  }

  Future<void> _checkpoint(GroupEngagementOwner owner, _Week week) async {
    if (!_context(owner, week) ||
        _storageFailed ||
        (_phase == _Phase.pending && _attempted)) {
      return;
    }
    final pending = _phase == _Phase.pending;
    if (pending) _attempted = true;
    final saved = await _storeCall(
      (guard) => store.replace(_encode(owner, week), isCurrent: guard),
      () => _context(owner, week),
    );
    if (!saved) {
      _storageFailed = true;
      return;
    }
    if (!_context(owner, week)) return;
    _dirty = false;
    if (!pending) return;
    var retained = false;
    try {
      retained = await owner.retain(week.week).timeout(_deadline);
    } catch (_) {
      // The durable pending checkpoint can retry on a later external wake.
    }
    if (!retained || !_context(owner, week)) return;
    _phase = _Phase.retained;
    _dirty = true;
    final retainedSaved = await _storeCall(
      (guard) => store.replace(_encode(owner, week), isCurrent: guard),
      () => _context(owner, week),
    );
    if (retainedSaved && _context(owner, week)) _dirty = false;
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
      // The shared physical writer still fences an already issued rename.
      waiting = false;
    }
  }

  static bool _contains(_Week week, int value) =>
      value >= week.startMilliseconds && value < week.endMilliseconds;

  static bool validIdentifier(String value) =>
      value.isNotEmpty &&
      value.length <= 256 &&
      utf8.encode(value).length <= 256 &&
      utf8.decode(utf8.encode(value)) == value;

  Future<void> flush() async {
    if (_disposed) return;
    _wake++;
    _start();
    while (_worker != null) {
      await _worker;
    }
  }

  Future<void> dispose() async {
    _invalidate();
    _disposed = true;
    await _worker;
    // The supplied checkpoint store remains externally owned.
  }
}
