@echo off

rem This is a variant of runDockerDaemon.cmd in programdata\docker installed by Install-ContainerHost.ps1
rem It has some key differences for use in Windows CI for TP5+
rem - Daemon is NOT debug
rem - Daemon is renamed to dockernssm.exe to spot easily in task manager
rem - Daemon is redirected to d:\daemon, D: being a fast SSD on CI machines
rem - TEMP and TMP are redirected to d:\temp (SSD drive)

if /I NOT "%LOCAL_CI_INSTALL%" EQU "1" (
    set TEMP=d:\temp
    set TMP=d:\temp
    mkdir d:\temp > nul 2>&1

    if exist d:\control (goto :runproduction)
    mkdir d:\control

    :runproduction
    copy %systemroot%\system32\dockerd.exe %systemroot%\system32\nssmdockerd.exe /Y
    nssmdockerd --graph=d:\control --pidfile=d:\control\daemon.pid
) ELSE (
    if exist c:\control (goto :runlocal)
    mkdir c:\control

    :runlocal
    copy %systemroot%\system32\dockerd.exe %systemroot%\system32\nssmdockerd.exe /Y
    nssmdockerd --graph=c:\control --pidfile=c:\control\daemon.pid
)
