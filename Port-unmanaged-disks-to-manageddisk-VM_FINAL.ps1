#region Read list of VMs for disk conversion from a CSV

# All the date in the user excel will be imported
Write-Host
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Reading from a CSV..."

$VMList = IMPORT-CSV "C:\Users\username\foldername\filename.csv"
Write-Host @($vmlist).Count "rows found"
Write-Host

#endregion



#--- On the destination
#--- For each single instance source VM with unmanaged disks from the CSV file

$vmcounter = 0
$avSet_comp = @()

FOREACH ($vmline in $VMList)
{
    $vmcounter++

    #$Subscription_dst = $vmline.Subscription

    #--- Set parameters for the source

    $rgName_src = $vmline.'Source Resource Group'
    $location_src = $vmline.'Source VM Location'
    $vmName_src = $vmline.'Source VM Name'
    $AvSetName_src = $vmline.'Source AvSet'

    #--- Set parameters for the destination, Destination location should be same as the snapshot location

    $rgName_dst = $vmline.'Target Resource Group'
    $location_dst = $vmline.'Target VM Location'
    $vmName_dst = $vmline.'Target VM Name'
    $storageType_dst = $vmline.'Target Storage Type'
    #    $AvSetName_dst-- = $vmline.'Target AvSet'


    #--- --- On the source - Convert to Managed Disk

    #$diskcounter.tostring("00")

    $vm_src = ""
    $vm_src = Get-AzureRmVM -ResourceGroupName $rgName_src -Name $vmName_src

    if($vm_src.AvailabilitySetReference)
    {
        Write-Host -BackgroundColor Cyan -ForegroundColor DarkBlue $vmcounter". Availability Set found"
        Write-Host 
        Write-Host "Source AvSet:" $AvSetName_src "-" $rgName_src "-" $location_src
        write-host

        if($avSet_comp -contains $AvSetName_src)
        {
            Write-Host "AvSet already converted"
            write-host
        }
        else
        {
            Write-Host -BackgroundColor Magenta -ForegroundColor White "Making changes to SOURCE Availability Set ""$AvSetName_src""..."
            Write-Host 

            Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Converting SOURCE Availability Set..."
            Write-Host 

            $avSet_src = Get-AzureRmAvailabilitySet -ResourceGroupName $rgName_src -Name $AvSetName_src

            Update-AzureRmAvailabilitySet -AvailabilitySet $avSet_src -Sku Aligned

            $avSet_src = Get-AzureRmAvailabilitySet -ResourceGroupName $rgName_src -Name $avSetName_src

            Write-Host -BackgroundColor Magenta -ForegroundColor White "Making changes to SOURCE VMs..."
            Write-Host 

            foreach($vmInfo_src in $avSet_src.VirtualMachinesReferences)
            {
                $vm_src = Get-AzureRmVM -ResourceGroupName $rgName_src | Where-Object {$_.Id -eq $vmInfo_src.id}

                #--- Deallocate the source VM
                Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue $vm_src.Name
                Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Shutting down..."
                Write-Host
        
                Stop-AzureRmVM -ResourceGroupName $rgName_src -Name $vm_src.Name -Force


                #--- Convert the source VM to managed disks

                Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Converting to managed disks..."
                Write-Host
        
                ConvertTo-AzureRmVMManagedDisk -ResourceGroupName $rgName_src -VMName $vm_src.Name
            }
            
            $avSet_comp += @($avSetName_src)
        }
    }
    else
    {
        Write-Host -BackgroundColor Cyan -ForegroundColor DarkBlue $vmcounter". Single Instnace VM found"
        Write-Host 
        Write-Host "Source VM: " $rgName_src "-" $location_src "-" $vmName_src
        Write-Host "Target VM: " $rgName_dst "-" $location_dst "-" $vmName_dst "@" $storageType_dst
        write-host

        Write-Host -BackgroundColor Magenta -ForegroundColor White "Making changes to SOURCE virtual machine ""$vmName_src""..."
        Write-Host 

        #--- Deallocate the source VM

        Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Shutting down..."
        Write-Host
        
       Stop-AzureRmVM -ResourceGroupName $rgName_src -Name $vmName_src -Force

        #--- Convert the source VM to managed disks

        Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Converting to managed disks..."
        Write-Host
        
       ConvertTo-AzureRmVMManagedDisk -ResourceGroupName $rgName_src -VMName $vmName_src
    }

   
    #--- --- On the target

        #--- Get Target VM

        Write-Host 
        Write-Host 
        Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Getting TARGET virtual machine"
        Write-Host $vmName_dst
        Write-Host 

        $vm_dst = Get-AzureRmVM -ResourceGroupName $rgName_dst -Name $vmName_dst

        Write-Host -BackgroundColor Magenta -ForegroundColor White "Making changes to TARGET virtual machine ""$vmName_dst""..."
        Write-Host 

        #--- Deallocate the target VM

        Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Shutting down..."
        Stop-AzureRmVM -ResourceGroupName $rgName_dst -Name $vm_dst.Name -Force
        Write-Host 

        #--- Remove all Data Disks from Target VM except disk at Lun 0, which is the config disk

        write-host -BackgroundColor Yellow -ForegroundColor DarkBlue "Removing existing data disks from target VM..."
        write-host 

        $disk_dstcounter = 0
        $vm_dst_changed = 0

        foreach($disk_dst in $vm_dst.StorageProfile.DataDisks)
        {
            if($vm_dst.StorageProfile.DataDisks[$disk_dstcounter].Lun -eq 0)
            {
                write-host -BackgroundColor Yellow -ForegroundColor DarkBlue "Disk" $disk_dst.Name  "   at    Lun" $disk_dst.Lun "   ...skipped"
            }
            else
            {
                Remove-AzureRmVMDataDisk -VM $vm_dst -DataDiskNames $disk_dst.Name        
                write-host -BackgroundColor Yellow -ForegroundColor DarkBlue "Disk" $disk_dst.Name  "   at    Lun" $disk_dst.Lun "   ...removed"
                $vm_dst_changed = 1
            }
            $disk_dstcounter++
        }

        #--- Update Target VM

        Write-Host 
        Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Updating target VM..."

        if($vm_dst_changed -ne 0)
        {
            Update-AzureRmVM -ResourceGroupName $rgName_dst -VM $vm_dst

            if($? -eq "True")
            {
                Write-Host "updated"
                Write-Host 
            }        
        }
        else
        {
            Write-Host "Noting changed, VM not updated"
        }

    #--- --- For each data disk of current source VM - Create a snapshot, Create a disk on target and Attach

        $vm_src = Get-AzureRmVM -ResourceGroupName $rgName_src -Name $vmName_src

        $disk_dstcounter = 0
        $diskcounter = 0

        foreach($DataDisk_src in $vm_src.StorageProfile.DataDisks)

        {

            #--- Create a snapshot except for LUN 0

            if($vm_src.StorageProfile.DataDisks[$diskcounter].Lun -eq 0)
            {
                Write-Host "DISK" $DataDisk_src.Name " ---> LUN 0 SNAPSHOT skipped"
                $diskcounter++
                Continue
            }

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

            Write-Host "created"
            Write-Host 

            #--- Create a new managed data disk on target VM using above snap

            Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Creating new managed data disk from snapshot on target VM... Lun " $diskcounter

            $DataDiskName_dst = $vm_dst.Name +"-data-disk-" +$diskcounter
            $diskConfig_dst = New-AzureRmDiskConfig -AccountType $storageType_dst -Location $location_dst -CreateOption Copy -SourceResourceId $snapshot.Id
            
            $dataDisk = New-AzureRmDisk -Disk $diskConfig_dst -ResourceGroupName $rgName_dst -DiskName $DataDiskName_dst

            if($? -eq "True")
            {
                Write-Host "Disk" $DataDiskName_dst
                Write-Host "created"
            }
            else
            {
                Write-Host -BackgroundColor Yellow -ForegroundColor Red "Error creating disk, existing now!"
                return
            }
            #--- Attach new Data Disk to Target VM

            $vm_dst = Add-AzureRmVMDataDisk -VM $vm_dst -Name $DataDiskName_dst -CreateOption Attach -ManagedDiskId $dataDisk.Id -Lun $diskcounter

            if($? -eq "True")
            {
                Write-Host "attached"
                Write-Host 
            }
            else
            {
                Write-Host -BackgroundColor Yellow -ForegroundColor Red "Error attach disk, existing now!"
                return
            }

            $diskcounter++
        }


    #--- --- Finalize the changes

        #--- Update Target VM

        Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Updating target VM..."

        Update-AzureRmVM -ResourceGroupName $rgName_dst -VM $vm_dst

        if($? -eq "True")
        {
            Write-Host "updated"
            Write-Host 

            Write-Host -BackgroundColor Green -ForegroundColor DarkBlue "Target VM updated with data disks, starting up now..."
            Write-Host 
        }

        #--- Start up target VM

        $job = Start-AzureRmVM -Name $vm_dst.Name -ResourceGroupName $rgName_dst -AsJob
}
