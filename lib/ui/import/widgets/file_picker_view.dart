import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/models/source_locator.dart';
import '../import_session_controller.dart';
import '../import_session_provider.dart';

/// Phase of the GitHub catalog picker UI.
enum _PickerPhase {
  /// User typing repo URL.
  entering,

  /// Tree fetch in progress.
  loading,

  /// Tree fetched; user selecting files.
  selecting,

  /// Fetch failed; showing error with retry.
  error,
}

/// Primary import entry point — fetches a GitHub repository tree,
/// auto-selects the .gst if exactly one exists, shows .cat checkboxes
/// (max [kMaxSelectedCatalogs]), then triggers [importFromGitHub].
///
/// Boundary: must NOT import HTTP or storage classes.
/// All network and storage delegation goes through [ImportSessionController].
class GitHubCatalogPickerView extends StatefulWidget {
  const GitHubCatalogPickerView({super.key});

  @override
  State<GitHubCatalogPickerView> createState() =>
      _GitHubCatalogPickerViewState();
}

class _GitHubCatalogPickerViewState extends State<GitHubCatalogPickerView> {
  static const _defaultRepoUrl = 'https://github.com/BSData/wh40k-10e';

  final _urlController =
      TextEditingController(text: _defaultRepoUrl);
  final _tokenController = TextEditingController();

  _PickerPhase _phase = _PickerPhase.entering;
  RepoTreeResult? _tree;
  String? _selectedGstPath;
  final Set<String> _selectedCatPaths = {};
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  // --- Source locator helpers ---

  SourceLocator? _buildSourceLocator(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host != 'github.com') return null;
    final segments = uri.pathSegments;
    if (segments.length < 2) return null;
    return SourceLocator(
      sourceKey: '${segments[0]}_${segments[1]}',
      sourceUrl: url.trim(),
    );
  }

  // --- Actions ---

  Future<void> _doFetch() async {
    final loc = _buildSourceLocator(_urlController.text);
    if (loc == null) {
      setState(() {
        _phase = _PickerPhase.error;
        _errorMessage =
            'Enter a valid GitHub URL (e.g. https://github.com/owner/repo).';
      });
      return;
    }

    setState(() {
      _phase = _PickerPhase.loading;
      _errorMessage = null;
    });

    final controller = ImportSessionProvider.of(context);

    // Apply token if entered
    final token = _tokenController.text.trim();
    controller.setAuthToken(token.isEmpty ? null : token);

    final tree = await controller.loadRepoCatalogTree(loc);

    if (!mounted) return;

    if (tree == null) {
      setState(() {
        _phase = _PickerPhase.error;
        _errorMessage = controller.resolverError?.userMessage ??
            'Failed to fetch repository tree.';
      });
      return;
    }

    // Auto-select .gst if exactly one exists
    String? autoGst;
    if (tree.gameSystemFiles.length == 1) {
      autoGst = tree.gameSystemFiles.first.path;
    }

    setState(() {
      _phase = _PickerPhase.selecting;
      _tree = tree;
      _selectedGstPath = autoGst;
      _selectedCatPaths.clear();
    });
  }

  Future<void> _doImport() async {
    final tree = _tree;
    final gstPath = _selectedGstPath;
    if (tree == null || gstPath == null || _selectedCatPaths.isEmpty) return;

    final loc = _buildSourceLocator(_urlController.text);
    if (loc == null) return;

    final controller = ImportSessionProvider.of(context);

    // catPaths in deterministic order: sort selected paths lexicographically
    final catPaths = _selectedCatPaths.toList()..sort();

    await controller.importFromGitHub(
      sourceLocator: loc,
      gstPath: gstPath,
      catPaths: catPaths,
      repoTree: tree,
    );
  }

  void _toggleCat(String path) {
    setState(() {
      if (_selectedCatPaths.contains(path)) {
        _selectedCatPaths.remove(path);
      } else if (_selectedCatPaths.length < kMaxSelectedCatalogs) {
        _selectedCatPaths.add(path);
      } else {
        // Show snackbar — do not add
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Maximum $kMaxSelectedCatalogs catalogs selected.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final controller = ImportSessionProvider.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Previous session card (preserved; shown at top when available)
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) => _buildSessionCard(context, controller),
          ),

          const Text(
            'Import from GitHub',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter a BSData-format GitHub repository URL to browse and import catalogs.',
          ),
          const SizedBox(height: 24),

          // URL field
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'GitHub Repository URL',
              hintText: 'https://github.com/BSData/wh40k-10e',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _doFetch(),
            enabled: _phase != _PickerPhase.loading,
          ),
          const SizedBox(height: 12),

          // Auth token field (optional, inline)
          TextField(
            controller: _tokenController,
            decoration: const InputDecoration(
              labelText: 'Personal Access Token (optional)',
              hintText: 'ghp_...',
              prefixIcon: Icon(Icons.key),
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            enabled: _phase != _PickerPhase.loading,
          ),
          const SizedBox(height: 16),

          // Fetch button
          if (_phase == _PickerPhase.entering ||
              _phase == _PickerPhase.error) ...[
            FilledButton.icon(
              onPressed: _doFetch,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Fetch Repository'),
            ),
          ],

          // Loading indicator
          if (_phase == _PickerPhase.loading) ...[
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Fetching repository tree...'),
                ],
              ),
            ),
          ],

          // Error state
          if (_phase == _PickerPhase.error && _errorMessage != null) ...[
            _buildErrorBanner(context),
          ],

          // Selection UI
          if (_phase == _PickerPhase.selecting && _tree != null) ...[
            _buildSelectionUI(context, _tree!),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    return Column(
      children: [
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _doFetch,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildSelectionUI(BuildContext context, RepoTreeResult tree) {
    final gstFiles = tree.gameSystemFiles;
    final catFiles = tree.catalogFiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),

        // Game System section
        _buildSectionHeader(
          context,
          icon: Icons.sports_esports,
          label: 'Game System (.gst)',
        ),
        const SizedBox(height: 8),

        if (gstFiles.isEmpty)
          _buildWarningText(context, 'No .gst file found in this repository.')
        else if (gstFiles.length == 1)
          _buildAutoSelectedGst(context, gstFiles.first.path)
        else
          _buildGstRadioList(context, gstFiles),

        const SizedBox(height: 16),

        // Catalogs section
        _buildSectionHeader(
          context,
          icon: Icons.folder_open,
          label: 'Catalogs (.cat) — select up to $kMaxSelectedCatalogs',
        ),
        const SizedBox(height: 8),

        if (catFiles.isEmpty)
          _buildWarningText(context, 'No .cat files found in this repository.')
        else
          _buildCatCheckboxList(context, catFiles),

        const SizedBox(height: 24),

        // Refetch option
        TextButton.icon(
          onPressed: () => setState(() {
            _phase = _PickerPhase.entering;
            _tree = null;
            _selectedGstPath = null;
            _selectedCatPaths.clear();
          }),
          icon: const Icon(Icons.edit),
          label: const Text('Change repository'),
        ),
        const SizedBox(height: 8),

        // Import button
        FilledButton.icon(
          onPressed: _canImport ? _doImport : null,
          icon: const Icon(Icons.download),
          label: Text(
            _selectedCatPaths.isEmpty
                ? 'Select catalogs to import'
                : 'Import ${_selectedCatPaths.length == 1 ? '1 pack' : '${_selectedCatPaths.length} packs'}',
          ),
        ),
      ],
    );
  }

  bool get _canImport =>
      _selectedGstPath != null && _selectedCatPaths.isNotEmpty;

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildWarningText(BuildContext context, String message) {
    return Text(
      message,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildAutoSelectedGst(BuildContext context, String path) {
    final fileName = path.split('/').last;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    'Auto-selected (only .gst in repo)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGstRadioList(BuildContext context, List<RepoTreeEntry> gstFiles) {
    return Column(
      children: gstFiles.map((entry) {
        final path = entry.path;
        final fileName = path.split('/').last;
        return RadioListTile<String>(
          title: Text(fileName),
          subtitle: Text(
            path,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          value: path,
          groupValue: _selectedGstPath,
          onChanged: (v) => setState(() => _selectedGstPath = v),
          dense: true,
          contentPadding: EdgeInsets.zero,
        );
      }).toList(),
    );
  }

  Widget _buildCatCheckboxList(
    BuildContext context,
    List<RepoTreeEntry> catFiles,
  ) {
    return Column(
      children: catFiles.map((entry) {
        final path = entry.path;
        final fileName = path.split('/').last;
        final isSelected = _selectedCatPaths.contains(path);
        final atMax = _selectedCatPaths.length >= kMaxSelectedCatalogs;

        return CheckboxListTile(
          title: Text(fileName),
          subtitle: path != fileName
              ? Text(
                  path,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : null,
          value: isSelected,
          onChanged: (!isSelected && atMax)
              ? (_) => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Maximum $kMaxSelectedCatalogs catalogs selected.',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  )
              : (_) => _toggleCat(path),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        );
      }).toList(),
    );
  }

  Widget _buildSessionCard(
    BuildContext context,
    ImportSessionController controller,
  ) {
    if (!controller.hasPersistedSession) {
      return const SizedBox.shrink();
    }

    final session = controller.persistedSession;
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  color:
                      Theme.of(context).colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Previous Session Available',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context)
                          .colorScheme
                          .onSecondaryContainer,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  iconSize: 18,
                  onPressed: () => controller.clearPersistedSession(),
                  tooltip: 'Dismiss',
                ),
              ],
            ),
            if (session != null) ...[
              const SizedBox(height: 4),
              Text(
                'Last used: ${_formatDate(session.savedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => controller.reloadLastSession(),
              child: const Text('Reload Last Pack'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats a [DateTime] as a relative or absolute string for display.
String _formatDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inMinutes < 1) {
    return 'just now';
  } else if (diff.inHours < 1) {
    return '${diff.inMinutes} min ago';
  } else if (diff.inDays < 1) {
    return '${diff.inHours} hours ago';
  } else if (diff.inDays == 1) {
    return 'yesterday';
  } else if (diff.inDays < 7) {
    return '${diff.inDays} days ago';
  } else {
    return '${date.month}/${date.day}/${date.year}';
  }
}
