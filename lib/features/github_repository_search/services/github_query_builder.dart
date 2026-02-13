import '../models/repo_search_query.dart';

class GitHubQueryBuilder {
  static const String canonicalFlutterQuery =
      'language:dart topic:flutter archived:false';
  static const String canonicalFlutterFallbackQuery =
      'flutter in:name,description,readme language:dart archived:false';

  String build(RepoSearchQuery query) {
    if (query.mode == RepoSearchMode.flutterDiscovery &&
        (query.text == null || query.text!.trim().isEmpty)) {
      return query.useFallbackFlutterQuery
          ? canonicalFlutterFallbackQuery
          : canonicalFlutterQuery;
    }

    final parts = <String>[];
    if (query.mode == RepoSearchMode.flutterDiscovery) {
      parts.addAll(<String>['archived:false', 'language:dart', 'topic:flutter']);
      final escaped = _escapeFreeText(query.text);
      if (escaped != null) {
        parts.add(escaped);
      }
    } else {
      final escaped = _escapeFreeText(query.text);
      if (escaped != null) {
        parts.add(escaped);
      }
    }
    return parts.join(' ');
  }

  String? _escapeFreeText(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return null;
    }
    final escapedQuotes = normalized.replaceAll('"', r'\"');
    if (escapedQuotes.contains(':') ||
        escapedQuotes.contains('-') ||
        escapedQuotes.contains(' ')) {
      return '"$escapedQuotes"';
    }
    return escapedQuotes;
  }

  String sortParam(RepoSearchSort sort) =>
      sort == RepoSearchSort.updated ? 'updated' : 'stars';

  String orderParam(SortOrder order) => order == SortOrder.asc ? 'asc' : 'desc';
}
