import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'receive_page.dart';
import 'send_page.dart';
import 'widgets/app_scaffold.dart';
import 'widgets/decorations.dart';

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
            _ActionCard(
              gradientColors: const [Color(0xFF582BE8), Color(0xFF8B5CF6)],
              title: 'Envoyer un fichier',
              subtitle: 'Sélectionner et transférer',
              isUpload: true,
              bubbleColor: const Color(0xFF4318D1),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SendPage()),
              ),
            ),
            const SizedBox(height: 16),
            _ActionCard(
              gradientColors: const [Color(0xFFFF6B8B), Color(0xFFFFA5A5)],
              title: 'Recevoir un fichier',
              subtitle: 'Prêt à recevoir',
              isUpload: false,
              bubbleColor: const Color(0xFFFA5279),
              onTap: () => Navigator.of(context).push(
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

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.gradientColors,
    required this.title,
    required this.subtitle,
    required this.isUpload,
    required this.bubbleColor,
    required this.onTap,
  });

  final List<Color> gradientColors;
  final String title;
  final String subtitle;
  final bool isUpload;
  final Color bubbleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          height: 136,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                // Organic background bubble decorations
                Positioned(
                  left: -20,
                  bottom: -30,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: bubbleColor.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                Positioned(
                  top: -15,
                  right: 90,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                // Sparkle accents
                const Positioned(
                  top: 16,
                  right: 90,
                  child: Sparkle(size: 16, color: Colors.white, opacity: 0.6),
                ),
                const Positioned(
                  bottom: 18,
                  right: 18,
                  child: Sparkle(size: 14, color: Colors.white, opacity: 0.5),
                ),
                // Content row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.baloo2(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              subtitle,
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Mockup-faithful prominent tray icon with black stroke
                      isUpload
                          ? const UploadTrayIcon(size: 48, color: AppTheme.ink)
                          : const DownloadTrayIcon(size: 48, color: AppTheme.ink),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
