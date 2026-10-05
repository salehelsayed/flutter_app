/// Pure oracle for the production transport census (Wave 4).
///
/// The original census has no numeric threshold: it reports the transport
/// mix and per-transport latency over N sends. The production measurement
/// keeps that report and makes its preconditions exact: every requested send
/// was attempted once, the counts reconcile, the receiver stored each
/// delivered census text exactly once and nothing else, and a condition with
/// deliveries produced transport samples and latency.
const productionTransportCensusInterval =
    'sender vantage: production sendChatMessage call to its result, '
    'per send; cold drops the connection to the receiver 300 ms before';

List<String> validateProductionTransportCensus(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool ok, String message) {
    if (!ok) failures.add(message);
  }

  final conditions = proof['conditions'];
  if (conditions is! List || conditions.isEmpty) {
    return ['no census condition recorded'];
  }
  require(
    proof['interval'] == productionTransportCensusInterval,
    'census interval named',
  );
  var anyDelivered = false;
  for (final raw in conditions) {
    if (raw is! Map) {
      failures.add('malformed condition');
      continue;
    }
    final name = raw['name'];
    final n = raw['n'];
    final cold = raw['cold'];
    final sends = raw['sends'];
    final report = raw['report'];
    final received = raw['receivedTexts'];
    final texts = raw['texts'];
    if (name is! String ||
        n is! int ||
        n < 1 ||
        cold is! bool ||
        sends is! List ||
        report is! Map ||
        received is! List ||
        texts is! List) {
      failures.add('$name: malformed census condition');
      continue;
    }
    require(sends.length == n, '$name: every requested send attempted');
    final indexes = [
      for (final s in sends)
        if (s is Map) s['index'],
    ];
    require(
      indexes.length == n &&
          [for (var i = 1; i <= n; i++) i].every(indexes.contains),
      '$name: sends 1..N exactly once',
    );
    require(
      sends.every(
        (s) => s is Map && s['cold'] == cold && s['condition'] == name,
      ),
      '$name: cold lever and condition recorded per send',
    );
    final delivered = [
      for (final s in sends)
        if (s is Map && s['result'] == 'success') s,
    ];
    final failed = sends.length - delivered.length;
    require(raw['delivered'] == delivered.length, '$name: delivered count');
    require(raw['failed'] == failed, '$name: failed count');
    require(
      delivered.every((s) => s['messageId'] is String),
      '$name: delivered sends have a stored message',
    );
    if (delivered.isNotEmpty) anyDelivered = true;
    final deliveredTexts = [
      for (final s in delivered)
        if (s['index'] is int) texts[(s['index'] as int) - 1],
    ];
    final censusReceived = [
      for (final t in received)
        if (t is String && texts.contains(t)) t,
    ];
    for (final t in deliveredTexts) {
      require(
        censusReceived.where((r) => r == t).length == 1,
        '$name: receiver stored delivered text once ($t)',
      );
    }
    require(
      censusReceived.toSet().difference(texts.toSet()).isEmpty &&
          censusReceived.length == censusReceived.toSet().length,
      '$name: no unexpected or duplicated census text',
    );
    final samples = report['totalTransportSamples'];
    final mix = report['transportMix'];
    final latency = report['latencyByTransport'];
    require(samples is int && samples >= 0, '$name: transport samples');
    require(mix is Map && latency is Map, '$name: census report shape');
    if (delivered.isNotEmpty && mix is Map && latency is Map) {
      require(
        samples is int && samples >= 1,
        '$name: delivered sends produced transport samples',
      );
      require(
        mix.values.whereType<int>().fold<int>(0, (a, b) => a + b) >= 1,
        '$name: transport mix observed',
      );
      require(
        latency.values.any((v) => v is Map && v['n'] is int && v['n'] >= 1),
        '$name: latency by transport observed',
      );
    }
  }
  require(anyDelivered, 'at least one census send delivered');
  return failures;
}
