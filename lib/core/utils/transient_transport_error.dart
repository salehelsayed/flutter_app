/// Transport interruption does not establish loss of the remote object.
abstract final class TransientTransportError {
  static bool matches(Object? error, {Object? code}) {
    final text = '${code ?? ''} ${error ?? ''}'.toLowerCase();
    return const [
      'relay unreachable',
      'relay unavailable',
      'stateless reset',
      'connection closed',
      'connection refused',
      'connection reset',
      'stream reset',
      'stream error',
      'stream closed',
      'broken pipe',
      'unexpected eof',
      'read response: eof',
      'err=eof',
      'timeout',
      'timed out',
      'deadline exceeded',
      'transfer stalled',
      'no recent network activity',
      'network is unreachable',
      'no route to host',
      'connect to relay',
      'failed to dial',
      'dial ',
      'open stream',
      'protocol stream',
      'no existing connection',
      'context canceled',
    ].any(text.contains);
  }
}
