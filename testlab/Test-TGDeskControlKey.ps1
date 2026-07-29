[CmdletBinding()]
param(
    [string]$MachineID = 'testlab-admin-vm'
)

$ErrorActionPreference = 'Stop'
$keyPath = Join-Path $PSScriptRoot 'artifacts\keys\admin.tgdesk-key'
$evidencePath = Join-Path $PSScriptRoot 'artifacts\control-key.json'

try {
    $keyResult = & (Join-Path $PSScriptRoot 'New-TGDeskLabAdminKey.ps1') -OutputPath $keyPath |
        ConvertFrom-Json
    if ($keyResult.state -ne 'passed') {
        throw 'A chave de teste não foi criada.'
    }

    $key = Get-Content $keyPath -Raw | ConvertFrom-Json
    $body = @{key = $key; machine_id = $MachineID} | ConvertTo-Json -Depth 5
    $first = Invoke-RestMethod -Method Post `
        -Uri 'http://127.0.0.1:18090/api/v1/auth/control-key/install' `
        -ContentType 'application/json' -Body $body

    $secondStatus = 0
    $secondError = ''
    try {
        Invoke-RestMethod -Method Post `
            -Uri 'http://127.0.0.1:18090/api/v1/auth/control-key/install' `
            -ContentType 'application/json' -Body $body | Out-Null
    } catch {
        $secondStatus = [int]$_.Exception.Response.StatusCode
        $secondError = $_.ErrorDetails.Message
    }

    if ($first.role -ne 'super_admin' -or
        -not $first.token -or
        -not $first.credential_id -or
        $secondStatus -ne 409 -or
        $secondError -notmatch 'utilizada') {
        throw 'O contrato de consumo único da chave não foi satisfeito.'
    }

    $evidence = [ordered]@{
        schema_version = 1
        scenario = 'control-key-single-use'
        state = 'passed'
        measured_at = (Get-Date).ToUniversalTime().ToString('o')
        role = $first.role
        machine_id = $first.machine_id
        credential_issued = [bool]$first.credential_id
        reuse_http_status = $secondStatus
        reuse_rejected_as_consumed = $true
        assertions = @(
            [ordered]@{
                id = 'key.single-use.atomic'
                state = 'passed'
                details = [ordered]@{
                    first_role = $first.role
                    reuse_http_status = $secondStatus
                }
            }
        )
    }
    $evidence | ConvertTo-Json -Depth 6 | Set-Content $evidencePath -Encoding UTF8
    $evidence | ConvertTo-Json -Depth 6
} catch {
    $evidence = [ordered]@{
        schema_version = 1
        scenario = 'control-key-single-use'
        state = 'failed'
        measured_at = (Get-Date).ToUniversalTime().ToString('o')
        error = $_.Exception.Message
    }
    $evidence | ConvertTo-Json -Depth 6 | Set-Content $evidencePath -Encoding UTF8
    $evidence | ConvertTo-Json -Depth 6
    exit 1
}
