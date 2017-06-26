#-----------------------
# Phase0.ps1
# Do not run directly. Use bootstrap instead.
#-----------------------

param(
    [Parameter(Mandatory=$false)][string]$ConfigSet
)

$ErrorActionPreference="stop"

function Test-Nano() {  
    $EditionId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID').EditionId  
    return (($EditionId -eq "ServerStandardNano") -or   
            ($EditionId -eq "ServerDataCenterNano") -or   
            ($EditionId -eq "NanoServer") -or   
            ($EditionId -eq "ServerTuva"))  
}  

function Copy-File {  
    [CmdletBinding()]  
    param(  
        [string] $SourcePath,  
        [string] $DestinationPath  
    )  

    if ($SourcePath -eq $DestinationPath) { return }  

    if (Test-Path $SourcePath) { 
        Copy-Item -Path $SourcePath -Destination $DestinationPath 
    } elseif (($SourcePath -as [System.URI]).AbsoluteURI -ne $null) {  
        if (Test-Nano) {
            $handler = New-Object System.Net.Http.HttpClientHandler  
            $client = New-Object System.Net.Http.HttpClient($handler)  
            $client.Timeout = New-Object System.TimeSpan(0, 30, 0)  
            $cancelTokenSource = [System.Threading.CancellationTokenSource]::new()   
            $responseMsg = $client.GetAsync([System.Uri]::new($SourcePath), $cancelTokenSource.Token)  
            $responseMsg.Wait()  

            if (!$responseMsg.IsCanceled) {  
                $response = $responseMsg.Result  
                if ($response.IsSuccessStatusCode) {  
                    $downloadedFileStream = [System.IO.FileStream]::new($DestinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)  
                    $copyStreamOp = $response.Content.CopyToAsync($downloadedFileStream)  
                    $copyStreamOp.Wait()  
                    $downloadedFileStream.Close()  
                    if ($copyStreamOp.Exception -ne $null) {  
                        throw $copyStreamOp.Exception  
                    }        
                }  
            }    
        }  
        elseif ($PSVersionTable.PSVersion.Major -ge 5) {
            # We disable progress display because it kills performance for large downloads (at least on 64-bit PowerShell)  
            $ProgressPreference = 'SilentlyContinue'  
            wget -Uri $SourcePath -OutFile $DestinationPath -UseBasicParsing  
            $ProgressPreference = 'Continue'  
        } else {  
            $webClient = New-Object System.Net.WebClient  
            $webClient.DownloadFile($SourcePath, $DestinationPath)  
        }   
    } else {  
        throw "Cannot copy from $SourcePath"  
    }  
}  

echo "$(date) Phase0.ps1 starting..." >> $env:SystemDrive\packer\configure.log
if (-not (Test-Nano)) {
    echo $(date) > "c:\users\public\desktop\Phase0 Start.txt"
}

try {
    # Delete the scheduled task if it exists
    $ConfirmPreference='none'
    $t = Get-ScheduledTask 'Phase0' -ErrorAction SilentlyContinue
    if ($t -ne $null) {
        echo "$(date) Phase0.ps1 deleting scheduled task.." >> $env:SystemDrive\packer\configure.log
        Unregister-ScheduledTask 'Phase0' -Confirm:$False -ErrorAction SilentlyContinue
    }

    if ([string]::IsNullOrWhiteSpace($ConfigSet)) {
         Throw "ConfigSet must be supplied (eg rs)"
    }
    echo "$(date) Phase0.ps1 ConfigSet is $ConfigSet" >> $env:SystemDrive\packer\configure.log

    # Coming out of sysprep, we reboot twice, so do not do anything on the first reboot. This also has the nice
    # side effect that we are guaranteed after the reboot the $env:ConfigSet is set so that any script subsequently can pick it up.
    if (-not (Test-Path c:\packer\Phase0.RebootedOnce.txt)) {

        # Re-register on account of local install on development machine (done in packer for production)
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-command c:\packer\Phase0.ps1 $ConfigSet"
        $trigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay 00:01:00
        Register-ScheduledTask -TaskName "Phase0" -Action $action -Trigger $trigger -User SYSTEM -RunLevel Highest

        echo "$(date) Phase0.RebootedOnce.txt doesn't exist, so creating it and not doing anything..." >> $env:SystemDrive\packer\configure.log
        New-Item c:\packer\Phase0.RebootedOnce.txt
        shutdown /t 0 /r /f /c "First reboot in Phase0"
        exit 0
    } else {
        # We've rebooted once. On our way forward then...

        # Create the scripts directory
        echo "$(date) Phase0.ps1 Creating scripts directory..." >> $env:SystemDrive\packer\configure.log
        mkdir c:\\scripts -ErrorAction SilentlyContinue 2>&1 | Out-Null

        # Download the script that downloads our files, but sleep 30 seconds to give the network time to come up
        echo "$(date) Phase0.ps1 Sleeping 30 seconds for network..." >> $env:SystemDrive\packer\configure.log
        Start-Sleep -Seconds 30
        echo "$(date) Phase0.ps1 Downloading DownloadScripts.ps1..." >> $env:SystemDrive\packer\configure.log
        Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/$ConfigSet/DownloadScripts.ps1" -DestinationPath "$env:SystemDrive\packer\DownloadScripts.ps1"

        # Invoke the downloads
        echo "$(date) Phase0.ps1 Invoking DownloadScripts.ps1..." >> $env:SystemDrive\packer\configure.log
        powershell -command "$env:SystemDrive\packer\DownloadScripts.ps1"

        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-command c:\packer\Phase1.ps1"
        $trigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay 00:01:00
        Register-ScheduledTask -TaskName "Phase1" -Action $action -Trigger $trigger -User SYSTEM -RunLevel Highest

        echo "$(date) Phase0.ps1 rebooting..." >> $env:SystemDrive\packer\configure.log
        shutdown /t 0 /r /f /c "Second reboot in Phase0"
    }
}
Catch [Exception] {
    Throw $_
    echo "$(date) Phase0.ps1 complete with Error '$_'" >> $env:SystemDrive\packer\configure.log
    if (-not (Test-Nano)) {
        echo $(date) > "c:\users\public\desktop\ERROR Phase0.txt"
    }
    exit 1
}
Finally {
    echo "$(date) Phase0.ps1 completed..." >> $env:SystemDrive\packer\configure.log
    if (-not (Test-Nano)) {
        echo $(date) > "c:\users\public\desktop\Phase0 End.txt"
    }
}  
