<#
.Synopsis
   Runs Windows Disk Cleanup with all available options
.DESCRIPTION
   The script is to be uploaded to your dashboard account as a user script.
   It can run both as a script check and as a scheduled task. Expects to be run
   with vitCheck-RMMDefaults.ps1
   
.EXAMPLE
   .\vitClean-Disk.ps1
.OUTPUTS
   Error file
.EMAIL
   vdonley@visionit.net
.VERSION
   1.0
#>

# We are only binding -logfile.
param (	
	# Make sure -logfile is NOT positional
	[Parameter(Mandatory=$false)]
    [string]$logfile
)

# Set error and warning preferences
$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"

# Force output to keep RMM from timing out
Write-Host ' '

# Create hashtable for output. Make it stay in order and start an error counter to create an alert if needed. Divide by 1 to force integer
$Return = [ordered]@{}
$Return.Error_Count = 0

# REGION Reporting setup
try {
    # Information about the script for reporting.
    $ErrorFileName = "vitClean-Disk.txt"
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

# REGION Prerequisites
try {
    # Path to Disk Cleanup
    $DiskCleanPath = $env:windir + '\system32\cleanmgr.exe'
    # Make sure Disk Cleanup is installed, exit if it is not
    if (Test-Path $DiskCleanPath) {
        $Return.Disk_Cleanup_Found = $DiskCleanPath
    }
    else {
        $Return.Disk_Cleanup_Found = "Error - Disk Cleanup not found, install or remove task"
        Write-Output @"
    
Script could not run!
Troubleshooting info below
_______________________________
    
"@
        $Return | Format-List | Out-String
        Exit 0
    }
}
catch {
    $myException = $_.Exception | Format-List | Out-String
    $Return.Prerequisite_Catch = $myException 
    $Return.Error_Count++ 
}
# END REGION

# REGION Get Windows version for new disk cleanup options
try {
    $myInfo = Get-WmiObject -Class Win32_OperatingSystem
    $Return.Product_Information = $myInfo.Caption
    $Return.Product_Version = $myInfo.Version
}
catch {
    $myException = $_.Exception | Format-List | Out-String
    $Return.Version_Catch = $myException 
    $Return.Error_Count++ 
}
# END REGION

# REGION Run Disk Cleanup
try
    {
    # If Windows version is 10, do this the easy way
    if ($Return.Product_Version -like "10.*") {
        $Return.Disk_Cleanup_Result = Start-Process -FilePath $DiskCleanPath -ArgumentList "/verylowdisk" -Wait -NoNewWindow | Out-String
    }
    else {
        # Registry key information for Disk Cleanup
        $strKeyPath   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        $strValueName = "StateFlags0042"
        $subkeys      = Get-ChildItem -Path $strKeyPath -Name
        
        # Set all options to run in registry
        ForEach($subkey in $subkeys) {
            $null = New-ItemProperty -Path $strKeyPath\$subkey -Name $strValueName -PropertyType DWord -Value 2
        }
        $Return.Registry_Keys_Update = "Success"
        
        # Run Disk Cleanup
        $Return.Disk_Cleanup_Result = Start-Process -FilePath $DiskCleanPath -ArgumentList "/sagerun:42" -Wait -NoNewWindow | Out-String
        
        #Remove the registry keys
        ForEach($subkey in $subkeys) {
            $null = Remove-ItemProperty -Path $strKeyPath\$subkey -Name $strValueName
        }
            $Return.Registry_Keys_Delete = "Success"
    }
}
catch { 
    $myException = $_.Exception | Format-List | Out-String
    $Return.Disk_Cleanup_Catch = $myException 
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