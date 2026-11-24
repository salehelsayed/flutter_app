import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/app/bootstrap/call_signaling_composition.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';
import '../../domain/repositories/fake_message_repository.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_mic_permission_gateway.dart';

const _peer = 'video-entry-contact';

final class _Calls implements OutgoingVideoCallCapability {
  bool videoGate = true;
  bool videoContact = true;
  OutgoingCallStartResult result = OutgoingCallStartResult.started;
  Completer<bool>? nextVideoCheck;
  final audioStarts = <String>[];
  final videoStarts = <String>[];
  final videoChecks = <String>[];
  final changes = StreamController<bool>.broadcast(sync: true);

  @override
  bool get isOutgoingCallAvailable => true;
  @override
  bool get isOutgoingVideoCallAvailable => videoGate;
  @override
  Stream<bool> get outgoingCallAvailabilityChanges => changes.stream;
  @override
  Future<bool> isOutgoingCallAvailableFor(String peer) async => true;
  @override
  Future<bool> isOutgoingVideoCallAvailableFor(String peer) async {
    videoChecks.add(peer);
    final pending = nextVideoCheck;
    nextVideoCheck = null;
    return pending?.future ?? videoContact;
  }

  @override
  Future<OutgoingCallStartResult> startOutgoingCall(
    String peer, {
    OutgoingCallStartRequest? request,
  }) async {
    audioStarts.add(peer);
    return result;
  }

  @override
  Future<OutgoingCallStartResult> startOutgoingVideoCall(
    String peer, {
    OutgoingCallStartRequest? request,
  }) async {
    request?.checkPending();
    videoStarts.add(peer);
    return result;
  }
}

final class _PermissionTestGraph
    implements CallSignalingGraphLifecycle, CallSignalingVideoAdmission {
  final starts = <(String, CallMediaKind)>[];

  @override
  Future<bool> start() async => true;
  @override
  Future<void> onResume() async {}
  @override
  Future<bool> advertiseCapability() async => true;
  @override
  Future<void> shutdown() async {}
  @override
  Future<bool> isOutgoingCallAvailableFor(String peer) async => true;
  @override
  Future<bool> isOutgoingVideoCallAvailableFor(String peer) async => true;

  @override
  Future<OutgoingCallStartResult> startOutgoingCall(
    String peer, {
    OutgoingCallStartRequest? request,
  }) async {
    request?.admit();
    starts.add((peer, CallMediaKind.audio));
    return OutgoingCallStartResult.started;
  }

  @override
  Future<OutgoingCallStartResult> startOutgoingVideoCall(
    String peer, {
    OutgoingCallStartRequest? request,
  }) async {
    request?.admit();
    starts.add((peer, CallMediaKind.video));
    return OutgoingCallStartResult.started;
  }
}

enum _MicrophonePrompt {
  grantVoice,
  grantVideo,
  deny,
  background,
  alreadyGranted,
}

void main() {
  late Directory avatars;
  late _Calls calls;
  late FakeP2PService transport;

  setUp(() {
    avatars = Directory.systemTemp.createTempSync('u6-entry-');
    UserAvatar.setDocumentsDir(avatars.path);
    calls = _Calls();
    transport = FakeP2PService();
  });
  tearDown(() async {
    await calls.changes.close();
    transport.dispose();
    avatars.deleteSync(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester, {
    OutgoingCallCapability? capability,
    MicPermissionGateway micPermissionGateway =
        const PermissionHandlerMicGateway(),
  }) async {
    final contact = ContactModel(
      peerId: _peer,
      publicKey: 'key',
      rendezvous: '/relay',
      username: 'Alice',
      signature: 'signature',
      scannedAt: '2026-11-13T00:00:00Z',
      mlKemPublicKey: 'received-key',
    );
    final contacts = FakeContactRepository()..seed([contact]);
    final messages = FakeMessageRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationWired(
          contact: contact,
          contactRepo: contacts,
          identityRepo: FakeIdentityRepository(),
          messageRepo: messages,
          chatMessageListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messages,
            contactRepo: contacts,
          ),
          p2pService: transport,
          outgoingCallCapability: capability ?? calls,
          micPermissionGateway: micPermissionGateway,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> menu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> chooser(WidgetTester tester) async {
    const bound = Duration(seconds: 3);
    await tester.tap(find.byIcon(Icons.call_outlined)).timeout(bound);
    await tester.pump().timeout(bound);
    await tester.pump(const Duration(milliseconds: 400)).timeout(bound);
  }

  Future<void> cleanup(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  for (final scenario in _MicrophonePrompt.values) {
    testWidgets('first chat call microphone prompt ${scenario.name}', (
      tester,
    ) async {
      const bound = Duration(seconds: 3);
      final video = scenario == _MicrophonePrompt.grantVideo;
      final permission = Completer<MicPermissionStatus>();
      final permissionGateway = FakeMicPermissionGateway()
        ..currentStatus = scenario == _MicrophonePrompt.alreadyGranted
            ? MicPermissionStatus.granted
            : MicPermissionStatus.denied;
      var permissionRequests = 0;
      final graph = _PermissionTestGraph();
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final composition = CallSignalingComposition(
        featureFlags: {
          'voice_call_capability_v1': true,
          'voice_call_outgoing_enabled': true,
          'voice_call_incoming_enabled': true,
          'voice_call_turn_enabled': true,
          'video_call_v2_enabled': video,
        },
        platform: CallEndpointPlatform.android,
        awaitReadiness: () async {},
        buildGraph: () async => graph,
        requestOutgoingMicrophonePermission: () {
          permissionRequests++;
          return permission.future.timeout(bound);
        },
        isForeground: () => binding.lifecycleState == AppLifecycleState.resumed,
      );
      try {
        await composition.start().timeout(bound);
        await mount(
          tester,
          capability: composition,
          micPermissionGateway: permissionGateway,
        ).timeout(bound);
        await chooser(tester).timeout(bound);
        if (video) {
          await tester.tap(find.text('Video call')).timeout(bound);
          await tester.pump().timeout(bound);
          await tester.pump(const Duration(milliseconds: 400)).timeout(bound);
        }
        expect(permissionRequests, 1);
        expect(graph.starts, isEmpty);

        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        if (scenario == _MicrophonePrompt.background) {
          binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        }
        permission.complete(
          scenario == _MicrophonePrompt.deny
              ? MicPermissionStatus.denied
              : MicPermissionStatus.granted,
        );
        await tester.pump().timeout(bound);
        expect(graph.starts, isEmpty, reason: 'No call while inactive');

        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump().timeout(bound);
        expect(permissionRequests, 1);
        expect(graph.starts, switch (scenario) {
          _MicrophonePrompt.grantVoice => [(_peer, CallMediaKind.audio)],
          _MicrophonePrompt.grantVideo => [(_peer, CallMediaKind.video)],
          _MicrophonePrompt.deny ||
          _MicrophonePrompt.background ||
          _MicrophonePrompt.alreadyGranted => isEmpty,
        });
      } finally {
        if (!permission.isCompleted) {
          permission.complete(MicPermissionStatus.denied);
        }
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await cleanup(tester).timeout(bound);
        await composition.shutdown().timeout(bound);
      }
    });
  }

  testWidgets(
    'eligible conversation call button offers audio and video without starting either',
    (tester) async {
      const bound = Duration(seconds: 3);
      try {
        await mount(tester).timeout(bound);
        await tester.tap(find.byIcon(Icons.call_outlined)).timeout(bound);
        await tester.pump().timeout(bound);
        await tester.pump(const Duration(milliseconds: 400)).timeout(bound);

        expect(
          calls.audioStarts,
          isEmpty,
          reason: 'Tapping the call button must wait for a call type selection',
        );
        expect(calls.videoStarts, isEmpty);
        expect(find.text('Voice call'), findsOneWidget);
        expect(find.text('Video call'), findsOneWidget);
      } finally {
        await cleanup(tester).timeout(bound);
      }
    },
  );

  testWidgets(
    'conversation tap waits for pending video eligibility before offering the chooser',
    (tester) async {
      const bound = Duration(seconds: 3);
      final videoEligibility = Completer<bool>();
      final refreshedVideoEligibility = Completer<bool>();
      calls.nextVideoCheck = videoEligibility;
      try {
        await mount(tester).timeout(bound);
        expect(calls.videoChecks, [_peer]);
        await chooser(tester).timeout(bound);
        expect(
          calls.audioStarts,
          isEmpty,
          reason: 'Pending video eligibility must not start an audio call',
        );
        expect(calls.videoStarts, isEmpty);
        expect(find.text('Video call'), findsNothing);

        videoEligibility.complete(true);
        await tester.pump().timeout(bound);
        await tester.pump(const Duration(milliseconds: 400)).timeout(bound);
        expect(find.text('Voice call'), findsOneWidget);
        expect(find.text('Video call'), findsOneWidget);
        expect(calls.audioStarts, isEmpty);
        expect(calls.videoStarts, isEmpty);

        await tester.binding.handlePopRoute().timeout(bound);
        await tester.pump().timeout(bound);
        await tester.pump(const Duration(milliseconds: 400)).timeout(bound);
        calls.videoContact = false;
        calls.changes.add(true);
        await tester.pump().timeout(bound);
        expect(find.byTooltip('Start voice call'), findsOneWidget);

        calls.videoContact = true;
        calls.nextVideoCheck = refreshedVideoEligibility;
        calls.changes.add(true);
        await tester.pump().timeout(bound);
        expect(calls.videoChecks, [_peer, _peer, _peer]);
        await chooser(tester).timeout(bound);
        expect(
          calls.audioStarts,
          isEmpty,
          reason: 'A readiness event invalidates the previous video result',
        );
        expect(calls.videoStarts, isEmpty);
        expect(find.text('Video call'), findsNothing);
        refreshedVideoEligibility.complete(true);
        await tester.pump().timeout(bound);
        await tester.pump(const Duration(milliseconds: 400)).timeout(bound);
        expect(find.text('Voice call'), findsOneWidget);
        expect(find.text('Video call'), findsOneWidget);

        await tester.tap(find.text('Video call')).timeout(bound);
        await tester.pump(const Duration(milliseconds: 500)).timeout(bound);
        expect(calls.audioStarts, isEmpty);
        expect(calls.videoStarts, [_peer]);
      } finally {
        if (!videoEligibility.isCompleted) videoEligibility.complete(false);
        if (!refreshedVideoEligibility.isCompleted) {
          refreshedVideoEligibility.complete(false);
        }
        await cleanup(tester).timeout(bound);
      }
    },
  );

  testWidgets(
    'U6-entry passive availability lets the header start video once',
    (tester) async {
      const bound = Duration(seconds: 3);
      try {
        await mount(tester);
        expect(calls.videoChecks, [_peer]);
        expect(calls.videoStarts, isEmpty);
        expect(calls.audioStarts, isEmpty);
        expect(find.byTooltip('Voice call / Video call'), findsOneWidget);
        await chooser(tester).timeout(bound);
        expect(find.text('Video call'), findsOneWidget);
        await tester.tap(find.text('Video call')).timeout(bound);
        await tester.pump(const Duration(milliseconds: 500)).timeout(bound);
        expect(calls.videoStarts, [_peer]);
        expect(calls.audioStarts, isEmpty);
        expect(calls.videoChecks, [_peer, _peer]);
        await menu(tester).timeout(bound);
        expect(find.text('Video call'), findsNothing);
      } finally {
        await cleanup(tester);
      }
    },
  );

  testWidgets('dismissed choice does nothing and Voice call starts audio', (
    tester,
  ) async {
    const bound = Duration(seconds: 3);
    try {
      await mount(tester).timeout(bound);
      await chooser(tester).timeout(bound);
      await tester.binding.handlePopRoute().timeout(bound);
      await tester.pump().timeout(bound);
      await tester.pump(const Duration(milliseconds: 400)).timeout(bound);
      expect(find.text('Video call'), findsNothing);
      expect(calls.audioStarts, isEmpty);
      expect(calls.videoStarts, isEmpty);

      await chooser(tester).timeout(bound);
      await tester.tap(find.text('Voice call')).timeout(bound);
      await tester.pump(const Duration(milliseconds: 500)).timeout(bound);
      expect(calls.audioStarts, [_peer]);
      expect(calls.videoStarts, isEmpty);
    } finally {
      await cleanup(tester).timeout(bound);
    }
  });

  for (final reason in ['gate', 'endpoint']) {
    testWidgets(
      'U6-entry unavailable $reason keeps the header a direct audio action',
      (tester) async {
        const bound = Duration(seconds: 3);
        calls.videoGate = reason != 'gate';
        calls.videoContact = reason != 'endpoint';
        try {
          await mount(tester);
          expect(calls.videoStarts, isEmpty);
          expect(calls.audioStarts, isEmpty);
          expect(find.byTooltip('Start voice call'), findsOneWidget);
          await chooser(tester).timeout(bound);
          expect(find.text('Voice call'), findsNothing);
          expect(find.text('Video call'), findsNothing);
          expect(calls.audioStarts, [_peer]);
          expect(calls.videoStarts, isEmpty);
        } finally {
          await cleanup(tester);
        }
      },
    );
  }

  testWidgets('U6-entry stale choice cannot bypass a withdrawn video gate', (
    tester,
  ) async {
    try {
      await mount(tester);
      await chooser(tester);
      expect(find.text('Video call'), findsOneWidget);
      calls.videoGate = false;
      await tester.tap(find.text('Video call'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls.videoStarts, isEmpty);
      expect(calls.audioStarts, isEmpty);
      expect(
        find.text('Video calling is unavailable right now.'),
        findsOneWidget,
      );
    } finally {
      await cleanup(tester);
    }
  });

  testWidgets(
    'U6-entry shared preflight blocks a retained audio action during video check',
    (tester) async {
      const bound = Duration(seconds: 3);
      final pending = Completer<bool>();
      try {
        await mount(tester).timeout(bound);
        final header = tester.widget<ConversationHeader>(
          find.byType(ConversationHeader),
        );
        await chooser(tester).timeout(bound);
        expect(find.text('Video call'), findsOneWidget);
        calls.nextVideoCheck = pending;
        await tester.tap(find.text('Video call')).timeout(bound);
        await tester.pump().timeout(bound);
        await tester.pump(const Duration(milliseconds: 400)).timeout(bound);
        expect(find.byType(SimpleDialog), findsNothing);
        expect(find.byTooltip('Starting video call'), findsOneWidget);
        header.onCall!();
        await tester.pump().timeout(bound);
        await tester.pump(const Duration(milliseconds: 400)).timeout(bound);
        expect(calls.audioStarts, isEmpty);
        expect(find.text('Voice call'), findsNothing);
        pending.complete(true);
        await tester.pump(const Duration(milliseconds: 500)).timeout(bound);
        expect(calls.videoStarts, [_peer]);
        expect(calls.audioStarts, isEmpty);
      } finally {
        if (!pending.isCompleted) pending.complete(false);
        await cleanup(tester).timeout(bound);
      }
    },
  );

  testWidgets(
    'U6-entry explicit failed video start uses approved feedback without audio fallback',
    (tester) async {
      calls.result = OutgoingCallStartResult.failed;
      try {
        await mount(tester);
        await chooser(tester);
        expect(find.text('Video call'), findsOneWidget);
        await tester.tap(find.text('Video call'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(calls.videoStarts, [_peer]);
        expect(calls.audioStarts, isEmpty);
        expect(
          find.text("Couldn't start the video call. Please try again."),
          findsOneWidget,
        );
      } finally {
        await cleanup(tester);
      }
    },
  );

  testWidgets(
    'U6-entry background availability failure never displays start-failed feedback',
    (tester) async {
      try {
        await mount(tester);
        calls.videoGate = false;
        calls.changes.add(false);
        await tester.pump();
        expect(calls.videoStarts, isEmpty);
        expect(
          find.text("Couldn't start the video call. Please try again."),
          findsNothing,
        );
      } finally {
        await cleanup(tester);
      }
    },
  );
}
