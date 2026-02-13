import 'dart:convert';

import 'package:combat_goblin_prime/features/github_repository_search/models/repo_search_error.dart';
import 'package:combat_goblin_prime/features/github_repository_search/models/repo_search_exception.dart';
import 'package:combat_goblin_prime/features/github_repository_search/models/repo_search_query.dart';
import 'package:combat_goblin_prime/features/github_repository_search/services/github_query_builder.dart';
import 'package:combat_goblin_prime/features/github_repository_search/services/github_repository_search_service_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('GitHubRepositorySearchServiceHttp', () {
    test('sends required headers and parses successful response', () async {
      late Uri capturedUri;
      late Map<String, String> capturedHeaders;

      final client = MockClient((request) async {
        capturedUri = request.url;
        capturedHeaders = request.headers;
        return http.Response(
          jsonEncode({
            'total_count': 1,
            'items': [
              {
                'full_name': 'Owner/Repo',
                'html_url': 'https://github.com/Owner/Repo',
                'description': '  neat package  ',
                'language': 'Dart',
                'stargazers_count': 42,
                'forks_count': 7,
                'updated_at': '2026-02-14T10:00:00Z',
              }
            ],
          }),
          200,
          headers: {
            'x-ratelimit-remaining': '9',
            'x-ratelimit-reset': '12345',
            'x-github-request-id': 'abc123',
          },
        );
      });

      final service = GitHubRepositorySearchServiceHttp(
        client: client,
        queryBuilder: GitHubQueryBuilder(),
        authTokenProvider: () => 'secret-token',
      );

      final page = await service.search(query: const RepoSearchQuery());

      expect(capturedHeaders['Accept'], 'application/vnd.github+json');
      expect(capturedHeaders['X-GitHub-Api-Version'], '2022-11-28');
      expect(capturedHeaders['Authorization'], 'Bearer secret-token');

      expect(capturedUri.queryParameters['per_page'], '30');
      expect(capturedUri.queryParameters['sort'], 'stars');
      expect(capturedUri.queryParameters['order'], 'desc');

      expect(page.items.single.fullName, 'owner/repo');
      expect(page.items.single.description, 'neat package');
      expect(page.nextPageToken, null);
      expect(page.isLastPage, isTrue);
      expect(page.diagnostics?.requestId, 'abc123');
    });

    test('maps 403 to forbidden when not rate-limited', () async {
      final client = MockClient(
        (_) async => http.Response('forbidden', 403),
      );
      final service = GitHubRepositorySearchServiceHttp(
        client: client,
        queryBuilder: GitHubQueryBuilder(),
      );

      expect(
        () => service.search(query: const RepoSearchQuery()),
        throwsA(
          isA<RepoSearchException>()
              .having((e) => e.error, 'error', RepoSearchError.forbidden),
        ),
      );
    });

    test('maps 403 with rate headers to rateLimited', () async {
      final client = MockClient(
        (_) async => http.Response('rate', 403, headers: {'x-ratelimit-remaining': '0'}),
      );
      final service = GitHubRepositorySearchServiceHttp(
        client: client,
        queryBuilder: GitHubQueryBuilder(),
      );

      expect(
        () => service.search(query: const RepoSearchQuery()),
        throwsA(
          isA<RepoSearchException>()
              .having((e) => e.error, 'error', RepoSearchError.rateLimited),
        ),
      );
    });

    test('maps invalid json to invalidResponse', () async {
      final client = MockClient((_) async => http.Response('not-json', 200));
      final service = GitHubRepositorySearchServiceHttp(
        client: client,
        queryBuilder: GitHubQueryBuilder(),
      );

      expect(
        () => service.search(query: const RepoSearchQuery()),
        throwsA(
          isA<RepoSearchException>()
              .having((e) => e.error, 'error', RepoSearchError.invalidResponse),
        ),
      );
    });

    test('does not expose auth token in exception message', () async {
      final client = MockClient((_) async => http.Response('nope', 401));
      final service = GitHubRepositorySearchServiceHttp(
        client: client,
        queryBuilder: GitHubQueryBuilder(),
        authTokenProvider: () => 'top-secret',
      );

      try {
        await service.search(query: const RepoSearchQuery());
      } on RepoSearchException catch (e) {
        expect(e.toString(), isNot(contains('top-secret')));
        expect(e.toString(), isNot(contains('Authorization')));
      }
    });
  });
}
