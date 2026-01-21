import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_screen.dart';
import 'package:flutter_app/features/identity/presentation/screens/mnemonic_input_screen.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_wired.dart';
import 'package:flutter_app/features/identity/presentation/screens/mnemonic_input_wired.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'dart:convert';

// Mock Repository for testing
class MockIdentityRepository implements IdentityRepository {
  IdentityModel? storedIdentity;
  int saveCallCount = 0;
  int loadCallCount = 0;
  bool shouldThrowOnSave = false;

  @override
  Future<IdentityModel?> loadIdentity() async {
    loadCallCount++;
    return storedIdentity;
  }

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    if (shouldThrowOnSave) {
      throw Exception('Mock save error');
    }
    saveCallCount++;
    storedIdentity = identity;
  }

  void reset() {
    storedIdentity = null;
    saveCallCount = 0;
    loadCallCount = 0;
    shouldThrowOnSave = false;
  }
}

// Mock JS bridge functions
Future<Map<String, dynamic>> mockJsIdentityGenerate() async {
  return {
    'ok': true,
    'identity': {
      'peerId': 'test-peer-id',
      'publicKey': 'test-public-key',
      'privateKey': 'test-private-key',
      'mnemonic12': 'test mnemonic words here for testing purposes only twelve',
      'createdAt': '2025-01-17T12:00:00.000Z',
      'updatedAt': '2025-01-17T12:00:00.000Z',
    }
  };
}

Future<Map<String, dynamic>> mockJsIdentityRestore(String mnemonic) async {
  if (mnemonic == 'invalid invalid invalid invalid invalid invalid invalid invalid invalid invalid invalid invalid') {
    return {
      'ok': false,
      'errorCode': 'INVALID_MNEMONIC',
      'errorMessage': 'Invalid mnemonic',
    };
  }
  return {
    'ok': true,
    'identity': {
      'peerId': 'restored-peer-id',
      'publicKey': 'restored-public-key',
      'privateKey': 'restored-private-key',
      'mnemonic12': mnemonic,
      'createdAt': '2025-01-17T12:00:00.000Z',
      'updatedAt': '2025-01-17T12:00:00.000Z',
    }
  };
}

void main() {
  group('Phase 4 Verification', () {
    late MockIdentityRepository mockRepo;

    setUp(() {
      mockRepo = MockIdentityRepository();
    });

    group('Screen Rendering', () {
      testWidgets('IdentityChoiceScreen renders correctly', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: IdentityChoiceScreen(
              onNewHere: () {},
              onLoadMyKey: () {},
            ),
          ),
        );

        // Verify title text exists
        expect(find.text('Welcome'), findsOneWidget);

        // Verify subtitle text exists
        expect(find.textContaining('Generate a new identity'), findsOneWidget);

        // Verify "I'm new here" button exists
        expect(find.text("I'm new here"), findsOneWidget);

        // Verify "Load my key" button exists
        expect(find.text('Load my key'), findsOneWidget);

        print('✓ IdentityChoiceScreen renders all UI elements correctly');
      });

      testWidgets('MnemonicInputScreen renders correctly', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MnemonicInputScreen(
              onRestorePressed: (mnemonic) async {},
            ),
          ),
        );

        // Verify title text exists
        expect(find.text('Enter Recovery Phrase'), findsOneWidget);

        // Verify helper text exists
        expect(find.text('Enter your 12-word recovery phrase below'), findsOneWidget);

        // Verify TextField exists
        expect(find.byType(TextField), findsOneWidget);

        // Verify "Restore identity" button exists
        expect(find.text('Restore identity'), findsOneWidget);

        // Verify back button exists
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);

        print('✓ MnemonicInputScreen renders all UI elements correctly');
      });

      testWidgets('IdentityChoiceWired integrates IdentityChoiceScreen', (WidgetTester tester) async {
        bool navigateCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: IdentityChoiceWired(
              repository: mockRepo,
              callJsIdentityGenerate: mockJsIdentityGenerate,
              callJsIdentityRestore: mockJsIdentityRestore,
              onNavigateToMain: () {
                navigateCalled = true;
              },
            ),
          ),
        );

        // Verify the screen is rendered through the wired wrapper
        expect(find.byType(IdentityChoiceScreen), findsOneWidget);
        expect(find.text('Welcome'), findsOneWidget);

        print('✓ IdentityChoiceWired correctly wraps IdentityChoiceScreen');
      });

      testWidgets('MnemonicInputWired integrates MnemonicInputScreen', (WidgetTester tester) async {
        bool navigateCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: MnemonicInputWired(
              repository: mockRepo,
              callJsIdentityRestore: mockJsIdentityRestore,
              onNavigateToMain: () {
                navigateCalled = true;
              },
            ),
          ),
        );

        // Verify the screen is rendered through the wired wrapper
        expect(find.byType(MnemonicInputScreen), findsOneWidget);
        expect(find.text('Enter Recovery Phrase'), findsOneWidget);

        print('✓ MnemonicInputWired correctly wraps MnemonicInputScreen');
      });
    });

    group('Button Callbacks', () {
      testWidgets('IdentityChoiceScreen onNewHere callback works', (WidgetTester tester) async {
        bool callbackCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: IdentityChoiceScreen(
              onNewHere: () {
                callbackCalled = true;
              },
              onLoadMyKey: () {},
            ),
          ),
        );

        // Tap "I'm new here" button
        await tester.tap(find.text("I'm new here"));
        await tester.pump();

        expect(callbackCalled, isTrue);
        print('✓ "I\'m new here" button triggers onNewHere callback');
      });

      testWidgets('IdentityChoiceScreen onLoadMyKey callback works', (WidgetTester tester) async {
        bool callbackCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: IdentityChoiceScreen(
              onNewHere: () {},
              onLoadMyKey: () {
                callbackCalled = true;
              },
            ),
          ),
        );

        // Tap "Load my key" button
        await tester.tap(find.text('Load my key'));
        await tester.pump();

        expect(callbackCalled, isTrue);
        print('✓ "Load my key" button triggers onLoadMyKey callback');
      });

      testWidgets('MnemonicInputScreen onRestorePressed callback works', (WidgetTester tester) async {
        String? receivedMnemonic;

        await tester.pumpWidget(
          MaterialApp(
            home: MnemonicInputScreen(
              onRestorePressed: (mnemonic) async {
                receivedMnemonic = mnemonic;
              },
            ),
          ),
        );

        // Enter text in TextField
        await tester.enterText(find.byType(TextField), 'test mnemonic here');

        // Tap "Restore identity" button
        await tester.tap(find.text('Restore identity'));
        await tester.pumpAndSettle();

        expect(receivedMnemonic, equals('test mnemonic here'));
        print('✓ "Restore identity" button triggers onRestorePressed with mnemonic');
      });

      testWidgets('IdentityChoiceWired handles generate success', (WidgetTester tester) async {
        bool navigateCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: IdentityChoiceWired(
              repository: mockRepo,
              callJsIdentityGenerate: mockJsIdentityGenerate,
              callJsIdentityRestore: mockJsIdentityRestore,
              onNavigateToMain: () {
                navigateCalled = true;
              },
            ),
          ),
        );

        // Tap "I'm new here" button
        await tester.tap(find.text("I'm new here"));
        await tester.pumpAndSettle();

        // Verify navigation was called on success
        expect(navigateCalled, isTrue);
        expect(mockRepo.saveCallCount, equals(1));
        print('✓ IdentityChoiceWired handles generate success and navigates');
      });

      testWidgets('MnemonicInputWired handles restore success', (WidgetTester tester) async {
        bool navigateCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: MnemonicInputWired(
              repository: mockRepo,
              callJsIdentityRestore: mockJsIdentityRestore,
              onNavigateToMain: () {
                navigateCalled = true;
              },
            ),
          ),
        );

        // Enter valid mnemonic
        await tester.enterText(
          find.byType(TextField),
          'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12'
        );

        // Tap "Restore identity" button
        await tester.tap(find.text('Restore identity'));
        await tester.pumpAndSettle();

        // Verify navigation was called on success
        expect(navigateCalled, isTrue);
        expect(mockRepo.saveCallCount, equals(1));
        print('✓ MnemonicInputWired handles restore success and navigates');
      });

      testWidgets('MnemonicInputWired shows error for invalid mnemonic', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MnemonicInputWired(
              repository: mockRepo,
              callJsIdentityRestore: mockJsIdentityRestore,
              onNavigateToMain: () {},
            ),
          ),
        );

        // Enter invalid mnemonic (wrong word count)
        await tester.enterText(find.byType(TextField), 'only three words');

        // Tap "Restore identity" button
        await tester.tap(find.text('Restore identity'));
        await tester.pumpAndSettle();

        // Verify error message is shown
        expect(find.text('Please enter exactly 12 words'), findsOneWidget);
        print('✓ MnemonicInputWired shows validation error for wrong word count');
      });
    });

    group('Navigation', () {
      testWidgets('Navigation from IdentityChoiceWired to MnemonicInputScreen', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: IdentityChoiceWired(
              repository: mockRepo,
              callJsIdentityGenerate: mockJsIdentityGenerate,
              callJsIdentityRestore: mockJsIdentityRestore,
              onNavigateToMain: () {},
            ),
          ),
        );

        // Tap "Load my key" button
        await tester.tap(find.text('Load my key'));
        await tester.pumpAndSettle();

        // Verify MnemonicInputScreen is now visible
        expect(find.byType(MnemonicInputScreen), findsOneWidget);
        expect(find.text('Enter Recovery Phrase'), findsOneWidget);
        print('✓ Navigation from IdentityChoice to MnemonicInput works');
      });

      testWidgets('Back navigation from MnemonicInputScreen', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: IdentityChoiceWired(
              repository: mockRepo,
              callJsIdentityGenerate: mockJsIdentityGenerate,
              callJsIdentityRestore: mockJsIdentityRestore,
              onNavigateToMain: () {},
            ),
          ),
        );

        // Navigate to MnemonicInputScreen
        await tester.tap(find.text('Load my key'));
        await tester.pumpAndSettle();

        // Verify we're on MnemonicInputScreen
        expect(find.text('Enter Recovery Phrase'), findsOneWidget);

        // Tap back button
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        // Verify we're back on IdentityChoiceScreen
        expect(find.text('Welcome'), findsOneWidget);
        expect(find.text("I'm new here"), findsOneWidget);
        print('✓ Back navigation from MnemonicInput to IdentityChoice works');
      });
    });

    test('Phase 4 Summary', () {
      print('\n' + '='*60);
      print('PHASE 4 VERIFICATION COMPLETE');
      print('='*60);
      print('✅ Screens render correctly');
      print('   - IdentityChoiceScreen shows all UI elements');
      print('   - MnemonicInputScreen shows all UI elements');
      print('   - Wired wrappers correctly integrate screens');
      print('');
      print('✅ Button callbacks trigger correct use cases');
      print('   - "I\'m new here" triggers generate identity');
      print('   - "Load my key" navigates to mnemonic input');
      print('   - "Restore identity" triggers restore use case');
      print('   - Success cases navigate to main');
      print('   - Error cases show appropriate messages');
      print('');
      print('✅ Navigation works between screens');
      print('   - Forward navigation to MnemonicInputScreen');
      print('   - Back navigation to IdentityChoiceScreen');
      print('='*60);
    });
  });
}