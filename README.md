
## Day-2 Operations Automation

이 프로젝트는 AWS EKS 기반 애플리케이션 배포 구조를 운영 관점에서 고도화한 Day-2 Ops 프로젝트입니다.

기존 인프라 구축 중심 구성에서 나아가, 실제 운영 단계에서 필요한 보안, 배포 자동화, 모니터링, 장애 알림, 운영 점검, Terraform 변경 관리 흐름을 개선했습니다.

주요 개선 내용은 다음과 같습니다.

- AWS Secrets Manager와 External Secrets를 이용한 Secret 분리
- IRSA 기반 Pod 권한 관리
- GitHub Actions와 ArgoCD 기반 GitOps 배포
- Prometheus, Grafana, Alertmanager 기반 모니터링
- Loki, Alloy 기반 Kubernetes 로그 수집 구조
- CloudWatch Alarm, SNS, Lambda, Microsoft Teams 연동 장애 알림
- Bastion/Ops Server 기반 운영 점검 스크립트
- Atlantis 기반 Pull Request 단위 Terraform plan/apply 자동화

자세한 개선 내용은 아래 문서에 정리했습니다.

- [Day-2 Operations Automation Summary](./docs/improvements/day2-ops-automation-summary.md)
- [Atlantis Terraform Automation Runbook](./docs/runbooks/atlantis-terraform-automation.md)
