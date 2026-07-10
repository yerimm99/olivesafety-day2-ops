# ArgoCD GitOps Deployment Runbook

## 1. 목적

이 문서는 `olivesafety-day2-ops` 프로젝트의 dev 환경에서 ArgoCD 기반 GitOps 배포 구조를 구성하고, 배포 상태를 점검하는 절차를 정리한다.

구성 목표는 다음과 같다.

```text
GitHub Actions
→ Docker image build
→ ECR push
→ k8s/overlays/dev/kustomization.yaml image tag update
→ Git commit
→ ArgoCD sync
→ EKS deployment
```

---

## 2. 구성 요소

| 구성 요소 | 역할 |
|---|---|
| GitHub Actions | 애플리케이션 이미지를 빌드하고 ECR에 push |
| Amazon ECR | commit SHA 기반 Docker image 저장소 |
| Kustomize | dev 환경 Kubernetes manifest 관리 |
| ArgoCD | Git repository의 manifest를 기준으로 EKS에 자동 배포 |
| EKS | 애플리케이션 실행 환경 |
| External Secrets Operator | AWS Secrets Manager 값을 Kubernetes Secret으로 동기화 |
| AWS Load Balancer Controller | Kubernetes Ingress를 AWS ALB로 생성 |

---

## 3. ArgoCD Application

ArgoCD Application은 다음 경로의 manifest를 기준으로 dev 환경을 동기화한다.

```text
k8s/overlays/dev
```

Application manifest 경로:

```text
argocd/apps/olivesafety-dev.yaml
```

주요 설정:

```yaml
spec:
  source:
    repoURL: https://github.com/yerimm99/olivesafety-day2-ops.git
    targetRevision: main
    path: k8s/overlays/dev

  destination:
    server: https://kubernetes.default.svc
    namespace: olivesafety

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 설정 의미

| 항목 | 설명 |
|---|---|
| `repoURL` | ArgoCD가 감시할 GitHub repository |
| `targetRevision` | 추적할 branch |
| `path` | Kubernetes manifest 경로 |
| `destination.namespace` | 배포 대상 namespace |
| `prune` | Git에서 삭제된 리소스를 클러스터에서도 삭제 |
| `selfHeal` | 클러스터에서 수동 변경된 값을 Git 기준으로 복구 |
| `CreateNamespace=true` | 대상 namespace가 없으면 자동 생성 |

---

## 4. 상태 확인 명령어

### Application 상태 확인

```bash
kubectl get application olivesafety-dev -n argocd
```

정상 상태:

```text
SYNC STATUS   HEALTH STATUS
Synced        Healthy
```

### 상세 상태 확인

```bash
kubectl get application olivesafety-dev -n argocd \
  -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{"\n"}'
```

정상 출력:

```text
Synced / Healthy
```

### 리소스별 Sync 상태 확인

```bash
kubectl get application olivesafety-dev -n argocd \
  -o jsonpath='{range .status.resources[*]}{.kind}{" / "}{.name}{" / "}{.status}{" / "}{.health.status}{"\n"}{end}'
```

### Application 조건 확인

```bash
kubectl get application olivesafety-dev -n argocd \
  -o jsonpath='{range .status.conditions[*]}{.type}{" | "}{.message}{"\n"}{end}'
```

---

## 5. 애플리케이션 상태 확인

```bash
kubectl get deploy,rs,pods,svc,ingress,hpa -n olivesafety
```

정상 기준:

```text
deployment.apps/olivesafety-api   1/1
pod/olivesafety-api-xxxxx         1/1 Running
ingress                           ADDRESS 할당 완료
hpa                               MINPODS 1
```

ALB 주소 확인:

```bash
kubectl get ingress olivesafety-api -n olivesafety \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

Health check:

```bash
APP_ALB_DNS=$(kubectl get ingress olivesafety-api -n olivesafety -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://${APP_ALB_DNS}/actuator/health
```

정상 응답:

```json
{"status":"UP","groups":["liveness","readiness"]}
```

---

## 6. 수동 Refresh

ArgoCD가 Git 변경을 바로 반영하지 않는 경우 hard refresh를 수행한다.

```bash
kubectl annotate application olivesafety-dev \
  -n argocd \
  argocd.argoproj.io/refresh=hard \
  --overwrite
```

---

## 7. 장애 사례 1: Sync Status가 Unknown

### 현상

```text
Unknown / Healthy
```

Application 조건 확인 시 다음 오류가 발생했다.

```text
ComparisonError | Failed to load target state:
kustomize build ... failed:
cluster-secret-store.yaml: no such file or directory
```

### 원인

`k8s/overlays/dev/kustomization.yaml`에서는 다음 파일을 참조하고 있었다.

```yaml
resources:
  - cluster-secret-store.yaml
  - external-secret.yaml
```

하지만 해당 파일들이 `.gitignore` 규칙에 의해 Git에 포함되지 않아, ArgoCD가 GitHub repository에서 manifest를 읽을 수 없었다.

ArgoCD는 로컬 파일이 아니라 GitHub 원격 repository에 push된 파일만 기준으로 동작한다.

### 조치

Git 추적 여부 확인:

```bash
git ls-files k8s/overlays/dev
```

무시된 파일 강제 추가:

```bash
git add -f k8s/overlays/dev/cluster-secret-store.yaml \
           k8s/overlays/dev/external-secret.yaml
```

ArgoCD Application manifest도 Git에 추가:

```bash
git add argocd/apps/olivesafety-dev.yaml
```

커밋 및 push:

```bash
git commit -m "add ArgoCD dev application and external secret manifests"
git push origin main
```

ArgoCD refresh:

```bash
kubectl annotate application olivesafety-dev \
  -n argocd \
  argocd.argoproj.io/refresh=hard \
  --overwrite
```

---

## 8. 장애 사례 2: Synced이지만 Progressing 상태

### 현상

```text
Synced / Progressing
```

애플리케이션 리소스 상태 확인 시 다음과 같이 Pending Pod가 존재했다.

```text
deployment.apps/olivesafety-api   1/2
pod/olivesafety-api-xxxxx         Pending
hpa MINPODS 2
```

### 원인

dev 환경은 비용 절감을 위해 단일 노드 기반으로 구성되어 있다.

여기에 다음 구성 요소가 함께 실행된다.

```text
olivesafety-api
ArgoCD
AWS Load Balancer Controller
External Secrets Operator
CoreDNS
```

기본 RollingUpdate 전략에서는 `replicas: 1`이어도 배포 시 기존 Pod를 유지한 상태에서 새 Pod를 먼저 생성한다.

따라서 순간적으로 Pod 2개가 필요해지고, 단일 노드 리소스가 부족하면 새 Pod가 Pending 상태가 된다.

### 조치

dev overlay에서 replicas와 HPA 값을 dev 환경에 맞게 조정했다.

`k8s/overlays/dev/deployment-replicas-patch.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: olivesafety-api
  namespace: olivesafety
spec:
  replicas: 1
  strategy:
    type: Recreate
```

`k8s/overlays/dev/hpa-dev-patch.yaml`

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: olivesafety-api
  namespace: olivesafety
spec:
  minReplicas: 1
  maxReplicas: 2
```

`Recreate` 전략은 기존 Pod를 먼저 종료한 뒤 새 Pod를 생성한다.

dev 환경에서는 잠깐의 서비스 중단을 허용하는 대신, 제한된 노드 리소스에서도 안정적으로 배포를 완료할 수 있다.

운영 환경에서는 RollingUpdate와 Multi-AZ Node Group을 사용하는 것이 적절하다.

---

## 9. 최종 정상 상태

Application 상태:

```bash
kubectl get application olivesafety-dev -n argocd \
  -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{"\n"}'
```

정상 출력:

```text
Synced / Healthy
```

애플리케이션 상태:

```bash
kubectl get deploy,rs,pods,hpa -n olivesafety
```

정상 기준:

```text
deployment.apps/olivesafety-api   1/1
pod/olivesafety-api-xxxxx         1/1 Running
hpa MINPODS 1
```

---

## 10. 정리

이번 구성으로 dev 환경의 배포 방식은 다음과 같이 개선되었다.

```text
Before:
로컬에서 이미지 빌드
로컬에서 manifest 수정
kubectl apply -k 수동 배포

After:
GitHub Actions에서 이미지 빌드
ECR에 commit SHA 기반 이미지 push
manifest image tag 자동 갱신
ArgoCD가 Git 기준으로 EKS 자동 배포
```

이를 통해 배포 이력과 클러스터 상태를 Git 기준으로 추적할 수 있게 되었고, 수동 배포 과정에서 발생할 수 있는 환경 차이와 적용 누락을 줄였다.
