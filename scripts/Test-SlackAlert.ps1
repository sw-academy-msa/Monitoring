# 실제 서비스/Prometheus 규칙을 건드리지 않고 합성 경보의 발생과 복구를 발송합니다.
param([string]$AlertmanagerUrl='http://localhost:9093')
$ErrorActionPreference='Stop'
$testId=[guid]::NewGuid().ToString('N')
$start=[DateTimeOffset]::UtcNow
$labels=@{alertname='SlackDeliveryTest';severity='info';job='monitoring-test';instance='synthetic';test_id=$testId}
function Read-SlackSuccessCount {
    $text=(Invoke-WebRequest -UseBasicParsing -Uri ($AlertmanagerUrl+'/metrics') -TimeoutSec 5).Content
    $total=0.0;$failed=0.0
    foreach($line in ($text -split "`n")) {
        if($line -match '^alertmanager_notification_requests_total\{[^}]*integration="slack"[^}]*\}\s+([0-9.eE+\-]+)'){$total += [double]$matches[1]}
        if($line -match '^alertmanager_notification_requests_failed_total\{[^}]*integration="slack"[^}]*\}\s+([0-9.eE+\-]+)'){$failed += [double]$matches[1]}
    }
    return ($total-$failed)
}
function Wait-SlackSuccess([double]$before) {
    $observed=$false
    for($attempt=0;$attempt -lt 30;$attempt++) {
        # 전송 시작 카운터를 성공으로 보지 않고 완료된 요청의 증가를 연속 확인합니다.
        if((Read-SlackSuccessCount) -gt $before){if($observed){return};$observed=$true}else{$observed=$false}
        Start-Sleep -Seconds 2
    }
    throw 'No Slack success-counter increase observed. Verify receiver, network and webhook privately; URL withheld.'
}
function Send-TestState([DateTimeOffset]$end) {
    $alert=@{labels=$labels;annotations=@{summary='STOCKDROP Alertmanager Slack 연결 테스트, 실제 서비스 장애가 아닙니다.'};startsAt=$start.ToString('o');endsAt=$end.ToString('o')}
    $body=ConvertTo-Json -InputObject @($alert) -Depth 5 -Compress
    Invoke-RestMethod -Method Post -Uri ($AlertmanagerUrl+'/api/v2/alerts') -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 5 | Out-Null
}
$before=Read-SlackSuccessCount
try {
    Send-TestState ($start.AddMinutes(2))
    Wait-SlackSuccess $before
    Write-Host 'Firing test submitted; Slack success counter increased.'
} finally {
    # 실패/중단 시에도 합성 경보가 반복되지 않도록 같은 fingerprint를 복구 처리합니다.
    $resolvedBefore=Read-SlackSuccessCount
    Send-TestState ([DateTimeOffset]::UtcNow)
}
Wait-SlackSuccess $resolvedBefore
Write-Host 'Resolved test submitted; Slack success counter increased. Confirm both messages in the webhook channel.'
