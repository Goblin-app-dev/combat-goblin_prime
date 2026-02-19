import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/ui/import/import_session_controller.dart';
import 'package:combat_goblin_prime/ui/import/import_session_provider.dart';

/// Screen for selecting a faction to load into a catalog slot.
///
/// Shows a searchable list of [FactionOption]s derived from the repo tree.
///
/// **Highlight-and-replace model**: the currently loaded faction (if any) is
/// highlighted with a check mark. Tapping a different faction immediately
/// replaces the slot — no second confirmation required. "Clear" is available
/// as a separate action in the AppBar.
class FactionPickerScreen extends StatefulWidget {
  /// Index of the slot this picker is acting on.
  final int slotIndex;

  /// Factions derived from the current repo tree.
  final List<FactionOption> factions;

  /// Source locator for the current repository.
  final SourceLocator locator;

  /// Primary catalog path of the currently loaded faction (for highlight).
  /// Null if the slot is empty.
  final String? currentFactionPath;

  const FactionPickerScreen({
    super.key,
    required this.slotIndex,
    required this.factions,
    required this.locator,
    this.currentFactionPath,
  });

  @override
  State<FactionPickerScreen> createState() => _FactionPickerScreenState();
}

class _FactionPickerScreenState extends State<FactionPickerScreen> {
  final _filterController = TextEditingController();
  String _filter = '';

  /// True while loadFactionIntoSlot is running (prevents double-tap).
  bool _loading = false;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  List<FactionOption> get _filtered {
    if (_filter.isEmpty) return widget.factions;
    final q = _filter.toLowerCase();
    return widget.factions
        .where((f) => f.displayName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _pick(FactionOption faction) async {
    if (_loading) return;
    setState(() => _loading = true);
    final controller = ImportSessionProvider.of(context);
    await controller.loadFactionIntoSlot(
      widget.slotIndex,
      faction,
      widget.locator,
    );
    if (mounted) Navigator.of(context).pop();
  }

  void _clearSlot() {
    ImportSessionProvider.of(context).clearSlot(widget.slotIndex);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: Text('Slot ${widget.slotIndex + 1} — Pick Faction'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _clearSlot,
            child: const Text('Clear Slot'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search / filter field
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _filterController,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'Filter factions...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),

          // Loading progress bar
          if (_loading) const LinearProgressIndicator(),

          // Faction list
          Expanded(
            child: displayed.isEmpty
                ? const Center(child: Text('No factions found.'))
                : ListView.builder(
                    itemCount: displayed.length,
                    itemBuilder: (context, index) {
                      final faction = displayed[index];
                      final isCurrent =
                          faction.primaryPath == widget.currentFactionPath;
                      return ListTile(
                        leading: isCurrent
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                            : const Icon(Icons.circle_outlined),
                        title: Text(faction.displayName),
                        subtitle: faction.libraryPaths.isNotEmpty
                            ? Text(
                                'Includes: ${faction.libraryPaths.map((p) {
                                  final base = p.split('/').last;
                                  return base.endsWith('.cat')
                                      ? base.substring(0, base.length - 4)
                                      : base;
                                }).join(', ')}',
                                style: const TextStyle(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        selected: isCurrent,
                        enabled: !_loading,
                        onTap: () => _pick(faction),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
