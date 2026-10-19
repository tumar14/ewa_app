import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/models/draw_request.dart';
import 'package:ewa_app/models/fee_schedule.dart';
import 'package:ewa_app/utils/wage_calculator.dart';

DrawRequest _draw({
  required String id,
  required double amount,
  DrawStatus status = DrawStatus.pending,
}) =>
    DrawRequest(
      id: id,
      employeeId: 'e1',
      amount: amount,
      fee: amount * 0.05,
      total: amount * 1.05,
      createdAt: DateTime(2026, 1, 5),
      status: status,
    );

void main() {
  group('accruedWages', () {
    test('whole hours: rate * hours', () {
      expect(
        WageCalculator.accruedWages(hourlyRate: 15, hoursWorked: const Duration(hours: 9)),
        135.0,
      );
    });

    test('fractional hours via minutes (9h 30m = 9.5 h)', () {
      expect(
        WageCalculator.accruedWages(
          hourlyRate: 20,
          hoursWorked: const Duration(hours: 9, minutes: 30),
        ),
        190.0,
      );
    });

    test('zero hours → zero wages', () {
      expect(
        WageCalculator.accruedWages(hourlyRate: 50, hoursWorked: Duration.zero),
        0.0,
      );
    });
  });

  group('alreadyDrawn', () {
    test('empty list → 0', () {
      expect(WageCalculator.alreadyDrawn([]), 0.0);
    });

    test('only rejected draws → 0 (rejected not counted)', () {
      expect(
        WageCalculator.alreadyDrawn([_draw(id: '1', amount: 500, status: DrawStatus.rejected)]),
        0.0,
      );
    });

    test('pending draws count against the cap', () {
      expect(
        WageCalculator.alreadyDrawn([_draw(id: '1', amount: 200, status: DrawStatus.pending)]),
        200.0,
      );
    });

    test('approved draws count against the cap', () {
      expect(
        WageCalculator.alreadyDrawn([_draw(id: '1', amount: 300, status: DrawStatus.approved)]),
        300.0,
      );
    });

    test('sums pending + approved, ignores rejected', () {
      final draws = [
        _draw(id: '1', amount: 200, status: DrawStatus.approved),
        _draw(id: '2', amount: 150, status: DrawStatus.pending),
        _draw(id: '3', amount: 999, status: DrawStatus.rejected),
      ];
      expect(WageCalculator.alreadyDrawn(draws), 350.0);
    });
  });

  group('maxAdditionalDraw', () {
    test('no prior draws: cap = accrued * maxDrawPercent', () {
      expect(
        WageCalculator.maxAdditionalDraw(
          accrued: 1350,
          maxDrawPercent: 0.5,
          cycleDraws: [],
        ),
        675.0,
      );
    });

    test('subtracts non-rejected prior draws', () {
      final draws = [
        _draw(id: '1', amount: 300, status: DrawStatus.approved),
        _draw(id: '2', amount: 999, status: DrawStatus.rejected),
      ];
      expect(
        WageCalculator.maxAdditionalDraw(accrued: 1350, maxDrawPercent: 0.5, cycleDraws: draws),
        375.0,
      );
    });

    test('never returns negative even when drawn amount exceeds cap', () {
      final draws = [_draw(id: '1', amount: 700, status: DrawStatus.approved)];
      expect(
        WageCalculator.maxAdditionalDraw(accrued: 1350, maxDrawPercent: 0.5, cycleDraws: draws),
        0.0,
      );
    });

    test('zero accrued wages → zero available', () {
      expect(
        WageCalculator.maxAdditionalDraw(accrued: 0, maxDrawPercent: 0.5, cycleDraws: []),
        0.0,
      );
    });

    test('pending draws count the same as approved draws against the cap', () {
      final draws = [_draw(id: '1', amount: 400, status: DrawStatus.pending)];
      expect(
        WageCalculator.maxAdditionalDraw(accrued: 1000, maxDrawPercent: 0.5, cycleDraws: draws),
        100.0, // 500 cap - 400 pending
      );
    });
  });

  group('canRequestDraw', () {
    test('allows when no draws taken yet', () {
      expect(WageCalculator.canRequestDraw(cycleDraws: [], maxDrawsPerCycle: 2), isTrue);
    });

    test('blocks when non-rejected draws reach the limit', () {
      final draws = List.generate(
        2,
        (i) => _draw(id: '$i', amount: 100, status: DrawStatus.pending),
      );
      expect(WageCalculator.canRequestDraw(cycleDraws: draws, maxDrawsPerCycle: 2), isFalse);
    });

    test('rejected draws do not count toward the limit', () {
      final draws = [
        _draw(id: '1', amount: 100, status: DrawStatus.rejected),
        _draw(id: '2', amount: 100, status: DrawStatus.rejected),
        _draw(id: '3', amount: 100, status: DrawStatus.pending),
      ];
      // 2 rejected + 1 pending; limit = 2 → should still be allowed (only 1 non-rejected)
      expect(WageCalculator.canRequestDraw(cycleDraws: draws, maxDrawsPerCycle: 2), isTrue);
    });

    test('one slot left: still allowed', () {
      final draws = [_draw(id: '1', amount: 100, status: DrawStatus.approved)];
      expect(WageCalculator.canRequestDraw(cycleDraws: draws, maxDrawsPerCycle: 2), isTrue);
    });
  });

  group('fees', () {
    test('feeFor: amount * feePercent', () {
      expect(WageCalculator.feeFor(500, const FeeSchedule.percent(0.05)), 25.0);
    });

    test('totalOwed: amount + fee', () {
      expect(WageCalculator.totalOwed(500, const FeeSchedule.percent(0.05)), 525.0);
    });

    test('zero-fee draw: totalOwed equals amount', () {
      expect(WageCalculator.totalOwed(300, const FeeSchedule.percent(0)), 300.0);
    });

    test('zero amount: fee and total are both zero', () {
      expect(WageCalculator.feeFor(0, const FeeSchedule.percent(0.05)), 0.0);
      expect(WageCalculator.totalOwed(0, const FeeSchedule.percent(0.05)), 0.0);
    });
  });
}
