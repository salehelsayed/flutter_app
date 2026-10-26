import 'package:flutter_app/core/config/thoughts_feature_flags.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Read by the iOS notification extension (NotificationPreviewResolver
/// resolvePostCreate): a thought's text shows only when this holds "1".
/// Anything else, including a build that never wrote it, keeps the card a
/// quiet "FRIEND · New thought".
const iosThoughtsSwitchKey = 'thoughts_enabled_v1';

/// Mirrors [thoughtsEnabled] into the keychain shared with the extension. Run
/// on every start, so a store build installed over a dev build clears it.
Future<void> publishThoughtsSwitchForIos(SecureKeyStore sharedStore) async {
  try {
    if (thoughtsEnabled) {
      await sharedStore.write(iosThoughtsSwitchKey, '1');
    } else {
      await sharedStore.delete(iosThoughtsSwitchKey);
    }
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'THOUGHTS_IOS_SWITCH_PUBLISH_FAILED',
      details: {'errorType': error.runtimeType.toString()},
    );
  }
}
