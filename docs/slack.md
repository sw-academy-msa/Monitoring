# Alertmanager Slack 연결

사용자용 NotificationService와 별개인 운영자 경보입니다. 기존 Prometheus 경보 조건과 대기 시간은 유지합니다.
Slack Incoming Webhook을 생성할 때 지정한 채널로 발송합니다. Bot OAuth 토큰이나 사용자 로그인 토큰은 필요하지 않습니다.

1. https://api.slack.com/apps 에서 앱을 생성하거나 기존 앱을 선택합니다.
2. Incoming Webhooks를 활성화하고 Add New Webhook to Workspace에서 발송 채널을 선택합니다.
3. URL을 Monitoring/secrets/slack-webhook-url 파일에 한 줄로 저장합니다. 채팅이나 Git에 붙이지 않습니다.
4. 아래 명령으로 연결하고 합성 경보를 전송합니다.

```powershell
cd C:\Users\user\Desktop\Monitoring
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Enable-SlackAlerting.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Test-SlackAlert.ps1
```

URL 형식은 로컬에서 검사하며 비밀값은 출력하지 않습니다. Enable은 전용 secret 디렉토리에 URL을 복사하고 .env의 ALERTMANAGER_CONFIG_NAME만 변경합니다.
Compose는 이 선택을 유지하므로 기존 로컬/운영 Compose 조합으로 다시 시작해도 Slack 설정을 사용합니다.
테스트는 합성 SlackDeliveryTest 경보와 복구 메시지를 발송합니다. 실제 서비스를 종료하거나 주문 데이터를 변경하지 않습니다.
테스트의 카운터 증가는 Slack API 성공 응답을 의미하며 사람이 읽었음을 뜻하지 않습니다. 동시 경보가 있으면 해당 카운터는 다른 발송도 포함할 수 있으므로 채널에서 테스트 문구를 확인합니다.
기존 발생 경보가 있으면 Slack 활성화 직후 함께 전달될 수 있습니다. 반복은 4시간, 그룹 초기 대기는 30초이며 테스트 경보만 1초 대기입니다.
웹훅 주소가 잘못됐거나 폐기되면 성공으로 보고하지 않습니다. Alertmanager 로그에는 전송 오류 URL이 포함될 수 있으므로 원문 로그를 채팅/공개 이슈로 복사하지 않습니다.

비활성화는 .env에서 ALERTMANAGER_CONFIG_NAME=alertmanager.yml로 변경한 뒤 docker compose -f compose.yaml up -d --no-deps alertmanager 입니다.
기존 경보 규칙과 Prometheus 수집은 계속 유지됩니다. 운영에서는 secret 파일 권한과 HTTPS 외부 통신, NAT 경로를 확인하고 로컬 Webhook을 운영에 재사용하지 않습니다.

공식 문서: https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/ , https://prometheus.io/docs/alerting/latest/configuration/#slack_config
