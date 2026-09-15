import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The multi-colored liquid organic blob illustration from the "Recevoir" screen (Mockup 4).
/// Composed of 3 smooth overlapping organic lobes (violet, coral pink, mint green)
/// with a glossy specular highlight curve.
class ReceivingBlobIllustration extends StatelessWidget {
  const ReceivingBlobIllustration({super.key, this.width = 130, this.height = 90});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _ReceivingBlobPainter(),
    );
  }
}

class _ReceivingBlobPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Mint / Turquoise lobe (bottom right)
    final mintPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF5EEAD4), Color(0xFF34D399)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(w * 0.45, h * 0.4, w * 0.5, h * 0.55))
      ..style = PaintingStyle.fill;

    final mintPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(w * 0.72, h * 0.68),
            width: w * 0.46,
            height: h * 0.44,
          ),
          Radius.circular(w * 0.2),
        ),
      );
    canvas.drawPath(mintPath, mintPaint);

    // 2. Coral Pink lobe (middle & upper right)
    final pinkPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFF7597), Color(0xFFFF94B2)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(w * 0.4, 0, w * 0.55, h * 0.7))
      ..style = PaintingStyle.fill;

    final pinkPath = Path()
      ..moveTo(w * 0.48, h * 0.28)
      ..cubicTo(w * 0.52, h * 0.05, w * 0.78, h * 0.05, w * 0.82, h * 0.25)
      ..cubicTo(w * 0.88, h * 0.45, w * 0.82, h * 0.65, w * 0.64, h * 0.65)
      ..cubicTo(w * 0.45, h * 0.65, w * 0.42, h * 0.45, w * 0.48, h * 0.28)
      ..close();
    canvas.drawPath(pinkPath, pinkPaint);

    // Small standalone pink drop at top right
    final smallPinkPaint = Paint()
      ..color = const Color(0xFFFF94B2)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.88, h * 0.28),
        width: w * 0.12,
        height: h * 0.16,
      ),
      smallPinkPaint,
    );

    // 3. Violet / Indigo lobe (main front left)
    final violetPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF582BE8), Color(0xFF7C3AED)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, h * 0.1, w * 0.65, h * 0.85))
      ..style = PaintingStyle.fill;

    final violetPath = Path()
      ..moveTo(w * 0.2, h * 0.25)
      ..cubicTo(w * 0.1, h * 0.08, w * 0.45, h * 0.1, w * 0.48, h * 0.32)
      ..cubicTo(w * 0.52, h * 0.55, w * 0.45, h * 0.85, w * 0.28, h * 0.85)
      ..cubicTo(w * 0.08, h * 0.85, w * 0.05, h * 0.55, w * 0.2, h * 0.25)
      ..close();
    canvas.drawPath(violetPath, violetPaint);

    // 4. White specular gloss highlight on the violet lobe
    final glossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final glossPath = Path()
      ..moveTo(w * 0.16, h * 0.38)
      ..cubicTo(w * 0.14, h * 0.28, w * 0.20, h * 0.22, w * 0.26, h * 0.22);
    canvas.drawPath(glossPath, glossPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Avatar badge sticker shown in the top right of the Home screen header (Mockup 2).
class AvatarBadge extends StatelessWidget {
  const AvatarBadge({super.key, this.size = 38});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFC6F6D5), // Mint circle base
        border: Border.all(color: Colors.black, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Face
          Positioned(
            bottom: 2,
            child: Container(
              width: size * 0.5,
              height: size * 0.45,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFFDFBA),
              ),
            ),
          ),
          // Teal hair
          Positioned(
            top: 2,
            child: Container(
              width: size * 0.65,
              height: size * 0.45,
              decoration: const BoxDecoration(
                color: Color(0xFF4EEDB2),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
          ),
          // Pink headset / accessory
          Positioned(
            top: 4,
            child: Container(
              width: size * 0.72,
              height: size * 0.28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFF6B8B), width: 2),
              ),
            ),
          ),
          // Smile
          Positioned(
            bottom: 6,
            child: Container(
              width: 6,
              height: 3,
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three fanned, rotated file-type cards with colorful borders and icons (PDF, Image, Audio)
/// matching the "Choisir un fichier" dropzone in Mockup 5.
class FanFileCards extends StatelessWidget {
  const FanFileCards({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      width: 120,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Left card: Audio/Music (pink)
          Positioned(
            left: 8,
            top: 10,
            child: Transform.rotate(
              angle: -0.22,
              child: _card(
                color: const Color(0xFFFF6B8B),
                icon: Icons.music_note_rounded,
                badge: 'MP3',
              ),
            ),
          ),
          // Right card: PDF (coral red)
          Positioned(
            right: 8,
            top: 10,
            child: Transform.rotate(
              angle: 0.22,
              child: _card(
                color: const Color(0xFFFF4B6E),
                icon: Icons.picture_as_pdf_rounded,
                badge: 'PDF',
              ),
            ),
          ),
          // Center card: Image (indigo / cyan)
          Positioned(
            top: 4,
            child: _card(
              color: const Color(0xFF582BE8),
              icon: Icons.image_rounded,
              badge: 'IMG',
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Color color, required IconData icon, required String badge}) {
    return Container(
      width: 44,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A wavy hand-drawn-style line, used near stat cards in Mockup 3.
class Squiggle extends StatelessWidget {
  const Squiggle({
    super.key,
    required this.color,
    this.width = 64,
    this.height = 20,
    this.strokeWidth = 4,
  });

  final Color color;
  final double width;
  final double height;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _SquigglePainter(color: color, strokeWidth: strokeWidth),
    );
  }
}

class _SquigglePainter extends CustomPainter {
  _SquigglePainter({required this.color, required this.strokeWidth});
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(0, size.height / 2);
    const waves = 3;
    final step = size.width / waves;
    for (var i = 0; i < waves; i++) {
      path.quadraticBezierTo(
        step * i + step / 2,
        i.isEven ? 0 : size.height,
        step * (i + 1),
        size.height / 2,
      );
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SquigglePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// Small solid dot accent scattered on backgrounds.
class Dot extends StatelessWidget {
  const Dot({
    super.key,
    required this.color,
    this.opacity = 1,
    this.size = 8,
  });

  final Color color;
  final double opacity;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: opacity),
    ),
  );
}

/// Full-bleed corner blobs, sparkles and dots for screen backgrounds.
/// Scaled and positioned so they add playful texture without being distracting.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    super.key,
    this.colors = const [AppTheme.mint, AppTheme.pink, AppTheme.indigo],
  });

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -30,
            child: Opacity(
              opacity: 0.35,
              child: BackgroundBlob(color: colors[0], size: 180),
            ),
          ),
          Positioned(
            top: 140,
            left: -50,
            child: Opacity(
              opacity: 0.22,
              child: BackgroundBlob(color: colors[1], size: 150),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -40,
            child: Opacity(
              opacity: 0.25,
              child: BackgroundBlob(color: colors[2], size: 190),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -40,
            child: Opacity(
              opacity: 0.2,
              child: BackgroundBlob(color: colors[0], size: 110),
            ),
          ),
          // Scattered playful accents
          const Positioned(top: 80, left: 32, child: Dot(color: AppTheme.ink, opacity: 0.1)),
          const Positioned(top: 200, right: 36, child: Dot(color: AppTheme.ink, opacity: 0.1, size: 6)),
          Positioned(bottom: 240, right: 60, child: Dot(color: colors[2], opacity: 0.25, size: 8)),
        ],
      ),
    );
  }
}

/// Gradient rounded-square logo badge with "P".
class LogoBadge extends StatelessWidget {
  const LogoBadge({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          colors: [AppTheme.indigo, AppTheme.pink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.indigo.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'P',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: size * 0.55,
          ),
        ),
      ),
    );
  }
}

/// Organic irregular blob painter.
class BackgroundBlob extends StatelessWidget {
  const BackgroundBlob({super.key, required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _BlobPainter(color));
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final rnd = Random(color.hashCode);
    const points = 8;
    final cx = size.width / 2, cy = size.height / 2;
    final vertices = [
      for (var i = 0; i < points; i++)
        (() {
          final angle = 2 * pi * i / points;
          final r = size.width / 2 * (0.75 + rnd.nextDouble() * 0.25);
          return Offset(cx + r * cos(angle), cy + r * sin(angle));
        })(),
    ];
    final path = Path();
    final start = Offset.lerp(vertices.last, vertices.first, 0.5)!;
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < points; i++) {
      final next = vertices[(i + 1) % points];
      final mid = Offset.lerp(vertices[i], next, 0.5)!;
      path.quadraticBezierTo(vertices[i].dx, vertices[i].dy, mid.dx, mid.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) => oldDelegate.color != color;
}
