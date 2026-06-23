#!/usr/bin/env bash
# create-signing-cert.sh - Create a stable self-signed code-signing certificate.
#
# WHY: macOS TCC (Privacy permissions like Accessibility and Input Monitoring)
# tie grants to an app's CODE IDENTITY. An unsigned app gets a fresh identity on
# every rebuild, so permissions are lost each time you rebuild. Ad-hoc signing
# (codesign -s -) is keyed to the binary's content hash, so it ALSO changes on
# every rebuild. The only way to keep permissions across rebuilds is to sign with
# a stable named identity. This script creates a self-signed one you can reuse.
#
# This is a ONE-TIME setup. It requires your admin password once (to trust the
# certificate for code signing). After this, run ./scripts/make-app.sh normally.
#
# USAGE:
#   ./scripts/create-signing-cert.sh           # create only if missing
#   ./scripts/create-signing-cert.sh --force   # remove existing and recreate

set -euo pipefail

CERT_NAME="MuteMe Self-Signed"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

FORCE=false
if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
    FORCE=true
fi

if [[ "$FORCE" == false ]] && security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "==> Signing identity '$CERT_NAME' already exists. Nothing to do."
    echo "    Run ./scripts/make-app.sh to build a signed app,"
    echo "    or re-run with --force to remove and recreate the certificate."
    exit 0
fi

if [[ "$FORCE" == true ]]; then
    echo "==> --force: removing existing '$CERT_NAME' certificate and trust settings..."
fi

# Clean up any prior (untrusted/partial/invalid) "$CERT_NAME" entries from
# previous runs so we don't accumulate duplicates. Loop until none remain.
echo "==> Removing any previous '$CERT_NAME' entries (best-effort)..."
for _ in 1 2 3 4 5 6 7 8 9 10; do
    security delete-identity -c "$CERT_NAME" "$LOGIN_KEYCHAIN" 2>/dev/null || true
    if ! security find-certificate -c "$CERT_NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
        break
    fi
    security delete-certificate -c "$CERT_NAME" "$LOGIN_KEYCHAIN" 2>/dev/null || true
done

# On --force, also remove the trusted copy (and its trust settings) from the
# System keychain so stale/invalid trusted certs don't accumulate.
if [[ "$FORCE" == true ]]; then
    for _ in 1 2 3 4 5; do
        sudo security delete-certificate -c "$CERT_NAME" /Library/Keychains/System.keychain 2>/dev/null || break
    done
fi

TMPDIR_CERT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_CERT"' EXIT

echo "==> Generating self-signed code-signing certificate..."
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMPDIR_CERT/key.pem" \
    -out "$TMPDIR_CERT/cert.pem" \
    -days 3650 \
    -subj "/CN=$CERT_NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false"

echo "==> Bundling into PKCS#12..."
# macOS `security` uses an older Security framework that can't read PKCS#12 files
# produced with OpenSSL 3.x defaults (SHA-256 MAC / AES PBE) -> "MAC verification
# failed". If this openssl supports -legacy, use it to emit SHA1/3DES that macOS
# can import. A non-empty password is also more reliable than an empty one.
P12_PASSWORD="muteme"
P12_ARGS=(pkcs12 -export
    -out "$TMPDIR_CERT/cert.p12"
    -inkey "$TMPDIR_CERT/key.pem"
    -in "$TMPDIR_CERT/cert.pem"
    -passout "pass:$P12_PASSWORD")
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    P12_ARGS+=(-legacy)
fi
openssl "${P12_ARGS[@]}"

echo "==> Importing into login keychain (allowing codesign to use it)..."
security import "$TMPDIR_CERT/cert.p12" \
    -k "$LOGIN_KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign

echo "==> Trusting the certificate for code signing (requires admin password)..."
# Self-signed cert IS a root, so use trustRoot (trustAsRoot is only for
# non-root certs and errors with "invalid parameters" on a root cert).
sudo security add-trusted-cert -d \
    -r trustRoot \
    -p codeSign \
    -k /Library/Keychains/System.keychain \
    "$TMPDIR_CERT/cert.pem"

echo ""
echo "==> Done. Verifying identity is available to codesign:"
security find-identity -v -p codesigning | grep "$CERT_NAME" || {
    echo "WARNING: identity not found by codesign. You may need to open Keychain"
    echo "Access and set the certificate to 'Always Trust' for Code Signing."
    exit 1
}

echo ""
echo "Next: ./scripts/make-app.sh"
echo "Grant Accessibility + Input Monitoring ONCE; they will now persist across rebuilds."
