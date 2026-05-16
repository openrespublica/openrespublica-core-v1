#!/bin/bash
set -e
# orp-pki-setup.sh — Sovereign PKI Certificate Generation
# Creates the certificate infrastructure for ORP Engine:
#   sovereign_root.crt/key  — Root CA (10 years)
#   orp_server.crt/key      — Nginx TLS server certificate (1 year)
#   operator_01.crt/key     — Operator client certificate (1 year)
#   operator_01.p12         — PKCS#12 bundle for browser import
#
# Run inside Termux via Alpine proot-distro. Idempotent — re-running
# will skip creation if files already exist.

PKI_DIR="${PKI_DIR:-$HOME/.orp_engine/ssl}"
mkdir -p "$PKI_DIR"
cd "$PKI_DIR"
touch index.txt
[ -f crlnumber ] || echo 1000 > crlnumber

echo "[*] Checking for openssl..."
if ! command -v openssl >/dev/null 2>&1; then
    echo "[*] Installing openssl..."
    apk update && apk add --no-cache openssl
fi

# Helper: certificate expiry check
check_cert_expiry() {
    local cert_path="$1" cert_name="$2"
    [ -f "$cert_path" ] || return 1
    local expiry_date days_left expiry_epoch now_epoch
    expiry_date="$(openssl x509 -noout -enddate -in "$cert_path" 2>/dev/null | cut -d= -f2)" || return 0
    expiry_epoch="$(date -d "$expiry_date" +%s 2>/dev/null)" || return 0
    now_epoch="$(date +%s)"
    days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
    if [ "$days_left" -le 0 ]; then
        echo "EXPIRED: ${cert_name} expired on ${expiry_date}"
    elif [ "$days_left" -lt 30 ]; then
        echo "WARNING: ${cert_name} expires in ${days_left} days (${expiry_date})"
    else
        echo "Valid until: $expiry_date (${days_left} days)"
    fi
}

echo "[*] Generating Sovereign Root CA..."
if [ -f sovereign_root.crt ]; then
    echo "Root CA already exists — skipping."
    check_cert_expiry "sovereign_root.crt" "Root CA"
else
    openssl genrsa -out sovereign_root.key 4096
    openssl req -x509 -new -nodes \
        -key sovereign_root.key \
        -sha256 -days 3650 \
        -out sovereign_root.crt \
        -subj "/C=PH/ST=Negros Oriental/L=Dumaguete City/O=ORP Sovereign/CN=ORP Root CA"
    echo "Root CA generated (valid 10 years)."
fi

echo "[*] Generating ORP Server Certificate..."
if [ -f orp_server.crt ]; then
    echo "Server certificate already exists — skipping."
    check_cert_expiry "orp_server.crt" "Server certificate"
else
    openssl genrsa -out orp_server.key 2048
    openssl req -new -key orp_server.key -out orp_server.csr \
        -subj "/C=PH/ST=Negros Oriental/L=Dumaguete City/O=ORP Engine/CN=localhost"
    openssl x509 -req -in orp_server.csr \
        -CA sovereign_root.crt -CAkey sovereign_root.key -CAcreateserial \
        -out orp_server.crt -days 365 -sha256
    rm -f orp_server.csr
    echo "Server certificate generated (valid 1 year)."
fi

echo "[*] Generating Operator Client Certificate..."
if [ -f operator_01.crt ]; then
    echo "Operator certificate already exists — skipping."
    check_cert_expiry "operator_01.crt" "Operator certificate"
else
    read -r -p "Operator Common Name (CN) [ORP-Operator-01]: " OP_CN
    OP_CN="${OP_CN:-ORP-Operator-01}"
    openssl genrsa -out operator_01.key 2048
    openssl req -new -key operator_01.key -out operator_01.csr \
        -subj "/C=PH/ST=Negros Oriental/O=ORP Operators/CN=${OP_CN}"
    openssl x509 -req -in operator_01.csr \
        -CA sovereign_root.crt -CAkey sovereign_root.key -CAcreateserial \
        -out operator_01.crt -days 365 -sha256
    rm -f operator_01.csr
    echo "Operator certificate: $OP_CN (valid 1 year)."
fi

echo "[*] Generating PKCS#12 bundle..."
if [ -f operator_01.p12 ]; then
    echo "PKCS#12 bundle already exists — skipping."
else
    read -s -r -p "Export password (blank = no password): " EXPORTPASS
    echo
    openssl pkcs12 -export \
        -out operator_01.p12 \
        -inkey operator_01.key \
        -in operator_01.crt \
        -certfile sovereign_root.crt \
        -passout "pass:${EXPORTPASS}"
    EXPORTPASS=""
    unset EXPORTPASS
    echo "PKCS#12 bundle: operator_01.p12"
fi

echo "[*] Setting file permissions..."
chmod 600 "$PKI_DIR"/*.key "$PKI_DIR"/*.p12 2>/dev/null || true
chmod 644 "$PKI_DIR"/*.crt 2>/dev/null || true

echo "[*] Verifying certificate chains..."
openssl verify -CAfile sovereign_root.crt operator_01.crt >/dev/null 2>&1 \
    && echo "operator_01.crt → sovereign_root.crt: VALID" \
    || echo "Chain verification FAILED for operator_01.crt"

openssl verify -CAfile sovereign_root.crt orp_server.crt >/dev/null 2>&1 \
    && echo "orp_server.crt → sovereign_root.crt: VALID" \
    || echo "Chain verification FAILED for orp_server.crt"

echo "[*] PKI setup complete."
echo "Root CA (public):     $PKI_DIR/sovereign_root.crt"
echo "Root CA (private):    $PKI_DIR/sovereign_root.key  ← KEEP SAFE"
echo "Server certificate:   $PKI_DIR/orp_server.crt"
echo "Operator certificate: $PKI_DIR/operator_01.crt"
echo "Browser bundle:       $PKI_DIR/operator_01.p12  ← IMPORT THIS"
