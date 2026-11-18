# 외부 발송이나 업무 API 변경 없이 설정과 경보 규칙을 검증합니다.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    & docker compose -f compose.yaml -f compose.kafka.yaml config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Compose configuration failed.' }
    & docker compose run --rm --no-deps --entrypoint /bin/promtool prometheus check config /etc/prometheus/prometheus.yml
    if ($LASTEXITCODE -ne 0) { throw 'Prometheus configuration failed.' }
    & docker run --rm --entrypoint /bin/promtool -v "${root}/prometheus:/work:ro" -w /work/tests prom/prometheus:v3.13.5 test rules alerts.test.yml
    if ($LASTEXITCODE -ne 0) { throw 'Alert rule tests failed.' }
    & docker run --rm --entrypoint /bin/amtool -v "${root}/alertmanager:/work:ro" prom/alertmanager:v0.28.1 check-config /work/alertmanager.yml
    if ($LASTEXITCODE -ne 0) { throw 'Alertmanager configuration failed.' }
    Write-Host 'Monitoring configuration and alert rule tests passed. Live targets and delivery require separate checks.'
} finally { Pop-Location }
