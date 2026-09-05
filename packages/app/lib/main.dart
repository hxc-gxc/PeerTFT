import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/ui/home_page.dart';

void main() {
  runApp(const ProviderScope(child: PeerTftApp()));
}

class PeerTftApp extends StatelessWidget {
  const PeerTftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PeerTFT',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomePage(),
    );
  }
}
