import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/transfer_session.dart';
import 'transfer_page.dart';

class SendPage extends ConsumerStatefulWidget {
  const SendPage({super.key});

  @override
  ConsumerState<SendPage> createState() => _SendPageState();
}

class _SendPageState extends ConsumerState<SendPage> {
  bool _started = false;

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

    return Scaffold(
      appBar: AppBar(title: const Text('Envoyer')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (state) {
          Idle() => _pickFileView(context),
          Connecting() => const Center(child: CircularProgressIndicator()),
          WaitingForPeer(:final code) => _waitingView(code),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _pickFileView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choisir un fichier'),
          ),
        ],
      ),
    );
  }

  Widget _waitingView(String code) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Code de transfert', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        SelectableText(
          code,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        QrImageView(data: code, version: QrVersions.auto, size: 200),
        const SizedBox(height: 24),
        const Text(
          'En attente du récepteur…',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;
    _started = true;
    ref
        .read(transferSessionProvider.notifier)
        .startSend(result.files.single.path!);
  }
}
