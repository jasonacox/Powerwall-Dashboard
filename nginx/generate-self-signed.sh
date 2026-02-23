#!/bin/sh
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

openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout ssl/server.key \
    -out ssl/server.crt \
    -days 365 \
    -subj "/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN"

chmod 600 ssl/server.key

cat <<EOF
Created self-signed cert for $DOMAIN in nginx/ssl/server.crt
and key in nginx/ssl/server.key
You can point your browser at https://$DOMAIN/ (or add /pypowerwall/ for the
pypowerwall console) once the nginx service is running.
EOF
