
param(
    [ValidateSet("RRD MSDN Ultimate", "RRD MSDN Premium", "AAMVA MSDN", "xiaodoli", "Compliance_Tools_Eng")]
    [string]$SubscriptionName = "RRD MSDN Premium",

    [string]$ResourceGroupName = "1es",

    [ValidateSet("westus", "westus2")]
    [string]$Location = "westus2",

    [string]$VMName = "dev1",
    [string]$AdminUser = "compliance",

    [ValidateSet("Standard_D16s_v3", "Standard_D8s_v3", "Standard_D4s_v3", "Standard_D2s_v3")]
    [string]$Size = "Standard_D4s_v3", # must use _v3 to have docker support
    [ValidateSet("Canonical")]
    [string]$VMPublisher = "Canonical",
    [ValidateSet("UbuntuServer")]
    [string]$VMOffer = "UbuntuServer",
    [ValidateSet("16.04-LTS", "18.04-LTS")]
    [string]$VMSku = "16.04-LTS"
)

Write-Host "1. Login azure subscription '$SubscriptionName'..." -ForegroundColor Green
$azAcct = az account show | ConvertFrom-Json
if (!$azAcct -or $azAcct.name -ine $SubscriptionName) {
    az login | Out-Null
    az account set -s $SubscriptionName | Out-Null
}

Write-Host "2. Ensure resource group '$ResourceGroupName'..." -ForegroundColor Green
[array]$rgsFound = az group list --query "[?name=='$ResourceGroupName']" | ConvertFrom-Json
if ($null -eq $rgsFound -or $rgsFound.Length -eq 0) {
    az group create --name $ResourceGroupName --location $Location | Out-Null
}
else {
    Write-Host "Resource group '$ResourceGroupName' already exists" -ForegroundColor Yellow
}

[array]$vmsFound = az vm list --resource-group $ResourceGroupName --query "[?name=='$VMName']" | ConvertFrom-Json
if ($null -eq $vmsFound -or $vmsFound.Length -eq 0) {
    Write-Host "3. Creating VM '$VMName'..." -ForegroundColor Green
    # az vm image list-publishers --location westus2 --query "[?starts_with(name, 'MicrosoftWindows')].{name:name}" -o json
    # az vm image list-offers --location westus2 --publisher MicrosoftWindowsDesktop --query "[].{name:name}"
    # az vm image list-skus --location westus2 --publisher MicrosoftWindowsDesktop --offer windows-10 --query "[].{name:name}" -o table
    # az vm image list-skus --location westus2 --publisher Canonical --offer UbuntuServer -o table

    $images = az vm image list --all --publisher $VMPublisher --offer $VMOffer --query "[?sku=='$VMSku']" | ConvertFrom-Json
    $vmImage = $images[$images.Count - 1].urn

    $adminPasswordSecure = Read-Host "Enter password for vm admin" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPasswordSecure)
    $adminPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    Write-Host "Creating vm: name=$VMName, size=$Size, group=$ResourceGroupName, image=$vmImage..." -ForegroundColor Green
    az vm create --name $VMName --resource-group $ResourceGroupName --location $Location `
        --image $vmImage --size $Size --admin-username $AdminUser --admin-password $adminPassword `
        --public-ip-address-dns-name $VMName

    Write-Host "3.1 opening RDP port..." -ForegroundColor Green
    az vm open-port --resource-group $ResourceGroupName --name $VMName --port 3389 --priority 100

    Write-Host "3.2 Adding data disk..." -ForegroundColor Green
    az vm disk attach --vm-name $VMName --resource-group $ResourceGroupName --disk "$($VMName)_data" --new --size-gb 127
}
else {
    Write-Host "VM '$VMName' already exists" -ForegroundColor Yellow
}

Write-Host "SSH into vm: $vmName..."
ssh "$AdminUser@$vmName.$Location.cloudapp.azure.com"

Write-Host "Common commands"
Write-Host "set password for root: sudo passwd root"
Write-Host "switch to root user: su"

Write-Host "Following the link below to mount new disk (127gb) as drive /e"
Write-Debug "https://docs.microsoft.com/en-us/azure/virtual-machines/linux/attach-disk-portal"
<#
 dmesg | grep "Attached SCSI disk"
 [    1.495623] sd 1:0:1:0: [sdb] Attached SCSI disk
 [    1.617999] sd 0:0:0:0: [sda] Attached SCSI disk
 [ 3837.681862] sd 3:0:0:0: [sdc] Attached SCSI disk


sudo fdisk /dev/sdc
Device contains neither a valid DOS partition table, nor Sun, SGI or OSF disklabel
Building a new DOS disklabel with disk identifier 0x2a59b123.
Changes will remain in memory only, until you decide to write them.
After that, of course, the previous content won't be recoverable.

Warning: invalid flag 0x0000 of partition table 4 will be corrected by w(rite)

Command (m for help): n
Partition type:
   p   primary (0 primary, 0 extended, 4 free)
   e   extended
Select (default p): p
Partition number (1-4, default 1): 1
First sector (2048-10485759, default 2048):
Using default value 2048
Last sector, +sectors or +size{K,M,G} (2048-10485759, default 10485759):
Using default value 10485759


Command (m for help): p

Disk /dev/sdc: 5368 MB, 5368709120 bytes
255 heads, 63 sectors/track, 652 cylinders, total 10485760 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x2a59b123

   Device Boot      Start         End      Blocks   Id  System
/dev/sdc1            2048    10485759     5241856   83  Linux

Command (m for help): w
The partition table has been altered!

Calling ioctl() to re-read partition table.
Syncing disks.

sudo mkfs -t ext4 /dev/sdc1
sudo mkdir /e
sudo mount /dev/sdc1 /e
sudo chown -R $(id -u):$(id -g) /e
#>

Write-Host "Following this link to setup RDP"
Write-Host "https://docs.microsoft.com/en-us/azure/virtual-machines/linux/use-remote-desktop"

<#
sudo apt-get update
sudo apt-get install xfce4
sudo apt-get install xrdp
sudo systemctl enable xrdp
echo xfce4-session >~/.xsession
sudo service xrdp restart

#>