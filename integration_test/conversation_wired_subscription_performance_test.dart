import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/shared/widgets/media/recording_overlay.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/services/fake_p2p_service.dart';
import '../test/features/conversation/domain/repositories/fake_message_repository.dart';
import '../test/features/conversation/domain/repositories/fake_reaction_repository.dart';
import '../test/features/contacts/domain/repositories/fake_contact_repository.dart';
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/fake_audio_recorder_service.dart';
import '../test/shared/fakes/in_memory_media_attachment_repository.dart';

late final IntegrationTestWidgetsFlutterBinding binding;

const _frameStep = Duration(milliseconds: 16);
const _settleFrames = 24;

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
    final worstBuildMs = buildTimesMs.reduce((a, b) => a > b ? a : b);
    final worstRasterMs = rasterTimesMs.reduce((a, b) => a > b ? a : b);

    return <String, dynamic>{
      'frameCount': _timings.length,
      'averageBuildMs': double.parse(averageBuildMs.toStringAsFixed(3)),
      'averageRasterMs': double.parse(averageRasterMs.toStringAsFixed(3)),
      'worstBuildMs': double.parse(worstBuildMs.toStringAsFixed(3)),
      'worstRasterMs': double.parse(worstRasterMs.toStringAsFixed(3)),
      'missedBuildBudgetCount': buildTimesMs.where((ms) => ms > 16.0).length,
      'missedRasterBudgetCount': rasterTimesMs.where((ms) => ms > 16.0).length,
    };
  }
}

class _EventRecorder {
  final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
  Stopwatch _stopwatch = Stopwatch();

  void start() {
    events.clear();
    _stopwatch
      ..reset()
      ..start();
  }

  void stop() {
    _stopwatch.stop();
  }

  void mark(String name, [Map<String, dynamic> details = const {}]) {
    final ms = _stopwatch.elapsedMicroseconds / 1000.0;
    final event = <String, dynamic>{
      'name': name,
      'ms': double.parse(ms.toStringAsFixed(3)),
      ...details,
    };
    events.add(event);
    developer.Timeline.instantSync('conversation_perf_event', arguments: event);
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

class _TrackingMessageRepository extends FakeMessageRepository
    implements MessageRepositoryChangeSource {
  _TrackingMessageRepository({required this.recorder});

  final _EventRecorder recorder;
  final _changeController = StreamController<ConversationMessage>.broadcast();

  Stream<ConversationMessage> get messageChanges => _changeController.stream;

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    await super.saveMessage(message);
    recorder.mark('repo_change_emitted', <String, dynamic>{
      'messageId': message.id,
      'status': message.status,
      'isIncoming': message.isIncoming,
    });
    _changeController.add(message);
  }

  Future<void> dispose() async {
    await _changeController.close();
  }
}

class _TrackingChatMessageListener extends ChatMessageListener {
  _TrackingChatMessageListener({
    required super.messageRepo,
    required super.contactRepo,
    required this.recorder,
  }) : super(chatMessageStream: const Stream<ChatMessage>.empty());

  final _EventRecorder recorder;
  final _incomingController = StreamController<ConversationMessage>.broadcast();
  final _contactUpdateController = StreamController<ContactModel>.broadcast();

  @override
  Stream<ConversationMessage> get incomingMessageStream =>
      _incomingController.stream;

  @override
  Stream<ContactModel> get contactUpdatedStream =>
      _contactUpdateController.stream;

  void emitIncomingMessage(ConversationMessage message) {
    recorder.mark('incoming_message_emitted', <String, dynamic>{
      'messageId': message.id,
      'status': message.status,
    });
    _incomingController.add(message);
  }

  @override
  void emitContactUpdate(ContactModel contact) {
    recorder.mark('contact_update_emitted', <String, dynamic>{
      'username': contact.username,
    });
    _contactUpdateController.add(contact);
  }

  Future<void> disposeControllers() async {
    await _incomingController.close();
    await _contactUpdateController.close();
  }
}

class _TrackingReactionListener extends ReactionListener {
  _TrackingReactionListener({
    required super.reactionRepo,
    required super.contactRepo,
    required super.bridge,
    required this.recorder,
  }) : super(
         reactionStream: const Stream<ChatMessage>.empty(),
         getOwnMlKemSecretKey: () async => null,
       );

  final _EventRecorder recorder;
  final _reactionChangeController =
      StreamController<ReactionChange>.broadcast();

  @override
  Stream<ReactionChange> get incomingReactionChangeStream =>
      _reactionChangeController.stream;

  void emitReactionChange(ReactionChange change) {
    recorder.mark('reaction_change_emitted', <String, dynamic>{
      'messageId': change.messageId,
      'type': change.type.name,
    });
    _reactionChangeController.add(change);
  }

  Future<void> disposeControllers() async {
    await _reactionChangeController.close();
  }
}

class _ConversationScenario {
  const _ConversationScenario({required this.id, required this.kind});

  final String id;
  final String kind;
}

class _HarnessEnvironment {
  _HarnessEnvironment({
    required this.scenario,
    required this.recorder,
    required this.identityRepo,
    required this.messageRepo,
    required this.contactRepo,
    required this.chatListener,
    required this.reactionRepo,
    required this.reactionListener,
    required this.bridge,
    required this.p2pService,
    required this.mediaAttachmentRepo,
    required this.audioRecorderService,
    required this.conversationTracker,
    required this.contact,
    required this.initialMessages,
  });

  final _ConversationScenario scenario;
  final _EventRecorder recorder;
  final FakeIdentityRepository identityRepo;
  final _TrackingMessageRepository messageRepo;
  final FakeContactRepository contactRepo;
  final _TrackingChatMessageListener chatListener;
  final FakeReactionRepository reactionRepo;
  final _TrackingReactionListener reactionListener;
  final FakeBridge bridge;
  final FakeP2PService p2pService;
  final InMemoryMediaAttachmentRepository mediaAttachmentRepo;
  final FakeAudioRecorderService audioRecorderService;
  final ActiveConversationTracker conversationTracker;
  final ContactModel contact;
  final List<ConversationMessage> initialMessages;

  static Future<_HarnessEnvironment> create(
    _ConversationScenario scenario,
  ) async {
    final recorder = _EventRecorder();
    final identityRepo = FakeIdentityRepository();
    final identity = IdentityModel(
      peerId: 'self-peer',
      publicKey: 'self-pk',
      privateKey: 'self-sk',
      mnemonic12:
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
      username: 'Me',
      createdAt: '2026-03-26T00:00:00Z',
      updatedAt: '2026-03-26T00:00:00Z',
    );
    identityRepo.seed(identity);

    final contact = ContactModel(
      peerId: 'contact-peer',
      publicKey: 'contact-pk',
      rendezvous: '/dns4/example.com/tcp/443',
      username: 'Alice',
      signature: 'sig',
      scannedAt: '2026-03-26T00:00:00Z',
    );
    final contactRepo = FakeContactRepository()..seed(<ContactModel>[contact]);

    final now = DateTime(2026, 3, 26, 12, 0);
    final initialMessages = <ConversationMessage>[
      ConversationMessage(
        id: 'msg-1',
        contactPeerId: contact.peerId,
        text: 'Initial message',
        senderPeerId: contact.peerId,
        timestamp: now.subtract(const Duration(minutes: 2)).toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: now.subtract(const Duration(minutes: 2)).toIso8601String(),
      ),
      ConversationMessage(
        id: 'msg-2',
        contactPeerId: contact.peerId,
        text: 'Reply',
        senderPeerId: identity.peerId,
        timestamp: now.subtract(const Duration(minutes: 1)).toIso8601String(),
        isIncoming: false,
        status: 'read',
        createdAt: now.subtract(const Duration(minutes: 1)).toIso8601String(),
      ),
    ];

    final messageRepo = _TrackingMessageRepository(recorder: recorder)
      ..seed(initialMessages);
    final chatListener = _TrackingChatMessageListener(
      recorder: recorder,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
    );
    final reactionRepo = FakeReactionRepository();
    final reactionListener = _TrackingReactionListener(
      recorder: recorder,
      reactionRepo: reactionRepo,
      contactRepo: contactRepo,
      bridge: FakeBridge(),
    );

    return _HarnessEnvironment(
      scenario: scenario,
      recorder: recorder,
      identityRepo: identityRepo,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      chatListener: chatListener,
      reactionRepo: reactionRepo,
      reactionListener: reactionListener,
      bridge: FakeBridge(),
      p2pService: FakeP2PService(),
      mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
      audioRecorderService: FakeAudioRecorderService()..fakeDurationMs = 1200,
      conversationTracker: ActiveConversationTracker(),
      contact: contact,
      initialMessages: initialMessages,
    );
  }

  Future<void> dispose() async {
    await chatListener.disposeControllers();
    await reactionListener.disposeControllers();
    await messageRepo.dispose();
    await audioRecorderService.dispose();
  }
}

class _ConversationHost extends StatefulWidget {
  const _ConversationHost({super.key, required this.env});

  final _HarnessEnvironment env;

  @override
  State<_ConversationHost> createState() => _ConversationHostState();
}

class _ConversationHostState extends State<_ConversationHost> {
  final navigatorKey = GlobalKey<NavigatorState>();

  void pushCover() {
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('Cover'))),
        ),
      ),
    );
  }

  void popCover() {
    navigatorKey.currentState!.pop();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ConversationWired(
        contact: widget.env.contact,
        identityRepo: widget.env.identityRepo,
        messageRepo: widget.env.messageRepo,
        chatMessageListener: widget.env.chatListener,
        p2pService: widget.env.p2pService,
        bridge: widget.env.bridge,
        contactRepo: widget.env.contactRepo,
        mediaAttachmentRepo: widget.env.mediaAttachmentRepo,
        conversationTracker: widget.env.conversationTracker,
        audioRecorderService: widget.env.audioRecorderService,
        reactionRepo: widget.env.reactionRepo,
        reactionListener: widget.env.reactionListener,
      ),
    );
  }
}

Future<void> _pumpFrames(WidgetTester tester, {required int count}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frameStep);
  }
}

Future<void> _pumpUntilReady(
  WidgetTester tester,
  _HarnessEnvironment env,
) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frameStep);
    final screenFinder = find.byType(ConversationScreen);
    if (screenFinder.evaluate().isEmpty) {
      continue;
    }
    final screen = tester.widget<ConversationScreen>(screenFinder);
    if (screen.initialLoadDone && screen.messages.isNotEmpty) {
      env.recorder.mark('ui_conversation_ready', <String, dynamic>{
        'messageCount': screen.messages.length,
      });
      return;
    }
  }
  fail('ConversationScreen did not become ready');
}

void _markConversationState(
  WidgetTester tester,
  _HarnessEnvironment env,
  String name,
) {
  final screen = tester.widget<ConversationScreen>(
    find.byType(ConversationScreen, skipOffstage: false),
  );
  final composerState =
      screen.composerStateListenable?.value ??
      ConversationComposerViewState(
        recordingState: screen.recordingState != VoiceRecordingState.idle
            ? screen.recordingState
            : (screen.isRecording
                  ? VoiceRecordingState.recording
                  : VoiceRecordingState.idle),
        recordingDuration: screen.recordingDuration,
        amplitudeValues: screen.amplitudeValues,
      );
  env.recorder.mark(name, <String, dynamic>{
    'messageCount': screen.messages.length,
    'recordingState': composerState.recordingState.name,
    'recordingDurationMs': composerState.recordingDuration.inMilliseconds,
    'amplitudeCount': composerState.amplitudeValues.length,
    'overlayVisible': find
        .byType(RecordingOverlay, skipOffstage: false)
        .evaluate()
        .isNotEmpty,
    'timerVisible': find
        .text('0:01', skipOffstage: false)
        .evaluate()
        .isNotEmpty,
  });
}

Future<void> _runVisibleStreamActivity(
  WidgetTester tester,
  _HarnessEnvironment env,
) async {
  final incoming = ConversationMessage(
    id: 'msg-visible-incoming',
    contactPeerId: env.contact.peerId,
    text: 'Visible incoming',
    senderPeerId: env.contact.peerId,
    timestamp: DateTime(2026, 3, 26, 12, 5).toIso8601String(),
    isIncoming: true,
    status: 'delivered',
    createdAt: DateTime(2026, 3, 26, 12, 5).toIso8601String(),
  );
  env.chatListener.emitIncomingMessage(incoming);
  env.chatListener.emitContactUpdate(env.contact.copyWith(username: 'Alice+'));
  await env.messageRepo.saveMessage(
    ConversationMessage(
      id: 'msg-outgoing-failed',
      contactPeerId: env.contact.peerId,
      text: 'Retry me',
      senderPeerId: 'self-peer',
      timestamp: DateTime(2026, 3, 26, 12, 6).toIso8601String(),
      isIncoming: false,
      status: 'failed',
      createdAt: DateTime(2026, 3, 26, 12, 6).toIso8601String(),
    ),
  );
  env.reactionListener.emitReactionChange(
    ReactionChange.upsert(
      MessageReaction(
        id: 'reaction-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: env.contact.peerId,
        timestamp: DateTime(2026, 3, 26, 12, 7).toIso8601String(),
        createdAt: DateTime(2026, 3, 26, 12, 7).toIso8601String(),
      ),
    ),
  );
  await _pumpFrames(tester, count: 12);
  _markConversationState(tester, env, 'ui_after_visible_stream_activity');
}

Future<void> _runRecordingWindow(
  WidgetTester tester,
  _HarnessEnvironment env,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byIcon(Icons.mic_rounded)),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pump();
  env.recorder.mark('recording_started');
  env.audioRecorderService.emitDuration(const Duration(seconds: 1));
  env.audioRecorderService.emitAmplitude(0.2);
  env.audioRecorderService.emitAmplitude(0.4);
  await _pumpFrames(tester, count: 6);
  expect(find.byType(RecordingOverlay), findsOneWidget);
  expect(find.text('Cancel'), findsOneWidget);
  expect(find.text('0:01'), findsOneWidget);
  _markConversationState(tester, env, 'ui_recording_active');

  await tester.tap(find.text('Cancel'));
  await tester.pump();
  env.recorder.mark('recording_cancelled');
  await _pumpFrames(tester, count: 6);
  expect(find.byType(RecordingOverlay), findsNothing);
  _markConversationState(tester, env, 'ui_after_recording_cancel');
}

Future<void> _runCoveredRouteActivity(
  WidgetTester tester,
  _HarnessEnvironment env,
) async {
  final hostState = tester.state<_ConversationHostState>(
    find.byType(_ConversationHost),
  );
  hostState.pushCover();
  await _pumpFrames(tester, count: 10);
  expect(find.text('Cover'), findsOneWidget);
  env.recorder.mark('cover_route_visible', <String, dynamic>{
    'trackerActive': env.conversationTracker.isViewing(env.contact.peerId),
  });

  final incoming = ConversationMessage(
    id: 'msg-covered-incoming',
    contactPeerId: env.contact.peerId,
    text: 'Hidden route incoming',
    senderPeerId: env.contact.peerId,
    timestamp: DateTime(2026, 3, 26, 12, 8).toIso8601String(),
    isIncoming: true,
    status: 'delivered',
    createdAt: DateTime(2026, 3, 26, 12, 8).toIso8601String(),
  );
  env.chatListener.emitIncomingMessage(incoming);
  await env.messageRepo.saveMessage(
    ConversationMessage(
      id: 'msg-covered-failed',
      contactPeerId: env.contact.peerId,
      text: 'Hidden route failed',
      senderPeerId: 'self-peer',
      timestamp: DateTime(2026, 3, 26, 12, 9).toIso8601String(),
      isIncoming: false,
      status: 'failed',
      createdAt: DateTime(2026, 3, 26, 12, 9).toIso8601String(),
    ),
  );
  env.reactionListener.emitReactionChange(
    ReactionChange.upsert(
      MessageReaction(
        id: 'reaction-2',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: env.contact.peerId,
        timestamp: DateTime(2026, 3, 26, 12, 10).toIso8601String(),
        createdAt: DateTime(2026, 3, 26, 12, 10).toIso8601String(),
      ),
    ),
  );
  await _pumpFrames(tester, count: 12);
  _markConversationState(tester, env, 'ui_while_covered');

  hostState.popCover();
  for (var i = 0; i < 40; i++) {
    await tester.pump(_frameStep);
    if (find.text('Cover').evaluate().isEmpty) {
      break;
    }
  }
  expect(find.text('Cover'), findsNothing);
  _markConversationState(tester, env, 'ui_after_cover_removed');
}

Future<void> _runScenario(
  WidgetTester tester,
  _ConversationScenario scenario,
) async {
  final env = await _HarnessEnvironment.create(scenario);
  final collector = _FrameTimingCollector()..start();
  try {
    env.recorder.start();
    await tester.pumpWidget(_ConversationHost(env: env));
    await _pumpUntilReady(tester, env);

    switch (scenario.kind) {
      case 'open_idle':
        await _pumpFrames(tester, count: _settleFrames);
        _markConversationState(tester, env, 'ui_after_idle_settle');
        break;
      case 'visible_stream_activity':
        await _runVisibleStreamActivity(tester, env);
        break;
      case 'recording_window':
        await _runRecordingWindow(tester, env);
        break;
      case 'covered_route_activity':
        await _runCoveredRouteActivity(tester, env);
        break;
      default:
        fail('Unknown scenario kind: ${scenario.kind}');
    }

    env.recorder.stop();
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['${scenario.id}_events'] = env.recorder.events;
    binding.reportData!['${scenario.id}_event_summary'] = env.recorder
        .summary();
    binding.reportData!['${scenario.id}_frame_summary'] = collector.toReport();
  } finally {
    await collector.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await env.dispose();
  }
}

Map<String, dynamic> _timelineSummary(Map<String, dynamic> timeline) {
  final events =
      (timeline['traceEvents'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
  final perfEvents = events
      .where((event) => event['name'] == 'conversation_perf_event')
      .toList(growable: false);

  int countContains(String needle) =>
      events.where((event) => '${event['name'] ?? ''}'.contains(needle)).length;

  return <String, dynamic>{
    'eventCount': events.length,
    'conversationPerfMarkerCount': perfEvents.length,
    'distinctMarkers':
        perfEvents
            .map(
              (event) =>
                  ((event['args'] as Map<dynamic, dynamic>?)?['name'] ?? '')
                      .toString(),
            )
            .toSet()
            .toList()
          ..sort(),
    'sceneDisplayLagEvents': countContains('SceneDisplayLag'),
    'customPaintEvents': countContains('RenderCustomPaint'),
    'backdropFilterEvents': countContains('BackdropFilter'),
  };
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
  _ConversationScenario scenario,
) async {
  final perfKey = '${scenario.id}_performance';
  final timelineKey = '${scenario.id}_timeline';
  final timelineSummaryKey = '${scenario.id}_timeline_summary';

  await binding.watchPerformance(
    () async => _runScenario(tester, scenario),
    reportKey: perfKey,
  );
  _printReportEntry(perfKey);
  _printReportEntry('${scenario.id}_event_summary');
  _printReportEntry('${scenario.id}_frame_summary');

  await binding.traceAction(
    () async => _runScenario(tester, scenario),
    reportKey: timelineKey,
    streams: const <String>['all'],
  );
  final timeline = binding.reportData?[timelineKey] as Map<String, dynamic>;
  binding.reportData ??= <String, dynamic>{};
  binding.reportData![timelineSummaryKey] = _timelineSummary(timeline);
  _printReportEntry(timelineSummaryKey);
}

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const scenarios = <_ConversationScenario>[
    _ConversationScenario(
      id: 'conversation_route_open_idle',
      kind: 'open_idle',
    ),
    _ConversationScenario(
      id: 'conversation_visible_stream_activity',
      kind: 'visible_stream_activity',
    ),
    _ConversationScenario(
      id: 'conversation_recording_window',
      kind: 'recording_window',
    ),
    _ConversationScenario(
      id: 'conversation_covered_route_activity',
      kind: 'covered_route_activity',
    ),
  ];

  testWidgets('captures ConversationWired subscription evidence', (
    WidgetTester tester,
  ) async {
    binding.reportData ??= <String, dynamic>{};
    binding
        .reportData!['conversation_subscription_perf_meta'] = <String, dynamic>{
      'scenarios': scenarios
          .map(
            (scenario) => <String, dynamic>{
              'id': scenario.id,
              'kind': scenario.kind,
            },
          )
          .toList(growable: false),
      'frameStepMs': _frameStep.inMilliseconds,
      'backgroundForegroundProfileCaptured': false,
      'backgroundForegroundReason':
          'ConversationWired has no own app lifecycle observer; macOS fallback run uses covered-route activity as the repo-local off-screen proxy.',
      'productionCodeChanged': false,
    };

    for (final scenario in scenarios) {
      await _captureScenario(tester, scenario);
    }

    expect(binding.reportData, isNotNull);
  });
}
