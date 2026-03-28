#!/bin/bash
# Generate a self-signed certificate for the nginx reverse proxy.
# Usage: ./nginx/generate-self-signed.sh [domain]
# Default domain is "localhost".

DOMAIN=${1:-localhost}

# ensure we're working in script directory (nginx/)
cd "$(dirname "$0")" || exit 1

# clean up any accidentally nested nginx/ssl from earlier versions
if [ -d nginx/ssl ]; then
    echo "removing old nested directory nginx/ssl"
    rm -rf nginx/ssl
fi

# create output directory directly beneath script
mkdir -p ssl

# Check for openssl
if ! command -v openssl > /dev/null 2>&1; then
    echo "ERROR: openssl is not installed or not in PATH."
    echo ""
    echo "Install it for your platform:"
    echo "  macOS:          brew install openssl"
    echo "  Debian/Ubuntu:  sudo apt-get install -y openssl"
    echo "  RHEL/CentOS:    sudo yum install -y openssl"
    echo "  Alpine:         sudo apk add openssl"
    echo "  Windows:        https://slproweb.com/products/Win32OpenSSL.html"
    echo ""
    exit 1
fi

# -addext (for SubjectAltName) requires OpenSSL >= 1.1.1.
# Older distros (e.g. CentOS 7 ships with 1.0.2) fall back to a config file.
if openssl req -help 2>&1 | grep -q -- '-addext'; then
    openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout ssl/server.key \
        -out ssl/server.crt \
        -days 365 \
        -subj "/CN=$DOMAIN" \
        -addext "subjectAltName=DNS:$DOMAIN"
else
    TMPCONF=$(mktemp)
    cat > "$TMPCONF" <<SSLEOF
[req]
distinguished_name = req_distinguished_name
x509_extensions    = v3_req
prompt             = no
[req_distinguished_name]
CN = $DOMAIN
[v3_req]
subjectAltName = DNS:$DOMAIN
SSLEOF
    openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout ssl/server.key \
        -out ssl/server.crt \
        -days 365 \
        -config "$TMPCONF"
    rm -f "$TMPCONF"
fi

chmod 600 ssl/server.key

cat <<EOF
Created self-signed cert for $DOMAIN in nginx/ssl/server.crt
and key in nginx/ssl/server.key
You can point your browser at https://$DOMAIN/ (or add /pypowerwall/ for the
pypowerwall console) once the nginx service is running.
EOF
