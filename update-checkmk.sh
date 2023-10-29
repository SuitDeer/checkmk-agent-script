#!/bin/bash

# check if running as root in a bash script
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

SERVER_NAME="v-u-checkmk-p"
SITE_NAME="cmk"
API_URL="http://$SERVER_NAME/$SITE_NAME/check_mk/api/1.0"
USERNAME="automation" 
PASSWORD="<PASSWORD_OF_THE_AUTOMATION_USER>"

# Get the host IP address
HostIP=$(ip -4 route get 8.8.8.8 | awk 'NR==1 {print $7}')

# Download check_mk_agent.deb file from checkmk-server via REST-API
curl -H "Accept: application/octet-stream" -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET -H "Content-Type: application/json" -o "/tmp/check_mk_agent.deb" "$API_URL/domain-types/agent/actions/download/invoke?os_type=linux_deb"

sleep 10

# Install check_mk_agent
dpkg -i /tmp/check_mk_agent.deb
wget http://$SERVER_NAME/$SITE_NAME/check_mk/agents/plugins/mk_apt --no-check-certificate
mv -f mk_apt /usr/lib/check_mk_agent/plugins
chmod +x /usr/lib/check_mk_agent/plugins/mk_apt

sleep 10

# Register the Agent
cmk-agent-ctl register --hostname $(hostname | tr '[:upper:]' '[:lower:]') --server v-u-checkmk-p --site cmk --user automation --password $PASSWORD --trust-cert

# Script deletes itself
currentscript=$0
shred -u ${currentscript}