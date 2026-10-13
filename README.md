# AWS EKS 쇼핑몰 MSA 파이널 프로젝트 — 구상도 반영 통합 소스

**기준 자료**: `베이스 파일.zip`의 MSA 소스, `구상도.png`의 아키텍처, AWS MSA 정리본 1~3의 실습 순서. 기존 회원/상품/주문/화면 코드를 보존하고 필요한 연결·인프라·보안을 보완했습니다. 원본 ZIP의 Git 이력과 AWS 자격증명은 포함하지 않습니다.

**범위 구분**: 이 프로젝트는 배포 가능한 구성 요소와 실행 스크립트가 갖춰진 **코드 통합본**입니다. **AWS 실제 배포 검증 완료본은 아닙니다.** AWS 계정, 구매·위임된 Route 53 도메인, SES 발신 이메일 인증, GitHub 저장소/권한과 Docker 빌드용 인터넷 연결이 있어야 구동됩니다. **`terraform apply`를 실행하면 지속적으로 과금**됩니다.

**2026-10-08 HCL 오류 수정:** `terraform/observability.tf`, `terraform/platform.tf`, `terraform/variables.tf`의 단일 행 블록 문법을 수정했습니다. 이미 프로젝트를 복사하여 `terraform.tfvars`를 설정했다면 수정된 TF 파일 3개만 덮어쓰세요. `terraform.tfvars` 또는 `.tfstate`를 삭제·덮어쓰지 마세요. `terraform fmt` → `terraform init` → `terraform validate` → `terraform plan` 순서로 사용자 환경에서 재검증해야 합니다. 제작 환경에는 Terraform 바이너리/Provider 설치가 없어 `init/validate/plan` 성공을 보장하지 않습니다.

## 아키텍처 구성

```text
브라우저 → Route53 → ACM 인증 HTTPS ALB → EKS Ingress (alb)
                                           ├─ Frontend(Nginx)
                                           └─ API Gateway (JWT, 경로 라우팅)
                                                ├─ Member (memberdb)
                                                ├─ Product (productdb, S3 images)
                                                └─ Ordering (orderingdb, product stock 호출)
                                                              └─ SNS order-events
                                                                    └─ SQS (+ DLQ)
                                                                         └─ Lambda → SES 거래성 이메일
RDS MySQL : private subnet / 서비스별 schema·DB 계정 분리
GitHub Actions → OIDC → ECR x5 (commit SHA) → GitOps manifest SHA 갱신 → Argo CD → EKS
HPA (Metrics Server) + Cluster Autoscaler (ASG tags / Pod Identity)
Prometheus(Node Exporter + kube-state-metrics) → Alertmanager → infra-alerts SNS → 관리자 이메일
ASG Node launch/terminate EventBridge → infra-alerts SNS
CloudWatch(EKS control-plane logs, SQS DLQ alarm) + CloudTrail(API audit events to S3)
ExternalDNS → Route53 (Ingress의 public DNS 레코드)
```

## 폴더 안내

| 경로 | 역할 |
| --- | --- |
| `msa/frontend` | 기존 쇼핑몰 정적 화면 |
| `msa/apigateway` | JWT 검사, backend URL 라우팅 |
| `msa/member` | 회원가입/로그인/관리자, 주문 이메일 내부 조회 |
| `msa/product` | 상품/이미지/S3/재고, 내부 재고 수정 인증 |
| `msa/ordering` | 주문·상품 Feign 호출, DB 커밋 후 SNS 발행 |
| `msa/*/k8s` | Deployment, Service, Pod Identity용 ServiceAccount |
| `msa/k8s/k8s-services` | **02번 스크립트가 생성하는** ALB Ingress/ConfigMap (GitOps 적용) |
| `msa/k8s/k8s-monitoring` | Prometheus, Grafana, Node Exporter, Alertmanager 설정 |
| `terraform` | VPC, 2AZ, NAT GW, EKS, ECR 5, RDS, S3, ACM, IAM, SNS/SQS/DLQ, SES/Lambda, CloudWatch/CloudTrail |
| `.github/workflows` | GitHub OIDC 인증, Docker 빌드, ECR SHA 태그, GitOps 이미지 갱신 |
| `argocd` | App-of-Apps 자동 배포 |
| `scripts` | EKS Add-on 설치 → 계정별 설정/DB 생성 → 상태 검증 |
| `deploy/templates` | Ingress, ConfigMap, Alertmanager, RDS bootstrap Job 템플릿 |
| `tests` | 소스/구성 정적 검증 및 주문 Lambda 단위 테스트 |

## 0. 준비사항 (Windows PowerShell)

- AWS CLI v2, Terraform 1.6+, Helm 3, kubectl, Git, Docker Desktop/Engine, PowerShell 5.1 이상.
- AWS 로그인(가능하면 SSO/임시 자격증명), 충분한 VPC/EKS/IAM/RDS/Route53/SES/ECR 권한.
- 본인 도메인의 **기존 퍼블릭 Route53 Hosted Zone**, 외부 등록기관의 NS가 Route53을 가리키는지 확인. ACM은 DNS 검증 레코드가 승인될 때까지 대기합니다.
- SES **발신자 이메일 인증**, 실 사용자에게 보내려면 SES 샌드박스 해제 혹은 인증된 수신자만 사용해야 합니다. Terraform이 이메일 인증 요청을 만들더라도 메일함에서 인증 작업은 수동으로 해야 합니다.
- GitHub 저장소 `https://github.com/OWNER/REPO.git`, Actions workflow에 대한 권한. GitHub의 OIDC 토큰 `sub` 형식은 저장소 생성 시점/조직 정책에 따라 달라집니다. 확인한 `sub`를 사용하세요.
- **동일 프로젝트를 기존 EKS/RDS와 혼용하지 마세요.** 새로운 Terraform은 새 VPC/EKS/RDS를 만듭니다. 기존 인프라를 사용하려면 state import, 데이터소스 조회 등 별도 설계가 필요합니다.

### 1. Terraform 인프라 만들기

```powershell
Copy-Item terraform\terraform.tfvars.example terraform\terraform.tfvars
notepad terraform\terraform.tfvars
aws sts get-caller-identity
terraform -chdir=terraform init
terraform -chdir=terraform fmt -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=tfplan
# 실제 자원 생성·비용에 동의한 후에만 실행
terraform -chdir=terraform apply tfplan
```

**`terraform.tfvars`에서 반드시 수정**: `admin_cidrs`(본인 실제 공인 IP `/32`), `github_oidc_subject`(본인 GitHub token `sub`), `domain_name`(쇼핑몰 서비스 호스트), `hosted_zone_id`, `ses_sender_email`. 필요에 따라 `admin_alert_email` 입력 후 SNS subscription 확인 메일의 링크 클릭. 이미 IAM GitHub OIDC provider가 있으면 `existing_github_oidc_provider_arn` 설정. `db_password` 등 **민감 Terraform state는 반드시 외부 유출을 방지**하세요. 실무에서는 S3 원격 backend + 잠금 구성 권장.

`kubernetes_version`은 1.35로 설정했습니다. 생성하는 EKS 버전과 Cluster Autoscaler 이미지 **minor 1.35는 일치**해야 합니다. 원하는 버전으로 바꾸면 `scripts/01-platform.ps1`의 CA 이미지 버전도 변경하세요.

### 2. Kubernetes 플랫폼 설치

```powershell
.\scripts\01-platform.ps1
```

스크립트가 kubeconfig를 신규 EKS로 바꾸고 namespace/ServiceAccount를 만든 뒤 Helm을 통해 AWS Load Balancer Controller, ExternalDNS, Cluster Autoscaler, Metrics Server, kube-state-metrics, Argo CD를 설치합니다. AWS LB Controller IAM 정책은 Terraform이 공식 v2.14.1 릴리스에서 읽어 배포합니다. 설치 완료 후 `kubectl get pods -A`로 확인하세요.

### 3. GitOps 설정 생성 + DB 스키마 분리 + Secret 생성

```powershell
.\scripts\02-configure-repo.ps1 -RepoUrl 'https://github.com/OWNER/REPO.git'
```

스크립트의 작업:

1. Terraform output을 읽어 `msa/k8s/k8s-services/ingress.yml`(**ALB/ACM/ExternalDNS**) 및 `runtime-config.yml`(상품 S3, 주문 SNS)을 생성.
2. `msa/k8s/k8s-monitoring/alertmanager.yml`의 SNS ARN/리전을 채우고, `argocd/*.yml`의 GitHub 저장소 URL을 자신의 저장소로 변경.
3. `soldesk` namespace에 DB master 자격증명을 **임시**로 생성, MySQL Job을 이용해 `memberdb`, `productdb`, `orderingdb` 및 각각 `memberapp`, `productapp`, `orderingapp` 생성·권한 부여. 완료되면 bootstrap Job/마스터 Secret 삭제.
4. 서비스별 `member-db-secret`, `product-db-secret`, `ordering-db-secret`, `jwt-secrets`, `internal-service-secret`와 `monitoring/grafana-admin`을 생성 (Git에 저장하지 않음).

이 스크립트를 **재실행하면 JWT/내부 서비스 토큰/DB 계정 비밀번호를 회전시킵니다.** 가동 중 반복 실행하면 기존 세션 및 서비스가 잠시 실패할 수 있습니다. 재실행 시에는 Deployment 재시작·Secret 교체 순서를 통제하세요. 관리자 최초 비밀번호는 `jwt-secrets` 내 `ADMIN_BOOTSTRAP_PASSWORD`에 생성되며 **표시하지 않습니다**. 최초 관리자 생성 후 복구 목적에만 사용하세요.

### 4. GitHub Actions와 Argo CD 배포

1. 저장소 **Actions → Variables**에 `AWS_GITHUB_ACTIONS_ROLE_ARN` = `terraform output github_actions_role_arn`, `AWS_REGION` = 리전 입력. Repository의 **Workflow permissions: Read and write** 허용. `main` 브랜치 자동 커밋 정책을 확인하세요.
2. 로컬의 `git add .`, `git commit -m "final project configuration"`, `git push origin main`. (`terraform.tfvars`·state·자격증명·`*.key`는 커밋하지 마세요.)
3. GitHub **Actions → CI - build SHA-tagged images → Run workflow** 최초 1회 실행: 5개 이미지를 ECR에 SHA 태그로 푸시하고 `msa/*/k8s/depl_svc.yml`을 실제 이미지 주소로 갱신한 커밋을 남깁니다.
4. GitHub 작업이 끝나면 `git pull`, 이후 **Argo CD Root Application** 등록:

```powershell
kubectl apply -f argocd/root-app.yml
kubectl get applications -n argocd
kubectl get pods -n soldesk
kubectl get ingress -n soldesk
```

`REPLACE_WITH_CI_SHA` 이미지가 남아 있으면 정상 이미지를 Pull할 수 없습니다. **Actions 성공 전 Argo CD 배포하지 마세요.** GitHub Actions는 배포 API에 직접 접근하지 않으며 Argo CD가 Git 변경 사항에 따라 Kubernetes를 갱신합니다.

### 5. 확인 및 시나리오 검증

```powershell
.\scripts\03-verify.ps1 -Domain 'shop.example.com'
kubectl get ingress -n soldesk
kubectl get hpa -n soldesk -w
kubectl get pods -n monitoring
kubectl logs -n soldesk deployment/ordering-depl --tail=100
kubectl logs -n kube-system deployment/cluster-autoscaler --tail=100
```

기능별 확인: HTTPS 접속 → 회원가입/로그인 → 상품 등록+이미지 S3 URL → 상품 조회 → 주문 → 회원/상품/주문 **별도 DB** 데이터 변화 → Ordering SNS publish 로그 → SQS Lambda 로그 `EMAIL_SUBMITTED_TO_SES` → 수신자 이메일 확인. 실패 시 SES identity/sandbox, IAM Pod Identity, SNS subscription, Lambda SQS redrive(DLQ) 순서대로 조사합니다. **Lambda 로그에 SES 수락 로그가 있다고 실제 메일함 도착이 보장되는 것은 아닙니다.**

Prometheus/Grafana/Argo CD는 공개 Ingress를 제거하고 포트포워딩 접속을 기본으로 합니다:

```powershell
kubectl -n monitoring port-forward svc/grafana 3000:3000
# 다른 터미널
kubectl -n monitoring port-forward svc/prometheus-service 9090:9090
# 다른 터미널
kubectl -n argocd port-forward svc/argocd-server 8081:80
```

Grafana 주소 `http://localhost:3000`, 관리자 암호는 Kubernetes Secret `grafana-admin`에서 확인. Datasource: `http://prometheus-service.monitoring.svc.cluster.local:9090`. Alertmanager는 `kube-state-metrics` 상태를 Prometheus Rule에서 검출하고 SNS `infra-alerts`로 보냅니다.

### 6. 테스트

```powershell
node --test tests/lambda.test.mjs
python tests/validate_assets.py
```

실행 환경에 Terraform, Docker, Helm, Gradle 빌드 네트워크가 있다면 반드시 추가로 `terraform validate/plan`, 5개 Docker build, EKS 실제 API 시나리오를 검증하세요. 새 Terraform 모듈이 전부 동작하는지는 **해당 AWS 계정에서의 plan/apply가 필요**합니다.

## 주의할 설계 한계

- **주문 원자성**: 원본처럼 Product 재고 차감과 Ordering 주문 저장이 서로 다른 DB 트랜잭션입니다. 동시 주문에 대한 락/보상 트랜잭션(SAGA), 이벤트 송신 재시도·Transactional Outbox 및 이메일 중복 방지(Idempotency)는 미구현입니다. DB 커밋 후 SNS 발행 실패 시 **로그만 기록**되므로 운영에서 주문 알림이 누락될 수 있습니다.
- **서비스별 계정·스키마 분리**: RDS 물리 인스턴스 하나 안에서 `memberdb`, `productdb`, `orderingdb`의 접근만 분리합니다. 고가용성 Multi-AZ나 서비스별 물리 DB 분리는 아닙니다.
- **인프라**: NAT Gateway 1개, RDS Single-AZ, 워커 2개, Terraform local state로 비용 절감 실습형 구성입니다. 운영 환경에서 NAT 2AZ/DB HA/원격 state/백업/Secret Manager/네트워크 정책 필요.
- **S3**: 기존 프런트엔드가 공개 이미지 URL을 사용하므로 `/products/*`만 Public GetObject입니다. AWS Account-level Block Public Access 정책이 이를 막는 경우 배포를 중지하고 CloudFront/private origin 등으로 개선하세요. 전체 버킷 공개 금지.
- **이메일**: SES 발신 ID 검증/샌드박스 탈출 또는 검증된 수신자가 필요합니다. SMTP 액세스 키를 쓰지 않습니다.
- **모니터링**: Prometheus/Grafana는 PVC 미지정이라 Pod 재생성 시 저장 데이터가 없어질 수 있습니다. 실무에서는 스토리지/PVC나 AMP 등 활용.
- **보안**: 이전 학습 문서에 있던 Access Key를 새 ZIP으로 복사하지 않았습니다. 기존 공개·공유 키가 실제 사용 중이면 반드시 IAM에서 폐기하고 재발급하세요. `terraform.tfstate`는 DB master password를 포함할 수 있으므로 Git에 올리지 마세요.
- **과금/삭제**: `terraform destroy` 전에 RDS 데이터와 S3 파일 백업. S3 객체가 남아 있으면 `force_destroy=false`로 삭제가 실패할 수 있습니다. Route53 도메인·Hosted Zone은 Terraform에서 새로 만들지 않습니다.

## 참고 공식 문서

- AWS EKS Load Balancer Controller: https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html
- AWS EKS Pod Identity: https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html
- ExternalDNS Helm chart: https://kubernetes-sigs.github.io/external-dns/latest/charts/external-dns/
- Cluster Autoscaler AWS: https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md
- Alertmanager SNS: https://prometheus.io/docs/alerting/latest/configuration/
