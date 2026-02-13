import '../models/repo_search_page.dart';
import '../models/repo_search_query.dart';

abstract interface class GitHubRepositorySearchService {
  Future<RepoSearchPage> search({
    required RepoSearchQuery query,
    String? pageCursor,
  });
}
