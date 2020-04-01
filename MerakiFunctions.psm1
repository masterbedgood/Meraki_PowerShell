#https://github.com/snagler/meraki_functions/blob/master/meraki_api_functions.ps1

#https://blog.darrenjrobinson.com/powershell-the-underlying-connection-was-closed-an-unexpected-error-occurred-on-a-send/
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

####################################################
### Declare constants for use in child functions ###
####################################################

#Org API key
$API_Key = ''

###  CHECKS API_KEY ###
#If no value exists in the API_Key var
if(!$API_Key)
{
    #Prompts for API_Key value
    $API_Key = Read-Host -Prompt "Enter API Key"

    #Gets directory of this module & assigns to ModulePath var for overwrite
    $ModulePath = (Get-Item "$PSScriptRoot\*.psm1").FullName
    #Gets content of module & assigns to ModuleText var for updating w/API_Key value
    $ModuleText = Get-Content "$PSScriptRoot\*.psm1"

    #Replaces line under Org API key comment with the API_Key value assignment
    $ModuleText = $ModuleText -Replace "^[$]API_Key = ''",('$API_Key = ' + "'$API_Key'")
    
    #Updates current module w/API_Key assignment to prevent prompts on next run
    $ModuleText | Out-File $ModulePath -Force | Out-Host
}

#Default value for $api.endpoint
$API = @{
    "endpoint" = 'https://dashboard.meraki.com/api/v0'
}
<#
    Default value for for API_Put.Endpoint - used for SSID PSK Change, etc
    Requires nXXX subdomain - getable w/Get-MerakiNxxx
#>
$API_Put = @{
"endpoint" = 'REPLACEMENT_TEXT'
    #"endpoint" = 'https://nXXX.meraki.com/api/v0'
}
#Default header
$Header = @{
    "X-Cisco-Meraki-API-Key" = $API_Key
    "Content-Type" = 'application/json'
}


###########################################################################
### Gather Functions - Required for other function default param values ###
###########################################################################

function Get-MerakiOrganizations
{   
    #Organizations URL
    $API.URL = '/organizations/'
    #Appdends URL value to Endpoint & assigns to $URI variable
    $URI = $API.endpoint + $API.URL
    
    Invoke-RestMethod -Method GET -Uri $URI -Headers $Header
}

function Get-MerakiNxxx
{
    $Nxxx = (Get-MerakiOrganizations).url -split '.meraki.com' -replace 'https://' | 
        Select-Object -First 1

    New-Object PSObject -Property @{
        API_Put = "https://$Nxxx.meraki.com/api/v0"
        Nxxx = $Nxxx
    }
}

######################
### CHECKS API_PUT ###
######################

#If no value for $API_Put.Endpoint
if("$($API_Put.endpoint)" -eq 'REPLACEMENT_TEXT')
{
    $API_Put.endpoint = "$((Get-MerakiNxxx).API_Put)"
    
    $API_Put.endpoint | Out-Host


    #Gets directory of this module & assigns to ModulePath var for overwrite
    $ModulePath = (Get-Item "$PSScriptRoot\*.psm1").FullName
    #Gets content of module & assigns to ModuleText var for updating w/API_Key value
    $ModuleText = Get-Content "$PSScriptRoot\*.psm1"

    #Replaces API_Put.endpoint value in module text
    $ModuleText = $ModuleText -Replace '^"endpoint" = .REPLACEMENT_TEXT.',"`t'endpoint' = '$($API_Put.endpoint)'"

    #Updates current module w/API_Put assignment to prevent prompts on next run
    $ModuleText | Out-File $ModulePath -Force | Out-Host
}


##################################
### START ADDITIONAL FUNCTIONS ###
##################################

function Get-MerakiNetworks
{
    param(
        [string[]]$OrganizationID = (Get-MerakiOrganizations).ID
    )

    #Initializes ReturnObject to enable appending information in ForEach loop
    $ReturnObj = @()

    Foreach($ID in $OrganizationID)
    {
        $API.URL = "/organizations/$ID/networks"
        $URI = $API.endpoint + $API.URL

        $ReturnObj += Invoke-RestMethod -Method GET -Uri $URI -Headers $header
    }

    #Returns updated ReturnObj
    $ReturnObj
}

function Get-MerakiSSIDs
{
    param(
        [string[]]$NetworkID = (Get-MerakiNetworks).ID
    )

    $ReturnObj = @()

    Foreach($ID in $NetworkID)
    {        
        $API.URL = "/networks/$ID/ssids"
        $URI = $API.endpoint + $API.URL

        $ReturnObj += Invoke-RestMethod -Method GET -Uri $URI -Headers $header
    }

    #Returns only SSIDs where the name does not match Unconfigured
    $ReturnObj  | Where-Object {$_.Name -notmatch "^Unconfigured"}
}

function Get-MerakiDevices
{
    param(
        [string[]]$NetworkID = (Get-MerakiNetworks).ID
    )

    $ReturnObj = @()

    Foreach($ID in $NetworkID)
    {        
        $API.URL = "/networks/$ID/devices"
        $URI = $API.endpoint + $API.URL

        $ReturnObj += Invoke-RestMethod -Method GET -Uri $URI -Headers $header
    }

    $ReturnObj
}

function Get-MerakiVPN 
{
    param(
        [string[]]$OrganizationID = (Get-MerakiOrganizations).ID
    )

    $ReturnObj = @()

    Foreach($ID in $OrganizationID)
    {
        $API.URL = "/organizations/$ID/thirdPartyVPNPeers"
        $URI = $API.endpoint + $API.URL

        $ReturnObj += Invoke-RestMethod -Method GET -Uri $URI -Headers $header
    }

    $ReturnObj
}

function Set-MerakiSSIDPassword
{
    param(
        [parameter(Mandatory=$true, Position=0)]
        [string]$SSID,
        [string]$NewSSIDPW,
        [string[]]$NetworkID = (Get-MerakiNetworks).ID
    )

    #If no value provided for NewSSIDPW
    if(!$NewSSIDPW)
    {
        #Specifies target CSV for approved words list
        $WordList = Import-Csv "$PSScriptRoot\Data\WordList.csv"
        
        #Runs contents of script block & assigns returned result to NewSSIDPW var
        $NewSSIDPW = &{
            #Assigns first word to a random value of word list
            $Word1 = Get-Random $WordList.Word
            
            #Assigns second word to random value of word list - loops until not equal first word
            do{
                $Word2 = Get-Random $WordList.Word
            }until($Word2 -ne $Word1)
        
            #Creates a random 3-digit number
            [int]$NumLength = 3
            Add-Type -AssemblyName System.Web
            $NumSet = '0123456789'.ToCharArray()
            $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
            $bytes = New-Object byte[]($NumLength)
            $rng.GetBytes($bytes)
            $EndNumber = New-Object char[]($NumLength)
            For ($i = 0 ; $i -lt $NumLength ; $i++)
            {
                    $EndNumber[$i] = $NumSet[$bytes[$i]%$NumSet.Length]
            }
         
            #Combines Word1, Word2, and EndNumber for GuestPW value
            "$Word1$Word2$(-join $EndNumber)"
        }
    }

    #Creates Data hashtable & adds 'psk' key with "NewSSIDPW" value
    $Data = @{
        "psk" = "$NewSSIDPW"
    }
    #Converts Data hashtable to Json format to be passed in the Invoke-RestMethod command
    $JBody = ConvertTo-Json -InputObject $Data

    foreach($Network in $NetworkID)
    {
        [int]$SSIDNumber = (Get-MerakiSSIDs -NetworkID $Network | Where-Object {$_.Name -eq $SSID}).Number

        if($SSIDNumber)
        {
            Write-Host "`nUpdating password for SSID '$SSID' on network $Network to '$NewSSIDPW'...`n"
            
            #URL path for target SSID on Network of current loop
            $API.SSID = "/networks/$Network/ssids/$SSIDNumber"

            #Sets Appends the API.SSID path to the API_Put.Endpoint URL & assigns to MerakiURI var
            $MerakiURI = $API_Put.endpoint + $API.SSID

            <#
                Pushes change to target SSID on Network of current loop
                Verbose & out-host displays changes w/o creating a new return object
            #>
            Invoke-RestMethod -Method Put -Uri $MerakiURI -Headers $Header -Body $JBody -Verbose | Out-Host

        }

        else
        {
            Write-Warning "SSID '$SSID' not found on network '$Network.'"
            Write-Host "`t Skipping PW set for '$SSID' on '$Network'.`n" -ForegroundColor Yellow
        }
    }

    #Returns the updated password - this can be passed to additional commands
    $NewSSIDPW
}
