#!/usr/bin/env bash
set -euo pipefail

install_dir="${INSTALL_DIR:-$HOME/.local/bin}"
target_binary="$install_dir/observer"

if [[ -e "$target_binary" ]]; then
  rm -f "$target_binary"
  echo "Removed $target_binary"
else
  echo "No installed observer found at $target_binary"
fi
