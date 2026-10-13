#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Domain)
$ErrorActionPreference = 'Stop'
Write-Host 'EKS + 배포 상태'

# 1. EKS Worker Node 확인
& kubectl get nodes
if ($LASTEXITCODE -ne 0) {
    throw "EKS Node 조회 실패"
}


# 2. Argo CD Application 동기화 및 Health 검사
Write-Host "Argo CD Application 상태 확인"

$appJson = & kubectl get applications.argoproj.io -n argocd -o json

if ($LASTEXITCODE -ne 0 -or -not $appJson) {
    throw "Argo CD Application 조회 실패"
}

$appData = ($appJson -join "`n") | ConvertFrom-Json

if ($appData.items.Count -eq 0) {
    throw "Argo CD Application이 존재하지 않습니다."
}

foreach ($app in $appData.items) {

    $name = $app.metadata.name
    $sync = [string]$app.status.sync.status
    $health = [string]$app.status.health.status

    Write-Host "$name : Sync=$sync / Health=$health"

    if ($sync -ne "Synced" -or $health -ne "Healthy") {
        throw "Argo CD Application 상태 비정상: $name"
    }
}

Write-Host "Argo CD Application 상태 정상" -ForegroundColor Green


# 3. MSA Deployment / HPA / Pod 확인
& kubectl get deployments,hpa,pods -n soldesk
if ($LASTEXITCODE -ne 0) {
    throw "MSA 리소스 조회 실패"
}
# MSA Deployment Ready 상태 검증
Write-Host "MSA Deployment 준비 상태 확인"

$deployJson = & kubectl get deployments -n soldesk -o json

if ($LASTEXITCODE -ne 0 -or -not $deployJson) {
    throw "Deployment 정보 조회 실패"
}

$deployments = ($deployJson -join "`n") | ConvertFrom-Json

if ($deployments.items.Count -eq 0) {
    throw "soldesk 네임스페이스에 Deployment가 없습니다."
}

foreach ($deployment in $deployments.items) {

    $name = $deployment.metadata.name
    $desired = [int]$deployment.spec.replicas
    $ready = [int]$deployment.status.readyReplicas
    $available = [int]$deployment.status.availableReplicas

    Write-Host "$name : Ready=$ready / Desired=$desired"

    if ($desired -eq 0 -or
        $ready -lt $desired -or
        $available -lt $desired) {

        throw "Deployment 준비 실패: $name"
    }
}

Write-Host "조회된 MSA Deployment 준비 상태 정상" -ForegroundColor Green



# 4. ALB Ingress 확인
& kubectl get ingress -n soldesk
if ($LASTEXITCODE -ne 0) {
    throw "Ingress 조회 실패"
}

# 5. 모니터링 Pod 확인
& kubectl get pods -n monitoring
if ($LASTEXITCODE -ne 0) {
    throw "Monitoring Pod 조회 실패"
}


# API Gateway Health Check
Write-Host "API Gateway 및 MSA Health Check 시작"

# 검증할 서비스 목록
$services = @(
    'member-service',
    'product-service',
    'ordering-service'
)

foreach ($service in $services) {

    # 1. 서비스 Health Check URL 구성
    $url = "https://$Domain/$service/health"

    Write-Host "확인 중: $url"

    # 2. HTTP 상태 코드 조회
    $httpCode = & curl.exe `
        --silent `
        --show-error `
        --max-time 20 `
        --output NUL `
        --write-out "%{http_code}" `
        $url

    # 3. 네트워크 또는 TLS 연결 오류 확인
    if ($LASTEXITCODE -ne 0) {
        throw "연결 실패: $service"
    }

    # 4. HTTP 200 응답 확인
    if ($httpCode -ne '200') {
        throw "Health Check 실패: $service (HTTP $httpCode)"
    }

    Write-Host "정상: $service (HTTP 200)" -ForegroundColor Green
}

Write-Host "MSA Health Check 완료!" -ForegroundColor Green
Write-Host "다음: 로그인, 상품 이미지, 주문, SES, SQS/DLQ 기능 테스트"
