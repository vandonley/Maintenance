<#
.Synopsis
   Uses PSFTP module to check that backup files are syncing to a remote host
   and trigger an alert in MaxRM if it fails.
.DESCRIPTION
   The script is to be uploaded to your dashboard account as a user script.
   It can run both as a script check and as a scheduled task.
   
.EXAMPLE
   pccBackup_Sync_Check-FTP my.bdr.com admin MyPassword 
.EXAMPLE
   pccBackup_Sync_Check-FTP -ftpHost my.bdr.com -ftpUser admin -Password MyPassword 
.EXAMPLE
   pccBackup_Sync_Check-FTP -ftpHost 10.10.10.10 -ftpUser admin -Password MyPassword -ftpPath /mnt/array1/shadowprotect/ServerName -ftpVolumes "System,C_VOL,D_VOL" -ftpMinimum 1 -ftpDays 2
.OUTPUTS
   Filenames and dates
.LINK
   https://gallery.technet.microsoft.com/scriptcenter/PowerShell-FTP-Client-db6fe0cb
.EMAIL
   VanD@ParsecComputer.com
.VERSION
   1.0
#>
  
Param(
    # Hostname or IP address of backup target
    [Parameter(Mandatory=$True,Position=1)]
    [string]
    $ftpHost,

    # Backup target username
    [Parameter(Mandatory=$True,Position=2)]
    [string]
    $ftpUser,

    # Backup target password
    [Parameter(Mandatory=$True,Position=3)]
    [string]$Password,

    # Path to backup folder (Defaults to '.' and checks entire host recursively)
    [Parameter()]
    [string]$ftpPath = ".",

    # Backup partition names to look for. Defaults to C_VOL. Enter multiples as an array using commas enclosed in a set of double quotes, ie. "System,C_VOL,D_VOL"
    [Parameter()]
    [string[]]
    $ftpVolumes = 'C_VOL',

    # Minimum count of each volume to look for. Default is 1
    [Parameter()]
    [int16]
    $ftpMinimum = '1',

    # Number of days to check history. Default is 2
    [Parameter()]
    [int16]
    $ftpDays = '2',

    # A parameter always supplied by MAXfocus. We MUST accept it.
    [Parameter()]
    [string]
    $logfile
)

# Force the script to output something to STDOUT, else errors may cause script timeout.
Write-Host " "

# Create array for troubleshooting and output and create error counter
[hashtable]$Return = @{}
[int16]$FailCount = 0

# Check if NuGet is registered as a package provider and install it if it is not
try {
    $NuGet = Get-PackageProvider -WarningAction Continue -ErrorAction Continue | Where-Object Name -EQ NuGet
        if (! $NuGet) {
            Write-Host 'NuGet not installed - Fixing'
            $Return.NuGet = Install-PackageProvider -Name NuGet -Force -WarningAction Continue -ErrorAction Continue -Verbose
            }
        else {
            $Return.Nuget = $NuGet
            }
    }
    catch [EXCEPTION] {
        $_.Exception | Format-List -Force
        $FailCount = $FailCount + 1
    }

# Check if PSGallery is a repository location and that it is trusted to make installs easier
try {
    $Repository = Get-PSRepository -WarningAction Continue -ErrorAction Continue | Where-Object Name -EQ PSGallery
        if (! $Repository) {
            Write-Host 'PSGallery not installed - Fixing'
            $Return.Repository = Register-PSRepository -Name PSGallery -SourceLocation https://www.powershellgallery.com/api/v2/ -PublishLocation `
             https://www.powershellgallery.com/api/v2/package/ -ScriptSourceLocation https://www.powershellgallery.com/api/v2/items/psscript/ `
             -ScriptPublishLocation https://www.powershellgallery.com/api/v2/package/ -InstallationPolicy Trusted -PackageManagementProvider NuGet `
             -WarningAction Continue -ErrorAction Continue -Verbose
            }
        elseif ($Repository.InstallationPolicy -eq "Untrusted") {
            Write-Host 'PSGallery not trusted - Fixing'
            $Return.Repository = Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -WarningAction Continue -ErrorAction Continue -Verbose
            }
        else {
            $Return.Repository = "PSGallery installed and trusted"
            }
    }
    catch [EXCEPTION] {
        $_.Exception | Format-List -Force
        $FailCount = $FailCount + 1
        }

# Check if PSFTP module is installed
try {
    $FTP = Get-InstalledModule | Where-Object Name -EQ PSFTP
        if (! $FTP) {
            Write-Host 'PSFTP not installed - Fixing'
            $FTP = Find-Module -Name PSFTP -WarningAction Continue -ErrorAction Continue | Install-Module -Force -WarningAction Continue -ErrorAction Continue -Verbose
        }
    else {
        $Return.FTP = $FTP  | Select-Object Name,Version
        }
    }
    catch  [EXCEPTION] {
        $_.Exception | Format-List -Force
        $FailCount = $FailCount + 1
        }

# Import PSFTP module
try {
    Import-Module -Name PSFTP -Force -WarningAction Continue -ErrorAction Continue
    $PoshFTP = Get-Module | Where-Object Name -EQ PSFTP
    if (! $PoshFTP) {
        $Return.PoshFTP = "PSFTP module import failed"
        $FailCount = $FailCount + 1
    }
    else {
        $Return.PoshFTP = "PSFTP module imported successfully"
    }
    }
    catch {
        $_.Exception | Format-List -Force
        $FailCount = $FailCount + 1
    }

# Create credential from plain-text username and password
try {
    $SecurePass = ConvertTo-SecureString $Password -AsPlainText -Force -WarningAction Continue -ErrorAction Continue
    $Cred = New-Object System.Management.Automation.PSCredential($ftpUser,$SecurePass) -WarningAction Continue -ErrorAction Continue
    if (! $Cred) {
        $Return.Credential = "Secure credental creation failed"
        $FailCount = $FailCount + 1
    }
    else {
        $Return.Credential = "Secure credential creation succeeded"
        }
        }
    catch {
        $_.Exception | Format-List -Force
        $FailCount = $FailCount + 1
    }

# Create FTP connection
try {
    Set-FTPConnection -Credentials $Cred -Server $ftpHost -UsePassive -Session BackupCheck -WarningAction Continue -ErrorAction Continue > $Return.ConnectionResult
    $FTPConnection = Get-FTPConnection -Session BackupCheck -WarningAction Continue -ErrorAction Continue
    if (! $FTPConnection) {
        $Return.FTPConnection = "FTP connection failed"
        $FailCount = $FailCount + 1
    }
    else {
        $Return.FTPConnection = "FTP connection succeeded"
        }
    }
    catch {
        $_.Exception | Format-List -Force
        $FailCount = $FailCount + 1
    }

# Get file list and check that correct number of files are present
try {
        foreach ($ftpVolume in $ftpVolumes) {
        $BackupCheck = Get-FTPChildItem -Session $FTPConnection.Session -Path $ftpPath -Recurse -WarningAction Continue -ErrorAction Continue | `
         Where-Object {($_.Name -like "*.spi") -and ($_.Name -like "*$ftpVolume*") -and ($_.ModifiedDate -ge (Get-Date).AddDays(-$ftpDays)) }
        if ($BackupCheck.count -lt $ftpMinimum ) {
            Write-Host "$ftpVolume backup file sync check failed or minimum number of files not met"
            $FailCount = $FailCount + 1
        } 
        else {
            Write-Host "$ftpVolume backup file sync check succeeded"
        }
    }
    }
    catch {
        $_.Exception | Format-List -Force
        $FailCount = $FailCount + 1
    }

# Cleanup and report success or failure
try {
    if ($FailCount -eq 0) {
        Write-Host " 
_________________________________
 
All backup volumes passed check

Troubleshooting info below
_________________________________
 
"
    $Return | Format-List -Force
    }
    else {
        $Error.Clear()
        [string]$ErrorString = "Check Failure - Volumes with errors:  $FailCount"
        [string]$ErrMessage = ( $Return | Format-List | Out-String )
        $Error.Add($ErrorString)
        Write-Error -Exception $ErrorString -ErrorId 1001 -Message $ErrMessage
        Exit 1001
        }
    }
    catch {
        $_.Exception | Format-List -Force
        $FailCount = $FailCount + 1
    }