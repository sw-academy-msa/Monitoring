# Kafka 지표 수집

Kafka Exporter는 토픽 오프셋과 소비 그룹 lag를 읽습니다. 메시지 생성이나 업무 데이터 변경은 하지 않습니다.
로컬은 공용 네트워크의 kafka:9092 INTERNAL listener를 사용합니다.
host.docker.internal:19092는 브로커가 localhost를 광고하여 컨테이너 내부에서 잘못 연결될 수 있으므로 사용하지 않습니다.
kafka.version=3.9.0은 Sarama 요청 호환 버전이며 기존 Kafka4.1 브로커 바이너리를 바꾸지 않습니다.
lag가 없으면 그룹이 아직 커밋하지 않았거나 지표가 미수집일 수 있으므로 0으로 강제 표시하지 않습니다.

## 브로커 지표

JMX Exporter는 Kafka JVM의 javaagent로 붙여 9404에서 브로커 MBean을 제공합니다. RMI/JMX 외부 포트를 열지 않습니다.
중앙 Prometheus와 Grafana는 모니터링 EC2에 유지합니다. agent는 Kafka EC2에서 실행합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Download-JmxExporter.ps1
docker compose -f ..\ProductQueryService\compose.kafka.yaml -f exporters\compose.kafka-jmx.local.yaml up -d kafka
```

jar 다운로드와 SHA-256 검증을 먼저 완료해야 합니다. override 적용 시 Kafka가 재시작되므로 진행 중인 테스트가 없는 시점에 실행합니다.
원복은 docker compose -f ../ProductQueryService/compose.kafka.yaml up -d kafka이며 기존 volume은 유지합니다.
운영은 기존 Kafka Compose에 agent, mount, 9404 사설 바인딩을 확인 후 적용합니다. 이 저장소가 AWS Kafka를 자동 수정하지 않습니다.
agent 미적용 시 브로커 패널은 No data/down입니다. 소비 그룹 지표와는 별개입니다.
클라이언트 오류는 실제 Micrometer Kafka 계측에서 노출된 항목만 표시합니다. 지표 부재를 성공으로 간주하지 않습니다.
단일 KRaft의 디스크 유실이나 장애를 exporter 설치로 복구하거나 HA로 만들지 않습니다.
