# 시연 Saga 패널

OrderCommandService PR #27의 지표 계약을 사용합니다. 서비스 main 배포와 `MONITORING_SAGA_ENABLED=true` 활성화는 운영 담당자가 수행하며 이 변경은 운영을 수정하지 않습니다.

추가 패널은 from/to별 최근 5분 상태 전이, 진행 중 수, 단계별 최근 5분 보상 완료, 가장 오래된 진행 중 나이, DB 상태별 주문 수, 수집 상태입니다. 주문 서비스 근처의 Saga 상자는 진행 중, 최근 5분 CONFIRMED, FAILED 또는 EXPIRED, 보상 완료 단계 수를 표시합니다. 지표가 없으면 상자 제목은 배포 후 표시이고 숫자는 대시로 표시합니다.

공유 DB 게이지는 `max`로 집계하고 collector available과 app up을 인스턴스별로 검사합니다. 프로세스 카운터는 복제본마다 `increase[5m]` 후 `sum`합니다. 가장 오래된 나이는 단계 진입 시각이 아닌 주문 생성 시각 기준입니다. PAYMENT_CANCEL과 STOCK_RELEASE는 별도 보상 완료 단계이므로 보상 수를 실패 주문 수로 해석하지 않습니다. 쿠폰 반환 완료는 CouponService에서 비동기로 처리하므로 주문 서비스 지표에 포함하지 않습니다.

Canvas의 모든 추가 요소는 scale 제약을 유지합니다. CI에서 연결선 교차, 서비스 및 Saga 상자 침범, 필드 바인딩, Kafka gauge에 대한 rate 오용을 검사합니다.

Kafka 토픽 계약을 대조하여 주문 문의, 멤버십 결제 결과, 광고 명령과 결과, 쿠폰 캠페인 알림도 발행 토픽 합계에 포함했습니다. 토픽 그래프는 내부 `__` 토픽을 제외합니다. 발행/s는 매핑된 토픽의 유입 추정이며 여러 서비스가 같은 토픽을 발행하면 생산자를 구분할 수 없습니다. 특히 캠페인 알림은 AI와 Coupon이 함께 발행하므로 서비스 고유 발행 성공률로 해석하지 않습니다. DLT 재발행은 별도 상세 패널로 봅니다.

운영 적용 순서: OrderCommandService 배포 및 플래그 활성화, 지표 확인, Monitoring 대시보드 적용, 필요 시 broker JMX topic 규칙을 별도 적용합니다. JMX topic 카운터 적용 전에도 Kafka 그래프는 exporter offset fallback으로 동작합니다.
