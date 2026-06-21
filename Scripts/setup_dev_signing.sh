#!/usr/bin/env bash
# Create a stable self-signed development code-signing identity to reduce
# keychain prompts. Only needed if you don't want ad-hoc signing and don't
# want to use your real Developer ID for local builds.
set -euo pipefail

APP_NAME=${APP_NAME:-AppReset}
CERT_NAME="${APP_NAME} Development"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "Certificate '$CERT_NAME' already exists."
  echo "Export this in your shell profile:"
  echo "  export APP_IDENTITY='$CERT_NAME'"
  exit 0
fi

echo "Creating self-signed certificate '$CERT_NAME'..."

TEMP_CONFIG=$(mktemp)
trap "rm -f $TEMP_CONFIG" EXIT

cat > "$TEMP_CONFIG" <<EOFCONF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[ req_distinguished_name ]
CN = $CERT_NAME
O = ${APP_NAME} Development
C = US

[ v3_req ]
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
EOFCONF

openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
    -nodes -keyout /tmp/dev.key -out /tmp/dev.crt \
    -config "$TEMP_CONFIG" 2>/dev/null

openssl pkcs12 -export -out /tmp/dev.p12 \
    -inkey /tmp/dev.key -in /tmp/dev.crt \
    -passout pass: 2>/dev/null

security import /tmp/dev.p12 -k ~/Library/Keychains/login.keychain-db \
  -T /usr/bin/codesign -T /usr/bin/security

rm -f /tmp/dev.{key,crt,p12}

echo ""
echo "Trust this certificate for code signing in Keychain Access."
echo "Then export in your shell profile:"
echo "  export APP_IDENTITY='$CERT_NAME'"
