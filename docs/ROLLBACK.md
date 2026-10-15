# 이전 이미지로 롤백

현재 프로젝트는 서비스별 Deployment YAML에 이미지 태그를 저장합니다. Git의 태그를 검토된 이전 이미지로 바꾸고 Argo CD가 반영하도록 합니다.

## 먼저 확인할 것

- 되돌릴 이미지가 현재 ECR에 존재하는가?
- 이전 이미지가 현재 DB·Secret·설정과 호환되는가?
- 일부 서비스만 되돌려도 API 계약이 호환되는가?
- 재구축 과정에서 이전 이미지가 삭제되지 않았는가?

10월 14일 ECR 정리를 수행했으므로 그 이전 태그가 남아 있다고 가정하지 않습니다.

## 절차

1. git pull로 최신 상태 확보
2. ECR에서 대상 태그 존재 확인
3. 대상 Deployment의 image 태그만 변경
4. 인증서·도메인·DB 설정 등은 현재 환경 유지
5. diff 검토 후 변경 파일만 stage
6. Git commit/push
7. Argo revision·Pod·실제 기능 확인

```powershell
git pull --ff-only origin main

# 예: 실제 존재하는 태그로 바꿔 조회
aws ecr describe-images --repository-name product-service --image-ids imageTag=EXISTING_TAG --region ap-northeast-2

# 편집 후
git diff -- msa/product/k8s/depl_svc.yml
git add msa/product/k8s/depl_svc.yml
git commit -m "Roll back product image tag [skip ci]"
git push origin main
```

EXISTING_TAG는 실제 태그로 바꿔야 합니다. 이 블록은 현재 롤백을 실행하라는 뜻이 아닙니다.

## 왜 skip ci를 사용하는가?

현재 workflow는 서비스의 k8s 파일 변경도 빌드 조건에 포함될 수 있습니다. 태그만 과거 이미지로 바꿨는데 CI가 현재 소스로 다시 빌드해 태그를 덮어쓰는 것을 피하려고 **순수 이미지 태그 롤백에 한해** skip ci를 사용합니다.

이는 CI 검사도 건너뛰므로 코드 수정이나 검증이 필요한 변경에 일반적으로 사용하지 않습니다. Argo CD는 Git 내용을 별도로 감시합니다.

## 반영 확인

```powershell
kubectl get applications.argoproj.io -n argocd
kubectl get deployment product-depl -n soldesk -o custom-columns="NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image"
kubectl get pods -n soldesk -l app=product
```

필요하면 대상 앱을 refresh하고, 의도한 이미지가 반영된 뒤 rollout과 기능을 확인합니다. rollout 성공만으로 이미지 변경을 단정하지 않습니다.

## 롤백으로 되돌릴 수 없는 것

- 이미 차감된 재고·생성된 주문
- 이미 발송된 메일
- 삭제한 데이터·이미지
- 새 DB 스키마 변경과의 비호환성

DB 복원과 서비스 이미지 롤백은 별도 절차입니다. Git 전체를 과거 시점으로 되돌리면 이전 인증서·환경 설정까지 복원될 수 있으므로 주의합니다.

[프로젝트 홈](../README.md) · [배포 이력](RELEASES.md)
