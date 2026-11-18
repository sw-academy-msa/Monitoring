# 로컬 모니터링 키만 동기화하며 기존 비밀값과 Docker 데이터는 출력하거나 변경하지 않습니다.
param([string]$ServicesRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$secretDir = Join-Path $root 'secrets'
[IO.Directory]::CreateDirectory($secretDir) | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
function New-LocalSecret {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}
$tokenPath = Join-Path $secretDir 'scrape-token'
$token = if (Test-Path -LiteralPath $tokenPath) { [IO.File]::ReadAllText($tokenPath).Trim() } else { New-LocalSecret }
if ($token -notmatch '^[a-f0-9]{64}$') { throw 'Invalid local monitoring token. Existing files preserved.' }
$pending = @()
$projects = @('AccountService','ProductCommandService','ProductQueryService','OrderCommandService','OrderQueryService','PaymentService','AIService','NotificationService','Gateway','PurchaseGateway','Eureka')
foreach ($project in $projects) {
    $path = Join-Path (Join-Path $ServicesRoot $project) '.env'
    $exists = Test-Path -LiteralPath $path
    if (-not $exists -and $project -notin @('Gateway','PurchaseGateway','Eureka')) { throw ('Missing local .env: ' + $project) }
    $original = if ($exists) { [IO.File]::ReadAllText($path) } else { '' }
    $pattern = '(?m)^MONITORING_SCRAPE_TOKEN=[^\r\n]*'
    if ([regex]::Matches($original, $pattern).Count -gt 1) { throw ('Duplicate monitoring token setting: ' + $project) }
    $updated = if ([regex]::IsMatch($original,$pattern)) { [regex]::Replace($original,$pattern,('MONITORING_SCRAPE_TOKEN='+$token)) } else { $original.TrimEnd("`r","`n") + "`r`nMONITORING_SCRAPE_TOKEN=$token`r`n" }
    if ($project -in @('AccountService','ProductCommandService','OrderCommandService','PaymentService','AIService')) {
        $outboxPattern = '(?m)^MONITORING_OUTBOX_ENABLED=[^\r\n]*'
        if ([regex]::Matches($updated,$outboxPattern).Count -gt 1) { throw 'Duplicate Outbox monitoring setting.' }
        $updated = if ([regex]::IsMatch($updated,$outboxPattern)) { [regex]::Replace($updated,$outboxPattern,'MONITORING_OUTBOX_ENABLED=true') } else { $updated.TrimEnd("`r","`n") + "`r`nMONITORING_OUTBOX_ENABLED=true`r`n" }
    }
    $pending += @{Path=$path; Original=$original; Updated=$updated; Exists=$exists}
}
foreach ($change in $pending) {
    if ($change.Exists) {
        if ([IO.File]::ReadAllText($change.Path) -cne $change.Original) { throw 'Local settings changed concurrently.' }
    } elseif (Test-Path -LiteralPath $change.Path) { throw 'Local settings created concurrently.' }
}
[IO.File]::WriteAllText($tokenPath,$token,$utf8)
$grafanaPath = Join-Path $secretDir 'grafana-password'
if (-not (Test-Path -LiteralPath $grafanaPath)) { [IO.File]::WriteAllText($grafanaPath,(New-LocalSecret),$utf8) }
$envPath = Join-Path $root '.env'
if (-not (Test-Path -LiteralPath $envPath)) { [IO.File]::WriteAllText($envPath,[IO.File]::ReadAllText((Join-Path $root '.env.example')),$utf8) }
foreach ($change in $pending) { [IO.File]::WriteAllText($change.Path,$change.Updated,$utf8) }
Write-Host 'Local monitoring credentials synchronized. Secrets withheld. Rebuild/restart all applications before scraping.'
