#-----------------------
# InstallPrivates.ps1
#-----------------------

$ErrorActionPreference='Stop'

echo "$(date) InstallPrivates.ps1 started (rs)" >> $env:SystemDrive\packer\configure.log

try {
    #--------------------------------------------------------------------------------------------
    # Can't delete files (knowndlls problem) causing leaking of base image disk space
    echo "$(date) Phase2.ps1 Installing private container.dll..." >> $env:SystemDrive\packer\configure.log
    copy c:\windows\system32\container.dll c:\windows\system32\container.orig.dll
    c:\privates\sfpcopy c:\privates\container.dll c:\windows\system32\container.dll

}
Catch [Exception] {
    echo "$(date) InstallPrivates.ps1 complete with Error '$_'" >> $env:SystemDrive\packer\configure.log
    Throw $_
}
Finally {
    echo "$(date) InstallPrivates.ps1 completed. Reboot required" >> $env:SystemDrive\packer\configure.log
} 

