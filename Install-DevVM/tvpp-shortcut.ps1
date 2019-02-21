    $TargetFile = "c:\tvpp\tvppsession.tvpp"
    $ShortcutFile = "C:\Users\$env:Username\Desktop\tvpp.lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
    $Shortcut.Arguments =""
    $Shortcut.TargetPath = $TargetFile
    $Shortcut.Save()
