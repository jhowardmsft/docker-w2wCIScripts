<#
.NOTES
    Author:  John Howard, Microsoft Corporation. (Github @jhowardmsft)

    Created: February 2017

    Summary: Customises a VHD from the build share which can be used to upload
             to Azure for Jenkins use, or for dev use. Will only run on Microsoft
             corpnet.

    License: See https://github.com/jhowardmsft/docker-w2wCIScripts/blob/master/LICENSE

    Pre-requisites:

     - Must be elevated
     - Must have access to \\winbuilds\release on Microsoft corpnet.

.Parameter Path
   The path to the build eg \\winbuilds\release\RS1_RELEASE\14393.726.170112-1758

.Parameter Target
   The path on the local machine. eg e:\vms

.Parameter SkipCopyVHD
   Whether to copy the VHD

.Parameter SkipBaseImages
   Whether to skip the creation of the base layers

.Parameter Password
   The administrator password

.Parameter CreateVM
   Whether to create a VM

.Parameter DebugPort
   The debug port (only used with -CreateVM)

.Parameter ConfigSet
   The configuration set such as "rs" (only used with -CreateVM)

.Parameter RedstoneRelease
   1,2,3,...

.Parameter Switch
   Name of the virtual switch (only used with -CreateVM)

.Parameter AzureImageVersion
   The image version (gets baked into the VHD filename such as the 31 in AzureRS1v31.vhd)

.Parameter AzurePassword
   The password for the Azure user (jenkins)

.Parameter IgnoreMissingImages
   Don't error out if images are missing

.Parameter Client
   Start from the client SKU
   
#>


param(
    [Parameter(Mandatory=$false)][string]$Path,
    [Parameter(Mandatory=$false)][string]$Target,
    [Parameter(Mandatory=$false)][switch]$SkipCopyVHD,
    [Parameter(Mandatory=$false)][switch]$SkipBaseImages,
    [Parameter(Mandatory=$false)][string]$Password,
    [Parameter(Mandatory=$false)][switch]$CreateVM,
    [Parameter(Mandatory=$false)][string]$Switch,
    [Parameter(Mandatory=$false)][int]   $DebugPort,
    [Parameter(Mandatory=$false)][string]$ConfigSet,
    [Parameter(Mandatory=$false)][int]$RedstoneRelease,
    [Parameter(Mandatory=$false)][int]   $AzureImageVersion,
    [Parameter(Mandatory=$false)][string]$AzurePassword,
	[Parameter(Mandatory=$false)][string]$IgnoreMissingImages,
	[Parameter(Mandatory=$false)][string]$Client

)

$ErrorActionPreference = 'Stop'
$mounted = $false
$azureMounted = $false
$targetSize = 127GB


# For debugging
#$Path="\\winbuilds\release\RS1_RELEASE_INMARKET\14393.823.170209-1910"
#$Target="e:\vms"
#$SkipCopyVHD=$False
#$SkipBaseImages=$False
#$Password="p@ssw0rd"
#$CreateVM=$True
#$Switch="Wired"
#$DebugPort=50011
#$ConfigSet="rs"
#$RedstoneRelease=1
#$AzureImageVersion=31

Function Test-IsAdmin () {
    [Security.Principal.WindowsPrincipal] $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()            
    $Identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)  
}

# Download-File is a simple wrapper to get a file from somewhere (HTTP, SMB or local file path)
# If file is supplied, the source is assumed to be a base path. Returns -1 if does not exist, 
# 0 if success. Throws error on other errors.
Function Download-File([string] $source, [string] $file, [string] $target) {
    $ErrorActionPreference = 'SilentlyContinue'
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


# Start of the main script. In a try block to catch any exception
Try {
    Write-Host -ForegroundColor Cyan "INFO: Starting at $(date)`n"
    set-PSDebug -Trace 0  # 1 to turn on


    if (-not (Test-IsAdmin)) {
        Throw("This must be run elevated")
    }

	$isClient = $($Client -ne "")
	
    # Split the path into it's parts
    #\\winbuilds\release\RS_ONECORE_CONTAINER_HYP\15140.1001.170220-1700
    # $branch    --> RS_ONECORE_CONTAINER_HYP
    # $build     --> 15140.1001
    # $timestamp --> 170220-1700
    $parts =$path.Split("\")
    if ($parts.Length -ne 6) {
        Throw ("Path appears to be invalid. Should be something like \\winbuilds\release\RS_ONECORE_CONTAINER_HYP\15140.1001.170220-1700")
    }
    $branch=$parts[4]
    Write-Host "INFO: Branch is $branch"
    
    $parts=$parts[5].Split(".")
    
    if ($parts.Length -ne 3) {
        Throw ("Path appears to be invalid. Should be something like \\winbuilds\release\RS_ONECORE_CONTAINER_HYP\15140.1001.170220-1700. Could not parse build ID")
    }
    $build=$parts[0]+"."+$parts[1]
    $timestamp = $parts[2]
    Write-Host "INFO: Build is $build"
    Write-Host "INFO: Timestamp is $timestamp"
    
    # Verify the VHD exists. Try VL first
	
	$sku = "server_serverdatacenter"
	if ($isClient) {
	    $sku = "client_enterprise"
	}
	

    $vhdFilename="$build"+".amd64fre."+$branch+".$timestamp"+"_"+$sku+"_en-us_vl.vhd"
    $vhdSource="\\winbuilds\release\$branch\$build"+".$timestamp\amd64fre\vhd\vhd_"+$sku+"_en-us_vl\$vhdFilename"
    
    if (-not (Test-Path $vhdSource)) { 
	    $vhdFilename="$build"+".amd64fre."+$branch+".$timestamp"+"_"+$sku+"_en-us.vhd"
		$vhdSource="\\winbuilds\release\$branch\$build"+".$timestamp\amd64fre\vhd\vhd_"+$sku+"_en-us\$vhdFilename"
		if (-not (Test-Path $vhdSource)) { Throw "$vhdSource could not be found" }
		Write-Host "INFO: Using non-VL VHD"
	}

    Write-Host "INFO: VHD found $vhdFilename"

 
    # Verify the container images exist
    $wscImageLocation="\\winbuilds\release\$branch\$build"+".$timestamp\amd64fre\ContainerBaseOsPkgs\cbaseospkg_serverdatacentercore_en-us\CBaseOs_$branch"+"_$build"+".$timestamp"+"_amd64fre_ServerDatacenterCore_en-us.tar.gz"
    if (-not (Test-Path $wscImageLocation)) {
		if ($IgnoreMissingImages -eq "Yes") {
			$wscImageLocation=""
			Write-Host "WARN: windowsservercore image is missing"
		} else {
			Throw "$wscImageLocation could not be found"
		}
	} else {
		Write-Host "INFO: windowsservercore base image found"
	}

    $nanoImageLocation="\\winbuilds\release\$branch\$build"+".$timestamp\amd64fre\ContainerBaseOsPkgs\cbaseospkg_nanoserver_en-us\CBaseOs_$branch"+"_$build"+".$timestamp"+"_amd64fre_NanoServer_en-us.tar.gz"
    if (-not (Test-Path $nanoImageLocation)) {
		if ($IgnoreMissingImages -eq "Yes") {
			$nanoImageLocation = ""
			Write-Host "WARN: nanoserver image is missing"
		} else { 
			Throw "$nanoImageLocation could not be found"
		}
	} else {
		Write-Host "INFO: nanoserver base image found"
	}

	$lkg = "\\sesdfs\1Windows\TestContent\CORE\Base\HYP\LOW\cri"
	
    # Make sure the target location exists
    if (-not (Test-Path $target)) { Throw "$target could not be found" }

    # Create a sub-directory under the target. OK if it already exists.
    $targetSubdir = Join-Path $Target -ChildPath ("$branch $build"+".$timestamp $sku")
    
    # Copy the VHD to the target sub directory
    if ($SkipCopyVHD) { 
        Write-Host "INFO: Skipping copying the VHD"
    } else {
        # Stop the VM if it is running and we're re-creating it, otherwise the VHD is locked
        if ($CreateVM) {
            $vm = Get-VM (split-path $targetSubdir -leaf) -ErrorAction SilentlyContinue
            if ($vm.State -eq "Running") {
                Write-Host "WARN: Stopping the VM"
                Stop-VM $vm -Force
            }
            # Remove it
            if ($vm -ne $null) { Remove-VM $vm -force }

            # And splat the directory
            if (Test-Path $targetSubdir) { Remove-Item $targetSubdir -Force -Recurse -ErrorAction SilentlyContinue }
        }

        Write-Host "INFO: Source $vhdSource"
        Write-Host "INFO: Copying the VHD to $targetSubdir. This may take some time..."
        if (Test-Path (Join-Path $targetSubdir -ChildPath $vhdFilename)) { Remove-Item (Join-Path $targetSubdir -ChildPath $vhdFilename) -force }
        if (-not (Test-Path $targetSubdir)) { New-Item $targetSubdir -ItemType Directory | Out-Null }
        Copy-Item $vhdSource $targetSubdir
    }

    # Get the VHD size in GB, and resize to the target if not already
    Write-Host "INFO: Examining the VHD"
    $disk=Get-VHD (Join-Path $targetSubdir -ChildPath $vhdFilename)
    $size=($disk.size)
    Write-Host "INFO: Size is $($size/1024/1024/1024) GB"
    if ($size -lt $targetSize) {
        Write-Host "INFO: Resizing to $($targetSize/1024/1024/1024) GB"
        Resize-VHD (Join-Path $targetSubdir -ChildPath $vhdFilename) -SizeBytes $targetSize
    }

    # Mount the VHD
    Write-Host "INFO: Mounting the VHD"
    Mount-DiskImage (Join-Path $targetSubdir -ChildPath $vhdFilename)
    $mounted = $true

    # Get the drive letter
    $driveLetter = (Get-DiskImage (Join-Path $targetSubdir -ChildPath $vhdFilename) | Get-Disk | Get-Partition | Get-Volume).DriveLetter
    Write-Host "INFO: Drive letter is $driveLetter"

    # Get the partition
    $partition = Get-DiskImage (Join-Path $targetSubdir -ChildPath $vhdFilename) | Get-Disk | Get-Partition

    # Resize the partition to its maximum size
    $maxSize = (Get-PartitionSupportedSize -DriveLetter $driveLetter).sizeMax
    if ($partition.size -lt $maxSize) {
        Write-Host "INFO: Resizing partition to maximum"
        Resize-Partition -DriveLetter $driveLetter -Size $maxSize
    } 

    # Create some directories
    if (-not (Test-Path "$driveLetter`:\packer"))     {New-Item -ItemType Directory "$driveLetter`:\packer" | Out-Null}
    if (-not (Test-Path "$driveLetter`:\privates"))   {New-Item -ItemType Directory "$driveLetter`:\privates" | Out-Null}
    if (-not (Test-Path "$driveLetter`:\baseimages")) {New-Item -ItemType Directory "$driveLetter`:\baseimages" | Out-Null}
    if (-not (Test-Path "$driveLetter`:\w2w"))        {New-Item -ItemType Directory "$driveLetter`:\w2w" | Out-Null}
    if (-not (Test-Path "$driveLetter`:\tvpp"))       {New-Item -ItemType Directory "$driveLetter`:\tvpp" | Out-Null}
    if (-not (Test-Path "$driveLetter`:\debuggers"))  {New-Item -ItemType Directory "$driveLetter`:\debuggers" | Out-Null}	
	if (-not (Test-Path "$driveLetter`:\lkg"))        {New-Item -ItemType Directory "$driveLetter`:\lkg" | Out-Null}	

    # The entire repo of w2w (we need this for a dev-vm scenario - bootstrap.ps1 makes that decision
    Copy-Item ..\* "$driveletter`:\w2w" -Recurse -Force

    # Put the bootstrap file additionally in \packer
    Copy-Item ..\common\Bootstrap.ps1 "$driveletter`:\packer\"

    # Files for test-signing and copying privates
    Copy-Item "\\sesdfs\1windows\TestContent\CORE\Base\HYP\HAT\setup\testroot-sha2.cer" "$driveLetter`:\privates\"
    Copy-Item ("\\winbuilds\release\$branch\$build"+".$timestamp\amd64fre\test_automation_bins\idw\sfpcopy.exe") "$driveLetter`:\privates\"

	# Binaries
	Expand-Archive \\sesdfs\1Windows\TestContent\CORE\Base\HYP\LOW\cri\package\lkg\package.zip "$driveletter`:\lkg\" -Force
	
	# Traceview++ https://osgwiki.com/wiki/TraceLogging_Ramp_Up_Guide#TraceView.2B.2B
	\\tkfiltoolbox\tools\tvpp\3.0\xcopyinstall.cmd "$driveletter`:\tvpp"
	Copy-Item "\\sesdfs.corp.microsoft.com\osg\Teams\CORE\Base\HYP\Team\jhoward\Docker\Install\tvpp\TVPPSession.tvpp" "$driveletter`:\tvpp\"
	
	# Debuggers
	\\dbg\privates\latest\dbgxcopyinstall.cmd "$driveletter`:\debuggers"
	
    # We need NuGet
    Write-Host "INFO: Installing NuGet package provider..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null


     if (-not $SkipBaseImages) {
        # https://github.com/microsoft/wim2img (Microsoft Internal)
        Register-PackageSource -Name HyperVDev -Provider PowerShellGet -Location \\sesdfs.corp.microsoft.com\1Windows\TestContent\CORE\Base\HYP\HAT\packages -Trusted -Force | Out-Null
        Write-Host "INFO: Installing Containers.Layers module..."
        Install-Module -Name Containers.Layers -Repository HyperVDev | Out-Null
        Write-Host "INFO: Importing Containers.Layers..."
        Import-Module Containers.Layers | Out-Null

        if (-not (Test-Path "$driveLetter`:\BaseImages\nanoserver.tar")) {
			if (-not ($nanoImageLocation -eq "")) {
				Write-Host "INFO: Converting nanoserver base image"
				Export-ContainerLayer -SourceFilePath $nanoImageLocation -DestinationFilePath "$driveLetter`:\BaseImages\nanoserver.tar" -Repository "microsoft/nanoserver" -latest
			}
        }
        if (-not (Test-Path "$driveLetter`:\BaseImages\windowsservercore.tar")) {
			if (-not ($wscImageLocation -eq "")) {
				Write-Host "INFO: Converting windowsservercore base image"
				Export-ContainerLayer -SourceFilePath $wscImageLocation -DestinationFilePath "$driveLetter`:\BaseImages\windowsservercore.tar" -Repository "microsoft/windowsservercore" -latest
			}
        }
    }

    # Read the current unattend.xml, put in the password and save it to the root of the VHD
    Write-Host "INFO: Creating unattend.xml"
    $unattend = Get-Content ".\unattend.xml"
    $unattend = $unattend.Replace("!!REPLACEME!!", $Password)
    [System.IO.File]::WriteAllText("$driveLetter`:\unattend.xml", $unattend, (New-Object System.Text.UTF8Encoding($False)))

    # Create the password file
    [System.IO.File]::WriteAllText("$driveLetter`:\packer\password.txt", $Password, (New-Object System.Text.UTF8Encoding($False)))

    # Add the pre-bootstrapper that gets invoked by the unattend. Note we always re-download the bootstrapper.
    # Note also the use of c:\packer\PreBootStrappedOnce.txt so that on the first specialize pass to add the scheduled task,
    # we make sure the VM is re-sysprepped, not re-started.
    $prebootstrap = `
       "certutil.exe -addstore root c:\privates\testroot-sha2.cer`n" + `
       "bcdedit /set `"{current}`" testsigning on`n" + `
       "set-executionpolicy bypass`n" + `
       "`$wc=New-Object net.webclient;`$wc.Downloadfile(`"https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/common/Bootstrap.ps1`",`"c:\w2w\common\Bootstrap.ps1`")`n" + `
        "`$action = New-ScheduledTaskAction -Execute `"powershell.exe`" -Argument `"-command c:\w2w\common\Bootstrap.ps1`"`n " + `
        "`$trigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay 00:01:00`n" + `
        "Register-ScheduledTask -TaskName `"Bootstrap`" -Action `$action -Trigger `$trigger -User SYSTEM -RunLevel Highest`n`n" + `
        "if (Test-Path c:\packer\PreBootStrappedOnce.txt) { shutdown /t 0 /r } else { New-Item c:\packer\PreBootStrappedOnce.txt -ErrorAction SilentlyContinue; c:\windows\system32\sysprep\sysprep.exe /generalize /oobe /shutdown }`n`n"

 
    [System.IO.File]::WriteAllText("$driveLetter`:\packer\prebootstrap.ps1", $prebootstrap, (New-Object System.Text.UTF8Encoding($False)))

    # Write the config set out to disk
    [System.IO.File]::WriteAllText("$driveLetter`:\packer\release.txt", "$($ConfigSet)$($RedstoneRelease)", (New-Object System.Text.UTF8Encoding($False)))
    [System.IO.File]::WriteAllText("$driveLetter`:\packer\configset.txt", $ConfigSet, (New-Object System.Text.UTF8Encoding($False)))

    # Write the debug port out to disk
    [System.IO.File]::WriteAllText("$driveLetter`:\packer\debugport.txt", $DebugPort, (New-Object System.Text.UTF8Encoding($False)))

    # Flush the disk
    Write-Host "INFO: Flushing drive $driveLetter"
    Write-VolumeCache -DriveLetter $driveLetter

    # Dismount - we're done preparing it.
    Write-Host "INFO: Dismounting VHD"
    Dismount-DiskImage (Join-Path $targetSubdir -ChildPath $vhdFilename)
    $mounted = $false
    

    # Create a VM from that VHD
    $vm = Get-VM (split-path $targetSubdir -leaf) -ErrorAction SilentlyContinue
    if ($vm -ne $null) {
        Write-Host "WARN: VM already exists - deleting"
        Remove-VM $vm -Force
    }
    Write-Host "INFO: Creating a VM"
    $vm = New-VM -generation 1 -Path $Target -Name (split-path $targetSubdir -leaf) -NoVHD
    Set-VMProcessor $vm -ExposeVirtualizationExtensions $true -Count 8
	Set-VM $vm -MemoryStartupBytes 4GB
	Set-VM $vm -CheckpointType Standard
	Set-VM $vm -AutomaticCheckpointsEnabled $False
    Add-VMHardDiskDrive $vm -ControllerNumber 0 -ControllerLocation 0 -Path (Join-Path $targetSubdir -ChildPath $vhdFilename)
    if ($switch -ne "") {
        Connect-VMNetworkAdapter -VMName (split-path $targetSubdir -leaf) -SwitchName $switch
    }

    Start-VM $vm
    Write-Host -NoNewline "INFO: Waiting for VM to complete booting and re-sysprep: "
    while ($vm.State -ne "Off") {
        Write-host -NoNewline "."
        Start-Sleep -seconds 6
    }
    Write-Host -NoNewLine "`n"

    # Are we creating the Azure image for this as well?
    if ($AzureImageVersion -ne 0) {
        $AzureTargetVHD=Join-Path $targetSubDir -ChildPath (("Azure$($ConfigSet)$($RedstoneRelease)")+("v$AzureImageVersion.vhd"))
        Write-Host "INFO: Copying Azure VHD to $AzureTargetVHD"
        Copy-Item (Join-Path $targetSubdir -ChildPath $vhdFilename) $AzureTargetVHD -force

        # Mount the Azure VHD
        Write-Host "INFO: Mounting the Azure VHD"
        Mount-DiskImage $AzureTargetVHD
        $azureMounted = $true

        # Get the drive letter
        $driveLetter = (Get-DiskImage $AzureTargetVHD | Get-Disk | Get-Partition | Get-Volume).DriveLetter
        Write-Host "INFO: Drive letter is $driveLetter"

        # Start deleting - unattend.xml is useless in Azure
        Write-Host "INFO: Removing bits from the Azure VHD"
        Remove-Item "$driveLetter`:\unattend.xml" -ErrorAction SilentlyContinue
        Remove-Item "$driveLetter`:\packer\debugport.txt" -ErrorAction SilentlyContinue
        Remove-Item "$driveLetter`:\packer\release.txt" -ErrorAction SilentlyContinue
        Remove-Item "$driveLetter`:\packer\configset.txt" -ErrorAction SilentlyContinue
        Remove-Item "$driveLetter`:\packer\password.txt" -ErrorAction SilentlyContinue

        # Create the password file for production systems
        [System.IO.File]::WriteAllText("$driveLetter`:\packer\password.txt", $AzurePassword, (New-Object System.Text.UTF8Encoding($False)))

        # Flush the disk
        Write-Host "INFO: Flushing drive $driveLetter"
        Write-VolumeCache -DriveLetter $driveLetter

        # Dismount - we're done preparing it.
        Write-Host "INFO: Dismounting Azure VHD"
        Dismount-DiskImage $AzureTargetVHD
        $azureMounted = $false
    }

    if ($createVM) {
        Write-Host "INFO: Starting the development VM. It will ask for creds in a few minutes..."
        Start-VM $vm
        # Checkpoint-VM $vm    
        vmconnect localhost (split-path $targetSubdir -leaf)
    }


    # The Azure upload piece

}
Catch [Exception] {
    Throw $_
}
Finally {
    if ($mounted) { 
        Write-Host "INFO: Dismounting VHD"
        Dismount-DiskImage (Join-Path $targetSubdir -ChildPath $vhdFilename)
    }
    if ($azureMounted) { 
        Write-Host "INFO: Dismounting Azure VHD"
        Dismount-DiskImage $AzureTargetVHD
    }
    Write-Host "INFO: Exiting at $(date)"
}
