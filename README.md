About
------

John Howard, Microsoft Corporation (@jhowardmsft). November 2016. 

This repo has scripts to deploy, configure, setup development VMs, and run Docker CI on Windows Server 2016.

###Directories - Deployment scripts
- <b>common</b> -  Common to all flavours
- <b>rs</b> -  Redstone specifics (rs1, rs2, rs3 as of June 2017)
- <b>config</b> - tells production servers how to configure themselves according to the hostname

###Other directories
- <b>runCI</b> -  The scripts to run CI, including <b>Invoke-DockerCI</b>. executeCI.ps1 is what is configured in Jenkins.
- <b>Deploy-JenkinsVM</b> -  Easy way to deploy a Jenkins VM
- <b>Install-DevVM</b> -  Setup an existing VM for development/CI VM if on Microsoft corpnet. 
- <b>Prepare-CIImage</b> - Pick a build (on corpnet) and get a development VM (and optional) azure VHD from it.

How to use.
--

### Pre-reqs

- Need publish settings in $env:HOME\\.azure\engine-team@docker.com.publishsettings
  Get-AzurePublishSettingsFile and save to above location.

- Make sure your azure credentials are set.   (Add-AzureAccount for engine-team@docker.com)

- Run elevated

### Sample variables for development VM only
$sourceDir="\\winbuilds\release\RS1_RELEASE\14393.693.161220-1747"
$AzureImageVersion=0
$debugPort=50001
cd e:\docker\ci\w2w\Prepare-CIImage
$AzureVMSize=""
$AzurePassword=""
$AzureStorageAccount="winrs1"
$configSet="rs"
$redstoneRelease=0
$vmBasePath="e:\VMs"
$localPassword="something"
$vmSwitch="Wired"

### Sample variables for production RS1 VHD (and development VM)
$sourceDir="\\winbuilds\release\RS1_RELEASE\14393.693.161220-1747"
$AzureImageVersion=31
$debugPort=50001
cd e:\docker\ci\w2w\Prepare-CIImage
$AzureVMSize="D3"
$AzurePassword="somethingelse"
$AzureStorageAccount="winrs1"
$configSet="0"
$redstoneRelease=1
$vmBasePath="e:\VMs"
$localPassword="something"
$vmSwitch="Wired"

###Create the development VM (and Azure image optionally)
cd e:\docker\ci\w2w\Prepare-CIImage
.\Prepare-CIImage.ps1 -Target $vmBasePath -Password $localPassword -CreateVM -Switch $vmSwitch -DebugPort $debugPort -Path $sourceDir -ConfigSet $configSet -AzureImageVersion $AzureImageVersion -AzurePassword  $AzurePassword -RedstoneRelease $redstoneRelease

###Upload VHD to Azure and create an image from it
$parts=$sourceDir.Split("\");
$localLocation=(join-path $vmBasePath -ChildPath ("$($parts[4]) $($parts[5])"));
$localVHD=(join-Path $localLocation -ChildPath "azure$($configSet)$($redstoneRelease)v$AzureImageVersion.vhd")
$AzureMediaLocation="https://$AzureStorageAccount.blob.core.windows.net/vhds/azure$($configSet)$($redstoneRelease)v$($AzureImageVersion).vhd"
Add-Azurevhd $AzureMediaLocation  -LocalFilePath $localVHD
Add-AzureVMImage -imagename "azure$($ConfigSet)$($redstoneRelease)v$($AzureImageVersion)" -MediaLocation $AzureMediaLocation -OS Windows

### Deploy to production
$vmIDs=@(1,2,3,4,5,6,7,8,9)
foreach ($vmID in $vmIDs) { start-job -argumentlist $vmID,$AzureVMSize,$AzureImageVersion,$configSet,$AzurePassword { 
    param([int]$vmID, [string]$AzureVMSize,[int]$AzureImageVersion,[string]$configSet,[string]$AzurePassword )
    cd e:\docker\ci\W2W\Deploy-JenkinsVM; dir;
    .\Deploy-JenkinsVM -Force -Size $AzureVMSize -ImageVersion $AzureImageVersion "jenkins-$configSet-$vmID" -Password $AzurePassword -ConfigSet $ConfigSet -RedstoneRelease $redstoneRelease
} | Out-Null }; Write-Host -nonewline "Deploying $($vmIDs.Count) production VMs in parallel:"
while (Get-Job -State "Running") { Write-Host -nonewline "."; Start-Sleep -Seconds 5 }; Write-Host "`n"
foreach ($job in Get-Job) { Receive-Job $Job; Remove-Job $Job; Write-Host -ForegroundColor Yellow "`n`n - - - - - - - -`n`n" }
