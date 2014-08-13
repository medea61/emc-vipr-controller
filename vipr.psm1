<#
    PowerShell wrapper for EMC ViPR controller
    (c) Parul Jain paruljain@hotmail.com
    Verison 0.4
    MIT License
#>

# Ignore self signed certificate installed on ViPR server
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

$ErrorActionPreference = 'stop'

$viprApi = New-Object System.Net.WebClient

function Vipr-PostJson {
    param(
        [Parameter(Mandatory=$true)][string]$location,
        [Parameter(Mandatory=$true)][hashtable]$payload
    )

    if (!$script:viprToken) { throw 'Must login to Vipr first' }
    if ($payload.Keys.Count -eq 0) { throw 'No payload' }

    $viprApi.Headers.Clear()
    $viprApi.QueryString.Clear()
    $viprApi.Headers.Add('X-SDS-AUTH-TOKEN', $script:viprToken)
    $viprApi.Headers.Add('Content-Type', 'application/json')
    $viprApi.Headers.Add('Accept', 'application/json')
    try { $result = $viprApi.UploadString($location, ($payload | ConvertTo-Json)) | ConvertFrom-Json }
    catch [System.Net.WebException] {
        $errorMsg = (New-Object System.IO.StreamReader $_.Exception.Response.GetResponseStream()).ReadToEnd() | ConvertFrom-Json
        throw $errorMsg.details
    }
    $result
}

function Vipr-Get {
    param(
        [Parameter(Mandatory=$true)][string]$location,
        [Parameter(Mandatory=$false)][hashtable]$queryParams
    )

    if (!$script:viprToken) { throw 'Must login to Vipr first' }
    $viprApi.Headers.Clear()
    $viprApi.QueryString.Clear()
    $viprApi.Headers.Add('X-SDS-AUTH-TOKEN', $script:viprToken)
    $viprApi.Headers.Add('Accept', 'application/json')
    if ($queryParams.Keys.Count -gt 0) {
        $queryParams.GetEnumerator() | % {
            $viprApi.QueryString.Add($_.Name, $_.Value)
        }
    }

    try { $result = $viprApi.DownloadString($location) | ConvertFrom-Json }
    catch [System.Net.WebException] {
        $errorMsg = (New-Object System.IO.StreamReader $_.Exception.Response.GetResponseStream()).ReadToEnd() | ConvertFrom-Json
        throw $errorMsg.details
    }
    $result
}


function Vipr-Login {
    # Logs in user to Vipr and sets up WebClient for future calls to Vipr API
    # This token should then be used with all future calls to the API
    param(
        [Parameter(Mandatory=$true)][string]$viprApiUri,
        [Parameter(Mandatory=$true)][string]$user,
        [Parameter(Mandatory=$true)][string]$password
    )
    $viprApi.BaseAddress = $viprApiUri
    $viprApi.Headers.Clear()
    $viprApi.QueryString.Clear()

    $viprApi.Headers.Add('Authorization', 'Basic ' + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($user + ':' + $password)))
    
    [void]$viprApi.DownloadString('login')

    $script:viprToken = $viprApi.ResponseHeaders['X-SDS-AUTH-TOKEN']
    $script:tenantId = (Vipr-GetTenant).id
}

function Vipr-GetHosts {
    (Vipr-Get ('/tenants/' + $script:tenantId + '/hosts')).host
}

function Vipr-GetTenant {
    Vipr-Get '/tenant'
}

function Vipr-AddHost {
    param(
        [Parameter(Mandatory=$true)][string]$hostname,
        [Parameter(Mandatory=$true)][ValidateSet('Other', 'Windows', 'Linux', 'HPUX', 'Esx')][string]$type

    )
    $hostSpec = @{
        type = $type
        host_name = $hostname
        name = $hostname
        discoverable = $false
    }
    (Vipr-PostJson ('/tenants/' + $script:tenantId + '/hosts') $hostSpec).resource
}

function Vipr-AddInitiator {
    param (
        [Parameter(Mandatory=$true)][string]$hostId,
        [Parameter(Mandatory=$true)][string]$portWwn,
        [Parameter(Mandatory=$false)][string]$nodeWwn = $portWwn)
    
    $found = Vipr-SearchInitiator -portWwn $portWwn
    if ($found) { throw 'Initiator ' + $portWwn + ' is already attached to host ' + $found.hostname }

    $initiatorSpec = @{
        protocol = 'FC'
        initiator_port = $portWwn
        initiator_node = $nodeWwn
    }
    Vipr-PostJson "/compute/hosts/$hostId/initiators" $initiatorSpec
}

function Vipr-SearchHost ([Parameter(Mandatory=$true)][string]$hostName) {
    (Vipr-Get '/compute/hosts/search' @{name = $hostName}).resource
}

function Vipr-SearchInitiator ([Parameter(Mandatory=$true)][string]$portWwn) {
    $initiatorId = (Vipr-Get 'compute/initiators/search' @{initiator_port = $portWwn}).resource.id
    if (!$initiatorId) { return }
    Vipr-Get "/compute/initiators/$initiatorId"
}

function Vipr-GetHostInitiators ([Parameter(Mandatory=$true)][string]$hostId) {
    (Vipr-Get "/compute/hosts/$hostId/initiators").initiator
}

function Vipr-AddCluster {
    param(
        [Parameter(Mandatory=$true)][string]$clusterName
    )
    Vipr-PostJson ('/tenants/' + $script:tenantId + '/clusters') @{name=$clusterName}
}

function Vipr-AddClusterHost {
    param(
        [Parameter(Mandatory=$true)][string]$hostname,
        [Parameter(Mandatory=$true)][ValidateSet('Other', 'Windows', 'Linux', 'HPUX', 'Esx')][string]$type,
        [Parameter(Mandatory=$true)][string]$clusterId
    )
    $hostSpec = @{
        type = $type
        host_name = $hostname
        name = $hostname
        discoverable = $false
        cluster = $clusterId
    }
    (Vipr-PostJson ('/tenants/' + $script:tenantId + '/hosts') $hostSpec).resource
}

function Vipr-GetClusters {
    (Vipr-Get ('/tenants/' + $script:tenantId + '/clusters')).cluster
}

function Vipr-GetClusterHosts {
    param(
        [Parameter(Mandatory=$true)][string]$clusterId
    )

    (Vipr-Get "/compute/clusters/$clusterId/hosts").host
}

function Vipr-GetHostDetails {
   param(
        [Parameter(Mandatory=$true)][string]$hostId
    )

    Vipr-Get "/compute/hosts/$hostId"
}
