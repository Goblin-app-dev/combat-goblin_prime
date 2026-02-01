import 'dart:convert';

import 'package:xml/xml.dart';

import '../models/import_dependency.dart';
import '../models/preflight_scan_result.dart';
import '../models/source_file_type.dart';

class PreflightScanService {
  Future<PreflightScanResult> scanBytes({
    required List<int> bytes,
    required SourceFileType fileType,
  }) async {
    final document =
        XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
    final rootElement = document.rootElement;
    final rootTag = rootElement.name.local;

    _validateRootTag(rootTag, fileType);

    final rootId = rootElement.getAttribute('id');
    if (rootId == null) {
      throw const FormatException('Missing root id.');
    }

    final rootName = rootElement.getAttribute('name');
    final rootRevision = rootElement.getAttribute('revision');
    final rootType = rootElement.getAttribute('type');

    String? declaredGameSystemId;
    String? declaredGameSystemRevision;
    String? libraryFlag;
    final importDependencies = <ImportDependency>[];

    if (fileType == SourceFileType.cat) {
      declaredGameSystemId = rootElement.getAttribute('gameSystemId');
      declaredGameSystemRevision =
          rootElement.getAttribute('gameSystemRevision');
      libraryFlag = rootElement.getAttribute('library');

      final catalogueLinks = rootElement.getElement('catalogueLinks');
      if (catalogueLinks != null) {
        for (final catalogueLink
            in catalogueLinks.findElements('catalogueLink')) {
          final targetId = catalogueLink.getAttribute('targetId');
          if (targetId == null) {
            continue;
          }
          final importRootEntriesValue =
              catalogueLink.getAttribute('importRootEntries');
          final importRootEntries = importRootEntriesValue == 'true';
          importDependencies.add(ImportDependency(
            targetId: targetId,
            importRootEntries: importRootEntries,
          ));
        }
      }
    }

    return PreflightScanResult(
      fileType: fileType,
      rootTag: rootTag,
      rootId: rootId,
      rootName: rootName,
      rootRevision: rootRevision,
      rootType: rootType,
      declaredGameSystemId: declaredGameSystemId,
      declaredGameSystemRevision: declaredGameSystemRevision,
      libraryFlag: libraryFlag,
      importDependencies: importDependencies,
    );
  }
}

void _validateRootTag(String rootTag, SourceFileType fileType) {
  String expectedRootTag;

  switch (fileType) {
    case SourceFileType.gst:
      expectedRootTag = 'gameSystem';
      break;
    case SourceFileType.cat:
      expectedRootTag = 'catalogue';
      break;
  }

  if (rootTag != expectedRootTag) {
    throw FormatException('Unexpected root tag: $rootTag.');
  }
}
