#Requires -Version 5.1
# Executes only after terraform apply; installs cluster platform add-ons.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
foreach ($tool in @('aws','terraform','kubectl','helm')) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool CLI 설치가 필요합니다." }
}
function TF([string]$name) {
  $value = (& terraform -chdir=terraform output -raw $name)
  if ($LASTEXITCODE -ne 0) { throw "Terraform output '$name' 실패" }
  return ($value | Out-String).Trim()
}
$region = TF 'aws_region'
$cluster = TF 'cluster_name'
$vpc = TF 'vpc_id'
Write-Host "대상 클러스터: $cluster / $region / $vpc"

# Terraform에서 사용한 AWS 계정 확인
$expectedAccount = TF 'aws_account_id'

# 현재 AWS CLI 인증 계정 확인
$actualAccount = (& aws sts get-caller-identity --query Account --output text)

if ($LASTEXITCODE -ne 0) {
    throw "AWS CLI 인증 확인 실패"
}

$actualAccount = ($actualAccount | Out-String).Trim()

# Terraform 계정과 AWS CLI 계정 비교
if ($expectedAccount -ne $actualAccount) {
    throw "AWS 계정 불일치: Terraform=$expectedAccount / CLI=$actualAccount"
}

Write-Host "AWS 계정 확인 완료: $actualAccount"

& aws eks update-kubeconfig --region $region --name $cluster
if ($LASTEXITCODE -ne 0) { throw 'kubeconfig 설정 실패' }
& kubectl get nodes
if ($LASTEXITCODE -ne 0) { throw 'EKS 노드 접근 실패' }
foreach ($ns in @('soldesk','monitoring','argocd')) {
  & kubectl create namespace $ns --dry-run=client -o yaml | & kubectl apply -f -
  if ($LASTEXITCODE -ne 0) { throw "namespace $ns 실패" }
}
foreach ($name in @('aws-load-balancer-controller','external-dns','cluster-autoscaler')) {
  & kubectl create serviceaccount $name -n kube-system --dry-run=client -o yaml | & kubectl apply -f -
  if ($LASTEXITCODE -ne 0) { throw "serviceaccount $name 실패" }
}
& helm repo add eks https://aws.github.io/eks-charts --force-update
& helm repo add autoscaler https://kubernetes.github.io/autoscaler --force-update
& helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ --force-update
& helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
& helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
& helm repo add argo https://argoproj.github.io/argo-helm --force-update
& helm repo update
if ($LASTEXITCODE -ne 0) { throw 'Helm repositories 갱신 실패' }
# Controller matches the policy pinned at Terraform platform.tf (LBC v2.14.1 / chart 1.14.0).
& helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller `
  -n kube-system --version 1.14.0 --wait --timeout 10m `
  --set "clusterName=$cluster" --set "region=$region" --set "vpcId=$vpc" `
  --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller
if ($LASTEXITCODE -ne 0) { throw 'AWS Load Balancer Controller 설치 실패' }
& helm upgrade --install external-dns external-dns/external-dns -n kube-system --wait --timeout 10m `
  --set provider.name=aws --set serviceAccount.create=false --set serviceAccount.name=external-dns `
  --set policy=upsert-only --set "txtOwnerId=$cluster" --set "sources[0]=service" `
  --set "domainFilters[0]=$(TF 'site_domain')"
if ($LASTEXITCODE -ne 0) { throw 'ExternalDNS 설치 실패' }
& helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler -n kube-system --wait --timeout 10m `
  --set "autoDiscovery.clusterName=$cluster" --set "awsRegion=$region" `
  --set rbac.serviceAccount.create=false --set rbac.serviceAccount.name=cluster-autoscaler `
  --set image.tag=v1.35.0
if ($LASTEXITCODE -ne 0) { throw 'Cluster Autoscaler 설치 실패' }
& helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system --wait --timeout 10m
if ($LASTEXITCODE -ne 0) { throw 'Metrics Server 설치 실패' }
& helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics -n monitoring --wait --timeout 10m
if ($LASTEXITCODE -ne 0) { throw 'kube-state-metrics 설치 실패' }
& helm upgrade --install argocd argo/argo-cd -n argocd --wait --timeout 15m `
  --set server.service.type=ClusterIP `
  --set-string 'configs.params.server\.insecure=true'

if ($LASTEXITCODE -ne 0) { throw 'Argo CD 설치 실패' }
& kubectl get pods -A
Write-Host '플랫폼 설치 끝. 이제 02-configure-repo.ps1 실행 후 Git push, GitHub Actions 이미지 빌드, Argo CD sync를 수행하세요.'
