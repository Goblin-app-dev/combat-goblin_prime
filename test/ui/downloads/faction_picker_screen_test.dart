import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/models/source_locator.dart';
import 'package:combat_goblin_prime/ui/downloads/faction_picker_screen.dart';
import 'package:combat_goblin_prime/ui/import/import_session_controller.dart';
import 'package:combat_goblin_prime/ui/import/import_session_provider.dart';

void main() {
  group('FactionPickerScreen: acceptance test 2 — no "library" visible in UI',
      () {
    testWidgets(
        'no rendered text contains "library" when factions include library paths',
        (WidgetTester tester) async {
      // Factions with library paths — the word "library" must never surface.
      final factions = [
        FactionOption(
          displayName: 'Tyranids',
          primaryPath: 'Tyranids.cat',
          libraryPaths: const ['Library - Tyranids.cat'],
        ),
        FactionOption(
          displayName: 'Chaos - Chaos Knights',
          primaryPath: 'Chaos - Chaos Knights.cat',
          libraryPaths: const ['Chaos - Chaos Knights - Library.cat'],
        ),
        FactionOption(
          displayName: 'Orks',
          primaryPath: 'Orks.cat',
        ),
      ];

      const locator = SourceLocator(
        sourceKey: 'test',
        sourceUrl: 'https://example.com/test',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ImportSessionProvider(
            controller: ImportSessionController(),
            child: FactionPickerScreen(
              slotIndex: 0,
              factions: factions,
              locator: locator,
            ),
          ),
        ),
      );

      // Collect every Text widget rendered on screen and assert none contain
      // "library" (case-insensitive).
      final renderedTexts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();

      for (final text in renderedTexts) {
        expect(
          text.toLowerCase(),
          isNot(contains('library')),
          reason: 'Rendered text "$text" must not contain "library"',
        );
      }
    });
  });
}
