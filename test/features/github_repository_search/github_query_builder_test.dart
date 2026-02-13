import 'package:combat_goblin_prime/features/github_repository_search/models/repo_search_query.dart';
import 'package:combat_goblin_prime/features/github_repository_search/services/github_query_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GitHubQueryBuilder', () {
    final builder = GitHubQueryBuilder();

    test('builds canonical default flutter query byte-for-byte', () {
      const query = RepoSearchQuery();
      expect(builder.build(query),
          'language:dart topic:flutter archived:false');
    });

    test('builds canonical fallback query byte-for-byte', () {
      const query = RepoSearchQuery(useFallbackFlutterQuery: true);
      expect(builder.build(query),
          'flutter in:name,description,readme language:dart archived:false');
    });

    test('applies deterministic qualifier ordering for dynamic query', () {
      const query = RepoSearchQuery(text: 'awesome-flutter');
      expect(builder.build(query),
          'archived:false language:dart topic:flutter "awesome-flutter"');
    });

    test('escapes quotes and keeps unicode', () {
      const query = RepoSearchQuery(text: 'Café "toolkit":flutter');
      expect(builder.build(query),
          'archived:false language:dart topic:flutter "Café \\\"toolkit\\\":flutter"');
    });
  });
}
