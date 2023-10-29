#!/bin/bash

# check if running as root in a bash script
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Uninstall Checkmk Agent
apt remove check-mk-agent

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

# Delete Host via REST-API
curl -H "Accept: application/json" -H "Authorization: Bearer $USERNAME $PASSWORD" -X DELETE -H "Content-Type: application/json" -d "$BODY" "$API_URL/objects/host_config/$(hostname | tr '[:upper:]' '[:lower:]')"

sleep 3

# Get ETag from "pending changes" object
# Create a temporary file
temp_file=$(mktemp)
# Run the curl command and save the output to the temporary file
curl -s -I -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET "$API_URL/domain-types/activation_run/collections/pending_changes" > "$temp_file"
# Extract the ETag value from the file content
result=$(grep -iE '^ETag: ' "$temp_file" | awk '{print $2}' | tr -d '"' | tr -cd '[:alnum:]')
# Delete the temporary file
rm "$temp_file"

sleep 3

# Activate the changes via REST-API
BODY="{\"force_foreign_changes\": \"false\", \"redirect\": \"false\", \"sites\": [\"$SITE_NAME\"]}"
curl -H "Accept: application/json" -H "Authorization: Bearer $USERNAME $PASSWORD" -H "If-Match: \"$result\"" -X POST -H "Content-Type: application/json" -d "$BODY" "$API_URL/domain-types/activation_run/actions/activate-changes/invoke"

# Script deletes itself
currentscript=$0
shred -u ${currentscript}