# check if running as administrator
#Requires -RunAsAdministrator

# parameters needed to be set site-specific.
$SERVER_NAME="v-u-checkmk-p"
$SITE_NAME="cmk"
$API_URL="http://$SERVER_NAME/$SITE_NAME/check_mk/api/1.0"
$USERNAME="automation" 
$PASSWORD="<PASSWORD_OF_THE_AUTOMATION_USER>"
# End specific parameters
##### below should not be changed unless you are absolutely sure in what you are doing !


$env:HostIP = (
    Get-NetIPConfiguration |
    Where-Object {
        $_.IPv4DefaultGateway -ne $null -and
        $_.NetAdapter.Status -ne "Disconnected"
    }
).IPv4Address.IPAddress


# Download check_mk_agent.msi file from checkmk-server via REST-API
$headers = @{
    'Accept' = 'application/octet-stream'
    'Authorization' = "Bearer $USERNAME $PASSWORD"
}
$BODY = @{
    'os_type' = 'windows_msi'
}
Invoke-RestMethod -Method GET -Uri "$API_URL/domain-types/agent/actions/download/invoke"  -Headers $headers -Body $BODY -ContentType 'application/json' -OutFile "C:\Windows\Temp\check_mk_agent.msi"


Start-Sleep -Seconds 10


# Install check_mk_agent
$installpathcheckmk = "/i C:\Windows\Temp\check_mk_agent.msi /qn"
Start-Process C:\Windows\System32\msiexec.exe -ArgumentList $installpathcheckmk -wait
Copy-Item 'C:\Program Files (x86)\checkmk\service\plugins\windows_updates.vbs' -Destination C:\ProgramData\checkmk\agent\plugins
Copy-Item 'C:\Program Files (x86)\checkmk\service\plugins\mk_inventory.vbs' -Destination C:\ProgramData\checkmk\agent\plugins


Start-Sleep -Seconds 10


# Create Host via REST-API
$headers = @{
    'Accept' = 'application/json'
    'Authorization' = "Bearer $USERNAME $PASSWORD"
}
$BODY = -join( '{"folder": "/windows_maschinen", "host_name": "' , $($env:computername.ToLower()) , '", "attributes": {"ipaddress": "' , $env:HostIP , '"}}' )
Invoke-RestMethod -Method Post -Uri "$API_URL/domain-types/host_config/collections/all" -Headers $headers -Body $BODY -ContentType "application/json"


Start-Sleep -Seconds 3


# Get ETag from "pending changes" object
$headers = @{
    'Accept' = 'application/json'
    'Authorization' = "Bearer $USERNAME $PASSWORD"
}
$result = Invoke-WebRequest -Method GET -Uri "$API_URL/domain-types/activation_run/collections/pending_changes" -Headers $headers -UseBasicParsing


Start-Sleep -Seconds 3


# Activate the changes via REST-API
$headers = @{
    'Accept' = 'application/json'
    'Authorization' = "Bearer $USERNAME $PASSWORD"
    'If-Match' = $result.Headers.ETag
}
$BODY= -join( '{"force_foreign_changes": "false", "redirect": "false", "sites": ["' , $SITE_NAME , '"]}' )
Invoke-RestMethod -Method Post -Uri "$API_URL/domain-types/activation_run/actions/activate-changes/invoke" -Headers $headers -Body $BODY -ContentType "application/json"


Start-Sleep -Seconds 60


# Register the Agent
Start-Process "C:\Program Files (x86)\checkmk\service\cmk-agent-ctl.exe" -ArgumentList "register --hostname $($env:computername.ToLower()) --server $SERVER_NAME --site $SITE_NAME --user $USERNAME --password $PASSWORD --trust-cert" -Wait -WindowStyle Hidden


Start-Sleep -Seconds 120


# Accept all found labels for the newly created host
$headers = @{
    'Accept' = 'application/json'
    'Authorization' = "Bearer $USERNAME $PASSWORD"
}
$BODY = -join( '{"host_name": "' , $($env:computername.ToLower()) , '", "mode": "only_host_labels"}' )
Invoke-RestMethod -Method Post -Uri "$API_URL/domain-types/service_discovery_run/actions/start/invoke" -Headers $headers -Body $BODY -ContentType "application/json" -TimeoutSec 120


Start-Sleep -Seconds 30


# Get ETag from "pending changes" object
$headers = @{
    'Accept' = 'application/json'
    'Authorization' = "Bearer $USERNAME $PASSWORD"
}
$result = Invoke-WebRequest -Method GET -Uri "$API_URL/domain-types/activation_run/collections/pending_changes" -Headers $headers -UseBasicParsing


Start-Sleep -Seconds 3


# Activate the changes via REST-API
$headers = @{
    'Accept' = 'application/json'
    'Authorization' = "Bearer $USERNAME $PASSWORD"
    'If-Match' = $result.Headers.ETag
}
$BODY= -join( '{"force_foreign_changes": "false", "redirect": "false", "sites": ["' , $SITE_NAME , '"]}' )
Invoke-RestMethod -Method Post -Uri "$API_URL/domain-types/activation_run/actions/activate-changes/invoke" -Headers $headers -Body $BODY -ContentType "application/json"

# Script deletes itself
Remove-Item -Path $MyInvocation.MyCommand.Source -Force