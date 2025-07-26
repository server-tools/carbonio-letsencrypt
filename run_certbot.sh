#!/bin/bash

# Check if both arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <email> <domain>"
    exit 1
fi

# Assign command-line arguments to variables
EMAIL="$1"
DOMAIN="$2"


su - zextras -c "carbonio prov gacf zimbraReverseProxyMailMode"
su - zextras -c "carbonio prov mcf zimbraReverseProxyMailMode redirect"
su - zextras -c "source /opt/zextras/bin/zmshutil; zmsetvars; carbonio prov ms \$(zmhostname) zimbraReverseProxyMailMode ''"
su - zextras -c "/opt/zextras/libexec/zmproxyconfgen"
su - zextras -c "zmproxyctl restart"

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
