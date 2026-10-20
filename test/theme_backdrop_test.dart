import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/theme/glass_theme.dart';
import 'package:ewa_app/widgets/glass_components.dart';

// The window behind a transparent screen is black on Android in dark mode.
const _window = Color(0xFF000000);
const _size = Size(400, 800);

class _Pixels {
  final ByteData data;
  final int width;
  _Pixels(this.data, this.width);
  List<int> at(int x, int y) {
    final i = (y * width + x) * 4;
    return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)];
  }
}

/// A screen built the way the app builds them: a transparent Scaffold with a
/// glass app bar, a gradient body and the floating glass bottom menu.
Widget _app({required bool dark, required bool backdrop}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildGlassThemeLight(),
    darkTheme: buildGlassTheme(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: backdrop ? brandAppBuilder : null,
    home: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Header'), actions: const [Icon(Icons.logout)]),
      body: const GlassBackground(child: SizedBox.expand()),
      bottomNavigationBar: GlassNavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    ),
  );
}

Future<_Pixels> _render(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: key, child: ColoredBox(color: _window, child: app)));
  await tester.pumpAndSettle();
  return (await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return _Pixels(data, image.width);
  }))!;
}

// Header: right of the title, clear of the action icon. Menu strip: the gap
// under the floating pill. Menu pill: between two destinations' labels.
const _header = [250, 40];
const _stripBelowMenu = [200, 795];
const _menuPill = [200, 760];

/// Navy is clearly bluer than red; grey is not.
bool _navy(List<int> rgb) => rgb[2] - rgb[0] >= 0x14;

void main() {
  testWidgets('dark mode: header, bottom menu and the strip around it are navy, not grey', (tester) async {
    final px = await _render(tester, _app(dark: true, backdrop: true));
    for (final spot in [_header, _stripBelowMenu, _menuPill]) {
      final rgb = px.at(spot[0], spot[1]);
      expect(_navy(rgb), isTrue, reason: 'pixel at $spot is $rgb');
    }
  });

  testWidgets('light mode: the same places stay light', (tester) async {
    final px = await _render(tester, _app(dark: false, backdrop: true));
    for (final spot in [_header, _stripBelowMenu, _menuPill]) {
      final rgb = px.at(spot[0], spot[1]);
      expect(rgb.every((c) => c > 0xDC), isTrue, reason: 'pixel at $spot is $rgb');
    }
  });

  testWidgets('without the backdrop the bars are grey (the bug this guards against)', (tester) async {
    final px = await _render(tester, _app(dark: true, backdrop: false));
    final rgb = px.at(_header[0], _header[1]);
    expect(_navy(rgb), isFalse, reason: 'pixel at $_header is $rgb');
  });
}
