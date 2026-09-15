import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'receive_page.dart';
import 'send_page.dart';
import 'widgets/app_scaffold.dart';
import 'widgets/decorations.dart';
import 'widgets/gradient_button.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      backdrop: const AmbientBackdrop(
        colors: [AppTheme.mint, AppTheme.pink, AppTheme.indigo],
      ),
      appBar: AppBar(
        titleSpacing: 24,
        title: Text(
          'PeerTFT',
          style: GoogleFonts.baloo2(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: AppTheme.ink,
          ),
        ),
        actions: [
          const AvatarBadge(size: 38),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'PeerTFT',
              children: const [
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Transfert direct P2P chiffré de bout en bout.'),
                ),
              ],
            ),
            icon: const Icon(Icons.settings_outlined, color: AppTheme.ink, size: 26),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Partage. Scanne.\nC’est parti.',
              style: GoogleFonts.baloo2(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                height: 1.12,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 28),
            GradientButton(
              label: 'Envoyer un fichier',
              icon: Icons.upload_rounded,
              colors: const [Color(0xFF582BE8), Color(0xFF8B5CF6)],
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SendPage()),
              ),
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: 'Recevoir un fichier',
              icon: Icons.download_rounded,
              colors: const [Color(0xFFFF6B8B), Color(0xFFFFA5A5)],
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReceivePage()),
              ),
            ),
            const SizedBox(height: 28),
            const _SecurityBadge(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}


class _SecurityBadge extends StatelessWidget {
  const _SecurityBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFC6F6D5), // Soft mint badge
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.ink, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield_outlined, size: 20, color: AppTheme.ink),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Transfert direct et chiffré',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
