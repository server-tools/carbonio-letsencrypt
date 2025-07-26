#!/bin/bash

# Configuration
DOMAIN="certdomain.com"
EMAIL="info@yourdomain.com"
DAYS_THRESHOLD=7  # Number of days before expiration to trigger renewal


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
EXPIRY_DATE=$(openssl s_client -servername "$DOMAIN" -connect "$DOMAIN":443 < /dev/null 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
CURRENT_EPOCH=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))

# Check if date parsing was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to parse certificate expiration date"
    exit 1
fi

echo "Certificate for $DOMAIN expires in $DAYS_LEFT days."

# Check if certificate is expiring soon
if [ "$DAYS_LEFT" -le "$DAYS_THRESHOLD" ]; then
    echo "Certificate is expiring soon. Renewing..."

    # Generate SSL
    echo "Generating new SSL certificate..."
    wget https://raw.githubusercontent.com/server-tools/carbonio-letsencrypt/refs/heads/main/run_certbot.sh -O run_certbot.sh
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download run_certbot.sh"
        exit 1
    fi

    chmod +x run_certbot.sh
    ./run_certbot.sh "$EMAIL" "$DOMAIN"
    if [ $? -ne 0 ]; then
        echo "Error: run_certbot.sh failed"
        exit 1
    fi

    # Deploy SSL
    echo "Deploying new SSL certificate..."
    wget https://raw.githubusercontent.com/server-tools/carbonio-letsencrypt/refs/heads/main/deploy_cert.sh -O deploy_cert.sh
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download deploy_cert.sh"
        exit 1
    fi

    chmod +x deploy_cert.sh
    ./deploy_cert.sh "$DOMAIN"
    if [ $? -ne 0 ]; then
        echo "Error: deploy_cert.sh failed"
        exit 1
    fi

    # Restart Zextras Proxy
    echo "Restarting Zextras Proxy..."
    su - zextras -c "/opt/zextras/libexec/zmproxyconfgen"
    su - zextras -c "/opt/zextras/bin/zmproxyctl reload"

    # Restart Zextras services as zextras user
    echo "Restarting Zextras services..."
    su - zextras -c "zmcontrol restart"
    if [ $? -ne 0 ]; then
        echo "Error: zmcontrol restart failed"
        exit 1
    fi

    echo "SSL certificate renewed, deployed, and Zextras services restarted successfully."
else
    echo "Certificate is still valid. No action needed."
fi
