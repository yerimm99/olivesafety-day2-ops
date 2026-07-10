#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-yerim-admin}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
PROJECT_NAME="olivesafety-day2-ops"
ENV="dev"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/envs/dev"

echo "==> [1/4] Delete Kubernetes resources"
kubectl delete -k "${ROOT_DIR}/k8s/overlays/dev" --ignore-not-found=true || true

echo "==> [2/4] Delete ECR images if repository exists"
if aws ecr describe-repositories \
  --repository-names "${PROJECT_NAME}-${ENV}/olivesafety-api" \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" >/dev/null 2>&1; then

  aws ecr list-images \
    --repository-name "${PROJECT_NAME}-${ENV}/olivesafety-api" \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" \
    --query 'imageIds[*]' \
    --output json > /tmp/olivesafety-ecr-images.json

  if [[ "$(cat /tmp/olivesafety-ecr-images.json)" != "[]" ]]; then
    aws ecr batch-delete-image \
      --repository-name "${PROJECT_NAME}-${ENV}/olivesafety-api" \
      --region "${AWS_REGION}" \
      --profile "${AWS_PROFILE}" \
      --image-ids file:///tmp/olivesafety-ecr-images.json
  else
    echo "No ECR images to delete"
  fi
else
  echo "ECR repository does not exist"
fi

echo "==> [3/4] Terraform destroy"
cd "${TF_DIR}"
terraform destroy -auto-approve

echo "==> [4/4] Force delete scheduled Secrets Manager secret if needed"
aws secretsmanager delete-secret \
  --secret-id "olivesafety/dev/api" \
  --force-delete-without-recovery \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" >/dev/null 2>&1 || true

echo "==> Done"
