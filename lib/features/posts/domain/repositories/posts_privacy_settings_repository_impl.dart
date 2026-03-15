import 'dart:async';

import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';

class PostsPrivacySettingsRepositoryImpl
    implements PostsPrivacySettingsRepository {
  final Future<Map<String, Object?>?> Function() dbLoadPostPrivacyState;
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertPostPrivacyState;

  final StreamController<PostsPrivacySettings> _settingsChangesController =
      StreamController<PostsPrivacySettings>.broadcast();

  PostsPrivacySettingsRepositoryImpl({
    required this.dbLoadPostPrivacyState,
    required this.dbUpsertPostPrivacyState,
  });

  @override
  Stream<PostsPrivacySettings> get settingsChanges =>
      _settingsChangesController.stream;

  @override
  Future<PostsPrivacySettings> load() async {
    final row = await dbLoadPostPrivacyState();
    if (row == null) {
      return const PostsPrivacySettings();
    }
    return PostsPrivacySettings.fromMap(row);
  }

  @override
  Future<void> save(PostsPrivacySettings settings) async {
    await dbUpsertPostPrivacyState(settings.toMap());
    _settingsChangesController.add(settings);
  }

  @override
  Future<void> setSharingEnabled(bool enabled) async {
    final current = await load();
    await save(current.copyWith(sharingEnabled: enabled));
  }

  @override
  void dispose() {
    _settingsChangesController.close();
  }
}
