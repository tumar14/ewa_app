import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/models/fee_schedule.dart';
import 'package:ewa_app/models/settings.dart';
import 'package:ewa_app/providers/firebase_providers.dart';
import 'package:ewa_app/providers/settings_providers.dart';
import 'package:ewa_app/screens/admin/settings_screen.dart';
import 'package:ewa_app/services/settings_repository.dart';

class _FakeSettingsRepository implements SettingsRepository {
  AppSettings? saved;
  AppSettings? previousSettings;

  @override
  Future<void> update(AppSettings settings) async {
    saved = settings;
  }

  @override
  Future<AppSettings?> previous() async => previousSettings;

  @override
  Stream<AppSettings> watch() => const Stream.empty();
}

void main() {
  final custom = AppSettings(
    companyName: 'Vuvuka Investment',
    maxDrawPercent: 0.3,
    feeSchedule: const FeeSchedule.percent(0.12),
    maxDrawsPerCycle: 5,
    autoApprove: true,
    allowManualHourEdits: false,
    maxShiftHours: 9,
    countOnlyReviewedHours: true,
  );

  Future<_FakeSettingsRepository> open(WidgetTester tester, {AppSettings? previous}) async {
    tester.view.physicalSize = const Size(900, 7000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = _FakeSettingsRepository()..previousSettings = previous;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        appSettingsProvider.overrideWith((ref) => Stream.value(custom)),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('shows the saved attendance rules', (tester) async {
    await open(tester);
    expect(find.text('Longest single time record: 9 hours'), findsOneWidget);
    expect(find.textContaining('Fee: 12.0%'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isTrue); // automatic approval
  });

  testWidgets('Reset to defaults loads the standard values, keeps the name, and saves nothing until Save', (tester) async {
    final repo = await open(tester);
    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();
    expect(find.text('Reset to standard settings?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(repo.saved, isNull);
    expect(find.text('Longest single time record: 14 hours'), findsOneWidget);
    expect(find.textContaining('Fee: 5.0%'), findsOneWidget);
    expect(find.text('Vuvuka Investment'), findsOneWidget);

    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    final saved = repo.saved!;
    expect(saved.companyName, 'Vuvuka Investment');
    expect(saved.maxDrawsPerCycle, 2);
    expect(saved.maxDrawPercent, 0.5);
    expect(saved.feeSchedule, const FeeSchedule.percent(0.05));
    expect(saved.autoApprove, isFalse);
    expect(saved.allowManualHourEdits, isTrue);
    expect(saved.countOnlyReviewedHours, isFalse);
    expect(saved.maxShiftHours, 14);
  });

  testWidgets('cancelling the reset changes nothing', (tester) async {
    final repo = await open(tester);
    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Longest single time record: 9 hours'), findsOneWidget);
    expect(repo.saved, isNull);
  });

  testWidgets('Restore previous says so when there is nothing to restore', (tester) async {
    await open(tester);
    await tester.tap(find.text('Restore previous'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no earlier settings'), findsOneWidget);
  });

  testWidgets('Restore previous brings back the earlier settings and still needs Save', (tester) async {
    final earlier = AppSettings(
      companyName: 'Vuvuka Investments (Pty) Ltd',
      maxDrawPercent: 0.4,
      feeSchedule: const FeeSchedule.percent(0.07),
      maxDrawsPerCycle: 3,
      maxShiftHours: 11,
    );
    final repo = await open(tester, previous: earlier);
    await tester.tap(find.text('Restore previous'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();

    expect(repo.saved, isNull);
    expect(find.text('Longest single time record: 11 hours'), findsOneWidget);
    expect(find.textContaining('Fee: 7.0%'), findsOneWidget);
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(repo.saved!.maxDrawsPerCycle, 3);
    expect(repo.saved!.companyName, 'Vuvuka Investments (Pty) Ltd');
  });
}
