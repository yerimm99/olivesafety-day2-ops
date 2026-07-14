# Bastion / Ops Server Runbook

## 1. 목적

이 문서는 `olivesafety-day2-ops` 프로젝트의 dev 환경에서 Bastion/Ops Server를 구성하고, 운영 도구 설치 및 점검 스크립트 배포를 자동화한 내용을 정리한다.

Bastion/Ops Server의 목적은 다음과 같다.

```text
운영자가 접속하는 표준 관리 서버 구성
EKS 운영 도구 설치 자동화
kubectl / helm / awscli / argocd cli 실행 환경 표준화
ops-check 스크립트 배포 및 실행
운영 점검 절차를 로컬 Mac이 아닌 Bastion 기준으로 수행
```

---

## 2. 전체 구성 흐름

```text
Terraform
→ Bastion EC2 생성
→ Bastion IAM Role 생성
→ EKS Access Entry 등록
→ SSH 접속 확인
→ Ansible inventory 생성
→ Ansible playbook 실행
→ 운영 도구 설치
→ ops-check 스크립트 배포
→ Bastion에서 dev health check 실행
```

---

## 3. Terraform 구성

Bastion/Ops Server는 Terraform으로 생성한다.

관련 파일:

```text
terraform/modules/bastion/
terraform/envs/dev/bastion.tf
terraform/envs/dev/bastion-eks-access.tf
terraform/envs/dev/bastion-ops-permissions.tf
```

### 3.1 Bastion module

`terraform/modules/bastion`은 Bastion EC2를 생성하는 공통 모듈이다.

생성 리소스:

```text
EC2 Instance
Security Group
SSH Key Pair
IAM Role
IAM Instance Profile
SSM Managed Instance Core Policy
CloudWatch Agent Server Policy
```

Bastion은 dev 환경 비용을 고려하여 다음 기준으로 구성한다.

```text
Instance Type: t3.micro
Subnet: Public Subnet
Public IP: Enabled
SSH Access: allowed_ssh_cidr 기준 제한
OS: Amazon Linux 2023
```

---

## 4. SSH 접근 제한

Bastion의 SSH 접근은 전체 공개가 아니라, 현재 작업자의 공인 IP만 허용한다.

`terraform/envs/dev/terraform.tfvars` 예시:

```hcl
bastion_allowed_ssh_cidr = "x.x.x.x/32"
bastion_public_key_path  = "~/.ssh/olivesafety-dev-bastion.pub"
```

현재 공인 IP 확인:

```bash
curl -s https://checkip.amazonaws.com
```

SSH 접속:

```bash
cd terraform/envs/dev
BASTION_IP=$(terraform output -raw bastion_public_ip)

ssh -i ~/.ssh/olivesafety-dev-bastion ec2-user@${BASTION_IP}
```

---

## 5. Bastion EKS 접근 권한

Bastion에서 `kubectl`로 EKS를 조회하려면 두 가지 권한이 필요하다.

```text
1. AWS IAM 권한
   - eks:DescribeCluster

2. EKS Access Entry
   - Bastion IAM Role을 EKS 클러스터 권한에 매핑
```

관련 파일:

```text
terraform/envs/dev/bastion-eks-access.tf
```

구성 내용:

```text
aws_iam_role_policy.bastion_eks_describe
aws_eks_access_entry.bastion
aws_eks_access_policy_association.bastion_cluster_admin
```

Bastion에서 kubeconfig 생성:

```bash
aws eks update-kubeconfig \
  --name olivesafety-day2-ops-dev-eks \
  --region ap-northeast-2
```

EKS 접근 확인:

```bash
kubectl get nodes
```

---

## 6. Bastion 운영 점검용 AWS Read 권한

Bastion에서 운영 점검 스크립트를 실행하려면 EKS 외에도 AWS 리소스 조회 권한이 필요하다.

관련 파일:

```text
terraform/envs/dev/bastion-ops-permissions.tf
```

주요 조회 권한:

```text
ECR image 조회
ALB / Target Group 조회
CloudWatch Alarm / Metric 조회
EC2 / Subnet / Security Group 조회
RDS 조회
ElastiCache 조회
Route53 조회
```

이 권한은 운영 점검 목적의 read 권한이며, 리소스 변경 권한은 포함하지 않는다.

---

## 7. Ansible 구성

Bastion 운영 도구 설치는 Ansible로 자동화한다.

관련 파일:

```text
ansible/ansible.cfg
ansible/render-inventory.sh
ansible/inventory/dev.ini
ansible/playbooks/setup-ops-server.yml
ansible/playbooks/deploy-ops-check.yml
ansible/roles/ops-tools/
```

### 7.1 ansible.cfg

`ansible/ansible.cfg`는 Ansible 실행 기본 설정 파일이다.

역할:

```text
inventory 기본 경로 지정
roles 경로 지정
SSH host key checking 비활성화
출력 포맷 설정
SSH pipelining 활성화
```

### 7.2 render-inventory.sh

`ansible/render-inventory.sh`는 Terraform output에서 Bastion public IP를 읽어 Ansible inventory를 생성한다.

실행:

```bash
./ansible/render-inventory.sh
```

생성되는 파일:

```text
ansible/inventory/dev.ini
```

`dev.ini`는 Bastion public IP가 들어가는 생성 파일이므로 Git에 올리지 않는다.

---

## 8. 설치되는 운영 도구

Ansible role `ops-tools`는 Bastion에 다음 도구를 설치한다.

```text
awscli
kubectl
helm
argocd cli
jq
git
curl-minimal
unzip
python3
CloudWatch Agent
```

실행:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg \
ansible-playbook -i ansible/inventory/dev.ini ansible/playbooks/setup-ops-server.yml
```

설치 확인:

```bash
aws --version
kubectl version --client=true
helm version --short
argocd version --client
```

---

## 9. ops-check 스크립트 배포

운영 점검 스크립트는 Ansible로 Bastion에 배포한다.

관련 파일:

```text
ops-check/dev-health-check.sh
ansible/playbooks/deploy-ops-check.yml
```

배포 명령:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg \
ansible-playbook -i ansible/inventory/dev.ini ansible/playbooks/deploy-ops-check.yml
```

Bastion 내 배포 위치:

```text
/opt/olivesafety/ops-check/dev-health-check.sh
```

---

## 10. Bastion에서 dev health check 실행

Bastion 기준으로 dev 환경 상태를 점검한다.

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg \
ansible ops -i ansible/inventory/dev.ini \
-m shell -a "/opt/olivesafety/ops-check/dev-health-check.sh"
```

점검 항목:

```text
Kubernetes context 확인
EKS node 접근 확인
ArgoCD Synced / Healthy 확인
Deployment rollout 확인
Pod Running 확인
ExternalSecret Ready 확인
Kubernetes Secret 존재 확인
Ingress ALB DNS 확인
/actuator/health 응답 확인
ECR image tag 존재 확인
```

정상 출력:

```text
[PASS] Dev environment health check completed successfully.
```

---

## 11. Troubleshooting

### 11.1 Ansible callback 오류

현상:

```text
community.general.yaml callback plugin has been removed
```

원인:

```text
최신 Ansible에서 community.general.yaml callback이 제거됨
```

조치:

`ansible/ansible.cfg`에서 다음 설정을 사용한다.

```ini
stdout_callback = default
callback_result_format = yaml
```

---

### 11.2 curl 패키지 충돌

현상:

```text
Depsolve Error occurred:
problem with installed package curl-minimal
```

원인:

```text
Amazon Linux 2023에는 curl-minimal이 기본 설치되어 있는데, curl 패키지를 추가 설치하려고 하면서 충돌 발생
```

조치:

Ansible base package 목록에서 `curl` 대신 `curl-minimal`을 사용한다.

```yaml
- curl-minimal
```

---

### 11.3 Bastion에서 kubectl 권한 오류

현상:

```text
You must be logged in to the server
Unauthorized
```

원인 후보:

```text
Bastion IAM Role에 EKS Access Entry가 없음
aws eks update-kubeconfig 미실행
Bastion IAM Role에 eks:DescribeCluster 권한 없음
```

확인:

```bash
aws sts get-caller-identity
kubectl config current-context
kubectl get nodes
```

조치:

```text
terraform/envs/dev/bastion-eks-access.tf 적용 여부 확인
Bastion에서 aws eks update-kubeconfig 재실행
```

---

### 11.4 SSH 접속 Timeout

원인 후보:

```text
현재 공인 IP와 bastion_allowed_ssh_cidr 불일치
Bastion Security Group 22번 미허용
Bastion public IP 변경
```

확인:

```bash
curl -s https://checkip.amazonaws.com
terraform output -raw bastion_public_ip
```

조치:

```text
terraform.tfvars의 bastion_allowed_ssh_cidr 수정
terraform apply 재실행
```

---

## 12. 정리

이번 Phase 5를 통해 운영 점검 기준이 로컬 개발자 PC에서 Bastion/Ops Server 중심으로 이동했다.

개선 전:

```text
로컬 Mac에서 kubectl/awscli 실행
운영 도구 설치 상태가 개인 환경에 의존
점검 스크립트도 로컬 기준 실행
```

개선 후:

```text
Terraform으로 Bastion/Ops Server 생성
Ansible로 운영 도구 설치 자동화
Bastion IAM Role로 EKS/AWS 조회
ops-check 스크립트를 Bastion에 배포
Bastion 기준으로 dev 환경 health check 실행
```

이를 통해 운영 도구 서버의 초기 설정과 점검 절차를 코드로 재현할 수 있게 되었다.
