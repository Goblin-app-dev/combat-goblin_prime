#!/usr/bin/env bash
set -euo pipefail

feature_dir="lib/features/github_repository_search"

if [[ ! -d "$feature_dir" ]]; then
  echo "[info] $feature_dir not present yet; isolation check skipped."
  exit 0
fi

if rg -n "^import 'package:combat_goblin_prime/modules/|^import '../+modules/|^import '.*/modules/" "$feature_dir" -g '*.dart' ; then
  echo "[fail] feature imports lib/modules, which violates isolation boundary"
  exit 1
fi

echo "[pass] no feature imports from lib/modules detected"
