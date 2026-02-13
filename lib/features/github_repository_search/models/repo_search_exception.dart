import 'repo_search_error.dart';

class RepoSearchException implements Exception {
  const RepoSearchException(this.error, {this.message});

  final RepoSearchError error;
  final String? message;

  @override
  String toString() =>
      'RepoSearchException(error: $error${message == null ? '' : ', message: $message'})';
}
