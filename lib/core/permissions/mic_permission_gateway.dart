import 'package:permission_handler/permission_handler.dart' as ph;

/// Tri-state microphone-permission result, abstracted away from any specific
/// plugin so the chat screens and the shared denied-prompt helper never depend
/// on `permission_handler` directly (tests inject a fake; production wraps the
/// plugin behind [PermissionHandlerMicGateway]).
///
/// The distinction that matters for UX is whether the user can still be
/// re-prompted in-app ([denied]) or has reached a state where the only way to
/// grant is the system Settings page ([permanentlyDenied] / restricted, which
/// is folded into [permanentlyDenied]).
enum MicPermissionStatus { granted, denied, permanentlyDenied }

/// Thin seam over the microphone permission + "open app settings" deep-link.
///
/// Plugins throw `MissingPluginException` under `flutter_test`, so this is the
/// injection point that lets host tests spy on the deep-link without touching
/// the real plugin — mirroring the `NearbyLocationService.openAppSettings()`
/// seam used by the posts nearby composer.
abstract class MicPermissionGateway {
  /// Requests the microphone permission, showing the OS prompt when the
  /// permission is still undetermined, and maps the result to
  /// [MicPermissionStatus].
  Future<MicPermissionStatus> request();

  /// Reads the current state without showing the OS prompt.
  Future<MicPermissionStatus> status();

  /// Deep-links to the app's system settings page so the user can flip the
  /// microphone toggle when in-app re-prompting is no longer possible.
  Future<bool> openAppSettings();
}

/// Production [MicPermissionGateway] wrapping the `permission_handler` plugin.
///
/// `const` so it can be the default constructor value of the chat screens — a
/// production screen built without an explicit gateway still gets the real
/// implementation, while tests always inject a [MicPermissionGateway] fake.
class PermissionHandlerMicGateway implements MicPermissionGateway {
  const PermissionHandlerMicGateway();

  /// Android reports "don't ask again" only from a request, while its plain
  /// status still says denied. The last request result in this process keeps
  /// that answer until the next request; a granted status always wins.
  static MicPermissionStatus? _lastRequestResult;

  @override
  Future<MicPermissionStatus> request() async {
    final result = _map(await ph.Permission.microphone.request());
    _lastRequestResult = result;
    return result;
  }

  @override
  Future<MicPermissionStatus> status() async {
    final current = _map(await ph.Permission.microphone.status);
    if (current == MicPermissionStatus.denied &&
        _lastRequestResult == MicPermissionStatus.permanentlyDenied) {
      return MicPermissionStatus.permanentlyDenied;
    }
    return current;
  }

  static MicPermissionStatus _map(ph.PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return MicPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return MicPermissionStatus.permanentlyDenied;
    }
    return MicPermissionStatus.denied;
  }

  @override
  Future<bool> openAppSettings() => ph.openAppSettings();
}
