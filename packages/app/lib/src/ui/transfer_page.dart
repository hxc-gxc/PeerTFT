import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/transfer_session.dart';
import 'complete_page.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Transfert')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (state) {
          Negotiating() => _negotiatingView(),
          Transferring(
            :final fileName,
            :final totalBytes,
            :final transferredBytes,
            :final throughputBps,
          ) =>
            _transferringView(
              fileName,
              totalBytes,
              transferredBytes,
              throughputBps,
            ),
          Failed(:final message) => _failedView(context, message, ref),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _negotiatingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Négociation de la connexion…'),
        ],
      ),
    );
  }

  Widget _transferringView(
    String fileName,
    int totalBytes,
    int transferred,
    double bps,
  ) {
    final progress = totalBytes > 0 ? transferred / totalBytes : 0.0;
    final mbps = bps / (1024 * 1024);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swap_vert, size: 48, color: Colors.teal.shade400),
          const SizedBox(height: 16),
          Text(
            fileName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          LinearProgressIndicator(value: progress, minHeight: 8),
          const SizedBox(height: 8),
          Text('${_fmtBytes(transferred)} / ${_fmtBytes(totalBytes)}'),
          if (mbps > 0)
            Text(
              '${mbps.toStringAsFixed(1)} Mo/s',
              style: const TextStyle(color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _failedView(BuildContext context, String message, WidgetRef ref) {
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
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Retour'),
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
