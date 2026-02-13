#!/bin/bash
set -euo pipefail

# Only run in remote (Claude Code on the web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# --- Flutter SDK installation ---
# Flutter does not persist between sessions in the remote container.
# Install to a fixed path so the container cache can reuse it.

FLUTTER_HOME="/home/user/flutter"
FLUTTER_BIN="$FLUTTER_HOME/bin"

if [ -x "$FLUTTER_BIN/flutter" ]; then
  echo "Flutter already installed at $FLUTTER_BIN"
else
  echo "Installing Flutter SDK..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi

# Make flutter and dart available for this session
export PATH="$FLUTTER_BIN:$FLUTTER_BIN/cache/dart-sdk/bin:$PATH"

# Persist PATH for the rest of the Claude Code session
echo "export PATH=\"$FLUTTER_BIN:$FLUTTER_BIN/cache/dart-sdk/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"

# Precache dart artifacts (triggers SDK download if needed)
flutter precache --no-android --no-ios --no-web --no-linux --no-macos --no-windows --no-fuchsia 2>/dev/null || flutter precache 2>/dev/null || true

# Disable analytics to avoid interactive prompts
flutter config --no-analytics 2>/dev/null || true
dart --disable-analytics 2>/dev/null || true

# Install project dependencies
cd "$CLAUDE_PROJECT_DIR"
flutter pub get
