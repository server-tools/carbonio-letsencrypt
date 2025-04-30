#!/bin/bash

# Check if domain name argument is provided
if [ -z "$1" ]; then
    echo "Error: Please provide a domain name as an argument"
    echo "Usage: $0 <domain_name>"
    exit 1
fi

# Set domain name variable
DOMAIN_NAME="$1"

# Execute commands as zextras user
su - zextras -c "
# Download ISRG Root X1 certificate
wget https://letsencrypt.org/certs/isrgrootx1.pem -O /opt/zextras/ssl/carbonio/commercial/isrgrootx1.pem

rm /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem
# Create zextras_ca.pem by combining fullchain and isrgrootx1
cat /opt/zextras/common/certbot/etc/letsencrypt/live/${DOMAIN_NAME}/chain.pem /opt/zextras/ssl/carbonio/commercial/isrgrootx1.pem > /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem

# Verify certificate
/opt/zextras/bin/zmcertmgr verifycrt comm /opt/zextras/common/certbot/etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem /opt/zextras/common/certbot/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem


# Copy private key
rm /opt/zextras/ssl/carbonio/commercial/commercial.key
cp /opt/zextras/common/certbot/etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem /opt/zextras/ssl/carbonio/commercial/commercial.key

# Deploy certificate
/opt/zextras/bin/zmcertmgr deploycrt comm /opt/zextras/common/certbot/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem /opt/zextras/ssl/carbonio/commercial/zextras_ca.pem

# Restart Zimbra services
#zmcontrol restart
"
