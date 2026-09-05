import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/transfer_session.dart';
import 'transfer_page.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Recevoir')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (state) {
          Idle() => _enterCodeView(context),
          Connecting() => const Center(child: CircularProgressIndicator()),
          WaitingForPeer(:final code) => _waitingView(code),
          Failed(:final message) => _failedView(context, message),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _enterCodeView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Code de transfert',
              hintText: 'renard-bureau-lampe-zenith',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _join,
            icon: const Icon(Icons.link),
            label: const Text('Rejoindre'),
          ),
        ],
      ),
    );
  }

  Widget _waitingView(String code) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SelectableText(
          code,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        const Text(
          'En attente de l\'émetteur…',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () {
            ref.read(transferSessionProvider.notifier).cancel();
            setState(() => _started = false);
          },
          child: const Text('Annuler'),
        ),
      ],
    );
  }

  Widget _failedView(BuildContext context, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
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

  void _join() {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    _started = true;
    ref.read(transferSessionProvider.notifier).startReceive(code);
  }
}
