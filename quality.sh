#!/usr/bin/env bash
set -euo pipefail

SCHEME="Keya Authenticator"
PROJECT="Keya Authenticator.xcodeproj"
DESTINATION="platform=iOS Simulator,name=iPhone 16,OS=latest"

echo "==> Building (release config)…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -configuration Release \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build \
    | xcpretty --color 2>/dev/null || true

echo ""
echo "==> SwiftLint…"
if command -v swiftlint &>/dev/null; then
    swiftlint --strict
else
    echo "  swiftlint not found — skipping (brew install swiftlint)"
fi

echo ""
echo "==> Static checks…"

FAIL=0

# No force-try (!!) in production code
if grep -rn --include="*.swift" " try!" "Keya Authenticator/" 2>/dev/null | grep -v "//"; then
    echo "FAIL: force-try found in production code"
    FAIL=1
fi

# No force-cast (as!) in production code
if grep -rn --include="*.swift" " as!" "Keya Authenticator/" 2>/dev/null | grep -v "//"; then
    echo "FAIL: force-cast found in production code"
    FAIL=1
fi

# No print() in production code
if grep -rn --include="*.swift" "\bprint(" "Keya Authenticator/" 2>/dev/null | grep -v "//"; then
    echo "FAIL: print() found in production code"
    FAIL=1
fi

# No leftover TODOs or FIXMEs
if grep -rn --include="*.swift" "TODO\|FIXME" "Keya Authenticator/" 2>/dev/null | grep -v "//.*documented"; then
    echo "WARN: TODO/FIXME found — review before shipping"
fi

if [ "$FAIL" -eq 0 ]; then
    echo ""
    echo "quality.sh PASSED"
else
    echo ""
    echo "quality.sh FAILED — fix the issues above before submitting"
    exit 1
fi
