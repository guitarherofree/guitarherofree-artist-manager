#!/bin/bash
# Builds Manager.app into ./build. The Release and CI workflows run this on GitHub's Apple silicon Macs;
# you don't need to run it yourself to get updates.
#
#   Scripts/build.sh          Build the app, signed ad hoc.
#   Scripts/build.sh --open   Also open it (for trying a change locally).
#
# Environment (set by the workflows):
#   MARKETING_VERSION   Version to build. Defaults to the top "## x.y.z" in CHANGELOG.md.
#   BUILD_NUMBER        Build number. Defaults to 1.
#   CONFIGURATION       release (default) or debug.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# shellcheck source=../Config/release.env
source Config/release.env
OPEN=0
for arg in "$@"; do
  case "$arg" in
    --open) OPEN=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

VERSION="${MARKETING_VERSION:-$(grep -m1 -E '^## v?[0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md | awk '{print $2}')}"
VERSION="${VERSION#v}"
if ! echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: couldn't find a version like 1.2.3 at the top of CHANGELOG.md (got '$VERSION')" >&2
  exit 1
fi
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CONFIGURATION="${CONFIGURATION:-release}"

OUT="$ROOT/build"
APP="$OUT/$APP_NAME.app"

step() { printf '\n==> %s\n' "$1"; }

step "Building $APP_NAME $VERSION ($BUILD_NUMBER)"
swift build -c "$CONFIGURATION" --product "$BUILD_PRODUCT"
BIN_DIR="$(swift build -c "$CONFIGURATION" --product "$BUILD_PRODUCT" --show-bin-path)"

step "Assembling the app bundle"
rm -rf "$APP"
# Builds from before the rename were called "Artist Manager.app". Remove that copy so there's only one app to open.
if [[ -d "$OUT/Artist Manager.app" ]]; then rm -rf "$OUT/Artist Manager.app"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$BUILD_PRODUCT" "$APP/Contents/MacOS/$EXECUTABLE"
printf 'APPL????' > "$APP/Contents/PkgInfo"

escape() { printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'; }
sed -e "s|__APP_NAME__|$(escape "$APP_NAME")|g" \
    -e "s|__EXECUTABLE__|$(escape "$EXECUTABLE")|g" \
    -e "s|__BUNDLE_ID__|$(escape "$BUNDLE_ID")|g" \
    -e "s|__VERSION__|$(escape "$VERSION")|g" \
    -e "s|__BUILD__|$(escape "$BUILD_NUMBER")|g" \
    -e "s|__GITHUB_REPOSITORY__|$(escape "$GITHUB_REPOSITORY")|g" \
    Config/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

step "Signing ad hoc"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

step "Done"
echo "$APP"
if [[ "$OPEN" == "1" ]]; then
  # A copy that's already running would keep showing the old build, so quit it first.
  if pgrep -xq "$EXECUTABLE"; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do pgrep -xq "$EXECUTABLE" || break; sleep 0.5; done
  fi
  open "$APP"
fi
