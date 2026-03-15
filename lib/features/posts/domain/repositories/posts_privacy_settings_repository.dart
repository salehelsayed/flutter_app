import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';

abstract class PostsPrivacySettingsRepository {
  Stream<PostsPrivacySettings> get settingsChanges;

  Future<PostsPrivacySettings> load();

  Future<void> save(PostsPrivacySettings settings);

  Future<void> setSharingEnabled(bool enabled);

  void dispose();
}
