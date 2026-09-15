import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../state/transfer_session.dart';
import '../theme/app_theme.dart';
import 'receive_page.dart';
import 'transfer_page.dart';
import 'widgets/app_scaffold.dart';
import 'widgets/bottom_nav_bar.dart';
import 'widgets/decorations.dart';
import 'widgets/gradient_button.dart';
import 'widgets/qr_frame.dart';

class SendPage extends ConsumerStatefulWidget {
  const SendPage({super.key});

  @override
  ConsumerState<SendPage> createState() => _SendPageState();
}

class _SendPageState extends ConsumerState<SendPage> {
  bool _started = false;
  PlatformFile? _picked;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transferSessionProvider);

    // Navigate to TransferPage when negotiating starts.
    ref.listen<TransferState>(transferSessionProvider, (previous, next) {
      if (next is Negotiating && _started) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const TransferPage()),
        );
      }
    });

    final isWaiting = state is WaitingForPeer;

    return AppScaffold(
      backdrop: isWaiting
          ? Stack(children: _codeReadyDecorations())
          : const AmbientBackdrop(
              colors: [AppTheme.mint, AppTheme.pink, AppTheme.indigo],
            ),
      appBar: AppBar(
        titleSpacing: isWaiting ? 0 : 24,
        leading: isWaiting
            ? Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.indigo,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        ref.read(transferSessionProvider.notifier).cancel();
                        setState(() => _started = false);
                        Navigator.of(context).maybePop();
                      },
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              )
            : IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.ink),
              ),
        title: Text(
          isWaiting ? 'Ton transfert est prêt' : 'Envoyer',
          style: GoogleFonts.baloo2(
            fontSize: isWaiting ? 22 : 26,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        actions: isWaiting
            ? null
            : [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LogoBadge(size: 20),
                      const SizedBox(width: 6),
                      Text(
                        'PeerTFT',
                        style: GoogleFonts.baloo2(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Menu'))),
                  icon: const Icon(
                    Icons.menu_rounded,
                    color: AppTheme.ink,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 8),
              ],
      ),
      bottomNavigationBar: state is Idle
          ? PeerBottomNavBar(
              currentTab: NavTab.envoyer,
              onTabSelected: (_) => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const ReceivePage()),
              ),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: switch (state) {
          Idle() => _pickFileView(context),
          Connecting() => const Center(
            child: CircularProgressIndicator(color: AppTheme.indigo),
          ),
          WaitingForPeer(:final code) => _waitingView(context, code),
          Failed(:final message) => _failedView(context, message),
          _ => const Center(
            child: CircularProgressIndicator(color: AppTheme.indigo),
          ),
        },
      ),
    );
  }

  Widget _pickFileView(BuildContext context) {
    return Column(
      children: [
        _DashedDropzone(onTap: _pickFile),
        const SizedBox(height: 16),
        if (_picked != null)
          _FileChip(
            file: _picked!,
            onRemove: () => setState(() => _picked = null),
          ),
        const SizedBox(height: 28),
        GradientButton(
          label: 'Générer un transfert',
          colors: const [Color(0xFF582BE8), Color(0xFF8B5CF6)],
          onPressed: _picked == null ? null : _send,
        ),
        const SizedBox(height: 10),
        Text(
          'Aucun compte requis',
          style: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.ink.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _waitingView(BuildContext context, String code) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.ink.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  QrFrame(data: code, size: 170),
                  const SizedBox(height: 20),
                  SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F0FF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFDDD6FE),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.indigo,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'En attente du destinataire',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  GradientButton(
                    label: 'Copier le code',
                    icon: Icons.copy_rounded,
                    colors: const [Color(0xFF582BE8), Color(0xFF7C3AED)],
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copié !')),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  GradientButton(
                    label: 'Partager',
                    icon: Icons.share_rounded,
                    colors: const [Color(0xFFFF6B8B), Color(0xFFFF8DA1)],
                    onPressed: () =>
                        SharePlus.instance.share(ShareParams(text: code)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.sensors_rounded,
                  size: 20,
                  color: AppTheme.indigo,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Transfert PeerTFT en cours',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      color: AppTheme.indigo,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () {
                ref.read(transferSessionProvider.notifier).cancel();
                setState(() => _started = false);
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
      ),
    );
  }

  Widget _failedView(BuildContext context, String message) {
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
              setState(() => _started = false);
            },
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final file = files.single;
    if (!kIsWeb && file.path == null) return;
    setState(() => _picked = file);
  }

  void _send() {
    final file = _picked;
    if (file == null) return;
    _started = true;
    ref.read(transferSessionProvider.notifier).startSend(file);
  }

  List<Widget> _codeReadyDecorations() => [
    const Positioned(
      top: 90,
      left: 24,
      child: Dot(color: AppTheme.ink, opacity: 0.15),
    ),
    const Positioned(
      top: 130,
      left: 60,
      child: Dot(color: AppTheme.ink, opacity: 0.15, size: 5),
    ),
    const Positioned(
      top: 160,
      right: 100,
      child: Dot(color: AppTheme.indigo, opacity: 0.3),
    ),
    const Positioned(
      top: 220,
      right: 40,
      child: Dot(color: AppTheme.ink, opacity: 0.15),
    ),
    const Positioned(
      top: 30,
      left: 140,
      child: Dot(color: AppTheme.pink, opacity: 0.25, size: 6),
    ),
    const Positioned(
      bottom: 260,
      left: 30,
      child: Dot(color: AppTheme.mint, opacity: 0.3, size: 6),
    ),
    const Positioned(
      bottom: 60,
      right: 60,
      child: Dot(color: AppTheme.ink, opacity: 0.15),
    ),
    const Positioned(
      top: 60,
      right: -30,
      child: Opacity(
        opacity: 0.25,
        child: BackgroundBlob(color: AppTheme.mint, size: 90),
      ),
    ),
    const Positioned(
      bottom: 140,
      left: -30,
      child: Opacity(
        opacity: 0.2,
        child: BackgroundBlob(color: AppTheme.indigo, size: 80),
      ),
    ),
  ];
}

class _DashedDropzone extends StatelessWidget {
  const _DashedDropzone({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: AppTheme.mint, radius: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36),
          decoration: BoxDecoration(
            color: const Color(0xFFE6FBF5),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              const FanFileCards(),
              const SizedBox(height: 14),
              Text(
                'Choisir un fichier',
                style: GoogleFonts.baloo2(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Glisser-déposer ou parcourir',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const dashWidth = 7.0, gapWidth = 6.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.file, required this.onRemove});
  final PlatformFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final sizeMb = (file.lengthSync() ?? 0) / (1024 * 1024);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.06),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(
                Icons.picture_as_pdf_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppTheme.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${sizeMb.toStringAsFixed(1)} Mo',
                  style: GoogleFonts.nunito(
                    color: AppTheme.ink.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFFE4E6),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Color(0xFFFF4B6E),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
