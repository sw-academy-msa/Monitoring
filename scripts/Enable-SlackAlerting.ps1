# URL을 출력하거나 환경 변수/추적 파일에 넣지 않고 전용 secret으로 전달합니다.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'secrets\slack-webhook-url'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Save your Slack Incoming Webhook URL to secrets/slack-webhook-url first.' }
$webhook = [IO.File]::ReadAllText($source).Trim()
$uri = $null
if (-not [Uri]::TryCreate($webhook,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'hooks.slack.com' -or -not $uri.IsDefaultPort -or $uri.UserInfo -ne '' -or $uri.Query -ne '' -or $uri.Fragment -ne '' -or $uri.AbsolutePath -notmatch '^/services/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$') {
    throw 'Invalid Slack Incoming Webhook URL. Value withheld; existing configuration preserved.'
}
$secretDirectory = Join-Path $root 'secrets\alertmanager'
[IO.Directory]::CreateDirectory($secretDirectory) | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
$target = Join-Path $secretDirectory 'slack-webhook-url'
[IO.File]::WriteAllText($target,$webhook,$utf8)
$envFile = Join-Path $root '.env'
if (-not (Test-Path -LiteralPath $envFile)) { throw 'Initialize local monitoring before enabling Slack.' }
$original = [IO.File]::ReadAllText($envFile)
$pattern = '(?m)^ALERTMANAGER_CONFIG_NAME=[^\r\n]*'
if ([regex]::Matches($original,$pattern).Count -gt 1) { throw 'Duplicate Alertmanager config selection. Existing .env preserved.' }
$updated = if ([regex]::IsMatch($original,$pattern)) { [regex]::Replace($original,$pattern,'ALERTMANAGER_CONFIG_NAME=alertmanager.slack.yml') } else { $original.TrimEnd("`r","`n") + "`r`nALERTMANAGER_CONFIG_NAME=alertmanager.slack.yml`r`n" }
Push-Location $root
try {
    & docker run --rm --entrypoint /bin/amtool -v "${root}/alertmanager:/work:ro" -v "${secretDirectory}:/run/secrets/alertmanager:ro" prom/alertmanager:v0.28.1 check-config /work/alertmanager.slack.yml
    if ($LASTEXITCODE -ne 0) { throw 'Slack Alertmanager config validation failed. Existing .env preserved.' }
    if ([IO.File]::ReadAllText($envFile) -cne $original) { throw 'Monitoring .env changed concurrently.' }
    [IO.File]::WriteAllText($envFile,$updated,$utf8)
    & docker compose -f compose.yaml config --quiet
    if ($LASTEXITCODE -ne 0) { [IO.File]::WriteAllText($envFile,$original,$utf8); throw 'Compose validation failed. Existing config selection restored.' }
    & docker compose -f compose.yaml up -d --no-deps alertmanager
    if ($LASTEXITCODE -ne 0) { throw 'Alertmanager restart failed. Inspect local status privately.' }
    Write-Host 'Slack alert routing selected and Alertmanager restarted. Webhook withheld. Run Test-SlackAlert.ps1 to verify delivery.'
} finally { Pop-Location }
