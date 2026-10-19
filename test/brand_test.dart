import 'dart:math' show pow;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/brand.dart';
import 'package:ewa_app/theme/glass_theme.dart';
import 'package:ewa_app/widgets/brand_mark.dart';

void main() {
  test('brand copy', () {
    expect(Brand.name, 'Hola Manje');
    expect(Brand.tagline, 'Your money. Your time.');
    expect(Brand.supportingMessage, 'Access your earned wages before payday.');
    expect(Brand.appTitle, contains(Brand.name));
  });

  testWidgets('BrandMark renders at the requested size with an accessible label', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: BrandMark(size: 80))));
    expect(tester.getSize(find.byType(BrandMark)), const Size(80, 80));
    expect(find.bySemanticsLabel('Hola Manje'), findsOneWidget);
  });

  test('palette is navy and teal, light theme is white-based', () {
    expect(glassNavy1, const Color(0xFF0B1F3A));
    expect(glassBlue, const Color(0xFF14B8A6));
    expect(glassLightBg0, const Color(0xFFFFFFFF));
    final light = buildGlassThemeLight();
    expect(light.brightness, Brightness.light);
    expect(light.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
  });

  test('white text on the filled-button teal meets 4.5:1 contrast', () {
    double lum(Color c) {
      double ch(double v) => v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }

    final ratio = (1.05) / (lum(glassBlueDark) + 0.05);
    expect(ratio, greaterThanOrEqualTo(4.5));
  });
}
