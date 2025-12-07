#!/bin/bash

#================================================================
# Carbonio CE Renewal Script (Restored Proxy Logic)
# Usage: ./carbonio_renew.sh <domain> <email>
#================================================================

# --- Argument Parsing & Configuration ---

if [ "$#" -ne 2 ]; then
    echo "Error: Missing parameters."
    echo "Usage: $0 <domain> <email>"
    exit 1
fi

DOMAIN="$1"
EMAIL="$2"
DAYS_THRESHOLD=7

# Path where Carbonio's specific Certbot saves files
LE_BASE_DIR="/opt/zextras/common/certbot/etc/letsencrypt/live"
LE_RENEWAL_DIR="/opt/zextras/common/certbot/etc/letsencrypt/renewal"
# ---------------------

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root."
  exit 1
fi

# Function to check command existence
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

for cmd in openssl wget; do
    if ! command_exists $cmd; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
done

echo "--- Starting Certificate Check for $DOMAIN ---"

#================================================
## 1. Check Currently DEPLOYED Certificate
#================================================
CERT_PATH="/opt/zextras/ssl/carbonio/commercial/commercial.crt"
CURRENT_EPOCH=$(date +%s)

if [ -f "$CERT_PATH" ]; then
    echo "Checking local deployed certificate..."
    EXPIRY_DATE=$(openssl x509 -in "$CERT_PATH" -noout -enddate | cut -d= -f2)
else
    echo "Local deployed cert not found. Checking via network..."
    EXPIRY_DATE=$(openssl s_client -servername "$DOMAIN" -connect "$DOMAIN":443 < /dev/null 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
fi

if [ -z "$EXPIRY_DATE" ]; then
    echo "Error: Could not determine deployed expiration date."
    exit 1
fi

EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
DAYS_LEFT=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))

echo "Deployed certificate expires in $DAYS_LEFT days."

if [ "$DAYS_LEFT" -gt "$DAYS_THRESHOLD" ]; then
    echo "Certificate is still valid. No action taken."
    exit 0
fi

echo "Threshold reached. Investigating..."

#================================================
## 2. Check Local Storage & Cleanup
#================================================
RUN_CERTBOT=true
TARGET_CERT_DIR="${LE_BASE_DIR}/${DOMAIN}"

# Check if a VALID certificate already exists in the standard location
if [ -d "$TARGET_CERT_DIR" ] && [ -f "$TARGET_CERT_DIR/cert.pem" ]; then
    echo "Checking stored certificate at $TARGET_CERT_DIR..."
    
    STORED_EXPIRY_DATE=$(openssl x509 -in "$TARGET_CERT_DIR/cert.pem" -noout -enddate | cut -d= -f2)
    STORED_EPOCH=$(date -d "$STORED_EXPIRY_DATE" +%s)
    STORED_DAYS_LEFT=$(( (STORED_EPOCH - CURRENT_EPOCH) / 86400 ))

    if [ "$STORED_DAYS_LEFT" -gt 30 ]; then
        echo "Found a FRESH existing certificate in storage ($STORED_DAYS_LEFT days left)."
        echo "Skipping Certbot renewal to avoid rate limits."
        RUN_CERTBOT=false
    else
        echo "Stored certificate is also old ($STORED_DAYS_LEFT days left). Proceeding with renewal."
    fi
fi

#================================================
## 3. Run Certbot (Exact User Command)
#================================================

if [ "$RUN_CERTBOT" = true ]; then

    # --- ZOMBIE CLEANUP ---
    if [ -d "$TARGET_CERT_DIR" ]; then
        echo "Backing up existing directory to allow fresh issuance..."
        mv "$TARGET_CERT_DIR" "${TARGET_CERT_DIR}_broken_$(date +%s)"
    fi

    if [ -f "${LE_RENEWAL_DIR}/${DOMAIN}.conf" ]; then
        echo "Backing up old renewal config..."
        mv "${LE_RENEWAL_DIR}/${DOMAIN}.conf" "${LE_RENEWAL_DIR}/${DOMAIN}.conf.bak_$(date +%s)"
    fi
    # ----------------------

    echo "Running Certbot..."
    su - zextras -c "
    /opt/zextras/libexec/certbot certonly \
        --preferred-chain 'ISRG Root X1' \
        --agree-tos \
        --email $EMAIL \
        -n \
        --keep \
        --webroot \
        -w /opt/zextras \
        --cert-name $DOMAIN \
        -d $DOMAIN
    "

    if [ $? -ne 0 ]; then
        echo "Error: Certbot renewal failed."
        exit 1
    fi
    echo "Certbot renewal successful."
fi

#================================================
## 4. Prepare Files (Root Logic)
#================================================
echo "Preparing SSL files..."

# Force usage of the standard certbot live directory
CERT_SOURCE_DIR="${LE_BASE_DIR}/${DOMAIN}"

echo "Using certificate source: $CERT_SOURCE_DIR"

if [ ! -f "$CERT_SOURCE_DIR/privkey.pem" ] || [ ! -f "$CERT_SOURCE_DIR/fullchain.pem" ]; then
    echo "CRITICAL ERROR: Certificate files not found in $CERT_SOURCE_DIR"
    echo "Please check /var/log/carbonio/letsencrypt/letsencrypt.log"
    exit 1
fi

COMMERCIAL_DIR="/opt/zextras/ssl/carbonio/commercial"

# Download Root CA
echo "Downloading ISRG Root X1..."
wget -q https://letsencrypt.org/certs/isrgrootx1.pem -O "$COMMERCIAL_DIR/isrgrootx1.pem"

# Create CA chain
cat "$CERT_SOURCE_DIR/chain.pem" "$COMMERCIAL_DIR/isrgrootx1.pem" > "$COMMERCIAL_DIR/zextras_ca.pem"

# Backup existing key
if [ -f "$COMMERCIAL_DIR/commercial.key" ]; then
    cp "$COMMERCIAL_DIR/commercial.key" "$COMMERCIAL_DIR/commercial.key.bak.$(date +%F)"
fi

# Copy Private Key (dereference symlinks with -L)
cp -L "$CERT_SOURCE_DIR/privkey.pem" "$COMMERCIAL_DIR/commercial.key"

# Fix Permissions
echo "Fixing permissions..."
chown zextras:zextras "$COMMERCIAL_DIR/commercial.key"
chown zextras:zextras "$COMMERCIAL_DIR/zextras_ca.pem"
chown zextras:zextras "$COMMERCIAL_DIR/isrgrootx1.pem"
chmod 640 "$COMMERCIAL_DIR/commercial.key"

# Prepare fullchain for verification
cp -L "$CERT_SOURCE_DIR/fullchain.pem" "$COMMERCIAL_DIR/fullchain_temp.pem"
chown zextras:zextras "$COMMERCIAL_DIR/fullchain_temp.pem"

#================================================
## 5. Verify and Deploy (As zextras)
#================================================
echo "Switching to zextras user for deployment..."

su - zextras -c "
echo 'Verifying certificate...'
/opt/zextras/bin/zmcertmgr verifycrt comm /opt/zextras/ssl/carbonio/commercial/commercial.key /opt/zextras/ssl/carbonio/commercial/fullchain_temp.pem /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem

if [ \$? -ne 0 ]; then
    echo 'Error: zmcertmgr verification failed.'
    exit 1
fi

echo 'Deploying certificate...'
/opt/zextras/bin/zmcertmgr deploycrt comm /opt/zextras/ssl/carbonio/commercial/fullchain_temp.pem /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem

if [ \$? -ne 0 ]; then
    echo 'Error: zmcertmgr deployment failed.'
    exit 1
fi
"

if [ $? -ne 0 ]; then
    echo "Deployment failed. Aborting restart."
    exit 1
fi

rm -f "$COMMERCIAL_DIR/fullchain_temp.pem"

#================================================
## 6. Restart Services
#================================================
echo "--- Restarting Services ---"

# RESTORED: Restart Zextras Proxy Configuration
echo "Regenerating Proxy Config and Reloading..."
su - zextras -c "/opt/zextras/libexec/zmproxyconfgen"
su - zextras -c "/opt/zextras/bin/zmproxyctl reload"

if systemctl list-unit-files | grep -q carbonio-directory-server.target; then
    echo "Detected newer Carbonio version (Systemd)."
    echo "1/4 Restarting Directory Server..."
    systemctl restart carbonio-directory-server.target
    echo "2/4 Restarting MTA..."
    systemctl restart carbonio-mta.target
    echo "3/4 Restarting AppServer..."
    systemctl restart carbonio-appserver.target
    echo "4/4 Restarting Proxy..."
    systemctl restart carbonio-proxy.target
else
    echo "Detected older Carbonio version (Legacy)."
    echo "Running zmcontrol restart..."
    su - zextras -c "zmcontrol restart"
fi

echo "=========================================="
echo "SUCCESS: Certificate processed and deployed."
echo "=========================================="
exit 0
