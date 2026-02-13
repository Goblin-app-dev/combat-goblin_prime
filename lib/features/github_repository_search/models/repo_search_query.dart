enum RepoSearchSort { stars, updated }

enum SortOrder { desc, asc }

enum RepoSearchMode { flutterDiscovery, exactName }

class RepoSearchQuery {
  const RepoSearchQuery({
    this.text,
    this.sort = RepoSearchSort.stars,
    this.order = SortOrder.desc,
    this.pageSize = 30,
    this.mode = RepoSearchMode.flutterDiscovery,
    this.useFallbackFlutterQuery = false,
  }) : assert(pageSize >= 1 && pageSize <= 100);

  final String? text;
  final RepoSearchSort sort;
  final SortOrder order;
  final int pageSize;
  final RepoSearchMode mode;
  final bool useFallbackFlutterQuery;
}
