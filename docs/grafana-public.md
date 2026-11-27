# Grafana 공개 주소 운영 적용 절차

이번 작업에서는 운영 명령을 실행하지 않았습니다. 기본 브랜치는 develop이고 운영 start.sh의 기본 참조는 main입니다. develop에만 병합하며 main으로 추가 병합하면 CD가 운영을 변경할 수 있습니다.

Infra의 Grafana 대상 그룹, HTTPS 규칙, SNI 인증서, Route53 Alias와 SG를 먼저 적용합니다. 3001은 ALB SG에서만 허용하고 Prometheus 9095는 공개하지 않습니다. 운영 overlay는 Grafana만 0.0.0.0:3001로 열고 Prometheus와 Alertmanager는 127.0.0.1을 유지합니다. GRAFANA_BIND_ADDRESS=10.20.10.40으로 사설 IP를 지정할 수도 있습니다. MONITORING_BIND_ADDRESS를 0.0.0.0으로 바꾸면 다른 서비스도 열리므로 변경하지 마세요. Compose 2.24.4 이상이 필요합니다.

회원가입, 익명 접근과 조직 생성을 금지하고 로그인 실패는 5분 동안 5회로 제한합니다. root URL은 https://grafana.stockdrop.cloud이며 secure cookie를 설정합니다. 변경된 관리자 비밀번호와 기존 /data/grafana를 유지합니다. [Grafana 공식 설정 문서](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/)

대시보드 provider는 updateIntervalSeconds: 30으로 파일 시스템 이벤트 대신 주기적으로 새 JSON을 확인합니다. 기존 STOCKDROP 폴더를 유지하기 위해 foldersFromFilesStructure는 사용하지 않습니다. 해당 옵션을 켜려면 고정 folder를 제거하고 디렉터리 구조에 맞춘 폴더로 전환해야 합니다.

## 사용자가 실행할 배포 명령

아래를 deploy-grafana.sh로 저장하고 RELEASE_SHA를 검토 완료된 develop 병합 SHA로 치환합니다. Grafana만 중지하여 SQLite 백업을 만든 후 Grafana만 재생성합니다. Prometheus와 exporter 및 EBS 마운트를 보존하기 위해 운영 compose.override.yaml까지 함께 사용합니다. 실패하면 아래 롤백을 실행합니다.

```bash
#!/bin/bash
set -euo pipefail
cd /opt/stockdrop/monitoring
RELEASE_SHA=REPLACE_WITH_REVIEWED_MERGE_SHA
[[ "$RELEASE_SHA" =~ ^[0-9a-f]{40}$ ]]
BACKUP="/opt/stockdrop/monitoring/backups/grafana-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 700 "$BACKUP"
printf '%s\n' "$BACKUP" > /opt/stockdrop/monitoring/last-grafana-backup
chmod 600 /opt/stockdrop/monitoring/last-grafana-backup
git -C repo rev-parse HEAD > "$BACKUP/revision"
cp -a repo/compose.yaml repo/compose.prod.yaml compose.override.yaml "$BACKUP/"
if [ -f repo/.env ]; then cp -a repo/.env "$BACKUP/repo.env"; fi
git -C repo diff --quiet && git -C repo diff --cached --quiet
git -C repo fetch origin develop
git -C repo merge-base --is-ancestor "$RELEASE_SHA" origin/develop
compose() { KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-kafka.stockdrop.internal:9092}" docker compose -p stockdrop-monitoring -f repo/compose.yaml -f repo/compose.prod.yaml -f compose.override.yaml "$@"; }
compose stop grafana
tar --acls --xattrs -C /data -czf "$BACKUP/grafana-data.tar.gz" grafana
git -C repo checkout --detach "$RELEASE_SHA"
compose config --quiet
compose up -d --no-deps --wait grafana
curl --fail --silent http://127.0.0.1:3001/api/health
printf 'Backup: %s\n' "$BACKUP"
```

다음은 로컬 Bash에서 스크립트를 SSM으로 전달하는 명령입니다. 명령 ID로 결과를 확인하고 브라우저에서 로그인 및 익명 대시보드 접근 차단을 확인합니다.

```bash
jq -Rs '{commands: ["bash -se <<'"'"'GRAFANA_DEPLOY'"'"'\n" + . + "\nGRAFANA_DEPLOY"], executionTimeout: ["900"]}' deploy-grafana.sh > deploy-grafana.json
aws ssm send-command --profile stockdrop --region ap-northeast-2 \
  --instance-ids i-00cc2156f0b1d893e --document-name AWS-RunShellScript \
  --comment 'Apply reviewed Grafana public configuration' \
  --parameters file://deploy-grafana.json --query Command.CommandId --output text
aws ssm get-command-invocation --profile stockdrop --region ap-northeast-2 \
  --instance-id i-00cc2156f0b1d893e --command-id REPLACE_WITH_COMMAND_ID
curl -fsS https://grafana.stockdrop.cloud/api/health
```

## 롤백

아래를 rollback-grafana.sh로 저장한 뒤 위 jq와 send-command 형식에서 파일명을 rollback-grafana로 바꿔 전달합니다. 백업 이후 Grafana 설정 변경은 되돌아갑니다.

```bash
#!/bin/bash
set -euo pipefail
cd /opt/stockdrop/monitoring
BACKUP=$(cat last-grafana-backup)
[[ "$BACKUP" == /opt/stockdrop/monitoring/backups/grafana-* ]]
compose() { KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-kafka.stockdrop.internal:9092}" docker compose -p stockdrop-monitoring -f repo/compose.yaml -f repo/compose.prod.yaml -f compose.override.yaml "$@"; }
compose stop grafana
git -C repo checkout --detach "$(cat "$BACKUP/revision")"
cp -a "$BACKUP/compose.yaml" "$BACKUP/compose.prod.yaml" repo/
cp -a "$BACKUP/compose.override.yaml" compose.override.yaml
if [ -f "$BACKUP/repo.env" ]; then cp -a "$BACKUP/repo.env" repo/.env; fi
mv /data/grafana "/data/grafana-before-rollback-$(date -u +%Y%m%dT%H%M%SZ)"
tar --acls --xattrs -C /data -xzf "$BACKUP/grafana-data.tar.gz"
compose config --quiet
compose up -d --no-deps --wait grafana
```

이전 버전이 loopback에만 바인딩하면 ALB health 실패는 예상된 결과입니다. SSM 포트 포워딩으로 확인합니다. Infra 롤백은 Grafana 관련 리소스만 제거하는 새 plan을 검토하며 api/pay와 EC2는 유지합니다.

## 로컬 검증 결과

Grafana 12.3.1 컨테이너를 loopback 13001로 실행해 검색 결과가 빈 상태에서 새 JSON을 추가했습니다. 재시작 없이 30초 후 STOCKDROP 폴더의 reload-proof 대시보드가 API 검색에 나타났으며 컨테이너 RestartCount는 0이었습니다.
