import '../../../core/permissions/mic_permission_gateway.dart';
import '../application/call_audio_controller.dart';

/// Production bridge from the shared permission gateway to call audio.
final class CallMicrophonePermissionAdapter
    implements CallMicrophonePermission {
  const CallMicrophonePermissionAdapter({
    MicPermissionGateway gateway = const PermissionHandlerMicGateway(),
  }) : _gateway = gateway;

  final MicPermissionGateway _gateway;

  @override
  Future<MicPermissionStatus> request() => _gateway.request();
}
