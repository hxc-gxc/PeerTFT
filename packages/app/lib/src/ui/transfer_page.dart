import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/transfer_session.dart';
import '../theme/app_theme.dart';
import 'complete_page.dart';
import 'widgets/app_scaffold.dart';
import 'widgets/countdown_text.dart';
import 'widgets/decorations.dart';
import 'widgets/gradient_button.dart';
import 'widgets/progress_ring.dart';

class TransferPage extends ConsumerWidget {
  const TransferPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transferSessionProvider);

    ref.listen<TransferState>(transferSessionProvider, (previous, next) {
      if (next is Complete) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const CompletePage()),
        );
      }
    });

    return AppScaffold(
      backdrop: const AmbientBackdrop(
        colors: [AppTheme.indigo, AppTheme.pink, AppTheme.mint],
      ),
      appBar: AppBar(
        titleSpacing: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF4EEDB2),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppTheme.ink,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'Transfert',
          style: GoogleFonts.baloo2(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: switch (state) {
          Negotiating() => _negotiatingView(),
          Transferring(
            :final fileName,
            :final totalBytes,
            :final transferredBytes,
            :final throughputBps,
          ) =>
            _transferringView(
              context,
              ref,
              fileName,
              totalBytes,
              transferredBytes,
              throughputBps,
            ),
          Failed(:final message) => _failedView(context, message, ref),
          Reconnecting(:final deadline) => _reconnectingView(
            context,
            ref,
            deadline,
          ),
          _ => const Center(
            child: CircularProgressIndicator(color: AppTheme.indigo),
          ),
        },
      ),
    );
  }

  Widget _negotiatingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.indigo),
          const SizedBox(height: 20),
          Text(
            'Négociation de la connexion…',
            style: GoogleFonts.baloo2(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _transferringView(
    BuildContext context,
    WidgetRef ref,
    String fileName,
    int totalBytes,
    int transferred,
    double bps,
  ) {
    final progress = totalBytes > 0 ? transferred / totalBytes : 0.0;
    final mbps = bps / (1024 * 1024);
    final etaSeconds = bps > 0
        ? ((totalBytes - transferred) / bps).ceil()
        : null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        ProgressRing(
          progress: progress,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.baloo2(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 4),
              // PDF file icon
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4B6E),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'PDF',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                fileName,
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppTheme.ink,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                'Le fichier arrive…',
                style: GoogleFonts.nunito(
                  color: const Color(0xFFFF6B8B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        // Stats Card with Squiggle Waves
        Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(
              top: -14,
              right: 16,
              child: Squiggle(
                color: Color(0xFFFF6B8B),
                width: 60,
                height: 18,
                strokeWidth: 4,
              ),
            ),
            const Positioned(
              bottom: -14,
              left: 16,
              child: Squiggle(
                color: Color(0xFF582BE8),
                width: 60,
                height: 18,
                strokeWidth: 4,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.ink.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mbps > 0 ? '${mbps.toStringAsFixed(1)} Mo/s' : '0,0 Mo/s',
                    style: GoogleFonts.baloo2(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(width: 28),
                  Text(
                    etaSeconds != null ? '$etaSeconds sec' : '-- sec',
                    style: GoogleFonts.baloo2(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${_fmtBytes(transferred)} / ${_fmtBytes(totalBytes)}',
          style: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.ink.withValues(alpha: 0.5),
          ),
        ),
        const Spacer(),
        GradientButton(
          label: 'Annuler',
          colors: const [Color(0xFF582BE8), Color(0xFF7C3AED)],
          onPressed: () {
            ref.read(transferSessionProvider.notifier).cancel();
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _failedView(BuildContext context, String message, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/illustrations/no_connection.svg',
            height: 140,
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              ref.read(transferSessionProvider.notifier).cancel();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Retour'),
          ),
        ],
      ),
    );
  }

  Widget _reconnectingView(
    BuildContext context,
    WidgetRef ref,
    DateTime deadline,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.indigo),
          const SizedBox(height: 20),
          Text(
            'Reconnexion en cours…',
            style: GoogleFonts.baloo2(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 8),
          CountdownText(deadline: deadline),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              ref.read(transferSessionProvider.notifier).cancel();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: Text(
              'Annuler',
              style: GoogleFonts.nunito(
                color: AppTheme.indigo,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}
