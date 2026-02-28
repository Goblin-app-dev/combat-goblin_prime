/// Closed set of reasons for leaving [ListeningState].
///
/// Invariant: a stop reason is always set when the controller exits listening.
/// No `unknown` or `other` values — every stop is explainable (Skill 11).
enum VoiceStopReason {
  /// User released the push-to-talk button or gesture.
  userReleasedPushToTalk,

  /// User explicitly cancelled (e.g. tap cancel while listening).
  userCancelled,

  /// Hands-free listen window expired with no speech detected.
  wakeTimeout,

  /// Microphone permission was denied by the user or OS.
  permissionDenied,

  /// Audio focus was denied or lost to another app.
  focusLost,

  /// Internal engine error (e.g. audio session setup failure).
  engineError,

  /// The active [VoiceListenMode] was changed while listening.
  modeDisabled,

  /// Audio route changed (Bluetooth device connected/disconnected, etc.).
  routeChanged,

  /// STT engine threw during transcription.
  ///
  /// Controller transitions to [ErrorState] with this reason when
  /// [SpeechToTextEngine.transcribe] throws.
  sttFailed,

  /// Hard capture-duration limit exceeded.
  ///
  /// Both PTT and hands-free sessions stop with this reason when
  /// [VoiceRuntimeController.maxCaptureDuration] is exceeded.
  captureLimitReached,

  /// Wake-word engine is unavailable in hands-free mode.
  ///
  /// Emitted momentarily as [ErrorState] when [setMode] is called with
  /// [VoiceListenMode.handsFreeAssistant] but no [WakeWordDetector] is wired.
  /// The controller immediately returns to [IdleState]; PTT remains functional.
  wakeEngineUnavailable,
}
