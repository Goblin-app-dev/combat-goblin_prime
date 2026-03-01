import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';
import 'package:combat_goblin_prime/ui/import/import_session_controller.dart';
import 'package:combat_goblin_prime/ui/import/import_session_provider.dart';
import 'package:combat_goblin_prime/ui/voice/voice_control_bar.dart';
import 'package:combat_goblin_prime/voice/adapters/voice_platform_factory.dart';
import 'package:combat_goblin_prime/voice/models/spoken_entity.dart';
import 'package:combat_goblin_prime/voice/models/spoken_variant.dart';
import 'package:combat_goblin_prime/voice/models/spoken_response_plan.dart';
import 'package:combat_goblin_prime/voice/models/text_candidate.dart';
import 'package:combat_goblin_prime/voice/models/voice_search_response.dart';
import 'package:combat_goblin_prime/voice/understanding/voice_assistant_coordinator.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_audio_focus_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_audio_route_observer.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_mic_permission_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_controller.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_event.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_stop_reason.dart';
import 'package:combat_goblin_prime/voice/settings/voice_settings.dart';
import 'package:combat_goblin_prime/voice/voice_search_facade.dart';

/// Home screen with 3-section vertical layout.
///
/// - **Top**: search bar (always visible)
/// - **Middle**: search results (expands)
/// - **Bottom**: slot status bar (fixed, shows loaded catalogs)
class HomeScreen extends StatefulWidget {
  /// Callback to navigate to the Downloads screen.
  final VoidCallback? onNavigateToDownloads;

  const HomeScreen({super.key, this.onNavigateToDownloads});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _facade = VoiceSearchFacade();
  late final VoiceAssistantCoordinator _coordinator;

  // Phase 12C: two-phase init — fakes first, real adapters async.
  late VoiceRuntimeController _voiceController;
  StreamSubscription<VoiceRuntimeEvent>? _voiceEventSub;

  /// Guards against duplicate SnackBars per (sessionId, reason) pair.
  final Set<(int, VoiceStopReason)> _shownVoiceErrors = {};

  VoiceSearchResponse? _voiceResult;

  /// Phase 12D: structured plan from the voice coordinator.
  SpokenResponsePlan? _voicePlan;

  List<String> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _coordinator = VoiceAssistantCoordinator(searchFacade: _facade);
    // Synchronous bootstrap with fakes so the widget is immediately usable.
    _voiceController = VoiceRuntimeController(
      permissionGateway: FakeMicPermissionGateway(allow: true),
      focusGateway: FakeAudioFocusGateway(allow: true),
      routeObserver: FakeAudioRouteObserver(),
    );
    _attachVoiceCallbacks(_voiceController);
    // Upgrade to real platform adapters asynchronously.
    unawaited(_initRealVoice());
  }

  /// Attaches [onTextCandidate] and the event listener to [controller].
  void _attachVoiceCallbacks(VoiceRuntimeController controller) {
    _voiceEventSub?.cancel();
    controller.onTextCandidate = _onTextCandidate;
    _voiceEventSub = controller.events.listen(_onVoiceEvent);
  }

  /// Async init: creates real platform adapters and replaces the controller.
  Future<void> _initRealVoice() async {
    const settings = VoiceSettings.defaults;
    final factory = VoicePlatformFactory(settings: settings);
    final captureGateway = factory.createCaptureGateway();
    final wakeDetector = await factory.createWakeWordDetector(
      captureGateway: captureGateway,
    );
    if (!mounted) {
      captureGateway.dispose();
      wakeDetector?.dispose();
      return;
    }
    final newController = VoiceRuntimeController(
      permissionGateway: factory.createPermissionGateway(),
      focusGateway: factory.createFocusGateway(),
      routeObserver: factory.createRouteObserver(),
      captureGateway: captureGateway,
      sttEngine: factory.createSttEngine(),
      wakeWordDetector: wakeDetector,
      maxCaptureDuration: Duration(seconds: settings.maxCaptureDurationSeconds),
    );
    final oldController = _voiceController;
    _attachVoiceCallbacks(newController);
    _voiceController = newController;
    oldController.dispose();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _voiceEventSub?.cancel();
    _searchController.dispose();
    _voiceController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Voice callbacks
  // ---------------------------------------------------------------------------

  /// Routes a [TextCandidate] through [VoiceAssistantCoordinator] and updates UI.
  Future<void> _onTextCandidate(TextCandidate candidate) async {
    if (!mounted || candidate.text.isEmpty) return;
    final sessionController = ImportSessionProvider.of(context);
    final bundles = _activeBundles(sessionController);
    final plan = await _coordinator.handleTranscript(
      transcript: candidate.text,
      slotBundles: bundles,
      contextHints: _buildContextHints(sessionController),
    );
    if (!mounted) return;
    setState(() {
      _voicePlan = plan;
      _voiceResult = null;
      _showSuggestions = false;
      _searchController.text = candidate.text;
    });
  }

  /// Shows a one-time SnackBar for voice permission/focus errors.
  void _onVoiceEvent(VoiceRuntimeEvent event) {
    if (!mounted) return;
    int? sessionId;
    VoiceStopReason? reason;
    if (event is PermissionDenied) {
      sessionId = event.sessionId;
      reason = VoiceStopReason.permissionDenied;
    } else if (event is AudioFocusDenied) {
      sessionId = event.sessionId;
      reason = VoiceStopReason.focusLost;
    }
    if (sessionId == null || reason == null) return;
    final key = (sessionId, reason);
    if (_shownVoiceErrors.contains(key)) return;
    _shownVoiceErrors.add(key);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reason == VoiceStopReason.permissionDenied
              ? 'Microphone permission denied'
              : 'Audio focus denied',
        ),
        action: reason == VoiceStopReason.permissionDenied
            ? SnackBarAction(label: 'Settings', onPressed: openAppSettings)
            : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Search helpers
  // ---------------------------------------------------------------------------

  Map<String, IndexBundle> _activeBundles(ImportSessionController c) {
    final bundles = <String, IndexBundle>{};
    bundles.addAll(c.slotIndexBundles);
    if (bundles.isEmpty) {
      bundles.addAll(c.indexBundles);
    }
    return bundles;
  }

  /// Builds STT context hints: faction names + unit/weapon keys, capped at 50.
  List<String> _buildContextHints(ImportSessionController controller) {
    final hints = <String>[];
    for (var i = 0; i < kMaxSelectedCatalogs; i++) {
      final slot = controller.slotState(i);
      if (slot.status == SlotStatus.loaded && slot.catalogName != null) {
        hints.add(slot.catalogName!);
      }
    }
    final bundles = _activeBundles(controller);
    for (final bundle in bundles.values) {
      for (final key in bundle.unitKeyToDocIds.keys.take(20)) {
        hints.add(key);
        if (hints.length >= 50) return hints;
      }
      for (final key in bundle.weaponKeyToDocIds.keys.take(15)) {
        hints.add(key);
        if (hints.length >= 50) return hints;
      }
    }
    return hints.take(50).toList();
  }

  void _onChanged(String query) {
    final controller = ImportSessionProvider.of(context);
    final bundles = _activeBundles(controller);
    if (query.isEmpty || bundles.isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    final suggestions = _facade.suggest(bundles, query, limit: 8);
    setState(() {
      _suggestions = suggestions;
      _showSuggestions = suggestions.isNotEmpty;
    });
  }

  void _search(String query) {
    final controller = ImportSessionProvider.of(context);
    final bundles = _activeBundles(controller);
    if (query.isEmpty || bundles.isEmpty) {
      setState(() {
        _voiceResult = null;
        _showSuggestions = false;
      });
      return;
    }
    final result = _facade.searchText(bundles, query);
    setState(() {
      _voiceResult = result;
      _voicePlan = null;
      _showSuggestions = false;
    });
  }

  void _selectSuggestion(String suggestion) {
    _searchController.text = suggestion;
    _search(suggestion);
  }

  /// Returns display names of all loaded catalog slots (for stats view).
  List<String> _loadedFactionNames(ImportSessionController controller) {
    return [
      for (var i = 0; i < kMaxSelectedCatalogs; i++)
        if (controller.slotState(i).status == SlotStatus.loaded)
          controller.slotState(i).catalogName ?? 'Slot ${i + 1}',
    ];
  }

  String? _partialLoadHint(ImportSessionController controller) {
    if (!controller.hasAnyLoaded) return null;
    final slots = controller.slots;
    final inProgress = slots.where(
      (s) =>
          s.status == SlotStatus.building ||
          s.status == SlotStatus.fetching ||
          s.isBootRestoring,
    );
    if (inProgress.isEmpty) return null;

    final loadedCount = slots.where((s) => s.status == SlotStatus.loaded).length;
    final total = slots.where((s) => s.status != SlotStatus.empty).length;
    if (total > 1) {
      return 'Searching $loadedCount of $total factions — more loading…';
    }
    return null;
  }

  void _showVariantDetail(BuildContext context, SpokenVariant variant) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              variant.displayName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('Type: ${variant.docType.name}'),
            Text('ID: ${variant.docId}'),
            Text('Key: ${variant.canonicalKey}'),
            Text('Slot: ${variant.sourceSlotId}'),
            const SizedBox(height: 16),
            Text(
              'Match: ${variant.matchReasons.map((r) => r.name).join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ImportSessionProvider.of(context);
    // Keep STT context hints current with loaded bundles.
    _voiceController.contextHints = _buildContextHints(controller);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          children: [
            // --- Update banner ---
            if (controller.isUpdating)
              Container(
                width: double.infinity,
                color: Colors.blue.shade50,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Updating data…',
                      style: TextStyle(
                          fontSize: 12, color: Colors.blue.shade800),
                    ),
                  ],
                ),
              ),

            // --- Top: Search Bar ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: _activeBundles(controller).isEmpty
                          ? 'Load catalogs to search...'
                          : 'Search units, weapons, rules...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _onChanged('');
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      enabled: _activeBundles(controller).isNotEmpty,
                    ),
                    onChanged: _onChanged,
                    onSubmitted: _search,
                    textInputAction: TextInputAction.search,
                  ),
                  if (_showSuggestions && _suggestions.isNotEmpty)
                    Material(
                      elevation: 4,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            leading: const Icon(Icons.history, size: 18),
                            title: Text(_suggestions[index]),
                            dense: true,
                            onTap: () =>
                                _selectSuggestion(_suggestions[index]),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            // --- Voice Control Bar ---
            VoiceControlBar(controller: _voiceController),

            // --- Middle: Results ---
            Expanded(child: _buildResults(controller)),

            // --- Bottom: Slot Status Bar ---
            _SlotStatusBar(
              controller: controller,
              onTap: widget.onNavigateToDownloads,
            ),
          ],
        );
      },
    );
  }

  Widget _buildResults(ImportSessionController controller) {
    final bundles = _activeBundles(controller);

    if (bundles.isEmpty) {
      final slots = controller.slots;
      final isBootRestoring = slots.any((s) => s.isBootRestoring);
      final isBuilding = slots.any((s) => s.status == SlotStatus.building);

      if (isBootRestoring || isBuilding) {
        final label = isBootRestoring ? 'Restoring…' : 'Building index…';
        final icon = isBootRestoring ? Icons.restore : Icons.build_circle;
        final color = isBootRestoring ? Colors.orange : Colors.amber;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: color),
              const SizedBox(height: 16),
              Text(label),
              const SizedBox(height: 4),
              Text(
                'Search will be available shortly',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        );
      }

      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text('No catalogs loaded'),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.onNavigateToDownloads,
              icon: const Icon(Icons.download),
              label: const Text('Go to Downloads'),
            ),
          ],
        ),
      );
    }

    // --- Phase 12D: voice coordinator plan takes priority over text search result ---
    if (_voicePlan != null) {
      return _buildPlanResults(_voicePlan!);
    }

    if (_voiceResult == null) {
      var totalUnits = 0;
      var totalWeapons = 0;
      var totalRules = 0;
      for (final bundle in bundles.values) {
        totalUnits += bundle.units.length;
        totalWeapons += bundle.weapons.length;
        totalRules += bundle.rules.length;
      }
      final packCount = bundles.length;
      final packLabel = packCount == 1 ? 'Pack' : 'Packs';
      final gameSystemName = controller.gameSystemDisplayName;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            if (gameSystemName != null) ...[
              Text(
                gameSystemName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              '$packCount $packLabel Loaded',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ..._loadedFactionNames(controller).map(
              (name) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$totalUnits units · $totalWeapons weapons · $totalRules rules',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_partialLoadHint(controller) case final hint?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  hint,
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Start typing to search',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_voiceResult!.entities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No results found'),
            if (_voiceResult!.diagnostics.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _voiceResult!.diagnostics.first.message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _voiceResult!.entities.length,
      itemBuilder: (context, index) {
        return _buildEntityCard(_voiceResult!.entities[index]);
      },
    );
  }

  /// DEBUG BRIDGE UI — validation and testing only, not final UX.
  ///
  /// Renders a [SpokenResponsePlan]: primary text banner + entity list.
  /// This rendering exists to validate voice coordinator output on-device
  /// during Phase 12D development. It is intentionally minimal and will be
  /// replaced by the proper spoken-response UX in a future phase.
  ///
  /// When [plan.selectedIndex] is non-null, the highlighted entity row is
  /// rendered with a subtle accent border.
  Widget _buildPlanResults(SpokenResponsePlan plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary text banner
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            plan.primaryText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
          ),
        ),
        if (plan.entities.isNotEmpty)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: plan.entities.length,
              itemBuilder: (context, index) {
                final isSelected = index == plan.selectedIndex;
                return _buildEntityCard(
                  plan.entities[index],
                  isSelected: isSelected,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildEntityCard(SpokenEntity entity, {bool isSelected = false}) {
    final selectedDecoration = isSelected
        ? BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          )
        : null;
    if (entity.variants.length == 1) {
      final variant = entity.variants.first;
      return Container(
        decoration: selectedDecoration,
        child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: _buildTypeIcon(variant.docType),
            title: Text(entity.displayName),
            subtitle: Text(
              '${variant.docType.name} • ${entity.slotId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showVariantDetail(context, variant),
          ),
        ),
      );
    }

    return Container(
      decoration: selectedDecoration,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ExpansionTile(
          leading: _buildTypeIcon(entity.variants.first.docType),
          title: Text(entity.displayName),
          subtitle: Text(
            '${entity.variants.first.docType.name} • ${entity.slotId} • ${entity.variants.length} variants',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          children: [
            for (final variant in entity.variants)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 32, right: 16),
                title: Text(variant.displayName),
                subtitle: Text(
                  variant.docId,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showVariantDetail(context, variant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeIcon(SearchDocType type) {
    final (icon, color) = switch (type) {
      SearchDocType.unit => (Icons.person, Colors.blue),
      SearchDocType.weapon => (Icons.gavel, Colors.orange),
      SearchDocType.rule => (Icons.menu_book, Colors.green),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.2),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

/// Bottom bar showing loaded slot status.
class _SlotStatusBar extends StatelessWidget {
  final ImportSessionController controller;
  final VoidCallback? onTap;

  const _SlotStatusBar({required this.controller, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              for (var i = 0; i < kMaxSelectedCatalogs; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _SlotChip(slot: controller.slotState(i), index: i)),
              ],
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  final SlotState slot;
  final int index;

  const _SlotChip({required this.slot, required this.index});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (slot.status) {
      SlotStatus.empty => ('Slot ${index + 1}: Empty', Colors.grey, Icons.add_circle_outline),
      SlotStatus.fetching => slot.isBootRestoring
          ? ('Restoring…', Colors.orange, Icons.restore)
          : ('Fetching…', Colors.amber, Icons.downloading),
      SlotStatus.ready => (slot.catalogName ?? 'Ready', Colors.blue, Icons.check_circle_outline),
      SlotStatus.building => ('Building…', Colors.amber, Icons.build_circle),
      SlotStatus.loaded => (slot.catalogName ?? 'Loaded', Colors.green, Icons.check_circle),
      SlotStatus.error => ('Error', Colors.red, Icons.error_outline),
    };

    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: color),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
