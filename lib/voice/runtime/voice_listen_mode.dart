/// User-selected voice interaction mode.
enum VoiceListenMode {
  /// Mic opens only while the PTT button is held or toggled.
  ///
  /// Wake events are ignored in this mode.
  pushToTalkSearch,

  /// Wake events trigger mic open in a bounded listen window.
  ///
  /// The controller enforces a [VoiceRuntimeController.listenTimeout] to
  /// prevent indefinite open-mic sessions.
  handsFreeAssistant,
}
