import 'package:permission_handler/permission_handler.dart';

import '../runtime/mic_permission_gateway.dart';

/// [MicPermissionGateway] backed by `permission_handler`.
///
/// Requests [Permission.microphone] from the OS. On Android the system dialog
/// appears at most once; subsequent denials return `false` immediately.
final class PlatformMicPermissionGateway implements MicPermissionGateway {
  @override
  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  @override
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }
}
