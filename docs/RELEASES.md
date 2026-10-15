# 배포 이력·이미지 태그

Git 이력과 실습 확인 기록을 구분해 정리했습니다. 아래 “단계”는 문서상의 분류이며 Git 태그나 GitHub Release를 새로 생성한 것은 아닙니다.

커밋 시간은 한국 시간 기준입니다. **커밋 시각은 실제 AWS 배포 완료 시각과 다릅니다.**

## 주요 변경 이력

| 날짜·커밋 시각(KST) | 변경 | 커밋 | 확인 범위 |
|---|---|---|---|
| 10/13 13:15 | 인프라·서비스 초기 소스 | [f294bbc](https://github.com/yunjun1208/msa/commit/f294bbc) | 초기 코드 이력 |
| 10/14 15:01 | NLB·ECR 배포 자동화 | [5d51b21](https://github.com/yunjun1208/msa/commit/5d51b21) | 이후 NLB HTTPS 접속 확인 |
| 10/14 15:12 | 이전 AWS 계정 검증 수정 | [52bd276](https://github.com/yunjun1208/msa/commit/52bd276) | 환경 설정 보완 |
| 10/14 15:20 | ECR 계정 ID 수정 | [4b95c73](https://github.com/yunjun1208/msa/commit/4b95c73) | 이미지 빌드·태그 반영 |
| 10/14 16:40 | Gateway JWT 필터 순서 | [a46a444](https://github.com/yunjun1208/msa/commit/a46a444) | Gateway 상품 조회 401→200 확인 |
| 10/14 19:44 | DB 서비스 HPA 최대 1개 | [cee4bc8](https://github.com/yunjun1208/msa/commit/cee4bc8) | 기존 Pod 초기 안정화 |
| 10/14 19:48 | Hikari max3/minIdle1 | [6ce91cf](https://github.com/yunjun1208/msa/commit/6ce91cf) | 새 Pod 기동·DB 접속 확인 |
| 10/14 20:32 | startupProbe·HPA 소유권 | [80a9ab6](https://github.com/yunjun1208/msa/commit/80a9ab6) | 라이브 Probe와 Argo ignore 설정 확인 |
| 10/14 20:40 | DB 서비스 HPA 최대 2개 | [4d4bf22](https://github.com/yunjun1208/msa/commit/4d4bf22) | 이후 Product 1→2→1 시험 |
| 10/15 12:41 | 새 인증서·초기화 보완 | [d6a18ba](https://github.com/yunjun1208/msa/commit/d6a18ba) | 재구축 Frontend 인증서·중복 제거 |
| 10/15 12:49 | 전체 이미지 태그 반영 | [dbad5db](https://github.com/yunjun1208/msa/commit/dbad5db) | 5개 ECR·YAML 태그 대조, 새 환경 배포 |
| 10/15 15:09 | Grafana GitOps provisioning | [351eb08](https://github.com/yunjun1208/msa/commit/351eb08) | 새 Pod에서 데이터 소스·대시보드 복원 |

## 이미지 태그와 GitOps 커밋

| 이미지 태그 앞자리 | 태그 갱신 커밋 | 범위 |
|---|---|---|
| 4b95c73 | 22accd5 | 초기 이미지 배포 |
| a46a444 | 7cd6611 | Gateway 변경 반영 |
| 6ce91cf | 6475139 | Member·Ordering·Product 풀 제한 |
| 80a9ab6 | 3baf822 | Java 서비스 기동·GitOps 설정 변경 |
| d6a18ba | c48532e | 재구축 Frontend 변경 |
| c48532e | dbad5db | 수동 실행으로 서비스 5개 전체 빌드 |

소스 커밋 SHA를 이미지 태그로 사용하고 CI가 다른 커밋으로 manifest를 갱신합니다.

c48532e 자체는 이전 실행의 태그 갱신 커밋이지만, 수동 실행이 이 main revision을 대상으로 수행돼 **5개 이미지의 태그**가 됐습니다.

### 10월 15일 전체 재구축 이미지

```text
apigateway       : c48532ecc6305d4d65cddf10ba45eba472ae9c1a
frontend-service : c48532ecc6305d4d65cddf10ba45eba472ae9c1a
member-service   : c48532ecc6305d4d65cddf10ba45eba472ae9c1a
ordering-service : c48532ecc6305d4d65cddf10ba45eba472ae9c1a
product-service  : c48532ecc6305d4d65cddf10ba45eba472ae9c1a
```

351eb08은 Grafana 설정 커밋입니다. 서비스 이미지를 모두 351eb08로 재빌드했다는 의미가 아닙니다.

## 커밋과 별도로 확인한 운영 작업

### 10월 14일

- 신규 Pod의 MySQL 연결 실패 로그 확인
- HPA·풀 제한 이후 정상 기동·DB 접속 확인
- 잘못된 주문 알림 수신자 복구 및 DLQ 정리
- Product 3,550건 조회 오류 0, 1→2→1 확인
- 사용자 결정으로 데이터 포함 전체 삭제, 마지막 감사 버킷까지 제거
- 최종 Terraform state가 비어 있음 확인

### 10월 15일

- 새 인프라 94개 생성과 EKS/노드그룹/RDS 정상 상태
- Helm 6개 설치·DB bootstrap·Secret 생성
- 수동 Actions #8 전체 이미지 빌드 성공
- 앱 배포·새 NLB·HTTPS·새 상품 주문과 메일 수신
- 관리자 SNS 구독 추가·확인 및 테스트 메일 수신
- Grafana 새 Pod에서 자동 복원·지표 표시

회원 이메일 변경, SNS 구독 확인, 테스트 알림, 인프라 삭제 등은 반드시 Git 커밋으로 남는 작업이 아니므로 코드 이력과 구분합니다.

## 이전 이미지 사용 주의

10월 14일 전체 삭제 과정에서 ECR 이미지도 삭제했습니다. **옛 SHA가 Git에 있다는 사실만으로 ECR에서 실행할 수 있는 것은 아닙니다.**

롤백 전 해당 이미지가 현재 ECR에 있는지 확인해야 합니다. DB 스키마·Secret·현재 인증서와 호환되는지도 따로 확인합니다.

[프로젝트 홈](../README.md) · [롤백 안내](ROLLBACK.md)
