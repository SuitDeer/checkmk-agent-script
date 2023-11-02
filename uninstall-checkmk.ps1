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
$body = @{
    'os_type' = 'windows_msi'
}
Invoke-RestMethod -Method GET -Uri "$API_URL/domain-types/agent/actions/download/invoke" -Headers $headers -Body $body -ContentType 'application/json' -OutFile "C:\Windows\Temp\check_mk_agent.msi"


Start-Sleep -Seconds 10


# Uninstall check_mk_agent
if ( $DEBUG == "yes" )
{
    Write-Output "Uninstall check_mk_agent"
}
$uninstallpathcheckmk = "/x C:\Windows\Temp\check_mk_agent.msi /qn"
Start-Process C:\Windows\System32\msiexec.exe -ArgumentList $uninstallpathcheckmk -wait


Start-Sleep -Seconds 10


# Delete Host via REST-API
if ( $DEBUG == "yes" )
{
    Write-Output "Delete Host via REST-API"
}
$headers = @{
    'Accept' = 'application/json'
    'Authorization' = "Bearer $USERNAME $PASSWORD"
}
Invoke-RestMethod -Method DELETE -Uri "$API_URL/objects/host_config/$($env:computername.ToLower())" -Headers $Headers -ContentType "application/json"


Start-Sleep -Seconds 3


# Get ETag from "pending changes" object via REST-API
if ( $DEBUG == "yes" )
{
    Write-Output "Get ETag from 'pending changes' object via REST-API"
}
$headers = @{
    'Accept' = 'application/json'
    'Authorization' = "Bearer $USERNAME $PASSWORD"
}
$result = Invoke-WebRequest -Method GET -Uri "$API_URL/domain-types/activation_run/collections/pending_changes" -Headers $headers -UseBasicParsing


Start-Sleep -Seconds 3


# Activate the pending changes via REST-API
if ( $DEBUG == "yes" )
{
    Write-Output "Activate the pending changes via REST-API"
}
$headers = @{
    'Accept' = 'application/json'
    'Authorization' = "Bearer $USERNAME $PASSWORD"
    'If-Match' = $result.Headers.ETag
}
$BODY= -join( '{"force_foreign_changes": "false", "redirect": "false", "sites": ["' , $SITE_NAME , '"]}' )
Invoke-RestMethod -Method Post -Uri "$API_URL/domain-types/activation_run/actions/activate-changes/invoke" -Headers $Headers -Body $BODY -ContentType "application/json"
    

Remove-Item "C:\Program Files (x86)\checkmk" -Recurse -Force
Remove-Item "C:\ProgramData\checkmk" -Recurse -Force
Remove-Item "C:\ProgramData\cmk_agent_uninstall.txt" -Force


# Script deletes itself
if ( $DEBUG == "yes" )
{
    Write-Output "Script deletes itself"
}
Remove-Item -Path $MyInvocation.MyCommand.Source -Force