import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/transfer_session.dart';

class CompletePage extends ConsumerWidget {
  const CompletePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transferSessionProvider);
    if (state is! Complete) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Terminé')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                state.hashMatch ? Icons.check_circle : Icons.warning,
                size: 64,
                color: state.hashMatch ? Colors.green : Colors.orange,
              ),
              const SizedBox(height: 16),
              Text(
                state.hashMatch ? 'Transfert réussi' : 'Intégrité incertaine',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              if (state.savedPath != null) ...[
                Text(
                  'Fichier enregistré:',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  state.savedPath!,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'SHA-256:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              SelectableText(
                state.sha256Received,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () {
                  ref.read(transferSessionProvider.notifier).cancel();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('Terminer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
