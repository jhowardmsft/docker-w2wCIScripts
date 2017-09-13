<#
.NOTES
    Author:  John Howard, Microsoft Corporation. (Github @jhowardmsft)

    Created: February 2016

    Summary: Invokes Windows to Windows Docker CI testing on an arbitrary
             build of Windows configured for running containers, against
             an arbitrary git branch (moby/moby master is default)

    License: See https://github.com/jhowardmsft/docker-w2wCIScripts/blob/master/LICENSE

    Pre-requisites:

     - Must be elevated
     - Hyper-V role is installed
     - Containers role is installed
     - (For non-public Windows builds/branches, either Microsoft corpnet access, or base images copied to c:\baseimages)

    If no parameters are supplied, the system drive will be used for
    everything; the latest binary from master.dockerproject.org will be
    used as the control daemon, and the sources will be the current master
    available at https://github.com/moby/moby.

    THIS TAKES AGES TO RUN!!!
      Expect this entire script to take (as at time of writing based on around
      540 integration tests and RS1 10B) ~48 mins on a Z420 in a VM running with
      8 cores, 4GB RAM and backed by a fast (Samsung Evo 850 Pro) SSD.
      I would expect HDD to take significantly longer (not recommended...). 

.PARAMETER SourcesDrive
     For example "c". Drive where the sources will be cloned.
     If not set, it will default to the system drive. If you have a
     secondary fast drive such as SSD/NVME PCIe adapter, using
     its drive would make this whole script run a lot faster

.PARAMETER SourcesSubdir
     For example "gopath". Subdir on SourcesDrive where the sources
     are cloned to such as c:\gopath\src\github.com\docker\docker. 
     If not set, defaults to 'gopath'

.PARAMETER TestrunDrive
     For example "c". Drive where the daemon under test is run.
     If not set, it will default to the system drive. If you have a
     secondary fast drive such as SSD/NVME PCIe adapter, using
     its drive would make this whole script run a lot faster

.PARAMETER TestrunSubdir
    For example "CI". Subdir on TestrunDrive where logs for the daemon under
    test are placed. The logs will be under TestrunDrive:\TestrunSubdir\CI-nnnnnn,
    where nnnnn is the commit ID of the git repo and branch being tested.
    If not set, defaults to 'CI'.

.PARAMETER GitRemote
    Allows a git repo to be tested. If set, it does the following
    steps:  git remote add remote $GitRemote
            git fetch $GitRemote (to get the branches for GitCheckout)

.PARAMETER GitCheckout
    Used in conjunction with GitRemote. If not specified, no
    `git checkout` after cloning the sources is done. This parameter
    allows a few things. 

    -  Want version 1.12.0 on master?  Use `v1.12.0` with no GitRemote

    -  Want to test a feature branch `jjh/buildpathhack`? Use the
       name of the feature branch. This is generally only useful if
       you also specify a GitRemote as that's where feature branches
       are expected to be committed and pushed to.

    -  Want to test a specific commit? Just put it in. For reference
       the TP4 docker is on moby/moby master, commit 18c9fe0,
       build date Nov 23 2015 22:32:50 UTC. In this example, you wouldn't
       set GitRemote as it's on master.

.PARAMETER DestroyCache
    When $True will remove the control daemons cache. This makes a second 
    run a lot slower. Defaults to $False.

.PARAMETER DockerBasePath
    The base path of the binary to use for the control binaries.
    Can be an http: path, or a file-path (local or UNC). If not supplied,
    the latest 64-bit Windows binary (binaries) from master.dockerproject.org
    will be used. Note that this is a path. The script will automatically
    add /docker.exe and optionally /dockerd.exe as needed. Don't include
    the trailing / or \ on this parameter!

.PARAMETER GitLocation
    The location of the git installer binary. Can be an http: path, or a
    file path (local or UNC). 

.PARAMETER CIScriptLocation
    The location of the bash CI script to actually do the CI work. This
    is a temporary parameter and will eventually be redundant once the
    Jenkins script is in the docker sources. Can be an http: path, or a
    file path (local or UNC).

.PARAMETER DUTDebugMode
    Whether to run the daemon under test in debug mode. Default is false.

.PARAMETER ControlDebugMode
    Whether to run the control daemon in debug mode. Default is false.

.PARAMETER SkipValidationTests
    Whether to skip the validation tests (fmt, lint etc). They are run by default

.PARAMETER SkipUnitTests
    Whether to skip the unit tests. They are run by default.

.PARAMETER SkipIntegrationTests
    Whether to skip the integration tests. They are run by default.

.PARAMETER SkipCopyGo
    Whether to skip the copying go from the container (eg on a hot cache).

.PARAMETER HyperVControl
    Whether to run the control daemon configured to run containers as
    Hyper-V containers. By default it is not

.PARAMETER HyperVDUT
    Whether to run the daemon under test configured to run containers as
    a Hyper-V container. By default it is not

.PARAMETER SkipClone
    Doesn't do the git clone and checkout and assumes that the Sources
    already exist

.PARAMETER IntegrationTestName
   Name match for the set of integration tests to run. For example 'TestInfo*'

.PARAMETER SkipBinaryBuild
   The binary is not built. 

.PARAMETER SkipZapDUT
   Doesn't zap the daemon under test directory once done.

.PARAMETER SkipImageBuild
   The docker image is not built. 

.PARAMETER SkipAllCleanup
   Doesn't do any cleanup at the end of the tests

.Parameter WindowsBaseImage
   The name of the default base image. If not set, defaults to windowsservercore.
   This is the base image used by the integration tests, not the one used by the
   "docker" image.

.Parameter SkipControlDownload
   Skips the download of docker.exe and dockerd.exe

.Parameter IntegrationInContainer
   Skips the download of docker.exe and dockerd.exe

.Parameter LCOWBasic
   Enables -basic- Linux-Containers-On-Windows (LCOW) mode for daemon under test

.Parameter LCOW
   Enables Linux-Containers-On-Windows (LCOW) mode for daemon under test

.Parameter CaptureHCSTraces
   Enables capturing of HCS tracing through the run
#>

# Note: The first four parameters are the ones which drive the bash script
#   for CI, and are in capitals for bash conventions in docker bash scripts.
#   Subsequent variables are used just by this script to configure
#   the machine to be able to run the bash CI script, install stuff, 
#   checkout the sources and so on. These are set in the environment as
#   that is where the bash script expects to pick them up from.


param(
    [Parameter(Mandatory=$false)][string]$SourcesDrive,
    [Parameter(Mandatory=$false)][string]$SourceSubdir, 
    [Parameter(Mandatory=$false)][string]$TestrunDrive,
    [Parameter(Mandatory=$false)][string]$TestrunSubdir,
    [Parameter(Mandatory=$false)][string]$GitRemote,
    [Parameter(Mandatory=$false)][string]$GitCheckout,
    [Parameter(Mandatory=$false)][switch]$DestroyCache=$False,
    [Parameter(Mandatory=$false)][string]$DockerBasePath = $DOCKER_DEFAULT_BASEPATH,
    [Parameter(Mandatory=$false)][string]$GitLocation = $GIT_DEFAULT_LOCATION,
    [Parameter(Mandatory=$false)][string]$CIScriptLocation = $CISCRIPT_DEFAULT_LOCATION,
    [Parameter(Mandatory=$false)][switch]$DUTDebugMode=$False,
    [Parameter(Mandatory=$false)][switch]$ControlDebugMode=$False,
    [Parameter(Mandatory=$false)][switch]$SkipValidationTests=$False,
    [Parameter(Mandatory=$false)][switch]$SkipUnitTests=$False,
    [Parameter(Mandatory=$false)][switch]$SkipIntegrationTests=$False,
    [Parameter(Mandatory=$false)][switch]$SkipCopyGo=$False,
    [Parameter(Mandatory=$false)][switch]$HyperVControl=$False,
    [Parameter(Mandatory=$false)][switch]$HyperVDUT=$False,
    [Parameter(Mandatory=$false)][switch]$SkipClone=$False,
    [Parameter(Mandatory=$false)][string]$IntegrationTestName,
    [Parameter(Mandatory=$false)][switch]$SkipBinaryBuild=$False,
    [Parameter(Mandatory=$false)][switch]$SkipZapDUT=$False,
    [Parameter(Mandatory=$false)][switch]$SkipImageBuild=$False,
    [Parameter(Mandatory=$false)][switch]$SkipAllCleanup=$False,
    [Parameter(Mandatory=$false)][string]$WindowsBaseImage="",
    [Parameter(Mandatory=$false)][switch]$SkipControlDownload=$False,
    [Parameter(Mandatory=$false)][switch]$IntegrationInContainer=$False,
    [Parameter(Mandatory=$false)][switch]$LCOWBasic=$False,
    [Parameter(Mandatory=$false)][switch]$LCOW=$False,
    [Parameter(Mandatory=$false)][switch]$CaptureHCSTraces=$False
)

$ErrorActionPreference = 'Stop'
$FinallyColour="Cyan"
$DOCKER_DEFAULT_BASEPATH="https://master.dockerproject.org/windows/x86_64"
$GIT_DEFAULT_LOCATION="https://github.com/git-for-windows/git/releases/download/v2.14.1.windows.1/Git-2.14.1-64-bit.exe"
$ConfigJSONBackedUp=$False
$CISCRIPT_DEFAULT_LOCATION = "https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/runCI/executeCI.ps1"
$HCS_TRACE_PROFILE = "https://gist.githubusercontent.com/jhowardmsft/71b37956df0b4248087c3849b97d8a71/raw/72e14a6d2e86d3ccdefea5766d09d6a9fc053f25/HcsTraceProfile.wprp"
$pushed=$False  # To restore the directory if we have temporarily pushed to one.

# Download-File is a simple wrapper to get a file from somewhere (HTTP, SMB or local file path)
# If file is supplied, the source is assumed to be a base path. Returns -1 if does not exist, 
# 0 if success. Throws error on other errors.
Function Download-File([string] $source, [string] $file, [string] $target) {
    $ErrorActionPreference = 'SilentlyContinue'

    # Ensure that all secure protocols are enabled (TLS 1.2 is not by default in some cases).
    $secureProtocols = @()
    $insecureProtocols = @([System.Net.SecurityProtocolType]::SystemDefault, [System.Net.SecurityProtocolType]::Ssl3)
    foreach ($protocol in [System.Enum]::GetValues([System.Net.SecurityProtocolType])) {
        if ($insecureProtocols -notcontains $protocol) { $secureProtocols += $protocol }
    }
    [System.Net.ServicePointManager]::SecurityProtocol = $secureProtocols

    if (($source).ToLower().StartsWith("http")) {
        if ($file -ne "") {
            $source+="/$file"
        }
        # net.webclient is WAY faster than Invoke-WebRequest
        $wc = New-Object net.webclient
        try {
            Write-Host -ForegroundColor green "INFO: Downloading $source..."
            $wc.Downloadfile($source, $target)
        } 
        catch [System.Net.WebException]
        {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if (($statusCode -eq 404) -or ($statusCode -eq 403)) { # master.dockerproject.org returns 403 for some reason!
                return -1
            }
            Throw ("Failed to download $source - $_")
        }
    } else {
        if ($file -ne "") {
            $source+="\$file"
        }
        if ((Test-Path $source) -eq $false) {
            return -1
        }
        $ErrorActionPreference='Stop'
        Copy-Item "$source" "$target"
    }
    $ErrorActionPreference='Stop'
    return 0
}

# Test-CommandExists returns $true if a command exists/is installed on the system
Function Test-CommandExists
{
    Param ($command)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'stop'
    try {if(Get-Command $command){RETURN $true}}
    Catch {RETURN $false}
    Finally {$ErrorActionPreference=$oldPreference}
} 

# Stop-DockerService stops any docker daemon service
Function Stop-DockerService {
    $ErrorActionPreference = 'Stop'
    try {
        $service=get-service docker -ErrorAction SilentlyContinue
        if ($service -ne $null) {
            if ($service.status -eq "running") {
                Write-Host -ForegroundColor green "INFO: Stopping the docker service..."
                stop-service $service -ErrorAction Stop
            }
        }
    }
    catch {
        throw $_
    }
}

# Dismount-MountedVHDs unmounts any VHDs which may be still mounted from a previous run
Function Dismount-MountedVHDs {
    $ErrorActionPreference = 'Stop'
    try {
        Write-Host -ForegroundColor green "INFO: Detaching lingering VHDs..."
        gwmi msvm_mountedstorageimage -namespace root\virtualization\v2 -ErrorAction SilentlyContinue | foreach-object {$_.DetachVirtualHardDisk() }
    } catch {
        Throw $_
    }
}

# Kill-Processes kills any processes which might be locking files.
Function Kill-Processes
{
    Get-Process -Name tail, docker, dockerd*, dockercontrol, dockerdcontrol, cc1, link, compile, ld, go, git, git-remote-https, integration-cli.test -ErrorAction SilentlyContinue | `
        Stop-Process -Force -ErrorAction SilentlyContinue | Wait-Process -ErrorAction SilentlyContinue
}

# Get-Sources does the git work to get the sources being tested
Function Get-Sources
{
    Param([string]$Workspace,
          [string]$GitRemote,
          [string]$GitCheckout)

    Set-PSDebug -Trace 0
    $ErrorActionPreference = 'Stop'

    try {

          
        # Clone the sources into the workspace.
        Write-Host -ForegroundColor green "INFO: Cloning docker sources into $Workspace..."
        #$env:GIT_TERMINAL_PROMPT=0 # Make git not prompt
        $retryCount = 0
        while ($true) {
            # Wipe the workspace where the sources exist
            if ( Test-Path $Workspace -ErrorAction SilentlyContinue ) {
                Write-Host -ForegroundColor green "INFO: Wiping $Workspace..."
                Remove-Item -Recurse -Force $Workspace
            }
            $proc = Start-Process git.exe -ArgumentList "clone https://github.com/moby/moby $Workspace" -NoNewWindow -PassThru 
            try
            {
                $proc | Wait-Process -Timeout 300 -ErrorAction Stop
                if ($proc.ExitCode -ne 0) {
                    Throw "Clone failed"
                }
                Write-Host -ForegroundColor green "INFO: Cloned successfully"
                break
            } catch {
                # No point using Stop-Process as git launches several sub-processes
                Kill-Processes
                if ($retryCount -lt 3) {
                    Write-Warning "Failed to clone, so retrying"
                } else {
                    Throw "Timeout cloning the docker sources"
                }
            }
            $retryCount++
        }

        # Change to our workspace directory
        Set-Location "$Workspace" -ErrorAction stop

        # Add a remote if supplied
        if (-not [string]::IsNullOrWhiteSpace($GitRemote)) {
            Write-Host -ForegroundColor green "INFO: Adding a remote to $GitRemote"
            $proc = Start-Process git.exe -ArgumentList "remote add remote $GitRemote" -NoNewWindow -PassThru 
            try
            {
                $proc | Wait-Process -Timeout 180 -ErrorAction Stop
                if ($proc.ExitCode -ne 0) {
                    Throw "Adding remote failed"
                }
                Write-Host -ForegroundColor green "INFO: Remote added successfully"
            } catch {
                # No point using Stop-Process as git launches several sub-processes
                Kill-Processes
                Throw "Timeout adding a remote to $GitRemote"
            }
        }

        # Fetch from the remote
        if (-not [string]::IsNullOrWhiteSpace($GitRemote)) {
            Write-Host -ForegroundColor green "INFO: Fetching from remote $GitRemote"
            $proc = Start-Process git.exe -ArgumentList "fetch remote" -NoNewWindow -PassThru 
            try
            {
                $proc | Wait-Process -Timeout 180 -ErrorAction Stop
                if ($proc.ExitCode -ne 0) {
                    Throw "Fetching from remote failed"
                }
                Write-Host -ForegroundColor green "INFO: Fetched from remote"
            } catch {
                # No point using Stop-Process as git launches several sub-processes
                Kill-Processes
                Throw "Timeout fetching from $GitRemote"
            }
        }
    
        # Perform a checkout if requested
        if (-not [string]::IsNullOrWhiteSpace($GitCheckout)) {
            if (-not [string]::IsNullOrWhiteSpace($GitRemote)) { $GitCheckout = "remote/$GitCheckout" }
            Write-Host -ForegroundColor green "INFO: Checking out $GitCheckout"
            $proc = Start-Process git.exe -ArgumentList "checkout $GitCheckout" -NoNewWindow -PassThru 
            try
            {
                $proc | Wait-Process -Timeout 180 -ErrorAction Stop
                if ($proc.ExitCode -ne 0) {
                    Throw "Failed to checkout $GitCheckout"
                }
                Write-Host -ForegroundColor green "INFO: Checked out $GitCheckout"
            } catch {
                # No point using Stop-Process as git launches several sub-processes
                Kill-Processes
                Throw "Timeout checking out $GitCheckout"
            }
        }
    
        # Useful to show the last couple of commits in the overall log
        Write-Host "`r`n"
        git log -2
        Write-Host "`r`n"
    }
    catch {
        Throw $_
    }
}

# Get-ImageTar generates the tar from the build share if not already present under \baseimages, and 
# subsequently loads it into the control daemon. Note if the location can't be reached, such as is
# the case for public users off Microsoft corpnet, no error is generated. Instead, we assume that
# the image can be docker pulled, which is generally true for public users. Not so for arbitrary
# nightly Windows builds of any branch though. These must come off the build share.
Function Get-ImageTar {
    Param([string]$Type,
          [string]$BuildName)
          
    $ErrorActionPreference = 'Stop'
    try {
        if (Test-Path c:\baseimages\$type.tar) {
            Write-Host -ForegroundColor green "INFO: c:\baseimages\$type.tar already exists - no need to grab the .tar file"
            return
        }

        $Location="\\winbuilds\release\$Branch\$Build\amd64fre\ContainerBaseOsPkgs"
        if ($(Test-Path $Location) -eq $False) {
            Write-Host -foregroundcolor green $("INFO: Skipping image conversion to c:\BaseImages\"+$type+".tar")
            return
        }

        # Needed on Windows Server 2016 10B (Oct 2016) and later
        #Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
        Install-PackageProvider -Name NuGet -Force

        # https://github.com/microsoft/wim2img (Microsoft Internal)
        Write-Host -ForegroundColor green "INFO: Installing containers module for image conversion"
        Register-PackageSource -Name HyperVDev -Provider PowerShellGet -Location \\sesdfs.corp.microsoft.com\1Windows\TestContent\CORE\Base\HYP\HAT\packages -Trusted -Force | Out-Null
        Install-Module -Name Containers.Layers -Repository HyperVDev | Out-Null
        Import-Module Containers.Layers | Out-Null
            
        $SourceTar=$Location+"\cbaseospkg_"+$BuildName+"_en-us\CBaseOS_"+$Branch+"_"+$Build+"_amd64fre_"+$BuildName+"_en-us.tar.gz"
        Write-Host -foregroundcolor green "INFO: Converting $SourceTar. This may take a few minutes..."

        if (-not(Test-Path "C:\BaseImages")) { mkdir "C:\BaseImages" }
        Export-ContainerLayer -SourceFilePath $SourceTar -DestinationFilePath c:\BaseImages\$type.tar -Repository $("microsoft/"+$Type) -latest

        Write-Host -foregroundcolor green "INFO: Loading $type.tar into the control daemon. This may take a few minutes..."
        docker load -i c:\BaseImages\$type.tar
    } catch {
        Throw $_
    }
}

# Start of the main script. In a try block to catch any exception
Try {
    Write-Host -ForegroundColor Cyan "INFO: Invoke-DockerCI.ps1 starting at $(date)`n"
    set-PSDebug -Trace 0  # 1 to turn on
    $controlDaemonStarted=$false

    # Save environment TEMP 
    $ORIGTEMP=$env:TEMP

    # Start in the root of the system drive
    Push-Location "$env:SystemDrive\"; $global:pushed=$True

    # Set some defaults if they are not defined in the environment
    if ([string]::IsNullOrWhiteSpace($SourcesDrive)) {
        if (-not [string]::IsNullOrWhiteSpace($env:SOURCES_DRIVE)) {
            $SourcesDrive = $env:SOURCES_DRIVE
        } else {
            $SourcesDrive =$Env:SystemDrive.Substring(0,1)
            $env:SOURCES_DRIVE = $SourcesDrive
            Write-Host -ForegroundColor green "INFO: Defaulted SourcesDrive to $SourcesDrive"
        }
    } 

    if ([string]::IsNullOrWhiteSpace($SourcesSubdir)) {
        if (-not [string]::IsNullOrWhiteSpace($env:SOURCES_SUBDIR)) {
            $SourcesSubdir = $env:SOURCES_SUBDIR
        } else {
            $SourcesSubdir= "gopath"
            $env:SOURCES_SUBDIR = $SourcesSubdir
            Write-Host -ForegroundColor green "INFO: Defaulted SourcesSubdir to $SourcesSubdir"
        }
    }

    if ([string]::IsNullOrWhiteSpace($TestrunDrive)) {
        if (-not [string]::IsNullOrWhiteSpace($env:TESTRUN_DRIVE)) {
            $TestrunDrive = $env:TESTRUN_DRIVE
        } else {
            $TestrunDrive = $Env:SystemDrive.Substring(0,1)
            $env:TESTRUN_DRIVE = $TestrunDrive
            Write-Host -ForegroundColor green "INFO: Defaulted TestrunDrive to $TestrunDrive"
        }
    }

    if ([string]::IsNullOrWhiteSpace($TestrunSubdir)) {
        if (-not [string]::IsNullOrWhiteSpace($env:TESTRUN_SUBDIR)) {
            $TestrunSubdir = $env:TESTRUN_SUBDIR
        } else {
            $TestrunSubdir="CI"
            $env:TESTRUN_SUBDIR = $TestrunSubdir
            Write-Host -ForegroundColor green "INFO: Defaulted TestrunSubdir to $TestrunSubdir"
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($IntegrationTestName)) {
        $env:INTEGRATION_TEST_NAME = $IntegrationTestName
    }
    $env:DOCKER_DUT_DEBUG=""
    if ($DUTDebugMode) {
        $env:DOCKER_DUT_DEBUG = "Yes, debug daemon under test"
    }
    $env:SKIP_VALIDATION_TESTS = ""
    if ($SkipValidationTests) {
        $env:SKIP_VALIDATION_TESTS = "Yes"
    }
    $env:SKIP_UNIT_TESTS=""
    if ($SkipUnitTests) {
        $env:SKIP_UNIT_TESTS = "Yes"
    }
    $env:SKIP_INTEGRATION_TESTS=""
    if ($SkipIntegrationTests) {
        $env:SKIP_INTEGRATION_TESTS = "Yes"
    }
    $env:INTEGRATION_IN_CONTAINER=""
    if ($IntegrationInContainer) {
        $env:INTEGRATION_IN_CONTAINER = "Yes"
    }
    $env:LCOW_BASIC_MODE=""
    if ($LCOWBasic) {
        $env:LCOW_BASIC_MODE = "Yes"
    }
    $env:LCOW_MODE=""
    if ($LCOW) {
        $env:LCOW_MODE = "Yes"
    }
    $env:SKIP_COPY_GO=""
    if ($SkipCopyGo) {
        $env:SKIP_COPY_GO = "Yes"
    }
    $env:SKIP_BINARY_BUILD=""
    if ($SkipBinaryBuild) {
        $env:SKIP_BINARY_BUILD = "Yes"
    }
    $env:DOCKER_DUT_HYPERV=""
    if ($HyperVDUT) {
        $env:DOCKER_DUT_HYPERV = "Yes"
    }
    $env:SKIP_ZAP_DUT=""
    if ($SkipZapDUT) {
        $env:SKIP_ZAP_DUT = "Yes"
    }
    $env:SKIP_IMAGE_BUILD=""
    if ($SkipImageBuild) {
        $env:SKIP_IMAGE_BUILD = "Yes"
    }
    $env:SKIP_ALL_CLEANUP=""
    if ($SkipAllCleanup) {
        $env:SKIP_ALL_CLEANUP = "Yes"
    }
    # Set some default values
    if ([string]::IsNullOrWhiteSpace($DockerBasePath)) {
        # Default to master.dockerproject.org
        $DockerBasePath=$DOCKER_DEFAULT_BASEPATH
    }
    if ([string]::IsNullOrWhiteSpace($GitLocation)) {
        $GitLocation = $GIT_DEFAULT_LOCATION
    }
    if ([string]::IsNullOrWhiteSpace($CIScriptLocation)) {
        $CIScriptLocation = $CISCRIPT_DEFAULT_LOCATION
    }

    # Where we run the control daemon from
    $ControlRoot="$($TestrunDrive):\control"

    # Get the build 
    $bl=(Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion"  -Name BuildLabEx).BuildLabEx
    $a=$bl.ToString().Split(".")
    $Branch=$a[3]
    $Build=$a[0]+"."+$a[1]+"."+$a[4]
    Write-Host -ForegroundColor green "INFO: Branch:$Branch Build:$Build"

    Write-Host -ForegroundColor green "INFO: Configuration:`n"
    Write-Host -ForegroundColor yellow "Paths"
    Write-Host " - Sources:           $SourcesDrive`:\$SourcesSubdir"
    Write-Host " - Test run:          $TestrunDrive`:\$TestrunSubdir"
    Write-Host " - Control daemon:    $ControlRoot"
    Write-Host  -ForegroundColor yellow "Git"
    if (-not [string]::IsNullOrWhiteSpace($GitRemote)) { Write-Host " - Remote:            $GitRemote" }
    if (-not [string]::IsNullOrWhiteSpace($GitCheckout)) { Write-Host " - Checkout:          $GitCheckout" }
    Write-Host " - Skip clone:        $SkipClone"
    Write-Host " - Installer:         $GitLocation"
    Write-Host  -ForegroundColor yellow "Debug"
    Write-Host " - Daemon under test: $DUTDebugMode"
    Write-Host " - Control daemon:    $ControlDebugMode"
    Write-Host  -ForegroundColor yellow "Skip tests"
    Write-Host " - Validation:        $SkipValidationTests"
    Write-Host " - Unit:              $SkipUnitTests"
    Write-Host " - Integration:       $SkipIntegrationTests"
    Write-Host  -ForegroundColor yellow "Hyper-V Containers"
    Write-Host " - Control daemon:    $HyperVControl"
    Write-Host " - Daemon under test: $HyperVDUT"
    Write-Host  -ForegroundColor yellow "Miscellaneous"
    Write-Host " - Destroy Cache:     $DestroyCache"
    Write-Host " - Control binaries:  $DockerBasePath"
    Write-Host " - CI Script:         $CIScriptLocation"
    Write-Host " - Skip binary build: $SkipBinaryBuild"
    Write-Host " - Skip zap DUT dir:  $SkipZapDUT"
    Write-Host " - Skip image build:  $SkipImageBuild"
    Write-Host " - Skip all cleanup:  $SkipAllCleanup"
    Write-Host " - Skip download:     $SkipControlDownload"
    Write-Host " - Skip copy go:      $SkipCopyGo"
    Write-Host " - Test in container: $IntegrationInContainer"
    Write-Host " - LCOW Basic Mode:   $LCOWBasic"
    Write-Host " - LCOW (Full) Mode:  $LCOW"
    Write-Host " - HCS Tracing:       $CaptureHCSTraces"
    if ($SkipIntegrationTests -eq $false) {
        if (-not ([string]::IsNullOrWhiteSpace($IntegrationTestName))) {
            Write-Host " - CLI test match:    $IntegrationTestName"
        }
    }
    if (-not ([string]::IsNullOrWhiteSpace($WindowsBaseImage))) {
        Write-Host " - Base image:        $WindowsBaseImage"
        $env:WINDOWS_BASE_IMAGE=$WindowsBaseImage # Pass through to executeCI.ps1
    }
    Write-Host "`n"

    # Where we clone the docker sources
    $WorkspaceRoot="$($SourcesDrive):\$($SourcesSubdir)"
    $Workspace="$WorkspaceRoot\src\github.com\docker\docker"

    if (-not(Test-Path "C:\CIUtilities")) { mkdir "C:\CIUtilities" | Out-Null }

    # Make sure we have the git posix utilities at the front of our path (overwrites find etc), and
    # also the GO bin directories. We also deliberately put $env:Temp there early so that the
    # docker.exe we are using is the one we downloaded above. Also configure GO environment variables
    if (-not ($env:PATH -like $("*"+$env:TEMP+"*"))) { $env:Path = "$env:TEMP;$env:Path" }
    if (-not ($env:PATH -like '*c:\gopath\bin*'))    { $env:Path = "c:\gopath\bin;$env:Path" }
    if (-not ($env:PATH -like '*c:\go\bin*'))        { $env:Path = "c:\go\bin;$env:Path" }
    if (-not ($env:PATH -like '*c:\git\usr\bin*'))   { $env:Path = "c:\git\usr\bin;$env:Path" }
    if (-not ($env:PATH -like '*c:\git\bin*'))       { $env:Path = "c:\git\bin;$env:Path" }
    if (-not ($env:PATH -like '*c:\git\cmd*'))       { $env:Path = "c:\git\cmd;$env:Path" }
    if (-not ($env:PATH -like '*c:\CIUtilities*'))   { $env:Path = "c:\CIUtilities;$env:Path" }

    $env:GOROOT="c:\go"
    $env:GOPATH="$WorkspaceRoot"

    # Turn off defender to make things run significantly faster
    Write-Host -ForegroundColor green "INFO: Disabling Windows Defender for performance..."
    set-mppreference -disablerealtimemonitoring $true -ErrorAction Stop

    # Stop the docker service if running.
    Stop-DockerService

    # Terminate processes which might be running
    Kill-Processes

    # In the RITP under T3T, we may not be in a clean state, and C:\ProgramData\docker\config\daemon.json may exist.
    # See OS#8699803. So now we've killed the processes, if the file exists, then rename it so that
    # it doesn't conflict, and we'll put it back to how it was at the end.
    if (Test-Path "$env:ProgramData\docker\config\daemon.json") {
        Write-Host -ForegroundColor green "INFO: $env:ProgramData\docker\config\daemon.json exists. Renaming temporarily to a .CIbackup file"
        Rename-Item "$env:ProgramData\docker\config\daemon.json" "$env:ProgramData\docker\config\daemon.CIBackup" -ErrorAction SilentlyContinue
        $ConfigJSONBackedUp=$True
    }

    # Detach any VHDs just in case there are lingerers
    Dismount-MountedVHDs

    if (-not $SkipControlDownload) {
        # Download docker.exe for the control daemon in single binary mode. In dual
        # binary mode, downloads docker.exe for the control client, dockerd.exe for
        # the control daemon
        Write-Host -ForegroundColor green "INFO: Control docker base path $DockerBasePath"
        Remove-Item "$env:Temp\docker.exe" -Erroraction SilentlyContinue
        Remove-Item "$env:Temp\dockercontrol.exe" -Erroraction SilentlyContinue
        Remove-Item "$env:Temp\dockerd.exe" -Erroraction SilentlyContinue
        Remove-Item "$env:Temp\dockerdcontrol.exe" -Erroraction SilentlyContinue

        # Download docker.exe client binary. 
        if (0 -ne (Download-File "$DockerBasePath" "docker.exe" "$env:Temp\docker.exe")) {
            Throw "Download docker failed"
        }
        Copy-Item "$env:Temp\docker.exe" "$env:Temp\dockercontrol.exe"

        # Download dockerd.exe daemon binary. 
        if (0 -ne (Download-file "$DockerBasePath" "dockerd.exe" "$env:Temp\dockerd.exe")) {
            Throw "Download dockerd.exe failed"
        }
        Copy-Item "$env:Temp\dockerd.exe" "$env:Temp\dockerdcontrol.exe"
    } else {
        Write-Host -ForegroundColor Magenta "WARN: Skipping control docker*.exe downloads"
    }

    # Install git if not already installed
    if (-not (Test-CommandExists git)) {
        Remove-Item "$env:Temp\gitinstaller.exe" -Erroraction SilentlyContinue
        Write-Host -ForegroundColor green "INFO: Git installer $GitLocation"
        $r=Download-File "$GitLocation" "" "$env:Temp\gitinstaller.exe"
        Unblock-File "$env:Temp\gitinstaller.exe" -ErrorAction Stop
        Write-Host -ForegroundColor green "INFO: Installing git..."
        $installPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        $installItem = 'Git_is1'
        New-Item -Path $installPath -Name $installItem -Force
        $installKey = $installPath+'\'+$installItem
        New-ItemProperty $installKey -Name 'Inno Setup CodeFile: Path Option' -Value 'CmdTools' -PropertyType 'String' -Force
        New-ItemProperty $installKey -Name 'Inno Setup CodeFile: Bash Terminal Option' -Value 'ConHost' -PropertyType 'String' -Force
        New-ItemProperty $installKey -Name 'Inno Setup CodeFile: CRLF Option' -Value 'CRLFCommitAsIs' -PropertyType 'String' -Force
        Start-Process -Wait "$env:Temp\gitinstaller.exe" -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /CLOSEAPPLICATIONS /DIR=c:\git' -ErrorAction Stop

        # Don't think needed for git 2.8 and later
        ## Set the path for the machine (as the installer doesn't seem to do it) AND for the current process.
        #[Environment]::SetEnvironmentVariable("Path","c:\git\bin;c:\git\usr\bin;$env:Path", "Machine")
        $env:Path="c:\git\bin;c:\git\usr\bin;$env:Path"
    }

    # Clone the sources of the repo being tested
    if (-not $SkipClone) {
        Get-Sources $Workspace $GitRemote $GitCheckout
    } else {
        Write-Host -ForegroundColor green "INFO: Skipping clone. Assuming sources are in $Workspace"
    }

    if (-not (Test-Path "c:\CIUtilities\docker-ci-zap.exe")) {
        $r=Download-File "https://github.com/jhowardmsft/docker-ci-zap/raw/master/docker-ci-zap.exe" "" "c:\CIUtilities\docker-ci-zap.exe"
        Unblock-File "c:\CIUtilities\docker-ci-zap.exe" -ErrorAction Stop
    }

    if (-not (Test-Path "c:\CIUtilities\docker-signal.exe")) {
        $r=Download-File "https://github.com/jhowardmsft/docker-signal/raw/master/docker-signal.exe" "" "c:\CIUtilities\docker-signal.exe"
        Unblock-File "c:\CIUtilities\docker-signal.exe" -ErrorAction Stop
    }

    if (-not (Test-Path "c:\CIUtilities\HcsTraceProfile.wprp")) {
        $r=Download-File $HCS_TRACE_PROFILE "" "c:\CIUtilities\HcsTraceProfile.wprp"
    }

    if ($CaptureHCSTraces) {
        Write-Host -ForegroundColor green "INFO: Starting HCS Argon tracing"
        Wpr.exe -start "c:\CIUtilities\HcsTraceProfile.wprp!HcsArgon" -filemode
    }
	
    # Zap the control daemons path if asked to destroy the cache
    if ( Test-Path $ControlRoot -ErrorAction SilentlyContinue ) {
        if ($DestroyCache -eq $true) {
            Write-Host -ForegroundColor green "INFO: Zapping $ControlRoot..."
            docker-ci-zap "-folder=$ControlRoot"
        } else {
            Write-Host -ForegroundColor green "INFO: Keeping control daemon cache hot"
            Remove-Item "$ControlRoot\daemon\docker.pid" -ErrorAction SilentlyContinue | Out-Null
        }
    }

    # Create the directories for starting the control daemon. OK if these fail (hot cache)
    Write-Host -ForegroundColor green "INFO: Preparing $ControlRoot..."
    New-Item "$ControlRoot\daemon" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    New-Item "$ControlRoot\graph" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
 
    # Download the CI script
    Write-Host -ForegroundColor green "INFO: CI script $CIScriptLocation"
    if (Test-Path "$ControlRoot\CIScript.ps1") { Remove-Item "$ControlRoot\CIScript.ps1" }
    $r=Download-File "$CIScriptLocation" "" "$ControlRoot\CIScript.ps1"

    # Update GOPATH now everything is installed
    $env:GOPATH="$WorkspaceRoot\src\github.com\docker\docker\vendor;$WorkspaceRoot"
   

    # Always by default use the named pipe. We override this for loading images as TCP is faster there.
    $env:DOCKER_HOST="npipe:////./pipe/docker_engine"

    # Start the control daemon
    $daemon="$env:Temp\dockerdcontrol.exe --data-root $ControlRoot --pidfile=$ControlRoot\daemon\docker.pid -H=$env:DOCKER_HOST -H=tcp://0.0.0.0:2375"
    if ($HyperVControl -eq $True) {
        $daemon=$daemon+" --exec-opt isolation=hyperv"
    }
    if ($ControlDebugMode -eq $True) {
        $daemon=$daemon+" -D"
    }
    Write-Host -ForegroundColor green "INFO: Starting a control daemon..."
    $controlDaemonStarted=$true
    $control=start-process "cmd" -ArgumentList "/s /c $daemon > $ControlRoot\daemon\daemon.log 2>&1" -WindowStyle Minimized
    $tail = start-process "tail" -ArgumentList "-f $ControlRoot\daemon\daemon.log" -ErrorAction SilentlyContinue

    # Verify we can get the control daemon to respond
    $tries=20
    Write-Host -ForegroundColor Green "INFO: Waiting for the control daemon to start..."
    while ($true) {
        $ErrorActionPreference = "SilentlyContinue"
        & "$env:TEMP\dockercontrol" version 2>&1 | Out-Null
        $ErrorActionPreference = "Stop"
        if ($LastExitCode -eq 0) {
            break
        }

        $tries--
        if ($tries -le 0) {
            Throw "ERROR: Failed to get a response from the control daemon"
        }
        Write-Host -NoNewline "."
        sleep 1
    }
    Write-Host -ForegroundColor Green "`nINFO: Control daemon started and replied!"

    # Attempt to cache the tar image for windowsservercore if not on disk. 
    if ($(docker images | select -skip 1 | select-string "windowsservercore" | Measure-Object -line).Lines -lt 1) {
        $installWSC=$true
        Write-Host -ForegroundColor green "INFO: windowsservercore is not installed as an image in the control daemon"
        Get-ImageTar "windowsservercore" "serverdatacentercore"
    }
    
    # Attempt to cache the tar image for nanoserver if not on disk
    if ($(docker images | select -skip 1 | select-string "nanoserver" | Measure-Object -line).Lines -lt 1) {
        Write-Host -ForegroundColor green "INFO: nanoserver is not installed as an image in the control daemon"
        Get-ImageTar "nanoserver" "nanoserver"
    }

    # Invoke the CI script itself.
    Write-Host -ForegroundColor cyan "INFO: Starting $TestrunDrive`:\control\CIScript.ps1"
    Try { & "$TestrunDrive`:\control\CIScript.ps1" }
    Catch [Exception] { Throw "CI script failed, so quitting Invoke-DockerCI with error $_" }

    Write-Host -ForegroundColor green "INFO: $TestrunDrive`:\control\CIScript.ps1 succeeded!!!"
}
Catch [Exception] {
    Write-Host -ForegroundColor Red "`n---------------------------------------------------------------------------"
    Write-Host -ForegroundColor Red ("ERROR: Overall CI run has failed with error:`n '$_'")
    Write-Host -ForegroundColor Red "---------------------------------------------------------------------------`n"
    $FinallyColour="Red"
    Throw $_
}
Finally {
    Kill-Processes
    $env:TEMP=$ORIGTEMP

    # Save the daemon under test log
    if ($controlDaemonStarted -eq $true) {
        if (Test-Path "$ControlRoot\daemon\daemon.log") {
            Write-Host -ForegroundColor green "INFO: Saving the control daemon log $ControlRoot\daemon\daemon.log to $ORIGTEMP\CIDControl.log"
            Copy-Item "$ControlRoot\daemon\daemon.log" "$ORIGTEMP\CIDControl.log" -Force -ErrorAction SilentlyContinue
        }
    }

    if ($CaptureHCSTraces) {
        Write-Host -ForegroundColor green "INFO: Stopping HCS Argon tracing"
       if (Test-Path "$ORIGTEMP\HcsTrace.etl") {
           Remove-Item "$ORIGTEMP\HcsTrace.etl" -ErrorAction SilentlyContinue -Force | Out-Null
        }
        Wpr.exe -stop "$ORIGTEMP\HcsTrace.etl" "Hcs Argon Tracing"
        Write-Host -foregroundcolor green "INFO: HCS Argon tracing saved to $ORIGTEMP\HcsTrace.etl"
    }


    if ($ConfigJSONBackedUp -eq $true) {
        Write-Host -ForegroundColor green "INFO: Restoring $env:ProgramData\docker\config\daemon.json"
        Rename-Item "$env:ProgramData\docker\config\daemon.CIBackup" "$env:ProgramData\docker\config\daemon.json" -ErrorAction SilentlyContinue
    }

    if ($global:pushed) { Pop-Location }
    
    Write-Host -ForegroundColor $FinallyColour "`nINFO: Invoke-DockerCI.ps1 exiting at $(date)"
}
