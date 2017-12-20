<#
.Synopsis
   Mount backup VHD files and run checkdisk. Use -Drive for an array of drives
   check and -Path for the path to a specific VHD. Both can accept multiple values
   as an array.
.DESCRIPTION
   The script is to be uploaded to your dashboard account as a user script.
   It can run both as a script check and as a scheduled task. Expects to be run
   with vitCheck-RMMDefaults.ps1
.EXAMPLE
   vitRepair-BackupVHD
.EXAMPLE
   vitRepair-BackupVHD -Drive "X:" -Path "X:\My.VHD"
.OUTPUTS
   Error file if needed and removes files
.EMAIL
   vdonley@visionms.net
.VERSION
   1.0
#>


<#
 Others optional but must accept -logfile from MaxRM.
#>  
param (	
    # Drive to cleanup, if not provided will search for backup drives
    [Parameter()]
    [array]
    $Drive,

    # Path to VHDs to be checked
    [Parameter()]
    [array]
    $Path,

	# Make sure -logfile is NOT positional
	[Parameter(Mandatory=$false)]
	[string]$logfile
)

# REGION VHD Functions
#Mount the VHD
function VHD-Mount {
    param (
    # Old for 2008, New for 2012+
    [Parameter(Mandatory=$true)]
    [string]
    $VhdType,
    
    # Parameter help description
    [Parameter(Mandatory=$true)]
    [string]
    $Path
    )
    try {
        if ($VhdType -eq 'Old') {
            # WMI object to mount and unmount the VHD files
            $objVHDService = get-wmiobject -class "Msvm_ImageManagementService" -namespace "root\virtualization" -computername "."
            $FunctionOut = $objVHDService.Mount("$Path") | Format-List | Out-String  
        }
        else {
            $FunctionOut = Mount-VHD -Path $Path -Verbose 4>&1 | Format-List | Out-String
        }
        return $FunctionOut
    }
    catch {
        $myException = $_.Exception | Format-List | Out-String
        return $myException
    }   
}
# Dismount the VHD
function VHD-Dismount {
    param (
    # Old for 2008, New for 2012+
    [Parameter(Mandatory=$true)]
    [string]
    $VhdType,
    
    # Parameter help description
    [Parameter(Mandatory=$true)]
    [string]
    $Path
    )
    try {
        if ($VhdType -eq 'Old') {
            # WMI object to mount and unmount the VHD files
            $objVHDService = get-wmiobject -class "Msvm_ImageManagementService" -namespace "root\virtualization" -computername "."
            $FunctionOut = $objVHDService.unmount("$Path") | Format-List | Out-String  
        }
        else {
            $FunctionOut = Dismount-VHD -Path $Path -Verbose 4>&1 | Format-List | Out-String
        }
        return $FunctionOut
    }
    catch {
        $myException = $_.Exception | Format-List | Out-String
        return $myException
    }   
}

# Set error and warning preferences
$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"

# Force output to keep RMM from timing out
Write-Host ' '

# Create hashtable for output. Make it stay in order and start
# an error counter to create an alert if needed.
$Return = [ordered]@{}
$Return.Error_Count = 0

# List of drives never to run this script on, in case someone enters something wrong
# or copies a backup to a data or system disk.
$IgnoreDrives = @("C:","D:","E:","F:","G:","H:","I:","J:","K:","L:")

# Backup types we are checking for, this just creates the variable, not if it is checked or not
$WindowsImageBackup = @()

# REGION Reporting setup
try {
    # Information about the script for reporting.
    $ErrorFileName = "vitRepair-BackupVHD.txt"
    # File name for ScriptRunnter
    $Return.RMM_Script_Name = $MyInvocation.MyCommand.Name
    # Check to see if the RMM Error Folder exists. Put the Error file in %TEMP% if it doesn't.
    $myErrorPath = $env:RMMErrorFolder
    if ($myErrorPath) {
        $Return.Error_File = $env:RMMErrorFolder + "\" + $ErrorFileName
    }
    else {
        $Return.Error_File = $env:TEMP + "\" + $ErrorFileName
    }
}
catch {
    $myException = $_.Exception | Format-List | Out-String
    $Return.File_Information_Catch = $myException 
    $Return.Error_Count++ 
}
# END REGION

# REGION Make sure script can run and find everything it needs
try {
    # Need to know the OS version to use the right WMI class to mount the VHD
    $OSInfo = Get-WmiObject Win32_OperatingSystem | Select-Object Caption,OSArchitecture,Version
    $OSInfoReturn = $OSInfo | Format-List | Out-String
    $Return.OS_Info = $OSInfoReturn
    if ($OSInfo.Caption -like "*2008*") {
        $VHDMethod = 'Old'
    }
    else {
        $VHDMethod = 'New'
        $HyperVPosh = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-Management-PowerShell'
        if ($HyperVPosh.State -eq 'Disabled') {
            $Return.'Hyper-V_Powershell_Results' = Enable-WindowsOptionalFeature -FeatureName 'Microsoft-Hyper-V-Management-PowerShell' -Online -NoRestart
        }
    }
    # Make sure Carbon module is installed
    $CarbonInstallCheck = Get-Module -ListAvailable -Name Carbon
    if (!($CarbonInstallCheck)) {
        $Return.Error_Count++
        $Return.Carbon_Test = "Unable to find Carbon module"
    }
    if ($Return.Error_Count -ge '1') {
        Write-Output @"
        
Script Failure!
Troubleshooting info below
_______________________________
   
"@
        $Return | Format-List | Out-String
        Add-Content -Path $Return.Error_File -Value "`n----------------------`n "
        Add-Content -Path $Return.Error_File -Value (get-date) -passthru
        Add-Content -Path $Return.Error_File -Value "`n "
        Add-Content -Path $Return.Error_File -Value ( $Return | Format-List | Out-String )
        Exit 1001
    }
    else {
        # Return success
        $Return.Carbon_Test = 'Carbon v{0}' -f $CarbonInstallCheck.Version
    }
}
catch {
    $myException = $_.Exception | Format-List | Out-String
    $Return.Prerequisit_Catch = $myException 
    $Return.Error_Count++ 
}
# END REGION

# REGION Find drives with backups
try {
    # Check if a drive was specified. If not, ignore $IgnoreDrives but check the rest
    # for backups
    if ($Drive) {
        $DriveString = [string]::Join(' ', $Drive)
        $Return.Drive_Selection = "Backup drive from command line, checking $DriveString"
    }
    else {
        $Return.Drive_Selection = "Backup drives not specified, checking for backups automatically"
        $Return.Ignoring_Drives = [string]::Join(' ', $IgnoreDrives)
        $FoundDrives = Get-PSDrive -PSProvider FileSystem | Select-Object @{name = 'Drive'; expression = {$_.Name + ':'}}
        $Return.Found_Drives = [string]::Join(' ', $FoundDrives.Drive)
        foreach ($item in $FoundDrives.Drive) {
            if (!($IgnoreDrives -like $item)) {
                $Drive += $item
            }
        }
        # Make sure there is something in $Drive at this point, error if not
        if (!($Drive -or $Path)) {
            $Return.Drives_to_Check = "No potential backup drives found, error"
            $Return.Error_Count++
        }
        else {
            $Return.Drives_to_Check = [string]::Join(' ', $Drive) 
        }          
    }
    # Check for Windows 7 image backups
    # If a path was specified, use that or try to find them automatically
    $Return.Windows_Image_Backups = @()
    if ($Path) {
        if (Test-Path $Path) {
            $Return.Windows_Image_Backups += $Path
        }     
    }
    else {
        foreach ($item in $Drive) {
            # Path of Windows 7 image backups
            $ImageBackupPath = $item + "\WindowsImageBackup\" + $env:COMPUTERNAME
            if (Test-Path -Path $ImageBackupPath) {
                $WindowsImageBackup += $item
            }
        }
        if ($WindowsImageBackup) {
            foreach ($item in $WindowsImageBackup) {
                $myVHD = (Get-ChildItem -Path $item -Recurse | Where-Object Name -Like '*.vh*' | Select-Object FullName).FullName
                $Return.Windows_Image_Backups += $myVHD
            }
        }
    }  
    if (!($Return.Windows_Image_Backups)) {
        $Return.Windows_Image_Backups = "No Windows 7 image backups found"
        $Return.Error_Count++
    }
}
catch {
    $myException = $_.Exception | Format-List | Out-String
    $Return.Backup_Path_Catch = $myException 
    $Return.Error_Count++ 
}
# END REGION

# REGION Repair VHD files
try {
    # Cleanup Windows image backups
    if (!($Return.Windows_Image_Backups -eq 'No Windows 7 image backups found')) {
        # Store the results
        $Return.VHD_Mount_Results = ''
        $Return.VHD_Repair_Results = ''     
        # Work thorugh list building a list of VHD files
        foreach ($item in $Return.Windows_Image_Backups) {
            $Return.VHD_Mount_Results += VHD-Mount -VhdType $VHDMethod -Path $item | Out-String
            # Get the drive letter
            $myDrive = (Get-DiskImage $item | Get-Disk | Get-Partition | `
              Select-Object DriveLetter).DriveLetter | Select-Object -Last 1
            # Add a colon
            $myDrive = $myDrive + ':'
            #Make some pretty output
            $Return.VHD_Repair_Results += "`n---------------------------`n"
            $Return.VHD_Repair_Results += "Starting disk check on $myDrive`n"
            $Return.VHD_Repair_Results += "---------------------------`n`n"
            $Return.VHD_Repair_Results += . CHKDSK.exe $myDrive /F | Out-String
            $Return.VHD_Mount_Results += VHD-Dismount -VhdType $VHDMethod -Path $item | Out-String
        }
    }
}
catch {
    $myException = $_.Exception | Format-List | Out-String
    $Return.VHD_Repair_Catch = $myException 
    $Return.Error_Count++ 
}
# END REGION

# REGION Output results and create an alert if needed
if ($Return.Error_Count -eq 0) {
    Write-Output @"
    
Script Success!
Troubleshooting info below
_______________________________
   
"@
    $Return | Format-List | Out-String
    if (Test-Path $Return.Error_File) {
        Remove-Item $Return.Error_File
    }
    Exit 0
    }
else {
    Write-Output @"
    
Script Failure!
Troubleshooting info below
_______________________________

"@
    $Return | Format-List | Out-String
    Add-Content -Path $Return.Error_File -Value "`n----------------------`n "
	Add-Content -Path $Return.Error_File -Value (get-date) -passthru
	Add-Content -Path $Return.Error_File -Value "`n "
	Add-Content -Path $Return.Error_File -Value ( $Return | Format-List | Out-String )
    Exit 1001
}
# END REGION