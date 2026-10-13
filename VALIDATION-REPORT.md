# 통합본 검증 기록 (2026-10-08)

## 완료한 로컬 검사

- `python tests/validate_assets.py`: **PASS**. Kubernetes/GitHub YAML **34개 파일 / 43개 YAML 문서** 파싱, 서비스별 5개 Deployment/Container 이미지 규칙, 서비스별 DB Secret 구분 및 Pod Identity 기초 구조, 필수 Terraform·GitOps 파일 존재, 텍스트 내 AWS 장기 Access Key 형태 검사, HCL 괄호/인용부호 기본 검사 통과.
- `node --test tests/lambda.test.mjs`: **3/3 PASS**. 정상 SNS/SQS 주문 메시지 파싱·SES 전달 호출, 잘못된 메시지의 SQS batch failure, SES 오류 시 재시도 대상 반환.
- `node --check msa/frontend/src/assets/app.js`: **PASS**. JavaScript 파일 문법 검사.
- Terraform 변수 기본 문법 오탈자, 누락된 Gradle Wrapper JAR에 대한 컨테이너 빌드 방식, 재고 업데이트 내부 토큰 보호, JWT 전달 헤더, 초기 관리자 비밀번호 외부화 연결, 공개 Ingress 제거, DB 스키마/계정 분리, 원본 문서의 Access Key 미포함 검토.

## 현재 환경에서 실행하지 못한 항목

| 테스트 | 상태 / 제한 |
|---|---|
| `terraform init`, `terraform validate`, `terraform plan/apply` | **미실행**: Terraform 바이너리 및 외부 provider 다운로드 불가 |
| 5개 Spring Gradle 빌드·JUnit·Docker 이미지 빌드 | **미실행**: Docker/Gradle 및 외부 Maven artifact 다운로드 불가 |
| PowerShell 자동화 스크립트 실제 실행 | **미실행**: PowerShell, AWS CLI, kubectl, Helm 런타임 없음 |
| EKS/VPC/RDS/S3/ALB/Route53/SES 실배포 | **미실행**: AWS 로그인 및 사용자 계정/도메인 입력 미제공 |
| GitHub Actions/OIDC/Argo CD 동기화 | **미실행**: 사용자 저장소·IAM 연동 필요 |
| 이메일 실제 도착, HPA/노드 자동 확장, CloudWatch·CloudTrail 기록 | **미실행**: AWS 실배포 필요 |

**판정**: 코드 통합 및 제한적 정적·단위 테스트 통과. **AWS에서 정상 작동이 입증된 완성 배포본은 아님**. 사용자 환경의 `terraform validate → plan → apply`, Docker 빌드, 배포 후 E2E 검증을 반드시 완료해야 함.

## 리스크 및 개선과제

1. 주문·재고 분산 트랜잭션 보상과 SNS 누락 방지를 위한 SAGA/Outbox 필요. 현재 SNS는 주문 커밋 후 직접 발행하므로 publish 실패 시 DB 주문은 이미 확정된 상태.
2. SES 수락이 메일 수신/중복 방지/수신거부 정책 구현을 의미하지 않음. Lambda/SQS at-least-once 처리에 따라 중복 메일 가능.
3. 실서비스 이전에 관리자 인증, JWT 로테이션, RDS 최소 권한, S3 이미지 접근·파일 검사, 프런트엔드 XSS, NAT/RDS HA, Prometheus 저장, Terraform 원격 state/잠금 보강 필요.
4. AWS 계정 레벨 S3 Public Access Block 정책은 현재 공개 상품 이미지 버킷 정책과 충돌할 수 있음.


## 2026-10-08 HCL 오류 수정
- `observability.tf`: CloudTrail SSE rule 중첩 블록 1건, IAM policy document principals 2건, condition 3건을 다중 행 HCL 블록으로 정정.
- `platform.tf`: Autoscaling group tag 2건 정정.
- `variables.tf`: `cloudtrail_retention_days` 변수의 다중 인수 단일 행 블록 1건 정정.
- `tests/validate_assets.py`: 동일한 문법 실수를 감지하는 정적 검사 추가.
- **한계:** Terraform CLI 및 AWS provider 플러그인이 실행 환경에 없어 실제 `terraform init`, `validate`, `plan`, `apply`는 실행하지 못함.
