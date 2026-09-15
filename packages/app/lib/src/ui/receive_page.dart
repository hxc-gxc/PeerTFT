import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../platform/web_save.dart';
import '../platform/web_save_stub.dart'
    if (dart.library.html) '../platform/web_save_web.dart';
import '../state/transfer_session.dart';
import '../theme/app_theme.dart';
import 'send_page.dart';
import 'transfer_page.dart';
import 'widgets/app_scaffold.dart';
import 'widgets/bottom_nav_bar.dart';
import 'widgets/decorations.dart';
import 'widgets/gradient_button.dart';

class ReceivePage extends ConsumerStatefulWidget {
  const ReceivePage({super.key});

  @override
  ConsumerState<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends ConsumerState<ReceivePage> {
  final _codeController = TextEditingController();
  bool _started = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transferSessionProvider);

    ref.listen<TransferState>(transferSessionProvider, (previous, next) {
      if (next is Negotiating && _started) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const TransferPage()),
        );
      }
    });

    return AppScaffold(
      backdrop: const Stack(
        children: [
          // Mint and Pink blobs at the top matching Mockup 4
          Positioned(
            top: -50,
            left: -30,
            child: Opacity(
              opacity: 0.55,
              child: BackgroundBlob(color: AppTheme.mint, size: 210),
            ),
          ),
          Positioned(
            top: -70,
            right: -50,
            child: Opacity(
              opacity: 0.5,
              child: BackgroundBlob(color: AppTheme.pink, size: 190),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -40,
            child: Opacity(
              opacity: 0.2,
              child: BackgroundBlob(color: AppTheme.indigo, size: 160),
            ),
          ),
          Positioned(
            bottom: 60,
            right: -20,
            child: Opacity(
              opacity: 0.25,
              child: BackgroundBlob(color: AppTheme.mint, size: 100),
            ),
          ),
          Positioned(
            bottom: 220,
            right: 36,
            child: Dot(color: AppTheme.indigo, opacity: 0.25),
          ),
        ],
      ),
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.ink),
        ),
        title: Text(
          'Recevoir',
          style: GoogleFonts.baloo2(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ),
      bottomNavigationBar: state is Idle
          ? PeerBottomNavBar(
              currentTab: NavTab.recevoir,
              onTabSelected: (_) => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const SendPage()),
              ),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: switch (state) {
          Idle() => _enterCodeView(context),
          Connecting() => const Center(
            child: CircularProgressIndicator(color: AppTheme.indigo),
          ),
          WaitingForPeer(:final code) => _waitingView(code),
          Failed(:final message) => _failedView(context, message),
          _ => const Center(
            child: CircularProgressIndicator(color: AppTheme.indigo),
          ),
        },
      ),
    );
  }

  Widget _enterCodeView(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              // Liquid organic blob illustration with specular gloss
              const ReceivingBlobIllustration(width: 130, height: 90),
              const SizedBox(height: 18),
              Text(
                'On récupère ton fichier',
                style: GoogleFonts.baloo2(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Entre le code reçu ou scanne le QR',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Code de transfert',
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _codeController,
                textAlign: TextAlign.left,
                style: GoogleFonts.baloo2(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
                decoration: InputDecoration(
                  hintText: 'ex. mangue-plafond-camion-aurore',
                  hintStyle: GoogleFonts.nunito(
                    color: AppTheme.ink.withValues(alpha: 0.4),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GradientButton(
                label: 'Rejoindre le transfert',
                colors: const [Color(0xFF582BE8), Color(0xFF7C3AED)],
                onPressed: _join,
              ),
              const SizedBox(height: 22),
              // Carousel / Indicator dots matching Mockup 4
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _indicatorDot(const Color(0xFF4EEDB2)),
                  const SizedBox(width: 8),
                  _indicatorDot(const Color(0xFFFF6B8B)),
                  const SizedBox(width: 8),
                  _indicatorDot(const Color(0xFF582BE8)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _indicatorDot(Color color) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _waitingView(String code) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              code,
              style: GoogleFonts.baloo2(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'En attente de l’émetteur…',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.ink.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            GradientButton(
              label: 'Annuler',
              colors: const [Color(0xFF582BE8), Color(0xFF7C3AED)],
              onPressed: () {
                ref.read(transferSessionProvider.notifier).cancel();
                setState(() => _started = false);
              },
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

  Future<void> _join() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    WebWritableSink? webSink;
    if (kIsWeb) {
      webSink = await pickWebSink(code); // first await in this handler --
      // showSaveFilePicker() needs transient user activation, which this
      // call must still be holding; see web_save_web.dart's doc comment.
    }
    _started = true;
    ref
        .read(transferSessionProvider.notifier)
        .startReceive(code, webSink: webSink);
  }
}
