import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_schema_capabilities.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/037_posts_repost_engagement_state.dart';
import 'package:flutter_app/core/database/migrations/040_posts_repost_visual_metrics.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> openLegacyDatabase(String path) async {
    final database = await openDatabase(path, version: 1);
    await runPostsCoreMigration(database);
    await runPostsPassAlongMigration(database);
    await runPostsRepostEngagementStateMigration(database);
    return database;
  }

  Future<Database> openNewerDatabase(String path) async {
    final database = await openDatabase(path, version: 1);
    await runPostsCoreMigration(database);
    await runPostsEngagementMigration(database);
    await runPostsPassAlongMigration(database);
    await runPostsRepostEngagementStateMigration(database);
    await runPostsRepostVisualMetricsMigration(database);
    return database;
  }

  void expectLegacyCapabilities(PostSchemaCapabilities capabilities) {
    expect(capabilities.hasPostsMediaKind, isFalse);
    expect(capabilities.hasPostsLastEngagementAt, isFalse);
    expect(capabilities.hasPassRecipientCount, isFalse);
    expect(capabilities.hasRepostSharedToCountBaseline, isFalse);
  }

  void expectNewerCapabilities(PostSchemaCapabilities capabilities) {
    expect(capabilities.hasPostsMediaKind, isTrue);
    expect(capabilities.hasPostsLastEngagementAt, isTrue);
    expect(capabilities.hasPassRecipientCount, isTrue);
    expect(capabilities.hasRepostSharedToCountBaseline, isTrue);
  }

  test('keeps legacy and newer database snapshots isolated', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'post_schema_capabilities_',
    );
    final legacyDb = await openLegacyDatabase('${tempDir.path}/legacy.db');
    final newerDb = await openNewerDatabase('${tempDir.path}/newer.db');

    try {
      final legacyCaps = await loadPostSchemaCapabilities(legacyDb);
      final newerCaps = await loadPostSchemaCapabilities(newerDb);

      expectLegacyCapabilities(legacyCaps);
      expectNewerCapabilities(newerCaps);
    } finally {
      await legacyDb.close();
      await newerDb.close();
      await tempDir.delete(recursive: true);
    }
  });

  test('keeps newer and legacy database snapshots isolated', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'post_schema_capabilities_',
    );
    final newerDb = await openNewerDatabase('${tempDir.path}/newer.db');
    final legacyDb = await openLegacyDatabase('${tempDir.path}/legacy.db');

    try {
      final newerCaps = await loadPostSchemaCapabilities(newerDb);
      final legacyCaps = await loadPostSchemaCapabilities(legacyDb);

      expectNewerCapabilities(newerCaps);
      expectLegacyCapabilities(legacyCaps);
    } finally {
      await newerDb.close();
      await legacyDb.close();
      await tempDir.delete(recursive: true);
    }
  });
}
