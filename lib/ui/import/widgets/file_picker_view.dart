import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/models/source_locator.dart';
import '../import_session_controller.dart';
import '../import_session_provider.dart';

/// View for selecting game system and catalog files.
class FilePickerView extends StatefulWidget {
  final VoidCallback? onFilesSelected;

  const FilePickerView({
    super.key,
    this.onFilesSelected,
  });

  @override
  State<FilePickerView> createState() => _FilePickerViewState();
}

class _FilePickerViewState extends State<FilePickerView> {
  final _repoUrlController = TextEditingController();
  bool _showRepoConfig = false;

  @override
  void dispose() {
    _repoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ImportSessionProvider.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Select Files',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a game system file (.gst) and a catalog file (.cat) to import.',
          ),
          const SizedBox(height: 24),

          // Game System File
          _FileSelectionCard(
            title: 'Game System',
            subtitle: '.gst file',
            icon: Icons.sports_esports,
            allowedExtension: 'gst',
            selectedFile: controller.gameSystemFile,
            onFilePicked: (name, bytes, path) {
              controller.setGameSystemFile(
                SelectedFile(fileName: name, bytes: bytes, filePath: path),
              );
            },
          ),
          const SizedBox(height: 16),

          // Primary Catalog File
          _FileSelectionCard(
            title: 'Primary Catalog',
            subtitle: '.cat file',
            icon: Icons.folder_open,
            allowedExtension: 'cat',
            selectedFile: controller.primaryCatalogFile,
            onFilePicked: (name, bytes, path) {
              controller.setPrimaryCatalogFile(
                SelectedFile(fileName: name, bytes: bytes, filePath: path),
              );
            },
          ),
          const SizedBox(height: 24),

          // Repository Configuration (collapsible)
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text('Repository Configuration'),
              subtitle: Text(
                _showRepoConfig
                    ? 'Configure BSData repository for auto-resolution'
                    : 'Optional: auto-resolve dependencies',
              ),
              initiallyExpanded: _showRepoConfig,
              onExpansionChanged: (expanded) {
                setState(() => _showRepoConfig = expanded);
              },
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _repoUrlController,
                        decoration: const InputDecoration(
                          labelText: 'GitHub Repository URL',
                          hintText: 'https://github.com/BSData/wh40k-10e',
                          prefixIcon: Icon(Icons.link),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _updateSourceLocator(controller),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'If provided, missing dependencies will be automatically '
                        'fetched from this repository.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Reload Last Session Button (if available)
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
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
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
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
            },
          ),

          // Import Button
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final canImport = controller.gameSystemFile != null &&
                  controller.primaryCatalogFile != null;

              return FilledButton.icon(
                onPressed: canImport ? widget.onFilesSelected : null,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import Pack'),
              );
            },
          ),
        ],
      ),
    );
  }

  void _updateSourceLocator(ImportSessionController controller) {
    final url = _repoUrlController.text.trim();
    if (url.isEmpty) {
      return;
    }

    // Extract sourceKey from URL
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != 'github.com') return;

    final segments = uri.pathSegments;
    if (segments.length < 2) return;

    final sourceKey = '${segments[0]}_${segments[1]}';
    controller.setSourceLocator(SourceLocator(
      sourceKey: sourceKey,
      sourceUrl: url,
    ));
  }
}

/// Card for selecting a single file.
class _FileSelectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final SelectedFile? selectedFile;
  final String allowedExtension;
  final void Function(String name, Uint8List bytes, String? path) onFilePicked;

  const _FileSelectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selectedFile,
    required this.allowedExtension,
    required this.onFilePicked,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = selectedFile != null;

    return Card(
      child: InkWell(
        onTap: () => _pickFile(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: hasFile
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  hasFile ? Icons.check : icon,
                  color: hasFile
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      hasFile ? selectedFile!.fileName : subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (hasFile)
                      Text(
                        _formatBytes(selectedFile!.bytes.length),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.upload_file,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [allowedExtension],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read file data.')),
        );
        return;
      }

      onFilePicked(file.name, Uint8List.fromList(bytes), file.path);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick file: $e')),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Formats a DateTime for display.
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
