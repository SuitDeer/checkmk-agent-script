#!/bin/bash

# parameters needed to be set site-specific.
SERVER_NAME="v-u-checkmk-p"
SITE_NAME="cmk"
API_URL="http://$SERVER_NAME/$SITE_NAME/check_mk/api/1.0"
USERNAME="automation"
PASSWORD="<PASSWORD_OF_THE_AUTOMATION_USER>"
# Debug switch, set to yes for verbose info, else the script will be silent.
DEBUG="yes"
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
  if [ $DEBUG == "yes" ]; then
    echo "Download check_mk_agent.deb file from checkmk-server via REST-API"
  fi
  curl -s -S -H "Accept: application/octet-stream" -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET -H "Content-Type: application/json" -o "/tmp/check_mk_agent.deb" "$API_URL/domain-types/agent/actions/download/invoke?os_type=linux_deb"

  sleep 10

  # Install check_mk_agent
  if [ $DEBUG == "yes" ]; then
    echo "Install check_mk_agent"
  fi
  dpkg -i /tmp/check_mk_agent.deb

  # Download mk_apt plugin from checkmk server
  if [ $DEBUG == "yes" ]; then
    echo "Download mk_apt plugin from checkmk server"
  fi
  wget http://$SERVER_NAME/$SITE_NAME/check_mk/agents/plugins/mk_apt --no-check-certificate
  mv -f mk_apt /usr/lib/check_mk_agent/plugins
  chmod +x /usr/lib/check_mk_agent/plugins/mk_apt

elif command -v rpm &> /dev/null; then
  # Download check_mk_agent.rpm file from checkmk-server via REST-API
  if [ $DEBUG == "yes" ]; then
    echo "Download check_mk_agent.rpm file from checkmk-server via REST-API"
  fi
  curl -s -S -H "Accept: application/octet-stream" -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET -H "Content-Type: application/json" -o "/tmp/check_mk_agent.rpm" "$API_URL/domain-types/agent/actions/download/invoke?os_type=linux_rpm"

  sleep 10

  # Install check_mk_agent
  if [ $DEBUG == "yes" ]; then
    echo "Install check_mk_agent"
  fi
  rpm -i /tmp/check_mk_agent.rpm

else
  echo "Neither dpkg nor rpm is installed. Install aborted."
  exit
fi


# Create a checkmk local script to check for pending reboots
if [ $DEBUG == "yes" ]; then
  echo "Create a checkmk local script to check for pending reboots"
fi
sudo cat << EOF > /usr/lib/check_mk_agent/local/reboot
#!/bin/bash

[[ -f /etc/os-release ]] && source /etc/os-release

if [[ -f /var/run/reboot-required ]]; then
  if [[ -f /var/run/reboot-required.pkgs ]]; then
    echo "1 Reboot_needed - A system reboot is needed due to updated packages: \$(cat /var/run/reboot-required.pkgs | tr '\n' ' ')"
  else
    echo "1 Reboot_needed - A system reboot is needed"
  fi
else
  echo "0 Reboot_needed - No system reboot needed"
fi
EOF
sudo chmod +x /usr/lib/check_mk_agent/local/reboot


sleep 10


# Get the host IP-Address
HostIP=$(ip -4 route get 8.8.8.8 | awk 'NR==1 {print $7}')

# Create Host via REST-API
if [ $DEBUG == "yes" ]; then
  echo "Create Host via REST-API"
fi
BODY="{\"folder\": \"/linux_maschinen\", \"host_name\": \"$(hostname | tr '[:upper:]' '[:lower:]')\", \"attributes\": {\"ipaddress\": \"$HostIP\"}}"
curl -s -S -H "Accept: application/json" -H "Authorization: Bearer $USERNAME $PASSWORD" -X POST -H "Content-Type: application/json" -d "$BODY" "$API_URL/domain-types/host_config/collections/all"


sleep 3


# Create a temporary file
temp_file=$(mktemp)
# Get ETag from "pending changes" object via REST-API
if [ $DEBUG == "yes" ]; then
  echo "Get ETag from 'pending changes' object via REST-API"
fi
curl -s -S -I -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET "$API_URL/domain-types/activation_run/collections/pending_changes" > "$temp_file"
# Extract the ETag value from the file content
result=$(grep -iE '^ETag: ' "$temp_file" | awk '{print $2}' | tr -d '"' | tr -cd '[:alnum:]')
# Delete the temporary file
rm "$temp_file"


sleep 3


# Activate the pending changes via REST-API
if [ $DEBUG == "yes" ]; then
  echo "Activate the pending changes via REST-API"
fi
BODY="{\"force_foreign_changes\": \"false\", \"redirect\": \"false\", \"sites\": [\"$SITE_NAME\"]}"
curl -s -S -H "Accept: application/json" -H "Authorization: Bearer $USERNAME $PASSWORD" -H "If-Match: \"$result\"" -X POST -H "Content-Type: application/json" -d "$BODY" "$API_URL/domain-types/activation_run/actions/activate-changes/invoke"


sleep 60


# Register the Agent
if [ $DEBUG == "yes" ]; then
  echo "Register the Agent"
fi
cmk-agent-ctl register --hostname $(hostname | tr '[:upper:]' '[:lower:]') --server $SERVER_NAME --site $SITE_NAME --user $USERNAME --password $PASSWORD --trust-cert


sleep 120


# Accept all found labels for the newly created host
if [ $DEBUG == "yes" ]; then
  echo "Accept all found labels for the newly created host"
fi
BODY="{\"host_name\": \"$(hostname | tr '[:upper:]' '[:lower:]')\", \"mode\": \"only_host_labels\"}"
curl -s -S -H "Accept: application/json" -H "Authorization: Bearer $USERNAME $PASSWORD" -X POST -H "Content-Type: application/json" -d "$BODY" "$API_URL/domain-types/service_discovery_run/actions/start/invoke"


sleep 30


# Create a temporary file
temp_file=$(mktemp)
# Get ETag from "pending changes" object via REST-API
if [ $DEBUG == "yes" ]; then
  echo "Get ETag from 'pending changes' object via REST-API"
fi
curl -s -S -I -H "Authorization: Bearer $USERNAME $PASSWORD" -X GET "$API_URL/domain-types/activation_run/collections/pending_changes" > "$temp_file"
# Extract the ETag value from the file content
result=$(grep -iE '^ETag: ' "$temp_file" | awk '{print $2}' | tr -d '"' | tr -cd '[:alnum:]')
# Delete the temporary file
rm "$temp_file"


sleep 3


# Activate the pending changes via REST-API
if [ $DEBUG == "yes" ]; then
  echo "Activate the pending changes via REST-API"
fi
BODY="{\"force_foreign_changes\": \"false\", \"redirect\": \"false\", \"sites\": [\"$SITE_NAME\"]}"
curl -s -S -H "Accept: application/json" -H "Authorization: Bearer $USERNAME $PASSWORD" -H "If-Match: \"$result\"" -X POST -H "Content-Type: application/json" -d "$BODY" "$API_URL/domain-types/activation_run/actions/activate-changes/invoke"


# Script deletes itself
if [ $DEBUG == "yes" ]; then
  echo "Script deletes itself"
fi
currentscript=$0
shred -u ${currentscript}