import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/transfer_session.dart';
import '../theme/app_theme.dart';
import 'widgets/app_scaffold.dart';
import 'widgets/decorations.dart';
import 'widgets/gradient_button.dart';

class CompletePage extends ConsumerWidget {
  const CompletePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transferSessionProvider);
    if (state is! Complete) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.indigo)),
      );
    }

    return AppScaffold(
      backdrop: AmbientBackdrop(
        colors: state.hashMatch
            ? const [AppTheme.mint, AppTheme.indigo, AppTheme.pink]
            : const [Colors.orange, AppTheme.indigo, AppTheme.pink],
      ),
      appBar: AppBar(
        titleSpacing: 24,
        title: Text(
          'Terminé',
          style: GoogleFonts.baloo2(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (state.hashMatch)
                SvgPicture.asset(
                  'assets/illustrations/completed.svg',
                  height: 160,
                )
              else
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orange.withValues(alpha: 0.2),
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    size: 56,
                    color: Colors.orange,
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                state.hashMatch ? 'Transfert réussi !' : 'Intégrité incertaine',
                style: GoogleFonts.baloo2(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (state.savedPath != null) ...[
                Text(
                  'Fichier enregistré dans :',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.ink.withValues(alpha: 0.08),
                    ),
                  ),
                  child: SelectableText(
                    state.savedPath!,
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                'SHA-256 :',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppTheme.ink.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                state.sha256Received,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppTheme.ink,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              GradientButton(
                label: 'Terminer',
                colors: const [Color(0xFF582BE8), Color(0xFF7C3AED)],
                onPressed: () {
                  ref.read(transferSessionProvider.notifier).cancel();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
