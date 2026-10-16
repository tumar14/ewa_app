import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/models/draw_request.dart';
import 'package:ewa_app/models/payroll_run.dart';
import 'package:ewa_app/models/settlement.dart';
import 'package:ewa_app/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter minor units', () {
    test('parseMinor reads plain amounts into cents', () {
      expect(CurrencyFormatter.parseMinor('1234'), 123400);
      expect(CurrencyFormatter.parseMinor('1234.5'), 123450);
      expect(CurrencyFormatter.parseMinor('1234.50'), 123450);
      expect(CurrencyFormatter.parseMinor('0.05'), 5);
      expect(CurrencyFormatter.parseMinor(' 12.30 '), 1230);
    });

    test('parseMinor rejects anything else', () {
      for (final bad in ['', 'abc', '-5', '1,234', '1.234', '12.', '.5', '1e3', '1 2']) {
        expect(CurrencyFormatter.parseMinor(bad), isNull, reason: bad);
      }
    });

    test('parseMinor has no floating-point drift', () {
      expect(CurrencyFormatter.parseMinor('0.29'), 29);
      expect(CurrencyFormatter.parseMinor('1.15'), 115);
      expect(CurrencyFormatter.parseMinor('4.35'), 435);
    });

    test('toMinor and formatMinor round-trip', () {
      expect(CurrencyFormatter.toMinor(200), 20000);
      expect(CurrencyFormatter.toMinor(19.99), 1999);
      expect(CurrencyFormatter.formatMinor(123456), 'E 1,234.56');
    });
  });

  group('models read integer cents', () {
    test('DrawRequest', () {
      final draw = DrawRequest.fromMap('d1', {
        'employeeId': 'e1',
        'amountMinor': 10000,
        'feeMinor': 500,
        'totalMinor': 10500,
        'status': 'approved',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'payrollRunId': null,
      });
      expect(draw.amount, 100.0);
      expect(draw.fee, 5.0);
      expect(draw.total, 105.0);
      expect(draw.status, DrawStatus.approved);
    });

    test('PayrollRun lines include the shortfall, and legacy runs count as completed', () {
      final run = PayrollRun.fromMap('r1', {
        'cycleStart': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'cycleEnd': Timestamp.fromDate(DateTime(2026, 10, 31)),
        'lines': [
          {
            'employeeId': 'e1',
            'accruedMinor': 15000,
            'drawsDeductedMinor': 20000,
            'netPayoutMinor': 0,
            'shortfallMinor': 5000,
          },
        ],
      });
      expect(run.isCompleted, isTrue);
      expect(run.lines.single.accruedTotal, 150.0);
      expect(run.lines.single.shortfall, 50.0);
      expect(run.lines.single.netPayout, 0.0);
    });

    test('Settlement', () {
      final s = Settlement.fromMap('s1', {
        'payrollRunId': 'r1',
        'reference': 'EWA-ABC123-20261031-K3F9',
        'currency': 'SZL',
        'status': 'PARTIALLY_SETTLED',
        'cycleStart': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'cycleEnd': Timestamp.fromDate(DateTime(2026, 10, 31)),
        'expectedMinor': 4250000,
        'confirmedMinor': 4200000,
        'receivedMinor': 2000000,
        'outstandingMinor': 2250000,
        'openExceptionCount': 1,
        'itemCount': 3,
      });
      expect(s.status, SettlementStatus.partiallySettled);
      expect(s.confirmedMinor, 4200000);
      expect(s.outstandingMinor, 2250000);
    });

    test('an unconfirmed settlement has no confirmed figure', () {
      final s = Settlement.fromMap('s2', {
        'status': 'DRAFT',
        'cycleStart': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'cycleEnd': Timestamp.fromDate(DateTime(2026, 10, 31)),
        'expectedMinor': 1000,
        'confirmedMinor': null,
      });
      expect(s.confirmedMinor, isNull);
      expect(s.status, SettlementStatus.draft);
    });
  });
}
