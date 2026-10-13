# 구상도 → 소스 및 실제 검증 매핑

> '구현'은 코드가 포함되어 있음을 의미하며, AWS에서 정상 동작까지 검증했다는 뜻이 아닙니다.

| 구상도 항목 | 소스/설정 구현 | AWS 실제 검증 |
|---|---|---|
| Route53 → ACM → ALB → EKS Ingress | `terraform/platform.tf`, `deploy/templates/alb-ingress.yml.tpl`, `scripts/02-configure-repo.ps1` | 미실행 |
| Frontend | `msa/frontend` 기존 베이스 | 이미지 빌드·접속 미실행 |
| Gateway JWT, Member/Product/Ordering 라우팅 | `msa/apigateway` 원본 + 헤더 위조 방지 | E2E 미실행 |
| Member / Product / Ordering | `msa/*` 기존 Spring 소스 유지 | DB 연결·기능 미실행 |
| 서비스별 MySQL 스키마/계정 분리 | `deploy/templates/db-bootstrap-job.yml.tpl`, `scripts/02-configure-repo.ps1` | DB Job 미실행 |
| S3 이미지 업로드 | Product AWS SDK + Pod Identity + S3 정책 | 업로드 미실행 |
| SNS → SQS → Lambda → SES / DLQ | Terraform Topic/Queue/Lambda/SES 및 OrderEventPublisher | Lambda 로직 단위 테스트 통과, 실송신 미실행 |
| ECR 5개, GitHub OIDC+Actions+SHA+Argo CD | Terraform IAM/ECR, `.github/workflows/`, `argocd/` | GitHub 빌드·동기화 미실행 |
| HPA Metrics Server / CA Node 확장 | `msa/k8s/k8s-hpa`, `scripts/01-platform.ps1`, `terraform/platform.tf` | Scale-out 미실행 |
| ExternalDNS → Route53 | Terraform IAM + Helm 설치 스크립트 | 레코드 생성 미실행 |
| Prometheus / Grafana / kube-state-metrics / Alertmanager→SNS | `msa/k8s/k8s-monitoring`, `deploy/templates/alertmanager.yml.tpl`, Terraform SNS Role | 수집/알림 미실행 |
| EventBridge ASG Launch/Terminate → SNS | `terraform/observability.tf` | AWS 이벤트 미실행 |
| CloudWatch / CloudTrail | `terraform/observability.tf`, `terraform/data.tf` | 실제 로그 미실행 |

**필수 외부 값**: AWS IAM 로그인, 공인 IP CIDR, GitHub Repo URL/OIDC sub, Route53 Hosted Zone/도메인, SES 발신 주소 및 인증. 이를 알지 못해 실제 자원 생성까지 대신 수행할 수 없습니다.

**운영 전에 보완**: SAGA+Outbox·메일 중복방지, TLS/서버 장애·부하 테스트, DB 백업, 원격 Terraform state, 실서비스 비밀관리, 실제 메일 도착 모니터링.
