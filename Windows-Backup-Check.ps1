$after = [datetime]::Now.AddDays(-1)
$logs = Get-WinEvent Microsoft-Windows-Backup | Where-Object { $_.TimeCreated -ge $after }
if (!($logs)) {
Write-Host "No backup events found!"
Exit 1001
}
$errors = $logs | Where-Object { $_.LevelDisplayName -ne "Information" }
if ($errors) {
Write-Host "Backup errors found!"
Write-Host "--------------------------"
$errors | Format-List | Out-String
Exit 1001
}
$success = $logs | Where-Object { ($_.id -eq 4) -and ($_.Message -eq "The backup operation has finished successfully.") }
if (!($success)) {
Write-Host "No successfull backup found!"
Exit 1001
}
else {
Write-Host "Backup Success!"
Exit 0
}