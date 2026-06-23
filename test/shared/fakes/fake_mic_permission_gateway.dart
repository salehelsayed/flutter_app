import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';

/// Host-test spy for [MicPermissionGateway]. Records the deep-link calls and
/// returns a scriptable status so a `permanentlyDenied → dialog` (and the
/// "Open Settings" tap) can be exercised without the real `permission_handler`
/// plugin (which throws `MissingPluginException` under `flutter_test`).
///
/// Defaults to [MicPermissionStatus.granted] so any screen builder that injects
/// this fake by default keeps the existing granted voice-record path green.
class FakeMicPermissionGateway implements MicPermissionGateway {
  MicPermissionStatus statusToReturn = MicPermissionStatus.granted;
  bool openAppSettingsReturn = true;

  int requestCallCount = 0;
  int openAppSettingsCallCount = 0;

  @override
  Future<MicPermissionStatus> request() async {
    requestCallCount++;
    return statusToReturn;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCallCount++;
    return openAppSettingsReturn;
  }
}
