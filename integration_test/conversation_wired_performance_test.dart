import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/services/fake_p2p_service.dart';
import '../test/features/contacts/domain/repositories/fake_contact_repository.dart';
import '../test/features/conversation/domain/repositories/fake_message_repository.dart';
import '../test/features/conversation/domain/repositories/fake_reaction_repository.dart';
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';

late final IntegrationTestWidgetsFlutterBinding binding;

const Duration _frameStep = Duration(milliseconds: 16);
const int _openFrames = 36;
const int _idleFrames = 24;
const int _coverFrames = 20;
const int _closeFrames = 20;
const int _streamBurstIterations = 4;
const int _recordingTickIterations = 8;

class _FrameTimingCollector {
  final _timings = <FrameTiming>[];
  TimingsCallback? _callback;

  void start() {
    _timings.clear();
    _callback = (List<FrameTiming> timings) => _timings.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(_callback!);
  }

  Future<Map<String, dynamic>> stopAndReport() async {
    if (_callback == null) {
      return <String, dynamic>{'frameCount': 0};
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    SchedulerBinding.instance.removeTimingsCallback(_callback!);
    _callback = null;

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
      'missedBuildBudgetCount': buildTimesMs.where((ms) => ms > 16.0).length,
      'missedRasterBudgetCount': rasterTimesMs.where((ms) => ms > 16.0).length,
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
    final event = <String, dynamic>{
      'name': name,
      'ms': double.parse(
        (_stopwatch.elapsedMicroseconds / 1000.0).toStringAsFixed(3),
      ),
      ...details,
    };
    events.add(event);
    developer.Timeline.instantSync('conversation_perf_event', arguments: event);
  }

  Map<String, dynamic> summary() {
    final countsByName = <String, int>{};
    final countsByPhase = <String, int>{};
    final firstSeenMs = <String, double>{};

    for (final event in events) {
      final name = event['name'] as String;
      countsByName.update(name, (value) => value + 1, ifAbsent: () => 1);
      firstSeenMs.putIfAbsent(name, () => event['ms'] as double);
      final phase = event['phase'];
      if (phase is String && phase.isNotEmpty) {
        countsByPhase.update(phase, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    return <String, dynamic>{
      'eventCount': events.length,
      'countsByName': countsByName,
      'countsByPhase': countsByPhase,
      'firstSeenMs': firstSeenMs,
      'events': events,
    };
  }
}

class _TrackingIdentityRepository extends FakeIdentityRepository {
  _TrackingIdentityRepository({
    required this.recorder,
    required IdentityModel seed,
  }) : super() {
    this.seed(seed);
  }

  final _EventRecorder recorder;

  @override
  Future<IdentityModel?> loadIdentity() async {
    final identity = await super.loadIdentity();
    recorder.mark('identity_load_complete', <String, dynamic>{
      'hasIdentity': identity != null,
    });
    return identity;
  }
}

class _TrackingMessageRepository extends FakeMessageRepository
    implements MessageRepositoryChangeSource {
  _TrackingMessageRepository(this.recorder)
    : _messageChangesController =
          StreamController<ConversationMessage>.broadcast(
            onListen: () => recorder.mark('repo_change_listener_attached'),
            onCancel: () => recorder.mark('repo_change_listener_detached'),
          );

  final _EventRecorder recorder;
  final StreamController<ConversationMessage> _messageChangesController;

  @override
  Stream<ConversationMessage> get messageChanges =>
      _messageChangesController.stream;

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    final messages = await super.getMessagesPage(
      contactPeerId,
      limit: limit,
      beforeTimestamp: beforeTimestamp,
    );
    recorder.mark('initial_page_loaded', <String, dynamic>{
      'contactPeerId': contactPeerId,
      'count': messages.length,
    });
    return messages;
  }

  @override
  Future<int> markConversationAsRead(String contactPeerId) async {
    final count = await super.markConversationAsRead(contactPeerId);
    recorder.mark('mark_conversation_read_complete', <String, dynamic>{
      'contactPeerId': contactPeerId,
      'count': count,
    });
    return count;
  }

  Future<void> emitRepoChange(
    ConversationMessage message, {
    required String phase,
  }) async {
    await super.saveMessage(message);
    recorder.mark('repo_change_emit', <String, dynamic>{
      'phase': phase,
      'status': message.status,
      'messageId': message.id,
    });
    _messageChangesController.add(message);
  }

  Future<void> disposeTracked() async {
    await _messageChangesController.close();
  }
}

class _TrackingChatMessageListener extends ChatMessageListener {
  _TrackingChatMessageListener({
    required this.recorder,
    required MessageRepository messageRepo,
    required ContactRepository contactRepo,
  }) : _incomingController = StreamController<ConversationMessage>.broadcast(
         onListen: () => recorder.mark('incoming_listener_attached'),
         onCancel: () => recorder.mark('incoming_listener_detached'),
       ),
       _contactController = StreamController<ContactModel>.broadcast(
         onListen: () => recorder.mark('contact_update_listener_attached'),
         onCancel: () => recorder.mark('contact_update_listener_detached'),
       ),
       super(
         chatMessageStream: const Stream.empty(),
         messageRepo: messageRepo,
         contactRepo: contactRepo,
       );

  final _EventRecorder recorder;
  final StreamController<ConversationMessage> _incomingController;
  final StreamController<ContactModel> _contactController;

  @override
  Stream<ConversationMessage> get incomingMessageStream =>
      _incomingController.stream;

  @override
  Stream<ContactModel> get contactUpdatedStream => _contactController.stream;

  @override
  void start() {}

  @override
  void stop() {}

  void emitIncomingMessage(
    ConversationMessage message, {
    required String phase,
  }) {
    recorder.mark('incoming_message_emit', <String, dynamic>{
      'phase': phase,
      'messageId': message.id,
    });
    _incomingController.add(message);
  }

  void emitTrackedContactUpdate(ContactModel contact, {required String phase}) {
    recorder.mark('contact_update_emit', <String, dynamic>{
      'phase': phase,
      'username': contact.username,
    });
    _contactController.add(contact);
  }

  Future<void> disposeTracked() async {
    await _incomingController.close();
    await _contactController.close();
  }
}

class _TrackingReactionRepository extends FakeReactionRepository {
  _TrackingReactionRepository(this.recorder);

  final _EventRecorder recorder;

  @override
  Future<Map<String, List<MessageReaction>>> getReactionsForMessages(
    List<String> messageIds,
  ) async {
    final result = await super.getReactionsForMessages(messageIds);
    recorder.mark('initial_reactions_loaded', <String, dynamic>{
      'messageCount': messageIds.length,
      'reactionMessageCount': result.length,
    });
    return result;
  }
}

class _TrackingReactionListener extends ReactionListener {
  _TrackingReactionListener({
    required this.recorder,
    required _TrackingReactionRepository reactionRepo,
    required ContactRepository contactRepo,
    required Bridge bridge,
  }) : _changeController = StreamController<ReactionChange>.broadcast(
         onListen: () => recorder.mark('reaction_listener_attached'),
         onCancel: () => recorder.mark('reaction_listener_detached'),
       ),
       super(
         reactionStream: const Stream.empty(),
         reactionRepo: reactionRepo,
         contactRepo: contactRepo,
         bridge: bridge,
         getOwnMlKemSecretKey: () async => null,
       );

  final _EventRecorder recorder;
  final StreamController<ReactionChange> _changeController;

  @override
  Stream<ReactionChange> get incomingReactionChangeStream =>
      _changeController.stream;

  @override
  void start() {}

  @override
  void stop() {}

  void emitReactionChange(ReactionChange change, {required String phase}) {
    recorder.mark('reaction_change_emit', <String, dynamic>{
      'phase': phase,
      'messageId': change.messageId,
      'type': change.type.name,
    });
    _changeController.add(change);
  }

  Future<void> disposeTracked() async {
    await _changeController.close();
  }
}

class _TrackingAudioRecorderService implements AudioRecorderService {
  _TrackingAudioRecorderService(this.recorder)
    : _durationController = StreamController<Duration>.broadcast(
        onListen: () => recorder.mark('duration_listener_attached'),
        onCancel: () => recorder.mark('duration_listener_detached'),
      ),
      _amplitudeController = StreamController<double>.broadcast(
        onListen: () => recorder.mark('amplitude_listener_attached'),
        onCancel: () => recorder.mark('amplitude_listener_detached'),
      );

  final _EventRecorder recorder;
  final StreamController<Duration> _durationController;
  final StreamController<double> _amplitudeController;

  bool _isRecording = false;

  @override
  bool get isRecording => _isRecording;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start({required String outputPath}) async {
    recorder.mark('recording_start_called', <String, dynamic>{
      'outputPath': outputPath.split('/').last,
    });
    _isRecording = true;
  }

  @override
  Future<AudioRecording?> stop() async {
    recorder.mark('recording_stop_called');
    if (!_isRecording) {
      return null;
    }
    _isRecording = false;
    return null;
  }

  @override
  Future<void> cancel() async {
    recorder.mark('recording_cancel_called');
    _isRecording = false;
  }

  void emitDurationTick(Duration duration, {required String phase}) {
    recorder.mark('duration_tick_emit', <String, dynamic>{
      'phase': phase,
      'durationMs': duration.inMilliseconds,
    });
    _durationController.add(duration);
  }

  void emitAmplitudeTick(double value, {required String phase}) {
    recorder.mark('amplitude_tick_emit', <String, dynamic>{
      'phase': phase,
      'value': double.parse(value.toStringAsFixed(3)),
    });
    _amplitudeController.add(value);
  }

  @override
  Future<void> dispose() async {
    await _durationController.close();
    await _amplitudeController.close();
  }
}

class _ConversationHarnessEnvironment {
  _ConversationHarnessEnvironment({
    required this.recorder,
    required this.identity,
    required this.primaryContact,
    required this.secondaryContact,
    required this.identityRepo,
    required this.contactRepo,
    required this.messageRepo,
    required this.bridge,
    required this.p2pService,
    required this.chatListener,
    required this.reactionRepo,
    required this.reactionListener,
    required this.audioRecorderService,
    required this.seededIncomingMessage,
    required this.seededOutgoingMessage,
  });

  final _EventRecorder recorder;
  final IdentityModel identity;
  final ContactModel primaryContact;
  final ContactModel secondaryContact;
  final _TrackingIdentityRepository identityRepo;
  final FakeContactRepository contactRepo;
  final _TrackingMessageRepository messageRepo;
  final FakeBridge bridge;
  final P2PService p2pService;
  final _TrackingChatMessageListener chatListener;
  final _TrackingReactionRepository reactionRepo;
  final _TrackingReactionListener reactionListener;
  final _TrackingAudioRecorderService audioRecorderService;
  final ConversationMessage seededIncomingMessage;
  final ConversationMessage seededOutgoingMessage;

  Widget buildConversation() {
    return ConversationWired(
      contact: primaryContact,
      identityRepo: identityRepo,
      messageRepo: messageRepo,
      chatMessageListener: chatListener,
      p2pService: p2pService,
      bridge: bridge,
      contactRepo: contactRepo,
      reactionRepo: reactionRepo,
      reactionListener: reactionListener,
      audioRecorderService: audioRecorderService,
    );
  }

  Future<void> dispose() async {
    await chatListener.disposeTracked();
    await reactionListener.disposeTracked();
    await messageRepo.disposeTracked();
    await audioRecorderService.dispose();
    bridge.dispose();
    p2pService.dispose();
  }
}

class _ConversationPerfHost extends StatefulWidget {
  const _ConversationPerfHost({super.key, required this.environment});

  final _ConversationHarnessEnvironment environment;

  @override
  State<_ConversationPerfHost> createState() => _ConversationPerfHostState();
}

class _ConversationPerfHostState extends State<_ConversationPerfHost> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  void openConversation() {
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => widget.environment.buildConversation(),
          settings: const RouteSettings(name: 'conversation-perf'),
        ),
      ),
    );
  }

  void pushCoverRoute() {
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Conversation Perf Cover')),
          ),
          settings: const RouteSettings(name: 'conversation-perf-cover'),
        ),
      ),
    );
  }

  void popTopRoute() {
    navigatorKey.currentState!.pop();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Center(child: Text('Conversation Perf Home'))),
    );
  }
}

Future<_ConversationHarnessEnvironment> _makeEnvironment() async {
  final recorder = _EventRecorder();
  final now = DateTime.utc(2026, 3, 26, 12, 0);
  final identity = IdentityModel(
    peerId: 'perf-self-peer',
    publicKey: 'perf-self-pk',
    privateKey: 'perf-self-sk',
    mnemonic12:
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    mlKemPublicKey: 'perf-self-mlkem-pk',
    mlKemSecretKey: 'perf-self-mlkem-sk',
    username: 'PerfSelf',
    createdAt: now.toIso8601String(),
    updatedAt: now.toIso8601String(),
  );
  final primaryContact = ContactModel(
    peerId: 'perf-contact-peer',
    publicKey: 'perf-contact-pk',
    rendezvous: '/dns4/example.com/tcp/443',
    username: 'PerfFriend',
    signature: 'sig-primary',
    scannedAt: now.toIso8601String(),
    mlKemPublicKey: 'perf-contact-mlkem-pk',
  );
  final secondaryContact = ContactModel(
    peerId: 'perf-other-peer',
    publicKey: 'perf-other-pk',
    rendezvous: '/dns4/example.com/tcp/444',
    username: 'OtherFriend',
    signature: 'sig-secondary',
    scannedAt: now.toIso8601String(),
  );
  final identityRepo = _TrackingIdentityRepository(
    recorder: recorder,
    seed: identity,
  );
  final contactRepo = FakeContactRepository()
    ..seed(<ContactModel>[primaryContact, secondaryContact]);
  final messageRepo = _TrackingMessageRepository(recorder);
  final seededIncomingMessage = ConversationMessage(
    id: 'perf-msg-incoming-1',
    contactPeerId: primaryContact.peerId,
    senderPeerId: primaryContact.peerId,
    text: 'Seed incoming 1',
    timestamp: now.subtract(const Duration(minutes: 4)).toIso8601String(),
    status: 'delivered',
    isIncoming: true,
    createdAt: now.subtract(const Duration(minutes: 4)).toIso8601String(),
  );
  final seededIncomingMessage2 = ConversationMessage(
    id: 'perf-msg-incoming-2',
    contactPeerId: primaryContact.peerId,
    senderPeerId: primaryContact.peerId,
    text: 'Seed incoming 2',
    timestamp: now.subtract(const Duration(minutes: 3)).toIso8601String(),
    status: 'delivered',
    isIncoming: true,
    createdAt: now.subtract(const Duration(minutes: 3)).toIso8601String(),
  );
  final seededOutgoingMessage = ConversationMessage(
    id: 'perf-msg-outgoing-1',
    contactPeerId: primaryContact.peerId,
    senderPeerId: identity.peerId,
    text: 'Seed outgoing',
    timestamp: now.subtract(const Duration(minutes: 2)).toIso8601String(),
    status: 'sent',
    isIncoming: false,
    createdAt: now.subtract(const Duration(minutes: 2)).toIso8601String(),
  );
  final seededOutgoingMessage2 = ConversationMessage(
    id: 'perf-msg-outgoing-2',
    contactPeerId: primaryContact.peerId,
    senderPeerId: identity.peerId,
    text: 'Seed outgoing 2',
    timestamp: now.subtract(const Duration(minutes: 1)).toIso8601String(),
    status: 'delivered',
    isIncoming: false,
    createdAt: now.subtract(const Duration(minutes: 1)).toIso8601String(),
  );
  messageRepo.seed(<ConversationMessage>[
    seededIncomingMessage,
    seededIncomingMessage2,
    seededOutgoingMessage,
    seededOutgoingMessage2,
  ]);
  final bridge = FakeBridge();
  final p2pService = FakeP2PService();
  final chatListener = _TrackingChatMessageListener(
    recorder: recorder,
    messageRepo: messageRepo,
    contactRepo: contactRepo,
  );
  final reactionRepo = _TrackingReactionRepository(recorder);
  final reactionListener = _TrackingReactionListener(
    recorder: recorder,
    reactionRepo: reactionRepo,
    contactRepo: contactRepo,
    bridge: bridge,
  );
  final audioRecorderService = _TrackingAudioRecorderService(recorder);

  return _ConversationHarnessEnvironment(
    recorder: recorder,
    identity: identity,
    primaryContact: primaryContact,
    secondaryContact: secondaryContact,
    identityRepo: identityRepo,
    contactRepo: contactRepo,
    messageRepo: messageRepo,
    bridge: bridge,
    p2pService: p2pService,
    chatListener: chatListener,
    reactionRepo: reactionRepo,
    reactionListener: reactionListener,
    audioRecorderService: audioRecorderService,
    seededIncomingMessage: seededIncomingMessage,
    seededOutgoingMessage: seededOutgoingMessage,
  );
}

Future<void> _pumpFrames(WidgetTester tester, {required int count}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frameStep);
  }
}

Future<void> _capturePhase(
  Map<String, dynamic> phaseSummaries,
  String phase,
  Future<void> Function() action,
) async {
  final collector = _FrameTimingCollector()..start();
  await action();
  phaseSummaries[phase] = await collector.stopAndReport();
}

Map<String, dynamic> _timelineSummary(Map<String, dynamic> timeline) {
  final events =
      (timeline['traceEvents'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
  final perfEvents = events
      .where((event) => event['name'] == 'conversation_perf_event')
      .toList(growable: false);
  final markerNames =
      perfEvents
          .map(
            (event) =>
                ((event['args'] as Map<dynamic, dynamic>?)?['name'] ?? '')
                    .toString(),
          )
          .toSet()
          .toList()
        ..sort();

  int countContains(String needle) =>
      events.where((event) => '${event['name'] ?? ''}'.contains(needle)).length;

  return <String, dynamic>{
    'eventCount': events.length,
    'conversationPerfMarkerCount': perfEvents.length,
    'distinctConversationPerfMarkers': markerNames,
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

ConversationMessage _makeIncomingMessage(
  _ConversationHarnessEnvironment env,
  String phase,
  int index,
) {
  final timestamp = DateTime.utc(2026, 3, 26, 13, 0, index)
      .add(Duration(minutes: phase == 'covered_route_stream_activity' ? 10 : 0))
      .toIso8601String();
  return ConversationMessage(
    id: 'perf-$phase-incoming-$index',
    contactPeerId: env.primaryContact.peerId,
    senderPeerId: env.primaryContact.peerId,
    text: 'Incoming $phase #$index',
    timestamp: timestamp,
    status: 'delivered',
    isIncoming: true,
    createdAt: timestamp,
  );
}

ConversationMessage _makeOutgoingChange(
  _ConversationHarnessEnvironment env,
  String phase,
  int index,
) {
  final status = index.isEven ? 'failed' : 'delivered';
  return env.seededOutgoingMessage.copyWith(
    status: status,
    text: 'Outgoing $phase #$index',
    timestamp: DateTime.utc(2026, 3, 26, 13, 30, index).toIso8601String(),
  );
}

MessageReaction _makeReaction(
  _ConversationHarnessEnvironment env,
  String phase,
  int index,
) {
  final emoji = index.isEven ? '👍' : '🔥';
  final timestamp = DateTime.utc(2026, 3, 26, 14, 0, index)
      .add(Duration(minutes: phase == 'covered_route_stream_activity' ? 10 : 0))
      .toIso8601String();
  return MessageReaction(
    id: 'reaction-$phase-$index',
    messageId: env.seededIncomingMessage.id,
    emoji: emoji,
    senderPeerId: env.primaryContact.peerId,
    timestamp: timestamp,
    createdAt: timestamp,
  );
}

Future<void> _emitConversationActivityBurst(
  WidgetTester tester,
  _ConversationHarnessEnvironment env, {
  required String phase,
}) async {
  for (var i = 0; i < _streamBurstIterations; i++) {
    await env.messageRepo.emitRepoChange(
      _makeOutgoingChange(env, phase, i),
      phase: phase,
    );
    await tester.pump(_frameStep);

    env.chatListener.emitTrackedContactUpdate(
      env.primaryContact.copyWith(username: 'PerfFriend $phase $i'),
      phase: phase,
    );
    await tester.pump(_frameStep);

    env.chatListener.emitIncomingMessage(
      _makeIncomingMessage(env, phase, i),
      phase: phase,
    );
    await tester.pump(_frameStep);

    env.reactionListener.emitReactionChange(
      ReactionChange.upsert(_makeReaction(env, phase, i)),
      phase: phase,
    );
    await tester.pump(_frameStep);
  }
}

Future<void> _runScenario(
  WidgetTester tester,
  _ConversationHarnessEnvironment env, {
  required bool collectPhaseFrames,
}) async {
  final hostFinder = find.byType(_ConversationPerfHost);
  final hostState = tester.state<_ConversationPerfHostState>(hostFinder);

  Future<void> phase(String name, Future<void> Function() action) async {
    if (!collectPhaseFrames) {
      await action();
      return;
    }
    final phaseSummaries =
        binding.reportData!['conversation_wired_phase_frame_summaries']
            as Map<String, dynamic>;
    await _capturePhase(phaseSummaries, name, action);
  }

  env.recorder.mark('host_ready');

  await phase('route_open_settle', () async {
    env.recorder.mark('route_open_start', <String, dynamic>{
      'phase': 'route_open_settle',
    });
    hostState.openConversation();
    await tester.pump();
    await _pumpFrames(tester, count: _openFrames);
    expect(find.byType(ConversationScreen), findsOneWidget);
    env.recorder.mark('conversation_route_visible', <String, dynamic>{
      'phase': 'route_open_settle',
    });
  });

  await phase('idle_visible', () async {
    env.recorder.mark('idle_visible_start', <String, dynamic>{
      'phase': 'idle_visible',
    });
    await _pumpFrames(tester, count: _idleFrames);
    env.recorder.mark('idle_visible_complete', <String, dynamic>{
      'phase': 'idle_visible',
    });
  });

  await phase('visible_stream_activity', () async {
    env.recorder.mark('visible_stream_activity_start', <String, dynamic>{
      'phase': 'visible_stream_activity',
    });
    await _emitConversationActivityBurst(
      tester,
      env,
      phase: 'visible_stream_activity',
    );
    env.recorder.mark('visible_stream_activity_complete', <String, dynamic>{
      'phase': 'visible_stream_activity',
    });
  });

  await phase('active_recording', () async {
    env.recorder.mark('active_recording_start', <String, dynamic>{
      'phase': 'active_recording',
    });
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);
    for (var i = 0; i < _recordingTickIterations; i++) {
      env.audioRecorderService.emitDurationTick(
        Duration(milliseconds: (i + 1) * 250),
        phase: 'active_recording',
      );
      env.audioRecorderService.emitAmplitudeTick(
        ((i % 5) + 1) / 5,
        phase: 'active_recording',
      );
      await tester.pump(_frameStep);
    }
    await gesture.up();
    await tester.pump();
    await _pumpFrames(tester, count: 6);
    env.recorder.mark('active_recording_complete', <String, dynamic>{
      'phase': 'active_recording',
    });
  });

  await phase('covered_route_stream_activity', () async {
    env.recorder.mark('cover_route_push_start', <String, dynamic>{
      'phase': 'covered_route_stream_activity',
    });
    hostState.pushCoverRoute();
    await tester.pump();
    await _pumpFrames(tester, count: _coverFrames);
    expect(find.text('Conversation Perf Cover'), findsOneWidget);
    expect(
      find.byType(ConversationScreen, skipOffstage: false),
      findsOneWidget,
    );
    env.recorder.mark('cover_route_visible', <String, dynamic>{
      'phase': 'covered_route_stream_activity',
    });
    await _emitConversationActivityBurst(
      tester,
      env,
      phase: 'covered_route_stream_activity',
    );
    env.recorder.mark(
      'covered_route_stream_activity_complete',
      <String, dynamic>{'phase': 'covered_route_stream_activity'},
    );
    hostState.popTopRoute();
    await tester.pump();
    await _pumpFrames(tester, count: _closeFrames);
    expect(find.byType(ConversationScreen), findsOneWidget);
    env.recorder.mark('cover_route_popped', <String, dynamic>{
      'phase': 'covered_route_stream_activity',
    });
  });

  env.recorder.mark('conversation_route_pop_start');
  hostState.popTopRoute();
  await tester.pump();
  await _pumpFrames(tester, count: _closeFrames);
  expect(find.text('Conversation Perf Home'), findsOneWidget);
  env.recorder.mark('conversation_route_closed');
}

Future<void> _captureEvidence(WidgetTester tester) async {
  Future<_ConversationHarnessEnvironment> prepareEnvironment() async {
    final env = await _makeEnvironment();
    env.recorder.reset();
    return env;
  }

  const perfKey = 'conversation_wired_overall_performance';
  const phaseFrameSummaryKey = 'conversation_wired_phase_frame_summaries';
  const eventSummaryKey = 'conversation_wired_event_summary';
  const eventLogKey = 'conversation_wired_event_log';
  const timelineKey = 'conversation_wired_timeline';
  const timelineSummaryKey = 'conversation_wired_timeline_summary';

  final perfEnv = await prepareEnvironment();
  binding.reportData ??= <String, dynamic>{};
  binding.reportData![phaseFrameSummaryKey] = <String, dynamic>{};

  await binding.watchPerformance(() async {
    perfEnv.recorder.start();
    await tester.pumpWidget(
      _ConversationPerfHost(
        key: const ValueKey('conversation-perf-host'),
        environment: perfEnv,
      ),
    );
    await _pumpFrames(tester, count: 8);
    expect(find.text('Conversation Perf Home'), findsOneWidget);
    await _runScenario(tester, perfEnv, collectPhaseFrames: true);
    perfEnv.recorder.stop();
  }, reportKey: perfKey);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  binding.reportData![eventSummaryKey] = perfEnv.recorder.summary();
  binding.reportData![eventLogKey] = perfEnv.recorder.events;
  _printReportEntry(perfKey);
  _printReportEntry(phaseFrameSummaryKey);
  _printReportEntry(eventSummaryKey);
  await perfEnv.dispose();

  final timelineEnv = await prepareEnvironment();
  await binding.traceAction(
    () async {
      timelineEnv.recorder.start();
      await tester.pumpWidget(
        _ConversationPerfHost(
          key: const ValueKey('conversation-perf-host-timeline'),
          environment: timelineEnv,
        ),
      );
      await _pumpFrames(tester, count: 8);
      await _runScenario(tester, timelineEnv, collectPhaseFrames: false);
      timelineEnv.recorder.stop();
    },
    reportKey: timelineKey,
    streams: const <String>['all'],
  );
  final timeline = binding.reportData![timelineKey] as Map<String, dynamic>;
  binding.reportData![timelineSummaryKey] = _timelineSummary(timeline);
  _printReportEntry(timelineSummaryKey);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await timelineEnv.dispose();
}

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures ConversationWired subscription performance evidence', (
    tester,
  ) async {
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['conversation_wired_perf_meta'] = <String, dynamic>{
      'frameStepMs': _frameStep.inMilliseconds,
      'openFrames': _openFrames,
      'idleFrames': _idleFrames,
      'coverFrames': _coverFrames,
      'closeFrames': _closeFrames,
      'streamBurstIterations': _streamBurstIterations,
      'recordingTickIterations': _recordingTickIterations,
      'productionCodeChanged': false,
      'backgroundForegroundMeasured': false,
      'backgroundForegroundReason':
          'ConversationWired has no WidgetsBindingObserver and this harness focuses on route-visible, recording, and covered-route cost.',
      'hiddenRouteMethod':
          'push opaque MaterialPageRoute over ConversationWired',
      'recorderExpectation':
          'duration/amplitude listeners should attach only while recording is active and detach on stop/cancel/dispose',
    };

    await _captureEvidence(tester);

    expect(binding.reportData, isNotNull);
  });
}
