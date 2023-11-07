#!/bin/bash

# parameters needed to be set site-specific.
SERVER_NAME="v-u-checkmk-p"
SITE_NAME="cmk" # More infos: https://docs.checkmk.com/latest/de/intro_setup.html#create_site
API_URL="http://$SERVER_NAME/$SITE_NAME/check_mk/api/1.0"
USERNAME="automation"
PASSWORD="<PASSWORD_OF_THE_AUTOMATION_USER>"
# End specific parameters
##### below should not be changed unless you are absolutely sure in what you are doing !


# check if running as root
if [ "$EUID" -ne 0 ]; then
  printf "$(tput setaf 1)%s$(tput sgr0)\n" "Please run as root!"
  exit
fi


# Function to display a message and a spinner while a background command is running
spinner() {
  # Arguments
  # 1. Message
  local message=$1
  # 2. additional delay in secounds
  local additionaldelay=$2
  additionaldelay=$(($additionaldelay*10))

  local pid=$!
  local delay=0.1
  local spinChars="/-\|"

  while ps -p $pid > /dev/null; do
    local spinChar=${spinChars:0:1}
    spinChars=${spinChars:1}${spinChar}
        printf "$(tput setaf 6)%s : %s$(tput sgr0)\r" "$message" "$spinChar"
    sleep $delay
  done

  for ((i = 1 ; i <= $additionaldelay; i++ )); do
    local spinChar=${spinChars:0:1}
    spinChars=${spinChars:1}${spinChar}
    printf "$(tput setaf 6)%s : %s$(tput sgr0)\r" "$message" "$spinChar"
    sleep $delay
  done

  # Wait for the background process to finish
  wait $pid

  # Check the exit status of curl
  if [ $? -ne 0 ]; then
    error_message=$(cat error.log)
    printf "\n$(tput setaf 1)%s$(tput sgr0)\n" "$error_message"
    rm error.log
    exit 1
  fi

  printf "$(tput setaf 2)%s : OK$(tput sgr0)\n" "$message"
}


# Check if there are any pending changes on the checkmk server
temp_file=$(mktemp)
# Get Content-Length from "pending changes" object via REST-API
curl -s -S -I -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET "$API_URL/domain-types/activation_run/collections/pending_changes" 1> "$temp_file" 2> error.log &
spinner "Get Content-Length from 'pending changes' object via REST-API" 0
# Extract the ETag value from the file content
result=$(grep -iE '^Content-Length: ' "$temp_file" | awk '{print $2}' | tr -d '"' | tr -cd '[:alnum:]')
# Delete the temporary file
rm "$temp_file"
if [ "$result" -gt 350 ]; then
  printf "$(tput setaf 1)%s$(tput sgr0)\n" "Please revert or accept pending change(s) on the checkmk server before running the script! Uninstall aborted!"
  exit
fi


# Check if rpm or dpkg package manager is installed
if command -v dpkg &> /dev/null; then
  # Download check_mk_agent.deb file from checkmk-server via REST-API
  curl -s -S -H "Accept: application/octet-stream" -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET -H "Content-Type: application/json" -o "/tmp/check_mk_agent.deb" "$API_URL/domain-types/agent/actions/download/invoke?os_type=linux_deb" 1> /dev/null 2> error.log &
  spinner "Download check_mk_agent.deb file from checkmk-server via REST-API" 0

  # Uninstall check_mk_agent
  apt remove -y check-mk-agent 1> /dev/null 2> error.log &
  rm -r /usr/lib/check_mk_agent
  rm -r /var/lib/check_mk_agent
  rm -r /var/lib/cmk-agent
  rm -r /etc/check_mk
  spinner "Uninstall check_mk_agent" 0

elif command -v rpm &> /dev/null; then
  # Download check_mk_agent.rpm file from checkmk-server via REST-API
  curl -s -S -H "Accept: application/octet-stream" -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET -H "Content-Type: application/json" -o "/tmp/check_mk_agent.rpm" "$API_URL/domain-types/agent/actions/download/invoke?os_type=linux_rpm" 1> /dev/null 2> error.log &
  spinner "Download check_mk_agent.rpm file from checkmk-server via REST-API" 0

  # Install check_mk_agent
  dnf remove -y check_mk_agent 1> /dev/null 2> error.log &
  rm -r /usr/lib/check_mk_agent
  rm -r /var/lib/check_mk_agent
  rm -r /var/lib/cmk-agent
  rm -r /etc/check_mk
  spinner "Uninstall check_mk_agent" 0

else
  printf "$(tput setaf 1)%s$(tput sgr0)\n" "Neither dpkg nor rpm is installed! Uninstall aborted!"
  exit
fi


# Delete Host via REST-API
curl -s -S -H "Accept: application/json" -H "Authorization: Bearer $USERNAME $PASSWORD" -X DELETE -H "Content-Type: application/json" -d "$BODY" "$API_URL/objects/host_config/$(hostname | tr '[:upper:]' '[:lower:]')" 1> /dev/null 2> error.log &
spinner "Delete Host via REST-API" 0


# Get ETag from "pending changes" object via REST-API
temp_file=$(mktemp)
curl -s -S -I -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET "$API_URL/domain-types/activation_run/collections/pending_changes" 1> "$temp_file" 2> error.log &
spinner "Get ETag from 'pending changes' object via REST-API" 0
# Extract the ETag value from the file content
etag=$(grep -iE '^ETag: ' "$temp_file" | awk '{print $2}' | tr -d '"' | tr -cd '[:alnum:]')
rm "$temp_file"


# Start activating the pending changes via REST-API
BODY="{\"force_foreign_changes\": \"false\", \"redirect\": \"false\", \"sites\": [\"$SITE_NAME\"]}"
curl -s -S -H "Accept: application/json" -H "Authorization: Bearer $USERNAME $PASSWORD" -H "If-Match: \"$etag\"" -X POST -H "Content-Type: application/json" -d "$BODY" "$API_URL/domain-types/activation_run/actions/activate-changes/invoke" 1> /dev/null 2> error.log &
spinner "Start activating the pending changes via REST-API" 0


# Script deletes itself
echo "Script deletes itself"
currentscript=$0
shred -u ${currentscript}