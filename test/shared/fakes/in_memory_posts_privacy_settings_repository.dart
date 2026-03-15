import 'dart:async';

import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';

class InMemoryPostsPrivacySettingsRepository
    implements PostsPrivacySettingsRepository {
  PostsPrivacySettings _settings;
  final StreamController<PostsPrivacySettings> _changes =
      StreamController<PostsPrivacySettings>.broadcast();

  InMemoryPostsPrivacySettingsRepository({
    PostsPrivacySettings initialSettings = const PostsPrivacySettings(),
  }) : _settings = initialSettings;

  @override
  Stream<PostsPrivacySettings> get settingsChanges => _changes.stream;

  @override
  Future<PostsPrivacySettings> load() async => _settings;

  @override
  Future<void> save(PostsPrivacySettings settings) async {
    _settings = settings;
    _changes.add(settings);
  }

  @override
  Future<void> setSharingEnabled(bool enabled) async {
    await save(_settings.copyWith(sharingEnabled: enabled));
  }

  @override
  void dispose() {
    _changes.close();
  }
}
