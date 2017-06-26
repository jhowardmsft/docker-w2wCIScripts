#-----------------------
# Phase3.ps1
#-----------------------

$ErrorActionPreference='Stop'

echo "$(date) Phase3.ps1 started" >> $env:SystemDrive\packer\configure.log

try {
    echo "$(date) Phase3.ps1 starting" >> $env:SystemDrive\packer\configure.log   
    echo $(date) > "c:\users\public\desktop\Phase3 Start.txt"

    #--------------------------------------------------------------------------------------------
    # Configure the control daemon
    echo "$(date) Phase3.ps1 Configuring control daemon..." >> $env:SystemDrive\packer\configure.log

    if ($env:LOCAL_CI_INSTALL -ne 1) {
        dockerd --data-root "$($env:TESTRUN_DRIVE):\control" --register-service
        net start docker
        sleep 5
        docker version >> $env:SystemDrive\packer\configure.log
    }

    #--------------------------------------------------------------------------------------------
    # Initiate Phase4. This runs as the Jenkins user interactively. This is particularly on account
    # of configuring cygwin SSH not working as local system, RunOnce regkey also fails. And so does
    # a scheduled task that isn't interactive. All due to cygwin oddities.
    echo "$(date) Phase3.ps1 Initiating phase4..." >> $env:SystemDrive\packer\configure.log
    $user="administrator"
    if ($env:LOCAL_CI_INSTALL -ne 1) {
        $user="jenkins"
        $pass = Get-Content c:\packer\password.txt -raw -ErrorAction SilentlyContinue
        REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinLogon" /v AutoAdminLogon /t REG_DWORD /d 1 /f | Out-Null
        REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinLogon" /v DefaultUserName /t REG_SZ /d $user /f | Out-Null
        REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinLogon" /v DefaultPassword /t REG_SZ /d $pass /f | Out-Null
    }
    # Create the shortcut (and the containing directory as we haven't logged on interactively yet)
    New-Item "C:\Users\$user\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" -Type Directory -ErrorAction SilentlyContinue    
    $TargetFile = "powershell"
    $ShortcutFile = "C:\Users\$user\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Phase4.lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
    $Shortcut.Arguments ="-NoProfile -Noninteractive -command c:\packer\Phase4.ps1"
    $Shortcut.TargetPath = $TargetFile
    $Shortcut.Save()

    #--------------------------------------------------------------------------------------------
    # Initiate Phase5. We do the cleanup of phase4 in phase5 as I hit an issue where PS seems to 
    # just die in the cleanup of phase 4. More an experiment, but may become permanent...
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-command c:\packer\Phase5.ps1"
    $trigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay 00:01:00
    if ($env:LOCAL_CI_INSTALL -ne 1) {
        $pass = Get-Content c:\packer\password.txt -raw
        Register-ScheduledTask -TaskName "Phase5" -Action $action -Trigger $trigger -User jenkins -Password $pass -RunLevel Highest
    } else {
        Register-ScheduledTask -TaskName "Phase5" -Action $action -Trigger $trigger -User administrator -Password "p@ssw0rd" -RunLevel Highest
    }
}
Catch [Exception] {
    echo "$(date) Phase3.ps1 complete with Error '$_'" >> $env:SystemDrive\packer\configure.log
    echo $(date) > "c:\users\public\desktop\ERROR Phase3.txt"
    exit 1
}
Finally {
    # Disable the scheduled task
    echo "$(date) Phase3.ps1 disabling scheduled task.." >> $env:SystemDrive\packer\configure.log
    $ConfirmPreference='none'
    Get-ScheduledTask 'Phase3' | Disable-ScheduledTask

    # Reboot
    echo "$(date) Phase3.ps1 completed. Rebooting" >> $env:SystemDrive\packer\configure.log
    echo $(date) > "c:\users\public\desktop\Phase3 End.txt"
    shutdown /t 0 /r /f /c "Phase3"
    echo "$(date) Phase3.ps1 complete successfully at $(date)" >> $env:SystemDrive\packer\configure.log
} 

