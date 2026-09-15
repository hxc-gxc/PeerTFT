import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Standard app scaffold that enforces mobile-first proportions (maxWidth: 440)
/// when viewed on wide desktop or tablet screens, preventing cards, inputs, and
/// buttons from stretching unnaturally across the entire display.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.backdrop,
    this.maxWidth = 440,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? backdrop;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: appBar,
      body: Stack(
        children: [
          // Full-bleed decorative backdrop, pointer-transparent
          if (backdrop != null)
            Positioned.fill(
              child: IgnorePointer(child: backdrop!),
            ),
          // Constrained content column, anchored at top-center
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: body,
            ),
          ),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar != null
          ? SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: bottomNavigationBar!,
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
