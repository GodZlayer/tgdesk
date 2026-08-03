$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$compose = Join-Path $root 'server\docker-compose.yml'

function Query([string]$Sql) {
    (& docker compose -f $compose exec -T postgres psql -U tgdesk -d tgdesk -Atqc $Sql |
        Out-String).Trim()
}

$networks = Query @"
SELECT string_agg(system_key||':'||peer_isolation::text,',' ORDER BY system_key)
FROM networks n JOIN organizations o ON o.id=n.organization_id
WHERE lower(o.name)='tgdevs';
"@
$expected = 'tgdevs.clientes:true,tgdevs.clientes_avulsos:true,tgdevs.principal:false,tgdevs.supervisores:true,tgdevs.tecnicos:true'
if ($networks -ne $expected) { throw "Redes TGDevs invalidas: $networks" }

$missing = Query @"
SELECT count(*) FROM devices d WHERE NOT EXISTS (
 SELECT 1 FROM device_networks dn JOIN networks n ON n.id=dn.network_id
 WHERE dn.device_id=d.id AND n.system_key IS NOT NULL);
"@
if ($missing -ne '0') { throw "$missing dispositivo(s) sem TGDevs" }

$dani = Query @"
SELECT string_agg(o.name||'/'||n.name,',' ORDER BY o.name,n.name)
FROM devices d JOIN device_networks dn ON dn.device_id=d.id
JOIN networks n ON n.id=dn.network_id JOIN organizations o ON o.id=n.organization_id
WHERE lower(d.hostname)='dani';
"@
if ($dani -ne 'Dani/Principal,TGDevs/Supervisores') {
    throw "Vinculos de Dani invalidos: $dani"
}

$diagnostics = Get-Content (Join-Path $root 'client-rustdesk-src\flutter\lib\tgdesk\diagnostics_dialog.dart') -Raw
if ($diagnostics -notmatch '_scheduleAutomaticRetry' -or
    $diagnostics -notmatch 'for \(var attempt = 0; attempt < 3; attempt\+\+\)') {
    throw 'Diagnostico nao possui recuperacao automatica deterministica.'
}

[pscustomobject]@{
    status = 'PASS'
    networks = 5
    isolated_networks = 4
    devices_without_tgdevs = 0
    dani = $dani
    diagnostics_auto_retry = $true
} | ConvertTo-Json
