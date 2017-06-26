#-----------------------
# DownloadScripts.ps1
#-----------------------

# Stop on error
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

echo "$(date) DownloadScripts.ps1 Starting..." >> $env:SystemDrive\packer\configure.log

try {
    # Create the scripts directory
    echo "$(date) DownloadScripts.ps1 Creating scripts directory..." >> $env:SystemDrive\packer\configure.log
    mkdir c:\scripts -ErrorAction SilentlyContinue 2>&1 | Out-Null

    # Create the docker directory
    echo "$(date) DownloadScripts.ps1 Creating docker directory..." >> $env:SystemDrive\packer\configure.log
    mkdir c:\docker -ErrorAction SilentlyContinue 2>&1 | Out-Null
    
    echo "$(date) DownloadScripts.ps1 Doing downloads..." >> $env:SystemDrive\packer\configure.log
        
    # Downloads scripts for performing local runs.
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/runCI/executeCI.ps1" -DestinationPath "$env:SystemDrive\scripts\executeCI.ps1"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/runCI/Invoke-DockerCI.ps1" -DestinationPath "$env:SystemDrive\scripts\Invoke-DockerCI.ps1"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/runCI/RunOnCIServer.cmd" -DestinationPath "$env:SystemDrive\scripts\RunOnCIServer.cmd"

    # Build agnostic files (alphabetical order)
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/common/authorized_keys" -DestinationPath "c:\packer\authorized_keys"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/common/ConfigureCIEnvironment.ps1" -DestinationPath "c:\packer\ConfigureCIEnvironment.ps1"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/common/ConfigureSSH.ps1" -DestinationPath "c:\packer\ConfigureSSH.ps1"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/common/ConfigureSSH.sh" -DestinationPath "c:\packer\ConfigureSSH.sh"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/common/InstallMostThings.ps1" -DestinationPath "c:\packer\InstallMostThings.ps1"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/common/Phase1.ps1" -DestinationPath "c:\packer\Phase1.ps1"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/common/Phase2.ps1" -DestinationPath "c:\packer\Phase2.ps1"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/common/Phase3.ps1" -DestinationPath "c:\packer\Phase3.ps1"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/common/Phase4.ps1" -DestinationPath "c:\packer\Phase4.ps1"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/common/Phase5.ps1" -DestinationPath "c:\packer\Phase5.ps1"


    # OS Version specific files (alphabetical order)
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/rs/ConfigureControlDaemon.ps1" -DestinationPath "c:\packer\ConfigureControlDaemon.ps1"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/rs/DownloadScripts.ps1" -DestinationPath "c:\packer\DownloadScripts.ps1"
    #Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/rs/InstallPrivates.ps1" -DestinationPath "c:\packer\InstallPrivates.ps1"
    Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/rs/nssmdocker.cmd" -DestinationPath "c:\packer\nssmdocker.cmd"
}
Catch [Exception] {
    echo "$(date) DownloadScripts.ps1 Error '$_'" >> $env:SystemDrive\packer\configure.log
    Throw $_
}
Finally {
    echo "$(date) DownloadScripts.ps1 Completed." >> $env:SystemDrive\packer\configure.log
}  

