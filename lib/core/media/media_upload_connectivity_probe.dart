import 'package:connectivity_plus/connectivity_plus.dart';

typedef MediaUploadConnectivityProbe = Future<bool> Function();

/// Returns whether the OS currently reports any usable network interface.
///
/// Automatic outbox passes use this before claiming/encrypting/uploading.
/// Probe failures fail closed for that pass and are never converted into an
/// attachment upload failure (therefore they cannot consume retry budget).
Future<bool> probeMediaUploadConnectivity({Connectivity? connectivity}) async {
  try {
    final results = await (connectivity ?? Connectivity()).checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  } catch (_) {
    return false;
  }
}
