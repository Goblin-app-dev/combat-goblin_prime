import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:combat_goblin_prime/features/github_repository_search/models/repo_search_query.dart';
import 'package:combat_goblin_prime/features/github_repository_search/services/github_query_builder.dart';
import 'package:combat_goblin_prime/features/github_repository_search/services/github_repository_search_service_http.dart';
import 'package:combat_goblin_prime/ui/downloads/github_catalog_picker_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

http.Response _repoResponse(List<Map<String, dynamic>> items) => http.Response(
      jsonEncode({'total_count': items.length, 'items': items}),
      200,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _repoJson({
  required String fullName,
  String? description,
  int stars = 0,
}) =>
    {
      'full_name': fullName,
      'html_url': 'https://github.com/$fullName',
      'description': description,
      'language': null,
      'stargazers_count': stars,
      'forks_count': 0,
      'updated_at': '2025-01-01T00:00:00Z',
    };

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GitHubCatalogPickerScreen', () {
    testWidgets('shows search field and results on load',
        (WidgetTester tester) async {
      final client = MockClient((_) async => _repoResponse([
            _repoJson(
              fullName: 'BSData/wh40k-10e',
              description: 'Warhammer 40,000 10th Edition',
              stars: 120,
            ),
            _repoJson(
              fullName: 'BSData/aos-4e',
              description: 'Age of Sigmar 4th Edition',
              stars: 45,
            ),
          ]));

      await tester.pumpWidget(
        MaterialApp(
          home: GitHubCatalogPickerScreen.withService(
            GitHubRepositorySearchServiceHttp(
              client: client,
              queryBuilder: GitHubQueryBuilder(),
            ),
          ),
        ),
      );

      // Loading indicator shown initially.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Settle HTTP call.
      await tester.pumpAndSettle();

      // Search field visible.
      expect(find.byType(TextField), findsOneWidget);
      // fullName is lowercased by the service.
      expect(find.text('bsdata/wh40k-10e'), findsOneWidget);
      expect(find.text('bsdata/aos-4e'), findsOneWidget);
    });

    testWidgets('returns selected repository URL on tap',
        (WidgetTester tester) async {
      final client = MockClient((_) async => _repoResponse([
            _repoJson(fullName: 'BSData/wh40k-10e', stars: 10),
          ]));

      String? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => GitHubCatalogPickerScreen.withService(
                      GitHubRepositorySearchServiceHttp(
                        client: client,
                        queryBuilder: GitHubQueryBuilder(),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap the result tile (fullName is lowercased by the service).
      await tester.tap(find.text('bsdata/wh40k-10e'));
      await tester.pumpAndSettle();

      // htmlUrl preserves the original casing from the JSON response.
      expect(result, 'https://github.com/BSData/wh40k-10e');
    });

    testWidgets('shows error state when network fails',
        (WidgetTester tester) async {
      final client = MockClient((_) async =>
          http.Response('', 503, headers: {'content-type': 'application/json'}));

      await tester.pumpWidget(
        MaterialApp(
          home: GitHubCatalogPickerScreen.withService(
            GitHubRepositorySearchServiceHttp(
              client: client,
              queryBuilder: GitHubQueryBuilder(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('uses bsdataDiscovery mode (canonical query sent to GitHub)',
        (WidgetTester tester) async {
      late Uri capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return _repoResponse([]);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: GitHubCatalogPickerScreen.withService(
            GitHubRepositorySearchServiceHttp(
              client: client,
              queryBuilder: GitHubQueryBuilder(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        capturedUri.queryParameters['q'],
        GitHubQueryBuilder.canonicalBsdataQuery,
      );
    });
  });
}
