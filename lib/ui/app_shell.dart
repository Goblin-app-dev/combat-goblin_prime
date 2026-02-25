import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/ui/downloads/downloads_screen.dart';
import 'package:combat_goblin_prime/ui/home/home_screen.dart';
import 'package:combat_goblin_prime/ui/import/import_session_controller.dart';
import 'package:combat_goblin_prime/ui/import/import_session_provider.dart';

/// Global app shell with navigation drawer.
///
/// Hosts [HomeScreen] (search + slot status) and [DownloadsScreen]
/// (slot management + catalog picker). Shows an update badge on the
/// AppBar when [ImportSessionController.updateAvailable] is true.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  /// Prevents the update dialog from showing more than once per session.
  bool _updatePromptShown = false;

  @override
  void initState() {
    super.initState();
    // Wire update-available notification after the first frame so that
    // ImportSessionProvider is accessible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ImportSessionProvider.of(context);
      controller.addListener(_onControllerChanged);
    });
  }

  @override
  void dispose() {
    // Unlisten before disposal. Accessing provider here may fail if the
    // widget has already been removed from the tree, so guard it.
    try {
      ImportSessionProvider.of(context).removeListener(_onControllerChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted || _updatePromptShown) return;
    final controller = ImportSessionProvider.of(context);
    if (controller.updateCheckStatus == UpdateCheckStatus.updatesAvailable) {
      _updatePromptShown = true;
      _showUpdatePrompt();
    }
  }

  void _showUpdatePrompt() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Updates available'),
        content: const Text(
          'New versions of your catalog files are available on GitHub. '
          'Go to Downloads and reload the affected slots to update.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _selectedIndex = 1);
            },
            child: const Text('Go to Downloads'),
          ),
        ],
      ),
    );
  }

  void _navigate(int index) {
    setState(() => _selectedIndex = index);
    Navigator.of(context).pop(); // close drawer
  }

  @override
  Widget build(BuildContext context) {
    final controller = ImportSessionProvider.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Combat Goblin'),
          actions: [
            _UpdateCheckIndicator(
              status: controller.updateCheckStatus,
              onTap: () => setState(() => _selectedIndex = 1),
            ),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: Colors.deepPurple),
                child: Text(
                  'Combat Goblin',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Home'),
                selected: _selectedIndex == 0,
                onTap: () => _navigate(0),
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Downloads'),
                selected: _selectedIndex == 1,
                onTap: () => _navigate(1),
              ),
              const Divider(),
              _DebugStatusSection(controller: controller),
            ],
          ),
        ),
        body: _selectedIndex == 0
            ? HomeScreen(
                onNavigateToDownloads: () =>
                    setState(() => _selectedIndex = 1),
              )
            : const DownloadsScreen(),
      ),
    );
  }
}

String _formatTimestamp(DateTime dt) {
  final local = dt.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  final s = local.second.toString().padLeft(2, '0');
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} $h:$m:$s';
}

/// Debug status panel shown at the bottom of the navigation drawer.
///
/// Displays:
/// - Last sync timestamp (from last successful repo tree fetch)
/// - Update check status and timestamp
/// - Rebuild rule description (static text)
class _DebugStatusSection extends StatelessWidget {
  final ImportSessionController controller;

  const _DebugStatusSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    final lastSync = controller.lastSyncAt;
    final lastCheck = controller.lastUpdateCheckAt;
    final checkStatus = controller.updateCheckStatus;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Debug',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.grey.shade500,
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 6),
          _DebugLine(
            label: 'Last sync',
            value: lastSync != null ? _formatTimestamp(lastSync) : 'unknown',
          ),
          _DebugLine(
            label: 'Update check',
            value: checkStatus.name,
          ),
          if (lastCheck != null)
            _DebugLine(
              label: 'Checked at',
              value: _formatTimestamp(lastCheck),
            ),
          const _DebugLine(
            label: 'Rebuild rule',
            value: 'SHA diff on tracked files',
          ),
        ],
      ),
    );
  }
}

class _DebugLine extends StatelessWidget {
  final String label;
  final String value;

  const _DebugLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              '$label:',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows update status in the AppBar with distinct states:
///
/// - [UpdateCheckStatus.unknown] — hidden (check hasn't run yet)
/// - [UpdateCheckStatus.upToDate] — no icon shown
/// - [UpdateCheckStatus.updatesAvailable] — badge with update icon
/// - [UpdateCheckStatus.failed] — warning icon with explanatory tooltip
class _UpdateCheckIndicator extends StatelessWidget {
  final UpdateCheckStatus status;
  final VoidCallback onTap;

  const _UpdateCheckIndicator({
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      UpdateCheckStatus.unknown ||
      UpdateCheckStatus.upToDate =>
        const SizedBox.shrink(),
      UpdateCheckStatus.updatesAvailable => IconButton(
          icon: const Badge(
            smallSize: 8,
            child: Icon(Icons.system_update),
          ),
          tooltip: 'Updates available',
          onPressed: onTap,
        ),
      UpdateCheckStatus.failed => IconButton(
          icon: Icon(
            Icons.cloud_off,
            color: Colors.grey.shade500,
            size: 20,
          ),
          tooltip: 'Update check failed — could not reach repository',
          onPressed: onTap,
        ),
    };
  }
}
