import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/models/source_locator.dart';
import 'package:combat_goblin_prime/services/bsd_resolver_service.dart';

void main() {
  const testSourceLocator = SourceLocator(
    sourceKey: 'test_repo',
    sourceUrl: 'https://github.com/TestOwner/test-repo',
    branch: 'main',
  );

  /// Sample XML head for a catalogue file (partial content, <2KB).
  const sampleCatalogueXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<catalogue id="abc123-def456" name="Test Catalogue" library="false">
  <!-- content truncated -->
''';

  /// Sample XML head for a gameSystem file.
  const sampleGameSystemXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<gameSystem id="gamesys-root-id" name="Test Game System">
  <!-- content truncated -->
''';

  /// Creates a mock GitHub Trees API response.
  String mockTreeResponse(List<String> filePaths) {
    final tree = filePaths.map((path) {
      return {
        'path': path,
        'type': 'blob',
        'sha': 'mock-sha-${path.hashCode}',
      };
    }).toList();

    return json.encode({
      'sha': 'mock-tree-sha',
      'tree': tree,
      'truncated': false,
    });
  }

  group('BsdResolverService: cache behavior', () {
    test('cache hit returns without network call', () async {
      var networkCallCount = 0;
      final fullContent = 'Full catalog content here';

      final mockClient = MockClient((request) async {
        networkCallCount++;

        if (request.url.path.contains('/git/trees/')) {
          return http.Response(
            mockTreeResponse(['Imperium - Space Marines.cat']),
            200,
          );
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          // Check if this is a range request or full fetch
          if (request.headers.containsKey('Range')) {
            return http.Response(sampleCatalogueXml, 206);
          } else {
            return http.Response(fullContent, 200);
          }
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);

      // First call to fetchCatalogBytes: builds index and fetches file
      final bytes1 = await service.fetchCatalogBytes(
        sourceLocator: testSourceLocator,
        targetId: 'abc123-def456',
      );
      expect(bytes1, isNotNull);
      expect(String.fromCharCodes(bytes1!), equals(fullContent));

      final callsAfterFirst = networkCallCount;
      // Should have: 1 tree fetch + 1 range fetch + 1 full fetch = 3
      expect(callsAfterFirst, equals(3));

      // Cache should now be populated
      final cachedIndex = service.getCachedIndex(testSourceLocator.sourceKey);
      expect(cachedIndex, isNotNull);
      expect(cachedIndex!['abc123-def456'], 'Imperium - Space Marines.cat');

      // Second call should only fetch the file, not rebuild index
      networkCallCount = 0;

      final bytes2 = await service.fetchCatalogBytes(
        sourceLocator: testSourceLocator,
        targetId: 'abc123-def456',
      );
      expect(bytes2, isNotNull);

      print('[TEST] Network calls for cached fetch: $networkCallCount');
      // Should only be 1 call (the actual file fetch), not 3 (tree + range + file)
      expect(networkCallCount, equals(1));
    });

    test('clearCache forces network call on next request', () async {
      var networkCallCount = 0;

      final mockClient = MockClient((request) async {
        networkCallCount++;

        if (request.url.path.contains('/git/trees/')) {
          return http.Response(
            mockTreeResponse(['Test.cat']),
            200,
          );
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          return http.Response(sampleCatalogueXml, 206);
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);

      // Build index first time
      await service.buildRepoIndex(testSourceLocator);
      final callsAfterFirst = networkCallCount;

      // Clear cache
      service.clearCache();
      expect(service.getCachedIndex(testSourceLocator.sourceKey), isNull);

      // Build index again - should hit network
      networkCallCount = 0;
      await service.buildRepoIndex(testSourceLocator);
      expect(networkCallCount, equals(callsAfterFirst));
    });
  });

  group('BsdResolverService: partial index early termination', () {
    test('stops once all needed ids found', () async {
      var rangeFetchCount = 0;

      // 10 files, but we only need 2 IDs
      final catFiles = List.generate(10, (i) => 'Catalog_$i.cat');

      // ID mapping: Catalog_3 -> id-003, Catalog_7 -> id-007
      final idMapping = <String, String>{
        'Catalog_3.cat': 'id-003',
        'Catalog_7.cat': 'id-007',
      };

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response(mockTreeResponse(catFiles), 200);
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          rangeFetchCount++;
          final path = request.url.pathSegments.last;

          final catalogueId = idMapping[path];
          if (catalogueId != null) {
            return http.Response(
              '<?xml version="1.0"?><catalogue id="$catalogueId" name="Test"/>',
              206,
            );
          }
          // Return a different ID for other files
          return http.Response(
            '<?xml version="1.0"?><catalogue id="other-${path.hashCode}" name="Test"/>',
            206,
          );
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      final neededIds = {'id-003', 'id-007'};

      var progressCalls = <(int, int)>[];
      final result = await service.buildPartialIndex(
        testSourceLocator,
        neededIds,
        onProgress: (found, needed) {
          progressCalls.add((found, needed));
        },
      );

      expect(result, isNotNull);
      expect(result!.containsKey('id-003'), isTrue);
      expect(result.containsKey('id-007'), isTrue);

      // Should have terminated early - not fetched all 10 files
      // Files are processed in order: 0,1,2,3 (finds id-003),4,5,6,7 (finds id-007), then stops
      // So we should see 8 range fetches max (indices 0-7)
      print('[TEST] Range fetch count: $rangeFetchCount');
      expect(rangeFetchCount, lessThanOrEqualTo(8));

      // Progress callbacks should report found/needed correctly
      expect(progressCalls.isNotEmpty, isTrue);
      expect(progressCalls.last, equals((2, 2)));
    });

    test('returns all found IDs even if not all requested', () async {
      final catFiles = ['A.cat', 'B.cat'];

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response(mockTreeResponse(catFiles), 200);
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          final path = request.url.pathSegments.last;
          if (path == 'A.cat') {
            return http.Response(
              '<?xml version="1.0"?><catalogue id="id-A" name="A"/>',
              206,
            );
          }
          if (path == 'B.cat') {
            return http.Response(
              '<?xml version="1.0"?><catalogue id="id-B" name="B"/>',
              206,
            );
          }
        }
        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);

      // Request 3 IDs, but only 2 exist
      final result = await service.buildPartialIndex(
        testSourceLocator,
        {'id-A', 'id-B', 'id-nonexistent'},
      );

      expect(result, isNotNull);
      expect(result!.length, equals(2));
      expect(result['id-A'], equals('A.cat'));
      expect(result['id-B'], equals('B.cat'));
    });
  });

  group('BsdResolverService: range fetch parsing', () {
    test('extracts catalogue id from partial XML', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response(mockTreeResponse(['Test.cat']), 200);
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          // Verify Range header is set
          expect(request.headers['Range'], equals('bytes=0-2047'));
          return http.Response(sampleCatalogueXml, 206);
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      final result = await service.buildRepoIndex(testSourceLocator);

      expect(result, isNotNull);
      expect(result!.targetIdToPath['abc123-def456'], equals('Test.cat'));
      expect(result.unparsedFiles, isEmpty);
    });

    test('extracts gameSystem id from partial XML', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response(mockTreeResponse(['Game.cat']), 200);
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          return http.Response(sampleGameSystemXml, 206);
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      final result = await service.buildRepoIndex(testSourceLocator);

      expect(result, isNotNull);
      expect(result!.targetIdToPath['gamesys-root-id'], equals('Game.cat'));
    });

    test('handles 200 response (full content) same as 206', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response(mockTreeResponse(['Full.cat']), 200);
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          // Some servers don't support Range and return full content with 200
          return http.Response(sampleCatalogueXml, 200);
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      final result = await service.buildRepoIndex(testSourceLocator);

      expect(result, isNotNull);
      expect(result!.targetIdToPath['abc123-def456'], equals('Full.cat'));
    });

    test('reports unparsed files when id cannot be extracted', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response(mockTreeResponse(['Invalid.cat']), 200);
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          // Return invalid XML without id attribute
          return http.Response('<?xml version="1.0"?><something/>', 206);
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      final result = await service.buildRepoIndex(testSourceLocator);

      expect(result, isNotNull);
      expect(result!.targetIdToPath, isEmpty);
      expect(result.unparsedFiles, contains('Invalid.cat'));
    });

    test('handles various id attribute formats', () async {
      final testCases = [
        // Standard format
        ('<catalogue id="test-id-1" name="Test"/>', 'test-id-1'),
        // With newlines and whitespace
        ('<catalogue\n  id="test-id-2"\n  name="Test"/>', 'test-id-2'),
        // With other attributes before id
        ('<catalogue name="Test" id="test-id-3" library="false"/>', 'test-id-3'),
        // Complex id with hyphens and numbers
        ('<catalogue id="b00-cd86-4b4c-97ba" name="Agents"/>', 'b00-cd86-4b4c-97ba'),
      ];

      for (final (xml, expectedId) in testCases) {
        final mockClient = MockClient((request) async {
          if (request.url.path.contains('/git/trees/')) {
            return http.Response(mockTreeResponse(['Test.cat']), 200);
          }

          if (request.url.host == 'raw.githubusercontent.com') {
            return http.Response('<?xml version="1.0"?>$xml', 206);
          }

          return http.Response('Not found', 404);
        });

        final service = BsdResolverService(client: mockClient);
        final result = await service.buildRepoIndex(testSourceLocator);

        expect(result, isNotNull, reason: 'Failed for XML: $xml');
        expect(result!.targetIdToPath[expectedId], equals('Test.cat'),
            reason: 'Failed to extract id "$expectedId" from: $xml');
      }
    });
  });

  group('BsdResolverService: deterministic ordering', () {
    test('tree paths processed in stable order', () async {
      // Files in tree response (order matters)
      final catFiles = [
        'z_last.cat',
        'a_first.cat',
        'm_middle.cat',
        'subdir/nested.cat',
      ];

      var processOrder = <String>[];

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response(mockTreeResponse(catFiles), 200);
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          final path = request.url.path
              .replaceFirst('/TestOwner/test-repo/main/', '');
          processOrder.add(path);
          return http.Response(
            '<?xml version="1.0"?><catalogue id="id-$path" name="Test"/>',
            206,
          );
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      await service.buildRepoIndex(testSourceLocator);

      // Order should match input tree order (as returned by GitHub API)
      expect(processOrder, equals(catFiles));
    });

    test('partial index respects tree order for early termination', () async {
      final catFiles = [
        'z_last.cat',      // id-z
        'a_first.cat',     // id-a (target)
        'm_middle.cat',    // id-m
        'b_second.cat',    // id-b (target)
      ];

      var processOrder = <String>[];

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response(mockTreeResponse(catFiles), 200);
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          final path = request.url.pathSegments.last;
          processOrder.add(path);

          final idMap = {
            'z_last.cat': 'id-z',
            'a_first.cat': 'id-a',
            'm_middle.cat': 'id-m',
            'b_second.cat': 'id-b',
          };

          return http.Response(
            '<?xml version="1.0"?><catalogue id="${idMap[path]}" name="Test"/>',
            206,
          );
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      await service.buildPartialIndex(
        testSourceLocator,
        {'id-a', 'id-b'},
      );

      // Should process z_last, a_first, m_middle, b_second in that order
      // and stop after finding id-b
      expect(processOrder, equals(['z_last.cat', 'a_first.cat', 'm_middle.cat', 'b_second.cat']));
    });

    test('result map has deterministic key order', () async {
      final catFiles = ['b.cat', 'a.cat', 'c.cat'];

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response(mockTreeResponse(catFiles), 200);
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          final path = request.url.pathSegments.last;
          final id = 'id-${path.replaceAll('.cat', '')}';
          return http.Response(
            '<?xml version="1.0"?><catalogue id="$id" name="Test"/>',
            206,
          );
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      final result1 = await service.buildRepoIndex(testSourceLocator);
      service.clearCache();
      final result2 = await service.buildRepoIndex(testSourceLocator);

      // Maps should have same entries
      expect(result1!.targetIdToPath, equals(result2!.targetIdToPath));

      // Key iteration order should be deterministic (insertion order in Dart)
      expect(result1.targetIdToPath.keys.toList(),
          equals(result2.targetIdToPath.keys.toList()));
    });
  });

  group('BsdResolverService: error handling', () {
    test('returns null on empty sourceUrl', () async {
      const emptySource = SourceLocator(
        sourceKey: 'empty',
        sourceUrl: '',
      );

      final service = BsdResolverService();
      final result = await service.buildRepoIndex(emptySource);
      expect(result, isNull);
    });

    test('returns null on invalid GitHub URL', () async {
      const invalidSource = SourceLocator(
        sourceKey: 'invalid',
        sourceUrl: 'https://gitlab.com/some/repo',
      );

      final service = BsdResolverService();
      final result = await service.buildRepoIndex(invalidSource);
      expect(result, isNull);
    });

    test('returns null on Trees API failure', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response('Not found', 404);
        }
        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      final result = await service.buildRepoIndex(testSourceLocator);
      expect(result, isNull);
    });

    test('gracefully handles range fetch errors', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response(mockTreeResponse(['Error.cat']), 200);
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          throw Exception('Network error');
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      final result = await service.buildRepoIndex(testSourceLocator);

      expect(result, isNotNull);
      expect(result!.targetIdToPath, isEmpty);
      expect(result.unparsedFiles, contains('Error.cat'));
    });
  });

  group('BsdResolverService: fetchCatalogBytes', () {
    test('fetches full file content after index lookup', () async {
      final fullContent = 'Full catalog content here with many bytes...';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response(mockTreeResponse(['Test.cat']), 200);
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          // Check if this is a range request or full fetch
          if (request.headers.containsKey('Range')) {
            return http.Response(sampleCatalogueXml, 206);
          } else {
            return http.Response(fullContent, 200);
          }
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      final bytes = await service.fetchCatalogBytes(
        sourceLocator: testSourceLocator,
        targetId: 'abc123-def456',
      );

      expect(bytes, isNotNull);
      expect(String.fromCharCodes(bytes!), equals(fullContent));
    });

    test('returns null for unknown targetId', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/git/trees/')) {
          return http.Response(mockTreeResponse(['Test.cat']), 200);
        }

        if (request.url.host == 'raw.githubusercontent.com') {
          return http.Response(sampleCatalogueXml, 206);
        }

        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      final bytes = await service.fetchCatalogBytes(
        sourceLocator: testSourceLocator,
        targetId: 'nonexistent-id',
      );

      expect(bytes, isNull);
    });
  });

  group('BsdResolverService: fetchFileByPath', () {
    test('returns bytes on 200 response', () async {
      const content = 'game data file content';

      final mockClient = MockClient((request) async {
        if (request.url.host == 'raw.githubusercontent.com') {
          return http.Response(content, 200);
        }
        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      final bytes = await service.fetchFileByPath(
        testSourceLocator,
        'Imperium - Space Marines.cat',
      );

      expect(bytes, isNotNull);
      expect(String.fromCharCodes(bytes!), equals(content));
    });

    test('returns null on 404 and sets lastError', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);
      expect(service.lastError, isNull);

      final bytes = await service.fetchFileByPath(
        testSourceLocator,
        'missing.cat',
      );

      expect(bytes, isNull);
      expect(service.lastError, isNotNull);
      expect(
        service.lastError!.code,
        equals(BsdResolverErrorCode.notFound),
      );
    });

    test('clears lastError before each call', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) return http.Response('Not found', 404);
        return http.Response('content', 200);
      });

      final service = BsdResolverService(client: mockClient);

      // First call fails — sets lastError
      await service.fetchFileByPath(testSourceLocator, 'missing.cat');
      expect(service.lastError, isNotNull);

      // Second call succeeds — lastError must be cleared
      final bytes =
          await service.fetchFileByPath(testSourceLocator, 'found.cat');
      expect(bytes, isNotNull);
      expect(service.lastError, isNull);
    });

    test('has no storage side effects (does not populate index cache)', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'raw.githubusercontent.com') {
          return http.Response('content', 200);
        }
        return http.Response('Not found', 404);
      });

      final service = BsdResolverService(client: mockClient);

      await service.fetchFileByPath(testSourceLocator, 'file.cat');
      await service.fetchFileByPath(testSourceLocator, 'file.cat');

      // fetchFileByPath must not populate the repo index cache
      expect(service.getCachedIndex(testSourceLocator.sourceKey), isNull);
    });
  });
}
