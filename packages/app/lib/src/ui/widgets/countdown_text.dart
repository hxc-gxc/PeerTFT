import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

/// Live "N s" countdown to [deadline], ticking once per second.
class CountdownText extends StatefulWidget {
  const CountdownText({super.key, required this.deadline});
  final DateTime deadline;

  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.deadline.difference(DateTime.now());
    final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
    return Text(
      '$seconds s',
      style: GoogleFonts.nunito(
        color: AppTheme.ink.withValues(alpha: 0.6),
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    );
  }
}
