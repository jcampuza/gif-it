#!/bin/sh
set -eu

CERT_NAME="Gif It Development"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
  echo "Certificate '$CERT_NAME' already exists in the login keychain."
  echo "Run ./scripts/signing-status.sh to verify it."
  echo "If codesign prompts for key access, enter your login password and choose Always Allow."
  exit 0
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gif-it-signing.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM
P12_PASSWORD=$(openssl rand -hex 24)

cat > "$WORK_DIR/certificate.conf" <<EOF
[ req ]
distinguished_name = distinguished_name
x509_extensions = code_signing
prompt = no

[ distinguished_name ]
CN = $CERT_NAME
O = Gif It Development

[ code_signing ]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
basicConstraints = critical,CA:true
EOF

openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout "$WORK_DIR/private-key.pem" \
  -out "$WORK_DIR/certificate.pem" \
  -config "$WORK_DIR/certificate.conf"
openssl pkcs12 -export \
  -out "$WORK_DIR/identity.p12" \
  -inkey "$WORK_DIR/private-key.pem" \
  -in "$WORK_DIR/certificate.pem" \
  -name "$CERT_NAME" \
  -passout "pass:$P12_PASSWORD"
security import "$WORK_DIR/identity.p12" \
  -k "$LOGIN_KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

echo "Imported '$CERT_NAME'. In Keychain Access, set its Code Signing trust to Always Trust."
echo "On the first build, enter your login password and choose Always Allow when codesign asks"
echo "to access the private key. That grants /usr/bin/codesign persistent access for later builds."
