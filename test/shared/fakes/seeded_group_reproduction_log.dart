import 'dart:convert';

class SeededGroupReproductionLog {
  SeededGroupReproductionLog({
    required this.rowId,
    required this.seed,
    required this.scenario,
  });

  final String rowId;
  final int seed;
  final String scenario;
  final List<Map<String, Object?>> _operations = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _bridgeResponses = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _diagnostics = <Map<String, Object?>>[];
  Map<String, Object?>? _failure;

  void recordOperation({
    required int step,
    required String actor,
    required String action,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    _operations.add(<String, Object?>{
      'step': step,
      'actor': actor,
      'action': action,
      'details': details,
    });
  }

  void recordBridgeResponse({
    required int step,
    required String actor,
    required String command,
    required bool ok,
    Map<String, Object?> response = const <String, Object?>{},
  }) {
    _bridgeResponses.add(<String, Object?>{
      'step': step,
      'actor': actor,
      'command': command,
      'ok': ok,
      'response': response,
    });
  }

  void recordDiagnostic({
    required int step,
    required String layer,
    required String event,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    _diagnostics.add(<String, Object?>{
      'step': step,
      'layer': layer,
      'event': event,
      'details': details,
    });
  }

  void recordFailure({
    required int step,
    required String layer,
    required String reason,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    _failure = <String, Object?>{
      'step': step,
      'layer': layer,
      'reason': reason,
      'details': details,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'rowId': rowId,
      'seed': seed,
      'scenario': scenario,
      'operations': List<Map<String, Object?>>.unmodifiable(_operations),
      'bridgeResponses': List<Map<String, Object?>>.unmodifiable(
        _bridgeResponses,
      ),
      'diagnostics': List<Map<String, Object?>>.unmodifiable(_diagnostics),
      if (_failure != null)
        'failure': Map<String, Object?>.unmodifiable(_failure!),
    };
  }

  String canonicalJson() => jsonEncode(_canonicalize(toJson()));
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final entries =
        value.entries
            .map((entry) => MapEntry(entry.key.toString(), entry.value))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return <String, Object?>{
      for (final entry in entries) entry.key: _canonicalize(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}
