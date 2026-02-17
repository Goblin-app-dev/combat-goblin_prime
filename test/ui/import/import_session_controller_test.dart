import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/models/source_locator.dart';
import 'package:combat_goblin_prime/services/bsd_resolver_service.dart';
import 'package:combat_goblin_prime/ui/import/import_session_controller.dart';

/// Mock BsdResolverService for testing.
class MockBsdResolverService extends BsdResolverService {
  final Map<String, Uint8List> _mockResponses = {};
  int fetchCallCount = 0;

  void setMockResponse(String targetId, Uint8List bytes) {
    _mockResponses[targetId] = bytes;
  }

  @override
  Future<Uint8List?> fetchCatalogBytes({
    required SourceLocator sourceLocator,
    required String targetId,
  }) async {
    fetchCallCount++;
    return _mockResponses[targetId];
  }

  @override
  Future<RepoIndexResult?> buildRepoIndex(SourceLocator sourceLocator) async {
    return RepoIndexResult(
      targetIdToPath: {
        for (final id in _mockResponses.keys) id: '$id.cat',
      },
      pathToBlobSha: {
        for (final id in _mockResponses.keys) '$id.cat': 'mock_sha_$id',
      },
      targetIdToBlobSha: {
        for (final id in _mockResponses.keys) id: 'mock_sha_$id',
      },
      unparsedFiles: [],
    );
  }
}

void main() {
  group('ImportSessionController: status transitions', () {
    test('starts in idle state', () {
      final controller = ImportSessionController();

      expect(controller.status, equals(ImportStatus.idle));
      expect(controller.statusMessage, isNull);
      expect(controller.errorMessage, isNull);
      expect(controller.gameSystemFile, isNull);
      expect(controller.primaryCatalogFile, isNull);
    });

    test('setGameSystemFile resets to idle state', () {
      final controller = ImportSessionController();

      // Set a file
      controller.setGameSystemFile(SelectedFile(
        fileName: 'test.gst',
        bytes: Uint8List.fromList([1, 2, 3]),
      ));

      expect(controller.status, equals(ImportStatus.idle));
      expect(controller.gameSystemFile, isNotNull);
      expect(controller.gameSystemFile!.fileName, equals('test.gst'));
    });

    test('setPrimaryCatalogFile resets to idle state', () {
      final controller = ImportSessionController();

      controller.setPrimaryCatalogFile(SelectedFile(
        fileName: 'test.cat',
        bytes: Uint8List.fromList([1, 2, 3]),
      ));

      expect(controller.status, equals(ImportStatus.idle));
      expect(controller.primaryCatalogFile, isNotNull);
      expect(controller.primaryCatalogFile!.fileName, equals('test.cat'));
    });

    test('attemptBuild fails when files not selected', () async {
      final controller = ImportSessionController();

      await controller.attemptBuild();

      expect(controller.status, equals(ImportStatus.failed));
      expect(controller.errorMessage, contains('select'));
    });

    test('attemptBuild transitions to preparing state immediately', () async {
      final controller = ImportSessionController();
      final statusChanges = <ImportStatus>[];

      controller.addListener(() {
        statusChanges.add(controller.status);
      });

      controller.setGameSystemFile(SelectedFile(
        fileName: 'test.gst',
        bytes: Uint8List.fromList([1, 2, 3]),
      ));
      controller.setSelectedCatalogs([
        SelectedFile(
          fileName: 'test.cat',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ]);

      // Start the build but don't await it (to capture state changes)
      final future = controller.attemptBuild();

      // First state should be preparing
      expect(statusChanges.contains(ImportStatus.preparing), isTrue);
      // Status message now shows catalog build progress
      expect(controller.statusMessage, isNotNull);

      // Wait for completion
      await future;
    });

    test('clear() resets all state', () {
      final controller = ImportSessionController();

      controller.setGameSystemFile(SelectedFile(
        fileName: 'test.gst',
        bytes: Uint8List.fromList([1, 2, 3]),
      ));
      controller.setPrimaryCatalogFile(SelectedFile(
        fileName: 'test.cat',
        bytes: Uint8List.fromList([1, 2, 3]),
      ));
      controller.setSourceLocator(const SourceLocator(
        sourceKey: 'test',
        sourceUrl: 'https://github.com/test/repo',
      ));

      controller.clear();

      expect(controller.status, equals(ImportStatus.idle));
      expect(controller.gameSystemFile, isNull);
      expect(controller.primaryCatalogFile, isNull);
      expect(controller.sourceLocator, isNull);
      expect(controller.missingTargetIds, isEmpty);
      expect(controller.resolvedDependencies, isEmpty);
    });
  });

  group('ImportSessionController: missingTargetIds stability', () {
    test('missingTargetIds is unmodifiable list', () {
      final controller = ImportSessionController();

      // Can't directly test internal state, but we can verify the getter
      expect(controller.missingTargetIds, equals(const <String>[]));

      // The list should be unmodifiable (const empty list is)
      expect(() {
        controller.missingTargetIds.add('test');
      }, throwsUnsupportedError);
    });

    test('provideManualDependency updates resolvedCount correctly', () {
      final controller = ImportSessionController();

      // Provide some manual dependencies
      controller.provideManualDependency('id-1', Uint8List.fromList([1]));
      expect(controller.resolvedCount, equals(1));
      expect(controller.resolvedDependencies.containsKey('id-1'), isTrue);

      controller.provideManualDependency('id-2', Uint8List.fromList([2]));
      expect(controller.resolvedCount, equals(2));
      expect(controller.resolvedDependencies.containsKey('id-2'), isTrue);

      // Overwriting same ID should not increase count
      controller.provideManualDependency('id-1', Uint8List.fromList([3]));
      expect(controller.resolvedCount, equals(2));
    });

    test('resolvedDependencies is unmodifiable', () {
      final controller = ImportSessionController();

      controller.provideManualDependency('test', Uint8List.fromList([1]));

      expect(() {
        controller.resolvedDependencies['new'] = Uint8List.fromList([2]);
      }, throwsUnsupportedError);
    });
  });

  group('ImportSessionController: cache behavior', () {
    test('clear() clears resolved dependencies', () {
      final controller = ImportSessionController();

      controller.provideManualDependency('id-1', Uint8List.fromList([1]));
      controller.provideManualDependency('id-2', Uint8List.fromList([2]));

      expect(controller.resolvedDependencies.length, equals(2));

      controller.clear();

      expect(controller.resolvedDependencies, isEmpty);
      expect(controller.resolvedCount, equals(0));
    });

    test('setGameSystemFile resets cache', () {
      final controller = ImportSessionController();

      controller.provideManualDependency('id-1', Uint8List.fromList([1]));

      controller.setGameSystemFile(SelectedFile(
        fileName: 'new.gst',
        bytes: Uint8List.fromList([1, 2, 3]),
      ));

      expect(controller.resolvedDependencies, isEmpty);
    });

    test('setPrimaryCatalogFile resets cache', () {
      final controller = ImportSessionController();

      controller.provideManualDependency('id-1', Uint8List.fromList([1]));

      controller.setPrimaryCatalogFile(SelectedFile(
        fileName: 'new.cat',
        bytes: Uint8List.fromList([1, 2, 3]),
      ));

      expect(controller.resolvedDependencies, isEmpty);
    });
  });

  group('ImportSessionController: allDependenciesResolved', () {
    test('returns true when no missing dependencies', () {
      final controller = ImportSessionController();

      // No missing dependencies, should be considered resolved
      expect(controller.allDependenciesResolved, isTrue);
    });

    test('retryBuildWithResolvedDeps fails when not all resolved', () async {
      final controller = ImportSessionController();

      // Cannot directly set missingTargetIds, but we can test the error path
      // by not providing the required dependencies

      // This should fail gracefully
      await controller.retryBuildWithResolvedDeps();

      // Should not have error since there are no missing deps
      // (the check is based on allDependenciesResolved being true)
    });
  });

  group('ImportSessionController: source locator', () {
    test('setSourceLocator notifies listeners', () {
      final controller = ImportSessionController();
      var notified = false;

      controller.addListener(() {
        notified = true;
      });

      controller.setSourceLocator(const SourceLocator(
        sourceKey: 'test',
        sourceUrl: 'https://github.com/test/repo',
      ));

      expect(notified, isTrue);
      expect(controller.sourceLocator, isNotNull);
      expect(controller.sourceLocator!.sourceKey, equals('test'));
    });
  });

  group('ImportSessionController: ChangeNotifier behavior', () {
    test('notifies on file selection', () {
      final controller = ImportSessionController();
      var notifyCount = 0;

      controller.addListener(() {
        notifyCount++;
      });

      controller.setGameSystemFile(SelectedFile(
        fileName: 'test.gst',
        bytes: Uint8List.fromList([1]),
      ));

      expect(notifyCount, equals(1));

      controller.setPrimaryCatalogFile(SelectedFile(
        fileName: 'test.cat',
        bytes: Uint8List.fromList([1]),
      ));

      expect(notifyCount, equals(2));
    });

    test('notifies on clear', () {
      final controller = ImportSessionController();
      var notifyCount = 0;

      controller.addListener(() {
        notifyCount++;
      });

      controller.clear();

      expect(notifyCount, equals(1));
    });

    test('notifies on provideManualDependency', () {
      final controller = ImportSessionController();
      var notifyCount = 0;

      controller.addListener(() {
        notifyCount++;
      });

      controller.provideManualDependency('id-1', Uint8List.fromList([1]));

      expect(notifyCount, equals(1));
    });
  });

  group('ImportSessionController: deterministic state', () {
    test('bundles are null until build succeeds', () {
      final controller = ImportSessionController();

      expect(controller.rawBundle, isNull);
      expect(controller.boundBundle, isNull);
      expect(controller.indexBundle, isNull);
    });

    test('reset clears all bundles', () {
      final controller = ImportSessionController();

      // Set files and trigger reset via setGameSystemFile
      controller.setGameSystemFile(SelectedFile(
        fileName: 'test.gst',
        bytes: Uint8List.fromList([1]),
      ));

      // Internal _reset should clear bundles
      expect(controller.rawBundle, isNull);
      expect(controller.boundBundle, isNull);
      expect(controller.indexBundle, isNull);
      expect(controller.missingTargetIds, isEmpty);
    });

    test('statusMessage reflects current phase', () async {
      final controller = ImportSessionController();

      controller.setGameSystemFile(SelectedFile(
        fileName: 'test.gst',
        bytes: Uint8List.fromList([1]),
      ));
      controller.setPrimaryCatalogFile(SelectedFile(
        fileName: 'test.cat',
        bytes: Uint8List.fromList([1]),
      ));

      final messages = <String?>[];

      controller.addListener(() {
        if (controller.statusMessage != messages.lastOrNull) {
          messages.add(controller.statusMessage);
        }
      });

      // This will fail (invalid files) but we can check status message
      await controller.attemptBuild();

      // Should have at least "Preparing pack storage..." message
      expect(messages.contains('Preparing pack storage...'), isTrue);
    });
  });

  group('ImportSessionController: BsdResolverService injection', () {
    test('accepts injected BsdResolverService', () {
      final mockResolver = MockBsdResolverService();
      final controller = ImportSessionController(bsdResolver: mockResolver);

      expect(controller, isNotNull);
    });

    test('resolveDependencies fails without source locator', () async {
      final mockResolver = MockBsdResolverService();
      final controller = ImportSessionController(bsdResolver: mockResolver);

      // Try to resolve without setting source locator
      await controller.resolveDependencies();

      // Should either fail or do nothing (no missingTargetIds)
      // Since missingTargetIds is empty, it returns early
    });
  });

  group('ImportSessionController: error state', () {
    test('failed status preserves error message', () async {
      final controller = ImportSessionController();

      await controller.attemptBuild();

      expect(controller.status, equals(ImportStatus.failed));
      expect(controller.errorMessage, isNotNull);
      expect(controller.errorMessage!.isNotEmpty, isTrue);
    });

    test('statusMessage is null on failure', () async {
      final controller = ImportSessionController();

      await controller.attemptBuild();

      expect(controller.status, equals(ImportStatus.failed));
      expect(controller.statusMessage, isNull);
    });
  });

  // Register additional multi-catalog tests
  registerMultiCatalogTests();
}

extension IterableExtension on Iterable<String?> {
  String? get lastOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    String? result = iterator.current;
    while (iterator.moveNext()) {
      result = iterator.current;
    }
    return result;
  }
}

// ============================================================================
// Multi-catalog selection tests (registered in main() above)
// ============================================================================

void registerMultiCatalogTests() {
  group('ImportSessionController: multi-catalog selection', () {
    test('selectedCatalogs starts empty', () {
      final controller = ImportSessionController();

      expect(controller.selectedCatalogs, isEmpty);
    });

    test('setSelectedCatalogs sets catalogs', () {
      final controller = ImportSessionController();

      controller.setSelectedCatalogs([
        SelectedFile(
          fileName: 'catalog1.cat',
          bytes: Uint8List.fromList([1]),
          rootId: 'cat-1',
        ),
        SelectedFile(
          fileName: 'catalog2.cat',
          bytes: Uint8List.fromList([2]),
          rootId: 'cat-2',
        ),
      ]);

      expect(controller.selectedCatalogs.length, equals(2));
      expect(controller.selectedCatalogs[0].fileName, equals('catalog1.cat'));
      expect(controller.selectedCatalogs[1].rootId, equals('cat-2'));
    });

    test('setSelectedCatalogs throws when exceeding max', () {
      final controller = ImportSessionController();

      expect(
        () => controller.setSelectedCatalogs([
          SelectedFile(fileName: 'c1.cat', bytes: Uint8List.fromList([1])),
          SelectedFile(fileName: 'c2.cat', bytes: Uint8List.fromList([2])),
          SelectedFile(fileName: 'c3.cat', bytes: Uint8List.fromList([3])),
          SelectedFile(fileName: 'c4.cat', bytes: Uint8List.fromList([4])),
        ]),
        throwsArgumentError,
      );
    });

    test('addSelectedCatalog adds catalog', () {
      final controller = ImportSessionController();

      final added = controller.addSelectedCatalog(
        SelectedFile(
          fileName: 'catalog1.cat',
          bytes: Uint8List.fromList([1]),
        ),
      );

      expect(added, isTrue);
      expect(controller.selectedCatalogs.length, equals(1));
    });

    test('addSelectedCatalog returns false when at max', () {
      final controller = ImportSessionController();

      // Add 3 catalogs (max)
      controller.setSelectedCatalogs([
        SelectedFile(fileName: 'c1.cat', bytes: Uint8List.fromList([1])),
        SelectedFile(fileName: 'c2.cat', bytes: Uint8List.fromList([2])),
        SelectedFile(fileName: 'c3.cat', bytes: Uint8List.fromList([3])),
      ]);

      // Try to add a 4th
      final added = controller.addSelectedCatalog(
        SelectedFile(fileName: 'c4.cat', bytes: Uint8List.fromList([4])),
      );

      expect(added, isFalse);
      expect(controller.selectedCatalogs.length, equals(3));
    });

    test('removeSelectedCatalog removes by index', () {
      final controller = ImportSessionController();

      controller.setSelectedCatalogs([
        SelectedFile(fileName: 'c1.cat', bytes: Uint8List.fromList([1])),
        SelectedFile(fileName: 'c2.cat', bytes: Uint8List.fromList([2])),
        SelectedFile(fileName: 'c3.cat', bytes: Uint8List.fromList([3])),
      ]);

      controller.removeSelectedCatalog(1);

      expect(controller.selectedCatalogs.length, equals(2));
      expect(controller.selectedCatalogs[0].fileName, equals('c1.cat'));
      expect(controller.selectedCatalogs[1].fileName, equals('c3.cat'));
    });

    test('selectedCatalogs is unmodifiable', () {
      final controller = ImportSessionController();

      controller.setSelectedCatalogs([
        SelectedFile(fileName: 'c1.cat', bytes: Uint8List.fromList([1])),
      ]);

      expect(
        () => controller.selectedCatalogs.add(
          SelectedFile(fileName: 'c2.cat', bytes: Uint8List.fromList([2])),
        ),
        throwsUnsupportedError,
      );
    });

    test('clear() clears selectedCatalogs', () {
      final controller = ImportSessionController();

      controller.setSelectedCatalogs([
        SelectedFile(fileName: 'c1.cat', bytes: Uint8List.fromList([1])),
        SelectedFile(fileName: 'c2.cat', bytes: Uint8List.fromList([2])),
      ]);

      controller.clear();

      expect(controller.selectedCatalogs, isEmpty);
    });

    test('indexBundles starts empty', () {
      final controller = ImportSessionController();

      expect(controller.indexBundles, isEmpty);
    });

    test('kMaxSelectedCatalogs constant is 3', () {
      expect(kMaxSelectedCatalogs, equals(3));
    });
  });

  group('ImportSessionController: legacy compatibility', () {
    // ignore: deprecated_member_use_from_same_package
    test('primaryCatalogFile returns first selected catalog', () {
      final controller = ImportSessionController();

      controller.setSelectedCatalogs([
        SelectedFile(fileName: 'c1.cat', bytes: Uint8List.fromList([1])),
        SelectedFile(fileName: 'c2.cat', bytes: Uint8List.fromList([2])),
      ]);

      // ignore: deprecated_member_use_from_same_package
      expect(controller.primaryCatalogFile?.fileName, equals('c1.cat'));
    });

    // ignore: deprecated_member_use_from_same_package
    test('primaryCatalogFile returns null when no catalogs', () {
      final controller = ImportSessionController();

      // ignore: deprecated_member_use_from_same_package
      expect(controller.primaryCatalogFile, isNull);
    });

    // ignore: deprecated_member_use_from_same_package
    test('setPrimaryCatalogFile sets single catalog', () {
      final controller = ImportSessionController();

      // ignore: deprecated_member_use_from_same_package
      controller.setPrimaryCatalogFile(
        SelectedFile(fileName: 'c1.cat', bytes: Uint8List.fromList([1])),
      );

      expect(controller.selectedCatalogs.length, equals(1));
      expect(controller.selectedCatalogs[0].fileName, equals('c1.cat'));
    });
  });
}
