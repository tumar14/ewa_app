import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/models/platform_config.dart';
import 'package:ewa_app/screens/platform_admin/platform_settings_screen.dart';

void main() {
  group('industry list rules', () {
    test('names are cleaned and checked', () {
      expect(cleanIndustryName('  Garment   making '), 'Garment making');
      expect(industryProblem('', []), isNotNull);
      expect(industryProblem('   ', []), isNotNull);
      expect(industryProblem('x' * 101, []), isNotNull);
      expect(industryProblem('<b>', []), isNotNull);
      expect(industryProblem('Retail', ['retail']), contains('already'));
      expect(industryProblem('Retail', ['Mining']), isNull);
      expect(industryProblem('One more', List.generate(kMaxIndustries, (i) => 'I$i')), isNotNull);
    });

    test('a saved list is read cleanly, and the defaults stand in for nothing usable', () {
      expect(industriesFromMap({'industries': ['  Retail ', 'retail', 3, '<x>', 'Mining']}), ['Retail', 'Mining']);
      expect(industriesFromMap(null), kDefaultIndustries);
      expect(industriesFromMap({'industries': []}), kDefaultIndustries);
      expect(industriesFromMap({'industries': 'Retail'}), kDefaultIndustries);
    });

    test('the standard list matches the one the server and website use', () {
      final source = File('functions/src/industries.ts').readAsStringSync();
      final block = RegExp(r'DEFAULT_INDUSTRIES: readonly string\[\] = \[([\s\S]*?)\];').firstMatch(source)!.group(1)!;
      final server = [
        for (final line in block.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty))
          if (line == 'INDUSTRY_OTHER,') kIndustryOther else RegExp(r'^"(.*)",$').firstMatch(line)!.group(1)!,
      ];
      expect(kDefaultIndustries, server);
    });

    test('the defaults are valid and distinct', () {
      final seen = <String>[];
      for (final name in kDefaultIndustries) {
        expect(industryProblem(name, seen), isNull, reason: name);
        seen.add(name);
      }
    });
  });

  group('IndustriesEditor', () {
    List<String>? saved;

    Future<void> open(WidgetTester tester, List<String> initial) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      saved = null;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: IndustriesEditor(
              saved: initial,
              onSave: (list) async => saved = list,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    FilledButton saveButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save industries'));

    testWidgets('nothing to save until something changes', (tester) async {
      await open(tester, ['Retail', 'Mining']);
      expect(find.text('Retail'), findsOneWidget);
      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('adding and removing industries saves the new list in order', (tester) async {
      await open(tester, ['Retail', 'Mining']);
      await tester.enterText(find.byType(TextField), '  Sugar   farming ');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.text('Sugar farming'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove Retail'));
      await tester.pumpAndSettle();
      expect(find.text('Retail'), findsNothing);

      expect(saveButton(tester).onPressed, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Save industries'));
      await tester.pumpAndSettle();
      expect(saved, ['Mining', 'Sugar farming']);
    });

    testWidgets('a duplicate is explained and not added', (tester) async {
      await open(tester, ['Retail']);
      await tester.enterText(find.byType(TextField), 'retail');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.textContaining('already in the list'), findsOneWidget);
      expect(find.text('Retail'), findsOneWidget);
    });

    testWidgets('an empty list cannot be saved', (tester) async {
      await open(tester, ['Retail']);
      await tester.tap(find.byTooltip('Remove Retail'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save industries'));
      await tester.pumpAndSettle();
      expect(find.text('Keep at least one industry in the list.'), findsOneWidget);
      expect(saved, isNull);
    });

    testWidgets('the standard list can be restored, and changes discarded', (tester) async {
      await open(tester, ['Retail']);
      await tester.tap(find.text('Use the standard list'));
      await tester.pumpAndSettle();
      expect(find.text('Construction'), findsOneWidget);
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Construction'), findsNothing);
      expect(find.text('Retail'), findsOneWidget);
    });
  });
}
