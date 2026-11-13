import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
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

  Future<void> mount(WidgetTester tester) async {
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
          outgoingCallCapability: calls,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> menu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> cleanup(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets(
    'U6-entry passive video availability sends nothing and exposes exact action',
    (tester) async {
      try {
        await mount(tester);
        expect(calls.videoChecks, [_peer]);
        expect(calls.videoStarts, isEmpty);
        expect(calls.audioStarts, isEmpty);
        await menu(tester);
        expect(find.text('Video call'), findsOneWidget);
        await tester.tap(find.text('Video call'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(calls.videoStarts, [_peer]);
        expect(calls.audioStarts, isEmpty);
        expect(calls.videoChecks, [_peer, _peer]);
      } finally {
        await cleanup(tester);
      }
    },
  );

  for (final reason in ['gate', 'endpoint']) {
    testWidgets(
      'U6-entry unavailable $reason hides video and preserves audio',
      (tester) async {
        calls.videoGate = reason != 'gate';
        calls.videoContact = reason != 'endpoint';
        try {
          await mount(tester);
          await menu(tester);
          expect(find.text('Video call'), findsNothing);
          expect(find.byIcon(Icons.call_outlined), findsOneWidget);
          expect(calls.videoStarts, isEmpty);
          expect(calls.audioStarts, isEmpty);
        } finally {
          await cleanup(tester);
        }
      },
    );
  }

  testWidgets('U6-entry stale menu cannot bypass a withdrawn video gate', (
    tester,
  ) async {
    try {
      await mount(tester);
      await menu(tester);
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
      final pending = Completer<bool>();
      try {
        await mount(tester);
        final header = tester.widget<ConversationHeader>(
          find.byType(ConversationHeader),
        );
        await menu(tester);
        expect(find.text('Video call'), findsOneWidget);
        calls.nextVideoCheck = pending;
        await tester.tap(find.text('Video call'));
        await tester.pump(const Duration(milliseconds: 400));
      expect(find.byTooltip('Starting video call'), findsOneWidget);
        header.onCall!();
        await tester.pump();
        expect(calls.audioStarts, isEmpty);
        pending.complete(true);
        await tester.pump(const Duration(milliseconds: 500));
        expect(calls.videoStarts, [_peer]);
        expect(calls.audioStarts, isEmpty);
      } finally {
        if (!pending.isCompleted) pending.complete(false);
        await cleanup(tester);
      }
    },
  );

  testWidgets(
    'U6-entry explicit failed video start uses approved feedback without audio fallback',
    (tester) async {
      calls.result = OutgoingCallStartResult.failed;
      try {
        await mount(tester);
        await menu(tester);
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
