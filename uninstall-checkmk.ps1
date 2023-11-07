# check if running as administrator
#Requires -RunAsAdministrator

# parameters needed to be set site-specific.
$SERVER_NAME="v-u-checkmk-p"
$SITE_NAME="cmk" # More infos: https://docs.checkmk.com/latest/de/intro_setup.html#create_site
$API_URL="http://$SERVER_NAME/$SITE_NAME/check_mk/api/1.0"
$USERNAME="automation"
$PASSWORD="<PASSWORD_OF_THE_AUTOMATION_USER>"
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
        Write-Host -NoNewline ($Message+" : " + $spinChar) -ForegroundColor Cyan
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
        Write-Host -NoNewline ($Message+" : " + $spinChar) -ForegroundColor Cyan
        Start-Sleep -Milliseconds 100
        Write-Host -NoNewline "`r"  # Clear the line
    }

    Write-Host ($Message+" : OK") -ForegroundColor Green
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
    Write-Output "Please revert or accept pending change(s) on the checkmk server before running the script! Uninstall aborted!" -ForegroundColor Red
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


# Uninstall check_mk_agent
$job = Start-Job -ScriptBlock {
    $installpathcheckmk = "/x C:\Windows\Temp\check_mk_agent.msi /qn"
    Start-Process C:\Windows\System32\msiexec.exe -ArgumentList $installpathcheckmk -wait
    Remove-Item "C:\Program Files (x86)\checkmk" -Recurse -Force
    Remove-Item "C:\ProgramData\checkmk" -Recurse -Force
    Remove-Item "C:\ProgramData\cmk_agent_uninstall.txt" -Force
}
Spinner -JobId $job.Id -Message "Uninstall check_mk_agent" -AdditionalDelay 0
Remove-Job -Id $job.Id


# Delete Host via REST-API
$job = Start-Job -ArgumentList $API_URL,$USERNAME,$PASSWORD -ScriptBlock {
    $headers = @{
        'Accept' = 'application/json'
        'Authorization' = "Bearer $($args[1]) $($args[2])"
    }
    Invoke-RestMethod -Method DELETE -Uri "$($args[0])/objects/host_config/$($env:computername.ToLower())" -Headers $Headers -ContentType "application/json"
}
Spinner -JobId $job.Id -Message "Delete Host via REST-API" -AdditionalDelay 0
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