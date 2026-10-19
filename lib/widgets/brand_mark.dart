import 'package:flutter/material.dart';

/// The Hola Manje logo mark (same shapes as site/assets/logo.svg): a navy
/// rounded square holding a white "H" with a teal crossbar and a coin dot.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Hola Manje',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MarkPainter()),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 512;
    RRect r(double x, double y, double w, double h, double rad) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x * k, y * k, w * k, h * k), Radius.circular(rad * k));

    canvas.drawRRect(r(0, 0, 512, 512, 116), Paint()..color = const Color(0xFF0B1F3A));
    final white = Paint()..color = Colors.white;
    canvas.drawRRect(r(136, 128, 52, 256, 26), white);
    canvas.drawRRect(r(324, 128, 52, 256, 26), white);
    final teal = Paint()..color = const Color(0xFF14B8A6);
    canvas.drawRRect(r(160, 228, 192, 56, 28), teal);
    canvas.drawCircle(Offset(376 * k, 136 * k), 30 * k, teal);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
