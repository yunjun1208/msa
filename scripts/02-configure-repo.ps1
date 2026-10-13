#Requires -Version 5.1
# Generates environment-specific GitOps manifests and creates runtime Kubernetes secrets.
# The script does not push Git changes nor run AWS terraform apply.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RepoUrl)
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
function TF([string]$name) {
  $v = (& terraform -chdir=terraform output -raw $name)
  if ($LASTEXITCODE -ne 0) { throw "Terraform output '$name' 실패" }
  return ($v | Out-String).Trim()
}
$domain = TF 'site_domain'
$cert = TF 'acm_certificate_arn'
if ([string]::IsNullOrWhiteSpace($domain) -or [string]::IsNullOrWhiteSpace($cert)) {
  throw '도메인·Route53 Hosted Zone·ACM 인증서가 Terraform에서 준비되어야 합니다.'
}
if ($RepoUrl -notmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?$') { throw 'GitHub HTTPS Repository URL 형식만 허용합니다.' }
if (-not $RepoUrl.EndsWith('.git')) { $RepoUrl += '.git' }

# 기존 Secret이 존재하면 초기화 스크립트 재실행 차단
# 비밀번호 및 인증 토큰의 의도하지 않은 변경 방지

foreach ($secretName in @(
    'member-db-secret',
    'product-db-secret',
    'ordering-db-secret',
    'jwt-secrets',
    'internal-service-secret'
)) {

    # 기존 Secret 존재 여부 조회
    $existingSecret = & kubectl get secret $secretName `
        -n soldesk `
        --ignore-not-found `
        -o name

    if ($LASTEXITCODE -ne 0) {
        throw "Secret 조회 실패: $secretName. EKS 연결 및 권한을 확인하세요."
    }

    if (-not [string]::IsNullOrWhiteSpace(
        ($existingSecret | Out-String).Trim()
    )) {
        throw "기존 Secret '$secretName' 발견. 초기화를 중단합니다."
    }
}

$placeholders = @{
  '__SITE_DOMAIN__' = $domain;
  '__ACM_ARN__' = $cert;
  '__PRODUCT_IMAGE_BUCKET__' = (TF 'product_image_bucket');
  '__ORDER_EVENTS_TOPIC_ARN__' = (TF 'order_events_topic_arn');
  '__INFRA_SNS_TOPIC__' = (TF 'infra_alerts_sns_arn');
  '__REGION__' = (TF 'aws_region')
}
$templates = @{
  'deploy/templates/alb-ingress.yml.tpl' = 'msa/k8s/k8s-services/ingress.yml';
  'deploy/templates/runtime-config.yml.tpl' = 'msa/k8s/k8s-services/runtime-config.yml';
  'deploy/templates/alertmanager.yml.tpl' = 'msa/k8s/k8s-monitoring/alertmanager.yml'
}
foreach ($source in $templates.Keys) {

    $destination = Join-Path (Get-Location) $templates[$source]

    $parent = Split-Path -Parent $destination

    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $contents = [System.IO.File]::ReadAllText(
        (Join-Path (Get-Location) $source)
    )

    foreach ($key in $placeholders.Keys) {
        $contents = $contents.Replace($key, $placeholders[$key])
    }

    [System.IO.File]::WriteAllText(
        $destination,
        $contents,
        (New-Object System.Text.UTF8Encoding($false))
    )
}
Get-ChildItem argocd -Recurse -Filter '*.yml' | ForEach-Object {
  $contents = [System.IO.File]::ReadAllText($_.FullName)
  $contents = $contents.Replace('https://github.com/REPLACE_OWNER/REPLACE_REPO.git', $RepoUrl)
  [System.IO.File]::WriteAllText($_.FullName, $contents, (New-Object System.Text.UTF8Encoding($false)))
}
# Cross-origin unnecessary when the shop and backend share the same host, but valid domain helps if needed.

# API Gateway 환경 변수 설정
$gatewayYml = 'msa/apigateway/k8s/depl_svc.yml'
$gatewayPath = Join-Path (Get-Location) $gatewayYml

# 기존 Deployment YAML 읽기
$contents = [System.IO.File]::ReadAllText($gatewayPath)

# 기존 파일의 줄바꿈 형식 유지
$nl = if ($contents.Contains("`r`n")) {
    "`r`n"
} else {
    "`n"
}

$originEntry = '        - name: APP_ALLOWED_ORIGIN'
$jwtEntry = '        - name: JWT_ACCESS_SECRET'
$originValue = "          value: 'https://$domain'"

# 기존 APP_ALLOWED_ORIGIN 선언 확인
$existingOrigin = '(?m)^[ \t]*- name: APP_ALLOWED_ORIGIN[ \t]*$'

if ([regex]::IsMatch($contents, $existingOrigin)) {

    # 이미 존재하면 value 값만 갱신
    $pattern = '(?m)^([ \t]*- name: APP_ALLOWED_ORIGIN[ \t]*\r?\n[ \t]*value:)[^\r\n]*'

    if (-not [regex]::IsMatch($contents, $pattern)) {
        throw "APP_ALLOWED_ORIGIN의 value 형식을 확인하세요."
    }

    $replacement = '${1} ' + "'https://$domain'"

    $contents = [regex]::Replace(
        $contents,
        $pattern,
        $replacement
    )

} else {

    # 없으면 JWT_ACCESS_SECRET 앞에 새로 추가
    if (-not $contents.Contains($jwtEntry)) {
        throw "JWT_ACCESS_SECRET 환경 변수를 찾을 수 없습니다."
    }

    $contents = $contents.Replace(
        $jwtEntry,
        "$originEntry$nl$originValue$nl$jwtEntry"
    )
}

# 수정된 Deployment YAML 저장
[System.IO.File]::WriteAllText(
    $gatewayPath,
    $contents,
    (New-Object System.Text.UTF8Encoding($false))
)


# Kubernetes Namespace 생성 및 오류 검증
foreach ($ns in @('soldesk', 'monitoring')) {

    # 1. Namespace YAML 생성
    $manifest = & kubectl create namespace $ns `
        --dry-run=client `
        -o yaml

    if ($LASTEXITCODE -ne 0 -or -not $manifest) {
        throw "Namespace YAML 생성 실패: $ns"
    }

    # 2. Kubernetes 클러스터에 적용
    $manifest | & kubectl apply -f -

    if ($LASTEXITCODE -ne 0) {
        throw "Namespace 적용 실패: $ns"
    }

    Write-Host "Namespace 확인 완료: $ns"
}

# No passwords in Git or Terraform-generated Kubernetes manifests.
# Temporarily write secrets to private local files; Kubernetes secret is still etcd-backed.
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('msa-secrets-'+[guid]::NewGuid().ToString('N'))
New-Item -Path $temp -ItemType Directory -Force | Out-Null
try {
  function RandomSecret([int]$n) {
    $b = New-Object byte[] $n
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($b)
  }

function ApplySecret(
    [string]$name,
    [string]$namespace,
    [hashtable]$values
) {

    # 1. Secret 생성 명령어 준비
    $kubectlArgs = @(
        'create', 'secret', 'generic',
        $name, '-n', $namespace
    )

    # 2. 각 Secret 데이터를 임시 파일로 저장
    foreach ($k in $values.Keys) {

        $file = Join-Path $temp $k

        [System.IO.File]::WriteAllText(
            $file,
            [string]$values[$k],
            (New-Object System.Text.UTF8Encoding($false))
        )

        $kubectlArgs += "--from-file=$k=$file"
    }

    $kubectlArgs += @('--dry-run=client', '-o', 'yaml')

    # 3. Secret YAML 생성
    $secretYaml = & kubectl @kubectlArgs

    if ($LASTEXITCODE -ne 0 -or -not $secretYaml) {
        throw "Secret YAML 생성 실패: $name"
    }

    # 4. Kubernetes에 Secret 적용
    $secretYaml | & kubectl apply -f -

    if ($LASTEXITCODE -ne 0) {
        throw "Kubernetes Secret 적용 실패: $name"
    }

    # 5. 적용 완료 후 임시 파일 삭제
    foreach ($k in $values.Keys) {
        Remove-Item (Join-Path $temp $k) -Force
    }

    Write-Host "Kubernetes Secret 적용 완료: $name"
}

  ApplySecret 'my-app-secrets' 'soldesk' @{ DB_HOST=(TF 'db_host'); DB_PW=(TF 'db_password') }
  # Create isolated schemas + limited-per-schema application users in RDS.
$sql = @("CREATE DATABASE IF NOT EXISTS memberdb CHARACTER SET utf8mb4;",
          "CREATE DATABASE IF NOT EXISTS productdb CHARACTER SET utf8mb4;",
          "CREATE DATABASE IF NOT EXISTS orderingdb CHARACTER SET utf8mb4;")


# DB 초기화가 완료될 때까지 애플리케이션 Secret 생성 보류
$pendingServiceSecrets = @()
$dbHost = TF 'db_host'

foreach ($service in @('member', 'product', 'ordering')) {

    $password = (RandomSecret 36).Replace('+','A').Replace('/','B').Replace('=','C')
    $username = $service + 'app'
    $database = $service + 'db'

    # 비밀번호는 메모리에 보관하고 Kubernetes에는 아직 적용하지 않음
    $pendingServiceSecrets += [pscustomobject]@{
        Name = $service + '-db-secret'
        Values = @{
            DB_HOST = $dbHost
            DB_NAME = $database
            DB_USER = $username
            DB_PW   = $password
        }
    }

    # RDS 초기화 SQL 생성
    $sql += "CREATE USER IF NOT EXISTS '$username'@'%' IDENTIFIED BY '$password';"
    $sql += "ALTER USER '$username'@'%' IDENTIFIED BY '$password';"
    $sql += "GRANT ALL PRIVILEGES ON $database.* TO '$username'@'%';"
}

  $sql += 'FLUSH PRIVILEGES;'
  ApplySecret 'msa-bootstrap-sql' 'soldesk' @{ 'init.sql'=($sql -join "`n") }
  & kubectl delete job msa-db-bootstrap -n soldesk --ignore-not-found=true | Out-Null
  & kubectl apply -f deploy/templates/db-bootstrap-job.yml.tpl
  if ($LASTEXITCODE -ne 0) { throw 'Database bootstrap Job 생성 실패' }
  & kubectl wait --for=condition=complete job/msa-db-bootstrap -n soldesk --timeout=360s
  if ($LASTEXITCODE -ne 0) {
    & kubectl logs -n soldesk job/msa-db-bootstrap --tail=40
    throw 'RDS schema/user initialization FAILED. Workloads should not be deployed.'
  }

# RDS 초기화에 성공한 경우에만 애플리케이션 DB Secret 생성
foreach ($item in $pendingServiceSecrets) {

    ApplySecret $item.Name 'soldesk' $item.Values

    Write-Host "DB Secret 생성 완료: $($item.Name)"
}

  & kubectl delete job msa-db-bootstrap -n soldesk --ignore-not-found=true | Out-Null
  & kubectl delete secret msa-bootstrap-sql my-app-secrets -n soldesk --ignore-not-found=true | Out-Null
  # On later runs, re-generating JWT invalidates existing sessions. Store secrets safely after first run.
  ApplySecret 'jwt-secrets' 'soldesk' @{ JWT_ACCESS_SECRET=(RandomSecret 64); JWT_REFRESH_SECRET=(RandomSecret 64); ADMIN_BOOTSTRAP_PASSWORD=(RandomSecret 24) }
  ApplySecret 'internal-service-secret' 'soldesk' @{ INTERNAL_SERVICE_TOKEN=(RandomSecret 48) }
  ApplySecret 'grafana-admin' 'monitoring' @{ GF_SECURITY_ADMIN_PASSWORD=(RandomSecret 24) }
} finally { Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'GitOps manifest 생성 완료. Runtime secrets는 Kubernetes에 생성했으며 Git에 포함되지 않습니다.'
Write-Host "도메인: https://$domain"
Write-Host '다음: git add -> git commit -> git push; GitHub Actions 첫 실행 -> Argo CD root app apply.'
