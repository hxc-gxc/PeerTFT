import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A pill-shaped button filled with a gradient or outlined — the mockups use this for
/// every primary/secondary CTA instead of a flat Material color.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.colors = const [],
    this.icon,
    this.isFullWidth = true,
    this.isOutlined = false,
    this.outlineColor,
    this.textColor,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final List<Color> colors;
  final IconData? icon;
  final bool isFullWidth;
  final bool isOutlined;
  final Color? outlineColor;
  final Color? textColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final effectiveTextColor =
        textColor ??
        (isOutlined
            ? (outlineColor ?? Theme.of(context).colorScheme.primary)
            : Colors.white);

    final buttonContent = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: isOutlined ? Colors.transparent : null,
        gradient: !isOutlined && colors.isNotEmpty
            ? LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        border: isOutlined
            ? Border.all(
                color: outlineColor ?? Theme.of(context).colorScheme.primary,
                width: 2,
              )
            : null,
        boxShadow: !isOutlined && !disabled && colors.isNotEmpty
            ? [
                BoxShadow(
                  color: colors.first.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.baloo2(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: effectiveTextColor,
                ),
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, color: effectiveTextColor, size: 20),
            ],
          ],
        ),
      ),
    );

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onPressed,
          child: isFullWidth
              ? SizedBox(width: double.infinity, child: buttonContent)
              : buttonContent,
        ),
      ),
    );
  }
}
