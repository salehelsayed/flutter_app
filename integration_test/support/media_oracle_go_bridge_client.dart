import 'package:flutter_app/core/bridge/go_bridge_client.dart';

import 'media_content_oracle.dart';

/// Test-composition drop-in retaining the real native client's callbacks,
/// channels and lifecycle. No extra encrypt/decrypt/upload, no shipping hook.
/// Instantiate only from the device executor's existing test composition.
class MediaOracleGoBridgeClient extends GoBridgeClient {
  MediaOracleGoBridgeClient({required this.mediaInputObserver});
  final MediaEncryptionInputObserver mediaInputObserver;

  @override
  Future<String> send(String message) =>
      mediaInputObserver.observe(message, () => super.send(message));
}
