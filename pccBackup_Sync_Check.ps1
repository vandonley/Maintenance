<#
.Synopsis
   Uses Posh-SSH module to check that backup files are syncing to a remote host
   and trigger an alert in MaxRM if it fails.
.DESCRIPTION
   The script is to be uploaded to your dashboard account as a user script.
   It can run both as a script check and as a scheduled task.
   
.EXAMPLE
   pccCheck-BackupSync my.bdr.com admin MyPassword 
.EXAMPLE
   pccCheck-BackupSync -sftpHost my.bdr.com -sftpUser admin -Password MyPassword 
.EXAMPLE
   pccCheck-BackupSync -sftpHost 10.10.10.10 -sftpUser admin -Password MyPassword -sftpPort 22 -sftpPath /mnt/array1/shadowprotect/ServerName -sftpVolumes "System,C_VOL,D_VOL" -sftpMinimum 1 -sftpDays 2
.OUTPUTS
   Filenames and dates
.LINK
   https://github.com/darkoperator/Posh-SSH
.EMAIL
   VanD@ParsecComputer.com
.VERSION
   1.0
#>
  
Param(
    # Hostname or IP address of backup target
    [Parameter(Mandatory=$True,Position=1)]
    [string]
    $sftpHost,

    # Backup target username
    [Parameter(Mandatory=$True,Position=2)]
    [string]
    $sftpUser,

    # Backup target password
    [Parameter(Mandatory=$True,Position=3)]
    [string]$Password,

    # Backup target port for SFTP (Default is 22)
    [Parameter()]
    [int32]$sftpPort = '22',

    # Path to backup folder (Defaults to '.' and checks entire host recursively)
    [Parameter()]
    [string]$sftpPath = ".",

    # Backup partition names to look for. Defaults to C_VOL. Enter multiples as an array using commas enclosed in a set of double quotes, ie. "System,C_VOL,D_VOL"
    [Parameter()]
    [string[]]
    $sftpVolumes = 'C_VOL',

    # Minimum count of each volume to look for. Default is 1
    [Parameter()]
    [int16]
    $sftpMinimum = '1',

    # Number of days to check history. Default is 2
    [Parameter()]
    [int16]
    $sftpDays = '2',

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
    $NuGet = Get-PackageProvider -Name NuGet -WarningAction Continue -ErrorAction Continue
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
    $Repository = Get-PSRepository -Name PSGallery -WarningAction Continue -ErrorAction Continue
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

# Check if Posh-SSH module is installed
try {
    $SSH = Get-InstalledModule -Name Posh-SSH
        if (! $SSH) {
            Write-Host 'Posh-SSH not installed - Fixing'
            $SSH = Find-Module -Name Posh-SSH -WarningAction Continue -ErrorAction Continue | Install-Module -Force -WarningAction Continue -ErrorAction Continue -Verbose
        }
    else {
        $Return.SSH = $SSH  | Select-Object Name,Version
        }
    }
    catch  [EXCEPTION] {
        $_.Exception | Format-List -Force
        $FailCount = $FailCount + 1
        }

# Import Posh-SSH module
try {
    Import-Module -Name Posh-SSH -Force -WarningAction Continue -ErrorAction Continue
    $PoshSSH = Get-Module -Name Posh-SSH -WarningAction Continue -ErrorAction Continue
    if (! $PoshSSH) {
        $Return.PoshSSH = "Posh-SSH module import failed"
        $FailCount = $FailCount + 1
    }
    else {
        $Return.PoshSSH = "Posh-SSH module imported successfully"
    }
    }
    catch {
        $_.Exception | Format-List -Force
        $FailCount = $FailCount + 1
    }

# Create credential from plain-text username and password
try {
    $SecurePass = ConvertTo-SecureString $Password -AsPlainText -Force -WarningAction Continue -ErrorAction Continue
    $Cred = New-Object System.Management.Automation.PSCredential($sftpUser,$SecurePass) -WarningAction Continue -ErrorAction Continue
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

# Create SFTP connection
try {
    New-SFTPSession -ComputerName $sftpHost -Credential $Cred -AcceptKey -Port $sftpPort  -WarningAction Continue -ErrorAction Continue > $Return.ConnectionResult
    $SFTPSession = Get-SFTPSession -PipelineVariable SessionId -WarningAction Continue -ErrorAction Continue | Where-Object {$_.Host -eq $sftpHost -and $_.Connected -eq $True}
    if (! $SFTPSession) {
        $Return.SFTPSession = "SFTP connection failed"
        $FailCount = $FailCount + 1
    }
    else {
        $Return.SFTPSession = "SFTP connection succeeded"
        }
    }
    catch {
        $_.Exception | Format-List -Force
        $FailCount = $FailCount + 1
    }

# Get file list and check that correct number of files are present
try {
        foreach ($sftpVolume in $sftpVolumes) {
        $BackupCheck = Get-SFTPChildItem -SessionId $SFTPSession.SessionId -Path $sftpPath -Recursive -WarningAction Continue -ErrorAction Continue | `
         Where-Object {($_.FullName -like "*.spi") -and ($_.FullName -like "*$sftpVolume*") -and ($_.LastWriteTime -ge (Get-Date).AddDays(-$sftpDays)) }
        if ($BackupCheck.count -lt $sftpMinimum ) {
            Write-Host "$sftpVolume backup file sync check failed or minimum number of files not met"
            $FailCount = $FailCount + 1
        } 
        else {
            Write-Host "$sftpVolume backup file sync check succeeded"
        }
    }
    }
    catch {
        $_.Exception | Format-List -Force
        $FailCount = $FailCount + 1
    }

# Cleanup and report success or failure
try {
    $SFTPSession | Remove-SFTPSession >$Return.SessionCleanup
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