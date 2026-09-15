import 'dart:math';

import 'package:flutter/material.dart';

/// A thick multi-color progress ring matching Mockup 3 with vibrant gradient arcs
/// (violet -> magenta -> coral pink -> mint green) and rounded stroke caps.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    required this.child,
    this.size = 250,
  });

  final double progress; // 0..1
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(progress.clamp(0, 1)),
          ),
          Padding(padding: const EdgeInsets.all(28), child: child),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 14;

    // Track ring
    final trackPaint = Paint()
      ..color = const Color(0xFFF1EEFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    // Outer subtle glow / decorative outer arc
    final outerGlow = Paint()
      ..color = const Color(0xFF582BE8).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + 2),
      -pi / 2,
      2 * pi * progress,
      false,
      outerGlow,
    );

    // Dynamic Multi-color Gradient Arc
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * pi * progress;

    final gradientPaint = Paint()
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: 2 * pi,
        colors: [
          Color(0xFF582BE8), // Violet
          Color(0xFF9333EA), // Magenta
          Color(0xFFFF6B8B), // Coral Pink
          Color(0xFF4EEDB2), // Mint Green
          Color(0xFF582BE8), // Violet
        ],
        transform: GradientRotation(-pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -pi / 2, sweep, false, gradientPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
