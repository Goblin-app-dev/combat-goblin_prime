import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/voice/runtime/voice_listen_mode.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_listen_trigger.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_controller.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_state.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_stop_reason.dart';

/// Minimal voice control bar: mode toggle + push-to-talk mic button.
///
/// Observes [VoiceRuntimeController] state and mode via [ValueListenableBuilder]
/// / [addListener]. Contains no direct mic logic (Skill 06).
///
/// Wired into HomeScreen in Phase 12B. Full voice UX redesign is deferred
/// to later phases.
class VoiceControlBar extends StatefulWidget {
  final VoiceRuntimeController controller;

  const VoiceControlBar({super.key, required this.controller});

  @override
  State<VoiceControlBar> createState() => _VoiceControlBarState();
}

class _VoiceControlBarState extends State<VoiceControlBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.state.addListener(_rebuild);
    widget.controller.modeNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.state.removeListener(_rebuild);
    widget.controller.modeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state.value;
    final mode = widget.controller.mode;
    final isListening = state is ListeningState;
    final isArming = state is ArmingState;
    final isBusy = isListening || isArming;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          // Mode label + toggle
          const Text('Assist', style: TextStyle(fontSize: 12)),
          Switch(
            value: mode == VoiceListenMode.handsFreeAssistant,
            // Disable switch while actively listening to avoid mid-session flip.
            onChanged: isBusy
                ? null
                : (v) => widget.controller.setMode(
                      v
                          ? VoiceListenMode.handsFreeAssistant
                          : VoiceListenMode.pushToTalkSearch,
                    ),
          ),
          const Spacer(),
          // PTT mic button
          GestureDetector(
            onTapDown: isBusy
                ? null
                : (_) => widget.controller
                    .beginListening(trigger: VoiceListenTrigger.pushToTalk),
            onTapUp: (_) => widget.controller
                .endListening(reason: VoiceStopReason.userReleasedPushToTalk),
            onTapCancel: () => widget.controller
                .endListening(reason: VoiceStopReason.userCancelled),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isListening
                    ? Colors.red
                    : isArming
                        ? Colors.orange
                        : Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Icon(
                Icons.mic,
                color: isListening || isArming
                    ? Colors.white
                    : Theme.of(context).colorScheme.onPrimaryContainer,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
