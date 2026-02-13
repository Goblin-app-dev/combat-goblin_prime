import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/repo_search_diagnostics.dart';
import '../models/repo_search_error.dart';
import '../models/repo_search_exception.dart';
import '../models/repo_search_page.dart';
import '../models/repo_search_query.dart';
import '../models/repo_summary.dart';
import 'github_query_builder.dart';
import 'github_repository_search_service.dart';

typedef AuthTokenProvider = String? Function();

class GitHubRepositorySearchServiceHttp
    implements GitHubRepositorySearchService {
  GitHubRepositorySearchServiceHttp({
    required http.Client client,
    required GitHubQueryBuilder queryBuilder,
    AuthTokenProvider? authTokenProvider,
  })  : _client = client,
        _queryBuilder = queryBuilder,
        _authTokenProvider = authTokenProvider;

  static const String _baseUrl = 'https://api.github.com/search/repositories';

  final http.Client _client;
  final GitHubQueryBuilder _queryBuilder;
  final AuthTokenProvider? _authTokenProvider;

  @override
  Future<RepoSearchPage> search({
    required RepoSearchQuery query,
    String? pageCursor,
  }) async {
    final page = int.tryParse(pageCursor ?? '') ?? 1;
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: <String, String>{
        'q': _queryBuilder.build(query),
        'sort': _queryBuilder.sortParam(query.sort),
        'order': _queryBuilder.orderParam(query.order),
        'per_page': query.pageSize.toString(),
        'page': page.toString(),
      },
    );

    final token = _authTokenProvider?.call();
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } on SocketException catch (_) {
      throw const RepoSearchException(RepoSearchError.networkFailure);
    } on http.ClientException catch (_) {
      throw const RepoSearchException(RepoSearchError.networkFailure);
    }

    final diagnostics = RepoSearchDiagnostics(
      statusCode: response.statusCode,
      rateLimitRemaining: int.tryParse(response.headers['x-ratelimit-remaining'] ?? ''),
      rateLimitResetEpochSeconds:
          int.tryParse(response.headers['x-ratelimit-reset'] ?? ''),
      requestId: response.headers['x-github-request-id'],
    );

    if (response.statusCode == 401) {
      throw const RepoSearchException(RepoSearchError.unauthorized);
    }
    if (response.statusCode == 403) {
      if (_isRateLimited(response.headers)) {
        throw const RepoSearchException(RepoSearchError.rateLimited);
      }
      throw const RepoSearchException(RepoSearchError.forbidden);
    }
    if (response.statusCode == 422) {
      throw const RepoSearchException(RepoSearchError.invalidQuery);
    }
    if (response.statusCode >= 500) {
      throw const RepoSearchException(RepoSearchError.serverFailure);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const RepoSearchException(RepoSearchError.serverFailure);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const RepoSearchException(RepoSearchError.invalidResponse);
    }

    if (decoded is! Map<String, dynamic>) {
      throw const RepoSearchException(RepoSearchError.invalidResponse);
    }

    final totalCount = decoded['total_count'] as int?;
    final items = (decoded['items'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(_toRepoSummary)
        .toList(growable: false);

    final isLastPage = items.isEmpty ||
        totalCount == null ||
        (page * query.pageSize) >= totalCount;

    return RepoSearchPage(
      items: items,
      nextPageToken: isLastPage ? null : (page + 1).toString(),
      isLastPage: isLastPage,
      totalCount: totalCount,
      diagnostics: diagnostics,
    );
  }

  bool _isRateLimited(Map<String, String> headers) {
    final remaining = int.tryParse(headers['x-ratelimit-remaining'] ?? '');
    if (remaining == 0) {
      return true;
    }
    return (headers['retry-after'] ?? '').isNotEmpty;
  }

  RepoSummary _toRepoSummary(Map<String, dynamic> item) {
    final fullNameRaw = (item['full_name'] as String? ?? '').trim();
    final fullName = fullNameRaw.toLowerCase();
    final descriptionRaw = item['description'] as String?;
    final description = descriptionRaw?.trim();
    return RepoSummary(
      fullName: fullName,
      htmlUrl: Uri.parse(item['html_url'] as String),
      description: (description == null || description.isEmpty) ? null : description,
      language: item['language'] as String?,
      stargazersCount: item['stargazers_count'] as int? ?? 0,
      forksCount: item['forks_count'] as int? ?? 0,
      updatedAt: DateTime.tryParse(item['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
