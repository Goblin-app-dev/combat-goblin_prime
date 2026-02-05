import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

import '../models/link_diagnostic.dart';
import '../models/linked_pack_bundle.dart';
import '../models/resolved_ref.dart';
import '../models/symbol_table.dart';

/// Service for linking cross-file references in a WrappedPackBundle.
///
/// Resolves only targetId on link elements: catalogueLink, entryLink,
/// infoLink, categoryLink.
///
/// Does NOT resolve childId, typeId, or other ID-bearing attributes.
/// Does NOT verify catalogueLink resolves to root node.
///
/// Part of M4 Link (Phase 2).
class LinkService {
  /// Link element tag names that M4 resolves.
  static const _linkTagNames = {
    'catalogueLink',
    'entryLink',
    'infoLink',
    'categoryLink',
  };

  /// Links all cross-file references in a WrappedPackBundle.
  ///
  /// Returns LinkedPackBundle containing symbol table, resolved refs,
  /// and any diagnostics. Does not throw for normal resolution issues.
  Future<LinkedPackBundle> linkBundle({
    required WrappedPackBundle wrappedBundle,
  }) async {
    // Build symbol table from aggregated idIndex
    final symbolTable = SymbolTable.fromWrappedBundle(wrappedBundle);

    final resolvedRefs = <ResolvedRef>[];
    final diagnostics = <LinkDiagnostic>[];

    // Process files in resolution order
    _processFile(
      wrappedBundle.primaryCatalog,
      symbolTable,
      resolvedRefs,
      diagnostics,
    );

    for (final dep in wrappedBundle.dependencyCatalogs) {
      _processFile(dep, symbolTable, resolvedRefs, diagnostics);
    }

    _processFile(
      wrappedBundle.gameSystem,
      symbolTable,
      resolvedRefs,
      diagnostics,
    );

    return LinkedPackBundle(
      packId: wrappedBundle.packId,
      linkedAt: DateTime.now().toUtc(),
      symbolTable: symbolTable,
      resolvedRefs: resolvedRefs,
      diagnostics: diagnostics,
      wrappedBundle: wrappedBundle,
    );
  }

  /// Process a single file, finding link elements and resolving targetId.
  void _processFile(
    WrappedFile file,
    SymbolTable symbolTable,
    List<ResolvedRef> resolvedRefs,
    List<LinkDiagnostic> diagnostics,
  ) {
    // Traverse nodes in order (0, 1, 2, ...) to find link elements
    for (final node in file.nodes) {
      if (!_linkTagNames.contains(node.tagName)) {
        continue;
      }

      // Extract targetId attribute
      final targetId = node.attributes['targetId'];

      // Check for missing or empty targetId
      if (targetId == null || targetId.trim().isEmpty) {
        diagnostics.add(LinkDiagnostic(
          code: LinkDiagnosticCode.invalidLinkFormat,
          message: targetId == null
              ? 'Link element <${node.tagName}> is missing targetId attribute'
              : 'Link element <${node.tagName}> has empty targetId attribute',
          sourceFileId: file.fileId,
          sourceNode: node.ref,
          targetId: targetId,
        ));
        // No ResolvedRef created for invalid format
        continue;
      }

      // Lookup targetId in symbol table
      final targets = symbolTable.lookup(targetId);

      // Create ResolvedRef
      final resolvedRef = ResolvedRef(
        sourceFileId: file.fileId,
        sourceNode: node.ref,
        targetId: targetId,
        targets: targets,
      );
      resolvedRefs.add(resolvedRef);

      // Emit diagnostics based on target count
      if (targets.isEmpty) {
        diagnostics.add(LinkDiagnostic(
          code: LinkDiagnosticCode.unresolvedTarget,
          message:
              'targetId "$targetId" not found in any file',
          sourceFileId: file.fileId,
          sourceNode: node.ref,
          targetId: targetId,
        ));
      } else if (targets.length > 1) {
        diagnostics.add(LinkDiagnostic(
          code: LinkDiagnosticCode.duplicateIdReference,
          message:
              'targetId "$targetId" found ${targets.length} times across files',
          sourceFileId: file.fileId,
          sourceNode: node.ref,
          targetId: targetId,
        ));
      }
    }
  }
}
