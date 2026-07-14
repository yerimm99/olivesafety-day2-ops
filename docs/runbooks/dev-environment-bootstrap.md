# Dev Environment Bootstrap Runbook

## 1. 목적

이 문서는 `olivesafety-day2-ops` 프로젝트의 dev 환경을 자동으로 생성하고 삭제하는 절차를 정리한다.

dev 환경은 비용을 최소화하면서도 다음 구성을 재현할 수 있도록 설계했다.

```text
Terraform
→ AWS Infrastructure Provisioning
→ EKS kubeconfig 연결
→ AWS Load Balancer Controller 설치
→ External Secrets Operator 설치
→ ArgoCD 설치
→ ArgoCD Application 적용
→ GitOps 기반 애플리케이션 배포
```

---

## 2. 주요 스크립트

| 스크립트 | 역할 |
|---|---|
| `scripts/dev-up.sh` | dev 환경 생성 및 GitOps 배포 자동화 |
| `scripts/dev-down.sh` | dev 환경 리소스 삭제 |
| `terraform/envs/dev` | dev 환경 AWS 인프라 정의 |
| `k8s/overlays/dev` | dev 환경 Kubernetes manifest |
| `argocd/apps/olivesafety-dev.yaml` | ArgoCD Application 정의 |

---

## 3. dev-up.sh 실행 흐름

`dev-up.sh`는 다음 순서로 dev 환경을 구성한다.

```text
1. Terraform apply
2. EKS kubeconfig 업데이트
3. Terraform output 조회
4. AWS Load Balancer Controller 설치
5. External Secrets Operator 설치
6. ECR bootstrap image 확인 및 필요 시 build/push
7. ArgoCD 설치
8. ArgoCD Application 적용
9. ALB endpoint 및 health check 확인
```

---

## 4. 사전 조건

로컬 환경에 다음 도구가 설치되어 있어야 한다.

```text
awscli
kubectl
helm
terraform
docker
git
```

AWS CLI profile은 기본적으로 다음 값을 사용한다.

```bash
AWS_PROFILE=yerim-admin
AWS_REGION=ap-northeast-2
```

다른 profile을 사용할 경우 실행 시 환경변수로 지정한다.

```bash
AWS_PROFILE=<profile-name> ./scripts/dev-up.sh
```

---

## 5. dev 환경 생성

프로젝트 루트에서 실행한다.

```bash
./scripts/dev-up.sh
```

정상 완료 시 마지막에 다음과 같은 결과가 출력된다.

```text
ArgoCD status: Synced / Healthy
ALB DNS: ...
Health check:
{"status":"UP","groups":["liveness","readiness"]}
```

---

## 6. dev-up.sh 주요 동작 설명

### 6.1 Terraform apply

```text
terraform/envs/dev
```

경로의 Terraform 코드를 기준으로 dev 환경 인프라를 생성한다.

주요 생성 리소스는 다음과 같다.

```text
VPC
Public Subnet
Private Subnet
EKS
ECR
RDS MySQL
ElastiCache Redis
Secrets Manager
SQS
SNS
IRSA IAM Role
GitHub Actions OIDC Role
```

---

### 6.2 EKS kubeconfig 업데이트

Terraform으로 생성된 EKS 클러스터에 `kubectl`로 접근할 수 있도록 kubeconfig를 갱신한다.

```bash
aws eks update-kubeconfig \
  --name olivesafety-day2-ops-dev-eks \
  --region ap-northeast-2 \
  --profile yerim-admin
```

---

### 6.3 AWS Load Balancer Controller 설치

Kubernetes Ingress 리소스를 AWS ALB로 생성하기 위해 AWS Load Balancer Controller를 설치한다.

이 프로젝트에서는 애플리케이션 외부 접근을 위해 다음 구조를 사용한다.

```text
Kubernetes Ingress
→ AWS Load Balancer Controller
→ AWS ALB
→ olivesafety-api Service
→ olivesafety-api Pod
```

---

### 6.4 External Secrets Operator 설치

애플리케이션 Secret 값을 Kubernetes manifest에 직접 저장하지 않기 위해 External Secrets Operator를 사용한다.

구성 흐름은 다음과 같다.

```text
AWS Secrets Manager
→ External Secrets Operator
→ Kubernetes Secret
→ Application Pod env
```

이를 통해 DB 접속 정보, Redis 정보, JWT Secret, SQS/SNS 정보 등을 Git에 직접 저장하지 않고 사용할 수 있다.

---

### 6.5 Bootstrap Image Build

`dev-down.sh` 실행 후 ECR repository가 비어 있을 수 있다.

ArgoCD는 Git에 기록된 image tag를 기준으로 애플리케이션을 배포하기 때문에, 해당 image tag가 ECR에 없으면 Pod가 `ImagePullBackOff` 상태가 된다.

이를 방지하기 위해 `dev-up.sh`는 `k8s/overlays/dev/kustomization.yaml`에 기록된 image tag가 ECR에 존재하는지 확인한다.

이미지가 없으면 한 번만 build/push를 수행한다.

```text
ECR에 image tag 존재
→ build 생략

ECR에 image tag 없음
→ Docker build
→ ECR push
```

기본값:

```bash
BUILD_BOOTSTRAP_IMAGE=true
```

bootstrap image build를 건너뛰고 싶을 경우:

```bash
BUILD_BOOTSTRAP_IMAGE=false ./scripts/dev-up.sh
```

---

### 6.6 ArgoCD 설치 및 Application 적용

ArgoCD를 설치한 뒤 다음 Application을 적용한다.

```text
argocd/apps/olivesafety-dev.yaml
```

Application은 다음 경로의 manifest를 기준으로 dev 환경을 동기화한다.

```text
k8s/overlays/dev
```

정상 상태:

```text
Synced / Healthy
```

---

## 7. dev 환경 상태 확인

### ArgoCD 상태 확인

```bash
kubectl get application olivesafety-dev -n argocd
```

정상 상태:

```text
NAME              SYNC STATUS   HEALTH STATUS
olivesafety-dev   Synced        Healthy
```

### 애플리케이션 상태 확인

```bash
kubectl get deploy,pods,svc,ingress,hpa -n olivesafety
```

정상 기준:

```text
deployment.apps/olivesafety-api   1/1
pod/olivesafety-api-xxxxx         1/1 Running
ingress                           ADDRESS 할당 완료
hpa                               MINPODS 1
```

### Health check

```bash
APP_ALB_DNS=$(kubectl get ingress olivesafety-api -n olivesafety -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://${APP_ALB_DNS}/actuator/health
```

정상 응답:

```json
{"status":"UP","groups":["liveness","readiness"]}
```

---

## 8. dev 환경 삭제

비용 절감을 위해 테스트가 끝난 후 dev 환경을 삭제한다.

```bash
./scripts/dev-down.sh
```

`dev-down.sh`는 다음 순서로 리소스를 정리한다.

```text
1. ArgoCD Application 삭제
2. Kubernetes 애플리케이션 리소스 삭제
3. ECR image 삭제
4. Terraform destroy
5. Secrets Manager scheduled deletion 상태 강제 삭제
```

---

## 9. dev-down.sh에서 ArgoCD Application을 먼저 삭제하는 이유

ArgoCD Application이 남아 있으면 `selfHeal` 정책에 의해 삭제한 Kubernetes 리소스가 다시 생성될 수 있다.

따라서 `dev-down.sh`에서는 먼저 ArgoCD Application을 삭제한다.

```text
ArgoCD Application 삭제
→ self-healing 중단
→ Kubernetes 리소스 삭제
→ AWS 리소스 삭제
```

---

## 10. 주의 사항

### 10.1 dev-down.sh 실행 후 GitHub Actions 실패 가능성

`dev-down.sh`는 ECR repository와 GitHub Actions OIDC Role도 Terraform destroy 대상으로 삭제한다.

따라서 dev 환경이 내려간 상태에서 GitHub Actions가 실행되면 ECR push 또는 AWS 인증 단계에서 실패할 수 있다.

이 프로젝트에서는 비용 절감을 위해 dev 리소스를 필요할 때만 생성하는 방식을 사용한다.

```text
비용 절감 목적의 개인 dev 환경
→ dev-down 시 CI/CD 관련 AWS 리소스도 삭제

운영 환경
→ ECR, GitHub Actions Role, ArgoCD 등은 별도 lifecycle로 관리하는 것이 적절
```

---

### 10.2 ALB 삭제 지연

Ingress 삭제 후 AWS ALB가 완전히 삭제되기까지 시간이 걸릴 수 있다.

Terraform destroy 중 보안 그룹 또는 subnet dependency 오류가 발생하면 몇 분 기다린 뒤 `dev-down.sh`를 다시 실행한다.

---

### 10.3 dev 환경의 Deployment 전략

dev 환경은 비용 절감을 위해 단일 노드 기반으로 구성한다.

ArgoCD, External Secrets Operator, AWS Load Balancer Controller, 애플리케이션 Pod가 함께 실행되기 때문에 리소스가 제한적이다.

따라서 dev overlay에서는 다음 값을 사용한다.

```text
replicas: 1
HPA minReplicas: 1
HPA maxReplicas: 2
Deployment strategy: Recreate
```

운영 환경에서는 Multi-AZ Node Group과 RollingUpdate 전략을 사용하는 것이 적절하다.

---

## 11. Troubleshooting

### 11.1 ArgoCD 상태가 Unknown인 경우

Application 조건 확인:

```bash
kubectl get application olivesafety-dev -n argocd \
  -o jsonpath='{range .status.conditions[*]}{.type}{" | "}{.message}{"\n"}{end}'
```

주요 원인:

```text
GitHub repository 접근 실패
kustomize build 실패
Git에 필요한 manifest 파일 누락
```

---

### 11.2 Synced이지만 Progressing인 경우

```bash
kubectl get deploy,rs,pods,hpa -n olivesafety
```

주요 원인:

```text
Pod Pending
Deployment rollout 미완료
Ingress ADDRESS 미할당
ExternalSecret 동기화 지연
```

---

### 11.3 ImagePullBackOff 발생 시

ECR에 manifest가 참조하는 image tag가 존재하는지 확인한다.

```bash
IMAGE_TAG=$(grep -A3 "name: olivesafety-api" k8s/overlays/dev/kustomization.yaml | grep newTag | awk '{print $2}')

aws ecr describe-images \
  --repository-name olivesafety-day2-ops-dev/olivesafety-api \
  --image-ids imageTag=${IMAGE_TAG} \
  --region ap-northeast-2 \
  --profile yerim-admin
```

이미지가 없다면 bootstrap image build를 포함하여 다시 실행한다.

```bash
BUILD_BOOTSTRAP_IMAGE=true ./scripts/dev-up.sh
```

---

## 12. 정리

이 자동화로 dev 환경은 다음 수준까지 재현 가능해졌다.

```text
AWS 인프라 생성
EKS 연결
운영 컨트롤러 설치
Secret 동기화 구성
ArgoCD 설치
GitOps Application 적용
애플리케이션 배포
ALB health check 검증
```

이를 통해 수동 명령어 중심의 배포 방식에서 벗어나, 프로젝트를 새 환경에서도 반복적으로 구성하고 검증할 수 있는 구조로 개선했다.
