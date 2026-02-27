/// Injectable boundary for microphone permission checks.
///
/// Real platform adapter (using `permission_handler` or equivalent) is
/// deferred to Phase 12C. In Phase 12B only [FakeMicPermissionGateway]
/// is provided.
abstract interface class MicPermissionGateway {
  /// Returns `true` if mic permission is already granted.
  Future<bool> hasPermission();

  /// Requests mic permission from the OS. Returns `true` if granted.
  Future<bool> requestPermission();
}
