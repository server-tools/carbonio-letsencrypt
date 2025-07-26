#!/bin/bash

# Check if both arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <email> <domain>"
    exit 1
fi

# Assign command-line arguments to variables
EMAIL="$1"
DOMAIN="$2"

# Run certbot command as zextras user
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
