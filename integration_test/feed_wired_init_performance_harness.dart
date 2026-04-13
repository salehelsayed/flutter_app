import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/identity/application/startup_decision.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/secure_storage/fake_secure_key_store.dart';
import '../test/core/services/fake_p2p_service.dart';
import '../test/features/contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../test/features/contacts/domain/repositories/fake_contact_repository.dart';
import '../test/shared/fakes/fake_media_file_manager.dart';
import '../test/shared/fakes/in_memory_media_attachment_repository.dart';
import '../test/shared/fakes/in_memory_message_repository.dart';
import '../test/shared/fakes/in_memory_post_repository.dart';
import '../test/shared/fakes/in_memory_posts_privacy_settings_repository.dart';

late final IntegrationTestWidgetsFlutterBinding binding;

const Duration _frameStep = Duration(milliseconds: 16);
const int _maxMountFrames = 60;

class _FrameTimingCollector {
  final _timings = <FrameTiming>[];
  TimingsCallback? _callback;

  void start() {
    _timings.clear();
    _callback = (List<FrameTiming> timings) => _timings.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(_callback!);
  }

  Future<void> stop() async {
    if (_callback == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    SchedulerBinding.instance.removeTimingsCallback(_callback!);
    _callback = null;
  }

  bool get hasData => _timings.isNotEmpty;

  Map<String, dynamic> toReport() {
    if (_timings.isEmpty) {
      return <String, dynamic>{'frameCount': 0};
    }

    final buildTimesMs = _timings
        .map((timing) => timing.buildDuration.inMicroseconds / 1000.0)
        .toList(growable: false);
    final rasterTimesMs = _timings
        .map((timing) => timing.rasterDuration.inMicroseconds / 1000.0)
        .toList(growable: false);
    final averageBuildMs =
        buildTimesMs.reduce((a, b) => a + b) / buildTimesMs.length;
    final averageRasterMs =
        rasterTimesMs.reduce((a, b) => a + b) / rasterTimesMs.length;
    final missedBuildBudgetCount = buildTimesMs.where((ms) => ms > 16.0).length;
    final missedRasterBudgetCount = rasterTimesMs
        .where((ms) => ms > 16.0)
        .length;

    return <String, dynamic>{
      'frameCount': _timings.length,
      'averageBuildMs': double.parse(averageBuildMs.toStringAsFixed(3)),
      'averageRasterMs': double.parse(averageRasterMs.toStringAsFixed(3)),
      'worstBuildMs': double.parse(
        buildTimesMs.reduce((a, b) => a > b ? a : b).toStringAsFixed(3),
      ),
      'worstRasterMs': double.parse(
        rasterTimesMs.reduce((a, b) => a > b ? a : b).toStringAsFixed(3),
      ),
      'missedBuildBudgetCount': missedBuildBudgetCount,
      'missedRasterBudgetCount': missedRasterBudgetCount,
    };
  }
}

class _EventRecorder {
  final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
  Stopwatch _stopwatch = Stopwatch();

  void reset() {
    events.clear();
    _stopwatch.stop();
    _stopwatch = Stopwatch();
  }

  void start() {
    events.clear();
    _stopwatch
      ..reset()
      ..start();
  }

  void stop() {
    _stopwatch.stop();
  }

  void mark(
    String name, [
    Map<String, dynamic> details = const <String, dynamic>{},
  ]) {
    final elapsedMs = _stopwatch.elapsedMicroseconds / 1000.0;
    final event = <String, dynamic>{
      'name': name,
      'ms': double.parse(elapsedMs.toStringAsFixed(3)),
      ...details,
    };
    events.add(event);
    developer.Timeline.instantSync('feed_init_event', arguments: event);
  }

  Map<String, dynamic> summary() {
    final counts = <String, int>{};
    final firstSeenMs = <String, double>{};
    for (final event in events) {
      final name = event['name'] as String;
      counts.update(name, (value) => value + 1, ifAbsent: () => 1);
      firstSeenMs.putIfAbsent(name, () => event['ms'] as double);
    }
    return <String, dynamic>{
      'eventCount': events.length,
      'counts': counts,
      'firstSeenMs': firstSeenMs,
      'events': events,
    };
  }
}

class _TrackingSecureKeyStore implements SecureKeyStore {
  _TrackingSecureKeyStore({
    required SecureKeyStore delegate,
    required _EventRecorder recorder,
  }) : _delegate = delegate,
       _recorder = recorder;

  final SecureKeyStore _delegate;
  final _EventRecorder _recorder;

  @override
  Future<String?> read(String key) async {
    final value = await _delegate.read(key);
    _recorder.mark('secure_store_read_complete', <String, dynamic>{
      'key': key,
      'hasValue': value != null,
    });
    return value;
  }

  @override
  Future<void> write(String key, String value) => _delegate.write(key, value);

  @override
  Future<void> delete(String key) => _delegate.delete(key);

  @override
  Future<bool> containsKey(String key) => _delegate.containsKey(key);
}

class _TrackingIdentityRepository implements IdentityRepository {
  _TrackingIdentityRepository({
    required IdentityRepository delegate,
    required _EventRecorder recorder,
  }) : _delegate = delegate,
       _recorder = recorder;

  final IdentityRepository _delegate;
  final _EventRecorder _recorder;

  @override
  Future<IdentityModel?> loadIdentity() async {
    final identity = await _delegate.loadIdentity();
    _recorder.mark('identity_repo_load_complete', <String, dynamic>{
      'hasIdentity': identity != null,
    });
    return identity;
  }

  @override
  Future<void> saveIdentity(IdentityModel identity) =>
      _delegate.saveIdentity(identity);
}

class _TrackingContactRepository extends FakeContactRepository {
  _TrackingContactRepository(this.recorder);

  final _EventRecorder recorder;

  @override
  Future<List<ContactModel>> getActiveContacts() async {
    final contacts = await super.getActiveContacts();
    recorder.mark(
      'contact_repo_get_active_contacts_complete',
      <String, dynamic>{'count': contacts.length},
    );
    return contacts;
  }

  @override
  Future<int> getContactCount() async {
    final count = await super.getContactCount();
    recorder.mark('contact_repo_get_contact_count_complete', <String, dynamic>{
      'count': count,
    });
    return count;
  }
}

class _TrackingMessageRepository extends InMemoryMessageRepository {
  _TrackingMessageRepository({
    required this.recorder,
    required this.unreadCountToReturn,
  });

  final _EventRecorder recorder;
  final int unreadCountToReturn;

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    final messages = await super.getMessagesForContact(contactPeerId);
    recorder.mark(
      'message_repo_get_messages_for_contact_complete',
      <String, dynamic>{
        'contactPeerId': contactPeerId,
        'count': messages.length,
      },
    );
    return messages;
  }

  @override
  Future<int> getTotalUnreadCountExcludingArchived() async {
    recorder.mark(
      'message_repo_get_total_unread_count_complete',
      <String, dynamic>{'count': unreadCountToReturn},
    );
    return unreadCountToReturn;
  }
}

class _FeedScenario {
  const _FeedScenario({
    required this.id,
    required this.warmIdentityBeforeMount,
  });

  final String id;
  final bool warmIdentityBeforeMount;
}

class _HarnessEnvironment {
  _HarnessEnvironment({
    required this.scenario,
    required this.recorder,
    required this.feedIdentityRepo,
    required this.baseIdentityRepo,
    required this.contactRepo,
    required this.contactRequestRepo,
    required this.messageRepo,
    required this.mediaAttachmentRepo,
    required this.postRepo,
    required this.postsPrivacyRepo,
    required this.bridge,
    required this.p2pService,
    required this.secureKeyStore,
    required this.imageProcessor,
    required this.mediaFileManager,
    required this.appShellController,
    required this.pendingPostTargetStore,
    required this.testIdentity,
    required this.testContact,
  });

  final _FeedScenario scenario;
  final _EventRecorder recorder;
  final IdentityRepository feedIdentityRepo;
  final IdentityRepository baseIdentityRepo;
  final _TrackingContactRepository contactRepo;
  final FakeContactRequestRepository contactRequestRepo;
  final _TrackingMessageRepository messageRepo;
  final InMemoryMediaAttachmentRepository mediaAttachmentRepo;
  final InMemoryPostRepository postRepo;
  final InMemoryPostsPrivacySettingsRepository postsPrivacyRepo;
  final FakeBridge bridge;
  final FakeP2PService p2pService;
  final SecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;
  final FakeMediaFileManager mediaFileManager;
  final AppShellController appShellController;
  final PendingPostTargetStore pendingPostTargetStore;
  final IdentityModel testIdentity;
  final ContactModel testContact;

  Widget buildApp() {
    final contactRequestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnPeerId: () => testIdentity.peerId,
    );
    final chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepo,
      contactRepo: contactRepo,
    );

    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FeedWired(
        repository: feedIdentityRepo,
        contactRepository: contactRepo,
        contactRequestRepository: contactRequestRepo,
        contactRequestListener: contactRequestListener,
        messageRepository: messageRepo,
        postRepository: postRepo,
        mediaAttachmentRepository: mediaAttachmentRepo,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        appShellController: appShellController,
        pendingPostTargetStore: pendingPostTargetStore,
        postsPrivacySettingsRepository: postsPrivacyRepo,
      ),
    );
  }

  Future<void> primeWarmIdentityPathIfNeeded() async {
    if (!scenario.warmIdentityBeforeMount) {
      return;
    }
    final decision = await decideStartupRoute(
      identityRepo: baseIdentityRepo,
      contactRepo: contactRepo,
    );
    expect(decision, StartupDecision.hasIdentityWithContacts);
  }

  Future<void> dispose() async {
    postsPrivacyRepo.dispose();
    postRepo.dispose();
  }
}

Future<_HarnessEnvironment> _makeEnvironment(_FeedScenario scenario) async {
  final recorder = _EventRecorder();
  final backingSecureKeyStore = FakeSecureKeyStore();
  final secureKeyStore = _TrackingSecureKeyStore(
    delegate: backingSecureKeyStore,
    recorder: recorder,
  );
  final testIdentity = IdentityModel(
    peerId: '12D3KooWFeedPerfPeerId',
    publicKey: 'feed-perf-public-key',
    privateKey: 'feed-perf-private-key',
    mnemonic12:
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    username: 'Alice',
    createdAt: '2026-03-26T00:00:00.000Z',
    updatedAt: '2026-03-26T00:00:00.000Z',
  );
  final storedRow = <String, Object?>{
    'peer_id': testIdentity.peerId,
    'public_key': testIdentity.publicKey,
    'private_key': null,
    'mnemonic12': null,
    'ml_kem_public_key': null,
    'ml_kem_secret_key': null,
    'username': testIdentity.username,
    'avatar_blob': null,
    'avatar_version': null,
    'created_at': testIdentity.createdAt,
    'updated_at': testIdentity.updatedAt,
  };
  final identityRepoImpl = IdentityRepositoryImpl(
    dbLoadIdentityRow: () async {
      recorder.mark('identity_db_load_row_complete');
      return storedRow;
    },
    dbUpsertIdentityRow: (_) async {},
    secureKeyStore: secureKeyStore,
  );
  final feedIdentityRepo = _TrackingIdentityRepository(
    delegate: identityRepoImpl,
    recorder: recorder,
  );
  final contactRepo = _TrackingContactRepository(recorder);
  final testContact = ContactModel(
    peerId: 'contact-feed-perf',
    publicKey: 'contact-public-key',
    rendezvous: '/dns4/example.com/tcp/443',
    username: 'Bob',
    signature: 'sig',
    scannedAt: '2026-03-26T00:00:00.000Z',
  );
  contactRepo.seed(<ContactModel>[testContact]);

  final messageRepo = _TrackingMessageRepository(
    recorder: recorder,
    unreadCountToReturn: 3,
  );
  final now = DateTime(2026, 3, 26, 12, 0);
  await messageRepo.saveMessage(
    ConversationMessage(
      id: 'msg-feed-perf-1',
      contactPeerId: testContact.peerId,
      text: 'Unread one',
      senderPeerId: testContact.peerId,
      timestamp: now
          .subtract(const Duration(minutes: 5))
          .toUtc()
          .toIso8601String(),
      isIncoming: true,
      status: 'delivered',
      createdAt: now
          .subtract(const Duration(minutes: 5))
          .toUtc()
          .toIso8601String(),
    ),
  );
  await messageRepo.saveMessage(
    ConversationMessage(
      id: 'msg-feed-perf-2',
      contactPeerId: testContact.peerId,
      text: 'Unread two',
      senderPeerId: testContact.peerId,
      timestamp: now
          .subtract(const Duration(minutes: 4))
          .toUtc()
          .toIso8601String(),
      isIncoming: true,
      status: 'delivered',
      createdAt: now
          .subtract(const Duration(minutes: 4))
          .toUtc()
          .toIso8601String(),
    ),
  );
  await messageRepo.saveMessage(
    ConversationMessage(
      id: 'msg-feed-perf-3',
      contactPeerId: testContact.peerId,
      text: 'Reply',
      senderPeerId: testIdentity.peerId,
      timestamp: now
          .subtract(const Duration(minutes: 3))
          .toUtc()
          .toIso8601String(),
      isIncoming: false,
      status: 'read',
      createdAt: now
          .subtract(const Duration(minutes: 3))
          .toUtc()
          .toIso8601String(),
    ),
  );

  await backingSecureKeyStore.write(
    'identity_private_key',
    testIdentity.privateKey,
  );
  await backingSecureKeyStore.write(
    'identity_mnemonic12',
    testIdentity.mnemonic12,
  );
  await backingSecureKeyStore.write('image_quality_preference', 'original');
  await backingSecureKeyStore.write('video_quality_preference', 'original');

  return _HarnessEnvironment(
    scenario: scenario,
    recorder: recorder,
    feedIdentityRepo: feedIdentityRepo,
    baseIdentityRepo: identityRepoImpl,
    contactRepo: contactRepo,
    contactRequestRepo: FakeContactRequestRepository(),
    messageRepo: messageRepo,
    mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
    postRepo: InMemoryPostRepository(),
    postsPrivacyRepo: InMemoryPostsPrivacySettingsRepository(),
    bridge: FakeBridge(),
    p2pService: FakeP2PService(),
    secureKeyStore: secureKeyStore,
    imageProcessor: ImageProcessor(
      compressFile:
          ({
            required path,
            required quality,
            required keepExif,
            minWidth = 1920,
            minHeight = 1080,
          }) async => null,
      compressVideo: ({required path, required compress, onProgress}) async =>
          null,
    ),
    mediaFileManager: FakeMediaFileManager(),
    appShellController: AppShellController(),
    pendingPostTargetStore: PendingPostTargetStore(),
    testIdentity: testIdentity,
    testContact: testContact,
  );
}

Future<void> _pumpThroughMount(
  WidgetTester tester,
  _HarnessEnvironment env,
) async {
  var sawFeedScreen = false;
  var sawIdentityVisible = false;
  var sawFeedItems = false;
  var sawFeedLoaded = false;
  var idleFrames = 0;

  for (var i = 0; i < _maxMountFrames; i++) {
    await tester.pump(_frameStep);

    final feedScreenFinder = find.byType(FeedScreen);
    if (feedScreenFinder.evaluate().isEmpty) {
      continue;
    }

    final feedScreen = tester.widget<FeedScreen>(feedScreenFinder);
    if (!sawFeedScreen) {
      env.recorder.mark('ui_feed_screen_visible');
      sawFeedScreen = true;
    }
    if (!sawIdentityVisible &&
        (feedScreen.username != 'Username' || feedScreen.userPeerId != null)) {
      env.recorder.mark('ui_identity_visible', <String, dynamic>{
        'username': feedScreen.username,
        'hasPeerId': feedScreen.userPeerId != null,
      });
      sawIdentityVisible = true;
    }
    if (!sawFeedItems && feedScreen.feedItems.isNotEmpty) {
      env.recorder.mark('ui_feed_items_visible', <String, dynamic>{
        'itemCount': feedScreen.feedItems.length,
      });
      sawFeedItems = true;
    }
    if (!sawFeedLoaded && feedScreen.feedLoaded) {
      env.recorder.mark('ui_feed_loaded_true', <String, dynamic>{
        'itemCount': feedScreen.feedItems.length,
      });
      sawFeedLoaded = true;
    }

    if (tester.binding.hasScheduledFrame) {
      idleFrames = 0;
    } else {
      idleFrames++;
    }

    if (sawFeedLoaded && sawIdentityVisible && idleFrames >= 5) {
      break;
    }
  }
}

Map<String, dynamic> _timelineSummary(Map<String, dynamic> timeline) {
  final events =
      (timeline['traceEvents'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
  final initEvents = events
      .where((event) => event['name'] == 'feed_init_event')
      .toList(growable: false);
  final initEventNames = initEvents
      .map(
        (event) => ((event['args'] as Map<dynamic, dynamic>?)?['name'] ?? '')
            .toString(),
      )
      .toList(growable: false);

  int countContains(String needle) =>
      events.where((event) => '${event['name'] ?? ''}'.contains(needle)).length;

  return <String, dynamic>{
    'eventCount': events.length,
    'feedInitMarkerCount': initEvents.length,
    'distinctFeedInitMarkers': initEventNames.toSet().toList()..sort(),
    'sceneDisplayLagEvents': countContains('SceneDisplayLag'),
    'customPaintEvents': countContains('RenderCustomPaint'),
    'backdropFilterEvents': countContains('BackdropFilter'),
  };
}

Future<bool> _canUseVmServiceTimeline() async {
  final info = await developer.Service.getInfo();
  return info.serverUri != null;
}

void _printReportEntry(String key) {
  final data = binding.reportData?[key];
  if (data == null) {
    debugPrint('[$key] report entry missing');
    return;
  }
  debugPrint('[$key] ${jsonEncode(data)}');
}

Future<void> _captureScenario(
  WidgetTester tester,
  _FeedScenario scenario,
) async {
  Future<_HarnessEnvironment> prepareEnvironment() async {
    final env = await _makeEnvironment(scenario);
    await env.primeWarmIdentityPathIfNeeded();
    env.recorder.reset();
    return env;
  }

  final perfKey = '${scenario.id}_performance';
  final frameSummaryKey = '${scenario.id}_frame_summary';
  final initEventsKey = '${scenario.id}_init_events';
  final initSummaryKey = '${scenario.id}_init_summary';
  final timelineKey = '${scenario.id}_timeline';
  final timelineSummaryKey = '${scenario.id}_timeline_summary';

  final perfEnv = await prepareEnvironment();
  final perfCollector = _FrameTimingCollector()..start();
  if (await _canUseVmServiceTimeline()) {
    await binding.watchPerformance(() async {
      perfEnv.recorder.start();
      await tester.pumpWidget(perfEnv.buildApp());
      await _pumpThroughMount(tester, perfEnv);
      perfEnv.recorder.stop();
    }, reportKey: perfKey);
  } else {
    perfEnv.recorder.start();
    await tester.pumpWidget(perfEnv.buildApp());
    await _pumpThroughMount(tester, perfEnv);
    perfEnv.recorder.stop();
  }
  await perfCollector.stop();
  binding.reportData ??= <String, dynamic>{};
  binding.reportData![perfKey] ??= perfCollector.toReport();
  binding.reportData![frameSummaryKey] = perfCollector.toReport();
  binding.reportData![initEventsKey] = perfEnv.recorder.events;
  binding.reportData![initSummaryKey] = perfEnv.recorder.summary();
  _printReportEntry(perfKey);
  _printReportEntry(frameSummaryKey);
  _printReportEntry(initSummaryKey);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await perfEnv.dispose();

  final timelineEnv = await prepareEnvironment();
  if (await _canUseVmServiceTimeline()) {
    await binding.traceAction(
      () async {
        timelineEnv.recorder.start();
        await tester.pumpWidget(timelineEnv.buildApp());
        await _pumpThroughMount(tester, timelineEnv);
        timelineEnv.recorder.stop();
      },
      reportKey: timelineKey,
      streams: const <String>['all'],
    );
    final timeline = binding.reportData?[timelineKey] as Map<String, dynamic>;
    binding.reportData![timelineSummaryKey] = _timelineSummary(timeline);
  } else {
    timelineEnv.recorder.start();
    await tester.pumpWidget(timelineEnv.buildApp());
    await _pumpThroughMount(tester, timelineEnv);
    timelineEnv.recorder.stop();
    binding.reportData![timelineSummaryKey] = <String, dynamic>{
      'eventCount': 0,
      'feedInitMarkerCount': 0,
      'distinctFeedInitMarkers': const <String>[],
      'sceneDisplayLagEvents': 0,
      'customPaintEvents': 0,
      'backdropFilterEvents': 0,
      'captureMode': 'frame_timing_fallback',
    };
  }
  _printReportEntry(timelineSummaryKey);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await timelineEnv.dispose();
}

void main() {
  final skipOnMobileDevice = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  if (skipOnMobileDevice) {
    testWidgets(
      'captures FeedWired init performance evidence',
      (_) async {},
      skip: true,
    );
    return;
  }
  VmServiceProxyGoldenFileComparator.useIfRunningOnDevice();
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const scenarios = <_FeedScenario>[
    _FeedScenario(
      id: 'feed_wired_mount_cold_identity_cache',
      warmIdentityBeforeMount: false,
    ),
    _FeedScenario(
      id: 'feed_wired_mount_warm_identity_cache',
      warmIdentityBeforeMount: true,
    ),
  ];

  testWidgets('captures FeedWired init performance evidence', (tester) async {
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['feed_wired_init_perf_meta'] = <String, dynamic>{
      'maxMountFrames': _maxMountFrames,
      'frameStepMs': _frameStep.inMilliseconds,
      'scenarios': scenarios
          .map(
            (scenario) => <String, dynamic>{
              'id': scenario.id,
              'warmIdentityBeforeMount': scenario.warmIdentityBeforeMount,
            },
          )
          .toList(growable: false),
      'warmIdentityMethod': 'decideStartupRoute before FeedWired mount',
      'productionCodeChanged': false,
    };

    for (final scenario in scenarios) {
      await _captureScenario(tester, scenario);
    }

    expect(binding.reportData, isNotNull);
  });
}
