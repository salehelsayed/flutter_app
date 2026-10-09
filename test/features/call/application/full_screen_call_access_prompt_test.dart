import 'package:flutter_app/features/call/application/full_screen_call_access_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

// O4 (beta 2026-10-08): ask for Android full-screen access only after a call
// rang without it, and again at most once a week.
void main() {
  final now = DateTime.utc(2026, 10, 8, 20);
  final call = now.subtract(const Duration(hours: 1));

  group('shouldShowFullScreenCallAccessPrompt', () {
    test('shows after a call rang without access', () {
      expect(
        shouldShowFullScreenCallAccessPrompt(
          FullScreenCallAccessState(
            supported: true,
            allowed: false,
            deniedCallAt: call,
          ),
          now,
        ),
        isTrue,
      );
    });

    test('never shows when unsupported, allowed, or no call was affected', () {
      for (final state in [
        FullScreenCallAccessState(
          supported: false,
          allowed: false,
          deniedCallAt: call,
        ),
        FullScreenCallAccessState(
          supported: true,
          allowed: true,
          deniedCallAt: call,
        ),
        const FullScreenCallAccessState(supported: true, allowed: false),
      ]) {
        expect(shouldShowFullScreenCallAccessPrompt(state, now), isFalse);
      }
    });

    test('Not now hides it for a week', () {
      FullScreenCallAccessState dismissed(Duration ago) =>
          FullScreenCallAccessState(
            supported: true,
            allowed: false,
            deniedCallAt: call,
            dismissedAt: now.subtract(ago),
          );
      expect(
        shouldShowFullScreenCallAccessPrompt(
          dismissed(const Duration(days: 6, hours: 23)),
          now,
        ),
        isFalse,
      );
      expect(
        shouldShowFullScreenCallAccessPrompt(
          dismissed(const Duration(days: 7)),
          now,
        ),
        isTrue,
      );
    });
  });

  test('fromMap reads the native channel payload', () {
    final state = FullScreenCallAccessState.fromMap({
      'supported': true,
      'allowed': false,
      'deniedCallAtMs': 1000,
      'dismissedAtMs': null,
    });
    expect(state.supported, isTrue);
    expect(state.allowed, isFalse);
    expect(
      state.deniedCallAt,
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    expect(state.dismissedAt, isNull);
  });

  test('a missing or malformed payload never shows the prompt', () {
    final state = FullScreenCallAccessState.fromMap({});
    expect(shouldShowFullScreenCallAccessPrompt(state, now), isFalse);
  });

  test('the platform gateway makes no channel call off Android', () async {
    const gateway = PlatformFullScreenCallAccessGateway(isAndroid: false);
    final state = await gateway.read();
    expect(state.supported, isFalse);
    expect(await gateway.openSettings(), isFalse);
  });

  test(
    'controller shows, dismisses, and hides once access is granted',
    () async {
      final gateway = FakeFullScreenCallAccessGateway(
        FullScreenCallAccessState(
          supported: true,
          allowed: false,
          deniedCallAt: call,
        ),
      );
      final controller = FullScreenCallAccessPromptController(
        gateway: gateway,
        clock: () => now,
      );
      await controller.refresh();
      expect(controller.value, isTrue);

      await controller.openSettings();
      expect(gateway.opened, 1);
      gateway.state = FullScreenCallAccessState(
        supported: true,
        allowed: true,
        deniedCallAt: call,
      );
      await controller.refresh();
      expect(controller.value, isFalse);

      gateway.state = FullScreenCallAccessState(
        supported: true,
        allowed: false,
        deniedCallAt: call,
      );
      await controller.refresh();
      await controller.dismiss();
      expect(controller.value, isFalse);
      expect(gateway.dismissed, 1);
      controller.dispose();
    },
  );
}

class FakeFullScreenCallAccessGateway implements FullScreenCallAccessGateway {
  FakeFullScreenCallAccessGateway(this.state);

  FullScreenCallAccessState state;
  int opened = 0;
  int dismissed = 0;

  @override
  Future<FullScreenCallAccessState> read() async => state;

  @override
  Future<bool> openSettings() async {
    opened++;
    return true;
  }

  @override
  Future<void> dismiss() async {
    dismissed++;
    final s = state;
    state = FullScreenCallAccessState(
      supported: s.supported,
      allowed: s.allowed,
      deniedCallAt: s.deniedCallAt,
      dismissedAt: DateTime.utc(2026, 10, 8, 20),
    );
  }
}
