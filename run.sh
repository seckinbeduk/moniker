#!/bin/bash
# Build and run Moniker without opening Xcode.
#   ./run.sh         build (Debug) and launch
#   ./run.sh test    run the MonikerCore tests
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-run}" == "test" ]]; then
  swift test --package-path MonikerCore 2>&1 | grep -E "error:|✘|passed|failed" | tail -40
  exit "${PIPESTATUS[0]}"
fi

command -v xcodegen >/dev/null || { echo "XcodeGen is missing: brew install xcodegen"; exit 1; }
xcodegen generate --quiet
mkdir -p .build

# Ad-hoc signing is enough to run locally.
SIGN=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="")
set +e
xcodebuild -project Moniker.xcodeproj -scheme Moniker -configuration Debug \
  -destination "platform=macOS,arch=arm64" -derivedDataPath .build/DerivedData \
  "${SIGN[@]}" build > .build/build.log 2>&1
status=$?
set -e
if [[ $status -ne 0 ]]; then
  grep -E "error:" .build/build.log | sort -u | head -40
  echo "❌ Build failed (full log: .build/build.log)"
  exit $status
fi

APP=".build/DerivedData/Build/Products/Debug/Moniker.app"
# Quit the running copy and wait until it's really gone; opening too early fails with -609.
if pkill -x Moniker 2>/dev/null; then
  for _ in $(seq 1 50); do pgrep -x Moniker >/dev/null || break; sleep 0.1; done
  sleep 0.3
fi
open "$APP" || { sleep 1; open "$APP"; }
echo "✅ Moniker is running. Look for the tag in the menu bar."
