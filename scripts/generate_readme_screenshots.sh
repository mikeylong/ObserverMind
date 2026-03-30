#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_root="$(cd "$script_dir/.." && pwd)"

cd "$package_root"

swift test --filter ObserverMindTests.generateReadmeScreenshots

echo "Generated:"
echo "  $package_root/docs/images/dashboard-light.png"
echo "  $package_root/docs/images/dashboard-dark.png"
