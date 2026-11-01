import 'package:flutter_app/core/media/composer_draft_store.dart';

/// Widget-test stand-in for [FileComposerDraftStore]: same contract, no file
/// I/O, so it completes inside fake-async pumps. One instance shared by two
/// pumped screens models leaving the chat and coming back.
class InMemoryComposerDraftStore implements ComposerDraftStore {
  final Map<ComposerDraftKey, ComposerDraft> drafts = {};

  @override
  Future<ComposerDraft?> load(ComposerDraftKey key) async => drafts[key];

  @override
  Future<void> save(ComposerDraftKey key, ComposerDraft draft) async {
    if (draft.isEmpty) {
      drafts.remove(key);
    } else {
      drafts[key] = draft;
    }
  }

  @override
  Future<void> clear(ComposerDraftKey key) async {
    drafts.remove(key);
  }
}
