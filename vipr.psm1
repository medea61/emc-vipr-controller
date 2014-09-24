<#
    PowerShell wrapper for EMC ViPR controller
    (c) Parul Jain paruljain@hotmail.com
    Verison 0.6
    MIT License
#>

# Ignore self signed certificate installed on ViPR server
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

$ErrorActionPreference = 'stop'

$viprApi = New-Object System.Net.WebClient

function hex ([string]$delimiter = '') {
    # Helper function to convert bytes into hex strings for display purposes
    # Often used to display WWN
    Begin { $hex = ''}
    Process { $hex += $_.toString('X2') + $delimiter }
    End { $hex.trimEnd($delimiter) }
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

function Vipr-Call {
    param(
        [Parameter(Mandatory=$true)][string]$location,
        [Parameter(Mandatory=$false)][hashtable]$message,
        [Parameter(Mandatory=$false)][hashtable]$params,
        [Parameter(Mandatory=$false)][ValidateSet('GET', 'POST', 'PUT')][string]$method = 'GET'
    )

    if (!$script:viprToken) { throw 'Must login to Vipr first' }

    $viprApi.Headers.Clear()
    $viprApi.QueryString.Clear()
    $viprApi.Headers.Add('X-SDS-AUTH-TOKEN', $script:viprToken)
    $viprApi.Headers.Add('Content-Type', 'application/json')
    $viprApi.Headers.Add('Accept', 'application/json')

    if ($params.Keys.Count -gt 0) {
        $params.GetEnumerator() | % {
            $viprApi.QueryString.Add($_.Name, $_.Value)
        }
    }

    try {
        if ($method -eq 'GET') {
            $result = $viprApi.DownloadString($location) | ConvertFrom-Json
        } elseif (!$message) {
            $result = $viprApi.UploadString($location, $method, '') | ConvertFrom-Json
        } else {
            $result = $viprApi.UploadString($location, $method, (ConvertTo-Json $message -Compress)) | ConvertFrom-Json
        }
    }
    catch [System.Net.WebException] {
        if ($_.Exception.Response.StatusCode -eq 'Unauthorized') { throw 'Login expired. Please login to Vipr again' }
        $errorMsg = (New-Object System.IO.StreamReader $_.Exception.Response.GetResponseStream()).ReadToEnd() | ConvertFrom-Json
        throw $errorMsg.details
    }
    $result
}

function Vipr-GetHosts {
    (Vipr-Call ('/tenants/' + $script:tenantId + '/hosts')).host
}

function Vipr-GetTenant {
    Vipr-Call '/tenant'
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
    (Vipr-Call ('/tenants/' + $script:tenantId + '/hosts') -message $hostSpec -method POST ).resource
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
    Vipr-Call "/compute/hosts/$hostId/initiators" -message $initiatorSpec -method POST
}

function Vipr-SearchHost ([Parameter(Mandatory=$true)][string]$hostName) {
    (Vipr-Call '/compute/hosts/search' -params @{name = $hostName}).resource
}

function Vipr-GetObjectByName {
    param(
        [Parameter(Mandatory=$true)][string]$ObjectName,
        [Parameter(Mandatory=$true)]
        [ValidateSet('cluster', 'host', 'volume', 'initiator', 'ipAddress')][string]$ObjectType
    )
    switch ($ObjectType) {
        'cluster' { $location = '/compute/clusters/search'; $key = 'name' }
        'host' { $location = '/compute/hosts/search'; $key = 'name' }
        'volume' { $location = '/block/volumes/search'; $key = 'name' }
        'initiator' { $location = '/compute/initiators/search'; $key = 'initiator_port' }
        'ipAddress' { $location = '/compute/ip-interfaces/search'; $key = 'ip_address' }
    }
    $result = (Vipr-Call $location -params @{$key=$ObjectName}).resource
    if ($result.Count -eq 0) { return }
    if ($result.Count -eq 1) { return $result.id }
    foreach ($object in $result) {
        if ($ObjectName -eq $object.match) { return $object.id }
    }
}

function Vipr-GetObjectByName1 {
    param(
        [Parameter(Mandatory=$true)][string]$ObjectName,
        [Parameter(Mandatory=$true)]
        [ValidateSet('cluster', 'host', 'volume', 'initiator', 'ipAddress')][string]$ObjectType
    )
    switch ($ObjectType) {
        'cluster' { $location = '/compute/clusters/search'; $key = 'name' }
        'host' { $location = '/compute/hosts/search'; $key = 'name' }
        'volume' { $location = '/block/volumes/search'; $key = 'name' }
        'initiator' { $location = '/compute/initiators/search'; $key = 'initiator_port' }
        'ipAddress' { $location = '/compute/ip-interfaces/search'; $key = 'ip_address' }
    }
    $result = (Vipr-Call $location -params @{$key=$ObjectName}).resource
    if ($result.Count -eq 0) { return }
    if ($result.Count -eq 1) { return (Vipr-Call $result.link.href) }
    foreach ($object in $result) {
        if ($ObjectName -eq $object.match) { return (Vipr-Call $object.link.href) }
    }
}

function Vipr-SearchInitiator ([Parameter(Mandatory=$true)][string]$portWwn) {
    $initiatorId = (Vipr-Call 'compute/initiators/search' -params @{initiator_port = $portWwn}).resource.id
    if (!$initiatorId) { return }
    Vipr-Call "/compute/initiators/$initiatorId"
}

function Vipr-GetInitiators ([Parameter(Mandatory=$true)][string]$hostName) {
    $initiators = @()
    (Vipr-Call '/compute/hosts/search' -params @{name = $hostName}).resource | % {
        $initiator = (Vipr-Call "/compute/hosts/$($_.id)/initiators").initiator
        $initiator | Add-Member -MemberType NoteProperty -Name hostname -Value $_.match
        $initiators += $initiator
    }
    $initiators | select hostname, name | ft -GroupBy hostname
}

function Vipr-AddCluster {
    param(
        [Parameter(Mandatory=$true)][string]$clusterName
    )
    Vipr-Call ('/tenants/' + $script:tenantId + '/clusters') -message @{name=$clusterName} -method POST
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
    (Vipr-Call ('/tenants/' + $script:tenantId + '/hosts') -message $hostSpec -method POST).resource
}

function Vipr-GetClusters {
    (Vipr-Call ('/tenants/' + $script:tenantId + '/clusters')).cluster
}

function Vipr-GetClusterHosts {
    param(
        [Parameter(Mandatory=$true)][string]$clusterId
    )

    (Vipr-Call "/compute/clusters/$clusterId/hosts").host
}

function Vipr-GetHostDetails {
   param(
        [Parameter(Mandatory=$true)][string]$hostId
    )

    Vipr-Call "/compute/hosts/$hostId"
}

function Vipr-AddHostWithInitiators {
    param(
        [Parameter(Mandatory=$true)][string]$hostname,
        [Parameter(Mandatory=$true)][ValidateSet('Other', 'Windows', 'Linux', 'HPUX', 'Esx')][string]$type,
        [Parameter(Mandatory=$true)][string[]]$initiators,
        [Parameter(Mandatory=$false)][string]$clusterName,
        [Parameter(Mandatory=$false)][switch]$createCluster
    )

    if (Vipr-SearchHost $hostname) { throw "Host $hostname already exists" }
    $initiators | % { 
        $found = Vipr-SearchInitiator $_
        if ($found) { throw 'Initiator ' + $_ + ' is already attached to host ' + $found.hostname }
    }
    if ($clusterName) {
        $clusterId = (Vipr-Call '/compute/clusters/search' -params @{name=$clusterName}).resource.id
        if (!$clusterId) {
            if ($createCluster) {
                write-host "Creating cluster $clusterName"
                $clusterId = (Vipr-AddCluster $clusterName).id
            } else { throw "Cluster $clusterName not found" }
        }
    }
    Write-Host "Creating host $hostname"
    if ($clusterId) { $hostId = (Vipr-AddClusterHost $hostname $type $clusterId).id }
    else { $hostId = (Vipr-AddHost $hostname $type).id }
    
    $initiators | % { 
        Write-Host "Adding initiator $_"
        [void](Vipr-AddInitiator $hostId $_)
    }
}

function Vipr-GetProjects {
    (Vipr-Call /tenants/$script:tenantid/projects).Project
}

function Vipr-GetVirtualArrays {
    (Vipr-Call /vdc/varrays).varray
}

function Vipr-GetVirtualPools {
    (Vipr-Call /block/vpools).virtualpool
}

function Vipr-CreateBlockVolume {
    param(
        [Parameter(Mandatory=$true)][string]$VolumeName,
        [Parameter(Mandatory=$false)][string]$ProjectId = 'urn:storageos:Project:33ef6797-23c2-4b77-987c-2ff4aa9909b9:global',
        [Parameter(Mandatory=$false)][string]$vArrayId = 'urn:storageos:VirtualArray:e9c2f81b-8f5c-48c3-82c6-136bcbc3c95a:vdc1',
        [Parameter(Mandatory=$false)][string]$vPoolId = 'urn:storageos:VirtualPool:4abf9546-43e0-48b1-b085-92137a1a41ce:vdc1',
        [Parameter(Mandatory=$true)][string]$SizeGB
    )
    $volSpec = @{
      name = $VolumeName
      project = $ProjectId
      size = $SizeGB
      varray = $vArrayId
      vpool = $vPoolId
    }
    $task = (Vipr-Call -location /block/volumes -method POST -message $volSpec).task
    $taskState = (Vipr-Call ('/block/volumes/' + $task.resource.id + '/tasks/' + $task.op_id)).state
    write-host -NoNewline 'Creating volume ... '
    do {
        $taskState = (Vipr-Call ('/block/volumes/' + $task.resource.id + '/tasks/' + $task.op_id)).state
        Start-Sleep -Seconds 1
    } until ($taskState -ne 'pending')
    if ($taskState -ne 'ready') { throw "Error while creating volume" }
    write-host 'Done'
    $task.resource.id
}

function Vipr-ExportBlockVolume {
    param(
        [Parameter(Mandatory=$true)][string]$VolumeName,
        [Parameter(Mandatory=$false)][string]$HostName = $env:COMPUTERNAME
    )

    $hostId =( Vipr-GetObjectByName1 -ObjectName $HostName -ObjectType host).id
    if (!$hostId) { throw "Host $HostName not found in Vipr. Please add it first" }

    $volume = Vipr-GetObjectByName1 -ObjectName $VolumeName -ObjectType volume
    if (!$volume) { throw "Unable to find volume $VolumeName" }

    $exportSpec = @{
        hosts = @($hostId)
        project = $volume.project.id
        varray = $volume.varray.id
        type = 'Host'
        name = $HostName
        volumes = @(@{id=$volume.id})
    }

    Write-Host 'Exporting volume'
    $null = Vipr-Call /block/exports -method POST -message $exportSpec | Vipr-WaitForTask
}

function Vipr-AddMyHost {
    Write-Host "Adding host $env:COMPUTERNAME to Vipr"
    $myHostId = Vipr-GetObjectByName -ObjectName $env:COMPUTERNAME -ObjectType host
    if ($myHostId) {
        write-host "Host $env:COMPUTERNAME already exists in Vipr"

    }
    else {
        $hostSpec = @{
            type = 'Windows'
            host_name = $env:COMPUTERNAME
            name = $env:COMPUTERNAME
            discoverable = $false
        }
        $myHostId = Vipr-Call "/tenants/$script:tenantId/hosts" -message $hostSpec -method POST | Vipr-WaitForTask
    }
    $wwns = gwmi -Namespace root\wmi -Class MSFC_FibrePortHBAAttributes -ErrorAction Ignore | % { $_.Attributes.Portwwn | Hex : }
    if ($wwns) {
        foreach ($wwn in $wwns) {
            Write-Host "Adding initiator $wwn to Vipr"
            $wwnId = Vipr-GetObjectByName -ObjectName $wwn -ObjectType initiator
            if (!$wwnId) {
                $initiatorSpec = @{
                    protocol = 'FC'
                    initiator_port = $wwn
                    initiator_node = $wwn
                }
                $null = Vipr-Call "/compute/hosts/$myHostId/initiators" -message $initiatorSpec -method POST
            }
            else {
                # wwn aleady exists in Vipr; get its details
                $initiator = Vipr-Call /compute/initiators/$wwnId
                if ($initiator.hostname -ne $env:COMPUTERNAME) {
                    Write-Host "Wwn $wwn is already registered to another host: $($initiator.hostname) and cannot be used"
                }
                elseif ($initiator.'registration_status' -ne 'registered') {
                    Write-Host "Wwn $wwn status is showing UNREGISTERED in Vipr and cannot be used"
                }
                else { Write-Host "Wwn $wwn is already present and registered in Vipr for this host" }
            }
        }
    } else { 'No HBAs found; skipping initiator add to Vipr' }
}

function Vipr-WaitForTask {
    Process {
        do {
            Start-Sleep -Seconds 1
            $state = (Vipr-Call $_.link.href).state
        } until ($state -ne 'pending')
        if ($state -eq 'error') { throw 'Task errored out' }
        $_.resource.id
    }
}
