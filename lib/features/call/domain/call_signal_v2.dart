/// This version has its own closed event vocabulary; v1 is unchanged.
enum CallSignalV2Type {
  invite('invite'),
  ringing('ringing'),
  accept('accept'),
  reject('reject'),
  offer('offer'),
  answer('answer'),
  ice('ice'),
  iceRestart('ice_restart'),
  terminate('terminate'),
  mediaRequest('media_request'),
  mediaResponse('media_response'),
  mediaCommit('media_commit'),
  mediaCommitAck('media_commit_ack'),
  mediaAbort('media_abort'),
  cameraState('camera_state');

  const CallSignalV2Type(this.wireName);
  final String wireName;
}

/// Strict encrypted v2 data. Parsing alone cannot authorize capture or a call.
final class CallSignalV2 {
  CallSignalV2._();

  static const String schema = 'mknoon.call_signal.v2';

  factory CallSignalV2.fromMap(
    Map<String, Object?> map, {
    bool videoEnabled = false,
  }) {
    // Compiling RED seam. Disabled and unsupported v2 both fail closed.
    throw const FormatException('call signal v2 is not implemented');
  }

  CallSignalV2Type get event => throw UnimplementedError();
  Map<String, Object?> get payload => throw UnimplementedError();
  Map<String, Object?> toMap() => throw UnimplementedError();
  Map<String, Object?> toDiagnosticMap() => throw UnimplementedError();
}
