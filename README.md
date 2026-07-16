# OliveSafety Day-2 Ops Automation

## 프로젝트 한 줄 소개

AWS EKS 기반 서비스 인프라를 대상으로 배포 이후 운영 단계에서 필요한 보안, GitOps 배포, 모니터링, 장애 알림, 운영 점검, Terraform 변경 관리를 자동화한 Day-2 Operations 고도화 프로젝트입니다.

## 프로젝트 목적

기존 프로젝트는 EKS 기반 애플리케이션 배포와 대규모 트래픽 대응 아키텍처 구성에 초점을 두었습니다.

이번 고도화에서는 단순 인프라 구축에서 나아가, 실제 운영 환경에서 반복적으로 필요한 Day-2 운영 요소를 보완하는 데 집중했습니다.

주요 목표는 다음과 같습니다.

- Secret과 권한을 안전하게 관리하는 구조로 개선
- GitOps 기반 배포 흐름 구성
- 운영자가 확인해야 하는 상태 점검 자동화
- 장애 발생 시 Teams로 알림 전달
- Terraform 변경을 로컬이 아닌 PR 기반으로 검토 및 적용
- 비용 절감을 위해 dev 환경을 필요할 때만 올리고 내리는 운영 방식 적용

## 기존 프로젝트 대비 고도화 포인트

| 구분 | 기존 구성 | 고도화 이후 |
|---|---|---|
| Secret 관리 | Kubernetes manifest 또는 환경 변수 중심 | AWS Secrets Manager + External Secrets |
| AWS 권한 | Access Key 기반 접근 가능성 존재 | IRSA 기반 Pod 권한 분리 |
| 배포 방식 | 수동 배포 또는 Jenkins 중심 | GitHub Actions + ArgoCD GitOps |
| Terraform 실행 | 로컬에서 plan/apply 수행 | Atlantis 기반 PR plan/apply |
| 운영 점검 | 수동 kubectl/AWS CLI 확인 | Bastion 기반 health report script |
| 장애 알림 | 콘솔 또는 수동 확인 | CloudWatch Alarm → SNS → Lambda → Teams |
| 모니터링 | Prometheus + Grafana 기반 모니터링 구조 | 애플리케이션 메트릭, PrometheusRule, Alertmanager 알림 규칙 보완 및 Runbook 문서화 |
| 로그 수집 | Loki + Promtail 기반 로그 수집 구조 | Loki + Alloy 기반 구조로 재정리하고 로그 수집 운영 문서 보완 |
| 비용 관리 | 리소스 상시 유지 가능성 | dev-up/dev-down 기반 필요 시 구동 |

## 아키텍처 흐름

### 1. 애플리케이션 배포 흐름

```text
GitHub Push
→ GitHub Actions
→ Docker Image Build
→ Amazon ECR Push
→ Kubernetes Manifest Image Tag Update
→ ArgoCD Sync
→ Amazon EKS Deployment Update
```

### 2. Secret 관리 흐름

```text
AWS Secrets Manager
→ External Secrets Operator
→ Kubernetes Secret
→ EKS Pod Environment Variable
```

### 3. 장애 알림 흐름

```text
ALB / TargetGroup Metric
→ CloudWatch Alarm
→ SNS Topic
→ Lambda Forwarder
→ Microsoft Teams Webhook
→ Teams Channel Notification
```

### 4. Terraform 변경 관리 흐름

```text
GitHub Pull Request
→ GitHub Webhook
→ Bastion Atlantis
→ Terraform Init
→ Terraform Plan
→ PR Comment Review
→ Atlantis Apply
→ AWS Infrastructure Update
```

### 5. 운영 점검 흐름

```text
Bastion / Ops Server
→ kubectl / AWS CLI
→ EKS Node, Pod, Service, Ingress 상태 확인
→ ALB TargetGroup Health 확인
→ Markdown Report 생성
```

## 핵심 기술 스택

| 영역 | 기술 |
|---|---|
| Cloud | AWS |
| Container Orchestration | Amazon EKS, Kubernetes |
| Network | VPC, Public/Private Subnet, NAT Gateway, ALB, Route53 |
| Database | Amazon RDS / Aurora 예정 |
| IaC | Terraform, S3 Backend |
| GitOps | ArgoCD, Kustomize |
| CI/CD | GitHub Actions, Amazon ECR |
| Secret Management | AWS Secrets Manager, External Secrets Operator |
| Authentication / Authorization | IAM, IRSA |
| Monitoring | Prometheus, Grafana, Alertmanager |
| Logging | Loki, Alloy |
| Alerting | CloudWatch Alarm, SNS, Lambda, Microsoft Teams Webhook |
| Ops Automation | Bastion, Ansible, Shell Script |
| Terraform Automation | Atlantis |
| Application | Spring Boot, Docker |

## 주요 검증 결과

### 1. EKS 애플리케이션 배포 검증

EKS 클러스터에 애플리케이션을 배포하고, ALB Ingress를 통해 외부 접근이 가능한 것을 확인했습니다.

검증 항목:

```text
- Deployment Pod Running
- Service 정상 연결
- Ingress ALB 생성
- /actuator/health 응답 확인
```

### 2. Secret 분리 검증

애플리케이션 Secret을 Git과 Kubernetes manifest에서 분리하고, AWS Secrets Manager와 External Secrets Operator를 통해 Kubernetes Secret으로 동기화했습니다.

검증 항목:

```text
- AWS Secrets Manager Secret 생성
- ExternalSecret 동기화
- Kubernetes Secret 생성 확인
- Pod에서 Secret 환경 변수 참조
```

### 3. IRSA 권한 검증

Pod가 AWS 리소스에 접근할 때 Access Key를 사용하지 않고, ServiceAccount와 IAM Role을 연결하는 IRSA 방식을 적용했습니다.

검증 항목:

```text
- ServiceAccount annotation 확인
- IAM Role trust policy 확인
- Pod 기준 AWS 권한 분리
```

### 4. GitOps 배포 검증

GitHub Actions에서 이미지를 빌드하고 ECR에 push한 뒤, Kubernetes manifest의 image tag를 갱신하여 ArgoCD가 변경 사항을 동기화하도록 구성했습니다.

검증 항목:

```text
- GitHub Actions build 성공
- ECR image push 확인
- Kustomize image tag 변경
- ArgoCD sync 확인
- EKS Deployment rollout 확인
```

### 5. 모니터링 구성 검증

기존 프로젝트에서도 Prometheus와 Grafana 기반 모니터링 구조를 사용했습니다. 이번 고도화에서는 이를 Day-2 운영 관점에서 재정리하고, 애플리케이션 메트릭 수집, PrometheusRule, Alertmanager 알림 규칙, 운영 Runbook을 보완했습니다.

검증 항목:

```text
- 기존 Prometheus/Grafana 모니터링 구조 재정리
- kube-prometheus-stack 구성 확인
- 애플리케이션 메트릭 endpoint 확인
- ServiceMonitor 적용
- Prometheus target 확인
- Grafana 접속 확인
- PrometheusRule 적용
- Alertmanager 연계 구조 확인
```

### 6. 로그 수집 구조 검증

기존 프로젝트에서도 Loki와 Promtail 기반 로그 수집 구조를 사용했습니다. 이번 고도화에서는 이를 Day-2 운영 관점에서 재정리하고, Loki와 Alloy 기반 Kubernetes 로그 수집 구조 및 운영 문서를 보완했습니다.

검증 항목:

```text
- Loki 설치
- Alloy 설치
- Kubernetes Pod 로그 수집 구조 확인
- Grafana datasource 연동 구조 문서화
```

### 7. Teams 장애 알림 검증

ALB TargetGroup의 UnhealthyHostCount를 기준으로 CloudWatch Alarm을 구성하고, SNS와 Lambda를 통해 Microsoft Teams로 알림이 전달되는 것을 검증했습니다.

검증 항목:

```text
- Teams Webhook Secret 생성
- Lambda Forwarder 배포
- SNS Topic 연동
- CloudWatch Alarm 생성
- TargetGroup unhealthy 상황 재현
- Teams 알림 수신 확인
```

### 8. Bastion 운영 점검 자동화 검증

Bastion/Ops Server에서 EKS와 ALB TargetGroup 상태를 점검하는 스크립트를 작성하고, Markdown 형식의 운영 리포트를 생성했습니다.

검증 항목:

```text
- EKS Node 상태 확인
- Pod 상태 확인
- Ingress 상태 확인
- ALB TargetGroup health 확인
- Markdown report 생성
```

### 9. Atlantis 기반 Terraform 자동화 검증

Terraform 변경을 로컬에서 직접 실행하지 않고, GitHub PR과 Atlantis를 통해 plan/apply하는 구조를 구성했습니다.

검증 항목:

```text
- GitHub Webhook 연동
- Bastion Atlantis 실행
- S3 backend 접근
- Bastion tfvars 주입
- Atlantis plan 성공
- Atlantis apply 성공
- CloudWatch Alarm dimension drift 반영
```

최종적으로 다음 변경을 Atlantis apply로 반영했습니다.

```text
Plan: 0 to add, 2 to change, 0 to destroy
```

변경 내용은 ALB와 TargetGroup 재생성에 따른 CloudWatch Alarm dimension 업데이트였습니다.

## 운영 자동화 문서

상세 운영 절차와 장애 대응 내용은 아래 문서에 정리했습니다.

| 문서 | 설명 |
|---|---|
| [Day-2 Operations Automation Summary](./docs/improvements/day2-ops-automation-summary.md) | 전체 Day-2 운영 자동화 개선 요약 |
| [Atlantis Terraform Automation Runbook](./docs/runbooks/atlantis-terraform-automation.md) | Atlantis 기반 Terraform plan/apply 운영 절차 |
| [Teams Alerting Runbook](./docs/runbooks/teams-alerting.md) | CloudWatch-SNS-Lambda-Teams 장애 알림 구성 및 검증 |
| [Loki Logging Runbook](./docs/runbooks/loki-logging.md) | Loki/Alloy 기반 로그 수집 구조 |
| [Application Metrics Monitoring](./docs/runbooks/application-metrics-monitoring.md) | 애플리케이션 메트릭 수집 및 모니터링 구성 |
| [Prometheus Alert Rules](./docs/runbooks/prometheus-alert-rules.md) | PrometheusRule 기반 알림 규칙 구성 |
| [ArgoCD GitOps Deployment](./docs/runbooks/argocd-gitops-deployment.md) | ArgoCD 기반 GitOps 배포 구성 |
| [Bastion Ops Server](./docs/runbooks/bastion-ops-server.md) | Bastion/Ops Server 구성 및 운영 도구 설치 |

## 비용 절감을 위한 dev-up/dev-down 운영 방식

이 프로젝트는 개인 학습 및 포트폴리오 목적의 AWS 환경이므로, 비용을 줄이기 위해 dev 환경을 상시 유지하지 않고 필요할 때만 올리는 방식으로 운영합니다.

기본 운영 방식:

```text
작업 시작 전 dev-up
→ EKS / 애플리케이션 / 운영 도구 검증
→ 모니터링 및 알림 테스트
→ 결과 기록
→ 작업 종료 후 dev-down
```

관련 스크립트:

```text
scripts/dev-up.sh
scripts/dev-down.sh
```

이 방식을 통해 다음 효과를 기대할 수 있습니다.

```text
- EKS, NAT Gateway, ALB, RDS 등 주요 비용 리소스의 불필요한 상시 운영 방지
- 필요한 검증 시점에만 dev 환경 구동
- 실습/포트폴리오 목적의 AWS 비용 최소화
- 반복 검증 가능한 환경 구성 유지
```

## 현재 진행 상태

| Phase | 내용 | 상태 |
|---|---|---|
| Phase 0 | 보안 정리, Secret 분리 준비 | 완료 |
| Phase 1 | Kubernetes manifest 정리 | 완료 |
| Phase 2 | Secrets Manager, External Secrets, IRSA | 완료 |
| Phase 3 | Terraform dev 환경 구성 | 완료 |
| Phase 4 | GitOps 배포 구성 | 완료 |
| Phase 5 | Bastion/Ops Server, Ansible | 완료 |
| Phase 6 | 운영 점검 스크립트 | 완료 |
| Phase 7 | Observability 구성 | 완료 |
| Phase 8 | Teams 장애 알림 | 완료 |
| Phase 9 | Atlantis 기반 Terraform PR 자동화 | 완료 |
| Phase 10 | prod/dr Terraform + Aurora DR | 예정 |
| Phase 11 | Karpenter 비용 최적화 | 예정 |

## 향후 개선 계획

### Phase 10. prod/dr Terraform + Aurora DR

```text
- prod/dr 환경 구성
- Aurora DR 검증
- Route53 failover 검증
- RTO/RPO 기록
```

### Phase 11. Karpenter 비용 최적화

```text
- NodePool 분리
- Spot interruption 대응
- idle node 정리
- 비용 최적화 문서화
```

## 포트폴리오 요약

이 프로젝트에서는 EKS 기반 애플리케이션 배포 이후 운영 단계에서 필요한 자동화와 변경 관리 체계를 구성했습니다.

특히 Secret 관리, IRSA 권한 분리, GitOps 배포, 기존 모니터링/로그 수집 구조의 운영 관점 재정리, 장애 알림, 운영 점검 스크립트, Atlantis 기반 Terraform PR 자동화를 단계적으로 적용했습니다.

이를 통해 단순한 인프라 구축을 넘어, 운영 환경에서 중요한 변경 이력 관리, 장애 감지, 알림, 점검 자동화, 비용 절감 운영 방식을 검증했습니다.
