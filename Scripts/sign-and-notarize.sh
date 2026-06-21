#!/usr/bin/env bash
# Build a universal release, sign with Developer ID + hardened runtime,
# notarize, staple, and produce a distributable zip.
#
# Credentials (any one source):
#   * Environment: APP_STORE_CONNECT_API_KEY_P8 (PEM text), APP_STORE_CONNECT_KEY_ID,
#     APP_STORE_CONNECT_ISSUER_ID.
#   * A local, git-ignored notary-creds.env file exporting the same vars.
#   * 1Password: run this script under `op run --env-file=...` so the vars are injected.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME=${APP_NAME:-AppReset}
APP_BINARY=${APP_BINARY:-AppResetApp}
EMBED_CLI=${EMBED_CLI:-appreset}
APP_IDENTITY=${APP_IDENTITY:-"Developer ID Application: Shahin Farzane (89S32876QM)"}
APP_BUNDLE="${APP_NAME}.app"
source "$ROOT/version.env"
ZIP_NAME="${APP_NAME}-${MARKETING_VERSION}.zip"

# Load credentials from a git-ignored file if present and not already in the env.
if [[ -f "$ROOT/notary-creds.env" && -z "${APP_STORE_CONNECT_KEY_ID:-}" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/notary-creds.env"
fi

if [[ -z "${APP_STORE_CONNECT_API_KEY_P8:-}" || -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "Missing APP_STORE_CONNECT_* env vars (API key PEM, key id, issuer id)." >&2
  echo "Set them in the environment, in notary-creds.env, or via 'op run'." >&2
  exit 1
fi

echo "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > /tmp/app-store-connect-key.p8
trap 'rm -f /tmp/app-store-connect-key.p8 /tmp/${APP_NAME}Notarize.zip' EXIT

ARCHES_VALUE=${ARCHES:-"arm64 x86_64"}
ARCH_LIST=( ${ARCHES_VALUE} )
for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c release --arch "$ARCH"
done

# package_app.sh signs the bundle + embedded CLI with the Developer ID identity.
APP_IDENTITY="$APP_IDENTITY" EMBED_CLI="$EMBED_CLI" ARCHES="${ARCHES_VALUE}" \
  "$ROOT/Scripts/package_app.sh" release

APP_ENTITLEMENTS="${APP_ENTITLEMENTS:-$ROOT/Resources/${APP_NAME}.entitlements}"

# Re-seal the outer bundle (entitlements + hardened runtime).
codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
  --entitlements "$APP_ENTITLEMENTS" \
  "$APP_BUNDLE"

DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "/tmp/${APP_NAME}Notarize.zip"

xcrun notarytool submit "/tmp/${APP_NAME}Notarize.zip" \
  --key /tmp/app-store-connect-key.p8 \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

xcrun stapler staple "$APP_BUNDLE"

xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

mkdir -p "$ROOT/dist"
"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "$ROOT/dist/$ZIP_NAME"

spctl -a -t exec -vv "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"

echo "Done: dist/$ZIP_NAME"
