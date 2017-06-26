
param(
    [Parameter(Mandatory=$false)][string]$vmName,
    [Parameter(Mandatory=$false)][switch]$Force=$False,
    [Parameter(Mandatory=$false)][string]$size="Standard_D3_v2_Promo", # Size of the VM
    [Parameter(Mandatory=$false)][string]$ImageVersion, # Image version
    [Parameter(Mandatory=$false)][string]$ConfigSet, # eg rs
    [Parameter(Mandatory=$false)][string]$RedstoneRelease, # eg 1,2,3 the "n" in RSn
    [Parameter(Mandatory=$false)][string]$Password
)

$vnetSiteName = 'Jenkins'             # Network to connect to
$defaultLocation = 'Central US'       # Hopefully obvious
#$size = "Standard_"+"$size"+"_v2"     # Size of the VM

$adminUsername = 'jenkins'

if ([string]::IsNullOrWhiteSpace($Password)) {
     Throw "Password for the user 'jenkins' must be supplied"
}

if ([string]::IsNullOrWhiteSpace($ImageVersion)) {
     Throw "ImageVersion must be supplied. It's the nnnnn bit in AzureRS1vnnnnn.vhd for example"
}

if ([string]::IsNullOrWhiteSpace($ConfigSet)) {
     Throw "ConfigSet must be supplied. It's the rs bit in AzureRS1vnnnnn.vhd for example"
}

if ([string]::IsNullOrWhiteSpace($RedstoneRelease)) {
     Throw "RedstoneRelease must be supplied. It's the X bit in AzureRSXvnnnnn.vhd for example"
}

$ErrorActionPreference = 'Stop'

function ask {
    param([string]$prompt)
    if ($Force -ne $True) {
        $confirm = Read-Host "$prompt [y/n]"
        while($confirm -ne "y") {
            if ($confirm -eq 'n') {Write-Host "OK, exiting...."; exit}
            $confirm = Read-Host "$prompt [y/n]"
        }
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($vmName)) { Throw("vmName parameter must be supplied") }

    Write-Host "INFO: Checking if VM $vmName exists"
    $vm = Get-AzureVM -ServiceName $vmName -Name $vmName -ErrorAction SilentlyContinue
    if ($vm -ne $null) {
        ask("WARN: VM $vmName already exists. Delete it?")
        ask("Really delete $vmName?")
        Write-Host "INFO: Deleting VM..."
        Remove-AzureVM -ServiceName $vmName -Name $vmName
    }

    Write-Host "INFO: Determining if service $vmName exists..."
    $service=Get-AzureService -ServiceName $vmName -ErrorAction SilentlyContinue
    if ( $service -eq $null ) {
        ask("Service $vmName does not exist - create?")
        Write-Host "INFO: Create service..."
        New-AzureService -ServiceName $vmName -Location $defaultLocation
    } else {
        Write-Host "INFO: Service exists."
    }


    # Useful $sourceImages = Get-AzureVMImage | Where-Object { $_.ImageName -like "$imagePrefix*" } | Sort-Object -Descending CreatedTime


    Write-Host "INFO: Creating the configuration object..."
    $ImageName="azure$($ConfigSet)$($RedstoneRelease)v$($ImageVersion)"
    Write-Host "INFO: Based on image $ImageName"
    $vmc = New-AzureVMConfig -ImageName $ImageName -InstanceSize $size -Name $vmName -DiskLabel $vmName |
            Add-AzureEndpoint -Name 'SSH' -LocalPort 22 -PublicPort 22 -Protocol tcp |
            Set-AzureSubnet 'Subnet-1'

    Write-Host "INFO: Creating a provisioning configuration..."
    $pc=Add-AzureProvisioningConfig -VM $vmc `
                                    -Windows `
                                    -AdminUsername $adminUsername `
                                    -Password $Password

    Write-Host "INFO: Creating the VM..."
    $pc | New-AzureVM -ServiceName $vmName -VNetName $vnetSiteName

}
catch { Write-Host -ForegroundColor Red "ERROR: $_" }
finally { Write-Host -ForegroundColor Yellow "Complete" }

