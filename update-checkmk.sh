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


# Check if rpm or dpkg package manager is installed
if command -v dpkg &> /dev/null; then
  # Download check_mk_agent.deb file from checkmk-server via REST-API
  curl -s -S -H "Accept: application/octet-stream" -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET -H "Content-Type: application/json" -o "/tmp/check_mk_agent.deb" "$API_URL/domain-types/agent/actions/download/invoke?os_type=linux_deb" 1> /dev/null 2> error.log &
  spinner "Download check_mk_agent.deb file from checkmk-server via REST-API" 0

  # Install check_mk_agent
  dpkg -i /tmp/check_mk_agent.deb 1> /dev/null 2> error.log &
  spinner "Install check_mk_agent" 0

  # Download mk_apt plugin from checkmk server
  wget http://$SERVER_NAME/$SITE_NAME/check_mk/agents/plugins/mk_apt --no-check-certificate 1> /dev/null 2> error.log &
  spinner "Download mk_apt plugin from checkmk server" 0
  mv -f mk_apt /usr/lib/check_mk_agent/plugins
  chmod +x /usr/lib/check_mk_agent/plugins/mk_apt

elif command -v rpm &> /dev/null; then
  # Download check_mk_agent.rpm file from checkmk-server via REST-API
  curl -s -S -H "Accept: application/octet-stream" -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET -H "Content-Type: application/json" -o "/tmp/check_mk_agent.rpm" "$API_URL/domain-types/agent/actions/download/invoke?os_type=linux_rpm" 1> /dev/null 2> error.log &
  spinner "Download check_mk_agent.rpm file from checkmk-server via REST-API" 0

  # Install check_mk_agent
  rpm -i /tmp/check_mk_agent.rpm 1> /dev/null 2> error.log &
  spinner "Install check_mk_agent" 0

else
  printf "$(tput setaf 1)%s$(tput sgr0)\n" "Neither dpkg nor rpm is installed! Update aborted!"
  exit
fi


# Register the Agent
cmk-agent-ctl register --hostname $(hostname | tr '[:upper:]' '[:lower:]') --server $SERVER_NAME --site $SITE_NAME --user $USERNAME --password $PASSWORD --trust-cert 1> /dev/null 2> error.log &
spinner "Register the Agent" 0


# Script deletes itself
echo "Script deletes itself"
currentscript=$0
shred -u ${currentscript}