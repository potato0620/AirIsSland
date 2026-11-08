#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
FRAMEWORKS="${AIRISLAND_UPDATE_FRAMEWORKS:?Set AIRISLAND_UPDATE_FRAMEWORKS to the Release products directory containing Sparkle.framework and its headers}"
CHECK_ROOT="$ROOT/build/checks/software-update/policy"
TEST_APP="$CHECK_ROOT/SoftwareUpdateTests.app"
mkdir -p "$TEST_APP/Contents/MacOS"
python3 - "$TEST_APP/Contents/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.airisland.updatepolicytests',
    'CFBundleName': 'SoftwareUpdateTests', 'CFBundleExecutable': 'SoftwareUpdateTests',
    'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
    'CFBundleShortVersionString': '1.0.0',
}))
PY
xcrun swiftc -parse-as-library -F "$FRAMEWORKS" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  "$ROOT/AirIsland/components/Settings/SoftwareUpdater.swift" \
  "$ROOT/Tests/SoftwareUpdateTests.swift" -o "$TEST_APP/Contents/MacOS/SoftwareUpdateTests"
"$TEST_APP/Contents/MacOS/SoftwareUpdateTests"

# Optional integration check using a real package prepared with the release tool.
if [[ -n "${AIRISLAND_UPDATE_PACKAGE_DIR:-}" ]]; then
  SPARKLE_BIN="${AIRISLAND_SPARKLE_BIN:?Set AIRISLAND_SPARKLE_BIN to the Sparkle bin directory}"
  PACKAGE_DIR="$AIRISLAND_UPDATE_PACKAGE_DIR"
  SIGNATURE="$(python3 - "$PACKAGE_DIR/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
print(ET.parse(sys.argv[1]).getroot().find('channel/item/enclosure').get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'))
PY
)"
  ARCHIVES=("$PACKAGE_DIR"/*.zip)
  [[ ${#ARCHIVES[@]} -eq 1 && -f "${ARCHIVES[0]}" ]]
  "$SPARKLE_BIN/sign_update" --account AirIsland-Personal --verify "${ARCHIVES[0]}" "$SIGNATURE"
  TAMPER_DIR="$(mktemp -d "$CHECK_ROOT/tamper.XXXXXX")"
  trap 'rm -rf "$TAMPER_DIR"' EXIT
  cp "${ARCHIVES[0]}" "$TAMPER_DIR/tampered.zip"
  printf 'changed' >> "$TAMPER_DIR/tampered.zip"
  if "$SPARKLE_BIN/sign_update" --account AirIsland-Personal --verify "$TAMPER_DIR/tampered.zip" "$SIGNATURE" > "$CHECK_ROOT/tamper.log" 2>&1; then
    echo "The tampered update unexpectedly passed signature verification" >&2
    exit 1
  fi
  echo "Real update signature verified; tampered update rejected."
fi
