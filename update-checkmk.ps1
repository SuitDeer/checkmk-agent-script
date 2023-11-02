# check if running as administrator
#Requires -RunAsAdministrator


# parameters needed to be set site-specific.
$SERVER_NAME="v-u-checkmk-p"
$SITE_NAME="cmk"
$API_URL="http://$SERVER_NAME/$SITE_NAME/check_mk/api/1.0"
$USERNAME="automation" 
$PASSWORD="<PASSWORD_OF_THE_AUTOMATION_USER>"
# Debug switch, set to yes for verbose info, else the script will be silent.
$DEBUG="yes"
# End specific parameters
##### below should not be changed unless you are absolutely sure in what you are doing !


# Download check_mk_agent.msi file from checkmk-server via REST-API
if ( $DEBUG == "yes" )
{
    Write-Output "Download check_mk_agent.msi file from checkmk-server via REST-API"
}
$headers = @{
    'Accept' = 'application/octet-stream'
    'Authorization' = "Bearer $USERNAME $PASSWORD"
}
$BODY = @{
    'os_type' = 'windows_msi'
}
Invoke-RestMethod -Method GET -Uri "$API_URL/domain-types/agent/actions/download/invoke" -Headers $headers -Body $BODY -ContentType 'application/json' -OutFile "C:\Windows\Temp\check_mk_agent.msi"


Start-Sleep -Seconds 10


# Install check_mk_agent
if ( $DEBUG == "yes" )
{
    Write-Output "Install check_mk_agent"
}
$installpathcheckmk = "/i C:\Windows\Temp\check_mk_agent.msi /qn"
Start-Process C:\Windows\System32\msiexec.exe -ArgumentList $installpathcheckmk -wait
Copy-Item 'C:\Program Files (x86)\checkmk\service\plugins\windows_updates.vbs' -Destination C:\ProgramData\checkmk\agent\plugins -Force
Copy-Item 'C:\Program Files (x86)\checkmk\service\plugins\mk_inventory.vbs' -Destination C:\ProgramData\checkmk\agent\plugins -Force


Start-Sleep -Seconds 10


# Register the Agent
if ( $DEBUG == "yes" )
{
    Write-Output "Register the Agent"
}
Start-Process "C:\Program Files (x86)\checkmk\service\cmk-agent-ctl.exe" -ArgumentList "register --hostname $($env:computername.ToLower()) --server $SERVER_NAME --site $SITE_NAME --user $USERNAME --password $PASSWORD --trust-cert" -Wait -WindowStyle Hidden


# Script deletes itself
if ( $DEBUG == "yes" )
{
    Write-Output "Script deletes itself"
}
Remove-Item -Path $MyInvocation.MyCommand.Source -Force