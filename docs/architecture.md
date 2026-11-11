# 중앙 수집과 운영 전환

업무 앱 8개, Gateway 2개, Eureka의 모든 복제본을 사설 IP로 직접 수집합니다. ALB, Gateway, Eureka를 수집 프록시로 거치지 않습니다.
기존 업무 포트의 /actuator/prometheus는 전용 Bearer 토큰과 GET만 허용합니다. 업무 JWT는 대체할 수 없습니다.
빈 토큰이나 32자 미만 토큰은 거부합니다. 업무 인증과 /actuator/health 주소는 유지합니다.
운영은 사설망과 보안 그룹에서 모니터링 EC2의 수집만 허용하고 Gateway 공개 ALB 경로에서 메트릭을 차단합니다.

## 운영 전환 순서

1. 모니터링 EC2 EBS에 데이터 볼륨을 준비합니다. Docker named volume의 실제 경로가 EBS 위에 있는지 확인합니다.
2. 일반 ASG에 Project=STOCKDROP, Pool=general, 구매 ASG에 Project=STOCKDROP, Pool=purchase 태그를 인스턴스로 전파합니다.
3. prometheus.prod.yml의 서울 리전 예시와 호스트 포트를 실제 배치에 맞춥니다.
4. 모니터링 EC2 IAM Role에 ec2:DescribeInstances를 부여하고 컨테이너의 IMDSv2 접근/hop limit을 확인합니다. 장기 AWS 키는 저장하지 않습니다.
5. 운영 전용 수집 토큰을 서비스 .env와 secrets/scrape-token에 동기화합니다. 로컬 키를 운영에 재사용하지 않습니다.
6. 고정 Kafka/DB 대상은 prometheus/targets JSON에 사설 주소를 넣습니다. 현재 빈 목록은 미설정입니다.
7. 서비스 메트릭과 HTTP 헬스 모두 EC2 SD로 ASG 증설과 교체에 대응합니다. Kafka/DB의 고정 대상만 file SD를 사용합니다.
8. Linux 각 EC2에 exporters/compose.node.yaml을 적용합니다. Docker Desktop VM 지표를 Windows 호스트 지표로 취급하지 않습니다.
9. Command DB의 제한된 모니터링 전용 계정과 secrets/postgres-exporter.env를 준비한 뒤 DB Exporter를 적용합니다. 서비스 계정을 재사용하지 않습니다.
10. docker compose -f compose.yaml -f compose.prod.yaml config --quiet로 검사한 뒤 같은 파일 조합으로 up -d 합니다. 로컬 Kafka overlay는 운영에 사용하지 않습니다.
11. linux/arm64 manifest와 실제 ARM 실행, ASG 교체, 백업/복원, Grafana 패널과 외부 경보 수신을 검증합니다.

Prometheus up은 메트릭 수집 성공이며 서비스 전체 정상이나 주문 성공 보장이 아닙니다.
Blackbox는 /actuator/health의 HTTP200과 status=UP을 별도로 점검합니다.
RDS 지표는 기존 CloudWatch에서 관리하며 CloudWatch Exporter 배포를 완료한 구성은 아닙니다.
Prometheus는 15일/10GB 보존 상한을 적용합니다. 실제 EBS 용량과 쓰기량을 확인하고 조정합니다.
Alertmanager 기본값은 외부 발송 없음이며 Slack 설정은 docs/slack.md에 따라 선택적으로 활성화합니다. 수신 채널과 비밀값을 준비하고 승인된 채널만 연결합니다.
경보 임계값은 초기 제안값이며 k6 실측 전에 확정된 SLO로 보지 않습니다.
모니터링 EC2 한 대는 단일 장애점입니다. 수집기 중단 시 이 수집기의 경보 전달도 보장하지 않습니다.
메트릭 라벨에 사용자/상품/주문 ID, 토큰, 이메일, 원문 URL query를 넣지 않습니다.
운영 방화벽, EC2 생성, DB 변경과 Git add/commit/push는 자동으로 실행하지 않습니다.

Outbox를 소유한 Account, Product Command, Order Command, Payment, AI는 MONITORING_OUTBOX_ENABLED=true로 자기 DB의 집계를 활성화합니다.
30초 주기 집계 캐시를 제공하며 HTTP scrape마다 DB를 조회하지 않습니다. collector_available=0은 집계 실패이며 이전 건수를 0으로 바꾸지 않습니다.
