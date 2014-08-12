<#
    PowerShell wrapper for EMC ViPR controller
    (c) Parul Jain paruljain@hotmail.com
    Verison 0.3
    MIT License
#>

# Ignore self signed certificate installed on ViPR server
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

$ErrorActionPreference = 'stop'

$viprApi = New-Object System.Net.WebClient

function Vipr-PostJson {
    param(
        [Parameter(Mandatory=$true)][string]$location,
        [Parameter(Mandatory=$true)][string]$jsonString
    )

    if (!$script:viprToken) { throw 'Must login to Vipr first' }
    $viprApi.Headers.Clear()
    $viprApi.QueryString.Clear()
    $viprApi.Headers.Add('X-SDS-AUTH-TOKEN', $script:viprToken)
    $viprApi.Headers.Add('Content-Type', 'application/json')
    try { $result = [xml]$viprApi.UploadString($location, $jsonString) }
    catch [System.Net.WebException] {
        $errorMsg = [xml](New-Object System.IO.StreamReader $_.Exception.Response.GetResponseStream()).ReadToEnd()
        throw $errorMsg.error.details
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
    if ($queryParams.Keys.Count -gt 0) {
        $queryParams.GetEnumerator() | % {
            $viprApi.QueryString.Add($_.Name, $_.Value)
        }
    }

    try { $result = [xml]$viprApi.DownloadString($location) }
    catch [System.Net.WebException] {
        $errorMsg = [xml](New-Object System.IO.StreamReader $_.Exception.Response.GetResponseStream()).ReadToEnd()
        throw $errorMsg.error.details
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
    (Vipr-Get ('/tenants/' + $script:tenantId + '/hosts')).hosts.host | % {
        @{name = $_.name; id = $_.id}
    }
}

function Vipr-GetTenant {
    $response = Vipr-Get '/tenant'
    @{
        name = $response.tenant_info.name
        id = $response.tenant_info.id
    }
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
    $response = Vipr-PostJson ('/tenants/' + $script:tenantId + '/hosts') ($hostSpec | ConvertTo-Json)
    @{
        name = $response.task.resource.name
        id = $response.task.resource.id
    }
}

function Vipr-AddInitiator {
    param (
        [Parameter(Mandatory=$true)][string]$hostId,
        [Parameter(Mandatory=$true)][string]$portWwn,
        [Parameter(Mandatory=$false)][string]$nodeWwn = $portWwn)
    
    $found = Vipr-SearchInitiator -portWwn $portWwn
    if ($found) { throw 'Initiator ' + $portWwn + ' is already attached to host ' + $found.hostname }

    $initiatorSpec = @{
        protocol = 'FC';
        initiator_port = $portWwn
        initiator_node = $nodeWwn
    }
    Vipr-PostJson "/compute/hosts/$hostId/initiators" ($initiatorSpec | ConvertTo-Json)
}

function Vipr-SearchHost ([Parameter(Mandatory=$true)][string]$hostName) {
    (Vipr-Get '/compute/hosts/search' @{name = $hostName}).results.resource.id
}

function Vipr-SearchInitiator ([Parameter(Mandatory=$true)][string]$portWwn) {
    $initiatorId = (Vipr-Get 'compute/initiators/search' @{initiator_port = $portWwn}).results.resource.id
    if (!$initiatorId) { return }
    $result = Vipr-Get "compute/initiators/$initiatorId"
    @{
        hostname = $result.initiator.hostname
        hostId = $result.initiator.host.id
        initiatorId = $result.initiator.id
        registrationStatus = $result.initiator.registration_status
    }
}

function Vipr-GetHostInitiators ([Parameter(Mandatory=$true)][string]$hostId) {
    (Vipr-Get "/compute/hosts/$hostId/initiators").initiators.initiator | % {
        @{ portWwn = $_.name; id = $_.id }
    }
}
