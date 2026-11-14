import 'package:flutter_app/features/call/application/call_recovery_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remaining recovery time retains its original monotonic origin', () {
    var elapsed = Duration.zero;
    final budget = CallRecoveryBudget(
      duration: const Duration(seconds: 15),
      monotonicNow: () => elapsed,
      isCurrent: () => true,
    );
    elapsed = const Duration(seconds: 13, milliseconds: 500);
    expect(budget.remaining, const Duration(milliseconds: 1500));
    elapsed = const Duration(seconds: 15);
    expect(budget.remaining, Duration.zero);
    elapsed = const Duration(seconds: 20);
    expect(budget.remaining, Duration.zero);
  });

  test('terminal or successor ownership immediately revokes a held budget', () {
    var current = true;
    final budget = CallRecoveryBudget(
      duration: const Duration(seconds: 15),
      monotonicNow: () => Duration.zero,
      isCurrent: () => current,
    );
    expect(budget.remaining, const Duration(seconds: 15));
    current = false;
    expect(budget.remaining, Duration.zero);
  });
}
