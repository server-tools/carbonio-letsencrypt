#!/bin/bash

#================================================================
# Combined Carbonio/Zextras Let's Encrypt Renewal & Deploy Script
#
# This script combines the logic from cert_cron.sh, 
# run_certbot.sh, and deploy_cert.sh into a single file.
#
# It checks certificate expiration and, if needed:
# 1. Runs Certbot to renew the certificate.
# 2. Deploys the new certificate using zmcertmgr.
# 3. Restarts all necessary services.
#================================================================

# --- Configuration ---
DOMAIN="certdomain.com"
EMAIL="info@yourdomain.com"
DAYS_THRESHOLD=7  # Days before expiration to trigger renewal
# ---------------------


# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if required tools are installed
if ! command_exists openssl; then
    echo "Error: openssl is not installed. Please install it."
    exit 1
fi

if ! command_exists wget; then
    echo "Error: wget is not installed. Please install it."
    exit 1
fi


# Get the certificate's expiration date
echo "Checking certificate expiration for $DOMAIN..."
EXPIRY_DATE=$(openssl s_client -servername "$DOMAIN" -connect "$DOMAIN":443 < /dev/null 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)

# Check if date parsing was successful
if [ $? -ne 0 ] || [ -z "$EXPIRY_EPOCH" ]; then
    echo "Error: Failed to get or parse certificate expiration date for $DOMAIN."
    echo "Please check network access and if the domain is resolving correctly."
    exit 1
fi

CURRENT_EPOCH=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))

echo "Certificate for $DOMAIN expires in $DAYS_LEFT days."

# Check if certificate is expiring soon
if [ "$DAYS_LEFT" -le "$DAYS_THRESHOLD" ]; then
    echo "Certificate is expiring in $DAYS_LEFT days (Threshold: $DAYS_THRESHOLD). Starting renewal process..."

    #================================================
    ## 1. Run Certbot to Renew Certificate
    ## (Logic from run_certbot.sh)
    #================================================
    echo "Configuring proxy for Certbot..."
    su - zextras -c "carbonio prov gacf zimbraReverseProxyMailMode"
    su - zextras -c "carbonio prov mcf zimbraReverseProxyMailMode redirect"
    su - zextras -c "source /opt/zextras/bin/zmshutil; zmsetvars; carbonio prov ms \$(zmhostname) zimbraReverseProxyMailMode ''"
    su - zextras -c "/opt/zextras/libexec/zmproxyconfgen"
    su - zextras -c "zmproxyctl restart"

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

    #================================================
    ## 2. Deploy the New Certificate
    ## (Logic from deploy_cert.sh)
    #================================================
    echo "Deploying new SSL certificate..."

    # Set variables for deployment
    BASE_PATH="/opt/zextras/common/certbot/etc/letsencrypt/live"
    EXACT_DIR="${BASE_PATH}/${DOMAIN}"
    CERT_DIR_PATTERN="${BASE_PATH}/${DOMAIN}*"

    # Find the latest certificate directory (handles certbot renewals, e.g., domain.com-0001)
    LATEST_DIR=$(ls -d ${CERT_DIR_PATTERN} 2>/dev/null | sort -V | tail -n 1)
    if [ -z "$LATEST_DIR" ]; then
      # If no numbered directories exist, fall back to the exact directory
      if [ -d "$EXACT_DIR" ]; then
        LATEST_DIR="$EXACT_DIR"
      else
        echo "Error: No certificate directories found for ${DOMAIN} in ${BASE_PATH}"
        exit 1
      fi
    fi
    
    echo "Found certificate directory: $LATEST_DIR"

    # Execute deployment commands as zextras user
    su - zextras -c "
    # Download ISRG Root X1 certificate
    echo 'Downloading ISRG Root X1 certificate...'
    wget https://letsencrypt.org/certs/isrgrootx1.pem -O /opt/zextras/ssl/carbonio/commercial/isrgrootx1.pem
    if [ $? -ne 0 ]; then echo 'Error: Failed to download isrgrootx1.pem'; exit 1; fi

    rm -f /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem
    
    # Create zextras_ca.pem by combining chain and isrgrootx1
    echo 'Creating new zextras_ca.pem...'
    cat ${LATEST_DIR}/chain.pem /opt/zextras/ssl/carbonio/commercial/isrgrootx1.pem > /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem

    # Verify certificate
    echo 'Verifying certificate with zmcertmgr...'
    /opt/zextras/bin/zmcertmgr verifycrt comm ${LATEST_DIR}/privkey.pem ${LATEST_DIR}/fullchain.pem /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem
    if [ $? -ne 0 ]; then echo 'Error: Certificate verification failed'; exit 1; fi


    # Copy private key
    echo 'Copying new private key...'
    rm -f /opt/zextras/ssl/carbonio/commercial/commercial.key
    cp ${LATEST_DIR}/privkey.pem /opt/zextras/ssl/carbonio/commercial/commercial.key

    # Deploy certificate
    echo 'Deploying certificate with zmcertmgr...'
    /opt/zextras/bin/zmcertmgr deploycrt comm ${LATEST_DIR}/fullchain.pem /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem
    if [ $? -ne 0 ]; then echo 'Error: Certificate deployment failed'; exit 1; fi
    "

    # Check if the su - zextras block failed
    if [ $? -ne 0 ]; then
        echo "Error: Deployment block failed."
        exit 1
    fi
    echo "Certificate deployment successful."

    #================================================
    ## 3. Restart Services
    ## (Logic from cert_cron.sh)
    #================================================
    
    # Restart Zextras Proxy
    echo "Restarting Zextras Proxy..."
    su - zextras -c "/opt/zextras/libexec/zmproxyconfgen"
    su - zextras -c "/opt/zextras/bin/zmproxyctl reload"

    echo "Restarting specific Carbonio services..."
    systemctl restart carbonio-ws-collaboration.service
    systemctl restart carbonio-message-broker.service
    systemctl restart carbonio-message-dispatcher.service

    # Restart Zextras services as zextras user
    echo "Restarting all Zextras services (zmcontrol)..."
    su - zextras -c "zmcontrol restart"
    if [ $? -ne 0 ]; then
        echo "Error: zmcontrol restart failed"
        exit 1
    fi

    echo "SSL certificate renewed, deployed, and Zextras services restarted successfully."

else
    echo "Certificate is still valid. No action needed."
fi

exit 0
