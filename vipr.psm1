<#
    PowerShell wrapper for EMC ViPR controller
    (c) Parul Jain paruljain@hotmail.com
    MIT License
#>

# Ignore self signed certificate installed on ViPR server
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

$ErrorActionPreference = 'stop'

$viprApi = New-Object System.Net.WebClient

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
    $viprApi.Headers.Add('Authorization', 'Basic ' + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($user + ':' + $password)))
    [void]$viprApi.DownloadString('login')
    $script:viprToken = $viprApi.ResponseHeaders['X-SDS-AUTH-TOKEN']
    $script:tenantId = (Vipr-GetTenant).id
}

function Vipr-GetHosts {
    $tenantId = (Vipr-GetTenant).id
    $viprApi.Headers.Clear()
    $viprApi.Headers.Add('X-SDS-AUTH-TOKEN', $script:viprToken)

    $response = [xml]$viprApi.DownloadString("tenants/$tenantId/hosts")

    foreach ($h in $response.hosts.host) {
        @{
            name = $h.name;
            id = $h.id
        }
    }
}

function Vipr-GetTenant {
    if (!$script:viprToken) { throw 'Must login to Vipr first' }
    $viprApi.Headers.Clear()
    $viprApi.Headers.Add('X-SDS-AUTH-TOKEN', $script:viprToken)
    $response = [xml]$viprApi.DownloadString('tenant')
    @{
        name = $response.tenant_info.name;
        id = $response.tenant_info.id
    }
}

function Vipr-AddHost ([string]$hostname, [string]$type = 'Other') {
    if (!$script:viprToken) { throw 'Must login to Vipr first' }
    $tenantId = $script:tenantId
    $hostSpec = @{
        type = $type;
        host_name = $hostname;
        name = $hostname;
        discoverable = $false
    }
    $viprApi.Headers.Clear()
    $viprApi.Headers.Add('X-SDS-AUTH-TOKEN', $script:viprToken)
    $viprApi.Headers.Add('Content-Type', 'application/json')
    $response = [xml]$viprApi.UploadString("tenants/$tenantId/hosts", ($hostSpec | ConvertTo-Json))
    @{
        name = $response.task.resource.name;
        id = $response.task.resource.id;
    }
}

function Vipr-AddInitiator ([string]$hostId, [string]$portWwn, [string]$nodeWwn) {
    if (!$script:viprToken) { throw 'Must login to Vipr first' }
    if (!$nodeWwn) { $nodeWwn = $portWwn }
    $initiatorSpec = @{
        protocol = 'FC';
        initiator_port = $portWwn;
        initiator_node = $nodeWwn
    }
    $viprApi.Headers.Clear()
    $viprApi.Headers.Add('X-SDS-AUTH-TOKEN', $script:viprToken)
    $viprApi.Headers.Add('Content-Type', 'application/json')
    [void]$viprApi.UploadString("/compute/hosts/$hostId/initiators", ($initiatorSpec | ConvertTo-Json))
}

