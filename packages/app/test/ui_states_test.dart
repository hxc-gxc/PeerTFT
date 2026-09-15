import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/src/state/transfer_session.dart';
import 'package:app/src/ui/receive_page.dart';
import 'package:app/src/ui/send_page.dart';
import 'package:app/src/ui/transfer_page.dart';

/// Minimal stub so widget tests can set any [TransferState] without touching
/// platform channels (WebRTC, file picker, WebSocket).
class _StubSession extends TransferSession {
  _StubSession(this._initial);
  final TransferState _initial;

  @override
  TransferState build() => _initial;

  @override
  Future<void> startSend(PlatformFile platformFile) async {}

  @override
  Future<void> startReceive(String code) async {}

  @override
  Future<void> cancel() async {
    state = const Idle();
  }
}

Widget _app(Widget page, TransferState initialState) => ProviderScope(
  overrides: [
    transferSessionProvider.overrideWith(() => _StubSession(initialState)),
  ],
  child: MaterialApp(home: page),
);

void main() {
  group('SendPage', () {
    testWidgets(
      'Failed state: shows error message and Réessayer button, no spinner',
      (tester) async {
        await tester.pumpWidget(_app(const SendPage(), const Failed('oops')));
        await tester.pump();

        expect(find.text('oops'), findsOneWidget);
        expect(find.text('Réessayer'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('WaitingForPeer state: shows cancel button', (tester) async {
      await tester.pumpWidget(
        _app(
          const SendPage(),
          const WaitingForPeer(code: 'renard-lampe-abc', isInitiator: true),
        ),
      );
      await tester.pump();

      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets('Réessayer button resets to file picker', (tester) async {
      await tester.pumpWidget(_app(const SendPage(), const Failed('oops')));
      await tester.pump();

      await tester.tap(find.text('Réessayer'));
      await tester.pump();

      expect(find.text('Choisir un fichier'), findsOneWidget);
    });
  });

  group('ReceivePage', () {
    testWidgets(
      'Failed state: shows error message and Réessayer button, no spinner',
      (tester) async {
        await tester.pumpWidget(
          _app(const ReceivePage(), const Failed('connexion perdue')),
        );
        await tester.pump();

        expect(find.text('connexion perdue'), findsOneWidget);
        expect(find.text('Réessayer'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('WaitingForPeer state: shows cancel button', (tester) async {
      await tester.pumpWidget(
        _app(
          const ReceivePage(),
          const WaitingForPeer(code: 'renard-lampe-abc', isInitiator: false),
        ),
      );
      await tester.pump();

      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets('Réessayer button resets to code input', (tester) async {
      await tester.pumpWidget(
        _app(const ReceivePage(), const Failed('connexion perdue')),
      );
      await tester.pump();

      await tester.tap(find.text('Réessayer'));
      await tester.pump();

      expect(find.text('Code de transfert'), findsOneWidget);
    });
  });

  group('TransferPage', () {
    testWidgets(
      'Reconnecting state: shows countdown and keeps cancel working',
      (tester) async {
        final deadline = DateTime.now().add(const Duration(seconds: 12));
        await tester.pumpWidget(
          _app(const TransferPage(), Reconnecting(deadline: deadline)),
        );
        await tester.pump();

        expect(find.text('Reconnexion en cours…'), findsOneWidget);
        expect(find.text('Annuler'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.tap(find.text('Annuler'));
        await tester.pump();
        // _StubSession.cancel() sets state back to Idle -- TransferPage's
        // switch falls through to the generic catch-all spinner for any
        // state it doesn't name explicitly (Idle included), so the
        // Reconnecting-specific text/countdown must be gone even though a
        // (different) CircularProgressIndicator is still shown.
        expect(find.text('Reconnexion en cours…'), findsNothing);
      },
    );
  });
}
