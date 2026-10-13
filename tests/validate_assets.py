"""Static checks only. They do NOT substitute for Terraform plan, Docker builds or AWS deploy."""
import re
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
files = sorted(p for p in ROOT.rglob('*') if p.is_file() and p.suffix in ('.yml', '.yaml'))
assert files, 'Missing YAML manifests'
count = 0
for file in files:
    docs = list(yaml.safe_load_all(file.read_text(encoding='utf-8-sig')))
    count += len(docs)
    for doc in docs:
        if not isinstance(doc, dict):
            continue
        if doc.get('kind') == 'Deployment':
            containers = doc['spec']['template']['spec'].get('containers', [])
            assert containers, f'Deployment has no containers: {file}'

services = ['apigateway', 'member', 'product', 'ordering', 'frontend']
for svc in services:
    assert (ROOT / f'msa/{svc}/Dockerfile').is_file(), svc
    deployment = ROOT / f'msa/{svc}/k8s/depl_svc.yml'
    assert deployment.is_file(), deployment
    manifest = deployment.read_text()
    assert ('REPLACE_WITH_CI_SHA' in manifest or re.search(r'image: .*:[0-9a-f]{40}\b', manifest)), f'CI SHA image format missing: {svc}'
    assert '256187519952' not in manifest, 'Old account ID remains'

for svc in ('member', 'product', 'ordering'):
    deploy = (ROOT / f'msa/{svc}/k8s/depl_svc.yml').read_text()
    conf = (ROOT / f'msa/{svc}/src/main/resources/application-prod.yml').read_text()
    assert f'{svc}-db-secret' in deploy
    assert 'DB_NAME' in deploy and 'DB_USER' in deploy and '${DB_NAME}' in conf
    assert 'INTERNAL_SERVICE_TOKEN' in deploy

must_have = ['terraform/eks.tf', 'terraform/network.tf', 'terraform/platform.tf',
    'terraform/observability.tf', 'terraform/consumer.tf',
    'deploy/templates/alb-ingress.yml.tpl',
    'deploy/templates/alertmanager.yml.tpl',
    'scripts/01-platform.ps1','scripts/02-configure-repo.ps1',
    'argocd/root-app.yml', 'msa/k8s/k8s-monitoring/prometheus-config.yml']
for rel in must_have:
    assert (ROOT/rel).is_file(), rel

# Secrets from study notes must not be accidentally included in the user-deliverable ZIP.
leaked=[]
for p in ROOT.rglob('*'):
    if not p.is_file():continue
    try: contents=p.read_text(encoding='utf-8-sig')
    except UnicodeDecodeError:continue
    if re.search(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b', contents): leaked.append(str(p))
assert not leaked, f'Plaintext AWS access-key patterns: {leaked}'

# Basic lexical HCL delimiter check; Terraform itself must validate in target environment.
for path in (ROOT/'terraform').glob('*.tf'):
    source=path.read_text();depth=[];quoted=False;escaped=False;comment=False
    for ch in source+'\n':
        if comment:
            if ch=='\n':comment=False
            continue
        if quoted:
            if escaped:escaped=False
            elif ch=='\\':escaped=True
            elif ch=='"':quoted=False
            continue
        if ch=='#':comment=True;continue
        if ch=='"':quoted=True;continue
        if ch in '{[(':depth.append(ch)
        if ch in '}])':
            match={'}':'{',']':'[',')':'('}[ch]
            assert depth and depth.pop()==match, f'Unbalanced HCL delimiters: {path}'
    assert not depth and not quoted, f'Unclosed HCL delimiters: {path}'

# Terraform HCL: a single-line block may contain only one direct argument.
# The earlier deliverable accidentally used multiple comma-separated arguments
# in blocks such as `principals { type = "Service", identifiers = [...] }`.
invalid_single_line_blocks=[]
for path in (ROOT/'terraform').glob('*.tf'):
    for i,line in enumerate(path.read_text().splitlines(),1):
        m=re.match(r'^\s*[A-Za-z_][\w-]*\s*\{\s*([^{}]*?)\s*\}\s*$',line)
        if m and len(re.findall(r'(?<![=!<>])=(?!=)',m.group(1)))>1:
            invalid_single_line_blocks.append(f'{path.name}:{i}: {line.strip()}')
assert not invalid_single_line_blocks, f'Invalid multi-argument single-line HCL blocks: {invalid_single_line_blocks}'

print('HCL SINGLE-LINE BLOCK CHECK PASS (NOT Terraform validate)')
print(f'STATIC PASS: {len(files)} YAML files, {count} YAML documents parsed')
print('STANDING CHECK PASS: 5 service manifests, isolated DB/SA config, Terraform/assets, no AWS key patterns')
print('BASIC HCL LEXICAL PASS: delimiters/quotes (NOT terraform validate)')
