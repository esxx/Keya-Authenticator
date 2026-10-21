#!/usr/bin/env bash
set -euo pipefail

SCHEME="Keya Authenticator"
PROJECT="Keya Authenticator.xcodeproj"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=latest}"

echo "==> Running unit tests…"
TEST=(xcodebuild
    -project "$PROJECT"
    -scheme "$SCHEME"
    -destination "$DESTINATION"
    -configuration Debug
    -testPlan "Keya Authenticator"
    "$@"
    test)
if command -v xcpretty &>/dev/null; then
    "${TEST[@]}" | xcpretty --color
else
    "${TEST[@]}"
fi

echo ""
echo "test.sh PASSED"
