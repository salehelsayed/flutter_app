import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const thoughtsMetricsEnabledStorageKey = 'thoughts_metrics_enabled';

/// Loads the Thoughts metrics switch. A missing value means on.
Future<bool> loadThoughtsMetricsEnabled({
  required SecureKeyStore secureKeyStore,
}) async {
  final value = await secureKeyStore.read(thoughtsMetricsEnabledStorageKey);
  return value != 'false';
}

/// Saves the Thoughts metrics switch. Turning it off also marks the own
/// Thoughts still waiting for a recipient, so their later sends carry the
/// opt-out. Turning it on never clears a mark.
Future<void> saveThoughtsMetricsEnabled({
  required SecureKeyStore secureKeyStore,
  required bool enabled,
  PostRepository? postRepository,
}) async {
  await secureKeyStore.write(
    thoughtsMetricsEnabledStorageKey,
    enabled ? 'true' : 'false',
  );
  if (!enabled) {
    await postRepository?.markUndeliveredOwnThoughtsMetricsOptOut();
  }
}
