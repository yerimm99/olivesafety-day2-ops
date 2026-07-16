# Runbooks

이 디렉터리는 `olivesafety-day2-ops` 프로젝트를 AWS EKS 환경에서 운영하면서 발생할 수 있는 주요 장애 상황과 대응 절차를 정리합니다.

각 Runbook은 다음 기준으로 작성합니다.

- 증상
- 영향도
- 주요 원인
- 확인 명령어
- 복구 절차
- 재발 방지 방법

## Runbook 목록

| 문서 | 상황 |
|---|---|
| imagepullbackoff.md | Pod가 ECR 이미지를 가져오지 못하는 경우 |
| actuator-health-401.md | readiness/liveness probe가 401로 실패하는 경우 |
| external-secrets-crd-missing.md | ExternalSecret / ClusterSecretStore 리소스가 적용되지 않는 경우 |
| irsa-credentials-error.md | Pod가 AWS credentials를 가져오지 못하는 경우 |
| sqs-queue-not-found.md | SQS polling 시 QueueDoesNotExist 오류가 발생하는 경우 |
| terraform-destroy-cleanup.md | terraform destroy 시 ECR/Secrets Manager 리소스 삭제가 실패하는 경우 |

- [Atlantis Terraform Automation](./atlantis-terraform-automation.md)
