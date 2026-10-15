# AWS · EKS 쇼핑몰 운영 프로젝트

Terraform으로 AWS 인프라를 구성하고, GitHub Actions와 Argo CD로 쇼핑몰을 배포한 실습 프로젝트입니다.

회원·상품·주문 기능을 실행하는 것에서 시작해 **배포 자동화, 자동 확장, 장애 대응, 이메일 알림, 모니터링**까지 연결했습니다. 전체 인프라를 삭제한 뒤 다시 구축하며 재구축 과정도 확인했습니다.

> 검증 기준: 2026-10-15. 현재 외부 접속은 **NLB**를 사용합니다. 초기 구상도의 ALB·Ingress와 다른 부분은 [프로젝트 구성](docs/01-architecture.md)에 구분했습니다.

## 프로젝트 문서

처음 보는 사람도 흐름을 따라갈 수 있도록 구성·배포·검증·장애 대응으로 나눴습니다.

| 문서 | 내용 |
|---|---|
| [프로젝트 구성](docs/01-architecture.md) | 서비스 역할, AWS 구성, 요청과 알림 흐름 |
| [배포 자동화](docs/02-deployment.md) | GitHub Actions → ECR → Argo CD → EKS |
| [모니터링과 실습 결과](docs/03-monitoring-and-tests.md) | 지표, 이메일 알림, Product 확장·축소 시험 |
| [문제 해결 기록](docs/04-troubleshooting.md) | DB 연결 과다, 잘못된 메일 수신자, 재구축 설정 |
| [삭제와 재구축](docs/05-rebuild.md) | 실행 단계와 Terraform apply의 자동화 범위 |

[배포 이력·이미지 태그](docs/RELEASES.md) · [이전 이미지로 롤백](docs/ROLLBACK.md)

## 현재 구성

```text
사용자 → Route 53 → NLB·ACM → Frontend Nginx → API Gateway
                                                ├─ Member
                                                ├─ Product → S3 이미지
                                                └─ Ordering → Product 재고 차감
                                                     └─ SNS → SQS → Lambda → SES → 주문자

Member·Product·Ordering → RDS MySQL의 서비스별 스키마·계정

Prometheus → Grafana
     └─ Alertmanager → SNS → 관리자 메일
```

## 사용 기술

- **서비스:** Java · Spring Boot · JPA · Spring Cloud Gateway · OpenFeign
- **화면:** HTML · CSS · JavaScript · Nginx
- **인프라:** Terraform · VPC · EKS · IAM · RDS · S3 · ACM · Route 53
- **배포:** Docker · ECR · GitHub Actions · OIDC · Argo CD · Helm
- **알림:** SNS · SQS · DLQ · Lambda · SES
- **관측:** Prometheus · Grafana · Alertmanager · CloudWatch · CloudTrail

## 저장소 구조

```text
.
├─ terraform/          # AWS 인프라
├─ scripts/            # 플랫폼 설치·환경 초기화
├─ argocd/             # GitOps 애플리케이션
├─ msa/                # 서비스 코드·Kubernetes 배포 설정
├─ deploy/templates/   # 런타임 설정·DB 초기화 템플릿
├─ tests/              # 정적 검사·Lambda 테스트
└─ docs/               # 구성·실습·배포·운영 기록
```

## 확인한 결과

| 실습 | 확인한 결과 |
|---|---|
| 인프라 재구축 | 전체 삭제 후 Terraform 리소스 94개 생성 |
| 서비스 배포 | Argo CD 앱 9개 Synced / Healthy |
| 외부 접속 | 홈페이지·공개 상품 API HTTPS 200 |
| 주문 흐름 | 로그인 상태, 상품·이미지 표시, 주문 후 재고 10→9 |
| 주문 알림 | 주문 접수 이메일 실제 수신 |
| Product 부하·HPA | 180초 조회 3,550건, 오류 0, Pod 1→2→1 |
| 모니터링 | 애플리케이션·노드·Kubernetes 지표 수집 |
| 관리자 알림 | Alertmanager → SNS → 이메일 실제 수신 |
| Grafana 복원 | 새 Pod에서 데이터 소스·MSA 대시보드 자동 생성 |

Product 부하·HPA 시험은 **10월 14일**, 빈 환경 재구축과 모니터링 검증은 **10월 15일**에 진행했습니다. 현재 리소스 수는 이후 추가한 SNS 구독 등으로 달라질 수 있습니다.

## 실습 범위

AWS 인프라는 Terraform, EKS 플랫폼은 PowerShell·Helm, 애플리케이션은 YAML·Argo CD로 관리합니다. **Terraform apply 한 번으로 쇼핑몰 전체가 완성되지는 않습니다.**

정상 Pod 증감 메일, 노드 증감 메일의 실제 수신 시험, Prometheus 지표 영구 저장, 재고 동시성·주문 실패 보상·알림 중복 방지는 후속 과제입니다.

AWS 자원이 실행 중이면 비용이 발생합니다. state·tfvars·Secret·토큰·개인정보가 포함된 복구 자료는 공개하지 않습니다.
