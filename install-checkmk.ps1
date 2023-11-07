# check if running as administrator
#Requires -RunAsAdministrator

# parameters needed to be set site-specific.
$SERVER_NAME="v-u-checkmk-p"
$SITE_NAME="cmk" # More infos: https://docs.checkmk.com/latest/de/intro_setup.html#create_site
$API_URL="http://$SERVER_NAME/$SITE_NAME/check_mk/api/1.0"
$USERNAME="automation"
$PASSWORD="<PASSWORD_OF_THE_AUTOMATION_USER>"
$FOLDER="/" # (Optional) More infos: https://docs.checkmk.com/latest/de/hosts_structure.html?#folder
# End specific parameters
##### below should not be changed unless you are absolutely sure in what you are doing !


# Function to display a message and a spinner while a background job is running
function Spinner {
    param (
        [Parameter(Mandatory=$true)][int]$JobId,
        [Parameter(Mandatory=$true)][String]$Message,
        [Parameter(Mandatory=$true)][int]$AdditionalDelay
    )
    $AdditionalDelay=$AdditionalDelay*10

    $spinChars = "/-\|"

    while ($true) {
        if ($job.State -eq 'Completed' -or $job.State -eq 'Failed' -or $job.State -eq 'Stopped') {
            break
        }
        $spinChar = $spinChars[0]
        $spinChars = $spinChars.Substring(1) + $spinChar
        Write-Host -NoNewline ($Message+": " + $spinChar) -ForegroundColor Cyan
        Start-Sleep -Milliseconds 100
        Write-Host -NoNewline "`r"  # Clear the line
    }

    if ($job.ChildJobs[0].Error -ne "") {
        Write-Host `r`n($job.ChildJobs[0].Error) -ForegroundColor Red
        exit 1
    }

    for ($i = 1; $i -le $AdditionalDelay; $i++) {
        $spinChar = $spinChars[0]
        $spinChars = $spinChars.Substring(1) + $spinChar
        Write-Host -NoNewline ($Message+": " + $spinChar) -ForegroundColor Cyan
        Start-Sleep -Milliseconds 100
        Write-Host -NoNewline "`r"  # Clear the line
    }

    Write-Host ($Message+": OK") -ForegroundColor Green
}


# Check if there are any pending changes on the checkmk server
$job = Start-Job -ArgumentList $API_URL,$USERNAME,$PASSWORD -ScriptBlock {
    $headers = @{
        'Accept' = 'application/json'
        'Authorization' = "Bearer $($args[1]) $($args[2])"
    }
    $result = Invoke-WebRequest -Method GET -Uri "$($args[0])/domain-types/activation_run/collections/pending_changes" -Headers $headers -UseBasicParsing
    Write-Output $result.RawContentLength
}
Spinner -JobId $job.Id -Message "Get Content-Length from 'pending changes' object via REST-API" -AdditionalDelay 0
$result = Receive-Job -Id $job.Id
Remove-Job -Id $job.Id
if ($result -gt 350) {
    Write-Output "Please revert or accept pending change(s) on the checkmk server before running the script! Install aborted!" -ForegroundColor Red
    exit
}


# Download check_mk_agent.msi file from checkmk-server via REST-API
$job = Start-Job -ArgumentList $API_URL,$USERNAME,$PASSWORD -ScriptBlock {
    $headers = @{
        'Accept' = 'application/octet-stream'
        'Authorization' = "Bearer $($args[1]) $($args[2])"
    }
    $BODY = @{
        'os_type' = 'windows_msi'
    }
    Invoke-RestMethod -Method GET -Uri "$($args[0])/domain-types/agent/actions/download/invoke" -Headers $headers -Body $BODY -ContentType 'application/json' -OutFile "C:\Windows\Temp\check_mk_agent.msi"
}
Spinner -JobId $job.Id -Message "Download check_mk_agent.msi file from checkmk-server via REST-API" -AdditionalDelay 0
Remove-Job -Id $job.Id


# Install check_mk_agent
$job = Start-Job -ScriptBlock {
    $installpathcheckmk = "/i C:\Windows\Temp\check_mk_agent.msi /qn"
    Start-Process C:\Windows\System32\msiexec.exe -ArgumentList $installpathcheckmk -wait
    Copy-Item 'C:\Program Files (x86)\checkmk\service\plugins\windows_updates.vbs' -Destination C:\ProgramData\checkmk\agent\plugins
    Copy-Item 'C:\Program Files (x86)\checkmk\service\plugins\mk_inventory.vbs' -Destination C:\ProgramData\checkmk\agent\plugins
}
Spinner -JobId $job.Id -Message "Install check_mk_agent" -AdditionalDelay 0
Remove-Job -Id $job.Id


# Get the host IP-Address
$env:HostIP = (
    Get-NetIPConfiguration |
    Where-Object {
        $_.IPv4DefaultGateway -ne $null -and
        $_.NetAdapter.Status -ne "Disconnected"
    }
).IPv4Address.IPAddress


# Create Host via REST-API
$job = Start-Job -ArgumentList $API_URL,$USERNAME,$PASSWORD,$FOLDER -ScriptBlock {
    $headers = @{
        'Accept' = 'application/json'
        'Authorization' = "Bearer $($args[1]) $($args[2])"
    }
    $BODY = -join( '{"folder": "' , $args[3] , '", "host_name": "' , $($env:computername.ToLower()) , '", "attributes": {"ipaddress": "' , $env:HostIP , '"}}' )
    Invoke-RestMethod -Method Post -Uri "$($args[0])/domain-types/host_config/collections/all" -Headers $headers -Body $BODY -ContentType "application/json"
}
Spinner -JobId $job.Id -Message "Create Host via REST-API" -AdditionalDelay 0
Remove-Job -Id $job.Id


# Get ETag from "pending changes" object via REST-API
$job = Start-Job -ArgumentList $API_URL,$USERNAME,$PASSWORD -ScriptBlock {
    $headers = @{
        'Accept' = 'application/json'
        'Authorization' = "Bearer $($args[1]) $($args[2])"
    }
    $result = Invoke-WebRequest -Method GET -Uri "$($args[0])/domain-types/activation_run/collections/pending_changes" -Headers $headers -UseBasicParsing
    Write-Output $result.Headers.ETag
}
Spinner -JobId $job.Id -Message "Get ETag from 'pending changes' object via REST-API" -AdditionalDelay 0
$result = Receive-Job -Id $job.Id
Remove-Job -Id $job.Id


# Start activating the pending changes via REST-API
$job = Start-Job -ArgumentList $API_URL,$USERNAME,$PASSWORD,$SITE_NAME,$result -ScriptBlock {
    $headers = @{
        'Accept' = 'application/json'
        'Authorization' = "Bearer $($args[1]) $($args[2])"
        'If-Match' = $args[4]
    }
    $BODY= -join( '{"force_foreign_changes": "false", "redirect": "false", "sites": ["' , $args[3] , '"]}' )
    $result = Invoke-RestMethod -Method Post -Uri "$($args[0])/domain-types/activation_run/actions/activate-changes/invoke" -Headers $headers -Body $BODY -ContentType "application/json"
    Write-Output $result.Id
}
Spinner -JobId $job.Id -Message "Start activating the pending changes via REST-API" -AdditionalDelay 0
$activation_id = Receive-Job -Id $job.Id
Remove-Job -Id $job.Id


# Waiting for changes to be applied
$job = Start-Job -ArgumentList $API_URL,$USERNAME,$PASSWORD,$activation_id -ScriptBlock {
    $headers = @{
        'Accept' = '*/*'
        'Authorization' = "Bearer $($args[1]) $($args[2])"
    }
    Invoke-RestMethod -Method Post -Uri "$($args[0])/objects/activation_run/$($args[3])/actions/wait-for-completion/invoke" -Headers $headers -Body $BODY -ContentType "application/json"
}
Spinner -JobId $job.Id -Message "Waiting for changes to be applied" -AdditionalDelay 0
Remove-Job -Id $job.Id


# Register the Agent
$job = Start-Job -ArgumentList $SERVER_NAME,$SITE_NAME,$USERNAME,$PASSWORD -ScriptBlock {
    Start-Process "C:\Program Files (x86)\checkmk\service\cmk-agent-ctl.exe" -ArgumentList "register --hostname $($env:computername.ToLower()) --server $($args[0]) --site $($args[1]) --user $($args[2]) --password $($args[3]) --trust-cert" -Wait -WindowStyle Hidden
}
Spinner -JobId $job.Id -Message "Register the Agent (Wait 60 secounds for host-lables to be assigned to host-object)" -AdditionalDelay 60
Remove-Job -Id $job.Id


# Start service discovery for the newly created host via REST-API
$job = Start-Job -ArgumentList $API_URL,$USERNAME,$PASSWORD -ScriptBlock {
    $headers = @{
        'Accept' = 'application/json'
        'Authorization' = "Bearer $($args[1]) $($args[2])"
    }
    $BODY = -join( '{"host_name": "' , $($env:computername.ToLower()) , '", "mode": "only_host_labels"}' )
    Invoke-RestMethod -Method Post -Uri "$($args[0])/domain-types/service_discovery_run/actions/start/invoke" -Headers $headers -Body $BODY -ContentType "application/json" -TimeoutSec 120
}
Spinner -JobId $job.Id -Message "Start service discovery for the newly created host via REST-API (Wait 120 secounds)" -AdditionalDelay 120
Remove-Job -Id $job.Id



# Get ETag from "pending changes" object via REST-API
$job = Start-Job -ArgumentList $API_URL,$USERNAME,$PASSWORD -ScriptBlock {
    $headers = @{
        'Accept' = 'application/json'
        'Authorization' = "Bearer $($args[1]) $($args[2])"
    }
    $result = Invoke-WebRequest -Method GET -Uri "$($args[0])/domain-types/activation_run/collections/pending_changes" -Headers $headers -UseBasicParsing
    Write-Output $result.Headers.ETag
}
Spinner -JobId $job.Id -Message "Get ETag from 'pending changes' object via REST-API" -AdditionalDelay 0
$result = Receive-Job -Id $job.Id
Remove-Job -Id $job.Id


# Start activating the pending changes via REST-API
$job = Start-Job -ArgumentList $API_URL,$USERNAME,$PASSWORD,$SITE_NAME,$result -ScriptBlock {
    $headers = @{
        'Accept' = 'application/json'
        'Authorization' = "Bearer $($args[1]) $($args[2])"
        'If-Match' = $args[4]
    }
    $BODY= -join( '{"force_foreign_changes": "false", "redirect": "false", "sites": ["' , $args[3] , '"]}' )
    Invoke-RestMethod -Method Post -Uri "$($args[0])/domain-types/activation_run/actions/activate-changes/invoke" -Headers $headers -Body $BODY -ContentType "application/json"
}
Spinner -JobId $job.Id -Message "Start activating the pending changes via REST-API" -AdditionalDelay 0
Remove-Job -Id $job.Id


# Script deletes itself
Write-Output "Script deletes itself"
Remove-Item -Path $MyInvocation.MyCommand.Source -Force