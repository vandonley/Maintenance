<#
.Synopsis
   Delete files from C:\Windows\Logs\CBS when it grows to large.
.DESCRIPTION
   The script is to be uploaded to your dashboard account as a user script.
   It can run both as a script check and as a scheduled task.   
.EXAMPLE
   vitCleanup-CBSLogs.ps1
.OUTPUTS
   Deletes files.
.EMAIL
   vdonley@visionms.net
.VERSION
   1.0
#>


<#
 Others optional but must accept -logfile from MaxRM.
#>  
param (	
	# Make sure -logfile is NOT positional
	[Parameter(Mandatory=$false)]
	[string]$logfile
)

# Set error and warning preferences
$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"

# Output the starting contents of the folder
Write-Host @" 
Starting Folder Contents
----------------------------------

"@
Get-ChildItem C:\Windows\Logs\CBS
# Delete the files, redirect error output to stdout
Write-Host @"
----------------------------------

Deleting files
----------------------------------

"@
Remove-Item C:\Windows\Logs\CBS\* -Force 2>&1
# Output the ending contents of the folder
Write-Host @" 
----------------------------------

Ending Folder Contents
----------------------------------

"@
Get-ChildItem C:\Windows\Logs\CBS