import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';

void main() {
  testWidgets('Home page shows send and receive buttons', (tester) async {
    await tester.pumpWidget(const PeerTftApp());
    await tester.pumpAndSettle();

    expect(find.text('Envoyer un fichier'), findsOneWidget);
    expect(find.text('Recevoir un fichier'), findsOneWidget);
  });
}
