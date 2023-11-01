#!/bin/bash

# parameters needed to be set site-specific.
SERVER_NAME="v-u-checkmk-p"
SITE_NAME="cmk"
API_URL="http://$SERVER_NAME/$SITE_NAME/check_mk/api/1.0"
USERNAME="automation" 
PASSWORD="<PASSWORD_OF_THE_AUTOMATION_USER>"
# End specific parameters
##### below should not be changed unless you are absolutely sure in what you are doing !


# check if running as root in a bash script
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi


# Check if rpm or dpkg package manager is installed
if command -v dpkg &> /dev/null; then
  # Download check_mk_agent.deb file from checkmk-server via REST-API
  curl -H "Accept: application/octet-stream" -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET -H "Content-Type: application/json" -o "/tmp/check_mk_agent.deb" "$API_URL/domain-types/agent/actions/download/invoke?os_type=linux_deb"

  sleep 10

  # Install check_mk_agent
  dpkg -i /tmp/check_mk_agent.deb

  # Download mk_apt plugin from checkmk server
  wget http://$SERVER_NAME/$SITE_NAME/check_mk/agents/plugins/mk_apt --no-check-certificate
  mv -f mk_apt /usr/lib/check_mk_agent/plugins
  chmod +x /usr/lib/check_mk_agent/plugins/mk_apt

elif command -v rpm &> /dev/null; then
  # Download check_mk_agent.rpm file from checkmk-server via REST-API
  curl -H "Accept: application/octet-stream" -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET -H "Content-Type: application/json" -o "/tmp/check_mk_agent.rpm" "$API_URL/domain-types/agent/actions/download/invoke?os_type=linux_rpm"

  sleep 10

  # Install check_mk_agent
  rpm -i /tmp/check_mk_agent.rpm

else
  echo "Neither dpkg nor rpm is installed"
fi


sleep 10


# Get the host IP address
HostIP=$(ip -4 route get 8.8.8.8 | awk 'NR==1 {print $7}')


# Register the Agent
cmk-agent-ctl register --hostname $(hostname | tr '[:upper:]' '[:lower:]') --server $SERVER_NAME --site $SITE_NAME --user $USERNAME --password $PASSWORD --trust-cert


# Script deletes itself
currentscript=$0
shred -u ${currentscript}