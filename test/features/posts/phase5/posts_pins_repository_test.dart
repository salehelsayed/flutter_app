import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_pin_dismissals_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_pins_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/031_posts_pins.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/post_pin_fixtures.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runPostsCoreMigration(db);
    await runPostsEngagementMigration(db);
    await runPostsNearbyMigration(db);
    await runPostsPassAlongMigration(db);
    await runPostsPinsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  PostRepositoryImpl buildRepository() {
    return PostRepositoryImpl(
      dbInsertPost: (row) => dbInsertPost(db, row),
      dbLoadPost: (postId) => dbLoadPost(db, postId),
      dbLoadPostsFeed: () => dbLoadPostsFeed(db),
      dbUpsertRecipientDelivery: (row) => dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (postId) => dbLoadPostRecipientDeliveries(db, postId),
      dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
      dbUpsertPostPinState: (row) => dbUpsertPostPinState(db, row),
      dbLoadPostPinState: (postId) => dbLoadPostPinState(db, postId),
      dbLoadActivePostPinStates: () => dbLoadActivePostPinStates(db),
      dbUpsertPinDismissal: (row) => dbUpsertPostPinDismissal(db, row),
      dbLoadPinDismissals: () => dbLoadPostPinDismissals(db),
      dbDeletePinDismissal: (postId) => dbDeletePostPinDismissal(db, postId),
    );
  }

  test('restores active pins and local dismissals across repository recreation', () async {
    final firstRepository = buildRepository();
    await firstRepository.savePost(
      postPinBasePost(
        keepAvailable: true,
      ),
    );
    await firstRepository.savePostPinState(
      const PostPinStateModel(
        postId: 'post-1',
        eventId: 'evt-pin-1',
        pinEventId: 'pin-evt-1',
        senderPeerId: 'peer-bob',
        state: 'active',
        effectiveAt: '2026-03-15T11:20:00.000Z',
        pinnedAt: '2026-03-15T11:20:00.000Z',
        createdAt: '2026-03-15T11:20:00.000Z',
      ),
    );
    await firstRepository.savePinDismissal(
      'post-1',
      '2026-03-15T12:05:00.000Z',
    );
    firstRepository.dispose();

    final secondRepository = buildRepository();
    final pinState = await secondRepository.getPostPinState('post-1');
    final activePins = await secondRepository.loadActivePinStates();
    final dismissed = await secondRepository.loadDismissedPinPostIds();

    expect(pinState, isNotNull);
    expect(pinState!.state, 'active');
    expect(activePins.map((state) => state.postId), <String>['post-1']);
    expect(dismissed, <String>{'post-1'});
    secondRepository.dispose();
  });
}
