# 모니터링과 실습 결과

## 지표 수집과 이메일

```text
Spring · Node Exporter · kube-state-metrics
→ Prometheus
    → Grafana
    → Alertmanager → SNS → 관리자 메일
```

Prometheus는 지표를 수집하고 규칙을 평가합니다. Grafana는 지표를 보여주며 Alertmanager는 알림을 전달합니다.

### 실제 확인

- Prometheus: kube-state-metrics 1/1, node-exporter 2/2, Spring 대상 모두 UP
- 규칙: NodeNotReady 3분, DeploymentUnavailable 5분
- Alertmanager 활성 대상 확인
- SNS 구독 활성화
- 테스트 알림의 Gmail 실제 수신

테스트 알림은 Alertmanager에 직접 입력했습니다. 실제 노드를 장애 상태로 만들어 Prometheus 감지부터 끝까지 시험한 것은 아닙니다.

## Grafana 자동 복원

현재 ConfigMap provisioning으로 데이터 소스·대시보드를 관리합니다.

- datasource UID: msa-prometheus
- dashboard UID: aws-eks-msa-overview
- 새 Pod에서 Import 없이 MSA 폴더와 지표 표시 확인

대시보드에는 수집 상태, 가용 Pod, 재시작, CPU, JVM heap, Hikari active/max가 있습니다.

자동 설정 복원과 과거 지표 영구 저장은 다릅니다. Prometheus TSDB와 Grafana 기타 수동 설정을 PVC에 보존하는 구성은 아직 없습니다.

## Product 부하·자동 확장 시험

2026-10-14 기준:

| 항목 | 결과 |
|---|---|
| 대상 | Product 내부 상품 목록 GET |
| 시간 | 180초 |
| 부하 | 최대 약 20 req/s |
| 성공 | 3,550 |
| 오류 | 0 |
| 확장·축소 | 1→2→1 |
| 새 Pod | Ready·재시작 0 확인 |

다음 날 재구축 환경에서 같은 부하 시험을 다시 한 것은 아닙니다. Member/Ordering/Gateway 전체 경유 시험 결과로 확대해서 해석하지 않습니다.

HPA 축소는 Pod 생성 후 5분이 아니라 최근 확장 권고의 안정화 창을 고려합니다.

## 재구축 후 기능 시험

2026-10-15 기준:

- 홈페이지·공개 상품 API HTTP 200
- 새 DB의 상품 [] 확인
- 상품 등록과 이미지 표시
- 주문 후 재고 10→9
- 주문번호 1의 메일 실제 수신
- 앱 9개 Synced/Healthy, 정상 Pod 확인

## 아직 구분할 항목

- 정상 Pod 증감 메일: 미구현
- ASG 노드 증감 메일: 이벤트 연결 설정, 실수신 시험 미완료
- CloudWatch DLQ 알람: 설정 존재, 실제 발동 시험 미완료
- RDS 연결 한도 61·접속 9: 10월 14일의 측정이며 새 DB의 측정값이 아님
- Hikari active=0: 순간 사용 중 연결이 없다는 뜻, 전체 연결=0은 아님

## 접속

각 명령은 별도 창에서 유지합니다.

```powershell
kubectl port-forward -n monitoring svc/prometheus-service 9090:9090
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

Grafana admin 비밀번호는 Secret으로 관리합니다. 이메일·SNS 구독 취소 링크·Secret이 보이는 화면은 가린 뒤 공개합니다.

[프로젝트 홈](../README.md) · [이전: 배포 자동화](02-deployment.md) · [다음: 문제 해결](04-troubleshooting.md)
