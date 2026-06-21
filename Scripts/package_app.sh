#!/usr/bin/env bash
# Build the SwiftPM executables and assemble a macOS .app bundle.
#
# Differs from the stock template in two ways:
#   * APP_NAME (display / bundle, e.g. "AppReset") is decoupled from APP_BINARY
#     (the SwiftPM product, e.g. "AppResetApp"). On a case-insensitive volume the
#     GUI binary and the `appreset` CLI cannot both be called "AppReset", so the
#     product is AppResetApp while the bundle is still AppReset.app.
#   * EMBED_CLI names a second executable product (the `appreset` CLI) that gets
#     copied into Contents/MacOS and code-signed alongside the app.
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME=${APP_NAME:-AppReset}            # display name + bundle name
APP_BINARY=${APP_BINARY:-AppResetApp}     # SwiftPM executable product for the GUI
EMBED_CLI=${EMBED_CLI:-appreset}          # CLI product embedded in the bundle ("" to skip)
BUNDLE_ID=${BUNDLE_ID:-ceo.nerd.appreset}
MACOS_MIN_VERSION=${MACOS_MIN_VERSION:-26.0}
MENU_BAR_APP=${MENU_BAR_APP:-0}
SIGNING_MODE=${SIGNING_MODE:-}
APP_IDENTITY=${APP_IDENTITY:-}
APP_CATEGORY=${APP_CATEGORY:-public.app-category.developer-tools}
COPYRIGHT=${COPYRIGHT:-"Copyright © 2026 Shahin Farzane. MIT Licensed."}

if [[ -f "$ROOT/version.env" ]]; then
  source "$ROOT/version.env"
else
  MARKETING_VERSION=${MARKETING_VERSION:-0.1.0}
  BUILD_NUMBER=${BUILD_NUMBER:-1}
fi

ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  HOST_ARCH=$(uname -m)
  ARCH_LIST=("$HOST_ARCH")
fi

# Build all requested architectures in a SINGLE invocation. SwiftPM emits a
# universal binary directly; building arches one-by-one would clobber the shared
# .build/<conf> output on this toolchain.
ARCH_FLAGS=()
for ARCH in "${ARCH_LIST[@]}"; do
  ARCH_FLAGS+=(--arch "$ARCH")
done
swift build -c "$CONF" "${ARCH_FLAGS[@]}"

APP="$ROOT/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

# Convert Icon.icon to Icon.icns if an Icon Composer file is present.
ICON_SOURCE="$ROOT/Icon.icon"
ICON_TARGET="$ROOT/Icon.icns"
if [[ -f "$ICON_SOURCE" ]]; then
  iconutil --convert icns --output "$ICON_TARGET" "$ICON_SOURCE" 2>/dev/null || true
fi

LSUI_VALUE="false"
if [[ "$MENU_BAR_APP" == "1" ]]; then
  LSUI_VALUE="true"
fi

BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_BINARY}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>LSUIElement</key><${LSUI_VALUE}/>
    <key>LSApplicationCategoryType</key><string>${APP_CATEGORY}</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>${COPYRIGHT}</string>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
</dict>
</plist>
PLIST

build_product_path() {
  local name="$1"
  local cap
  case "$CONF" in
    release) cap="Release" ;;
    debug) cap="Debug" ;;
    *) cap="$CONF" ;;
  esac
  # A multi-arch build lands under .build/apple/Products/<Config>/; a single-arch
  # build lands in .build/<conf>/. Probe both and return whichever exists.
  local candidates=(
    ".build/apple/Products/$cap/$name"
    ".build/$CONF/$name"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done
  echo ".build/$CONF/$name"
}

verify_binary_arches() {
  local binary="$1"; shift
  local expected=("$@")
  local actual
  actual=$(lipo -archs "$binary")
  local actual_count expected_count
  actual_count=$(wc -w <<<"$actual" | tr -d ' ')
  expected_count=${#expected[@]}
  if [[ "$actual_count" -ne "$expected_count" ]]; then
    echo "ERROR: $binary arch mismatch (expected: ${expected[*]}, actual: ${actual})" >&2
    exit 1
  fi
  for arch in "${expected[@]}"; do
    if [[ "$actual" != *"$arch"* ]]; then
      echo "ERROR: $binary missing arch $arch (have: ${actual})" >&2
      exit 1
    fi
  done
}

install_binary() {
  local name="$1"
  local dest="$2"
  local src
  src=$(build_product_path "$name")
  if [[ ! -f "$src" ]]; then
    echo "ERROR: Missing ${name} build at ${src}" >&2
    exit 1
  fi
  cp "$src" "$dest"
  chmod +x "$dest"
  verify_binary_arches "$dest" "${ARCH_LIST[@]}"
}

# Main GUI binary (named after CFBundleExecutable).
install_binary "$APP_BINARY" "$APP/Contents/MacOS/$APP_BINARY"

# Embed the CLI tool inside the bundle so the app can offer to install it.
if [[ -n "$EMBED_CLI" ]]; then
  install_binary "$EMBED_CLI" "$APP/Contents/MacOS/$EMBED_CLI"
fi

# Bundle app resources (if any).
APP_RESOURCES_DIR="$ROOT/Sources/App/Resources"
if [[ -d "$APP_RESOURCES_DIR" ]]; then
  cp -R "$APP_RESOURCES_DIR/." "$APP/Contents/Resources/"
fi

# SwiftPM resource bundles are emitted next to the built binary.
PREFERRED_BUILD_DIR="$(dirname "$(build_product_path "$APP_BINARY")")"
shopt -s nullglob
SWIFTPM_BUNDLES=("${PREFERRED_BUILD_DIR}/"*.bundle)
shopt -u nullglob
if [[ ${#SWIFTPM_BUNDLES[@]} -gt 0 ]]; then
  for bundle in "${SWIFTPM_BUNDLES[@]}"; do
    cp -R "$bundle" "$APP/Contents/Resources/"
  done
fi

if [[ -f "$ICON_TARGET" ]]; then
  cp "$ICON_TARGET" "$APP/Contents/Resources/Icon.icns"
fi

# Ensure contents are writable before stripping attributes and signing.
chmod -R u+w "$APP"

# Strip extended attributes to prevent AppleDouble files that break code sealing.
xattr -cr "$APP"
find "$APP" -name '._*' -delete

ENTITLEMENTS_DIR="$ROOT/.build/entitlements"
mkdir -p "$ENTITLEMENTS_DIR"
DEFAULT_ENTITLEMENTS="$ROOT/Resources/${APP_NAME}.entitlements"
if [[ ! -f "$DEFAULT_ENTITLEMENTS" ]]; then
  DEFAULT_ENTITLEMENTS="$ENTITLEMENTS_DIR/${APP_NAME}.entitlements"
  if [[ ! -f "$DEFAULT_ENTITLEMENTS" ]]; then
    cat > "$DEFAULT_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Non-sandboxed developer tool. -->
</dict>
</plist>
PLIST
  fi
fi
APP_ENTITLEMENTS=${APP_ENTITLEMENTS:-$DEFAULT_ENTITLEMENTS}

if [[ "$SIGNING_MODE" == "adhoc" || -z "$APP_IDENTITY" ]]; then
  CODESIGN_ARGS=(--force --sign "-")
else
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$APP_IDENTITY")
fi

# Sign embedded frameworks and their nested binaries before the app bundle.
sign_frameworks() {
  shopt -s nullglob
  local fw
  for fw in "$APP/Contents/Frameworks/"*.framework; do
    [[ -d "$fw" ]] || continue
    while IFS= read -r -d '' bin; do
      codesign "${CODESIGN_ARGS[@]}" "$bin"
    done < <(find "$fw" -type f -perm -111 -print0)
    codesign "${CODESIGN_ARGS[@]}" "$fw"
  done
  shopt -u nullglob
}
sign_frameworks

# Sign the embedded CLI (a nested Mach-O must be signed before the outer bundle).
if [[ -n "$EMBED_CLI" && -f "$APP/Contents/MacOS/$EMBED_CLI" ]]; then
  codesign "${CODESIGN_ARGS[@]}" "$APP/Contents/MacOS/$EMBED_CLI"
fi

codesign "${CODESIGN_ARGS[@]}" \
  --entitlements "$APP_ENTITLEMENTS" \
  "$APP"

echo "Created $APP"
