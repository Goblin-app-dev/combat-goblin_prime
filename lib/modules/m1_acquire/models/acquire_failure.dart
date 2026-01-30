class AcquireFailure {
  final String message;
  final String? details;

  const AcquireFailure({
    required this.message,
    this.details,
  });
}
