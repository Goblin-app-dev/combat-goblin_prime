import 'search_diagnostic.dart';

/// A hard failure during M10 search (invalid state, misuse).
///
/// Distinct from [SearchDiagnostic] which is informational.
/// Does not reuse M9 diagnostics.
class SearchFailure {
  /// Human-readable failure description.
  final String message;

  /// Optional associated diagnostic providing additional detail.
  final SearchDiagnostic? diagnostic;

  const SearchFailure({
    required this.message,
    this.diagnostic,
  });

  @override
  String toString() => 'SearchFailure: $message';
}
