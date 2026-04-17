/// HomeScreen voice-first UI tests
///
/// Verifies the structural properties of the voice-first home screen:
///
///   1. No TextField — text input removed entirely
///   2. No EditableText — no keyboard cursor surface anywhere
///   3. "Start Listening" button is rendered in initial idle state
///   4. "Start Listening" button is enabled (tap-able) in idle state
///   5. Display panel shows "No catalogs loaded" when no data is present
///   6. Slot status bar chips are visible at the bottom

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/ui/home/home_screen.dart';
import 'package:combat_goblin_prime/ui/import/import_session_controller.dart';
import 'package:combat_goblin_prime/ui/import/import_session_provider.dart';

Widget _buildTestApp() => MaterialApp(
      home: Scaffold(
        body: ImportSessionProvider(
          controller: ImportSessionController(),
          child: const HomeScreen(),
        ),
      ),
    );

void main() {
  group('HomeScreen — voice-first UI', () {
    testWidgets('1. no TextField in widget tree', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('2. no EditableText (no keyboard cursor)', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('3. Start Listening button rendered in idle state', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();
      expect(find.text('Start Listening'), findsOneWidget);
    });

    testWidgets('4. Start Listening button is enabled in idle state', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();
      final btn = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Start Listening'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(btn.onPressed, isNotNull,
          reason: 'Button must be tap-able when runtime is idle');
    });

    testWidgets('5. display panel shows No catalogs loaded when no data',
        (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();
      expect(find.text('No catalogs loaded'), findsOneWidget);
    });

    testWidgets('6. slot status bar is visible with empty slot chips',
        (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();
      // Status bar renders one chip per slot; all start empty.
      expect(find.textContaining('Slot'), findsWidgets);
    });
  });
}
