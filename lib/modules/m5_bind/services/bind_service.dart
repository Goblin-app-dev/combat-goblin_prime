import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';

import '../models/bind_diagnostic.dart';
import '../models/bound_category.dart';
import '../models/bound_constraint.dart';
import '../models/bound_cost.dart';
import '../models/bound_entry.dart';
import '../models/bound_pack_bundle.dart';
import '../models/bound_profile.dart';

/// Service for binding LinkedPackBundle into typed, queryable entities.
///
/// Uses M4's resolved target ordering as single source of truth.
/// Implements eligibility filtering before matching.
/// Never binds a node solely because id matches.
///
/// Entry-root detection: An entry is a "root" if its parent is not an
/// eligible entry tag. This is container-agnostic and robust across
/// schema variants.
///
/// Part of M5 Bind (Phase 3).
class BindService {
  /// Eligible tagNames for BoundEntry.
  static const _entryTags = {'selectionEntry', 'selectionEntryGroup'};

  /// Eligible tagNames for BoundProfile.
  static const _profileTags = {'profile'};

  /// Eligible tagNames for BoundCategory.
  static const _categoryTags = {'categoryEntry'};

  /// Eligible tagNames for BoundCost.
  static const _costTags = {'cost'};

  /// Eligible tagNames for BoundConstraint.
  static const _constraintTags = {'constraint'};

  /// Link element tags that need resolution.
  static const _entryLinkTags = {'entryLink'};
  static const _infoLinkTags = {'infoLink'};
  static const _categoryLinkTags = {'categoryLink'};

  /// Binds a LinkedPackBundle into a BoundPackBundle.
  Future<BoundPackBundle> bindBundle({
    required LinkedPackBundle linkedBundle,
  }) async {
    final diagnostics = <BindDiagnostic>[];

    // Build lookup for resolved refs by (sourceFileId, sourceNode)
    final resolvedRefIndex = _buildResolvedRefIndex(linkedBundle);

    // Build node lookup for quick access
    final nodeLookup = _buildNodeLookup(linkedBundle.wrappedBundle);

    // Build file lookup for characteristic extraction (fileId → WrappedFile)
    final fileLookup = _buildFileLookup(linkedBundle.wrappedBundle);

    // Collect all bound entities in binding order
    final allEntries = <BoundEntry>[];
    final allProfiles = <BoundProfile>[];
    final allCategories = <BoundCategory>[];

    // Process files in file resolution order
    final files = _filesInResolutionOrder(linkedBundle.wrappedBundle);

    for (final file in files) {
      // Process nodes in node order (already M3 traversal order)
      for (final node in file.nodes) {
        // Entry-root detection: bind if eligible entry AND parent is not an entry
        if (_entryTags.contains(node.tagName)) {
          final isEntryRoot = _isEntryRoot(node, file);
          if (isEntryRoot) {
            final entry = _bindEntry(
              node: node,
              file: file,
              resolvedRefIndex: resolvedRefIndex,
              nodeLookup: nodeLookup,
              fileLookup: fileLookup,
              diagnostics: diagnostics,
            );
            if (entry != null) {
              allEntries.add(entry);
              // Collect nested entities
              _collectNestedEntities(entry, allEntries, allProfiles, allCategories);
            }
          }
        }
        // Profile-root detection: bind if eligible profile AND no entry ancestor
        else if (_profileTags.contains(node.tagName)) {
          final isProfileRoot = !_hasEntryAncestor(node, file);
          if (isProfileRoot) {
            final profile = _bindProfile(node: node, file: file);
            if (profile != null) {
              allProfiles.add(profile);
            }
          }
        }
        // Category-root detection: bind if eligible category AND no entry ancestor
        else if (_categoryTags.contains(node.tagName)) {
          final isCategoryRoot = !_hasEntryAncestor(node, file);
          if (isCategoryRoot) {
            final category = _bindCategory(node: node, file: file);
            if (category != null) {
              allCategories.add(category);
            }
          }
        }
      }
    }

    return BoundPackBundle(
      packId: linkedBundle.packId,
      boundAt: linkedBundle.linkedAt, // Deterministic: derived from upstream
      entries: allEntries,
      profiles: allProfiles,
      categories: allCategories,
      diagnostics: diagnostics,
      linkedBundle: linkedBundle,
    );
  }

  /// Returns true if this entry node is an "entry root" (not nested in another entry).
  bool _isEntryRoot(WrappedNode node, WrappedFile file) {
    if (node.parent == null) return true;
    final parentNode = file.nodes[node.parent!.nodeIndex];
    // Entry root = parent is not an eligible entry tag
    return !_entryTags.contains(parentNode.tagName);
  }

  /// Returns true if this node has an entry ancestor (is nested inside an entry).
  bool _hasEntryAncestor(WrappedNode node, WrappedFile file) {
    var current = node.parent;
    while (current != null) {
      final parentNode = file.nodes[current.nodeIndex];
      if (_entryTags.contains(parentNode.tagName)) {
        return true;
      }
      current = parentNode.parent;
    }
    return false;
  }

  /// Returns files in file resolution order.
  List<WrappedFile> _filesInResolutionOrder(WrappedPackBundle bundle) {
    return [
      bundle.primaryCatalog,
      ...bundle.dependencyCatalogs,
      bundle.gameSystem,
    ];
  }

  /// Builds index from (fileId, nodeIndex) to ResolvedRef.
  Map<(String, int), ResolvedRef> _buildResolvedRefIndex(
      LinkedPackBundle bundle) {
    final index = <(String, int), ResolvedRef>{};
    for (final ref in bundle.resolvedRefs) {
      index[(ref.sourceFileId, ref.sourceNode.nodeIndex)] = ref;
    }
    return index;
  }

  /// Builds lookup from (fileId, nodeIndex) to WrappedNode.
  Map<(String, int), WrappedNode> _buildNodeLookup(WrappedPackBundle bundle) {
    final lookup = <(String, int), WrappedNode>{};
    for (final file in _filesInResolutionOrder(bundle)) {
      for (final node in file.nodes) {
        lookup[(file.fileId, node.ref.nodeIndex)] = node;
      }
    }
    return lookup;
  }

  /// Builds lookup from fileId to WrappedFile.
  Map<String, WrappedFile> _buildFileLookup(WrappedPackBundle bundle) {
    final lookup = <String, WrappedFile>{};
    for (final file in _filesInResolutionOrder(bundle)) {
      lookup[file.fileId] = file;
    }
    return lookup;
  }

  /// Binds an entry node (selectionEntry or selectionEntryGroup).
  BoundEntry? _bindEntry({
    required WrappedNode node,
    required WrappedFile file,
    required Map<(String, int), ResolvedRef> resolvedRefIndex,
    required Map<(String, int), WrappedNode> nodeLookup,
    required Map<String, WrappedFile> fileLookup,
    required List<BindDiagnostic> diagnostics,
  }) {
    // Verify eligibility
    if (!_entryTags.contains(node.tagName)) {
      return null;
    }

    final id = node.attributes['id'];
    if (id == null) return null;

    final name = node.attributes['name'] ?? '';
    final isGroup = node.tagName == 'selectionEntryGroup';
    final isHidden = node.attributes['hidden'] == 'true';

    // Bind children (nested entries + resolved entryLinks)
    final children = <BoundEntry>[];
    final profiles = <BoundProfile>[];
    final categories = <BoundCategory>[];
    final costs = <BoundCost>[];
    final constraints = <BoundConstraint>[];

    for (final childRef in node.children) {
      final childNode = file.nodes[childRef.nodeIndex];

      // Nested entry
      if (_entryTags.contains(childNode.tagName)) {
        final childEntry = _bindEntry(
          node: childNode,
          file: file,
          resolvedRefIndex: resolvedRefIndex,
          nodeLookup: nodeLookup,
          fileLookup: fileLookup,
          diagnostics: diagnostics,
        );
        if (childEntry != null) {
          children.add(childEntry);
        }
      }
      // entryLink - resolve and bind target
      else if (_entryLinkTags.contains(childNode.tagName)) {
        final resolved = _resolveEntryLink(
          linkNode: childNode,
          file: file,
          resolvedRefIndex: resolvedRefIndex,
          nodeLookup: nodeLookup,
          diagnostics: diagnostics,
        );
        if (resolved != null) {
          children.add(resolved);
        }
      }
      // Nested profile
      else if (_profileTags.contains(childNode.tagName)) {
        final profile = _bindProfile(node: childNode, file: file);
        if (profile != null) {
          profiles.add(profile);
        }
      }
      // infoLink - resolve and bind target profile
      else if (_infoLinkTags.contains(childNode.tagName)) {
        final resolved = _resolveInfoLink(
          linkNode: childNode,
          file: file,
          resolvedRefIndex: resolvedRefIndex,
          nodeLookup: nodeLookup,
          fileLookup: fileLookup,
          diagnostics: diagnostics,
        );
        if (resolved != null) {
          profiles.add(resolved);
        }
      }
      // Nested categoryEntry
      else if (_categoryTags.contains(childNode.tagName)) {
        final category = _bindCategory(node: childNode, file: file);
        if (category != null) {
          categories.add(category);
        }
      }
      // categoryLink - resolve and bind target category
      else if (_categoryLinkTags.contains(childNode.tagName)) {
        final resolved = _resolveCategoryLink(
          linkNode: childNode,
          file: file,
          resolvedRefIndex: resolvedRefIndex,
          nodeLookup: nodeLookup,
          diagnostics: diagnostics,
        );
        if (resolved != null) {
          categories.add(resolved);
        }
      }
      // Nested cost
      else if (_costTags.contains(childNode.tagName)) {
        final cost = _bindCost(node: childNode, file: file);
        if (cost != null) {
          costs.add(cost);
        }
      }
      // Nested constraint
      else if (_constraintTags.contains(childNode.tagName)) {
        final constraint = _bindConstraint(node: childNode, file: file);
        if (constraint != null) {
          constraints.add(constraint);
        }
      }
      // Recurse into containers that may hold nested content
      else if (_isContainer(childNode.tagName)) {
        _bindContainerChildren(
          container: childNode,
          file: file,
          resolvedRefIndex: resolvedRefIndex,
          nodeLookup: nodeLookup,
          fileLookup: fileLookup,
          diagnostics: diagnostics,
          children: children,
          profiles: profiles,
          categories: categories,
          costs: costs,
          constraints: constraints,
        );
      }
    }

    return BoundEntry(
      id: id,
      name: name,
      isGroup: isGroup,
      isHidden: isHidden,
      children: children,
      profiles: profiles,
      categories: categories,
      costs: costs,
      constraints: constraints,
      sourceFileId: file.fileId,
      sourceNode: node.ref,
    );
  }

  /// Container tags that may hold bindable content.
  bool _isContainer(String tagName) {
    return const {
      'selectionEntries',
      'selectionEntryGroups',
      'entryLinks',
      'profiles',
      'infoLinks',
      'categoryLinks',
      'costs',
      'constraints',
      'categories',
    }.contains(tagName);
  }

  /// Binds children within a container element.
  void _bindContainerChildren({
    required WrappedNode container,
    required WrappedFile file,
    required Map<(String, int), ResolvedRef> resolvedRefIndex,
    required Map<(String, int), WrappedNode> nodeLookup,
    required Map<String, WrappedFile> fileLookup,
    required List<BindDiagnostic> diagnostics,
    required List<BoundEntry> children,
    required List<BoundProfile> profiles,
    required List<BoundCategory> categories,
    required List<BoundCost> costs,
    required List<BoundConstraint> constraints,
  }) {
    for (final childRef in container.children) {
      final childNode = file.nodes[childRef.nodeIndex];

      if (_entryTags.contains(childNode.tagName)) {
        final entry = _bindEntry(
          node: childNode,
          file: file,
          resolvedRefIndex: resolvedRefIndex,
          nodeLookup: nodeLookup,
          fileLookup: fileLookup,
          diagnostics: diagnostics,
        );
        if (entry != null) children.add(entry);
      } else if (_entryLinkTags.contains(childNode.tagName)) {
        final entry = _resolveEntryLink(
          linkNode: childNode,
          file: file,
          resolvedRefIndex: resolvedRefIndex,
          nodeLookup: nodeLookup,
          diagnostics: diagnostics,
        );
        if (entry != null) children.add(entry);
      } else if (_profileTags.contains(childNode.tagName)) {
        final profile = _bindProfile(node: childNode, file: file);
        if (profile != null) profiles.add(profile);
      } else if (_infoLinkTags.contains(childNode.tagName)) {
        final profile = _resolveInfoLink(
          linkNode: childNode,
          file: file,
          resolvedRefIndex: resolvedRefIndex,
          nodeLookup: nodeLookup,
          fileLookup: fileLookup,
          diagnostics: diagnostics,
        );
        if (profile != null) profiles.add(profile);
      } else if (_categoryTags.contains(childNode.tagName)) {
        final category = _bindCategory(node: childNode, file: file);
        if (category != null) categories.add(category);
      } else if (_categoryLinkTags.contains(childNode.tagName)) {
        final category = _resolveCategoryLink(
          linkNode: childNode,
          file: file,
          resolvedRefIndex: resolvedRefIndex,
          nodeLookup: nodeLookup,
          diagnostics: diagnostics,
        );
        if (category != null) categories.add(category);
      } else if (_costTags.contains(childNode.tagName)) {
        final cost = _bindCost(node: childNode, file: file);
        if (cost != null) costs.add(cost);
      } else if (_constraintTags.contains(childNode.tagName)) {
        final constraint = _bindConstraint(node: childNode, file: file);
        if (constraint != null) constraints.add(constraint);
      }
    }
  }

  /// Resolves an entryLink to its target entry.
  BoundEntry? _resolveEntryLink({
    required WrappedNode linkNode,
    required WrappedFile file,
    required Map<(String, int), ResolvedRef> resolvedRefIndex,
    required Map<(String, int), WrappedNode> nodeLookup,
    required List<BindDiagnostic> diagnostics,
  }) {
    final resolvedRef = resolvedRefIndex[(file.fileId, linkNode.ref.nodeIndex)];
    if (resolvedRef == null || resolvedRef.targets.isEmpty) {
      diagnostics.add(BindDiagnostic(
        code: BindDiagnosticCode.unresolvedEntryLink,
        message: 'entryLink target not found: ${linkNode.attributes['targetId']}',
        sourceFileId: file.fileId,
        sourceNode: linkNode.ref,
        targetId: linkNode.attributes['targetId'],
      ));
      return null;
    }

    // Iterate targets in order, select first with eligible tagName
    WrappedNode? selectedNode;
    String? selectedFileId;
    final skippedTargets = <String>[];

    for (final target in resolvedRef.targets) {
      final targetNode = nodeLookup[(target.fileId, target.nodeRef.nodeIndex)];
      if (targetNode == null) continue;

      if (_entryTags.contains(targetNode.tagName)) {
        if (selectedNode == null) {
          selectedNode = targetNode;
          selectedFileId = target.fileId;
        } else {
          skippedTargets.add('${target.fileId}:${target.nodeRef.nodeIndex}');
        }
      } else {
        skippedTargets.add('${target.fileId}:${target.nodeRef.nodeIndex} (ineligible: ${targetNode.tagName})');
      }
    }

    if (selectedNode == null) {
      diagnostics.add(BindDiagnostic(
        code: BindDiagnosticCode.unresolvedEntryLink,
        message: 'entryLink resolved but no eligible entry target',
        sourceFileId: file.fileId,
        sourceNode: linkNode.ref,
        targetId: linkNode.attributes['targetId'],
      ));
      return null;
    }

    if (skippedTargets.isNotEmpty) {
      diagnostics.add(BindDiagnostic(
        code: BindDiagnosticCode.shadowedDefinition,
        message: 'entryLink shadowed targets: ${skippedTargets.join(', ')}',
        sourceFileId: file.fileId,
        sourceNode: linkNode.ref,
        targetId: linkNode.attributes['targetId'],
      ));
    }

    return BoundEntry(
      id: selectedNode.attributes['id'] ?? '',
      name: selectedNode.attributes['name'] ?? '',
      isGroup: selectedNode.tagName == 'selectionEntryGroup',
      isHidden: selectedNode.attributes['hidden'] == 'true',
      children: const [], // Linked entries don't recurse further
      profiles: const [],
      categories: const [],
      costs: const [],
      constraints: const [],
      sourceFileId: selectedFileId!,
      sourceNode: selectedNode.ref,
    );
  }

  /// Resolves an infoLink to its target profile.
  BoundProfile? _resolveInfoLink({
    required WrappedNode linkNode,
    required WrappedFile file,
    required Map<(String, int), ResolvedRef> resolvedRefIndex,
    required Map<(String, int), WrappedNode> nodeLookup,
    required Map<String, WrappedFile> fileLookup,
    required List<BindDiagnostic> diagnostics,
  }) {
    final resolvedRef = resolvedRefIndex[(file.fileId, linkNode.ref.nodeIndex)];
    if (resolvedRef == null || resolvedRef.targets.isEmpty) {
      diagnostics.add(BindDiagnostic(
        code: BindDiagnosticCode.unresolvedInfoLink,
        message: 'infoLink target not found: ${linkNode.attributes['targetId']}',
        sourceFileId: file.fileId,
        sourceNode: linkNode.ref,
        targetId: linkNode.attributes['targetId'],
      ));
      return null;
    }

    // Iterate targets in order, select first with eligible tagName
    WrappedNode? selectedNode;
    String? selectedFileId;
    final skippedTargets = <String>[];

    for (final target in resolvedRef.targets) {
      final targetNode = nodeLookup[(target.fileId, target.nodeRef.nodeIndex)];
      if (targetNode == null) continue;

      if (_profileTags.contains(targetNode.tagName)) {
        if (selectedNode == null) {
          selectedNode = targetNode;
          selectedFileId = target.fileId;
        } else {
          skippedTargets.add('${target.fileId}:${target.nodeRef.nodeIndex}');
        }
      } else {
        skippedTargets.add('${target.fileId}:${target.nodeRef.nodeIndex} (ineligible: ${targetNode.tagName})');
      }
    }

    if (selectedNode == null) {
      diagnostics.add(BindDiagnostic(
        code: BindDiagnosticCode.unresolvedInfoLink,
        message: 'infoLink resolved but no eligible profile target',
        sourceFileId: file.fileId,
        sourceNode: linkNode.ref,
        targetId: linkNode.attributes['targetId'],
      ));
      return null;
    }

    if (skippedTargets.isNotEmpty) {
      diagnostics.add(BindDiagnostic(
        code: BindDiagnosticCode.shadowedDefinition,
        message: 'infoLink shadowed targets: ${skippedTargets.join(', ')}',
        sourceFileId: file.fileId,
        sourceNode: linkNode.ref,
        targetId: linkNode.attributes['targetId'],
      ));
    }

    // Resolve file for characteristic extraction
    final targetFile = fileLookup[selectedFileId!];
    if (targetFile == null) {
      diagnostics.add(BindDiagnostic(
        code: BindDiagnosticCode.unresolvedInfoLink,
        message: 'infoLink target file not found: $selectedFileId',
        sourceFileId: file.fileId,
        sourceNode: linkNode.ref,
        targetId: linkNode.attributes['targetId'],
      ));
      return null;
    }

    return _bindProfileFromNode(selectedNode, targetFile);
  }

  /// Resolves a categoryLink to its target category.
  BoundCategory? _resolveCategoryLink({
    required WrappedNode linkNode,
    required WrappedFile file,
    required Map<(String, int), ResolvedRef> resolvedRefIndex,
    required Map<(String, int), WrappedNode> nodeLookup,
    required List<BindDiagnostic> diagnostics,
  }) {
    final resolvedRef = resolvedRefIndex[(file.fileId, linkNode.ref.nodeIndex)];
    if (resolvedRef == null || resolvedRef.targets.isEmpty) {
      diagnostics.add(BindDiagnostic(
        code: BindDiagnosticCode.unresolvedCategoryLink,
        message: 'categoryLink target not found: ${linkNode.attributes['targetId']}',
        sourceFileId: file.fileId,
        sourceNode: linkNode.ref,
        targetId: linkNode.attributes['targetId'],
      ));
      return null;
    }

    // Iterate targets in order, select first with eligible tagName
    WrappedNode? selectedNode;
    String? selectedFileId;
    final skippedTargets = <String>[];

    for (final target in resolvedRef.targets) {
      final targetNode = nodeLookup[(target.fileId, target.nodeRef.nodeIndex)];
      if (targetNode == null) continue;

      if (_categoryTags.contains(targetNode.tagName)) {
        if (selectedNode == null) {
          selectedNode = targetNode;
          selectedFileId = target.fileId;
        } else {
          skippedTargets.add('${target.fileId}:${target.nodeRef.nodeIndex}');
        }
      } else {
        skippedTargets.add('${target.fileId}:${target.nodeRef.nodeIndex} (ineligible: ${targetNode.tagName})');
      }
    }

    if (selectedNode == null) {
      diagnostics.add(BindDiagnostic(
        code: BindDiagnosticCode.unresolvedCategoryLink,
        message: 'categoryLink resolved but no eligible categoryEntry target',
        sourceFileId: file.fileId,
        sourceNode: linkNode.ref,
        targetId: linkNode.attributes['targetId'],
      ));
      return null;
    }

    if (skippedTargets.isNotEmpty) {
      diagnostics.add(BindDiagnostic(
        code: BindDiagnosticCode.shadowedDefinition,
        message: 'categoryLink shadowed targets: ${skippedTargets.join(', ')}',
        sourceFileId: file.fileId,
        sourceNode: linkNode.ref,
        targetId: linkNode.attributes['targetId'],
      ));
    }

    // Use primary from the link node itself
    final isPrimary = linkNode.attributes['primary'] == 'true';

    return BoundCategory(
      id: selectedNode.attributes['id'] ?? '',
      name: selectedNode.attributes['name'] ?? '',
      isPrimary: isPrimary,
      sourceFileId: selectedFileId!,
      sourceNode: selectedNode.ref,
    );
  }

  /// Binds a profile node.
  BoundProfile? _bindProfile({
    required WrappedNode node,
    required WrappedFile file,
  }) {
    if (!_profileTags.contains(node.tagName)) return null;
    return _bindProfileFromNode(node, file);
  }

  /// Binds a profile from a node with access to file for child node resolution.
  BoundProfile _bindProfileFromNode(WrappedNode node, WrappedFile file) {
    final id = node.attributes['id'] ?? '';
    final name = node.attributes['name'] ?? '';
    final typeId = node.attributes['typeId'];
    final typeName = node.attributes['typeName'];

    // Extract characteristics from nested characteristic elements
    // Structure: <profile><characteristics><characteristic name="M">6"</characteristic>...
    final characteristics = <({String name, String value})>[];
    for (final childRef in node.children) {
      final childNode = file.nodeAt(childRef);
      if (childNode.tagName == 'characteristics') {
        // Found characteristics container, extract individual characteristics
        for (final charRef in childNode.children) {
          final charNode = file.nodeAt(charRef);
          if (charNode.tagName == 'characteristic') {
            final charName = charNode.attributes['name'] ?? '';
            final charValue = charNode.textContent ?? '';
            characteristics.add((name: charName, value: charValue));
          }
        }
      }
    }

    return BoundProfile(
      id: id,
      name: name,
      typeId: typeId,
      typeName: typeName,
      characteristics: characteristics,
      sourceFileId: file.fileId,
      sourceNode: node.ref,
    );
  }

  /// Binds a category node.
  BoundCategory? _bindCategory({
    required WrappedNode node,
    required WrappedFile file,
  }) {
    if (!_categoryTags.contains(node.tagName)) return null;

    final id = node.attributes['id'] ?? '';
    final name = node.attributes['name'] ?? '';
    final isPrimary = node.attributes['primary'] == 'true';

    return BoundCategory(
      id: id,
      name: name,
      isPrimary: isPrimary,
      sourceFileId: file.fileId,
      sourceNode: node.ref,
    );
  }

  /// Binds a cost node.
  BoundCost? _bindCost({
    required WrappedNode node,
    required WrappedFile file,
  }) {
    if (!_costTags.contains(node.tagName)) return null;

    final typeId = node.attributes['typeId'] ?? '';
    final typeName = node.attributes['name'];
    final valueStr = node.attributes['value'] ?? '0';
    final value = double.tryParse(valueStr) ?? 0.0;

    return BoundCost(
      typeId: typeId,
      typeName: typeName,
      value: value,
      sourceFileId: file.fileId,
      sourceNode: node.ref,
    );
  }

  /// Binds a constraint node.
  BoundConstraint? _bindConstraint({
    required WrappedNode node,
    required WrappedFile file,
  }) {
    if (!_constraintTags.contains(node.tagName)) return null;

    final type = node.attributes['type'] ?? '';
    final field = node.attributes['field'] ?? '';
    final scope = node.attributes['scope'] ?? '';
    final valueStr = node.attributes['value'] ?? '0';
    final value = int.tryParse(valueStr) ?? 0;
    final id = node.attributes['id'];

    return BoundConstraint(
      type: type,
      field: field,
      scope: scope,
      value: value,
      id: id,
      sourceFileId: file.fileId,
      sourceNode: node.ref,
    );
  }

  /// Collects nested entities from a bound entry into flat lists.
  void _collectNestedEntities(
    BoundEntry entry,
    List<BoundEntry> allEntries,
    List<BoundProfile> allProfiles,
    List<BoundCategory> allCategories,
  ) {
    // Add nested profiles
    allProfiles.addAll(entry.profiles);

    // Add nested categories
    allCategories.addAll(entry.categories);

    // Recurse into children
    for (final child in entry.children) {
      allEntries.add(child);
      _collectNestedEntities(child, allEntries, allProfiles, allCategories);
    }
  }
}
