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
  # Uninstall Checkmk Agent
  apt remove -y check-mk-agent

elif command -v rpm &> /dev/null; then
  # Uninstall Checkmk Agent
  dnf remove -y check-mk-agent

else
  echo "Neither dpkg nor rpm is installed"

fi


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