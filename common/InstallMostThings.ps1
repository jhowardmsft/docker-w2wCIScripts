#-----------------------
# InstallMostThings.ps1
#-----------------------


# Version configuration. We put them here rather than in packer variables so that this script block can be run on any machine,
# not just a CI server. Note Git is a full location, not a version as interim releases have more than just the version in the path.
echo "$(date) InstallMostThings.ps1 starting" >> $env:SystemDrive\packer\configure.log

$GIT_LOCATION="https://github.com/git-for-windows/git/releases/download/v2.16.2.windows.1/PortableGit-2.16.2-64-bit.7z.exe" #2/26/2018
#$JDK_LOCATION="http://download.oracle.com/otn-pub/java/jdk/8u144-b01/090f390dda5b47b9b721c7dfaa008135/jdk-8u144-windows-x64.exe" #8/14/2017
#$JDK_LOCATION="http://download.oracle.com/otn-pub/java/jdk/9.0.1+11/jdk-9.0.1_windows-x64_bin.exe"
$JDK_LOCATION="https://winrs1.blob.core.windows.net/jdk/jdk-8u151-windows-x64.exe"
$NPP_LOCATION="https://notepad-plus-plus.org/repository/7.x/7.5.4/npp.7.5.4.Installer.x64.exe" # 2/26/2018
$DOCKER_LOCATION="https://master.dockerproject.org/windows/x86_64"
$DELVE_LOCATION="github.com/derekparker/delve/cmd/dlv"


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
        } else {  
            $webClient = New-Object System.Net.WebClient  
            $webClient.DownloadFile($SourcePath, $DestinationPath)  
        }   
    } else {  
        throw "Cannot copy from $SourcePath"  
    }  
}  

echo "$(date)  Git:           $GIT_LOCATION"    >> $env:SystemDrive\packer\configure.log
if ($env:LOCAL_CI_INSTALL -ne 1) {echo "$(date)  JDK:           $JDK_LOCATION"         >> $env:SystemDrive\packer\configure.log }
echo "$(date)  Notepad++:     $NPP_LOCATION"         >> $env:SystemDrive\packer\configure.log
echo "$(date)  Docker:        $DOCKER_LOCATION"      >> $env:SystemDrive\packer\configure.log


try {

    # Create directory for our local run scripts
    mkdir $env:SystemDrive\scripts -ErrorAction SilentlyContinue 2>&1 | Out-Null

    # Set PATH for machine and current session
    echo "$(date) InstallMostThings.ps1 Updating path" >> $env:SystemDrive\packer\configure.log
    if ($env:LOCAL_CI_INSTALL -eq 1) {
        if (-not ($env:PATH -like '*c:\gopath\bin*'))    { $env:Path = "c:\gopath\bin;$env:Path" }
        if (-not ($env:PATH -like '*c:\go\bin*'))        { $env:Path = "c:\go\bin;$env:Path" }
    } else {
        if (-not ($env:PATH -like '*c:\jdk\bin*'))       { $env:Path = "c:\jdk\bin;$env:Path" }
    }
    if (-not ($env:PATH -like '*c:\gcc\bin*'))                 { $env:Path = "c:\gcc\bin;$env:Path" }
    if (-not ($env:PATH -like '*c:\git\usr\bin*'))             { $env:Path = "c:\git\usr\bin;$env:Path" }
    if (-not ($env:PATH -like '*c:\git\bin*'))                 { $env:Path = "c:\git\bin;$env:Path" }
    if (-not ($env:PATH -like '*c:\git\cmd*'))                 { $env:Path = "c:\git\cmd;$env:Path" }
    if (-not ($env:PATH -like '*c:\CIUtilities*'))             { $env:Path = "c:\CIUtilities;$env:Path" }
    if (-not ($env:PATH -like '*c:\Program Files\Notepad++*')) { $env:Path = "c:\Program Files\Notepad++;$env:Path" }
    if (-not ($env:PATH -like '*c:\pstools*'))                 { $env:Path = "c:\pstools;$env:Path" }
    setx "PATH" "$env:PATH" /M

    # Only need golang, delve locally if this is a dev VM
    # While it might see weird we don't need go, it's because we copy the version of GO out of the image
    # to ensure it's consistent.
    if ($env:LOCAL_CI_INSTALL -eq 1) {
        # Work out the version of GO from dockerfile.Windows currently on master
        echo "$(date) InstallMostThings.ps1 Working out GO version..." >> $env:SystemDrive\packer\configure.log
        Copy-File -SourcePath "https://raw.githubusercontent.com/docker/docker/master/Dockerfile.windows" -DestinationPath "$env:Temp\dockerfile.Windows"
        $pattern=select-string $env:Temp\dockerfile.windows -pattern "GO_VERSION="
        if ($pattern.Count -lt 1) {
            Throw "Could not find GO_VERSION= in dockerfile.Windows!"
        }
        $line=$pattern[0]
        $line=$line -replace "\\",""
        $line=$line -replace("``","")
        $line=$line.TrimEnd()
        $index=$line.indexof("=")
        if ($index -eq -1) {
            Throw "Could not find '=' in the GO_VERSION line of dockerfile.Windows"
        }
        $GO_VERSION=$line.Substring($index+1)
        echo "$(date) InstallMostThings.ps1 Need GO version $GO_VERSION" >> $env:SystemDrive\packer\configure.log

        # Download and install golang, plus set GOROOT and GOPATH for machine and current session.
        echo "$(date) InstallMostThings.ps1 Downloading go..." >> $env:SystemDrive\packer\configure.log
        if (-not (Test-Nano)) {
            Copy-File -SourcePath "https://storage.googleapis.com/golang/go$GO_VERSION.windows-amd64.msi" -DestinationPath "$env:Temp\go.msi"
            echo "$(date) InstallMostThings.ps1 Installing go..." >> $env:SystemDrive\packer\configure.log
            Start-Process msiexec -ArgumentList "-i $env:Temp\go.msi -quiet" -Wait
        } else {
            Copy-File -SourcePath "https://storage.googleapis.com/golang/go$GO_VERSION.windows-amd64.zip" -DestinationPath "$env:Temp\go.zip"
            echo "$(date) InstallMostThings.ps1 Extracting go..." >> $env:SystemDrive\packer\configure.log
            Expand-Archive $env:Temp\go.zip $env:SystemDrive\ -Force
        }
        echo "$(date) InstallMostThings.ps1 Updating GOROOT and GOPATH..." >> $env:SystemDrive\packer\configure.log
        $env:GOROOT="$env:SystemDrive\go"
        $env:GOPATH="$env:SystemDrive\gopath"
        setx "GOROOT" "$env:GOROOT" /M  # persist
    }

    # Only need GCC if this is a dev VM (and want to build locally)
    if ($env:LOCAL_CI_INSTALL -eq 1) {
        echo "$(date) InstallMostThings.ps1 Downloading compiler 1 of 3..." >> $env:SystemDrive\packer\configure.log
        Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-tdmgcc/master/gcc.zip" -DestinationPath "$env:Temp\gcc.zip"
         echo "$(date) InstallMostThings.ps1 Downloading compiler 2 of 3..." >> $env:SystemDrive\packer\configure.log
        Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-tdmgcc/master/runtime.zip" -DestinationPath "$env:Temp\runtime.zip"
        echo "$(date) InstallMostThings.ps1 Downloading compiler 3 of 3..." >> $env:SystemDrive\packer\configure.log
        Copy-File -SourcePath "https://raw.githubusercontent.com/jhowardmsft/docker-tdmgcc/master/binutils.zip" -DestinationPath "$env:Temp\binutils.zip"
        echo "$(date) InstallMostThings.ps1 Extracting compiler 1 of 3..." >> $env:SystemDrive\packer\configure.log
        Expand-Archive $env:Temp\gcc.zip $env:SystemDrive\gcc -Force
        echo "$(date) InstallMostThings.ps1 Extracting compiler 2 of 3..." >> $env:SystemDrive\packer\configure.log
        Expand-Archive $env:Temp\runtime.zip $env:SystemDrive\gcc -Force
        echo "$(date) InstallMostThings.ps1 Extracting compiler 3 of 3..." >> $env:SystemDrive\packer\configure.log
        Expand-Archive $env:Temp\binutils.zip $env:SystemDrive\gcc -Force
    }

    # Download and install git
    echo "$(date) InstallMostThings.ps1 Downloading git..." >> $env:SystemDrive\packer\configure.log
    Copy-File -SourcePath "$GIT_LOCATION" -DestinationPath "$env:Temp\gitsetup.7z.exe"
    echo "$(date) InstallMostThings.ps1 installing PS7Zip package..." >> $env:SystemDrive\packer\configure.log
    Install-Package PS7Zip -Force | Out-Null
    echo "$(date) InstallMostThings.ps1 importing PS7Zip..." >> $env:SystemDrive\packer\configure.log
    Import-Module PS7Zip -Force
    New-Item C:\git -ItemType Directory -erroraction SilentlyContinue| Out-Null
    Push-Location C:\git
    echo "$(date) InstallMostThings.ps1 extracting git..." >> $env:SystemDrive\packer\configure.log
    Expand-7Zip "$env:Temp\gitsetup.7z.exe" | Out-Null
    Pop-Location

    # Perform an initial clone so that we can do a local verification outside of jenkins through c:\scripts\doit.sh
    if ($env:LOCAL_CI_INSTALL -ne 1) {
        echo "$(date) InstallMostThings.ps1 Cloning docker sources..." >> $env:SystemDrive\packer\configure.log
        Start-Process -wait git -ArgumentList "clone https://github.com/docker/docker $env:SystemDrive\gopath\src\github.com\docker\docker"
    }

    # Install delve debugger (after GIT is installed) if on a dev VM
    if ($env:LOCAL_CI_INSTALL -eq 1) {
        echo "$(date) InstallMostThings.ps1 Installing delve..." >> $env:SystemDrive\packer\configure.log
        go get $DELVE_LOCATION
    }

    # Keep for reference. This is how you might download OpenSSH-Win64
    # Download and extract OpenSSH-Win64  
    #if ($env:LOCAL_CI_INSTALL -ne 1) {
    #    echo "$(date) Phase1.ps1 downloading OpenSSH..." >> $env:SystemDrive\packer\configure.log
    #    mkdir $env:SystemDrive\OpenSSH-Win64 -erroraction silentlycontinue 2>&1 | Out-Null
    #    $wc=New-Object net.webclient;$wc.Downloadfile("https://github.com/PowerShell/Win32-OpenSSH/releases/download/5_30_2016/OpenSSH-Win64.zip","$env:Temp\OpenSSH-Win64.zip")
    #    echo "$(date) Phase1.ps1 unzipping OpenSSH-Win64..." >> $env:SystemDrive\packer\configure.log
    #    Expand-Archive $env:Temp\OpenSSH-Win64.zip "$env:SystemDrive\" -Force
    #}

    # Keep for reference. This is how you might setup OpenSSH-Win64. Unfortunately, while it connects, I just cannot
    # get it to work with mingw and remove cygwin. I'd really rather the Jenkins SSH plugin were smart enough to
    # know it's at a cmd prompt, not a cygwin shell prompt. The steps below would be for phase 4.
    # cd c:\OpenSSH-Win64\
    # .\Install-SSHD.ps1
    # .\Install-SSHLSA.ps1
    # .\ssh-keygen -A
    # "PasswordAuthentication no`n" | Out-File -Append .\sshd_config -Encoding utf8
    # mkdir $env:SystemDrive\users\$env:USERNAME\.ssh
    # Copy-Item $env:SystemDrive\packer\authorized_keys $env:SystemDrive\users\$env:USERNAME\.ssh
    # Set-Service sshd -StartupType Automatic
    # Set-Service ssh-agent -StartupType Automatic
    # net start sshd

    echo "$(date) InstallMostThings.ps1 Downloading utilities..." >> $env:SystemDrive\packer\configure.log
    if (-not(Test-Path "C:\CIUtilities")) { mkdir "C:\CIUtilities" | Out-Null }
    if (-not (Test-Path "c:\CIUtilities\docker-ci-zap.exe")) {
        Copy-File -SourcePath "https://github.com/jhowardmsft/docker-ci-zap/raw/master/docker-ci-zap.exe" -DestinationPath "c:\CIUtilities\docker-ci-zap.exe"
        Unblock-File "c:\CIUtilities\docker-ci-zap.exe" -ErrorAction Stop
    }

    if (-not (Test-Path "c:\CIUtilities\docker-signal.exe")) {
        Copy-File -SourcePath "https://github.com/jhowardmsft/docker-signal/raw/master/docker-signal.exe" -DestinationPath "c:\CIUtilities\docker-signal.exe"
        Unblock-File "c:\CIUtilities\docker-signal.exe" -ErrorAction Stop
    }

    # Download docker client
    echo "$(date) InstallMostThings.ps1 Downloading docker.exe..." >> $env:SystemDrive\packer\configure.log
    Copy-File -SourcePath "$DOCKER_LOCATION/docker.exe" -DestinationPath "$env:SystemRoot\System32\docker.exe"

    # Download docker daemon
    echo "$(date) InstallMostThings.ps1 Downloading dockerd.exe..." >> $env:SystemDrive\packer\configure.log
    Copy-File -SourcePath "$DOCKER_LOCATION/dockerd.exe" -DestinationPath "$env:SystemRoot\System32\dockerd.exe"

    if (-not (Test-Nano)) {
        # Download and install Notepad++
        echo "$(date) InstallMostThings.ps1 Downloading Notepad++..." >> $env:SystemDrive\packer\configure.log
        $wc=New-Object net.webclient;$wc.Downloadfile($NPP_LOCATION,"$env:Temp\nppinstaller.exe")
        echo "$(date) InstallMostThings.ps1 Installing Notepad++..." >> $env:SystemDrive\packer\configure.log
        Start-Process -wait $env:Temp\nppinstaller.exe -ArgumentList "/S"
    }

    # Download and install PSTools
    echo "$(date) InstallMostThings.ps1 Downloading PSTools..." >> $env:SystemDrive\packer\configure.log
    Copy-File -SourcePath "https://download.sysinternals.com/files/PSTools.zip" -DestinationPath "$env:Temp\pstools.zip"
    echo "$(date) InstallMostThings.ps1 Installing PSTools..." >> $env:SystemDrive\packer\configure.log
    Expand-Archive $env:Temp\pstools.zip c:\pstools

    if (-not (Test-Nano)) {
        # Stop Server Manager from opening at logon
        echo "$(date) InstallMostThings.ps1 Turning off server manager at logon..." >> $env:SystemDrive\packer\configure.log
        REG ADD "HKLM\SOFTWARE\Microsoft\ServerManager" /v DoNotOpenServerManagerAtLogon /t REG_DWORD /d 1 /f | Out-Null
    }

    # BUGBUG This could be problematic with Copy-File
    # Download and install Java Development Kit if not a development VM. Needed for Jenkins connectivity.
    # http://stackoverflow.com/questions/10268583/downloading-java-jdk-on-linux-via-wget-is-shown-license-page-instead
    if (-not (Test-Nano)) {
        if ($env:LOCAL_CI_INSTALL -ne 1) {
            echo "$(date) InstallMostThings.ps1 Downloading JDK..." >> $env:SystemDrive\packer\configure.log
            $wc=New-Object net.webclient;
            $wc.Headers.Set("Cookie","oraclelicense=accept-securebackup-cookie")
            $wc.Downloadfile("$JDK_LOCATION","$env:Temp\jdkinstaller.exe")
            echo "$(date) InstallMostThings.ps1 Installing JDK..." >> $env:SystemDrive\packer\configure.log
            Start-Process -Wait "$env:Temp\jdkinstaller.exe" -ArgumentList "/s /INSTALLDIRPUBJRE=$env:SystemDrive\jdk"
        }
    }

    # Download slave.jar from Jenkins
    # Keep for reference. Just in case can get off SSH due to other reasons.
    #$JAR_LOCATION="http://jenkins.dockerproject.org/jnlpJars/slave.jar"
    #if ($env:LOCAL_CI_INSTALL -ne 1) { echo "$(date)  Jenkins JAR:   $JAR_LOCATION"         >> $env:SystemDrive\packer\configure.log }
    #if ($env:LOCAL_CI_INSTALL -ne 1) {
    #    Use Copy-Item for nanoserver compatibility...
    #    Invoke-WebRequest http://jenkins.dockerproject.org/jnlpJars/slave.jar -OutFile slave.jar
    #    echo "$(date) InstallMostThings.ps1 Downloading slave.jar from Jenkins..." >> $env:SystemDrive\packer\configure.log
    #    $wc=New-Object net.webclient;
    #    $wc.Downloadfile("$JAR_LOCATION","$env:Temp\slave.jar")
    #}

}
Catch [Exception] {
    echo "$(date) InstallMostThings.ps1 Error '$_'" >> $env:SystemDrive\packer\configure.log
    Throw $_
}
Finally {
    echo "$(date) InstallMostThings.ps1 Completed." >> $env:SystemDrive\packer\configure.log
}  

