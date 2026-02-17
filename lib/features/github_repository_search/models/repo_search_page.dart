import 'repo_search_diagnostics.dart';
import 'repo_summary.dart';

class RepoSearchPage {
  const RepoSearchPage({
    required this.items,
    required this.nextPageToken,
    required this.isLastPage,
    required this.totalCount,
    required this.diagnostics,
  });

  final List<RepoSummary> items;
  final String? nextPageToken;
  final bool isLastPage;
  final int? totalCount;
  final RepoSearchDiagnostics? diagnostics;
}
