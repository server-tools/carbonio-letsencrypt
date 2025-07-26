#!/bin/bash

# Check if domain name argument is provided
if [ -z "$1" ]; then
    echo "Error: Please provide a domain name as an argument"
    echo "Usage: $0 <domain_name>"
    exit 1
fi

# Set domain name variable

DOMAIN_NAME="$1"
BASE_PATH="/opt/zextras/common/certbot/etc/letsencrypt/live"
TARGET_DIR="${BASE_PATH}/${DOMAIN_NAME}"
EXACT_DIR="${BASE_PATH}/${DOMAIN_NAME}"
CERT_DIR_PATTERN="${BASE_PATH}/${DOMAIN_NAME}*"

# Check for numbered certificate directories first
LATEST_DIR=$(ls -d ${CERT_DIR_PATTERN} 2>/dev/null | sort -V | tail -n 1)
if [ -z "$LATEST_DIR" ]; then
  # If no numbered directories exist, fall back to the exact directory
  if [ -d "$EXACT_DIR" ]; then
    LATEST_DIR="$EXACT_DIR"
  else
    echo "Error: No certificate directories found for intranet-${DOMAIN_NAME}"
    exit 1
  fi
fi


# Execute commands as zextras user
su - zextras -c "
# Download ISRG Root X1 certificate
wget https://letsencrypt.org/certs/isrgrootx1.pem -O /opt/zextras/ssl/carbonio/commercial/isrgrootx1.pem

rm /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem
# Create zextras_ca.pem by combining fullchain and isrgrootx1
cat ${LATEST_DIR}/chain.pem /opt/zextras/ssl/carbonio/commercial/isrgrootx1.pem > /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem

# Verify certificate
/opt/zextras/bin/zmcertmgr verifycrt comm ${LATEST_DIR}/privkey.pem ${LATEST_DIR}/fullchain.pem /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem


# Copy private key
rm /opt/zextras/ssl/carbonio/commercial/commercial.key
cp ${LATEST_DIR}/privkey.pem /opt/zextras/ssl/carbonio/commercial/commercial.key

# Deploy certificate
/opt/zextras/bin/zmcertmgr deploycrt comm ${LATEST_DIR}/fullchain.pem /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem

# Restart Zimbra services
#zmcontrol restart
"
