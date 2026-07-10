# Runbook: Terraform Destroy Cleanup

## 1. 상황

개인 AWS 계정 비용 절감을 위해 dev 환경을 삭제하는 과정에서 `terraform destroy`가 실패한다.

대표적인 오류는 다음과 같다.

```text
ECR Repository not empty
RepositoryNotEmptyException
```

또는 다음 apply 시 Secrets Manager 오류가 발생한다.

```text
You can't create this secret because a secret with this name is already scheduled for deletion
```

## 2. 영향도

리소스가 완전히 삭제되지 않아 비용이 계속 발생할 수 있다.

또는 다음 dev 환경 생성 시 같은 이름의 Secret을 생성하지 못해 Terraform apply가 실패할 수 있다.

## 3. 주요 원인

1. ECR Repository 안에 image가 남아 있음
2. Secrets Manager Secret이 즉시 삭제되지 않고 삭제 예약 상태가 됨
3. ALB Ingress가 삭제되기 전에 EKS/VPC 삭제를 시도함
4. AWS Load Balancer Controller가 만든 ALB, Target Group, Security Group이 아직 정리 중임

## 4. 권장 삭제 순서

1. Kubernetes 리소스 삭제
2. ECR image 삭제
3. Terraform destroy
4. Secrets Manager 강제 삭제
5. 주요 리소스 삭제 확인

## 5. 복구 절차

Kubernetes 리소스 삭제:

```bash
kubectl delete -k k8s/overlays/dev --ignore-not-found=true
```

ECR image 삭제:

```bash
aws ecr list-images \
  --repository-name olivesafety-day2-ops-dev/olivesafety-api \
  --region ap-northeast-2 \
  --profile yerim-admin \
  --query 'imageIds[*]' \
  --output json > /tmp/olivesafety-ecr-images.json
```

이미지가 존재하면 삭제:

```bash
aws ecr batch-delete-image \
  --repository-name olivesafety-day2-ops-dev/olivesafety-api \
  --region ap-northeast-2 \
  --profile yerim-admin \
  --image-ids file:///tmp/olivesafety-ecr-images.json
```

Terraform destroy:

```bash
cd terraform/envs/dev
terraform destroy -auto-approve
cd ../../..
```

Secrets Manager 강제 삭제:

```bash
aws secretsmanager delete-secret \
  --secret-id "olivesafety/dev/api" \
  --force-delete-without-recovery \
  --region ap-northeast-2 \
  --profile yerim-admin
```

## 6. 삭제 확인

Terraform state 확인:

```bash
cd terraform/envs/dev
terraform state list
cd ../../..
```

출력이 없으면 Terraform 관리 리소스는 삭제된 상태다.

EKS 확인:

```bash
aws eks describe-cluster \
  --name olivesafety-day2-ops-dev-eks \
  --region ap-northeast-2 \
  --profile yerim-admin
```

`ResourceNotFoundException`이 나오면 정상 삭제된 것이다.

ALB 확인:

```bash
aws elbv2 describe-load-balancers \
  --region ap-northeast-2 \
  --profile yerim-admin \
  --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-')].[LoadBalancerName,State.Code]" \
  --output table
```

결과가 없으면 ALB가 삭제된 상태다.

RDS 확인:

```bash
aws rds describe-db-instances \
  --db-instance-identifier olivesafety-day2-ops-dev-mysql \
  --region ap-northeast-2 \
  --profile yerim-admin
```

`DBInstanceNotFound`가 나오면 정상 삭제된 것이다.

Redis 확인:

```bash
aws elasticache describe-replication-groups \
  --replication-group-id olivesafety-day2-ops-dev-redis \
  --region ap-northeast-2 \
  --profile yerim-admin
```

`ReplicationGroupNotFoundFault`가 나오면 정상 삭제된 것이다.

## 7. 재발 방지

- dev 환경 ECR에는 `force_delete = true` 적용을 고려한다.
- dev Secret은 `recovery_window_in_days = 0` 설정을 고려한다.
- `scripts/dev-down.sh`에서 ECR image 삭제와 Secrets Manager force delete를 자동화한다.
- Ingress 삭제 후 ALB가 완전히 삭제될 때까지 잠시 대기한다.
