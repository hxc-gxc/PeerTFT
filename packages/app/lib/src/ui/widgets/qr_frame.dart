import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../theme/app_theme.dart';

/// A QR code with thick colored corner brackets matching Mockup 1:
/// Top-left: Pink, Top-right: Mint, Bottom-left: Violet, Bottom-right: Pink.
class QrFrame extends StatelessWidget {
  const QrFrame({super.key, required this.data, this.size = 180});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    const bracketSize = 26.0;
    const padding = 12.0;

    return SizedBox(
      width: size + padding * 2,
      height: size + padding * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: data,
              version: QrVersions.auto,
              size: size,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppTheme.ink,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppTheme.ink,
              ),
            ),
          ),
          // Top-Left: Coral Pink
          Positioned(
            top: 0,
            left: 0,
            child: _corner(const Color(0xFFFF6B8B), 0, bracketSize),
          ),
          // Top-Right: Mint
          Positioned(
            top: 0,
            right: 0,
            child: _corner(const Color(0xFF4EEDB2), 1, bracketSize),
          ),
          // Bottom-Right: Coral Pink
          Positioned(
            bottom: 0,
            right: 0,
            child: _corner(const Color(0xFFFF6B8B), 2, bracketSize),
          ),
          // Bottom-Left: Violet
          Positioned(
            bottom: 0,
            left: 0,
            child: _corner(const Color(0xFF582BE8), 3, bracketSize),
          ),
        ],
      ),
    );
  }

  Widget _corner(Color color, int quadrant, double bracketSize) {
    return Transform.rotate(
      angle: quadrant * 1.57079632679, // 90° intervals
      child: CustomPaint(
        size: Size.square(bracketSize),
        painter: _BracketPainter(color),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  _BracketPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const cornerRadius = 6.0;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, cornerRadius)
      ..quadraticBezierTo(0, 0, cornerRadius, 0)
      ..lineTo(size.width, 0);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BracketPainter oldDelegate) =>
      oldDelegate.color != color;
}
