# 문제 해결 기록

## 1. 새 Pod가 DB 연결 실패로 종료

### 증상과 증거

HPA 확장 이후 Product 새 Pod가 반복 종료됐습니다. 이전 실행 로그에 MySQL 1040 Too many connections, JPA 초기화 실패, Exit Code 1이 있었습니다.

한 실행은 약 43초 만에 종료됐고 liveness는 60초 후 시작하므로 해당 실행의 직접 종료 원인은 liveness가 아니었습니다.

### 원인 분석과 조치

Pod가 늘수록 DB 연결 풀 합계가 증가하는데 서비스별 상한이 명시되지 않았습니다.

- HPA max를 일시적으로 1로 제한
- DB 서비스 Hikari max3/minIdle1 설정
- startupProbe 도입
- Argo CD가 HPA replicas 변경을 존중하도록 보완
- 안정화 후 HPA max2

Argo CD 충돌 가능성을 보완했지만 그것이 최초 DB 오류의 직접 원인이었다고 확정하지는 않습니다.

### 결과

새 Pod 정상 기동, DB 신규 접속 성공, Product 부하 오류 0과 1→2→1 확인.

## 2. 주문 알림이 잘못된 이메일로 실패

회원 이메일을 바꿔도 이미 큐에 들어간 이벤트의 수신자는 바뀌지 않았습니다.

원본 백업과 주문·회원 대조 후 수신자만 정정한 알림을 처리했습니다. 실제 수신 확인 후 DLQ 원본을 삭제했습니다.

복구를 위해 주문을 다시 만들지 않아 추가 재고 차감을 피했습니다. 과거 고정 메시지 ID가 들어간 복구 스크립트는 재구축 후 재사용하지 않습니다.

## 3. 재구축 후 이전 인증서 ARN과 환경변수 중복

placeholder만 치환하면 이미 렌더링된 ARN은 갱신되지 않았습니다. Windows CRLF 환경에서 Gateway APP_ALLOWED_ORIGIN 탐지도 보완이 필요했습니다.

현재 Terraform 인증서 출력으로 annotation을 갱신하고 환경변수를 1개로 정리했습니다. 수정된 초기화 파일은 scripts/ 아래에 배치합니다.

DB·Secret 생성이 이미 성공한 환경에서는 문제를 고치려고 초기화 전체를 다시 실행하지 않습니다.

## 4. Grafana 수동 설정 소실 가능성

PVC 없는 Grafana의 수동 데이터 소스·대시보드는 새 Pod에서 유지되지 않을 수 있었습니다.

ConfigMap provisioning과 고정 UID로 전환하고 새 Pod에서 Import 없이 복원되는 것을 확인했습니다. 과거 TSDB 지표를 보존하는 해결책과는 다릅니다.

## 5. Terraform 삭제 중 S3 BucketNotEmpty

CloudTrail 버킷을 비운 뒤 지연 로그가 남아 마지막 버킷 삭제가 실패했습니다.

남은 state를 확인하고 해당 버킷의 버전·삭제 마커까지 비운 뒤 새 destroy plan으로 마무리했습니다. 최종 state list가 빈 것을 확인했습니다.

실패 후 state 파일을 지우거나 오래된 삭제 계획을 그대로 재사용하지 않습니다.

## 6. 정상 배포처럼 보였지만 새 revision 미반영

Push 직후 Argo CD는 이전 커밋 기준 Synced/Healthy였고 rollout status도 성공했습니다.

새 변경 검증에는 revision·이미지 태그·실제 설정·Pod 교체를 같이 봐야 했습니다. 대상 앱 refresh 후 새 revision 반영을 확인했습니다.

[프로젝트 홈](../README.md) · [이전: 모니터링](03-monitoring-and-tests.md) · [다음: 삭제·재구축](05-rebuild.md)
