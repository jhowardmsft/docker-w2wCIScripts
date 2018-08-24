
param(
    [Parameter(Mandatory=$false)][string]$vmName,
    [Parameter(Mandatory=$false)][switch]$Force=$False,
    [Parameter(Mandatory=$false)][string]$size="Standard_D3_v2_Promo", # Size of the VM
    [Parameter(Mandatory=$false)][string]$ImageVersion, # Image version
    [Parameter(Mandatory=$false)][string]$ConfigSet, # eg rs
    [Parameter(Mandatory=$false)][string]$RedstoneRelease, # eg 1,2,3 the "n" in RSn
    [Parameter(Mandatory=$false)][string]$Password,
    [Parameter(Mandatory=$false)][string]$ResourceGroupName,
    [Parameter(Mandatory=$false)][string]$ImageName
)

$vnetSiteName = 'Jenkins'             # Network to connect to
$Location = 'West US 2'        # Hopefully obvious
$adminUsername = 'jenkins'

if ([string]::IsNullOrWhiteSpace($Password)) {
     Throw "Password for the user 'jenkins' must be supplied"
}

if ([string]::IsNullOrWhiteSpace($ImageVersion)) {
     Throw "ImageVersion must be supplied. It's the nnnnn bit in AzureRS4vnnnnn.vhd for example"
}

if ([string]::IsNullOrWhiteSpace($ConfigSet)) {
     Throw "ConfigSet must be supplied. It's the rs bit in AzureRS4vnnnnn.vhd for example"
}

if ([string]::IsNullOrWhiteSpace($RedstoneRelease)) {
     Throw "RedstoneRelease must be supplied. It's the 4 bit in AzureRS4vnnnnn.vhd for example"
}

if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) {
     Throw "ResourceGroupName must be supplied. It's winrs for example"
}

if ([string]::IsNullOrWhiteSpace($ImageName)) {
     Throw "ImageName must be supplied. It's azurers4v5 for example"
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

	echo "INFO: vmName:              $vmName"
	echo "INFO: ResourceGroupName:   $ResourceGroupName"
	echo "INFO: ImageName:           $imageName"
    Write-Host "INFO: Checking if VM $vmName exists"
    $vm = Get-AzureRMVM -Name $vmName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if ($vm -ne $null) {
        ask("WARN: VM $vmName already exists. Delete it?")
        ask("Really delete $vmName?")
        Write-Host "INFO: Deleting VM..."
        Remove-AzureRMVM -Name $vmName -ResourceGroupName $ResourceGroupName
    }
	echo "After Get-AzureRMVM"

    # Useful - keep me.
    # Get-AzureRMImage | Where-Object { $_.Name -like "*$ConfigSet*" } | Sort-Object -Descending CreatedTime

	echo "INFO: Looking for image $imageName"
    $Image = Get-AzureRMImage | Where-Object { $_.Name -eq $imageName }
    Write-Host "INFO: $($Image.Id)"
    
    $subnetName = "win-$configSet-prod-subnet"
    #$ErrorActionPreference = "SilentlyContinue"
    #$singleSubnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $subnetName
    #$ErrorActionPreference = "Stop"
    #if ($singleSubnet -eq $Null) {
        echo "INFO: Creating subnet $subnetName"
        $singleSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix "10.0.0.0/24"
    #} else {
    #    echo "INFO: Subnet $subnetName already exists"
    #}
    
    # Create a virtual network
    $vnetName = "win-$configSet-prod-vnet"
    $ErrorActionPreference = "SilentlyContinue"
    $vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $vnetName
    $ErrorActionPreference = "Stop"
    if ($vnet -eq $Null) {
        echo "INFO: Creating virtual network $vnetName"
        $vnet = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix "10.0.0.0/16" -subnet $singleSubnet
    } else {
        echo "INFO: Virtual network $vnetName already exists"
    }
    
    # Create a public IP address
    $ipName = $vmName
    $ErrorActionPreference = "SilentlyContinue"
    $pip = Get-AzureRMPublicIpAddress -Name $ipName -ResourceGroupName $ResourceGroupName
    $ErrorActionPreference = "Stop"
    if ($pip -eq $Null) {
        echo "INFO: Creating public IP address $ipName"
        $pip = New-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Dynamic -DomainNameLabel $vmName
    } else {
        echo "INFO: Public IP address $ipname already exists"
    }
    
    # Create a NIC for the VM
    $nicName = $vmName
    $ErrorActionPreference = "SilentlyContinue"
    $nic = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName
    $ErrorActionPreference = "Stop"
    if ($nic -eq $Null) {
        echo "INFO: Creating networking interface $nicName"
        $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -Location $Location -PublicIpAddressId $pip.Id -SubnetId $vnet.Subnets[0].Id
    } else {
        echo "INFO: Network interface $nicName already exists"
    }
    
    # Network Security Group for RDP and SSL
    $nsgName = $ResourceGroupName
    $ErrorActionPreference = "SilentlyContinue"
    $nsg = Get-AzureRmNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName
    $ErrorActionPreference = "Stop"
    if ($nsg -eq $Null) {

        # Network security rule for RDP
        $rdpRuleName = "RDP-In"
        echo "INFO: Creating RDP network security rule"
        $rdpRule = New-AzureRmNetworkSecurityRuleConfig -Name $rdpRuleName -Description "Allow RDP" `
            -Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
            -SourceAddressPrefix Internet -SourcePortRange * `
            -DestinationAddressPrefix * -DestinationPortRange 3389

        # Network security rule for SSL
        $sslRuleName = "SSL-In"
        echo "INFO: Creating SSL network security rule"
        $sslRule = New-AzureRmNetworkSecurityRuleConfig -Name $sslRuleName -Description "Allow SSL" `
            -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 `
            -SourceAddressPrefix Internet -SourcePortRange * `
            -DestinationAddressPrefix * -DestinationPortRange 22

        echo "INFO: Creating network security group $nsgName"
        $nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $nsgName -SecurityRules $rdpRule
    } else {
        echo "INFO: Network security group $nsgName already exists"
    }
        
    
    $secPassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential ($adminUsername, $secPassword)
    echo "INFO: Creating VM config size $size"
    $VM = New-AzureRmVMConfig -VMName $vmName -VMSize $size
    echo "INFO: Setting VM OS and credentials"
    $VM = Set-AzureRmVMOperatingSystem -VM $VM -Windows -ComputerName $vmName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
    echo "INFO: Setting source image"
    $VM = Set-AzureRmVMSourceImage -VM $VM -Id $Image.Id
    echo "INFO: Adding network interface to VM"
    $VM = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id
    echo "INFO: Creating the VM"
    New-AzureRmVM -VM $vm -ResourceGroupName $ResourceGroupName -Location $Location

}
catch { Write-Host -ForegroundColor Red "ERROR: $_" }
finally { Write-Host -ForegroundColor Yellow "Complete" }

