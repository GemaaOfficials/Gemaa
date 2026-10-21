#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node --check "$ROOT/electron/main.cjs"
node --check "$ROOT/electron/preload.cjs"
node --check "$ROOT/src/browser-utils.cjs"
node --test "$ROOT"/tests/*.test.cjs
printf '\nSource syntax checks and utility tests passed.\n'
printf 'A release build additionally requires npm dependencies; Android requires Flutter + Android SDK; Windows NSIS is best built on a Windows runner.\n'
