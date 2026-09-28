#!/bin/sh
# Install into the current project (or explicit -ProjectRoot), not this checkout.
set -eu
RULES_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if ! command -v pwsh >/dev/null 2>&1; then
  echo "Нужен PowerShell 7 (pwsh). Установка для macOS: https://learn.microsoft.com/powershell/scripting/install/install-powershell-on-macos" >&2
  exit 127
fi
exec pwsh -NoLogo -NoProfile -File "$RULES_DIR/install.ps1" "$@"
