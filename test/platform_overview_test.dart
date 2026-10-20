import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/models/platform_overview.dart';
import 'package:ewa_app/screens/platform_admin/platform_overview_screen.dart';

Map<String, dynamic> _row(String id, String name, {String currency = 'SZL', bool active = true, int owed = 0, int open = 0, int pending = 0}) => {
      'companyId': id,
      'name': name,
      'shortCode': name.substring(0, 3).toUpperCase(),
      'currency': currency,
      'active': active,
      'employees': 12,
      'activeEmployees': 10,
      'activeWorkers': 8,
      'advancesThisCycle': 5,
      'pendingApproval': pending,
      'awaitingPayout': 1,
      'openSettlements': open,
      'owedMinor': owed,
    };

Map<String, dynamic> _payload() => {
      'generatedAtMs': DateTime(2026, 10, 20, 9, 30).millisecondsSinceEpoch,
      'truncated': false,
      'totals': {
        'companies': 2, 'activeCompanies': 1, 'activeEmployees': 14, 'activeWorkers': 11,
        'advancesThisCycle': 6, 'pendingApproval': 2, 'awaitingPayout': 3, 'openSettlements': 3,
      },
      'companies': [
        _row('a', 'Alpha Garments', owed: 1250000, open: 2, pending: 2),
        _row('b', 'Beta Textiles', currency: 'ZAR', active: false, owed: 5000, open: 1),
      ],
    };

void main() {
  group('PlatformOverview.fromMap', () {
    test('reads the server answer', () {
      final o = PlatformOverview.fromMap(_payload());
      expect(o.companies.length, 2);
      expect(o.totals.activeWorkers, 11);
      expect(o.companies.first.owedMinor, 1250000);
      expect(o.companies.last.active, isFalse);
      expect(o.truncated, isFalse);
    });

    test('missing or odd values become zeros rather than crashing', () {
      final o = PlatformOverview.fromMap({'companies': [{'name': 'X', 'employees': '7'}]});
      expect(o.companies.single.employees, 0);
      expect(o.companies.single.active, isTrue);
      expect(o.totals.companies, 0);
    });

    test('money is shown in the company\'s own currency', () {
      final o = PlatformOverview.fromMap(_payload());
      expect(o.companies.first.owedDisplay, 'E 12,500.00');
      expect(o.companies.last.owedDisplay, 'ZAR 50.00');
    });
  });

  group('overview screen', () {
    Future<void> open(WidgetTester tester, Future<PlatformOverview> Function() load) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [platformOverviewProvider.overrideWith((ref) => load())],
        child: const MaterialApp(home: PlatformOverviewScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows totals and one card per company', (tester) async {
      await open(tester, () async => PlatformOverview.fromMap(_payload()));
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('Alpha Garments'), findsOneWidget);
      expect(find.text('Beta Textiles'), findsOneWidget);
      expect(find.text('Suspended'), findsOneWidget);
      expect(find.text('E 12,500.00'), findsOneWidget);
      expect(find.text('ZAR 50.00'), findsOneWidget);
      expect(find.textContaining('no names or individual amounts'), findsOneWidget);
    });

    testWidgets('says when there are no companies', (tester) async {
      await open(tester, () async => PlatformOverview.fromMap({'companies': [], 'totals': {}}));
      expect(find.text('No companies yet.'), findsOneWidget);
    });

    testWidgets('says when the list was cut short', (tester) async {
      final data = _payload()..['truncated'] = true;
      await open(tester, () async => PlatformOverview.fromMap(data));
      expect(find.textContaining('Only the first 2 companies'), findsOneWidget);
    });

    testWidgets('a failure is explained and can be retried', (tester) async {
      var calls = 0;
      await open(tester, () async {
        calls++;
        if (calls == 1) throw Exception('Platform admin role required.');
        return PlatformOverview.fromMap(_payload());
      });
      expect(find.textContaining('Platform admin role required.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha Garments'), findsOneWidget);
    });
  });
}
