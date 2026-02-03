import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:xml/xml.dart';

import '../models/element_dto.dart';
import '../models/parse_failure.dart';
import '../models/parsed_file.dart';
import '../models/parsed_pack_bundle.dart';

/// Service that parses RawPackBundle into ParsedPackBundle.
///
/// Part of M2 Parse (Phase 1B).
class ParseService {
  /// Parses a RawPackBundle into a ParsedPackBundle.
  ///
  /// Converts each file's bytes into an ElementDto tree.
  /// Preserves document order and links each ParsedFile back to source via fileId.
  ///
  /// Throws [ParseFailure] on malformed XML.
  Future<ParsedPackBundle> parseBundle({
    required RawPackBundle rawBundle,
  }) async {
    final gameSystem = _parseFile(
      bytes: rawBundle.gameSystemBytes,
      fileId: rawBundle.gameSystemMetadata.fileId,
      fileType: rawBundle.gameSystemMetadata.fileType,
      rootId: rawBundle.gameSystemPreflight.rootId,
    );

    final primaryCatalog = _parseFile(
      bytes: rawBundle.primaryCatalogBytes,
      fileId: rawBundle.primaryCatalogMetadata.fileId,
      fileType: rawBundle.primaryCatalogMetadata.fileType,
      rootId: rawBundle.primaryCatalogPreflight.rootId,
    );

    final dependencyCatalogs = <ParsedFile>[];
    for (var i = 0; i < rawBundle.dependencyCatalogBytesList.length; i++) {
      final depFile = _parseFile(
        bytes: rawBundle.dependencyCatalogBytesList[i],
        fileId: rawBundle.dependencyCatalogMetadatas[i].fileId,
        fileType: rawBundle.dependencyCatalogMetadatas[i].fileType,
        rootId: rawBundle.dependencyCatalogPreflights[i].rootId,
      );
      dependencyCatalogs.add(depFile);
    }

    return ParsedPackBundle(
      packId: rawBundle.packId,
      parsedAt: DateTime.now().toUtc(),
      gameSystem: gameSystem,
      primaryCatalog: primaryCatalog,
      dependencyCatalogs: dependencyCatalogs,
    );
  }

  ParsedFile _parseFile({
    required List<int> bytes,
    required String fileId,
    required SourceFileType fileType,
    required String rootId,
  }) {
    final xmlString = String.fromCharCodes(bytes);

    XmlDocument document;
    try {
      document = XmlDocument.parse(xmlString);
    } catch (e) {
      throw ParseFailure(
        message: 'Failed to parse XML',
        fileId: fileId,
        details: e.toString(),
      );
    }

    final rootElement = document.rootElement;
    var indexCounter = 0;
    final root = _convertElement(rootElement, () => indexCounter++);

    return ParsedFile(
      fileId: fileId,
      fileType: fileType,
      rootId: rootId,
      root: root,
    );
  }

  ElementDto _convertElement(XmlElement element, int Function() nextIndex) {
    final attributes = <String, String>{};
    for (final attr in element.attributes) {
      attributes[attr.localName] = attr.value;
    }

    final children = <ElementDto>[];
    for (final child in element.childElements) {
      children.add(_convertElement(child, nextIndex));
    }

    // Get text content (concatenate all text nodes, trim whitespace)
    final textNodes = element.children
        .whereType<XmlText>()
        .map((t) => t.value.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final textContent = textNodes.isEmpty ? null : textNodes.join(' ');

    return ElementDto(
      tagName: element.localName,
      attributes: attributes,
      children: children,
      textContent: textContent,
      sourceIndex: nextIndex(),
    );
  }
}
