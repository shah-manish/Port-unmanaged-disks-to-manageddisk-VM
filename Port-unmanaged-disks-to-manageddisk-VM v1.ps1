#region Login

# Login to the user's default Azure AD Tenant
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Login to User's default Azure AD Tenant"
$Account = Add-AzureRmAccount
Write-Host

# Get the list of Azure AD Tenants this user has access to, and select the correct one
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of Azure AD Tenants for this User"
$Tenants = @(Get-AzureRmTenant)
Write-Host

# Get the list of Azure AD Tenants this user has access to, and select the correct one
if($Tenants.Count -gt 1) # User has access to more than one Azure AD Tenant
{
    $Tenant = $Tenants |  Out-GridView -Title "Select the Azure AD Tenant you wish to use..." -OutputMode Single
}
elseif($Tenants.Count -eq 1) # User has access to only one Azure AD Tenant
{
    $Tenant = $Tenants.Item(0)
}
else # User has access to no Azure AD Tenant
{
    Return
}

# Get Authentication Token, just in case it is required in future
$TokenCache = (Get-AzureRmContext).TokenCache
$Token = $TokenCache.ReadItems() | Where-Object { $_.TenantId -eq $Tenant.Id }

# Check if the current Azure AD Tenant is the required Tenant
if($Account.Context.Tenant.Id -ne $Tenant.Id)
{
    # Login to the required Azure AD Tenant
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Login to correct Azure AD Tenant"
    $Account = Add-AzureRmAccount -TenantId $Tenant.Id
    Write-Host
}

#endregion

#region Select subscriptions

# Get list of Subscriptions associated with this Azure AD Tenant, for which this User has access
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of Azure Subscriptions for this Azure AD Tenant"
$Subscriptions = @(Get-AzureRmSubscription -TenantId $Tenant.Id)
Write-Host

if($Subscriptions.Count -gt 1) # User has access to more than one Azure Subscription
{
    $Subscriptions = $Subscriptions |  Out-GridView -Title "Select the Azure Subscriptions you wish to use..." -OutputMode Multiple
}
elseif($Subscriptions.Count -eq 1) # User has access to only one Azure Subscription
{
    $Subscriptions = @($Subscriptions.Item(0))
}
else # User has access to no Azure Subscription
{
    Return
}

#endregion

#region Define parameters

#--- Temporary overwrite of Subscription
$Subscription_dst = "####################-----------------------###################"

#--- Set parameters for the source
$rgName_src = "RG1-unmanaged_disk"
$location_src = 'ukwest' 
$vmName_src = "lvm1-unman"


#--- Set parameters for the destination
#--- Destination location should be same as the snapshot location
$rgName_dst = "RG2-managed_disk"
$location_dst = 'ukwest' 
$vmName_dst = "lvm2-managed"
$storageType_dst = 'Standard_LRS'

#endregion

#--- Current scope: one vm at a time, only single instance VMs


#--- On the destination
#--- For each single instance VM with unmanaged disks

#--- Find the name of the destination VM that will replace the source VM
#--- For now using the name defined/ hardcoded above


#--- Get Target VM
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Getting TARGET virtual machine"
Write-Host $vmName_dst
Write-Host 

$vm_dst = get-azurermvm `
    -ResourceGroupName $rgName_dst `
    -Name $vmName_dst

Write-Host -BackgroundColor Magenta -ForegroundColor White "Making changes to TARGET virtual machine ""$vmName_dst""..."
Write-Host 


#--- Deallocate the target VM

Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Shutting down..."
Stop-AzureRmVM -ResourceGroupName $rgName_dst -Name $vm_dst.Name -Force


#--- Remove all Data Disks from Target VM
#--Remove-AzureRmVMDataDisk -VM $vm_dst -Confirm -DataDiskNames vm2-d1

Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Removing all data disks..."
Write-Host 
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Please confirm."
Write-Host 
Remove-AzureRmVMDataDisk -VM $vm_dst -Confirm
Update-AzureRmVM -ResourceGroupName $rgName_dst -VM $vm_dst



#--- On the source

#--- "Single Instance VM with Unmanaged Disks"
#--- For each VM with unmanaged disks

Write-Host -BackgroundColor Magenta -ForegroundColor White "Making changes to SOURCE virtual machine ""$vmName_src""..."
Write-Host 

#--- Deallocate the source VM
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Shutting down..."
Stop-AzureRmVM -ResourceGroupName $rgName_src -Name $vmName_src -Force
Write-Host "done"
Write-Host

#--- Convert the source VM to managed disks
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Converting to managed disks..."
ConvertTo-AzureRmVMManagedDisk -ResourceGroupName $rgName_src -VMName $vmName_src
Write-Host "done"
Write-Host

$vm_src = get-azurermvm `
    -ResourceGroupName $rgName_src `
    -Name $vmName_src


#--- For each data disk of current source VM
#        create a snapshot
#        create a disk on target
#        Attache the disk
    

    $counter = 0

    foreach($DataDisk_src in $vm_src.StorageProfile.DataDisks)

    {
            
        $Lun = $counter
        $counter++

        #--- Create a snapshot
        Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Creating snapshot..."

        $snapshotConfig =  New-AzureRmSnapshotConfig `
            -SourceUri $DataDisk_src.ManagedDisk.Id `
            -Location $location_dst `
            -CreateOption copy

        $snapshotName =  $DataDisk_src.name + "_" + $(Get-Date -format "yyyyMMdd_HHmmss")

        Write-Host "DISK" $DataDisk_src.Name " ---> SNAPSHOT" $snapshotName 

        $snapshot = New-AzureRmSnapshot `
            -Snapshot $snapshotConfig `
            -SnapshotName $snapshotName `
            -ResourceGroupName $rgName_dst

        Write-Host "Snapshot created successfully"
        Write-Host 

        #--- Create a new managed data disk on target VM using above snap
        Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Creating new managed data disk from snapshot on target VM... Lun " $Lun

        $DataDiskName_dst = $vm_dst.Name +"-data-disk-" +$counter
        $diskConfig_dst = New-AzureRmDiskConfig -AccountType $storageType_dst -Location $location_dst -CreateOption Copy -SourceResourceId $snapshot.Id
        $dataDisk = New-AzureRmDisk -Disk $diskConfig_dst -ResourceGroupName $rgName_dst -DiskName $DataDiskName_dst

        Write-Host "Disk" $DataDisk_src.name

        if($? -eq "True")
        {
            Write-Host "created"
        }

        #--- Attach new Data Disk to Target VM
        $vm_dst = Add-AzureRmVMDataDisk -VM $vm_dst -Name $DataDiskName_dst -CreateOption Attach -ManagedDiskId $dataDisk.Id -Lun $Lun

        if($? -eq "True")
        {
            Write-Host "attached"
            Write-Host 
        }
    }

#--- Update Target VM
    Update-AzureRmVM -ResourceGroupName $rgName_dst -VM $vm_dst

    if($? -eq "True")
    {
        Write-Host -BackgroundColor Green -ForegroundColor DarkBlue "Target VM updated with data disks, starting up now..."
        Write-Host 
    }


#--- Start up target VM
    $job = Start-AzureRmVM -Name $vm_dst -ResourceGroupName $rgName_dst -AsJob
