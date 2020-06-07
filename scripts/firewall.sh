#!/bin/bash
set -eu

# Installing ufw ------------------------------------------------------------------------------------- #
apt-get -qq update && apt-get -qq install -y ufw
sed -i 's/IPV6=yes/IPV6=no/g' /etc/default/ufw
# ---------------------------------------------------------------------------------------------------- #


# Setting up default rules --------------------------------------------------------------------------- #
PRIVATE_IP=$(hostname -I | xargs -n1 | grep '^10\.0\.0\.')
PUBLIC_IP=$(hostname -I | awk '{print $1}')

ufw default deny incoming
ufw allow proto tcp to $PUBLIC_IP port 22 from any comment "SSH"
ufw allow to $PRIVATE_IP from 10.0.0.0/24 comment "INT-NET"
ufw route allow to $PRIVATE_IP

echo "y" | ufw enable
# ---------------------------------------------------------------------------------------------------- #
