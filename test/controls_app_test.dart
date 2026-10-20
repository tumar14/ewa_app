import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/models/audit_log_entry.dart';
import 'package:ewa_app/models/draw_request.dart';
import 'package:ewa_app/models/employee.dart';
import 'package:ewa_app/models/settings.dart';
import 'package:ewa_app/models/signoff_record.dart';
import 'package:ewa_app/providers/signoff_providers.dart';
import 'package:ewa_app/screens/admin/supervisor_signoff_screen.dart';
import 'package:ewa_app/screens/platform_admin/platform_settings_screen.dart';
import 'package:ewa_app/services/signoff_service.dart';
import 'package:ewa_app/utils/payment_reference.dart';

class _FakeSignOff implements SignOffService {
  final List<SignOffRecord> records;
  List<String>? signedIds;
  _FakeSignOff(this.records);

  @override
  Future<List<SignOffRecord>> day(DateTime day) async => records;

  @override
  Future<({int signed, List<String> refused})> signOff(List<String> ids) async {
    signedIds = ids;
    return (signed: ids.length, refused: <String>[]);
  }
}

SignOffRecord _rec(String id, String name, {bool canSign = true, bool reviewed = false, bool voided = false, bool flagged = false, String source = 'manual', String? reason}) =>
    SignOffRecord(
      id: id,
      employeeId: 'e-$id',
      employeeName: name,
      employeeNumber: 'N-$id',
      clockIn: DateTime(2026, 10, 19, 7),
      clockOut: DateTime(2026, 10, 19, 16),
      source: source,
      flagged: flagged,
      voided: voided,
      reviewed: reviewed,
      editReason: reason,
      canSign: canSign,
    );

void main() {
  group('payment reference', () {
    test('real references pass, app-style and junk do not', () {
      expect(paymentReferenceProblem('MP201020.1530.A12345'), isNull);
      expect(paymentReferenceProblem('FNB/2026/10/445'), isNull);
      for (final bad in ['', 'abc', 'x' * 61, '<b>', 'DISP-ABCD1234', 'disp-1234']) {
        expect(paymentReferenceProblem(bad), isNotNull, reason: bad);
      }
    });
  });

  group('settings model', () {
    test('the new controls have safe defaults and survive a round trip', () {
      final d = AppSettings();
      expect(d.separatePayer, isTrue);
      expect(d.separateSignOff, isTrue);
      expect(d.dualApprovalAboveMinor, isNull);
      expect(d.payoutCoolingHours, 48);
      expect(d.pauseDrawsDaysBeforeExit, 7);
      expect(d.claimCodeValidDays, 30);
      final custom = AppSettings(
        dualApprovalAboveMinor: 50000,
        separatePayer: false,
        newEmployeeWaitDays: 14,
        pauseDrawsDaysBeforeExit: 3,
        payoutCoolingHours: 72,
        separateSignOff: false,
        claimCodeValidDays: 0,
      );
      final back = AppSettings.fromMap(custom.toMap());
      expect(back.dualApprovalAboveMinor, 50000);
      expect(back.separatePayer, isFalse);
      expect(back.newEmployeeWaitDays, 14);
      expect(back.pauseDrawsDaysBeforeExit, 3);
      expect(back.payoutCoolingHours, 72);
      expect(back.separateSignOff, isFalse);
      expect(back.claimCodeValidDays, 0);
    });

    test('old documents without the new fields, and out-of-range values, fall back to the defaults', () {
      final old = AppSettings.fromMap({'companyName': 'X'});
      expect(old.payoutCoolingHours, 48);
      expect(old.separatePayer, isTrue);
      final odd = AppSettings.fromMap({'newEmployeeWaitDays': 5000, 'payoutCoolingHours': -3, 'claimCodeValidDays': 'x'});
      expect(odd.newEmployeeWaitDays, 0);
      expect(odd.payoutCoolingHours, 48);
      expect(odd.claimCodeValidDays, 30);
    });
  });

  group('other models', () {
    test('a draw knows when it needs a second admin', () {
      final d = DrawRequest.fromMap('d1', {
        'employeeId': 'w', 'amountMinor': 20000, 'feeMinor': 1000, 'totalMinor': 21000,
        'status': 'pending', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 19)),
        'needsSecondApproval': true, 'firstApprovalBy': 'a1',
      });
      expect(d.needsSecondApproval, isTrue);
      expect(d.firstApprovalBy, 'a1');
      expect(DrawRequest.fromMap('d2', {
        'employeeId': 'w', 'amountMinor': 100, 'feeMinor': 5, 'totalMinor': 105, 'status': 'pending',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 19)),
      }).needsSecondApproval, isFalse);
    });

    test('an employee carries the last working day and the payout hold', () {
      final e = Employee.fromMap('w', {
        'name': 'T', 'hourlyRate': 40, 'role': 'worker',
        'lastWorkingDay': Timestamp.fromDate(DateTime(2026, 11, 30)),
        'payoutChangedAt': Timestamp.fromDate(DateTime(2026, 10, 19)),
      });
      expect(e.lastWorkingDay, DateTime(2026, 11, 30));
      expect(e.payoutChangedAt, DateTime(2026, 10, 19));
      expect(e.toMap()['lastWorkingDay'], isA<Timestamp>());
      expect(Employee.fromMap('w', {'name': 'T', 'hourlyRate': 40}).toMap()['lastWorkingDay'], isNull);
    });

    test('the audit log describes the new kinds of entry', () {
      AuditLogEntry e(String type, Map<String, dynamic> data) => AuditLogEntry(id: 'x', type: type, data: {'type': type, ...data});
      expect(e('settings_changed', {'changes': [{'field': 'maxDrawPercent', 'from': 0.5, 'to': 0.4}]}).summary, contains('maxDrawPercent'));
      expect(e('settings_changed', {'changedBy': 'u1'}).actorId, 'u1');
      expect(e('employee_changed', {'employeeId': 'w', 'changes': [{'field': 'hourlyRate'}], 'changedBy': 'a'}).summary, contains('hourlyRate'));
      expect(e('employee_added', {'name': 'Ghost', 'role': 'worker'}).summary, contains('Ghost'));
      expect(e('draw_first_approval', {'amountMinor': 20000, 'employeeId': 'w'}).summary, contains('second admin'));
      expect(e('time_signoff', {'count': 4, 'signedBy': 's'}).summary, contains('4'));
    });

    test('a sign-off record reads the server answer', () {
      final r = SignOffRecord.fromMap({
        'id': 's1', 'employeeId': 'w', 'employeeName': 'Thandi', 'employeeNumber': 'DG-101',
        'clockInMs': DateTime(2026, 10, 19, 7).millisecondsSinceEpoch,
        'clockOutMs': null, 'source': 'adminEdit', 'canSign': true, 'reviewed': false, 'editReason': 'Forgot',
      });
      expect(r.employeeName, 'Thandi');
      expect(r.needsSignOff, isTrue);
      expect(r.clockOut, isNull);
      expect(SignOffRecord.fromMap({}).canSign, isFalse);
    });
  });

  group('sign-off screen', () {
    Future<_FakeSignOff> open(WidgetTester tester, List<SignOffRecord> records) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeSignOff(records);
      await tester.pumpWidget(ProviderScope(
        overrides: [signOffServiceProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: SupervisorSignoffScreen()),
      ));
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('shows names, marks what cannot be signed by this person, and signs only the rest', (tester) async {
      final fake = await open(tester, [
        _rec('1', 'Thandi Nkosi'),
        _rec('2', 'Bongani Simelane', canSign: false, source: 'adminEdit', reason: 'Phone had no signal'),
        _rec('3', 'Zodwa Khumalo', reviewed: true),
        _rec('4', 'Void Person', voided: true),
      ]);
      expect(find.textContaining('Thandi Nkosi'), findsOneWidget);
      expect(find.textContaining('Reason: Phone had no signal'), findsOneWidget);
      expect(find.byTooltip('Someone else must sign this off'), findsOneWidget);

      await tester.tap(find.text('Sign off day'));
      await tester.pumpAndSettle();
      expect(find.text('Sign off day?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign off'));
      await tester.pumpAndSettle();
      expect(fake.signedIds, ['1']);
    });

    testWidgets('with nothing this person may sign there is no sign-off button', (tester) async {
      await open(tester, [_rec('1', 'Own Hours', canSign: false), _rec('2', 'Done', reviewed: true)]);
      expect(find.text('Sign off day'), findsNothing);
    });

    testWidgets('an empty day says so', (tester) async {
      await open(tester, []);
      expect(find.text('No punches on this day.'), findsOneWidget);
    });
  });

  group('platform ceiling editor', () {
    testWidgets('saves only after a change and shows the percentage', (tester) async {
      double? saved;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DrawCeilingEditor(saved: 0.5, onSave: (c) async => saved = c),
        ),
      ));
      expect(find.text('50% of earned wages'), findsOneWidget);
      FilledButton button() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save ceiling'));
      expect(button().onPressed, isNull);

      final slider = tester.getTopLeft(find.byType(Slider));
      await tester.tapAt(slider + const Offset(8, 20)); // far left: the minimum
      await tester.pumpAndSettle();
      expect(find.text('5% of earned wages'), findsOneWidget);
      expect(button().onPressed, isNotNull);
      await tester.tap(find.text('Save ceiling'));
      await tester.pumpAndSettle();
      expect(saved, closeTo(0.05, 0.001));
    });
  });
}
