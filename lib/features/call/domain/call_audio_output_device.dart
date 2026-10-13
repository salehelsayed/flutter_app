import 'call_engine.dart';

/// Ephemeral native inventory for the visible picker. Never serialize, persist
/// or include the identifier/name in diagnostics or call snapshots.
final class CallAudioOutputDevice {
  const CallAudioOutputDevice({
    required this.id,
    required this.name,
    required this.route,
    required this.selected,
  });
  final String id;
  final String name;
  final CallAudioOutputRoute route;
  final bool selected;
  @override
  String toString() =>
      'CallAudioOutputDevice(route: ${route.name}, selected: $selected)';
}

abstract interface class CallAudioDevicePort {
  Future<List<CallAudioOutputDevice>> outputDevices();

  /// True only after the native owner reports this exact endpoint selected.
  Future<bool> selectOutputDevice(String id);
}
