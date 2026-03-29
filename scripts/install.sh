#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_root="$(cd "$script_dir/.." && pwd)"
install_dir="${INSTALL_DIR:-$HOME/.local/bin}"

cd "$package_root"

echo "Building observer in release mode..."
swift build -c release --product observer

bin_dir="$(swift build -c release --product observer --show-bin-path)"
source_binary="$bin_dir/observer"
target_binary="$install_dir/observer"

if [[ ! -x "$source_binary" ]]; then
  echo "error: built binary not found at $source_binary" >&2
  exit 1
fi

mkdir -p "$install_dir"
install -m 0755 "$source_binary" "$target_binary"

echo "Installed observer to $target_binary"

if [[ ":$PATH:" == *":$install_dir:"* ]]; then
  echo "observer is available on your PATH."
else
  echo "warning: $install_dir is not currently on PATH." >&2
  echo "Add this to your shell profile:" >&2
  echo "  export PATH=\"$install_dir:\$PATH\"" >&2
fi
