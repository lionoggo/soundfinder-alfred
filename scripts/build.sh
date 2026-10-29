#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
/usr/bin/codesign --force --sign - "$binary_dir/soundfinder"
python3 scripts/package_workflow.py "$binary_dir/soundfinder"
python3 scripts/test_workflow.py dist/SoundFinder-1.1.1.alfredworkflow
