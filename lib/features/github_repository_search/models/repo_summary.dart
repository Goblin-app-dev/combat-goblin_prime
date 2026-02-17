class RepoSummary {
  const RepoSummary({
    required this.fullName,
    required this.htmlUrl,
    required this.description,
    required this.language,
    required this.stargazersCount,
    required this.forksCount,
    required this.updatedAt,
  });

  final String fullName;
  final Uri htmlUrl;
  final String? description;
  final String? language;
  final int stargazersCount;
  final int forksCount;
  final DateTime updatedAt;
}
