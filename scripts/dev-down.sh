#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-yerim-admin}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
PROJECT_NAME="olivesafety-day2-ops"
ENV="dev"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/envs/dev"

echo "==> [1/5] Delete ArgoCD Application to stop self-healing"
kubectl delete application olivesafety-dev \
  -n argocd \
  --ignore-not-found=true || true

echo "==> [2/5] Delete Kubernetes application resources"
kubectl delete -k "${ROOT_DIR}/k8s/overlays/dev" --ignore-not-found=true || true

echo "Waiting for Ingress deletion..."
for i in {1..30}; do
  if ! kubectl get ingress olivesafety-api -n olivesafety >/dev/null 2>&1; then
    echo "Ingress deleted."
    break
  fi

  echo "Waiting for Ingress deletion... ${i}/30"
  sleep 10
done

echo "==> [3/5] Delete ECR images if repository exists"
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

echo "==> [4/5] Terraform destroy"
cd "${TF_DIR}"
terraform destroy -auto-approve

echo "==> [5/5] Force delete scheduled Secrets Manager secret if needed"
aws secretsmanager delete-secret \
  --secret-id "olivesafety/dev/api" \
  --force-delete-without-recovery \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" >/dev/null 2>&1 || true

echo "==> Done"
