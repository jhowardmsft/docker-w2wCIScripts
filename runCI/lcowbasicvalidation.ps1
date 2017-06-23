#
# Jenkins CI scripts for Windows LCOW CI
# By John Howard (@jhowardmsft) June 2017.
#
# These are very basic tests, NOT the integration CLI
#

$ErrorActionPreference = 'Stop'
$StartTime=Get-Date

Function Try-Command([string]$command, [bool]$hardFail, [string]$mustContain) {
    #$ErrorActionPreference = "SilentlyContinue"
    $global:count++
    $start=$(get-date)
    Write-Host -foregroundColor yellow " `n>>> ($global:count) $(get-date -format 'HH:mm:s.ffff') $command"
    # https://stackoverflow.com/questions/8097354/how-do-i-capture-the-output-into-a-variable-from-an-external-process-in-powershe
    $output = cmd /c $command '2>&1' | Out-String
    $ErrorActionPreference = "Stop"
    if (($LastExitCode -ne 0) -and ($hardFail)) {
        Write-Host -ForegroundColor Red "`n$output`n"
        Throw "'$command' failed with exitcode $LastExitCode"
    }
    if ($mustContain -ne "") {
        if (-not ($output -match $mustContain)) {
            Throw "$command output did not contain '$mustContain': $output"
        }
    }

    $Dur=New-TimeSpan -Start $start -End $(Get-Date)    
    Write-Host -foregroundColor yellow "<<< ($global:count) Duration`:$($dur -f "{0:g}")`n"
    return $output
}


Try {
    $global:count=0
    Write-Host -ForegroundColor Cyan "INFO: lcowtests.ps1 starting at $(date)"
    Write-Host -ForegroundColor Cyan "INFO: Pointing to daemon at $env:DOCKER_HOST"


    #---------------------------------------------------------------------------------#

    Try-Command "docker info" $true "LCOW:" # From the storage driver

    Try-Command "docker version" $true "API version:"

    Try-Command "docker ps -a" $true "CONTAINER ID" # From the heading

    Try-Command "docker images" $true "REPOSITORY" # From the heading

    # Delete all containers
    $psaq = Try-Command 'docker ps -aq' $false ""
    $psaq = $psaq -replace("`r`n"," ")
    if ($psaq.Length -gt 0) {
       Try-Command "docker rm -f $psaq" $true ""
    }

    # Delete all images
    $imgs = Try-Command 'docker images --format "{{.ID}}"' $false ""
    $imgs = $imgs -replace("`r`n"," ")
    if ($imgs.Length -gt 0) {
       Try-Command "docker rmi -f $imgs" $true ""
    }

    # Pull and verify it's listed
    Try-Command "docker pull busybox" $true ""
    Try-Command 'docker images --format "{{.Repository}}:{{.ID}}"' $true "busybox:"
    Try-Command 'docker images' $false ""


    # Run a container, commit it, make sure it shows up in the list of images, and that when we run it, the change was present.
    Try-Command "docker run --name commitme busybox mkdir /john" $true ""
    $sha = Try-Command "docker commit commitme committed" $true "sha256:"   # sha256 is printed on the line after a commit
    $sha = $sha.Substring(7,12)  # get the short-id
    Try-Command 'docker images --format "{{.Repository}}:{{.ID}}"' $true "committed:$sha"
    Try-Command "docker run committed ls -l /" $true "john"


    #---------------------------------------------------------------------------------#

} Catch [Exception] {
    $FinallyColour="Red"
    Write-Host -ForegroundColor Red ("`r`n`r`nERROR: Failed '$_' at $(Get-Date)")
    Write-Host "`n`n"

    # Exit to ensure Jenkins captures it. Don't do this in the ISE or interactive Powershell - they will catch the Throw onwards.
    if ( ([bool]([Environment]::GetCommandLineArgs() -Like '*-NonInteractive*')) -and `
         ([bool]([Environment]::GetCommandLineArgs() -NotLike "*Powershell_ISE.exe*"))) {
        exit 1
    }
    Throw $_
}
Finally {
    $ErrorActionPreference="SilentlyContinue"
	$global:ProgressPreference=$origProgressPreference
    $Dur=New-TimeSpan -Start $StartTime -End $(Get-Date)
    Write-Host -ForegroundColor $FinallyColour "INFO: lcowtests.ps1 exiting at $(date). Duration $dur"
}

