#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-yerim-admin}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
export AWS_PROFILE AWS_REGION

PROJECT_NAME="olivesafety-day2-ops"
ENV="dev"
CLUSTER_NAME="${PROJECT_NAME}-${ENV}-eks"
ECR_REPOSITORY_NAME="${PROJECT_NAME}-${ENV}/olivesafety-api"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/envs/dev"

echo "==> [0/7] Update kubeconfig if cluster exists"
if aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" >/dev/null 2>&1; then

  aws eks update-kubeconfig \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" || true

  kubectl config current-context || true
else
  echo "EKS cluster does not exist or is not reachable: ${CLUSTER_NAME}"
fi

echo "==> [1/7] Capture current ALB DNS"
ALB_DNS="$(kubectl get ingress olivesafety-api -n olivesafety \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

if [[ -n "${ALB_DNS}" ]]; then
  echo "Current ALB DNS: ${ALB_DNS}"
else
  echo "No ALB DNS found"
fi

echo "==> [2/7] Delete ArgoCD Application to stop self-healing"
kubectl delete application olivesafety-dev \
  -n argocd \
  --ignore-not-found=true || true

echo "==> [3/7] Delete Kubernetes application resources"
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

if [[ -n "${ALB_DNS}" ]]; then
  echo "Waiting for AWS ALB deletion: ${ALB_DNS}"

  for i in {1..60}; do
    ALB_STATE="$(aws elbv2 describe-load-balancers \
      --region "${AWS_REGION}" \
      --profile "${AWS_PROFILE}" \
      --query "LoadBalancers[?DNSName=='${ALB_DNS}'].DNSName | [0]" \
      --output text 2>/dev/null || true)"

    if [[ -z "${ALB_STATE}" || "${ALB_STATE}" == "None" ]]; then
      echo "ALB deleted."
      break
    fi

    echo "Waiting for ALB deletion... ${i}/60"
    sleep 10
  done
fi

echo "==> [4/7] Uninstall Helm releases"
helm uninstall kube-prometheus-stack -n monitoring >/dev/null 2>&1 || true
helm uninstall loki -n monitoring >/dev/null 2>&1 || true
helm uninstall alloy -n monitoring >/dev/null 2>&1 || true
helm uninstall external-secrets -n external-secrets >/dev/null 2>&1 || true
helm uninstall aws-load-balancer-controller -n kube-system >/dev/null 2>&1 || true

echo "==> [5/7] Delete ECR images if repository exists"
if aws ecr describe-repositories \
  --repository-names "${ECR_REPOSITORY_NAME}" \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" >/dev/null 2>&1; then

  aws ecr list-images \
    --repository-name "${ECR_REPOSITORY_NAME}" \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" \
    --query 'imageIds[*]' \
    --output json > /tmp/olivesafety-ecr-images.json

  if [[ "$(cat /tmp/olivesafety-ecr-images.json)" != "[]" ]]; then
    aws ecr batch-delete-image \
      --repository-name "${ECR_REPOSITORY_NAME}" \
      --region "${AWS_REGION}" \
      --profile "${AWS_PROFILE}" \
      --image-ids file:///tmp/olivesafety-ecr-images.json
  else
    echo "No ECR images to delete"
  fi
else
  echo "ECR repository does not exist"
fi

echo "==> [6/7] Terraform destroy"
cd "${TF_DIR}"
terraform init
terraform destroy -auto-approve

echo "==> [7/7] Cleanup generated files and force delete scheduled Secrets Manager secrets"
rm -f "${TF_DIR}/alerting.auto.tfvars"

aws secretsmanager delete-secret \
  --secret-id "olivesafety/dev/api" \
  --force-delete-without-recovery \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" >/dev/null 2>&1 || true

aws secretsmanager delete-secret \
  --secret-id "olivesafety/dev/teams-webhook" \
  --force-delete-without-recovery \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" >/dev/null 2>&1 || true

echo "==> Done"
