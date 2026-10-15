# 삭제와 재구축

## Terraform apply는 어디까지 하나?

| 단계 | 수행 범위 |
|---|---|
| Terraform apply | AWS 네트워크·EKS·RDS·ECR·IAM·메시징 등 |
| 01-platform.ps1 | kubeconfig·namespace·Helm 플랫폼 설치 |
| 02-configure-repo.ps1 | 빈 DB 초기화·Secret·환경 설정 |
| GitHub Actions 수동 실행 | 서비스 이미지 5개 빌드·ECR·태그 갱신 |
| Argo CD root 적용 | 앱·HPA·모니터링·Grafana 자동 설정 |

SES 인증, SNS 구독 확인, 도메인 위임 조건, 회원·상품·주문 생성은 별도입니다. 과거 데이터가 자동으로 돌아오는 절차가 아닙니다.

## 빈 환경 재구축 순서

1. 계정·리전·로컬 저장소·현재 state 확인
2. 개인 tfvars와 현재 EKS 접근 CIDR 확인
3. init → validate → plan 검토 → apply
4. EKS/노드그룹 ACTIVE, RDS available 확인
5. 플랫폼 설치
6. 빈 환경 DB·Secret 생성
7. 인증서 ARN·Gateway 환경변수·Git diff 확인
8. 환경 설정 반영 후 GitHub Actions 수동 전체 빌드
9. ECR와 manifest 태그 확인
10. root 앱 적용
11. DNS·HTTPS·새 Pod·메일·모니터링 확인

```powershell
git pull --ff-only origin main
aws sts get-caller-identity --query Account --output text
terraform "-chdir=terraform" state list
terraform "-chdir=terraform" init
terraform "-chdir=terraform" validate
terraform "-chdir=terraform" plan "-out=rebuild.tfplan"

# 계획 검토 후 실행. AWS 자원과 비용이 발생한다.
terraform "-chdir=terraform" apply "rebuild.tfplan"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\01-platform.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\02-configure-repo.ps1 -RepoUrl "https://github.com/OWNER/REPO.git"

# 환경 설정과 이미지 준비를 확인한 다음
kubectl apply -f argocd/root-app.yml
```

OWNER/REPO는 실제 환경으로 바꿉니다. 다른 저장소에서 실행하려면 OIDC trust와 기존 Argo repoURL 등도 확인합니다. 기존 Secret이 있으면 초기화 보호 장치를 제거하지 말고 현재 상태부터 확인합니다.

처음 재구축에서는 94개 생성됐지만 관리자 SNS 이메일 구독 추가 등으로 현재 개수는 달라질 수 있습니다.

## 전체 삭제의 순서와 주의

**삭제는 데이터 손실이 발생하는 별도 작업입니다.**

1. 보존할 데이터·로컬 설정을 결정
2. 계정·대상과 최신 destroy plan 확인
3. 진행 중 CI 확인 및 Argo CD의 재생성 방지
4. LBC를 유지한 상태에서 Frontend Service와 NLB·target group 정리
5. 프로젝트 CloudTrail 기록 중지
6. 대상 ECR 이미지와 S3 객체·버전·삭제 마커 정리
7. 변경된 실제 환경 기준으로 최신 destroy plan 생성
8. 계획 실행 후 state와 AWS 잔여 자원 확인

현재 RDS는 skip_final_snapshot=true, deletion_protection=false입니다. S3는 force_destroy=false라 내용이 남으면 삭제가 실패할 수 있습니다. state가 비어도 공용 Hosted Zone·로그 등 비용이 남을 수 있습니다.

로컬 삭제·복구 보조 스크립트는 특정 계정·리소스에 종속돼 있고 이 문서 묶음에 포함하지 않습니다. 다른 계정에 그대로 복사하지 않습니다.

[프로젝트 홈](../README.md) · [이전: 문제 해결](04-troubleshooting.md)
