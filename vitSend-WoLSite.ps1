<#
.Synopsis
   Send Wake on LAN packets to all MAC's in a Solar Winds RMM site.
.DESCRIPTION
   The script is to be uploaded to your dashboard account as a user script.
   It can run both as a script check and as a scheduled task. You must provide
   the API key and Site ID's as parameters on the command line. Intended to
   be used with vit-Check-RMMDefaults for error tracking and reporting.
   Requires Carbon module.
.EXAMPLE
   vitSend-WoLSite.ps1 -APIKey MyAPIKeyHere -SiteID SiteID1,SiteID2
.OUTPUTS
   Wake on LAN packets and text log
.EMAIL
   vdonley@visionms.net
.VERSION
   1.0
#>

# Must accept -logfile
param (
    # API key to use in the URL
    [Parameter(Mandatory=$true)]
    [string]
    $APIKey,

    # Array of Site ID's to get MAC's from
    [Parameter(Mandatory=$true)]
    [array]
    $SiteID,

	# Make sure -logfile is NOT positional
	[Parameter(Mandatory=$false)]
	[string]$logfile
)

# Set error and warning preferences
$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"

# Force output to keep MaxRM from timing out
Write-Host ' '

# Array to collect MAC"s and machine info
$myMACs = @()
$myMachineInfo = @()

# URL to retrieve site information
$APIURL = "https://www.systemmonitor.us/api/?apikey=$APIKey"

# Create hashtable for output. Make it stay in order and start an error counter to create an alert if needed.
$Return = [ordered]@{}
$Return.Error_Count = 0

# REGION Functions
# Send WoL packets to MAC's
function Send-WOLPacket {
    param (
        # Array of MAC's to send WOL packets 
        [Parameter(Mandatory=$false)]
        [array]
        $MACList
    )
try {
        # Make sure MACList is populated
        if ($MACList) {
            # Create the broadcast address
            $Broadcast = ([System.Net.IPAddress]::Broadcast)
            # Create IP endpoints for each port
            $IPEndPoint1 = New-Object Net.IPEndPoint $Broadcast, 0
            $IPEndPoint2 = New-Object Net.IPEndPoint $Broadcast, 7
            $IPEndPoint3 = New-Object Net.IPEndPoint $Broadcast, 9
            # Send the packets
            foreach ($MAC in $MACList) {
                # Format the MAC
                $MAC = $MAC -replace '-',''
                $MAC = $MAC -replace ':',''
                # Change string to byte array
                $MAC = [Net.NetworkInformation.PhysicalAddress]::Parse($MAC)
                # Create the magic packet
                # Construct the Magic Packet frame
                $Frame = [byte[]]@(255,255,255, 255,255,255);
                $Frame += ($MAC.GetAddressBytes()*16)
                # Send the packet
                $UDPClient = New-Object System.Net.Sockets.UdpClient
                # Number of times to send the packet
                $AttemptCount = (1..3)
                foreach ($i in $AttemptCount) {
                    $UdpClient.Send($Frame, $Frame.Length, $IPEndPoint1) | Out-Null
                    $UdpClient.Send($Frame, $Frame.Length, $IPEndPoint2) | Out-Null
                    $UdpClient.Send($Frame, $Frame.Length, $IPEndPoint3) | Out-Null
                    Start-Sleep -Seconds 1
                }
                $UDPClient.Close()
            }
            return "Magic packets sent"
        }
        else {
            # Exit if there are no MAC's
            return "No MAC's, function failed"
        }
    }
    catch {
        $myException = $_.Exception | Format-List | Out-String
        return $myException
    }
}
# END REGION

# REGION Reporting setup
try {
    # Information about the script for reporting.
    $ErrorFileName = "vitSend-WoLSite.txt"
    # File name for ScriptRunnter
    $Return.RMM_Script_Name = $MyInvocation.MyCommand.Name
    # Check to see if the RMM Error Folder exists. Put the Error file in %TEMP% if it doesn't.
    if (Test-Path $env:RMMErrorFolder) {
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

# REGION Build the list of computers to wake
try {
    # Go through each site ID
    foreach ($item in $SiteID) {
        # Build the URL and download XML
        $SiteURL = "$($APIURL)&service=list_workstations&siteid=$item"
        [xml]$XMLSite = (new-object System.Net.WebClient).DownloadString($SiteURL)
        # Build return information and MAC list by adding it to $myMachineInfo and $myMACs
        foreach ($Workstation in $XMLSite.result.items.workstation) {
            $WorkstationInfo = [pscustomobject]@{}
            $WorkstationInfo | Add-Member -MemberType NoteProperty -Name "Name" -Value $Workstation.name."#cdata-section"
            $WorkstationInfo | Add-Member -MemberType NoteProperty -Name "Last_IP" -Value $Workstation.ip."#cdata-section"
            $MAC1 = $Workstation.mac1."#cdata-section"
            if ($MAC1.Length -eq 17) {
                $WorkstationInfo | Add-Member -MemberType NoteProperty -Name "MAC_1" -Value $MAC1
                $myMACs += $MAC1
            }
            else {
                $WorkstationInfo | Add-Member -MemberType NoteProperty -Name "MAC_1" -Value "Null"
            }
            $MAC2 = $Workstation.mac2."#cdata-section"
            if ($MAC2.Length -eq 17) {
                $WorkstationInfo | Add-Member -MemberType NoteProperty -Name "MAC_2" -Value $MAC2
                $myMACs += $MAC2
            }
            else {
                $WorkstationInfo | Add-Member -MemberType NoteProperty -Name "MAC_2" -Value "Null"
            }
            $MAC3 = $Workstation.mac3."#cdata-section"
            if ($MAC3.Length -eq 17) {
                $WorkstationInfo | Add-Member -MemberType NoteProperty -Name "MAC_3" -Value $MAC3
                $myMACs += $MAC3
            }
            else {
                $WorkstationInfo | Add-Member -MemberType NoteProperty -Name "MAC_3" -Value "Null"
            }
            $myMachineInfo += $WorkstationInfo
        }
    }
}
catch {
    $myException = $_.Exception | Format-List | Out-String
    $Return.XML_Processing_Catch = $myException 
    $Return.Error_Count++ 
}
# END REGION

# REGION Send magic packets
try {
    $Return.Magic_Packets_Output = Send-WOLPacket -MACList $myMACs
    if (!($Return.Magic_Packets_Output -eq "Magic packets sent")) {
        $Return.Error_Count++
    }
}
catch {
    $myException = $_.Exception | Format-List | Out-String
    $Return.Magic_Packet_Catch = $myException 
    $Return.Error_Count++
}
# END REGION

# REGION Output results and create an alert if needed
# Add the XML processing output to the return in case it is long....
$Return.Workstation_Information = $myMachineInfo | Sort-Object -Property 'Name' | Format-List | Out-String
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