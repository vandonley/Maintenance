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
   pccCheck-BackupSync -Host my.bdr.com -User admin -Password MyPassword 
.EXAMPLE
   pccCheck-BackupSync -Host 10.10.10.10 -User admin -Password MyPassword -Port 22 -Path /mnt/array1/shadowprotect/ServerName -Volumes "System,C_VOL,D_VOL" -Minimum 1 -Days 2
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
    $Host,

    # Backup target username
    [Parameter(Mandatory=$True,Position=2)]
    [string]
    $User,

    # Backup target password
    [Parameter(Mandatory=$True,Position=3)]
    [string]$Password,

    # Backup target port for SFTP (Default is 22)
    [Parameter()]
    [int32]$Port = '22',

    # Path to backup folder (Defaults to '.' and checks entire host recursivly)
    [Parameter()]
    [string]$Path = '.',

    # Backup partition names to look for. Defaults to C_VOL. Enter multiples as an array using commas enclosed in a set of double quotes, ie. "System,C_VOL,D_VOL"
    [Parameter()]
    [string[]]
    $Volumes = 'C_VOL',

    # Minimum count of each volume to look for. Default is 1
    [Parameter()]
    [int16]
    $Minimum = '1',

    # Number of days to check history. Default is 2
    [Parameter()]
    [int16]
    $Days = '2',

    # A parameter always supplied by MAXfocus. We MUST accept it.
    [Parameter()]
    [string]
    $logfile
)

# Force the script to output something to STDOUT, else errors may cause script timeout.
Output-Host " "

# Create array for troubleshooting and output
[hashtable]$Return = @{}

# Check if NuGet is registered as a package provider and install it if it is not
try {
    $NuGet = Get-PackageProvider -Name NuGet -WarningAction Continue -ErrorAction Continue
        if (-not $NuGet) {
            Output-Host 'NuGet not installed - Fixing'
            $Return.NuGet = Install-PackageProvider -Name NuGet -Force -WarningAction Continue -ErrorAction Continue -Verbose
            }
        else {
            $Return.Nuget = $NuGet
            }
    }

    catch [EXCEPTION] {
        $_.Exception | Format-List -Force
    }

# Check if PSGallery is a repository location and that it is trusted to make installs easier
try {
    $Repository = Get-PSRepository -Name PSGallery -WarningAction Continue -ErrorAction Continue
        if (-not $Repository) {
            Output-Host 'PSGallery not installed - Fixing'
            $Return.Repository = Register-PSRepository -Name PSGallery -SourceLocation https://www.powershellgallery.com/api/v2/ -PublishLocation `
             https://www.powershellgallery.com/api/v2/package/ -ScriptSourceLocation https://www.powershellgallery.com/api/v2/items/psscript/ `
             -ScriptPublishLocation https://www.powershellgallery.com/api/v2/package/ -InstallationPolicy Trusted -PackageManagementProvider NuGet `
             -WarningAction Continue -ErrorAction Continue -Verbose
            }
        elseif (-not $Repository.InstallationPolicy -eq "Trusted") {
            Output-Host 'PSGallery not trusted - Fixing'
            $Return.Repository = Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -WarningAction Continue -ErrorAction Continue -Verbose
            }
        else {
            $Return.Repository = $PSGallery | Select-Object Name,Registered,InstallationPolicy
            }
    }

    catch [EXCEPTION] {
        $_.Exception | Format-List -Force
        }

# Check if Posh-SSH module is installed
try {
    $SSH = Get-InstalledModule -Name Posh-SSH
        if (-not $SSH) {
            Output-Host 'Posh-SSH not installed - Fixing'
            $SSH = Find-Module -Name Posh-SSH -WarningAction Continue -ErrorAction Continue | Install-Module -Force -WarningAction Continue -ErrorAction Continue -Verbose
        }
    else {
        $Return.SSH = $SSH  | Select-Object Name,Version
    }
    }
    catch  [EXCEPTION] {
        $_.Exception | Format-List -Force
        }

# Import Posh-SSH module
try {
    Import-Module -Name Posh-SSH -Force -WarningAction Continue -ErrorAction Continue
    $PoshSSH = Get-Module -Name Posh-SSH -WarningAction Continue -ErrorAction Continue
    if (-not $PoshSSH) {
        $Return.PoshSSH = "Posh-SSH module import failed"
    }
    else {
        $Return.PoshSSH = "Posh-SSH module imported successfully"
    }
    }
    catch {
        $_.Exception | Format-List -Force
    }

# Create credential from plain-text username and password
try {
    $SecurePass = ConvertTo-SecureString $Password -AsPlainText -Force -WarningAction Continue -ErrorAction Continue
    $Cred = New-Object System.Management.Automation.PSCredential($User,$SecurePass) -WarningAction Continue -ErrorAction Continue
    if (-not $Cred) {
        $Return.Credential = "Secure credental creation failed"
    }
    else {
        $Return.Credential = "Secure credential creation succeeded"
    }
    }
catch {
    $_.Exception | Format-List -Force
    }

# Create SFTP connection
try {
    New-SFTPSession -ComputerName $Host -Credential $Cred -AcceptKey -Force -Port $Port -WarningAction Continue -ErrorAction Continue
    $SFTPSession = Get-SFTPSession -SessionId * -WarningAction Continue -ErrorAction Continue
    if (-not $SFTPSession) {
        $Return.SFTPSession = "SFTP connection failed"
    }
    else {
        $Return.SFTPSession = "SFTP connection succeeded"
    }

    }
    catch {
        $_.Exception | Format-List -Force
    }

# Get file list and check that correct number of files are present
try {
    [int16]$FailCount = 0
    foreach ($Volume in $Volumes) {
        $BackupCheck = Get-SFTPChildItem -SessionId $SFTPSession.SessionId -Path $Path -Recursive -WarningAction Continue -ErrorAction Continue | `
         Where-Object {($_.FullName -like '*.spi') -and ($_.FullName -like '*$Volume*') -and ($_.LastWriteTime -ge (Get-Date).AddDays(-$Days)) }
        if (-not $BackupCheck.count -ge $Minimum ) {
            Output-Host "$Volume backup file sync check failed or minimum number of files not met"
            $FailCount = $FailCount +1
        } 
        else {
            Output-Host "$Volume backup file sync check succeeded"
        }
    }
    }
    catch {
        $_.Exception | Format-List -Force
    }

# Cleanup and report success or failure
try {
    Remove-SFTPSession -SessionId *
    if ($FailCount -eq 0) {
        Output-Host " 
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
}