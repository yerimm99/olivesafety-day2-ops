# Day-2 Operations Automation Summary

## 개요

이 프로젝트는 단순히 EKS 기반 애플리케이션을 배포하는 데서 끝나지 않고, 운영 단계에서 필요한 보안, 배포, 모니터링, 장애 알림, Terraform 변경 관리 흐름을 자동화하는 것을 목표로 한다.

기존 부트캠프 프로젝트가 서비스 배포와 대규모 트래픽 대응 구조에 초점을 두었다면, 이번 고도화에서는 실제 운영 환경에서 반복적으로 필요한 Day-2 운영 요소를 보완했다.

## 주요 개선 영역

| 영역 | 개선 내용 |
|---|---|
| 보안 | Secret을 Git 및 Kubernetes manifest에서 분리하고 AWS Secrets Manager + External Secrets 기반으로 관리 |
| 권한 | Pod가 AWS 리소스에 접근할 때 Access Key 대신 IRSA 기반 권한 사용 |
| 배포 | GitHub Actions와 ArgoCD를 이용해 이미지 빌드 후 GitOps 방식으로 배포 |
| 인프라 관리 | Terraform S3 backend와 state lock을 사용하여 원격 상태 관리 |
| 운영 서버 | Bastion/Ops Server를 구성하고 Ansible로 운영 도구 설치 자동화 |
| 헬스체크 | Bastion에서 EKS, ALB TargetGroup, Pod 상태를 점검하는 운영 점검 스크립트 작성 |
| 모니터링 | Prometheus, Grafana, Alertmanager 기반 메트릭 수집 및 알림 기반 구성 |
| 로그 | Loki와 Alloy를 이용한 Kubernetes 로그 수집 구조 구성 |
| 장애 알림 | CloudWatch Alarm → SNS → Lambda → Microsoft Teams 알림 연동 |
| Terraform 자동화 | Atlantis를 이용해 PR 기반 Terraform plan/apply 흐름 구성 |

## 운영 자동화 흐름

```text
Developer
→ GitHub Pull Request
→ Atlantis Webhook
→ Terraform Plan
→ PR Comment Review
→ Atlantis Apply
→ AWS Infrastructure Update
```

애플리케이션 배포 흐름은 다음과 같다.

```text
GitHub Push
→ GitHub Actions
→ Docker Image Build
→ ECR Push
→ Kubernetes Manifest Image Tag Update
→ ArgoCD Sync
→ EKS Deployment Update
```

장애 알림 흐름은 다음과 같다.

```text
ALB / TargetGroup Metric
→ CloudWatch Alarm
→ SNS Topic
→ Lambda Forwarder
→ Microsoft Teams Webhook
→ Teams Channel Notification
```

## Atlantis 기반 Terraform 운영 자동화

기존에는 로컬 환경에서 직접 Terraform 명령어를 실행했다.

```text
local terraform plan
local terraform apply
```

이 방식은 빠르게 작업할 수 있지만, 실제 운영 관점에서는 다음 한계가 있다.

```text
- 누가 어떤 변경을 적용했는지 추적하기 어려움
- Terraform 실행 위치가 개인 로컬 환경에 의존함
- PR 기반 변경 검토 흐름이 부족함
- remote state 접근 권한을 개인 계정에 의존할 수 있음
```

이를 개선하기 위해 Bastion/Ops Server에 Atlantis를 구성했다.

```text
GitHub PR
→ GitHub Webhook
→ Bastion Atlantis
→ Terraform plan
→ PR 댓글로 결과 확인
→ Atlantis apply
```

민감 변수는 Git에 올리지 않고 Bastion 내부의 tfvars 파일로 관리했다.

```text
/opt/atlantis/tfvars/dev.tfvars
/opt/atlantis/tfvars/alerting.tfvars
```

이를 통해 Git에는 코드와 설정 구조만 남기고, Secret이나 환경별 민감 값은 실행 환경에서 주입되도록 분리했다.

## 검증한 운영 시나리오

### 1. ALB Target Health 점검

Bastion에서 ALB TargetGroup 상태를 조회하는 스크립트를 작성하고, 현재 Target 상태를 Markdown 리포트로 저장했다.

이를 통해 EKS Pod, Service, Ingress, ALB TargetGroup 연결 상태를 한 번에 확인할 수 있도록 했다.

### 2. Teams 장애 알림

ALB TargetGroup의 UnhealthyHostCount를 기준으로 CloudWatch Alarm을 구성했다.

의도적으로 health check path를 잘못 설정하여 TargetGroup unhealthy 상태를 만들고, Teams 채널로 알림이 전달되는 것을 검증했다.

### 3. Terraform Drift 반영

dev 환경 재구성으로 ALB와 TargetGroup이 새로 생성되면서 CloudWatch Alarm dimension이 기존 리소스를 바라보는 drift가 발생했다.

Atlantis plan에서 다음 변경을 확인했다.

```text
Plan: 0 to add, 2 to change, 0 to destroy
```

이후 Atlantis apply를 통해 CloudWatch Alarm dimension을 현재 ALB/TargetGroup 기준으로 업데이트했다.

## TroubleShooting 경험

Atlantis 도입 과정에서 다음 이슈를 해결했다.

| 이슈 | 원인 | 해결 |
|---|---|---|
| S3 backend 403 | Bastion Role에 tfstate bucket 접근 권한 없음 | S3 backend prefix 접근 권한 추가 |
| Terraform module not found | 로컬 module이 Git에 커밋되지 않음 | 누락된 module directory 커밋 |
| required variable 누락 | 로컬 tfvars가 Atlantis 실행 환경에 없음 | Bastion tfvars 생성 후 atlantis.yaml에서 var-file 주입 |
| tfvars permission denied | Atlantis container 사용자와 파일 권한 불일치 | tfvars 파일 소유자/권한 수정 |
| YAML tab error | atlantis.yaml에 tab 문자 포함 | space 기반 YAML로 수정 |
| CloudWatch Alarm destroy 예정 | alerting.tfvars 미적용 | ALB/TG suffix tfvars 추가 |
| NodeGroup desired size drift | 수동으로 늘린 node 수가 Terraform 변수에 미반영 | Terraform 기준 desired size 수정 |

## 포트폴리오 요약 문장

AWS EKS 기반 서비스 인프라를 대상으로 Day-2 운영 자동화 고도화를 수행했습니다. 기존 배포 중심 구조에서 나아가 Secrets Manager와 IRSA 기반 보안 구성, ArgoCD 기반 GitOps 배포, Prometheus/Grafana 모니터링, CloudWatch-SNS-Lambda-Teams 장애 알림, Bastion 기반 운영 점검 스크립트, Atlantis 기반 PR 단위 Terraform plan/apply 자동화까지 구현했습니다. 이를 통해 단순 인프라 구축이 아닌 운영 단계에서 필요한 변경 관리, 장애 감지, 알림, 점검 자동화 흐름을 검증했습니다.

## 면접 설명용 요약

이 프로젝트에서는 EKS에 애플리케이션을 배포하는 것보다, 배포 이후 운영 과정에서 필요한 자동화와 변경 관리에 집중했습니다. Secret 관리, Pod 권한, GitOps 배포, 모니터링, 장애 알림, 운영 점검 스크립트, Terraform PR 자동화를 단계적으로 구성했습니다. 특히 Atlantis를 Bastion에 구성해 Terraform 변경을 로컬이 아닌 PR 기반으로 검토하고 적용하도록 개선했으며, 이 과정에서 S3 remote state 권한, tfvars 주입, AWS 조회 권한, CloudWatch Alarm drift 같은 실제 운영 이슈를 해결했습니다.
