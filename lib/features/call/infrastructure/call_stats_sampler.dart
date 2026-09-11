import '../domain/call_engine.dart';

/// Packet-counter progress contains no statistics identifiers or addresses.
final class CallRtpProgressSample {
  const CallRtpProgressSample({required this.inbound, required this.outbound});
  final bool inbound;
  final bool outbound;
}

/// Compares consecutive valid aggregate audio counters. A first sample,
/// missing statistics, or counter reset cannot prove new packet flow.
final class CallRtpProgressSampler {
  (int, int)? _inbound;
  (int, int)? _outbound;

  CallRtpProgressSample sample(Iterable<CallStatsRecord> records) {
    (int, int)? inbound;
    (int, int)? outbound;
    for (final record in records) {
      if (record.values['kind'] != 'audio' &&
          record.values['mediaType'] != 'audio') {
        continue;
      }
      final isInbound = record.type == 'inbound-rtp';
      if (!isInbound && record.type != 'outbound-rtp') continue;
      final packets = _counter(
        record.values[isInbound ? 'packetsReceived' : 'packetsSent'],
      );
      final bytes = _counter(
        record.values[isInbound ? 'bytesReceived' : 'bytesSent'],
      );
      if (packets == null || bytes == null) continue;
      if (isInbound) {
        inbound = ((inbound?.$1 ?? 0) + packets, (inbound?.$2 ?? 0) + bytes);
      } else {
        outbound = ((outbound?.$1 ?? 0) + packets, (outbound?.$2 ?? 0) + bytes);
      }
    }
    bool advanced((int, int)? previous, (int, int)? current) =>
        previous != null &&
        current != null &&
        current.$1 > previous.$1 &&
        current.$2 > previous.$2;
    final result = CallRtpProgressSample(
      inbound: advanced(_inbound, inbound),
      outbound: advanced(_outbound, outbound),
    );
    _inbound = inbound;
    _outbound = outbound;
    return result;
  }

  static int? _counter(Object? value) {
    final number = value is num
        ? value
        : value is String
        ? num.tryParse(value)
        : null;
    if (number == null ||
        !number.isFinite ||
        number < 0 ||
        number > 9007199254740991 ||
        number != number.truncateToDouble()) {
      return null;
    }
    return number.toInt();
  }
}

/// A plugin-independent copy of one WebRTC statistics row.
///
/// Only fixed fields needed for readiness and coarse route classification are
/// read. Addresses, identifiers, SDP, and counters are never retained in the
/// returned sample.
final class CallStatsRecord {
  const CallStatsRecord({
    required this.id,
    required this.type,
    required this.values,
  });

  final String id;
  final String type;
  final Map<Object?, Object?> values;
}

final class CallStatsSample {
  const CallStatsSample({
    required this.selectedPairSucceeded,
    required this.selectedPairNominated,
    required this.selectedRelayProtocol,
    required this.dtlsReady,
    required this.transport,
    required this.inboundAudioRtpObserved,
    required this.outboundAudioRtpObserved,
  });

  static const empty = CallStatsSample(
    selectedPairSucceeded: false,
    selectedPairNominated: false,
    selectedRelayProtocol: CallRelayProtocol.unknown,
    dtlsReady: false,
    transport: CallTransportClass.unknown,
    inboundAudioRtpObserved: false,
    outboundAudioRtpObserved: false,
  );

  final bool selectedPairSucceeded;
  final bool selectedPairNominated;
  final CallRelayProtocol selectedRelayProtocol;
  final bool dtlsReady;
  final CallTransportClass transport;
  final bool inboundAudioRtpObserved;
  final bool outboundAudioRtpObserved;
}

/// Version-tolerant, privacy-safe selected-pair parser.
final class CallStatsSampler {
  const CallStatsSampler();

  CallStatsSample sample(Iterable<CallStatsRecord> records) {
    var inboundAudioRtpObserved = false;
    var outboundAudioRtpObserved = false;
    final byId = <String, CallStatsRecord>{
      for (final record in records) record.id: record,
    };
    CallStatsRecord? transportRecord;
    CallStatsRecord? selectedPair;

    for (final record in records) {
      if (_isAudioRtp(record)) {
        if (record.type == 'inbound-rtp') {
          inboundAudioRtpObserved |=
              _positive(record.values['packetsReceived']) &&
              _positive(record.values['bytesReceived']);
        } else if (record.type == 'outbound-rtp') {
          outboundAudioRtpObserved |=
              _positive(record.values['packetsSent']) &&
              _positive(record.values['bytesSent']);
        }
      }
      if (record.type == 'transport') {
        transportRecord ??= record;
        final selectedId = _string(record.values['selectedCandidatePairId']);
        if (selectedId != null) selectedPair = byId[selectedId];
      }
    }
    if (selectedPair == null) {
      for (final record in records) {
        if (record.type != 'candidate-pair') continue;
        if (_bool(record.values['selected']) ||
            _bool(record.values['nominated'])) {
          selectedPair = record;
          break;
        }
      }
    }

    final pair = selectedPair;
    if (pair == null) {
      return CallStatsSample(
        selectedPairSucceeded: false,
        selectedPairNominated: false,
        selectedRelayProtocol: CallRelayProtocol.unknown,
        dtlsReady: _dtlsReady(transportRecord),
        transport: CallTransportClass.unknown,
        inboundAudioRtpObserved: inboundAudioRtpObserved,
        outboundAudioRtpObserved: outboundAudioRtpObserved,
      );
    }

    final state = _string(pair.values['state'])?.toLowerCase();
    final succeeded = state == 'succeeded';
    final selectedByTransport =
        transportRecord != null &&
        _string(transportRecord.values['selectedCandidatePairId']) == pair.id;
    final nominated = _bool(pair.values['nominated']) || selectedByTransport;
    final localId = _string(pair.values['localCandidateId']);
    final referencedLocal = localId == null ? null : byId[localId];
    final local = referencedLocal?.type == 'local-candidate'
        ? referencedLocal
        : null;

    return CallStatsSample(
      selectedPairSucceeded: succeeded,
      selectedPairNominated: nominated,
      selectedRelayProtocol: _selectedRelayProtocol(local),
      dtlsReady: _dtlsReady(transportRecord),
      transport: _transportClass(local),
      inboundAudioRtpObserved: inboundAudioRtpObserved,
      outboundAudioRtpObserved: outboundAudioRtpObserved,
    );
  }

  static bool _isAudioRtp(CallStatsRecord record) {
    if (record.type != 'inbound-rtp' && record.type != 'outbound-rtp') {
      return false;
    }
    final kind = _string(
      record.values['kind'] ?? record.values['mediaType'],
    )?.toLowerCase();
    return kind == 'audio';
  }

  static bool _dtlsReady(CallStatsRecord? transport) {
    final value = _string(transport?.values['dtlsState'])?.toLowerCase();
    return value == 'connected';
  }

  static CallTransportClass _transportClass(CallStatsRecord? candidate) {
    if (candidate == null) return CallTransportClass.unknown;
    final candidateType = _string(
      candidate.values['candidateType'],
    )?.toLowerCase();
    final relayedPrflx = _isTurnBackedPrflx(candidate, candidateType);
    if (candidateType == 'host' ||
        candidateType == 'srflx' ||
        (candidateType == 'prflx' && !relayedPrflx)) {
      return CallTransportClass.direct;
    }
    if (candidateType != 'relay' && !relayedPrflx) {
      return CallTransportClass.unknown;
    }
    final protocol =
        _string(candidate.values['relayProtocol'])?.toLowerCase() ??
        _string(candidate.values['protocol'])?.toLowerCase();
    if (protocol == 'tcp' || protocol == 'tls') {
      return CallTransportClass.turnTcpTls;
    }
    if (protocol == 'udp') return CallTransportClass.turnUdp;
    return CallTransportClass.relay;
  }

  static CallRelayProtocol _selectedRelayProtocol(CallStatsRecord? candidate) {
    if (candidate == null) return CallRelayProtocol.unknown;
    final candidateType = _string(
      candidate.values['candidateType'],
    )?.toLowerCase();
    final relayedPrflx = _isTurnBackedPrflx(candidate, candidateType);
    if (candidateType == 'host' ||
        candidateType == 'srflx' ||
        (candidateType == 'prflx' && !relayedPrflx)) {
      return CallRelayProtocol.notRelay;
    }
    if (candidateType != 'relay' && !relayedPrflx) {
      return CallRelayProtocol.unknown;
    }
    return switch (_string(candidate.values['relayProtocol'])?.toLowerCase()) {
      'udp' => CallRelayProtocol.udp,
      'tcp' => CallRelayProtocol.tcp,
      'tls' => CallRelayProtocol.tls,
      null || _ => CallRelayProtocol.unknown,
    };
  }

  // M144 Connection::MaybeUpdateLocalCandidate can remap a TURN candidate to
  // prflx while retaining its TURN port. RTCStatsCollector explicitly exposes
  // relayProtocol for that local prflx candidate. Require this native evidence;
  // ordinary prflx, generic protocol, URLs, and remote relays cannot prove TURN.
  static bool _isTurnBackedPrflx(
    CallStatsRecord candidate,
    String? candidateType,
  ) =>
      candidateType == 'prflx' &&
      candidate.type == 'local-candidate' &&
      const {
        'udp',
        'tcp',
        'tls',
      }.contains(_string(candidate.values['relayProtocol'])?.toLowerCase());

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static bool _bool(Object? value) => value == true || value == 1;

  static bool _positive(Object? value) =>
      value is num && value.isFinite && value > 0;
}
