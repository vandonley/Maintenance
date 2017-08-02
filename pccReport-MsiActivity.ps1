<#
.Synopsis
   Creates a report of install and uninstall events in the Application log.
   Can set number of days with -Days or default to 30.
.DESCRIPTION
   The script is to be uploaded to your dashboard account as a user script.
   It can run both as a script check and as a scheduled task. Expects to be
   used with pccCheck-RMMFolders.ps1
.EXAMPLE
   pccReport-MsiActivity
.EXAMPLE
   pccReport-MsiActivity -Days 10
.OUTPUTS
   HTML report to dashboard and file in the RMM\Reports folder 
.EMAIL
   VanD@ParsecComputer.com
.VERSION
   1.0
#>
  
Param(
    # Number of days of logs to check (Defaults to 30)
    [Parameter()]
    [int32]$Days = '30',

    # A parameter always supplied by MaxRM. We MUST accept it.
    [Parameter()]
    [string]
    $logfile
)

# Force the script to output something to STDOUT, else errors may cause script timeout.
Write-Host " "

# Create array for troubleshooting and output and create error counter
[hashtable]$Return = @{}
[int16]$FailCount = 0

# Get variables ready, make $Days negative
$myDays = '-' + $Days
$myDate = Get-Date
$ReportPath = $env:RMMFolder + "\Reports"
$ReportFile = $ReportPath + "\pccReport-MsiActivity.html"

# Create a header for the report
$ReportTitle = @"
<h1><span style="color: #0000ff;">MSI Installer Changes ($myDays days)</span></h1>
<p><span style="color: #333333;"><em>Report Generated $myDate</em></span></p>
"@

# Format the output for the table
$InstalledHead = '<table cellspacing="2" cellpadding="4"><caption><h2><span style="color: #008000;">Software Installed</span></h2></caption>'

# Format the output for the table
$UninstalledHead = '<table cellspacing="2" cellpadding="4"><caption><h2><span style="color: #ff0000;">Software Uninstalled</span></h2></caption>'

# Get a list of installed software and turn it into an HTML table. Then apply formatting.
$InstalledSoftware = Get-EventLog -LogName Application -After ((Get-Date).AddDays($myDays)) -Source MsiInstaller -InstanceId 11707 -ErrorAction SilentlyContinue | `
Select @{L='Date/Time';E={$_.TimeWritten}},@{L='Software Package';E={$_.Message -replace ".*Product: " -replace " -- Install.*"}},@{L='User Name';E={$_.UserName}} | `
Sort-Object TimeWritten | ConvertTo-Html -Fragment

if ($InstalledSoftware.Count -le '2') {
    $InstalledSoftware = @"
$InstalledHead
<colgroup><col /><col /><col /></colgroup>
<tr><th>Date/Time</th><th>Software Package</th><th>User Name</th></tr>
<tr><td></td><td>No Installs Found</td><td></td></tr>
</table>
"@
}

else {
    $InstalledSoftware = $InstalledSoftware -replace '<table>', $InstalledHead
}

# Get a list of uninstalled software and turn it into an HTML table. Then apply formatting.
$UninstalledSoftware = Get-EventLog -LogName Application -After ((Get-Date).AddDays($myDays)) -Source MsiInstaller -InstanceId 11727 -ErrorAction SilentlyContinue | `
Select @{L='Date/Time';E={$_.TimeWritten}},@{L='Software Package';E={$_.Message -replace ".*Product: " -replace " -- Install.*"}},@{L='User Name';E={$_.UserName}} | `
Sort-Object TimeWritten | ConvertTo-Html -Fragment

if ($UninstalledSoftware.Count -le '2') {
    $UninstalledSoftware = @"
$UninstalledHead
<colgroup><col /><col /><col /></colgroup>
<tr><th>Date/Time</th><th>Software Package</th><th>User Name</th></tr>
<tr><td></td><td>No Uninstalls Found</td><td></td></tr>
</table>
"@
}

else {
    $UninstalledSoftware = $UninstalledSoftware -replace '<table>', $UninstalledHead
}

# Generate the HTML for output
$Output = @"
$ReportTitle
$InstalledSoftware
<p>&nbsp;&nbsp;</p>
$UninstalledSoftware
"@

Write-Host $Output
Out-File -FilePath $ReportFile -InputObject $Output -Force