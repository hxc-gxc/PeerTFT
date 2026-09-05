import 'package:flutter/material.dart';

import 'src/ui/handshake_test_page.dart';

/// Entry point for the section-13 throwaway prototype. Server addresses are
/// intentionally hardcoded to localhost: point them at your `docker compose`
/// stack (see the top-level README) or override them for a real deployment.
void main() {
  runApp(const PeerTftPrototypeApp());
}

class PeerTftPrototypeApp extends StatelessWidget {
  const PeerTftPrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PeerTFT prototype',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: HandshakeTestPage(
        signalingHttpUri: Uri.parse('http://localhost:8080'),
        signalingWsUri: Uri.parse('ws://localhost:8080/ws'),
        stunUri: 'stun:localhost:3478',
      ),
    );
  }
}
