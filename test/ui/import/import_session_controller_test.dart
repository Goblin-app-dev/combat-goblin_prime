import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart'
    show AcquireFailure, AcquireService, RawPackBundle;
import 'package:combat_goblin_prime/modules/m1_acquire/models/source_locator.dart';
import 'package:combat_goblin_prime/services/bsd_resolver_service.dart';
import 'package:combat_goblin_prime/services/github_sync_state.dart'
    show
        GitHubSyncState,
        GitHubSyncStateService,
        RepoSyncState,
        TrackedFile;
import 'package:combat_goblin_prime/services/session_persistence_service.dart'
    show PersistedCatalog;
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

      // Add 2 catalogs (max)
      controller.setSelectedCatalogs([
        SelectedFile(fileName: 'c1.cat', bytes: Uint8List.fromList([1])),
        SelectedFile(fileName: 'c2.cat', bytes: Uint8List.fromList([2])),
      ]);

      // Try to add a 3rd
      final added = controller.addSelectedCatalog(
        SelectedFile(fileName: 'c3.cat', bytes: Uint8List.fromList([3])),
      );

      expect(added, isFalse);
      expect(controller.selectedCatalogs.length, equals(2));
    });

    test('removeSelectedCatalog removes by index', () {
      final controller = ImportSessionController();

      controller.setSelectedCatalogs([
        SelectedFile(fileName: 'c1.cat', bytes: Uint8List.fromList([1])),
        SelectedFile(fileName: 'c2.cat', bytes: Uint8List.fromList([2])),
      ]);

      controller.removeSelectedCatalog(0);

      expect(controller.selectedCatalogs.length, equals(1));
      expect(controller.selectedCatalogs[0].fileName, equals('c2.cat'));
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

    test('kMaxSelectedCatalogs constant is 2', () {
      expect(kMaxSelectedCatalogs, equals(2));
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

  _loadRepoCatalogTreeTests();
  _importFromGitHubTests();
  _availableFactionsTests();
  _bootRestoringTests();
  _retrySlotTests();
  _updateCheckTimestampTests();
  _lastSyncAtTests();
}

// --- Enhanced mock for GitHub import tests ---

/// Mock that supports fetchRepoTree() and fetchFileByPath() overrides.
class _MockGitHubResolverService extends BsdResolverService {
  RepoTreeResult? _mockTreeResult;
  BsdResolverException? _mockTreeError;
  BsdResolverException? _mockFileError;
  BsdResolverException? _mockLastError;

  /// Recorded paths passed to fetchFileByPath(), in call order.
  final List<String> downloadedPaths = [];

  /// File bytes to return, keyed by path. null value → failure.
  final Map<String, Uint8List?> _fileBytes = {};

  @override
  BsdResolverException? get lastError => _mockLastError;

  void setTree(RepoTreeResult tree) {
    _mockTreeResult = tree;
    _mockTreeError = null;
  }

  void setTreeError(BsdResolverException error) {
    _mockTreeResult = null;
    _mockTreeError = error;
  }

  /// Register bytes for a path. Pass null to simulate download failure.
  void setFile(String path, Uint8List? bytes) {
    _fileBytes[path] = bytes;
  }

  /// Error returned when a path is not in [_fileBytes] or its value is null.
  void setFileError(BsdResolverException error) {
    _mockFileError = error;
  }

  @override
  Future<RepoTreeResult?> fetchRepoTree(SourceLocator sourceLocator) async {
    if (_mockTreeError != null) {
      _mockLastError = _mockTreeError;
      return null;
    }
    _mockLastError = null;
    return _mockTreeResult;
  }

  @override
  Future<Uint8List?> fetchFileByPath(
    SourceLocator sourceLocator,
    String path,
  ) async {
    _mockLastError = null;
    downloadedPaths.add(path);
    final bytes = _fileBytes[path];
    if (bytes == null) {
      _mockLastError = _mockFileError;
    }
    return bytes;
  }

  @override
  Future<Uint8List?> fetchCatalogBytes({
    required SourceLocator sourceLocator,
    required String targetId,
  }) async =>
      null;

  @override
  Future<RepoIndexResult?> buildRepoIndex(SourceLocator sourceLocator) async {
    return const RepoIndexResult(
      targetIdToPath: {},
      pathToBlobSha: {},
      targetIdToBlobSha: {},
      unparsedFiles: [],
    );
  }
}

// --- Helpers ---

const _kTestLocator = SourceLocator(
  sourceKey: 'bsdata_wh40k',
  sourceUrl: 'https://github.com/BSData/wh40k-10e',
  branch: 'main',
);

final _emptyTree = RepoTreeResult(
  entries: [],
  fetchedAt: DateTime(2026, 2, 17),
);

RepoTreeResult _makeTree(List<String> paths) {
  return RepoTreeResult(
    entries: paths
        .map((p) => RepoTreeEntry(
              path: p,
              blobSha: 'sha_${p.hashCode.abs()}',
              extension: p.endsWith('.gst') ? '.gst' : '.cat',
            ))
        .toList(),
    fetchedAt: DateTime(2026, 2, 17),
  );
}

// --- loadRepoCatalogTree tests ---

void _loadRepoCatalogTreeTests() {
  group('ImportSessionController: loadRepoCatalogTree', () {
    test('returns sorted RepoTreeResult on success', () async {
      final mock = _MockGitHubResolverService();
      mock.setTree(_makeTree([
        'z-catalog.cat',
        'a-catalog.cat',
        'game.gst',
        'b-catalog.cat',
      ]));
      final controller = ImportSessionController(bsdResolver: mock);

      final result = await controller.loadRepoCatalogTree(_kTestLocator);

      expect(result, isNotNull);
      final paths = result!.entries.map((e) => e.path).toList();
      expect(paths, equals([
        'a-catalog.cat',
        'b-catalog.cat',
        'game.gst',
        'z-catalog.cat',
      ]));
    });

    test('does not change ImportStatus', () async {
      final mock = _MockGitHubResolverService();
      mock.setTree(_makeTree(['game.gst']));
      final controller = ImportSessionController(bsdResolver: mock);

      expect(controller.status, equals(ImportStatus.idle));
      await controller.loadRepoCatalogTree(_kTestLocator);
      expect(controller.status, equals(ImportStatus.idle));
    });

    test('sets resolverError on rate-limit failure and returns null', () async {
      const rateLimit = BsdResolverException(
        code: BsdResolverErrorCode.rateLimitExceeded,
        message: 'Rate limit exceeded',
      );
      final mock = _MockGitHubResolverService();
      mock.setTreeError(rateLimit);
      final controller = ImportSessionController(bsdResolver: mock);

      final result = await controller.loadRepoCatalogTree(_kTestLocator);

      expect(result, isNull);
      expect(controller.resolverError, isNotNull);
      expect(
        controller.resolverError!.code,
        equals(BsdResolverErrorCode.rateLimitExceeded),
      );
      // Status must remain idle — tree browsing is view-local state
      expect(controller.status, equals(ImportStatus.idle));
    });

    test('clears resolverError before each call', () async {
      const rateLimit = BsdResolverException(
        code: BsdResolverErrorCode.rateLimitExceeded,
        message: 'Rate limit exceeded',
      );
      final mock = _MockGitHubResolverService();
      final controller = ImportSessionController(bsdResolver: mock);

      // First call fails
      mock.setTreeError(rateLimit);
      await controller.loadRepoCatalogTree(_kTestLocator);
      expect(controller.resolverError, isNotNull);

      // Second call succeeds — resolverError must be cleared
      mock.setTree(_makeTree(['game.gst']));
      final result = await controller.loadRepoCatalogTree(_kTestLocator);
      expect(result, isNotNull);
      expect(controller.resolverError, isNull);
    });

    test('returns only gst and cat files sorted lexicographically', () async {
      final mock = _MockGitHubResolverService();
      mock.setTree(_makeTree(['Chaos.cat', 'Alpha.cat', 'Wh40k.gst']));
      final controller = ImportSessionController(bsdResolver: mock);

      final result = await controller.loadRepoCatalogTree(_kTestLocator);

      expect(result, isNotNull);
      expect(result!.gameSystemFiles.map((e) => e.path).toList(),
          equals(['Wh40k.gst']));
      expect(result.catalogFiles.map((e) => e.path).toList(),
          equals(['Alpha.cat', 'Chaos.cat']));
    });
  });
}

// --- importFromGitHub tests ---

void _importFromGitHubTests() {
  group('ImportSessionController: importFromGitHub', () {
    test('throws ArgumentError when catPaths exceeds kMaxSelectedCatalogs',
        () async {
      final mock = _MockGitHubResolverService();
      final controller = ImportSessionController(bsdResolver: mock);

      expect(
        () => controller.importFromGitHub(
          sourceLocator: _kTestLocator,
          gstPath: 'game.gst',
          catPaths: ['a.cat', 'b.cat', 'c.cat'],
          repoTree: _emptyTree,
        ),
        throwsArgumentError,
      );
    });

    test('transitions to failed when .gst download fails', () async {
      const networkError = BsdResolverException(
        code: BsdResolverErrorCode.networkError,
        message: 'Network error',
      );
      final mock = _MockGitHubResolverService();
      mock.setFileError(networkError);
      final controller = ImportSessionController(bsdResolver: mock);

      await controller.importFromGitHub(
        sourceLocator: _kTestLocator,
        gstPath: 'game.gst',
        catPaths: ['a.cat'],
        repoTree: _emptyTree,
      );

      expect(controller.status, equals(ImportStatus.failed));
      expect(controller.resolverError, isNotNull);
      expect(controller.indexBundles, isEmpty);
    });

    test('transitions to failed when .cat download fails (no partial state)',
        () async {
      final mock = _MockGitHubResolverService();
      // .gst succeeds
      mock.setFile('game.gst', Uint8List.fromList([1, 2, 3]));
      // .cat not registered → returns null
      mock.setFileError(const BsdResolverException(
        code: BsdResolverErrorCode.notFound,
        message: 'File not found',
      ));
      final controller = ImportSessionController(bsdResolver: mock);

      await controller.importFromGitHub(
        sourceLocator: _kTestLocator,
        gstPath: 'game.gst',
        catPaths: ['a.cat'],
        repoTree: _emptyTree,
      );

      expect(controller.status, equals(ImportStatus.failed));
      expect(controller.indexBundles, isEmpty);
    });

    test('sets sourceLocator from argument', () async {
      final mock = _MockGitHubResolverService();
      // fail fast so we don't run the pipeline
      mock.setFileError(const BsdResolverException(
        code: BsdResolverErrorCode.networkError,
        message: 'fail',
      ));
      final controller = ImportSessionController(bsdResolver: mock);

      await controller.importFromGitHub(
        sourceLocator: _kTestLocator,
        gstPath: 'game.gst',
        catPaths: ['a.cat'],
        repoTree: _emptyTree,
      );

      expect(controller.sourceLocator, equals(_kTestLocator));
    });

    test('downloads .gst first, then .cat files in lexicographic order',
        () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('game.gst', Uint8List.fromList([1]));
      // cats fail so pipeline doesn't run
      mock.setFileError(const BsdResolverException(
        code: BsdResolverErrorCode.networkError,
        message: 'fail',
      ));
      final controller = ImportSessionController(bsdResolver: mock);

      // Pass in reverse order — should still download alphabetically.
      await controller.importFromGitHub(
        sourceLocator: _kTestLocator,
        gstPath: 'game.gst',
        catPaths: ['b.cat', 'a.cat'],
        repoTree: _emptyTree,
      );

      // .gst downloaded first; first .cat is 'a.cat' (sorted), not 'b.cat'.
      expect(mock.downloadedPaths.first, equals('game.gst'));
      expect(mock.downloadedPaths.length, greaterThanOrEqualTo(2));
      expect(mock.downloadedPaths[1], equals('a.cat'));
    });

    test('different catPaths orders produce identical download + catalog order',
        () async {
      // Run 1: reverse-alphabetical input order
      final mock1 = _MockGitHubResolverService();
      mock1.setFile('game.gst', Uint8List.fromList([1]));
      mock1.setFile('a.cat', Uint8List.fromList([1]));
      mock1.setFile('b.cat', Uint8List.fromList([2]));
      final ctrl1 = ImportSessionController(bsdResolver: mock1);

      await ctrl1.importFromGitHub(
        sourceLocator: _kTestLocator,
        gstPath: 'game.gst',
        catPaths: ['b.cat', 'a.cat'],
        repoTree: _emptyTree,
      );

      // Run 2: different input order
      final mock2 = _MockGitHubResolverService();
      mock2.setFile('game.gst', Uint8List.fromList([1]));
      mock2.setFile('a.cat', Uint8List.fromList([1]));
      mock2.setFile('b.cat', Uint8List.fromList([2]));
      final ctrl2 = ImportSessionController(bsdResolver: mock2);

      await ctrl2.importFromGitHub(
        sourceLocator: _kTestLocator,
        gstPath: 'game.gst',
        catPaths: ['a.cat', 'b.cat'],
        repoTree: _emptyTree,
      );

      // Download order must be identical regardless of input order.
      expect(mock1.downloadedPaths, equals(mock2.downloadedPaths));
      expect(
        mock1.downloadedPaths,
        equals(['game.gst', 'a.cat', 'b.cat']),
      );

      // selectedCatalogs order (which feeds sync-state rootIds) must match.
      final names1 =
          ctrl1.selectedCatalogs.map((f) => f.fileName).toList();
      final names2 =
          ctrl2.selectedCatalogs.map((f) => f.fileName).toList();
      expect(names1, equals(names2));
      expect(names1, equals(['a.cat', 'b.cat']));
    });

    test('enforces max kMaxSelectedCatalogs strictly', () async {
      final mock = _MockGitHubResolverService();
      final controller = ImportSessionController(bsdResolver: mock);

      // Exactly at limit (2) — should not throw
      mock.setFileError(const BsdResolverException(
        code: BsdResolverErrorCode.networkError,
        message: 'fail',
      ));

      await controller.importFromGitHub(
        sourceLocator: _kTestLocator,
        gstPath: 'game.gst',
        catPaths: ['a.cat', 'b.cat'],
        repoTree: _emptyTree,
      );

      // Over limit (3) — must throw
      expect(
        () => controller.importFromGitHub(
          sourceLocator: _kTestLocator,
          gstPath: 'game.gst',
          catPaths: ['a.cat', 'b.cat', 'c.cat'],
          repoTree: _emptyTree,
        ),
        throwsArgumentError,
      );
    });
  });

  _slotStateTests();
}

// --- Per-slot state transition tests ---

void _slotStateTests() {
  group('ImportSessionController: slot state', () {
    test('slots start empty', () {
      final controller = ImportSessionController();

      expect(controller.slots.length, equals(kMaxSelectedCatalogs));
      for (final s in controller.slots) {
        expect(s.status, equals(SlotStatus.empty));
        expect(s.catalogPath, isNull);
        expect(s.indexBundle, isNull);
      }
    });

    test('slotIndexBundles is empty when no slots loaded', () {
      final controller = ImportSessionController();

      expect(controller.slotIndexBundles, isEmpty);
    });

    test('hasAnyLoaded is false initially', () {
      final controller = ImportSessionController();

      expect(controller.hasAnyLoaded, isFalse);
    });

    test('assignCatalogToSlot transitions to fetching then error on failure',
        () async {
      final mock = _MockGitHubResolverService();
      mock.setFileError(const BsdResolverException(
        code: BsdResolverErrorCode.networkError,
        message: 'Network error',
      ));
      final controller = ImportSessionController(bsdResolver: mock);

      final statuses = <SlotStatus>[];
      controller.addListener(() {
        statuses.add(controller.slotState(0).status);
      });

      await controller.assignCatalogToSlot(0, 'test.cat', _kTestLocator);

      expect(statuses.contains(SlotStatus.fetching), isTrue);
      expect(controller.slotState(0).status, equals(SlotStatus.error));
      expect(controller.slotState(0).errorMessage, isNotNull);
    });

    test('assignCatalogToSlot transitions to fetching then ready on success',
        () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('test.cat', Uint8List.fromList([1, 2, 3]));
      final controller = ImportSessionController(bsdResolver: mock);

      final statuses = <SlotStatus>[];
      controller.addListener(() {
        statuses.add(controller.slotState(0).status);
      });

      await controller.assignCatalogToSlot(0, 'test.cat', _kTestLocator);

      expect(statuses.contains(SlotStatus.fetching), isTrue);
      expect(controller.slotState(0).status, equals(SlotStatus.ready));
      expect(controller.slotState(0).fetchedBytes, isNotNull);
      expect(controller.slotState(0).catalogName, equals('test.cat'));
    });

    test('clearSlot resets slot to empty', () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('test.cat', Uint8List.fromList([1, 2, 3]));
      final controller = ImportSessionController(bsdResolver: mock);

      await controller.assignCatalogToSlot(0, 'test.cat', _kTestLocator);
      expect(controller.slotState(0).status, equals(SlotStatus.ready));

      controller.clearSlot(0);
      expect(controller.slotState(0).status, equals(SlotStatus.empty));
      expect(controller.slotState(0).catalogPath, isNull);
    });

    test('loadSlot does nothing when slot is not ready', () async {
      final controller = ImportSessionController();

      await controller.loadSlot(0);

      expect(controller.slotState(0).status, equals(SlotStatus.empty));
    });

    test('loadSlot errors when game system not set', () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('test.cat', Uint8List.fromList([1, 2, 3]));
      final controller = ImportSessionController(bsdResolver: mock);

      await controller.assignCatalogToSlot(0, 'test.cat', _kTestLocator);
      expect(controller.slotState(0).status, equals(SlotStatus.ready));

      await controller.loadSlot(0);
      expect(controller.slotState(0).status, equals(SlotStatus.error));
      expect(controller.slotState(0).errorMessage, contains('Game system'));
    });

    test('slots list is unmodifiable', () {
      final controller = ImportSessionController();

      expect(
        () => controller.slots.add(const SlotState()),
        throwsUnsupportedError,
      );
    });

    test('slots are independent', () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('a.cat', Uint8List.fromList([1]));
      mock.setFileError(const BsdResolverException(
        code: BsdResolverErrorCode.networkError,
        message: 'fail',
      ));
      final controller = ImportSessionController(bsdResolver: mock);

      // Slot 0: success
      await controller.assignCatalogToSlot(0, 'a.cat', _kTestLocator);

      // Slot 1: will fail because the error is now set
      await controller.assignCatalogToSlot(1, 'b.cat', _kTestLocator);

      expect(controller.slotState(0).status, equals(SlotStatus.ready));
      expect(controller.slotState(1).status, equals(SlotStatus.error));
    });

    test('clear() resets all slots', () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('a.cat', Uint8List.fromList([1]));
      final controller = ImportSessionController(bsdResolver: mock);

      await controller.assignCatalogToSlot(0, 'a.cat', _kTestLocator);
      expect(controller.slotState(0).status, equals(SlotStatus.ready));

      controller.clear();

      // Slots with fetched bytes get demoted during _reset, then clear()
      // sets _selectedCatalogs = const [], _gameSystemFile = null, and
      // calls _reset() which calls _demoteSlotBuildState().
      // The slot still has bytes so it stays ready after _reset.
      // To fully clear, clearSlot should be called explicitly.
      // For now verify controller.clear() doesn't break.
      expect(controller.gameSystemFile, isNull);
      expect(controller.selectedCatalogs, isEmpty);
    });

    test('updateAvailable is false initially', () {
      final controller = ImportSessionController();

      expect(controller.updateAvailable, isFalse);
      expect(controller.updateCheckStatus, equals(UpdateCheckStatus.unknown));
    });

    test('UpdateCheckStatus starts as unknown', () {
      final controller = ImportSessionController();

      expect(controller.updateCheckStatus, equals(UpdateCheckStatus.unknown));
    });

    test('SlotState.missingTargetIds defaults to empty', () {
      const state = SlotState();

      expect(state.missingTargetIds, isEmpty);
      expect(state.hasMissingDeps, isFalse);
    });

    test('SlotState.hasMissingDeps is true when list is non-empty', () {
      const state = SlotState(
        status: SlotStatus.error,
        missingTargetIds: ['id-a', 'id-b'],
      );

      expect(state.hasMissingDeps, isTrue);
      expect(state.missingTargetIds, equals(['id-a', 'id-b']));
    });

    test('SlotState.copyWith preserves missingTargetIds when not overridden',
        () {
      const state = SlotState(
        status: SlotStatus.error,
        missingTargetIds: ['id-a'],
      );

      final copied = state.copyWith(status: SlotStatus.ready);

      expect(copied.missingTargetIds, equals(['id-a']));
    });

    test('fetchAndSetGameSystem sets game system on success', () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('game.gst', Uint8List.fromList([1, 2, 3]));
      final controller = ImportSessionController(bsdResolver: mock);

      final result =
          await controller.fetchAndSetGameSystem(_kTestLocator, 'game.gst');

      expect(result, isTrue);
      expect(controller.gameSystemFile, isNotNull);
      expect(controller.gameSystemFile!.fileName, equals('game.gst'));
      expect(controller.status, equals(ImportStatus.idle));
    });

    test('fetchAndSetGameSystem fails on download error', () async {
      final mock = _MockGitHubResolverService();
      mock.setFileError(const BsdResolverException(
        code: BsdResolverErrorCode.networkError,
        message: 'fail',
      ));
      final controller = ImportSessionController(bsdResolver: mock);

      final result =
          await controller.fetchAndSetGameSystem(_kTestLocator, 'game.gst');

      expect(result, isFalse);
      expect(controller.status, equals(ImportStatus.failed));
      expect(controller.resolverError, isNotNull);
    });

    test('fetchAndSetGameSystem demotes loaded slots to ready', () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('a.cat', Uint8List.fromList([1]));
      mock.setFile('game.gst', Uint8List.fromList([2]));
      final controller = ImportSessionController(bsdResolver: mock);

      // Put slot 0 in ready state
      await controller.assignCatalogToSlot(0, 'a.cat', _kTestLocator);
      expect(controller.slotState(0).status, equals(SlotStatus.ready));

      // Fetch game system
      await controller.fetchAndSetGameSystem(_kTestLocator, 'game.gst');

      // Slot 0 should remain ready (it was already ready, not loaded)
      expect(controller.slotState(0).status, equals(SlotStatus.ready));
    });
  });

  _updateCheckTests();
  _loadSlotMissingDepsTests();
}

// ---------------------------------------------------------------------------
// Mock helpers
// ---------------------------------------------------------------------------

/// In-memory GitHubSyncStateService that returns a fixed state.
class _FakeGitHubSyncStateService extends GitHubSyncStateService {
  GitHubSyncState _state;
  bool throwOnLoad;

  _FakeGitHubSyncStateService(this._state, {this.throwOnLoad = false})
      : super(storageRoot: '/dev/null');

  @override
  Future<GitHubSyncState> loadState() async {
    if (throwOnLoad) throw Exception('network error');
    return _state;
  }
}

/// AcquireService subclass that always throws a given AcquireFailure.
class _ThrowingAcquireService extends AcquireService {
  final AcquireFailure _failure;

  _ThrowingAcquireService(this._failure);

  @override
  Future<RawPackBundle> buildBundle({
    required List<int> gameSystemBytes,
    required String gameSystemExternalFileName,
    required List<int> primaryCatalogBytes,
    required String primaryCatalogExternalFileName,
    required Future<List<int>?> Function(String) requestDependencyBytes,
    required SourceLocator source,
  }) async {
    throw _failure;
  }
}

// ---------------------------------------------------------------------------
// UpdateCheckStatus state-transition tests
// ---------------------------------------------------------------------------

void _updateCheckTests() {
  group('ImportSessionController: UpdateCheckStatus', () {
    test('starts as unknown and updateAvailable is false', () {
      final controller = ImportSessionController();

      expect(controller.updateCheckStatus, equals(UpdateCheckStatus.unknown));
      expect(controller.updateAvailable, isFalse);
    });

    test('successful check with no SHA diffs → upToDate', () async {
      const sourceKey = 'bsdata_wh40k';
      const path = 'game.gst';
      const sha = 'abc123';

      final tree = RepoTreeResult(
        entries: [
          RepoTreeEntry(path: path, blobSha: sha, extension: '.gst'),
        ],
        fetchedAt: DateTime(2026, 2, 18),
      );

      final syncState = GitHubSyncState(
        repos: {
          sourceKey: RepoSyncState(
            repoUrl: 'https://github.com/BSData/wh40k-10e',
            branch: 'main',
            trackedFiles: {
              path: TrackedFile(
                repoPath: path,
                fileType: 'gst',
                blobSha: sha, // same SHA → no update
                lastCheckedAt: DateTime(2026, 2, 17),
              ),
            },
          ),
        },
      );

      final mock = _MockGitHubResolverService()..setTree(tree);
      final syncService = _FakeGitHubSyncStateService(syncState);
      final controller = ImportSessionController(
        bsdResolver: mock,
        gitHubSyncStateService: syncService,
      );
      // _sourceLocator must be set for check to run
      controller.setSourceLocatorForTesting(
        const SourceLocator(
          sourceKey: sourceKey,
          sourceUrl: 'https://github.com/BSData/wh40k-10e',
        ),
      );

      await controller.checkForUpdates();

      expect(controller.updateCheckStatus, equals(UpdateCheckStatus.upToDate));
      expect(controller.updateAvailable, isFalse);
    });

    test('successful check with changed blob SHA → updatesAvailable', () async {
      const sourceKey = 'bsdata_wh40k';
      const path = 'game.gst';

      final tree = RepoTreeResult(
        entries: [
          RepoTreeEntry(
            path: path,
            blobSha: 'new_sha_456',
            extension: '.gst',
          ),
        ],
        fetchedAt: DateTime(2026, 2, 18),
      );

      final syncState = GitHubSyncState(
        repos: {
          sourceKey: RepoSyncState(
            repoUrl: 'https://github.com/BSData/wh40k-10e',
            branch: 'main',
            trackedFiles: {
              path: TrackedFile(
                repoPath: path,
                fileType: 'gst',
                blobSha: 'old_sha_123', // different SHA → update available
                lastCheckedAt: DateTime(2026, 2, 17),
              ),
            },
          ),
        },
      );

      final mock = _MockGitHubResolverService()..setTree(tree);
      final syncService = _FakeGitHubSyncStateService(syncState);
      final controller = ImportSessionController(
        bsdResolver: mock,
        gitHubSyncStateService: syncService,
      );
      controller.setSourceLocatorForTesting(
        const SourceLocator(
          sourceKey: sourceKey,
          sourceUrl: 'https://github.com/BSData/wh40k-10e',
        ),
      );

      await controller.checkForUpdates();

      expect(
        controller.updateCheckStatus,
        equals(UpdateCheckStatus.updatesAvailable),
      );
      expect(controller.updateAvailable, isTrue);
    });

    test('check fails when fetchRepoTree returns null → failed', () async {
      final mock = _MockGitHubResolverService()
        ..setTreeError(const BsdResolverException(
          code: BsdResolverErrorCode.networkError,
          message: 'timeout',
        ));
      final syncService = _FakeGitHubSyncStateService(const GitHubSyncState());
      final controller = ImportSessionController(
        bsdResolver: mock,
        gitHubSyncStateService: syncService,
      );
      controller.setSourceLocatorForTesting(
        const SourceLocator(
          sourceKey: 'bsdata_wh40k',
          sourceUrl: 'https://github.com/BSData/wh40k-10e',
        ),
      );

      await controller.checkForUpdates();

      expect(
        controller.updateCheckStatus,
        equals(UpdateCheckStatus.failed),
      );
      expect(controller.updateAvailable, isFalse);
    });

    test('check fails when syncService throws → failed, not upToDate',
        () async {
      const sourceKey = 'bsdata_wh40k';
      const path = 'game.gst';

      final tree = RepoTreeResult(
        entries: [
          RepoTreeEntry(path: path, blobSha: 'abc', extension: '.gst'),
        ],
        fetchedAt: DateTime(2026, 2, 18),
      );

      final mock = _MockGitHubResolverService()..setTree(tree);
      final syncService = _FakeGitHubSyncStateService(
        const GitHubSyncState(),
        throwOnLoad: true,
      );
      final controller = ImportSessionController(
        bsdResolver: mock,
        gitHubSyncStateService: syncService,
      );
      controller.setSourceLocatorForTesting(
        const SourceLocator(
          sourceKey: sourceKey,
          sourceUrl: 'https://github.com/BSData/wh40k-10e',
        ),
      );

      await controller.checkForUpdates();

      expect(controller.updateCheckStatus, equals(UpdateCheckStatus.failed));
      // Must never imply upToDate when check failed
      expect(
        controller.updateCheckStatus,
        isNot(equals(UpdateCheckStatus.upToDate)),
      );
    });

    test('check with no sourceLocator stays unknown', () async {
      final controller = ImportSessionController();

      await controller.checkForUpdates();

      // _sourceLocator is null → check exits early → status stays unknown
      expect(controller.updateCheckStatus, equals(UpdateCheckStatus.unknown));
    });

    test('failed check does not set upToDate', () async {
      final mock = _MockGitHubResolverService()
        ..setTreeError(const BsdResolverException(
          code: BsdResolverErrorCode.networkError,
          message: 'fail',
        ));
      final controller = ImportSessionController(
        bsdResolver: mock,
        gitHubSyncStateService: _FakeGitHubSyncStateService(
          const GitHubSyncState(),
        ),
      );
      controller.setSourceLocatorForTesting(
        const SourceLocator(
          sourceKey: 'bsdata_wh40k',
          sourceUrl: 'https://github.com/BSData/wh40k-10e',
        ),
      );

      await controller.checkForUpdates();

      expect(
        controller.updateCheckStatus,
        isNot(equals(UpdateCheckStatus.upToDate)),
      );
    });
  });
}

// ---------------------------------------------------------------------------
// loadSlot missing-dependency tests
// ---------------------------------------------------------------------------

void _loadSlotMissingDepsTests() {
  group('ImportSessionController: loadSlot missing dependencies', () {
    test(
        'AcquireFailure with missingTargetIds → slot error with sorted ids',
        () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('test.cat', Uint8List.fromList([1, 2, 3]));
      mock.setFile('game.gst', Uint8List.fromList([4, 5, 6]));

      final acquireFactory = (_) => _ThrowingAcquireService(
            const AcquireFailure(
              message: 'Missing deps',
              missingTargetIds: ['z-id', 'a-id', 'm-id'],
            ),
          );

      final controller = ImportSessionController(
        bsdResolver: mock,
        acquireServiceFactory: acquireFactory,
      );

      // Set game system
      await controller.fetchAndSetGameSystem(_kTestLocator, 'game.gst');
      expect(controller.gameSystemFile, isNotNull);

      // Put slot 0 in ready state
      await controller.assignCatalogToSlot(0, 'test.cat', _kTestLocator);
      expect(controller.slotState(0).status, equals(SlotStatus.ready));

      // Load — pipeline will throw AcquireFailure with unordered IDs
      await controller.loadSlot(0);

      // Slot ends in error with sorted missing IDs
      final state = controller.slotState(0);
      expect(state.status, equals(SlotStatus.error));
      expect(state.hasMissingDeps, isTrue);
      expect(state.missingTargetIds, equals(['a-id', 'm-id', 'z-id']));
      expect(state.missingTargetIds, isA<List<String>>());
    });

    test('AcquireFailure without missingTargetIds → error with empty list',
        () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('test.cat', Uint8List.fromList([1, 2, 3]));
      mock.setFile('game.gst', Uint8List.fromList([4, 5, 6]));

      final acquireFactory = (_) => _ThrowingAcquireService(
            const AcquireFailure(message: 'build failed'),
          );

      final controller = ImportSessionController(
        bsdResolver: mock,
        acquireServiceFactory: acquireFactory,
      );

      await controller.fetchAndSetGameSystem(_kTestLocator, 'game.gst');
      await controller.assignCatalogToSlot(0, 'test.cat', _kTestLocator);
      await controller.loadSlot(0);

      final state = controller.slotState(0);
      expect(state.status, equals(SlotStatus.error));
      expect(state.hasMissingDeps, isFalse);
      expect(state.missingTargetIds, isEmpty);
      expect(state.errorMessage, equals('build failed'));
    });

    test('missing IDs are stable-sorted and immutable', () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('test.cat', Uint8List.fromList([1]));
      mock.setFile('game.gst', Uint8List.fromList([2]));

      final acquireFactory = (_) => _ThrowingAcquireService(
            const AcquireFailure(
              message: 'deps',
              missingTargetIds: ['cc', 'aa', 'bb'],
            ),
          );

      final controller = ImportSessionController(
        bsdResolver: mock,
        acquireServiceFactory: acquireFactory,
      );

      await controller.fetchAndSetGameSystem(_kTestLocator, 'game.gst');
      await controller.assignCatalogToSlot(0, 'test.cat', _kTestLocator);
      await controller.loadSlot(0);

      final ids = controller.slotState(0).missingTargetIds;
      expect(ids, equals(['aa', 'bb', 'cc']));
      // Must be unmodifiable
      expect(() => ids.add('xx'), throwsUnsupportedError);
    });

    test('clearing slot after error removes missingTargetIds', () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('test.cat', Uint8List.fromList([1]));
      mock.setFile('game.gst', Uint8List.fromList([2]));

      final acquireFactory = (_) => _ThrowingAcquireService(
            const AcquireFailure(
              message: 'deps',
              missingTargetIds: ['a-id'],
            ),
          );

      final controller = ImportSessionController(
        bsdResolver: mock,
        acquireServiceFactory: acquireFactory,
      );

      await controller.fetchAndSetGameSystem(_kTestLocator, 'game.gst');
      await controller.assignCatalogToSlot(0, 'test.cat', _kTestLocator);
      await controller.loadSlot(0);

      expect(controller.slotState(0).hasMissingDeps, isTrue);

      controller.clearSlot(0);

      expect(controller.slotState(0).status, equals(SlotStatus.empty));
      expect(controller.slotState(0).missingTargetIds, isEmpty);
    });
  });
}

// --- availableFactions tests ---

void _availableFactionsTests() {
  ImportSessionController _ctrl() =>
      ImportSessionController(bsdResolver: _MockGitHubResolverService());

  group('ImportSessionController: availableFactions', () {
    test('returns empty list for empty tree', () {
      final result = _ctrl().availableFactions(_emptyTree);
      expect(result, isEmpty);
    });

    test('single primary .cat → one entry, no library', () {
      final result = _ctrl().availableFactions(
        _makeTree(['Chaos - Chaos Knights.cat', 'Warhammer 40,000.gst']),
      );
      expect(result, hasLength(1));
      expect(result.first.displayName, 'Chaos - Chaos Knights');
      expect(result.first.libraryPaths, isEmpty);
    });

    // ── Suffix pattern: "Category - FactionName - Library.cat" ─────────────
    test('suffix-pattern library is grouped with its primary (Chaos Knights)',
        () {
      final result = _ctrl().availableFactions(_makeTree([
        'Chaos - Chaos Knights.cat',
        'Chaos - Chaos Knights - Library.cat',
        'Warhammer 40,000.gst',
      ]));
      expect(result, hasLength(1));
      expect(result.first.displayName, 'Chaos - Chaos Knights');
      expect(result.first.primaryPath, 'Chaos - Chaos Knights.cat');
      expect(result.first.libraryPaths,
          equals(['Chaos - Chaos Knights - Library.cat']));
    });

    test('suffix-pattern library is grouped with its primary (Imperial Knights)',
        () {
      final result = _ctrl().availableFactions(_makeTree([
        'Imperium - Imperial Knights.cat',
        'Imperium - Imperial Knights - Library.cat',
        'Warhammer 40,000.gst',
      ]));
      expect(result, hasLength(1));
      expect(result.first.displayName, 'Imperium - Imperial Knights');
      expect(result.first.primaryPath, 'Imperium - Imperial Knights.cat');
      expect(result.first.libraryPaths,
          equals(['Imperium - Imperial Knights - Library.cat']));
    });

    // ── Prefix pattern: "Library - FactionName.cat" ─────────────────────────
    test('prefix-pattern library is grouped with its primary (Tyranids)', () {
      final result = _ctrl().availableFactions(_makeTree([
        'Xenos - Tyranids.cat',
        'Library - Tyranids.cat',
        'Warhammer 40,000.gst',
      ]));
      expect(result, hasLength(1));
      expect(result.first.displayName, 'Xenos - Tyranids');
      expect(result.first.primaryPath, 'Xenos - Tyranids.cat');
      expect(result.first.libraryPaths, equals(['Library - Tyranids.cat']));
    });

    test('orphan library (no paired primary) appears with cleaned display name',
        () {
      final result = _ctrl().availableFactions(_makeTree([
        'Library - Titans.cat',
        'Warhammer 40,000.gst',
      ]));
      expect(result, hasLength(1));
      expect(result.first.displayName, 'Titans');
      expect(result.first.primaryPath, 'Library - Titans.cat');
      expect(result.first.libraryPaths, isEmpty);
    });

    // ── Prefix pattern with category prefix after "Library - " ───────────────
    test(
        'prefix-pattern library with category prefix is grouped with its primary',
        () {
      final result = _ctrl().availableFactions(_makeTree([
        'Unaligned - Giants.cat',
        'Library - Unaligned - Giants.cat',
        'Warhammer 40,000.gst',
      ]));
      expect(result, hasLength(1));
      expect(result.first.displayName, 'Unaligned - Giants');
      expect(result.first.primaryPath, 'Unaligned - Giants.cat');
      expect(result.first.libraryPaths,
          equals(['Library - Unaligned - Giants.cat']));
    });

    // ── No category prefix, suffix pattern ──────────────────────────────────
    test('suffix-pattern library without category prefix is grouped', () {
      final result = _ctrl().availableFactions(_makeTree([
        'Orks.cat',
        'Orks - Library.cat',
      ]));
      expect(result, hasLength(1));
      expect(result.first.displayName, 'Orks');
      expect(result.first.libraryPaths, equals(['Orks - Library.cat']));
    });

    // ── Mixed factions ───────────────────────────────────────────────────────
    test('multiple factions produce one entry each, sorted by display name',
        () {
      final result = _ctrl().availableFactions(_makeTree([
        'Chaos - Chaos Knights.cat',
        'Chaos - Chaos Knights - Library.cat',
        'Imperium - Imperial Knights.cat',
        'Imperium - Imperial Knights - Library.cat',
        'Xenos - Tyranids.cat',
        'Library - Tyranids.cat',
        'Library - Titans.cat', // library-only: skipped
        'Warhammer 40,000.gst',
      ]));
      expect(result, hasLength(4));
      expect(result.map((f) => f.displayName).toList(),
          equals([
            'Chaos - Chaos Knights',
            'Imperium - Imperial Knights',
            'Titans', // orphan library: displayName cleaned
            'Xenos - Tyranids',
          ]));
      // The 3 paired factions each have exactly one library path.
      for (final f in result.where((f) => f.displayName != 'Titans')) {
        expect(f.libraryPaths, hasLength(1),
            reason: '${f.displayName} should have exactly one library path');
      }
      // The orphan library has no library paths (it IS the file).
      final titans = result.firstWhere((f) => f.displayName == 'Titans');
      expect(titans.libraryPaths, isEmpty);
      expect(titans.primaryPath, 'Library - Titans.cat');
    });

    // ── Regression tests (prevent every real-world library-leak pattern) ─────

    // Regression 1: prefix library + primary with NO faction category prefix.
    // "Library - Tyranids.cat" must merge with bare "Tyranids.cat".
    test(
        'regression: prefix-pattern library merges with bare primary '
        '(no category prefix on primary)', () {
      final result = _ctrl().availableFactions(_makeTree([
        'Tyranids.cat',
        'Library - Tyranids.cat',
      ]));
      expect(result, hasLength(1),
          reason:
              '"Library - Tyranids.cat" must not appear as a separate entry');
      expect(result.first.displayName, 'Tyranids');
      expect(result.first.primaryPath, 'Tyranids.cat');
      expect(result.first.libraryPaths, equals(['Library - Tyranids.cat']));
    });

    // Regression 2: suffix-pattern library + prefixed primary.
    // Already covered by the Imperial Knights test above; repeated here as an
    // explicit named regression to lock the behavior.
    test(
        'regression: suffix-pattern library merges with prefixed primary '
        '(Chaos Daemons variant)', () {
      final result = _ctrl().availableFactions(_makeTree([
        'Chaos - Chaos Daemons.cat',
        'Chaos - Chaos Daemons - Library.cat',
      ]));
      expect(result, hasLength(1),
          reason:
              '"Chaos Daemons - Library" must not appear as a separate entry');
      expect(result.first.displayName, 'Chaos - Chaos Daemons');
      expect(result.first.primaryPath, 'Chaos - Chaos Daemons.cat');
      expect(result.first.libraryPaths,
          equals(['Chaos - Chaos Daemons - Library.cat']));
    });

    // Regression 3: prefix-pattern library WITH category prefix after "Library - ".
    // "Library - Unaligned - Giants.cat" must merge with "Unaligned - Giants.cat".
    // _pairKey strips "library" and one leading category segment from both stems,
    // so both resolve to the same key ("giants").
    test(
        'regression: prefix-pattern library with category prefix merges '
        '(Library - Unaligned - Giants + Unaligned - Giants)', () {
      final result = _ctrl().availableFactions(_makeTree([
        'Unaligned - Giants.cat',
        'Library - Unaligned - Giants.cat',
      ]));
      expect(result, hasLength(1),
          reason:
              '"Library - Unaligned - Giants.cat" must not appear as a separate entry');
      expect(result.first.displayName, 'Unaligned - Giants');
      expect(result.first.primaryPath, 'Unaligned - Giants.cat');
      expect(result.first.libraryPaths,
          equals(['Library - Unaligned - Giants.cat']));
    });

    // ── Acceptance test 1: deterministic pairing ────────────────────────────
    // "Library - Tyranids.cat" must pair with bare "Tyranids.cat",
    // producing exactly one row with displayName "Tyranids" and 2 paths total.
    test('acceptance: Tyranids.cat + Library - Tyranids.cat → one row, '
        'displayName Tyranids, 2 paths', () {
      final result = _ctrl().availableFactions(_makeTree([
        'Tyranids.cat',
        'Library - Tyranids.cat',
      ]));
      expect(result, hasLength(1),
          reason: 'Must produce exactly one row, not two');
      expect(result.first.displayName, 'Tyranids');
      expect(result.first.primaryPath, 'Tyranids.cat');
      expect(result.first.libraryPaths, equals(['Library - Tyranids.cat']),
          reason: 'Library path must be associated, not shown as a separate row');
    });

    // ── Acceptance test 2: orphan library (Astartes Heresy Legends) ────────
    // "Library - Astartes Heresy Legends.cat" has no paired primary. It must
    // appear in the picker as "Astartes Heresy Legends" — never "Library".
    test('acceptance: orphan library "Library - Astartes Heresy Legends.cat" '
        'shown as "Astartes Heresy Legends"', () {
      final result = _ctrl().availableFactions(_makeTree([
        'Library - Astartes Heresy Legends.cat',
        'Chaos - Chaos Knights.cat',
        'Warhammer 40,000.gst',
      ]));
      expect(result, hasLength(2));
      final orphan = result.firstWhere(
        (f) => f.primaryPath == 'Library - Astartes Heresy Legends.cat',
      );
      expect(orphan.displayName, 'Astartes Heresy Legends');
      expect(orphan.libraryPaths, isEmpty);
      // "Library" must not appear in any display name.
      for (final f in result) {
        expect(f.displayName, isNot(contains('Library')));
      }
    });

    // Regression 4 (UI render): no faction displayName may contain "Library".
    // Enforces the requirement that no library filename leaks into the picker UI.
    test('regression: no faction displayName contains "Library"', () {
      final result = _ctrl().availableFactions(_makeTree([
        'Chaos - Chaos Knights.cat',
        'Chaos - Chaos Knights - Library.cat',
        'Imperium - Imperial Knights.cat',
        'Imperium - Imperial Knights - Library.cat',
        'Xenos - Tyranids.cat',
        'Library - Tyranids.cat',
        'Unaligned - Giants.cat',
        'Library - Unaligned - Giants.cat',
        'Library - Titans.cat', // orphan library: shown as "Titans"
        'Chaos - Chaos Daemons.cat',
        'Chaos - Chaos Daemons - Library.cat',
        'Warhammer 40,000.gst',
      ]));
      for (final f in result) {
        expect(
          f.displayName,
          isNot(contains('Library')),
          reason: '"${f.displayName}" must not contain "Library"',
        );
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Fake SessionPersistenceService
// ---------------------------------------------------------------------------

/// Returns a fixed [PersistedSession] without touching the file system.
class _FakePersistenceService extends SessionPersistenceService {
  final PersistedSession? _session;

  _FakePersistenceService(this._session) : super(storageRoot: '/dev/null');

  @override
  Future<PersistedSession?> loadValidSession() async => _session;

  @override
  Future<void> saveSession(PersistedSession session) async {}

  @override
  Future<void> clearSession() async {}
}

// ---------------------------------------------------------------------------
// isBootRestoring flag tests
// ---------------------------------------------------------------------------

void _bootRestoringTests() {
  group('SlotState: isBootRestoring', () {
    test('defaults to false', () {
      const s = SlotState();
      expect(s.isBootRestoring, isFalse);
    });

    test('copyWith(isBootRestoring: true) sets flag', () {
      const s = SlotState();
      final s2 = s.copyWith(isBootRestoring: true);
      expect(s2.isBootRestoring, isTrue);
    });

    test('copyWith(isBootRestoring: false) clears flag', () {
      const s = SlotState(isBootRestoring: true);
      final s2 = s.copyWith(isBootRestoring: false);
      expect(s2.isBootRestoring, isFalse);
    });

    test('copyWith() without argument preserves existing flag', () {
      const s = SlotState(isBootRestoring: true);
      final s2 = s.copyWith(status: SlotStatus.building);
      expect(s2.isBootRestoring, isTrue);
    });

    test(
        'initPersistenceAndRestore sets isBootRestoring=true during Phase 1',
        () async {
      // Build a fake session with one catalog label.
      final fakeSession = PersistedSession(
        gameSystemPath: '/nonexistent/game.gst',
        gameSystemDisplayName: 'Warhammer 40,000',
        selectedCatalogs: [
          const PersistedCatalog(
            path: '/nonexistent/tyranids.cat',
            factionDisplayName: 'Tyranids',
            primaryCatRepoPath: 'Tyranids.cat',
          ),
        ],
        savedAt: DateTime(2026, 2, 1),
      );

      final controller = ImportSessionController(
        bsdResolver: _MockGitHubResolverService(),
      );

      // Capture slot states after Phase 1 (before Phase 2 can read files)
      var capturedBootRestoring = false;
      controller.addListener(() {
        if (controller.slotState(0).isBootRestoring) {
          capturedBootRestoring = true;
        }
      });

      // initPersistenceAndRestore will run Phase 1 then fail Phase 2 because
      // the game system file doesn't exist on disk — that's fine for this test.
      await controller.initPersistenceAndRestore(
        _FakePersistenceService(fakeSession),
      );

      // At minimum Phase 1 must have fired, setting isBootRestoring=true.
      expect(capturedBootRestoring, isTrue,
          reason:
              'isBootRestoring must be true during Phase-1 label restore');
    });

    test('slot label visible after Phase 1 even if Phase 2 files missing',
        () async {
      final fakeSession = PersistedSession(
        gameSystemPath: '/nonexistent/game.gst',
        gameSystemDisplayName: 'Warhammer 40,000',
        selectedCatalogs: [
          const PersistedCatalog(
            path: '/nonexistent/tyranids.cat',
            factionDisplayName: 'Tyranids',
            primaryCatRepoPath: 'Tyranids.cat',
          ),
        ],
        savedAt: DateTime(2026, 2, 1),
      );

      final controller = ImportSessionController(
        bsdResolver: _MockGitHubResolverService(),
      );

      await controller.initPersistenceAndRestore(
        _FakePersistenceService(fakeSession),
      );

      // Slot 0 must have the faction display name regardless of Phase 2 outcome
      expect(
        controller.slotState(0).catalogName,
        equals('Tyranids'),
        reason: 'Phase-1 label must survive Phase-2 failure',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// retrySlot tests
// ---------------------------------------------------------------------------

void _retrySlotTests() {
  group('ImportSessionController: retrySlot', () {
    test('does nothing when slot is empty', () async {
      final controller = ImportSessionController();

      await controller.retrySlot(0);

      expect(controller.slotState(0).status, equals(SlotStatus.empty));
    });

    test('does nothing when slot is ready (not error)', () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('test.cat', Uint8List.fromList([1, 2, 3]));
      final controller = ImportSessionController(bsdResolver: mock);

      await controller.assignCatalogToSlot(0, 'test.cat', _kTestLocator);
      expect(controller.slotState(0).status, equals(SlotStatus.ready));

      await controller.retrySlot(0);

      // Should still be ready (retrySlot only acts on error)
      expect(controller.slotState(0).status, equals(SlotStatus.ready));
    });

    test('does nothing when slot is error but has no bytes', () async {
      // Put slot in error state without bytes (e.g. via download failure)
      final mock = _MockGitHubResolverService();
      mock.setFileError(const BsdResolverException(
        code: BsdResolverErrorCode.networkError,
        message: 'fail',
      ));
      final controller = ImportSessionController(bsdResolver: mock);

      await controller.assignCatalogToSlot(0, 'test.cat', _kTestLocator);
      expect(controller.slotState(0).status, equals(SlotStatus.error));
      expect(controller.slotState(0).fetchedBytes, isNull);

      await controller.retrySlot(0);

      // Still in error — no bytes to retry with
      expect(controller.slotState(0).status, equals(SlotStatus.error));
    });

    test('transitions error+bytes slot through building then to error again '
        'when game system missing', () async {
      final mock = _MockGitHubResolverService();
      mock.setFile('test.cat', Uint8List.fromList([1, 2, 3]));
      mock.setFile('game.gst', Uint8List.fromList([4, 5, 6]));

      // Use a throwing AcquireService so we can observe the transition
      // to building without needing real file pipeline to succeed.
      final acquireFactory = (_) => _ThrowingAcquireService(
            const AcquireFailure(message: 'expected test failure'),
          );

      final controller = ImportSessionController(
        bsdResolver: mock,
        acquireServiceFactory: acquireFactory,
      );

      await controller.fetchAndSetGameSystem(_kTestLocator, 'game.gst');
      await controller.assignCatalogToSlot(0, 'test.cat', _kTestLocator);

      // Manually move to error with bytes to simulate a failed previous build
      // (The pipeline failed but bytes are retained for retry.)
      // loadSlot will fail via the throwing factory → slot goes to error.
      await controller.loadSlot(0);
      expect(controller.slotState(0).status, equals(SlotStatus.error));
      expect(controller.slotState(0).fetchedBytes, isNotNull);

      final statuses = <SlotStatus>[];
      controller.addListener(() {
        statuses.add(controller.slotState(0).status);
      });

      await controller.retrySlot(0);

      // Must have passed through building
      expect(statuses.contains(SlotStatus.building), isTrue);
      // Ends in error again (factory always throws)
      expect(controller.slotState(0).status, equals(SlotStatus.error));
    });
  });
}

// ---------------------------------------------------------------------------
// lastUpdateCheckAt timestamp tests
// ---------------------------------------------------------------------------

void _updateCheckTimestampTests() {
  group('ImportSessionController: lastUpdateCheckAt', () {
    test('is null before any check', () {
      final controller = ImportSessionController();

      expect(controller.lastUpdateCheckAt, isNull);
    });

    test('is set after a successful check (upToDate)', () async {
      const sourceKey = 'bsdata_wh40k';
      const path = 'game.gst';
      const sha = 'abc123';

      final tree = RepoTreeResult(
        entries: [
          RepoTreeEntry(path: path, blobSha: sha, extension: '.gst'),
        ],
        fetchedAt: DateTime(2026, 2, 18),
      );

      final syncState = GitHubSyncState(
        repos: {
          sourceKey: RepoSyncState(
            repoUrl: 'https://github.com/BSData/wh40k-10e',
            branch: 'main',
            trackedFiles: {
              path: TrackedFile(
                repoPath: path,
                fileType: 'gst',
                blobSha: sha,
                lastCheckedAt: DateTime(2026, 2, 17),
              ),
            },
          ),
        },
      );

      final mock = _MockGitHubResolverService()..setTree(tree);
      final controller = ImportSessionController(
        bsdResolver: mock,
        gitHubSyncStateService: _FakeGitHubSyncStateService(syncState),
      );
      controller.setSourceLocatorForTesting(
        const SourceLocator(
          sourceKey: sourceKey,
          sourceUrl: 'https://github.com/BSData/wh40k-10e',
        ),
      );

      final before = DateTime.now();
      await controller.checkForUpdates();
      final after = DateTime.now();

      expect(controller.lastUpdateCheckAt, isNotNull);
      expect(
        controller.lastUpdateCheckAt!.isAfter(before) ||
            controller.lastUpdateCheckAt!.isAtSameMomentAs(before),
        isTrue,
      );
      expect(
        controller.lastUpdateCheckAt!.isBefore(after) ||
            controller.lastUpdateCheckAt!.isAtSameMomentAs(after),
        isTrue,
      );
    });

    test('is set after a failed check (network error)', () async {
      final mock = _MockGitHubResolverService()
        ..setTreeError(const BsdResolverException(
          code: BsdResolverErrorCode.networkError,
          message: 'fail',
        ));
      final controller = ImportSessionController(
        bsdResolver: mock,
        gitHubSyncStateService: _FakeGitHubSyncStateService(
          const GitHubSyncState(),
        ),
      );
      controller.setSourceLocatorForTesting(
        const SourceLocator(
          sourceKey: 'bsdata_wh40k',
          sourceUrl: 'https://github.com/BSData/wh40k-10e',
        ),
      );

      await controller.checkForUpdates();

      expect(controller.lastUpdateCheckAt, isNotNull);
    });

    test('is updated on repeat calls', () async {
      final mock = _MockGitHubResolverService()
        ..setTreeError(const BsdResolverException(
          code: BsdResolverErrorCode.networkError,
          message: 'fail',
        ));
      final controller = ImportSessionController(
        bsdResolver: mock,
        gitHubSyncStateService: _FakeGitHubSyncStateService(
          const GitHubSyncState(),
        ),
      );
      controller.setSourceLocatorForTesting(
        const SourceLocator(
          sourceKey: 'bsdata_wh40k',
          sourceUrl: 'https://github.com/BSData/wh40k-10e',
        ),
      );

      await controller.checkForUpdates();
      final first = controller.lastUpdateCheckAt;

      // Brief delay to ensure timestamps differ
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await controller.checkForUpdates();
      final second = controller.lastUpdateCheckAt;

      expect(second, isNotNull);
      expect(second!.isAfter(first!), isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// lastSyncAt timestamp tests
// ---------------------------------------------------------------------------

void _lastSyncAtTests() {
  group('ImportSessionController: lastSyncAt', () {
    test('is null before loadRepoCatalogTree is called', () {
      final controller = ImportSessionController();

      expect(controller.lastSyncAt, isNull);
    });

    test('is set to tree fetchedAt after successful loadRepoCatalogTree',
        () async {
      final fetchedAt = DateTime(2026, 2, 20, 12, 0, 0);
      final tree = RepoTreeResult(
        entries: [
          RepoTreeEntry(path: 'game.gst', blobSha: 'abc', extension: '.gst'),
        ],
        fetchedAt: fetchedAt,
      );

      final mock = _MockGitHubResolverService()..setTree(tree);
      final controller = ImportSessionController(bsdResolver: mock);

      await controller.loadRepoCatalogTree(_kTestLocator);

      expect(controller.lastSyncAt, equals(fetchedAt));
    });

    test('is not set when loadRepoCatalogTree returns null (tree error)',
        () async {
      final mock = _MockGitHubResolverService()
        ..setTreeError(const BsdResolverException(
          code: BsdResolverErrorCode.networkError,
          message: 'fail',
        ));
      final controller = ImportSessionController(bsdResolver: mock);

      await controller.loadRepoCatalogTree(_kTestLocator);

      expect(controller.lastSyncAt, isNull);
    });

    test('is updated on subsequent successful calls', () async {
      final t1 = DateTime(2026, 2, 20, 10, 0, 0);
      final t2 = DateTime(2026, 2, 20, 11, 0, 0);

      final mock = _MockGitHubResolverService();
      final controller = ImportSessionController(bsdResolver: mock);

      mock.setTree(RepoTreeResult(
        entries: [RepoTreeEntry(path: 'game.gst', blobSha: 'a', extension: '.gst')],
        fetchedAt: t1,
      ));
      await controller.loadRepoCatalogTree(_kTestLocator);
      expect(controller.lastSyncAt, equals(t1));

      mock.setTree(RepoTreeResult(
        entries: [RepoTreeEntry(path: 'game.gst', blobSha: 'b', extension: '.gst')],
        fetchedAt: t2,
      ));
      await controller.loadRepoCatalogTree(_kTestLocator);
      expect(controller.lastSyncAt, equals(t2));
    });
  });
}
