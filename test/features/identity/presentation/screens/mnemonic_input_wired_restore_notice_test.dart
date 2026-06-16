import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/presentation/screens/mnemonic_input_wired.dart';

import '../../../../shared/fakes/in_memory_group_repository.dart';

/// A4 (multi-device honesty): after a successful restore that hydrates NO local
/// groups, the user must see a one-time honest notice instead of a silent empty
/// group list. These tests drive the real restore success path end-to-end
/// through [MnemonicInputWired] and assert the SnackBar copy.
class _FakeIdentityRepo implements IdentityRepository {
  IdentityModel? savedIdentity;

  @override
  Future<IdentityModel?> loadIdentity() async => savedIdentity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    savedIdentity = identity;
  }
}

const _validMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

final _fakeIdentityResponse = <String, dynamic>{
  'ok': true,
  'identity': {
    'peerId': '12D3KooWTestRestore',
    'publicKey': 'publicKeyBase64',
    'privateKey': 'privateKeyBase64',
    'mnemonic12': _validMnemonic,
    'createdAt': '2024-01-01T00:00:00Z',
    'updatedAt': '2024-01-01T00:00:00Z',
  },
};

const _fakeMlKemResponse = <String, dynamic>{
  'ok': true,
  'publicKey': 'mlkemPub',
  'secretKey': 'mlkemSec',
};

GroupModel _group(String id) => GroupModel(
  id: id,
  name: 'Group $id',
  type: GroupType.chat,
  topicName: 'topic-$id',
  createdAt: DateTime.utc(2024, 1, 1),
  createdBy: 'peer-self',
  myRole: GroupRole.member,
);

void main() {
  Future<void> pumpAndRestore(
    WidgetTester tester, {
    required InMemoryGroupRepository? groupRepo,
    required bool navigated,
    required void Function() onNavigate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MnemonicInputWired(
          repository: _FakeIdentityRepo(),
          callIdentityRestore: (_) async => _fakeIdentityResponse,
          callMlKemKeygen: () async => _fakeMlKemResponse,
          onNavigateToMain: onNavigate,
          groupRepo: groupRepo,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), _validMnemonic);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the honest notice when restore hydrates zero groups', (
    tester,
  ) async {
    var navigated = false;
    await pumpAndRestore(
      tester,
      groupRepo: InMemoryGroupRepository(),
      navigated: navigated,
      onNavigate: () => navigated = true,
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.restore_groups_device_local_notice), findsOneWidget);
    expect(navigated, isTrue, reason: 'restore must still navigate to main');
  });

  testWidgets('does NOT show the notice when groups already exist locally', (
    tester,
  ) async {
    final repo = InMemoryGroupRepository();
    await repo.saveGroup(_group('g1'));

    var navigated = false;
    await pumpAndRestore(
      tester,
      groupRepo: repo,
      navigated: navigated,
      onNavigate: () => navigated = true,
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.restore_groups_device_local_notice), findsNothing);
    expect(navigated, isTrue);
  });

  testWidgets('no notice and no crash when groupRepo is absent (harness)', (
    tester,
  ) async {
    var navigated = false;
    await pumpAndRestore(
      tester,
      groupRepo: null,
      navigated: navigated,
      onNavigate: () => navigated = true,
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.restore_groups_device_local_notice), findsNothing);
    expect(navigated, isTrue);
  });
}
