# https://github.com/12Knocksinna/Office365itpros/blob/master/FindTabsAndAppsInTeams.ps1
# The correct tenant values for the app id etc. are in this script.
Cls
# Define the values applicable for the application used to connect to the Graph
$AppId = "d716b32c-0edb-48be-9385-30a9cfd96153"    # Change this
$TenantId = "b662313f-14fc-43a2-9a7a-d2e27f4f3476" # And this
$AppSecret = 's_rkvIn1oZ1cNceUBvJ2or1lrrIsb*:='    # and this

# Construct URI and body needed for authentication
$uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$body = @{
    client_id     = $AppId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $AppSecret
    grant_type    = "client_credentials"
}

# Get OAuth 2.0 Token
$tokenRequest = Invoke-WebRequest -Method Post -Uri $uri -ContentType "application/x-www-form-urlencoded" -Body $body -UseBasicParsing

# Unpack Access Token
$token = ($tokenRequest.Content | ConvertFrom-Json).access_token

# Base URL
$uri = "https://graph.microsoft.com/beta/"
$headers = @{Authorization = "Bearer $token"}
$ctype = "application/json"

# Create list of Teams in the tenant
Write-Host "Fetching list of Teams in the tenant"
# This call only returns 100 teams
# $Teams = Invoke-WebRequest -Method GET -Uri "$($uri)groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')" -ContentType $ctype -Headers $headers | ConvertFrom-Json
# This is how to paginate through and build a hashtable containing all the teams in a tenant using the NextLink
$Teams = Invoke-WebRequest -Method GET -Uri "$($uri)groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')" -ContentType $ctype -Headers $headers | ConvertFrom-Json
$TeamsHash = @{}
$Teams.Value.ForEach( {
   $TeamsHash.Add($_.Id, $_.DisplayName) } )
$NextLink = $Teams.'@Odata.NextLink'
While ($NextLink -ne $Null) {
   $Teams = Invoke-WebRequest -Method GET -Uri $NextLink -ContentType $ctype -Headers $headers | ConvertFrom-Json
   $Teams.Value.ForEach( {
      $TeamsHash.Add($_.Id, $_.DisplayName) } )
   $NextLink = $Teams.'@odata.NextLink' }

# All teams found...
Write-Host "Processing" $TeamsHash.Count "Teams..."

$Report = [System.Collections.Generic.List[Object]]::new() # Create output file for report; $ReportLine = $Null
$i = 0
# Loop through each team to examine its channels and discover if any are email-enabled
ForEach ($Team in $TeamsHash.Keys) {
      $i++
      $TeamId = $($Team); $TeamDisplayName = $TeamsHash[$Team]  #Populate variables to identify the team
      $ProgressBar = "Processing Team " + $TeamDisplayName + " (" + $i + " of " + $TeamsHash.Count + ")"
      Write-Progress -Activity "Checking Teams Information" -Status $ProgressBar -PercentComplete ($i/$TeamsHash.Count*100)
      # Get apps installed in the team
      $TeamApps = Invoke-WebRequest -Headers $Headers -Uri "https://graph.microsoft.com/v1.0/teams/$($TeamId)/installedApps?`$expand=teamsApp" -ErrorAction Stop
      $TeamApps = ($TeamApps.content | ConvertFrom-Json).Value
      $TeamAppNumber = 0
      ForEach ($App in $TeamApps) {
         $TeamAppNumber++
         $ReportLine = [PSCustomObject][Ordered]@{
            Record  = "App"
            Number  = $TeamAppNumber
            Team    = $TeamDisplayName
            TeamId  = $TeamId
            Channel = "N/A"
            App     = $App.TeamsApp.DisplayName
            AppId   = $App.TeamsApp.Id
            Distribution = $App.TeamsApp.DistributionMethod 
            WebURL  = "N/A" }
        $Report.Add($ReportLine) }
            
# Get the channels so we can report the tabs created in each channel
 $TeamChannels = Invoke-WebRequest -Headers $Headers -Uri "https://graph.microsoft.com/beta/Teams/$($TeamId)/channels" -ErrorAction Stop
 $TeamChannels = ($TeamChannels.Content | ConvertFrom-Json).value
# Find the tabs created for each channel (standard tabs like Files don't show up here)    
     ForEach ($Channel in $TeamChannels) {
        $Tabs = Invoke-WebRequest -Headers $Headers -Uri "https://graph.microsoft.com/beta/teams/$($TeamId)/channels/$($channel.id)/tabs?`$expand=teamsApp" 
        $Tabs = ($Tabs.Content | ConvertFrom-Json).value
        $TabNumber = 0
        ForEach ($Tab in $Tabs) {
            $TabNumber++
            $ReportLine = [PSCustomObject][Ordered]@{
              Record  = "Channel tab"
              Number  = $TabNumber
              Team    = $TeamDisplayName
              TeamId  = $TeamId
              Channel = $Channel.DisplayName
              Tab     = $Tab.DisplayName
              AppId   = $Tab.TeamsApp.Id
              Distribution = $Tab.TeamsApp.DistributionMethod 
              WebURL  = $Tab.WebURL}
        $Report.Add($ReportLine) }}
}

$Report | Sort Team | Export-CSV C:\Temp\TeamsChannelsAndAppsCsv -NoTypeInformation
Write-Host $TeamsHash.Count "teams processed. Details are in C:\Temp\TeamsChannelsAndApps.Csv"
