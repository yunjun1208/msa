# 배포 자동화

## 코드가 서비스로 반영되는 과정

```text
GitHub 코드 Push
→ GitHub Actions
→ OIDC 임시 인증
→ Docker 이미지 빌드·ECR 저장
→ GitOps YAML 이미지 태그 갱신 커밋
→ Argo CD 자동 동기화
→ 새 Pod 기동
```

이미지는 commit SHA로 추적합니다. 소스 커밋과 이미지 태그 갱신 커밋은 다릅니다.

## 자동화 도구의 역할

| 도구 | 담당 |
|---|---|
| Terraform | VPC·EKS·RDS·ECR·메시징 등 AWS 자원 |
| 01-platform.ps1 | Argo CD·컨트롤러·메트릭 도구 Helm 설치 |
| 02-configure-repo.ps1 | 빈 DB 초기화·Secret·환경별 YAML |
| GitHub Actions | 서비스 이미지 빌드·ECR push·태그 갱신 |
| Argo CD | 앱·HPA·모니터링 Git 설정 반영 |

SES 인증 링크·SNS 구독 확인은 사용자가 처리해야 합니다. 상품과 주문 데이터는 자동으로 복원되지 않습니다.

## Push 실행과 수동 실행

현재 workflow는 서비스 경로 변경에 따라 필요한 이미지를 빌드합니다. Kubernetes 배포 파일 변경도 해당 서비스 빌드 조건에 포함될 수 있습니다.

전체 삭제 후 ECR가 비었을 때는 수동 workflow_dispatch로 서비스 5개를 모두 빌드합니다. 변경한 서비스 하나만 빌드하면 나머지 이미지가 없어 Pod 기동이 실패할 수 있습니다.

## 배포 확인

```powershell
git pull --ff-only origin main
kubectl get applications.argoproj.io -n argocd
kubectl get pods -n soldesk
kubectl get hpa -n soldesk
kubectl get deployment member-depl ordering-depl product-depl apigateway-depl -n soldesk -o custom-columns="NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image"
```

확인 기준:

1. GitHub Actions 성공
2. ECR에 배포 이미지 존재
3. Argo CD가 의도한 Git revision 확인
4. 실제 Deployment 설정·태그 반영
5. 새 Pod Ready와 재시작 안정
6. HTTP·기능 확인

rollout status만 성공했다고 새 배포를 확인한 것은 아닙니다. 기존 배포가 정상이어도 성공할 수 있습니다.

## HPA와 Argo CD의 역할 분리

Argo CD는 Git의 replicas를, HPA는 부하에 따른 replicas를 바꾸므로 조정이 필요합니다. 현재 서비스 4개 Application에 /spec/replicas ignore와 RespectIgnoreDifferences=true를 적용했습니다.

## 변경 이력

[배포 이력](RELEASES.md)에서 소스 커밋·이미지 태그·GitOps 커밋을 구분합니다. [롤백 안내](ROLLBACK.md)에는 현재 CI에서 태그만 되돌릴 때의 주의점을 정리했습니다.

[프로젝트 홈](../README.md) · [이전: 프로젝트 구성](01-architecture.md) · [다음: 모니터링](03-monitoring-and-tests.md)
