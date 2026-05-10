#!/usr/bin/env bash
set -euo pipefail

SCHEME="Keya Authenticator"
PROJECT="Keya Authenticator.xcodeproj"
DESTINATION="platform=iOS Simulator,name=iPhone 16,OS=latest"

echo "==> Running unit tests…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -configuration Debug \
    -testPlan UnitTests \
    test \
    | xcpretty --color 2>/dev/null || \
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -configuration Debug \
    test

echo ""
echo "test.sh PASSED"
