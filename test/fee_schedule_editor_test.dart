import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/models/fee_schedule.dart';
import 'package:ewa_app/screens/admin/fee_schedule_editor.dart';

void main() {
  late FeeSchedule schedule;
  String? problem;

  Future<void> open(WidgetTester tester, FeeSchedule initial) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    schedule = initial;
    problem = 'not reported yet';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FeeScheduleEditor(
            initial: initial,
            onChanged: (s, p) {
              schedule = s;
              problem = p;
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('percentage mode shows the percentage and what workers would pay', (tester) async {
    await open(tester, const FeeSchedule.percent(0.05));
    expect(find.textContaining('Fee: 5.0%'), findsOneWidget);
    expect(problem, isNull);
    expect(schedule, const FeeSchedule.percent(0.05));
    expect(find.text('Advance of E100'), findsOneWidget);
    expect(find.text('fee E 5.00'), findsWidgets);
  });

  testWidgets('switching to a tariff table offers starter bands and a valid schedule', (tester) async {
    await open(tester, const FeeSchedule.percent(0.05));
    await tester.tap(find.text('Tariff table'));
    await tester.pumpAndSettle();

    expect(find.text('Band 1'), findsOneWidget);
    expect(find.text('Band 3'), findsOneWidget);
    expect(schedule.isPercent, isFalse);
    expect(problem, isNull);
    expect(schedule.tiers.length, 3);
    expect(schedule.tiers.last.upToMinor, isNull);
    // The starter table charges E1 up to E50, E3 up to E200.
    expect(schedule.feeMinorFor(5000), 100);
    expect(schedule.feeMinorFor(20000), 300);
    expect(find.text('fee E 1.00'), findsOneWidget); // E50 row of the preview
  });

  testWidgets('a saved tariff is shown as editable bands', (tester) async {
    await open(
      tester,
      const FeeSchedule.tiered([
        FeeTier(upToMinor: 5000, flatMinor: 100),
        FeeTier(upToMinor: 20000, flatMinor: 300),
        FeeTier(upToMinor: null, percent: 0.015),
      ]),
    );
    expect(find.text('Band 3'), findsOneWidget);
    expect(find.text('Band 4'), findsNothing);
    expect(problem, isNull);
    expect(schedule.feeMinorFor(100000), 1500);
    expect(find.text('fee E 15.00'), findsWidgets);
  });

  testWidgets('an upper limit that is not higher than the previous band is explained', (tester) async {
    await open(tester, const FeeSchedule.percent(0.05));
    await tester.tap(find.text('Tariff table'));
    await tester.pumpAndSettle();

    await tester.enterText(field('Up to (E)').at(1), '40'); // band 2 below band 1's E50
    await tester.pumpAndSettle();
    expect(problem, contains('higher than the previous'));
    expect(find.textContaining('higher than the previous'), findsOneWidget);
    expect(find.text('What workers would pay'), findsNothing);
  });

  testWidgets('text that is not an amount is explained rather than silently ignored', (tester) async {
    await open(tester, const FeeSchedule.percent(0.05));
    await tester.tap(find.text('Tariff table'));
    await tester.pumpAndSettle();

    await tester.enterText(field('Up to (E)').first, '1.234'); // three decimals
    await tester.pumpAndSettle();
    expect(problem, contains('Band 1'));
    expect(problem, contains('upper limit'));
  });

  testWidgets('bands can be added and removed', (tester) async {
    await open(tester, const FeeSchedule.percent(0.05));
    await tester.tap(find.text('Tariff table'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add band'));
    await tester.pumpAndSettle();
    expect(find.text('Band 4'), findsOneWidget);
    // The new band sits before the open top band, which stays last; it needs a limit.
    expect(problem, isNotNull);
    await tester.enterText(field('Up to (E)').at(2), '500');
    await tester.enterText(find.widgetWithText(TextField, 'Flat fee').at(2), '5');
    await tester.pumpAndSettle();
    expect(problem, isNull);
    expect(schedule.tiers.length, 4);
    expect(schedule.tiers.last.upToMinor, isNull);

    await tester.tap(find.byTooltip('Remove band 3'));
    await tester.pumpAndSettle();
    expect(find.text('Band 4'), findsNothing);
    expect(schedule.tiers.length, 3);
  });

  testWidgets('without an open top band, larger amounts are shown as not allowed', (tester) async {
    await open(tester, const FeeSchedule.percent(0.05));
    await tester.tap(find.text('Tariff table'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch)); // turn off "Last band covers any larger amount"
    await tester.pumpAndSettle();
    await tester.enterText(field('Up to (E)').last, '500');
    await tester.pumpAndSettle();

    expect(problem, isNull);
    expect(schedule.maxAmountMinor, 50000);
    expect(find.text('not allowed'), findsWidgets); // E1000 and E2000 in the preview
  });

  testWidgets('switching back to a percentage restores a percentage schedule', (tester) async {
    await open(tester, const FeeSchedule.percent(0.05));
    await tester.tap(find.text('Tariff table'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Percentage'));
    await tester.pumpAndSettle();
    expect(schedule, const FeeSchedule.percent(0.05));
    expect(problem, isNull);
  });
}
