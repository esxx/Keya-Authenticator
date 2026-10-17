#!/usr/bin/env bash
set -euo pipefail

SCHEME="Keya Authenticator"
PROJECT="Keya Authenticator.xcodeproj"
DESTINATION="generic/platform=iOS Simulator"

echo "==> Building (release config)…"
BUILD=(xcodebuild
    -project "$PROJECT"
    -scheme "$SCHEME"
    -destination "$DESTINATION"
    -configuration Release
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY=""
    build)
if command -v xcpretty &>/dev/null; then
    "${BUILD[@]}" | xcpretty --color
else
    "${BUILD[@]}"
fi

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

# Every class declares its deinit (MainActor default isolation would otherwise infer an isolated one)
while IFS= read -r -d '' file; do
    classes=$(grep -cE '^[[:space:]]*(@[A-Za-z]+[[:space:]]+)*((public|private|fileprivate|internal|final|nonisolated)[[:space:]]+)*class[[:space:]]+[A-Z]' "$file" || true)
    deinits=$(grep -cE '^[[:space:]]*((nonisolated|isolated)[[:space:]]+)?deinit\b' "$file" || true)
    if [ "$classes" -gt "$deinits" ]; then
        echo "FAIL: $file declares $classes class(es) but only $deinits deinit(s)"
        FAIL=1
    fi
done < <(find "Keya Authenticator" CredentialProviderExtension -name "*.swift" -print0)

if [ "$FAIL" -eq 0 ]; then
    echo ""
    echo "quality.sh PASSED"
else
    echo ""
    echo "quality.sh FAILED — fix the issues above before submitting"
    exit 1
fi
