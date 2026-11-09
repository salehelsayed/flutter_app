/// Producer-side observation boundary; the RED baseline forwards every event.
final class RoutineAuthorityPublicationCoalescer {
  RoutineAuthorityPublicationCoalescer({
    required Duration Function() monotonicNow,
    required void Function(Map<String, Object?>) emit,
  }) : _emit = emit;

  final void Function(Map<String, Object?>) _emit;

  void add(
    Map<String, Object?> event, {
    required String streamKey,
    required String stateKey,
    required Object publication,
    required bool routine,
    required bool activeCall,
    required int consentEpoch,
  }) => _emit(event);

  void reset() {}
  void close() {}
}
