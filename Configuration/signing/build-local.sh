#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA="${AIRISLAND_LOCAL_DERIVED_DATA:-$PROJECT_ROOT/build/local-signed/DerivedData}"
SIGNER="$PROJECT_ROOT/Configuration/signing/local_signing.py"
# Initialization is deliberately separate: missing keys must never silently change identity.
python3 "$SIGNER" identity > /dev/null
BUILD_ARGS=(-project AirIsland.xcodeproj -scheme AirIsland -configuration Release
  -derivedDataPath "$DERIVED_DATA")
if [[ -n "${AIRISLAND_SOURCE_PACKAGES:-}" ]]; then
  BUILD_ARGS+=(-clonedSourcePackagesDirPath "$AIRISLAND_SOURCE_PACKAGES"
    -disableAutomaticPackageResolution -skipPackageUpdates)
fi
xcodebuild "${BUILD_ARGS[@]}" build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
# The intermediate ad-hoc app must never be installed. Re-sign owned code inside out.
python3 "$SIGNER" sign --app "$DERIVED_DATA/Build/Products/Release/AirIsland.app"
