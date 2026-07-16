# Atlantis Terraform Automation Runbook

## 목적

이 문서는 Bastion/Ops Server 기반 Atlantis를 사용하여 Terraform 변경 사항을 Pull Request 기준으로 검토하고 적용하는 운영 자동화 절차를 정리한다.

기존에는 운영자가 로컬 환경에서 직접 `terraform plan`과 `terraform apply`를 실행했다. 이 방식은 빠르게 작업할 수 있지만, 변경 이력 관리, 실행 위치 통제, PR 기반 검토, remote state 접근 권한 관리 측면에서 운영 표준으로 보기 어렵다.

이에 따라 Bastion/Ops Server에 Atlantis를 구성하여 GitHub PR 이벤트를 기준으로 Terraform plan/apply를 수행하도록 개선했다.

## 전체 흐름

```text
GitHub Pull Request
→ GitHub Webhook
→ Bastion/Ops Server Atlantis
→ Terraform init
→ S3 remote state 접근
→ tfvars 주입
→ Terraform plan
→ PR 댓글로 plan 결과 확인
→ Atlantis apply
```

## 구성 방식

| 항목 | 구성 |
|---|---|
| Atlantis 실행 위치 | Bastion/Ops Server |
| Atlantis 실행 방식 | Docker container |
| Webhook public endpoint | ngrok |
| Git host | GitHub |
| Terraform backend | S3 backend |
| Terraform 대상 경로 | `terraform/envs/dev` |
| 민감 변수 주입 | Bastion 내 `/opt/atlantis/tfvars/*.tfvars` |
| apply 조건 | 개인 프로젝트 기준 `mergeable` |

## Repository 구성 파일

### atlantis.yaml

위치:

```text
atlantis.yaml
```

역할:

```text
Atlantis가 이 repository에서 어떤 Terraform directory를 대상으로 plan/apply를 실행할지 정의한다.
```

현재 dev project는 다음 경로를 대상으로 한다.

```text
terraform/envs/dev
```

개인 프로젝트에서는 단일 계정으로 PR을 관리하기 때문에 `approved` 조건을 적용하기 어렵다. 따라서 현재는 `mergeable` 조건만 적용했다.

운영 환경에서는 다음과 같이 `approved`와 `mergeable`을 함께 사용하는 것이 적절하다.

```yaml
apply_requirements:
  - approved
  - mergeable
```

### atlantis/repos.yaml

위치:

```text
atlantis/repos.yaml
```

역할:

```text
Atlantis 서버 측 repository 정책 예시를 repository에 문서화한다.
```

주의할 점:

```text
atlantis/repos.yaml에는 token, webhook secret, tfvars 등 민감정보를 저장하지 않는다.
```

현재 Bastion에서 실제 Atlantis가 사용하는 서버 설정 파일은 다음 위치에 있다.

```text
/opt/atlantis/repos.yaml
```

## Bastion Atlantis 디렉터리 구조

```text
/opt/atlantis
├── atlantis.env
├── repos.yaml
├── data/
└── tfvars/
    ├── dev.tfvars
    ├── alerting.tfvars
    └── olivesafety-dev-bastion.pub
```

| 파일 | 역할 | Git 커밋 여부 |
|---|---|---|
| `/opt/atlantis/atlantis.env` | GitHub token, webhook secret 등 Atlantis 실행 환경 변수 | 커밋 금지 |
| `/opt/atlantis/repos.yaml` | Atlantis 서버 측 repository 정책 | 서버 로컬 관리 |
| `/opt/atlantis/data` | Atlantis 작업 디렉터리 | 커밋 금지 |
| `/opt/atlantis/tfvars/dev.tfvars` | Terraform 민감 변수 | 커밋 금지 |
| `/opt/atlantis/tfvars/alerting.tfvars` | ALB/TG CloudWatch alarm dimension 변수 | 커밋 금지 |

## 민감정보 관리

Terraform에 필요한 민감 변수는 Git에 올리지 않고 Bastion 내 tfvars로 관리한다.

```text
/opt/atlantis/tfvars/dev.tfvars
```

이 파일에는 다음과 같은 값이 포함될 수 있다.

```text
secret_values
bastion_allowed_ssh_cidr
bastion_public_key_path
node desired size 관련 변수
```

CloudWatch ALB Alarm dimension은 dev 환경 재생성 시 바뀔 수 있으므로 별도 파일로 관리한다.

```text
/opt/atlantis/tfvars/alerting.tfvars
```

예시:

```hcl
enable_alb_alarms       = true
alb_arn_suffix          = "app/k8s-.../..."
target_group_arn_suffix = "targetgroup/k8s-.../..."
```

주의할 점은 TargetGroup dimension에 반드시 `targetgroup/` prefix가 포함되어야 한다.

```hcl
target_group_arn_suffix = "targetgroup/k8s-.../..."
```

prefix가 빠지면 CloudWatch Alarm은 datapoint를 받지 못한다.

## Atlantis 실행 확인

Atlantis는 Bastion에서 Docker container로 실행한다.

```bash
docker ps
docker logs --tail=50 atlantis
curl -i http://127.0.0.1:4141
```

Mac에서 `127.0.0.1:4141`로 확인하면 Mac 자신의 localhost를 보는 것이므로 실패한다. Atlantis는 Bastion에서 실행 중이므로 Bastion 내부에서 확인해야 한다.

## ngrok Webhook URL 확인

Bastion에서 실행:

```bash
NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | \
  python3 -c 'import sys,json; data=json.load(sys.stdin); print(data["tunnels"][0]["public_url"])')

echo "$NGROK_URL"
echo "${NGROK_URL}/events"
```

GitHub Webhook Payload URL은 다음 형식이다.

```text
https://<ngrok-url>/events
```

## GitHub Webhook 설정

GitHub repository에서 다음 경로로 이동한다.

```text
Settings
→ Webhooks
→ Add webhook
```

설정값:

| 항목 | 값 |
|---|---|
| Payload URL | `https://<ngrok-url>/events` |
| Content type | `application/json` |
| Secret | `/opt/atlantis/atlantis.env`의 `GH_WEBHOOK_SECRET` |
| SSL verification | Enable |

선택 이벤트:

```text
Pull requests
Pushes
Issue comments
```

Webhook delivery가 200이면 GitHub → Atlantis 연결이 정상이다.

## Terraform plan 실행

PR 댓글에서 실행:

```text
atlantis plan -p dev
```

정상적으로 동작하면 Atlantis가 다음을 수행한다.

```text
terraform init
terraform plan
PR 댓글로 plan 결과 작성
```

## Terraform apply 실행

현재 개인 프로젝트에서는 apply 조건을 `mergeable`로 설정했다.

PR 댓글에서 실행:

```text
atlantis apply -p dev
```

운영 환경에서는 `approved + mergeable` 조건을 적용하고, 리뷰 승인 이후 apply하는 것이 적절하다.

## Bastion IAM Role 권한

Atlantis가 Terraform plan/apply를 수행하려면 Bastion IAM Role에 필요한 권한이 있어야 한다.

현재 Bastion Role:

```text
olivesafety-day2-ops-dev-bastion-role
```

### S3 Remote State 접근 권한

Terraform S3 backend에 접근하려면 다음 권한이 필요하다.

```text
s3:ListBucket
s3:GetBucketLocation
s3:GetObject
s3:PutObject
s3:DeleteObject
```

대상 bucket:

```text
olivesafety-day2-ops-191524136560-ap-northeast-2-tfstate
```

대상 prefix:

```text
envs/dev/*
```

### Terraform refresh 조회 권한

Terraform plan은 리소스 상태를 refresh하므로 여러 AWS 리소스 조회 권한이 필요하다.

실제 plan 과정에서 다음 권한 부족이 발생했다.

```text
iam:GetPolicy
iam:GetRole
iam:GetOpenIDConnectProvider
sqs:GetQueueAttributes
sns:GetTopicAttributes
secretsmanager:DescribeSecret
secretsmanager:GetSecretValue
ec2:Describe*
ecr:ListTagsForResource
```

개인 dev 환경에서는 plan 검증을 위해 Bastion Role에 ReadOnlyAccess를 추가했다.

운영 환경에서는 ReadOnlyAccess 대신 필요한 서비스와 리소스 ARN 범위로 최소 권한 정책을 구성하는 것이 적절하다.

### Secrets Manager 조회 권한

Terraform이 `aws_secretsmanager_secret_version`을 관리하는 경우 plan refresh 중에도 secret value를 읽을 수 있다.

따라서 dev 범위 Secret에 대해 다음 권한이 필요하다.

```text
secretsmanager:DescribeSecret
secretsmanager:GetSecretValue
secretsmanager:ListSecretVersionIds
```

대상 Secret:

```text
olivesafety/dev/api
olivesafety/dev/teams-webhook
```

운영 환경에서는 Secret value가 Terraform state에 포함되지 않도록 구조를 분리하는 것이 더 적절하다.

### CloudWatch Alarm 변경 권한

Atlantis apply로 CloudWatch Alarm dimension을 업데이트하려면 다음 권한이 필요하다.

```text
cloudwatch:DescribeAlarms
cloudwatch:PutMetricAlarm
cloudwatch:DeleteAlarms
cloudwatch:TagResource
cloudwatch:UntagResource
cloudwatch:ListTagsForResource
```

대상 alarm:

```text
arn:aws:cloudwatch:ap-northeast-2:191524136560:alarm:olivesafety-day2-ops-dev-*
```

## ALB/TG Dimension Drift 반영

dev 환경을 삭제 후 재생성하면 Kubernetes Ingress가 생성하는 ALB와 TargetGroup이 새로 생성된다.

그 결과 기존 CloudWatch Alarm은 과거 ALB/TG dimension을 바라볼 수 있다.

Atlantis plan에서 다음과 같은 변경이 발생하면 정상적인 drift 반영이다.

```text
CloudWatch Alarm dimensions update
LoadBalancer: old ALB suffix → new ALB suffix
TargetGroup: old TargetGroup suffix → new TargetGroup suffix
```

이 경우 `destroy`가 없고 dimension update만 있다면 apply 가능하다.

정상 예시:

```text
Plan: 0 to add, 2 to change, 0 to destroy
```

## ALB/TG Dimension 값 생성

Bastion에서 실행:

```bash
export AWS_REGION="ap-northeast-2"

ALB_DNS=$(kubectl get ingress olivesafety-api -n olivesafety \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

ALB_ARN=$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --query "LoadBalancers[?DNSName=='${ALB_DNS}'].LoadBalancerArn | [0]" \
  --output text)

TG_ARN=$(aws elbv2 describe-target-groups \
  --load-balancer-arn "$ALB_ARN" \
  --region "$AWS_REGION" \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

ALB_ARN_SUFFIX="${ALB_ARN#*loadbalancer/}"
TG_ARN_SUFFIX="targetgroup/${TG_ARN#*targetgroup/}"

cat <<'INNER' | sudo tee /opt/atlantis/tfvars/alerting.tfvars > /dev/null
enable_alb_alarms       = true
alb_arn_suffix          = "${ALB_ARN_SUFFIX}"
target_group_arn_suffix = "${TG_ARN_SUFFIX}"
INNER
```

주의: 위 예시는 문서용이다. 실제 실행 시에는 변수 치환이 필요하므로 `cat <<INNER` 형태로 실행한다.

권한 수정:

```bash
ATLANTIS_UID=$(docker run --rm --entrypoint sh ghcr.io/runatlantis/atlantis:latest -c 'id -u')
ATLANTIS_GID=$(docker run --rm --entrypoint sh ghcr.io/runatlantis/atlantis:latest -c 'id -g')

sudo chown "${ATLANTIS_UID}:${ATLANTIS_GID}" /opt/atlantis/tfvars/alerting.tfvars
sudo chmod 640 /opt/atlantis/tfvars/alerting.tfvars
```

확인:

```bash
docker exec atlantis sh -c 'test -r /opt/atlantis/tfvars/alerting.tfvars && echo "alerting.tfvars readable"'
```

## Troubleshooting

### 1. S3 backend 403 Forbidden

증상:

```text
Unable to access object envs/dev/terraform.tfstate in S3 bucket
StatusCode: 403
```

원인:

```text
Bastion Role에 Terraform S3 backend 접근 권한이 없음
```

조치:

```text
Bastion Role에 tfstate bucket/prefix에 대한 S3 접근 권한 추가
```

### 2. Unreadable module directory

증상:

```text
Unreadable module directory
../../modules/secrets-manager: no such file or directory
../../modules/external-secrets-irsa: no such file or directory
```

원인:

```text
로컬에는 module이 있지만 GitHub PR branch에 module directory가 커밋되지 않음
```

조치:

```bash
git add -f terraform/modules/secrets-manager terraform/modules/external-secrets-irsa
git commit -m "add missing Terraform modules for Atlantis plan"
git push origin "$(git branch --show-current)"
```

### 3. No value for required variable

증상:

```text
No value for required variable
secret_values
bastion_allowed_ssh_cidr
```

원인:

```text
로컬 terraform.tfvars는 Git에 없고, Atlantis 실행 환경에도 var-file이 주입되지 않음
```

조치:

```text
Bastion의 /opt/atlantis/tfvars/dev.tfvars를 만들고 atlantis.yaml workflow에서 -var-file로 주입
```

### 4. tfvars permission denied

증상:

```text
Failed to read variables file
open /opt/atlantis/tfvars/dev.tfvars: permission denied
```

원인:

```text
tfvars 파일 소유자와 Atlantis container 내부 사용자 권한 불일치
```

조치:

```bash
ATLANTIS_UID=$(docker run --rm --entrypoint sh ghcr.io/runatlantis/atlantis:latest -c 'id -u')
ATLANTIS_GID=$(docker run --rm --entrypoint sh ghcr.io/runatlantis/atlantis:latest -c 'id -g')

sudo chown -R "${ATLANTIS_UID}:${ATLANTIS_GID}" /opt/atlantis/tfvars
sudo chmod 750 /opt/atlantis/tfvars
sudo chmod 640 /opt/atlantis/tfvars/dev.tfvars
```

### 5. YAML tab indentation error

증상:

```text
go-yaml load error
found a tab character that violates indentation
```

원인:

```text
atlantis.yaml에 tab 문자가 포함됨
```

조치:

```bash
python3 - <<'PY'
from pathlib import Path

p = Path("atlantis.yaml")
for i, line in enumerate(p.read_text().splitlines(), 1):
    if "\t" in line:
        print(f"Line {i}: {line!r}")
PY
```

YAML은 tab 대신 space를 사용해야 한다.

### 6. CloudWatch Alarm destroy가 plan에 표시됨

증상:

```text
aws_cloudwatch_metric_alarm.alb_target_5xx[0] will be destroyed
because index [0] is out of range for count
```

원인:

```text
enable_alb_alarms=false 이거나 ALB/TG suffix 값이 비어 있음
alerting.tfvars가 Atlantis plan에 적용되지 않음
```

조치:

```text
/opt/atlantis/tfvars/alerting.tfvars 생성
atlantis.yaml에 -var-file=/opt/atlantis/tfvars/alerting.tfvars 추가
```

### 7. EKS NodeGroup desired_size drift

증상:

```text
desired_size = 2 -> 1
```

원인:

```text
AWS CLI로 nodegroup desired size를 수동 증설했지만 Terraform 변수는 1로 남아 있음
```

조치:

```text
현재 운영에 필요한 desired size를 Terraform 변수 또는 tfvars에도 반영한다.
```

## 검증 결과

이번 구성에서 다음 흐름을 검증했다.

```text
GitHub PR 생성
→ Atlantis webhook 수신
→ Terraform init 성공
→ S3 backend 접근 성공
→ Bastion tfvars 주입 성공
→ Terraform plan 성공
→ CloudWatch Alarm dimension drift 확인
→ Atlantis apply 성공
→ CloudWatch Alarm dimension 업데이트
```

최종적으로 로컬 수동 Terraform 실행 방식에서 Bastion 기반 PR 자동화 방식으로 Terraform 운영 흐름을 개선했다.
