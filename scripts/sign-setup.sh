#!/bin/bash
# Creates a local self-signed code-signing certificate "Caelestia Local Signing" in the login
# keychain so every build of Caelestia for Mac has the SAME code signature. macOS ties
# Accessibility / Input Monitoring / Screen Recording grants to the signing identity; with ad-hoc
# signatures every rebuild is a "new app" and the grants are lost.
#
# What it does (you can read it all below; it asks before each step):
#   1. generates a 2048-bit RSA key + X.509 certificate with the codeSigning extended key usage
#      (10 years) in a temporary directory;
#   2. imports them into ~/Library/Keychains/login.keychain-db (codesign is allowed to use the key);
#   3. marks the certificate as trusted for code signing for YOUR user only (no sudo, no system
#      trust store);
#   4. shreds the temporary files. The private key never leaves the keychain and is never
#      written into the repo.
#
# Remove it again with:  scripts/sign-setup.sh --remove
set -euo pipefail

NAME="Caelestia Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if [[ "${1:-}" == "--remove" ]]; then
  echo "Removing \"$NAME\" from the login keychain..."
  security delete-identity -c "$NAME" "$KEYCHAIN" 2>/dev/null || true
  security delete-certificate -c "$NAME" "$KEYCHAIN" 2>/dev/null || true
  echo "done."
  exit 0
fi

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$NAME\""; then
  echo "\"$NAME\" already exists in the login keychain. Nothing to do."
  exit 0
fi

echo "This will create a self-signed code-signing certificate named \"$NAME\" in your login keychain."
echo "It is only used to sign the Caelestia for Mac apps you build on this machine."
read -r -p "Continue? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "aborted"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -P -f "$TMP"/* 2>/dev/null || rm -rf "$TMP"; rmdir "$TMP" 2>/dev/null || true' EXIT

cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
O = Caelestia for Mac (local)
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
EOF

echo "==> generating key and certificate"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" >/dev/null 2>&1
PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export -legacy -out "$TMP/identity.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout "pass:$PASS" >/dev/null 2>&1 || \
openssl pkcs12 -export -out "$TMP/identity.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout "pass:$PASS" >/dev/null 2>&1

echo "==> importing into the login keychain (codesign may use the key without asking each time)"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "==> trusting the certificate for code signing (your user only; macOS will ask for your login password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
  echo "==> ok: \"$NAME\" is ready. scripts/build.sh will use it automatically."
else
  echo "error: the identity was not created; see 'security find-identity -v -p codesigning'" >&2
  exit 1
fi
