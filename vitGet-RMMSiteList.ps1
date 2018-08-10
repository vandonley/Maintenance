<#
.Synopsis
   Generate a list of clients and sites from Solar Winds RMM.
.DESCRIPTION
   Edit script to insert correct API key.
.EXAMPLE
   vitGet-RMMSiteList
.OUTPUTS
  Grid view and CSV file saved to users desktop.
.EMAIL
   vdonley@visionms.net
.VERSION
   1.0
#>
#Your API key
$APIKey = "MyAPIKey"
# URL to retrieve client list
$ClientURL = "https://www.hound-dog.us/api/?apikey=$APIKey&service=list_clients"
# Date for the CSV file
$myDate =  Get-Date -Format yyyy_MM_dd
# Save the CSV file to the user's desktop
$myCSV = [System.Environment]::GetFolderPath("Desktop") + "\RMM_Site_List-{0}.csv" -f $myDate
# Array to save the information too
$SiteList = @()

# Get the list of RMM clients
[xml]$XMLClients = (New-Object System.Net.WebClient).DownloadString($ClientURL)

# Get the name and ID of each client
foreach ($XMLClientsList in $XMLClients.result.items.client) {
    $Client_Name = $XMLClientsList.name."#cdata-section"
    $Client_ID = $XMLClientsList.clientid
    # URL to retrieve site list for each client
    $SitesURL = "https://www.hound-dog.us/api/?apikey=$APIKey&service=list_sites&clientid=$Client_ID"
    # Get the list of sites for each client
    [xml]$XMLSites = (new-object System.Net.WebClient).DownloadString($SitesURL)
    # Get the name and ID of each site
    foreach ($XMLSitesList in $XMLSites.result.items.site) {
        $Site_Name = $XMLSitesList.name."#cdata-section"
        $Site_ID = $XMLSitesList.siteid
        # Create an object to store the results
        $SiteInfo = [pscustomobject]@{}
        $SiteInfo | Add-Member -MemberType NoteProperty -Name "Client_Name" -Value $Client_Name
        $SiteInfo | Add-Member -MemberType NoteProperty -Name "Client_ID" -Value $Client_ID
        $SiteInfo | Add-Member -MemberType NoteProperty -Name "Site_Name" -Value $Site_Name
        $SiteInfo | Add-Member -MemberType NoteProperty -Name "Site_ID" -Value $Site_ID
        # Add the results to the site list
        $SiteList += $SiteInfo
    }
}

# Output to the screen and CSV file
$SiteList | Sort-Object -Property "Client_Name" | Out-GridView -Title "RMM Client List"
$SiteList | Sort-Object -Property "Client_Name" | Export-Csv -Path $myCSV -NoTypeInformation -Force