import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/presentation/widgets/pending_group_invite_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

// TC-07 (plan 150): the new `PendingGroupInviteCard` outcome param renders the
// KEPT-invite row states inline.
//
// LOCKED CONTRACT (must compile against these EXACT names once production lands):
//   enum PendingInviteRowState { idle, processing, waitingForKey, retryable }
//   PendingInviteRowState rowState = PendingInviteRowState.idle   // new, DEFAULTED
//   VoidCallback? onRetry                                          // new, DEFAULTED null
//   ValueKey('pending-group-invite-retry-<groupId>')              // inline Retry control
//
// This file is EXPECTED to compile-FAIL on HEAD (the enum / `rowState` / `onRetry`
// params do not exist yet). That compile failure IS the documented RED for TC-07.

PendingGroupInvite makeInvite({
  String groupId = 'grp-card',
  String groupName = 'Book Club',
}) {
  final now = DateTime.now().toUtc();
  final createdAt = now.subtract(const Duration(hours: 6));
  final inviteTimestamp = createdAt.add(const Duration(minutes: 5));
  final Map<String, dynamic> groupConfig = {
    'name': groupName,
    'groupType': 'chat',
    'description': 'Invite description',
    'members': [
      {
        'peerId': '12D3KooWAlice',
        'username': 'Alice',
        'role': 'admin',
        'publicKey': 'alicePubKey64',
        'mlKemPublicKey': 'aliceMlKem64',
      },
    ],
    'createdBy': '12D3KooWAlice',
    'createdAt': createdAt.toIso8601String(),
  };
  final payload = GroupInvitePayload(
    id: 'invite-$groupId',
    groupId: groupId,
    groupKey: 'base64-key',
    keyEpoch: 1,
    groupConfig: groupConfig,
    senderPeerId: '12D3KooWAlice',
    senderUsername: 'Alice',
    timestamp: inviteTimestamp.toIso8601String(),
    invitePolicy: GroupInvitePolicy(
      expiresAt: now.add(pendingGroupInviteTtl),
      allowedDevices: const ['12D3KooWAlice'],
      assignedRole: 'writer',
      canInviteOthers: false,
      joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
      keyEpoch: 1,
    ),
  ).withInviteSignature(signature: 'signed-invite-by-alice');
  return PendingGroupInvite.fromPayload(payload, receivedAt: now);
}

void main() {
  group('PendingGroupInviteCard', () {
    final invite = makeInvite();
    final acceptKey = ValueKey('pending-group-invite-accept-${invite.groupId}');
    final declineKey = ValueKey(
      'pending-group-invite-decline-${invite.groupId}',
    );
    final containerKey = ValueKey('pending-group-invite-${invite.groupId}');
    final retryKey = ValueKey('pending-group-invite-retry-${invite.groupId}');

    Widget wrap(Widget child) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );
    }

    testWidgets('idle renders accept + decline buttons, no outcome controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          PendingGroupInviteCard(
            invite: invite,
            isProcessing: false,
            onAccept: () {},
            onDecline: () {},
            rowState: PendingInviteRowState.idle,
          ),
        ),
      );

      expect(find.byKey(containerKey), findsOneWidget);
      expect(find.byKey(acceptKey), findsOneWidget);
      expect(find.byKey(declineKey), findsOneWidget);
      expect(find.byKey(retryKey), findsNothing);
      expect(find.text('Waiting for key'), findsNothing);
      // Idle is the default-enabled state: accept is tappable.
      expect(tester.widget<FilledButton>(find.byKey(acceptKey)).onPressed,
          isNotNull);
    });

    testWidgets(
      'processing (isProcessing:true) shows the in-button spinner (preserved)',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            PendingGroupInviteCard(
              invite: invite,
              isProcessing: true,
              onAccept: () {},
              onDecline: () {},
              rowState: PendingInviteRowState.processing,
            ),
          ),
        );

        // The byte-for-byte legacy behavior: the in-button spinner is inside the
        // accept button and driven by the existing `isProcessing` bool.
        final spinner = find.descendant(
          of: find.byKey(acceptKey),
          matching: find.byType(CircularProgressIndicator),
        );
        expect(spinner, findsOneWidget);
        // While processing the accept button is disabled.
        expect(tester.widget<FilledButton>(find.byKey(acceptKey)).onPressed,
            isNull);
      },
    );

    testWidgets(
      'waitingForKey shows a trailing spinner and the "Waiting for key" text',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            PendingGroupInviteCard(
              invite: invite,
              isProcessing: false,
              onAccept: () {},
              onDecline: () {},
              rowState: PendingInviteRowState.waitingForKey,
            ),
          ),
        );

        expect(
          find.descendant(
            of: find.byKey(containerKey),
            matching: find.text('Waiting for key'),
          ),
          findsOneWidget,
        );
        // A trailing progress spinner accompanies the waiting state.
        expect(
          find.descendant(
            of: find.byKey(containerKey),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        // The card is KEPT — no inline Retry in this state.
        expect(find.byKey(retryKey), findsNothing);
      },
    );

    testWidgets(
      'retryable renders an inline Retry control that fires onRetry on tap',
      (tester) async {
        var retryCount = 0;
        await tester.pumpWidget(
          wrap(
            PendingGroupInviteCard(
              invite: invite,
              isProcessing: false,
              onAccept: () {},
              onDecline: () {},
              rowState: PendingInviteRowState.retryable,
              onRetry: () => retryCount++,
            ),
          ),
        );

        final retryFinder = find.byKey(retryKey);
        expect(retryFinder, findsOneWidget);
        expect(
          find.descendant(of: find.byKey(containerKey), matching: retryFinder),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);

        await tester.tap(retryFinder);
        await tester.pump();
        expect(retryCount, 1);
      },
    );

    testWidgets(
      'Orbit default: no rowState / onRetry passed → today\'s accept/decline '
      'buttons, no outcome controls',
      (tester) async {
        // orbit_screen.dart constructs the card WITHOUT the new params; the
        // defaults (idle / null onRetry) must preserve the legacy render.
        await tester.pumpWidget(
          wrap(
            PendingGroupInviteCard(
              invite: invite,
              isProcessing: false,
              onAccept: () {},
              onDecline: () {},
            ),
          ),
        );

        expect(find.byKey(containerKey), findsOneWidget);
        expect(find.byKey(acceptKey), findsOneWidget);
        expect(find.byKey(declineKey), findsOneWidget);
        expect(find.byKey(retryKey), findsNothing);
        expect(find.text('Waiting for key'), findsNothing);
      },
    );
  });
}
