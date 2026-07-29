[CmdletBinding()]
param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
if (-not $Root) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$flutter = Join-Path $Root 'client-rustdesk-src\flutter'
$sources = @{
    contract = Get-Content -LiteralPath (Join-Path $flutter 'lib\tgdesk\support_contract.dart') -Raw
    page = Get-Content -LiteralPath (Join-Path $flutter 'lib\tgdesk\support_page.dart') -Raw
    client = Get-Content -LiteralPath (Join-Path $flutter 'lib\tgdesk\client_home_page.dart') -Raw
    hub = Get-Content -LiteralPath (Join-Path $flutter 'lib\tgdesk\hub_home_page.dart') -Raw
    control = Get-Content -LiteralPath (Join-Path $flutter 'lib\tgdesk\control_channel.dart') -Raw
    api = Get-Content -LiteralPath (Join-Path $flutter 'lib\tgdesk\api_client.dart') -Raw
}

$checks = [ordered]@{
    'ticket.client-open' = @('client', 'Abrir chamado')
    'ticket.live-state' = @('control', "event['type'] == 'support_ticket'")
    'ticket.supervisor-queue' = @('page', 'canManageQueue')
    'ticket.os-conversion' = @('api', 'convertTicketToServiceOrder')
    'ticket.audit' = @('page', 'Chamados e ordens de serviço')
    'ticket.close-reopen' = @('contract', 'canTransition')
    'ticket.notifications' = @('control', "event['type'] == 'support_offer'")
    'freelancer.new-role' = @('contract', 'TgdeskSupportRole.freelancer')
    'freelancer.supervisor-link' = @('page', 'Atendimentos disponíveis')
    'freelancer.request-data' = @('page', 'Dados técnicos e localização')
    'freelancer.dynamic-queue' = @('control', 'offers =')
    'freelancer.staggered-offer' = @('control', 'support_offer')
    'freelancer.atomic-accept' = @('api', 'acceptSupportOffer')
    'freelancer.client-tab' = @('hub', 'TgdeskClientHomePage')
    'freelancer.admin-superset' = @('contract', 'role == TgdeskSupportRole.admin')
    'onsite.geolocation-consent' = @('page', 'somente após consentimento')
    'onsite.photos' = @('page', 'Chegada, execução e conclusão')
    'onsite.signature' = @('page', 'Assinatura digital')
    'onsite.print' = @('page', 'Imprimir')
    'onsite.export' = @('page', 'exportar')
    'onsite.offline-sync' = @('contract', 'local_id')
    'standalone.request-entry' = @('client', 'Solicitar atendimento avulso')
    'standalone.public-scope' = @('api', '/api/v1/public/support/standalone')
    'standalone.virtual-onsite' = @('client', "value: 'onsite'")
    'standalone.remote-ticket-bound' = @('contract', 'canUseTemporaryRemote')
    'standalone.analysis-permission' = @('contract', 'canUseTicketDiagnostics')
    'standalone.permission-revoke' = @('contract', 'permissionsMustBeRevoked')
    'standalone.privacy' = @('client', 'não permite visualizar outros clientes')
}

$results = foreach ($entry in $checks.GetEnumerator()) {
    $sourceName = $entry.Value[0]
    $needle = $entry.Value[1]
    $passed = $sources[$sourceName].Contains($needle)
    [pscustomobject]@{
        id = $entry.Key
        component_state = if ($passed) { 'passed' } else { 'failed' }
        acceptance_state = 'pending_end_to_end'
        source = $sourceName
        contract = $needle
    }
}

$state = if (@($results | Where-Object component_state -eq 'failed').Count) {
    'failed'
} else {
    'passed'
}
$artifact = [ordered]@{
    schema_version = 1
    phase = 'v1.1.0-client-surfaces'
    state = $state
    measured_at = (Get-Date).ToUniversalTime().ToString('o')
    note = 'Client-side evidence only. Acceptance remains pending until backend and Windows lab prove the complete criterion.'
    client_assertions = @($results)
}
$artifactPath = Join-Path $Root 'testlab\artifacts\v1.1.0-client-surfaces.json'
$artifact | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $artifactPath -Encoding utf8
$artifact | ConvertTo-Json -Depth 6
if ($state -ne 'passed') { exit 1 }
