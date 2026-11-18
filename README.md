# STOCKDROP Monitoring

중앙 Prometheus, Grafana, Alertmanager, HTTP 헬스 점검과 Kafka 지표 수집 설정입니다. Git 연결과 AWS 배포는 하지 않습니다.

## 로컬 실행

Docker Desktop, 기존 업무 서비스와 공용 Kafka를 먼저 준비합니다. Monitoring은 Desktop의 서비스 디렉토리들과 나란히 둡니다.

```powershell
cd C:\Users\user\Desktop\Monitoring
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Initialize-LocalMonitoring.ps1
# 각 서비스를 새 코드로 빌드하고 재시작합니다.
docker compose -f compose.yaml -f compose.kafka.yaml up -d
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Test-Monitoring.ps1
```

| 화면 | 로컬 주소 |
|---|---|
| Grafana | http://localhost:3001 |
| Prometheus | http://localhost:9095 |
| Alertmanager | http://localhost:9093 |

Grafana 사용자명은 admin, 비밀번호는 무시된 secrets/grafana-password 파일에 생성됩니다. 채팅이나 로그에 출력하지 않습니다.
Prometheus는 기존 S3Mock 9090과 충돌하지 않도록 호스트 9095를 사용합니다.
Grafana STOCKDROP 폴더의 서비스, Kafka, 인프라 대시보드는 자동 등록됩니다. UI 편집 대신 JSON 원본을 수정합니다.
Docker named volume에 데이터를 보존하며 down -v를 사용하지 않습니다.

## 상세 문서

- [배치와 보안, 운영 전환](docs/architecture.md)
- [Kafka 브로커와 소비 그룹](docs/kafka.md)
- [Alertmanager Slack 발송](docs/slack.md)

JMX agent, Linux EC2의 Node Exporter, PostgreSQL Exporter와 운영 대상 주소는 각각 적용해야 합니다.
미설정 대상을 정상이나 0으로 꾸미지 않으므로 해당 패널의 No data/down은 준비 상태를 확인해야 합니다.
Alertmanager 기본값은 외부 발송 없음입니다. Slack은 비밀 Webhook 파일을 준비한 뒤 별도 활성화합니다. docs/slack.md를 확인합니다.
