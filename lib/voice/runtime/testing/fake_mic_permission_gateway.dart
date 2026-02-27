import 'package:combat_goblin_prime/voice/runtime/mic_permission_gateway.dart';

/// Configurable fake [MicPermissionGateway] for deterministic testing.
class FakeMicPermissionGateway implements MicPermissionGateway {
  /// Whether [requestPermission] and [hasPermission] return `true`.
  bool allow;

  FakeMicPermissionGateway({this.allow = true});

  @override
  Future<bool> hasPermission() async => allow;

  @override
  Future<bool> requestPermission() async => allow;
}
