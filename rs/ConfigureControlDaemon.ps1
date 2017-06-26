#-----------------------
# ConfigureControlDaemon.ps1
# BUGBUG This can be removed after service PR merged
#-----------------------

$ErrorActionPreference='Stop'

echo "$(date) ConfigureControlDaemon.ps1 (TP5 variety - NSSM) started" >> $env:SystemDrive\packer\configure.log

try {
    # Create directory for storing the nssm configuration
    
    # Install NSSM by extracting archive and placing in system32
    echo "$(date) ConfigureControlDaemon.ps1 downloading NSSM..." >> $env:SystemDrive\packer\configure.log
    $wc=New-Object net.webclient;$wc.Downloadfile("https://nssm.cc/release/nssm-2.24.zip","$env:Temp\nssm.zip")
    echo "$(date) ConfigureControlDaemon.ps1 extracting NSSM..." >> $env:SystemDrive\packer\configure.log
    Expand-Archive -Path $env:Temp\nssm.zip -DestinationPath $env:Temp
    echo "$(date) ConfigureControlDaemon.ps1 installing NSSM..." >> $env:SystemDrive\packer\configure.log
    Copy-Item $env:Temp\nssm-2.24\win64\nssm.exe $env:SystemRoot\System32

    # Configure the docker NSSM service
    echo "$(date) ConfigureControlDaemon.ps1 configuring NSSM..." >> $env:SystemDrive\packer\configure.log
    Start-Process -Wait "nssm" -ArgumentList "install docker $($env:SystemRoot)\System32\cmd.exe /s /c $env:SystemDrive\packer\nssmdocker.cmd < nul"
    Start-Process -Wait "nssm" -ArgumentList "set docker DisplayName Docker Daemon"
    Start-Process -Wait "nssm" -ArgumentList "set docker Description Docker control daemon for CI testing"
    Start-Process -Wait "nssm" -ArgumentList "set docker AppStopMethodConsole 30000"
    if ($env:LOCAL_CI_INSTALL -ne 1) {
        mkdir "d:\nssmdaemon" -ErrorAction SilentlyContinue 2>&1 | Out-Null
        Start-Process -Wait "nssm" -ArgumentList "set docker AppStderr d:\nssmdaemon\nssmdaemon.log"
        Start-Process -Wait "nssm" -ArgumentList "set docker AppStdout d:\nssmdaemon\nssmdaemon.log"
    } else {
        mkdir "c:\nssmdaemon" -ErrorAction SilentlyContinue 2>&1 | Out-Null
        Start-Process -Wait "nssm" -ArgumentList "set docker AppStderr c:\nssmdaemon\nssmdaemon.log"
        Start-Process -Wait "nssm" -ArgumentList "set docker AppStdout c:\nssmdaemon\nssmdaemon.log"
    }
    
    echo "$(date) ConfigureControlDaemon.ps1 Starting docker..." >> $env:SystemDrive\packer\configure.log    
    nssm start docker
    sleep 5

    echo "$(date) ConfigureControlDaemon.ps1 Docker version:" >> $env:SystemDrive\packer\configure.log    
    docker version >> $env:SystemDrive\packer\configure.log
}
Catch [Exception] {
    echo "$(date) ConfigureControlDaemon.ps1 complete with Error '$_'" >> $env:SystemDrive\packer\configure.log
    Throw $_
}
Finally {
    echo "$(date) ConfigureControlDaemon.ps1 completed at $(date)" >> $env:SystemDrive\packer\configure.log
} 

