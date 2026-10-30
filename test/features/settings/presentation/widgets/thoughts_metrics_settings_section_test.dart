import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/settings/application/thoughts_metrics_preference_use_cases.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

const _switchKey = ValueKey('settings-thoughts-metrics-switch');
const _description =
    'Helps us count Thoughts as weekly estimates. We never read your Thoughts '
    'and keep no record of who sent what. Turning it off applies from now on.';

void main() {
  late FakeSecureKeyStore store;
  late InMemoryPostRepository posts;

  setUp(() {
    store = FakeSecureKeyStore();
    posts = InMemoryPostRepository();
  });

  tearDown(() => posts.dispose());

  Future<void> pumpSettings(WidgetTester tester) async {
    final shell = AppShellController();
    addTearDown(shell.dispose);
    final privacyRepo = InMemoryPostsPrivacySettingsRepository();
    addTearDown(privacyRepo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsWired(
          identityRepo: FakeIdentityRepository()
            ..seed(FakeIdentityRepository.makeIdentity()),
          bridge: FakeBridge(),
          contactRepo: FakeContactRepository(),
          p2pService: FakeP2PService(),
          secureKeyStore: store,
          imageProcessor: ImageProcessor(),
          appShellController: shell,
          postsPrivacySettingsRepository: privacyRepo,
          postRepository: posts,
        ),
      ),
    );
    // AmbientBackground animates forever: bounded pumps only.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.byKey(_switchKey));
    await tester.pump();
  }

  bool switchValue(WidgetTester tester) =>
      tester.widget<Switch>(find.byKey(_switchKey)).value;

  testWidgets('shows on by default with its title and full description', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(switchValue(tester), isTrue);
    expect(find.text('Thoughts metrics'), findsOneWidget);
    expect(find.text(_description), findsOneWidget);
    expect(await store.read(thoughtsMetricsEnabledStorageKey), isNull);
  });

  testWidgets('a stored off shows the switch off', (tester) async {
    await store.write(thoughtsMetricsEnabledStorageKey, 'false');

    await pumpSettings(tester);

    expect(switchValue(tester), isFalse);
  });

  testWidgets(
    'toggling off writes the setting and marks a pending Thought, toggling on '
    'keeps the mark',
    (tester) async {
      final now = DateTime.now().toUtc().toIso8601String();
      await posts.savePost(
        PostModel(
          id: 'pending',
          eventId: 'evt-pending',
          senderPeerId: 'my-peer-id',
          authorPeerId: 'my-peer-id',
          authorUsername: 'Alice',
          text: 'Thought',
          audience: PostAudience.allFriends(),
          createdAt: now,
          visibleAt: now,
          expiresAt: now,
          isIncoming: false,
          deliveryStatus: 'sending',
        ),
      );
      await pumpSettings(tester);

      await tester.tap(find.byKey(_switchKey));
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      expect(switchValue(tester), isFalse);
      expect(await store.read(thoughtsMetricsEnabledStorageKey), 'false');
      expect((await posts.getPost('pending'))!.metricsOptOut, isTrue);

      await tester.tap(find.byKey(_switchKey));
      await tester.pump();

      expect(switchValue(tester), isTrue);
      expect(await store.read(thoughtsMetricsEnabledStorageKey), 'true');
      expect((await posts.getPost('pending'))!.metricsOptOut, isTrue);
    },
  );

  testWidgets('if a pending Thought cannot be marked, the switch stays on', (
    tester,
  ) async {
    posts.dispose();
    posts = _FailingMarkRepository();
    await pumpSettings(tester);

    await tester.tap(find.byKey(_switchKey));
    await tester.pump();
    await tester.pump();

    expect(switchValue(tester), isTrue);
    expect(await store.read(thoughtsMetricsEnabledStorageKey), isNull);
  });
}

class _FailingMarkRepository extends InMemoryPostRepository {
  @override
  Future<void> markUndeliveredOwnThoughtsMetricsOptOut() async {
    throw StateError('disk full');
  }
}
