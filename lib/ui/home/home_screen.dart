import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';
import 'package:combat_goblin_prime/ui/import/import_session_controller.dart';
import 'package:combat_goblin_prime/ui/import/import_session_provider.dart';
import 'package:combat_goblin_prime/voice/adapters/voice_platform_factory.dart';
import 'package:combat_goblin_prime/voice/models/spoken_entity.dart';
import 'package:combat_goblin_prime/voice/models/spoken_variant.dart';
import 'package:combat_goblin_prime/voice/models/spoken_response_plan.dart';
import 'package:combat_goblin_prime/voice/models/text_candidate.dart';
import 'package:combat_goblin_prime/voice/models/voice_search_response.dart';
import 'package:combat_goblin_prime/voice/understanding/voice_assistant_coordinator.dart';
import 'package:combat_goblin_prime/voice/runtime/noop_text_to_speech_engine.dart';
import 'package:combat_goblin_prime/voice/runtime/spoken_plan_player.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_audio_focus_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_audio_route_observer.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_mic_permission_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_listen_trigger.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_controller.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_event.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_state.dart';
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

  // Phase 12E: spoken output player, two-phase init mirrors _voiceController.
  late SpokenPlanPlayer _spokenPlanPlayer;

  /// Guards against duplicate SnackBars per (sessionId, reason) pair.
  final Set<(int, VoiceStopReason)> _shownVoiceErrors = {};

  VoiceSearchResponse? _voiceResult;

  /// Structured plan from the voice coordinator.
  SpokenResponsePlan? _voicePlan;

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
    // Silent until real voice is initialized; Noop (not Fake) keeps production
    // code free of test-only artifacts.
    _spokenPlanPlayer = SpokenPlanPlayer(
      engine: NoopTextToSpeechEngine(),
      settings: VoiceSettings.defaults,
    );
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

    // Replace spoken plan player with one backed by the real TTS engine.
    final oldPlayer = _spokenPlanPlayer;
    await oldPlayer.stop(); // stop any in-flight audio before swap
    _spokenPlanPlayer = SpokenPlanPlayer(
      engine: factory.createTtsEngine(),
      settings: settings,
    );
    oldPlayer.dispose(); // fire-and-forget; stop() already called

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _voiceEventSub?.cancel();
    _searchController.dispose();
    _voiceController.dispose();
    _spokenPlanPlayer.dispose();
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
      _searchController.text = candidate.text;
    });
    // Speak the plan. play() handles its own concurrency: any previous
    // playback is cancelled before the new plan starts.
    unawaited(_spokenPlanPlayer.play(plan));
  }

  /// Shows a one-time SnackBar for voice permission/focus errors.
  void _onVoiceEvent(VoiceRuntimeEvent event) {
    if (!mounted) return;

    // Stop funnel: silence TTS before mic capture begins to prevent echo.
    if (event is ListeningBegan) {
      unawaited(_spokenPlanPlayer.stop());
      return;
    }

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

  void _search(String query) {
    final controller = ImportSessionProvider.of(context);
    final bundles = _activeBundles(controller);
    if (query.isEmpty || bundles.isEmpty) {
      setState(() {
        _voiceResult = null;
        _voicePlan = null;
      });
      return;
    }
    // Route through coordinator so typed questions use the full intent pipeline.
    final hints = _buildContextHints(controller);
    unawaited(() async {
      final plan = await _coordinator.handleTranscript(
        transcript: query,
        slotBundles: bundles,
        contextHints: hints,
      );
      if (!mounted) return;
      setState(() {
        _voicePlan = plan;
        _voiceResult = null;
      });
    }());
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
    // Resolve bundle once at tap time — not inside the sheet builder.
    final controller = ImportSessionProvider.of(context);
    final bundle = _activeBundles(controller)[variant.sourceSlotId];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: _buildDetailContent(sheetContext, variant, bundle),
        ),
      ),
    );
  }

  Widget _buildDetailContent(
    BuildContext context,
    SpokenVariant variant,
    IndexBundle? bundle,
  ) {
    final children = <Widget>[
      Text(variant.displayName, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text(
        '${variant.docType.name} · ${variant.sourceSlotId}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade600,
            ),
      ),
      const Divider(height: 24),
    ];

    if (bundle == null) {
      children.add(Text(
        '[no bundle available for slot ${variant.sourceSlotId}]',
        style: TextStyle(color: Colors.orange.shade700),
      ));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
    }

    switch (variant.docType) {
      case SearchDocType.unit:
        _addUnitDetail(context, children, variant.docId, bundle);
      case SearchDocType.weapon:
        _addWeaponDetail(context, children, variant.docId, bundle);
      case SearchDocType.rule:
        _addRuleDetail(context, children, variant.docId, bundle);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  void _addUnitDetail(
    BuildContext ctx,
    List<Widget> out,
    String docId,
    IndexBundle bundle,
  ) {
    final unit = bundle.unitByDocId(docId);
    if (unit == null) {
      out.add(Text('[missing unit: $docId]',
          style: TextStyle(color: Colors.orange.shade700)));
      return;
    }

    if (unit.characteristics.isNotEmpty) {
      out.add(_sectionLabel(ctx, 'Stats'));
      out.add(_characteristicsRow(unit.characteristics));
      out.add(const SizedBox(height: 12));
    }

    if (unit.costs.isNotEmpty) {
      out.add(_sectionLabel(ctx, 'Points'));
      for (final cost in unit.costs) {
        out.add(Text('${cost.typeName}: ${cost.value.toStringAsFixed(0)}'));
      }
      out.add(const SizedBox(height: 12));
    }

    if (unit.keywordTokens.isNotEmpty) {
      out.add(_sectionLabel(ctx, 'Keywords'));
      out.add(Text(
        unit.keywordTokens.join(', '),
        style: Theme.of(ctx).textTheme.bodySmall,
      ));
      out.add(const SizedBox(height: 12));
    }

    // Weapons: resolve, sort by (name, docId), render.
    final weapons = unit.weaponDocRefs
        .map(bundle.weaponByDocId)
        .whereType<WeaponDoc>()
        .toList()
      ..sort((a, b) {
        final n = a.name.compareTo(b.name);
        return n != 0 ? n : a.docId.compareTo(b.docId);
      });
    final missingWeapons =
        unit.weaponDocRefs.where((r) => bundle.weaponByDocId(r) == null).toList();

    if (weapons.isNotEmpty || missingWeapons.isNotEmpty) {
      out.add(_sectionLabel(ctx, 'Weapons'));
      for (final w in weapons) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(w.name, style: Theme.of(ctx).textTheme.titleSmall),
        ));
        out.add(_characteristicsRow(w.characteristics));
        if (w.keywordTokens.isNotEmpty) {
          out.add(Text(
            w.keywordTokens.join(', '),
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ));
        }
      }
      for (final ref in missingWeapons) {
        out.add(Text('[missing weapon: $ref]',
            style: TextStyle(color: Colors.orange.shade700)));
      }
      out.add(const SizedBox(height: 12));
    }

    // Rules/Abilities: resolve, sort by (name, docId), render.
    final rules = unit.ruleDocRefs
        .map(bundle.ruleByDocId)
        .whereType<RuleDoc>()
        .toList()
      ..sort((a, b) {
        final n = a.name.compareTo(b.name);
        return n != 0 ? n : a.docId.compareTo(b.docId);
      });
    final missingRules =
        unit.ruleDocRefs.where((r) => bundle.ruleByDocId(r) == null).toList();

    if (rules.isNotEmpty || missingRules.isNotEmpty) {
      out.add(_sectionLabel(ctx, 'Abilities'));
      for (final rule in rules) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            rule.page != null ? '${rule.name} (p. ${rule.page})' : rule.name,
            style: Theme.of(ctx).textTheme.titleSmall,
          ),
        ));
        out.add(Text(rule.description, style: Theme.of(ctx).textTheme.bodySmall));
      }
      for (final ref in missingRules) {
        out.add(Text('[missing rule: $ref]',
            style: TextStyle(color: Colors.orange.shade700)));
      }
    }
  }

  void _addWeaponDetail(
    BuildContext ctx,
    List<Widget> out,
    String docId,
    IndexBundle bundle,
  ) {
    final weapon = bundle.weaponByDocId(docId);
    if (weapon == null) {
      out.add(Text('[missing weapon: $docId]',
          style: TextStyle(color: Colors.orange.shade700)));
      return;
    }

    if (weapon.characteristics.isNotEmpty) {
      out.add(_sectionLabel(ctx, 'Profile'));
      out.add(_characteristicsRow(weapon.characteristics));
      out.add(const SizedBox(height: 12));
    }

    if (weapon.keywordTokens.isNotEmpty) {
      out.add(_sectionLabel(ctx, 'Keywords'));
      out.add(Text(
        weapon.keywordTokens.join(', '),
        style: Theme.of(ctx).textTheme.bodySmall,
      ));
      out.add(const SizedBox(height: 12));
    }

    final rules = weapon.ruleDocRefs
        .map(bundle.ruleByDocId)
        .whereType<RuleDoc>()
        .toList()
      ..sort((a, b) {
        final n = a.name.compareTo(b.name);
        return n != 0 ? n : a.docId.compareTo(b.docId);
      });

    if (rules.isNotEmpty) {
      out.add(_sectionLabel(ctx, 'Rules'));
      for (final rule in rules) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(rule.name, style: Theme.of(ctx).textTheme.titleSmall),
        ));
        out.add(Text(rule.description, style: Theme.of(ctx).textTheme.bodySmall));
        if (rule.page != null) {
          out.add(Text('Page: ${rule.page}', style: Theme.of(ctx).textTheme.bodySmall));
        }
      }
    }
  }

  void _addRuleDetail(
    BuildContext ctx,
    List<Widget> out,
    String docId,
    IndexBundle bundle,
  ) {
    final rule = bundle.ruleByDocId(docId);
    if (rule == null) {
      out.add(Text('[missing rule: $docId]',
          style: TextStyle(color: Colors.orange.shade700)));
      return;
    }

    out.add(Text(rule.description));
    if (rule.page != null) {
      out.add(const SizedBox(height: 8));
      out.add(Text('Page: ${rule.page}', style: Theme.of(ctx).textTheme.bodySmall));
    }
  }

  Widget _characteristicsRow(List<IndexedCharacteristic> chars) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final c in chars)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.name,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              Text(
                c.valueText,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext ctx, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: Theme.of(ctx)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
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

            // --- Input row: text field + mic button ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Ask a question…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: _search,
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _MicButton(controller: _voiceController),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 1),

            // --- Body: results / states ---
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

// ---------------------------------------------------------------------------
// Mic button — push-to-talk, observes VoiceRuntimeController state directly.
// ---------------------------------------------------------------------------

class _MicButton extends StatefulWidget {
  final VoiceRuntimeController controller;
  const _MicButton({required this.controller});

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> {
  @override
  void initState() {
    super.initState();
    widget.controller.state.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.state.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state.value;
    final isListening = state is ListeningState;
    final isArming = state is ArmingState;
    final isBusy = isListening || isArming;

    final Color bg = isListening
        ? Colors.red
        : isArming
            ? Colors.orange
            : Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTapDown: isBusy
          ? null
          : (_) => widget.controller
              .beginListening(trigger: VoiceListenTrigger.pushToTalk),
      onTapUp: (_) => widget.controller
          .endListening(reason: VoiceStopReason.userReleasedPushToTalk),
      onTapCancel: () => widget.controller
          .endListening(reason: VoiceStopReason.userCancelled),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg,
          boxShadow: [
            BoxShadow(
              color: bg.withValues(alpha: 0.35),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(
          isListening ? Icons.stop : Icons.mic,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }
}
