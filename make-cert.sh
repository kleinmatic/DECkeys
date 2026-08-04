#!/bin/sh
# Create the local self-signed code-signing identity DECkeys is built with.
# Run once. Idempotent — it exits quietly if the identity already exists.
#
# WHY: see the long comment in build.sh. Short version — an ad-hoc signature
# makes the app's designated requirement a hash of the binary, so macOS treats
# every rebuild as a new app and drops the Accessibility grant. A stable
# identity makes the requirement "this bundle id + this certificate", which
# survives rebuilds.
#
# This certificate signs nothing but local builds on this machine. It is not
# added to any system trust store, and it does not need to be: codesign will
# use an untrusted self-signed identity, and TCC pins the leaf certificate.
set -e

IDENTITY="DECkeys Local Signing"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "identity '$IDENTITY' already present — nothing to do"
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PW=$(openssl rand -hex 16)          # transient, only guards the temp PKCS#12

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$IDENTITY" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# -certpbe/-keypbe/-macalg: OpenSSL 3 defaults to a PKCS#12 MAC that macOS's
# Security framework cannot read ("MAC verification failed during PKCS12
# import"). These force the legacy algorithms macOS accepts.
openssl pkcs12 -export -out "$WORK/ident.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -passout "pass:$PW" -name "$IDENTITY" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

security import "$WORK/ident.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PW" -T /usr/bin/codesign -A

echo "created identity '$IDENTITY' in your login keychain"
echo "now run ./build.sh, then grant Accessibility to DECkeys.app one final time"
