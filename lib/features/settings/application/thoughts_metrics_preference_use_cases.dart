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

Future<void>? _ordered;

/// Runs [action] after every earlier switch change and Thought save, one at a
/// time. A new Thought's last switch read and its insert run inside it, as
/// does switching off, so the Thought is either saved before the off pass
/// marks it or reads off itself. The queue empties after its last run, so no
/// finished future is kept to chain onto.
Future<T> inThoughtsMetricsOrder<T>(Future<T> Function() action) {
  final previous = _ordered;
  final run = previous == null
      ? Future.sync(action)
      : previous.then((_) => action());
  final done = run.then<void>((_) {}, onError: (_) {});
  _ordered = done;
  done.whenComplete(() {
    if (identical(_ordered, done)) _ordered = null;
  });
  return run;
}

/// Saves the Thoughts metrics switch. Turning it off first marks the own
/// Thoughts still waiting for a recipient, so their later sends carry the
/// opt-out; off is stored only once they are marked, and a failure leaves the
/// switch as it was. Turning it on never clears a mark.
Future<void> saveThoughtsMetricsEnabled({
  required SecureKeyStore secureKeyStore,
  required bool enabled,
  PostRepository? postRepository,
}) => inThoughtsMetricsOrder(() async {
  if (!enabled) {
    await postRepository?.markUndeliveredOwnThoughtsMetricsOptOut();
  }
  await secureKeyStore.write(
    thoughtsMetricsEnabledStorageKey,
    enabled ? 'true' : 'false',
  );
});
