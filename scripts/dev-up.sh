#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-yerim-admin}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
PROJECT_NAME="olivesafety-day2-ops"
ENV="dev"
CLUSTER_NAME="${PROJECT_NAME}-${ENV}-eks"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"

ALB_ROLE_NAME="${PROJECT_NAME}-${ENV}-aws-load-balancer-controller-role"
EXTERNAL_SECRETS_ROLE_NAME="${PROJECT_NAME}-${ENV}-external-secrets-role"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/envs/dev"

echo "==> [1/8] Terraform apply"
cd "${TF_DIR}"
terraform init
terraform apply -auto-approve

echo "==> [2/8] Update kubeconfig"
aws eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}"

echo "==> [3/8] Get Terraform outputs"
ECR_URL="$(terraform output -raw ecr_repository_url)"
API_ROLE_ARN="$(terraform output -raw api_irsa_role_arn)"
SQS_QUEUE_URL="$(terraform output -raw sqs_queue_url)"
SNS_TOPIC_ARN="$(terraform output -raw sns_topic_arn)"

echo "ECR_URL=${ECR_URL}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "API_ROLE_ARN=${API_ROLE_ARN}"
echo "SQS_QUEUE_URL=${SQS_QUEUE_URL}"
echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}"

cd "${ROOT_DIR}"

echo "==> [4/8] Install AWS Load Balancer Controller"
ALB_ROLE_ARN="$(aws iam get-role \
  --role-name "${ALB_ROLE_NAME}" \
  --profile "${AWS_PROFILE}" \
  --query 'Role.Arn' \
  --output text)"

VPC_ID="$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)"

helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set region="${AWS_REGION}" \
  --set vpcId="${VPC_ID}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ALB_ROLE_ARN}" \
  --wait \
  --timeout 5m

echo "Waiting for AWS Load Balancer Controller to be ready..."
kubectl rollout status deployment/aws-load-balancer-controller \
  -n kube-system \
  --timeout=300s

echo "Waiting for AWS Load Balancer webhook endpoints..."
WEBHOOK_READY=false

for i in {1..30}; do
  ENDPOINTS="$(kubectl get endpoints aws-load-balancer-webhook-service \
    -n kube-system \
    -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"

  if [[ -n "${ENDPOINTS}" ]]; then
    echo "AWS Load Balancer webhook endpoints ready: ${ENDPOINTS}"
    WEBHOOK_READY=true
    break
  fi

  echo "Waiting for webhook endpoints... ${i}/30"
  sleep 5
done

if [[ "${WEBHOOK_READY}" != "true" ]]; then
  echo "ERROR: AWS Load Balancer webhook endpoints are not ready."
  kubectl get pods -n kube-system | grep aws-load-balancer-controller || true
  kubectl describe deployment aws-load-balancer-controller -n kube-system || true
  exit 1
fi

echo "==> [5/8] Install External Secrets Operator"
EXTERNAL_SECRETS_ROLE_ARN="$(aws iam get-role \
  --role-name "${EXTERNAL_SECRETS_ROLE_NAME}" \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" \
  --query 'Role.Arn' \
  --output text)"

helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-secrets \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${EXTERNAL_SECRETS_ROLE_ARN}"

echo "==> [6/8] Build and push app image"
aws ecr get-login-password \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" \
  | docker login --username AWS --password-stdin "$(echo "${ECR_URL}" | cut -d/ -f1)"

docker buildx build \
  --platform linux/amd64 \
  -t "${ECR_URL}:${IMAGE_TAG}" \
  "${ROOT_DIR}/app" \
  --push

echo "==> [7/8] Update app IRSA patch and apply Kubernetes manifests"
cat > "${ROOT_DIR}/k8s/overlays/dev/serviceaccount-irsa-patch.yaml" <<PATCH
apiVersion: v1
kind: ServiceAccount
metadata:
  name: olivesafety-api-sa
  namespace: olivesafety
  annotations:
    eks.amazonaws.com/role-arn: ${API_ROLE_ARN}
PATCH

python3 - <<PY2
from pathlib import Path

p = Path("${ROOT_DIR}/k8s/overlays/dev/kustomization.yaml")
s = p.read_text()

lines = s.splitlines()
out = []
in_images = False
target_image = False

for line in lines:
    stripped = line.strip()

    if stripped == "images:":
        in_images = True
        out.append(line)
        continue

    if in_images and stripped.startswith("- name:"):
        target_image = stripped == "- name: olivesafety-api"
        out.append(line)
        continue

    if in_images and target_image and stripped.startswith("newName:"):
        out.append(f"    newName: ${ECR_URL}")
        continue

    if in_images and target_image and stripped.startswith("newTag:"):
        out.append(f"    newTag: ${IMAGE_TAG}")
        target_image = False
        continue

    out.append(line)

p.write_text("\n".join(out) + "\n")
PY2

kubectl apply -k "${ROOT_DIR}/k8s/overlays/dev"

echo "==> [8/8] Restart and verify deployment"
kubectl rollout restart deployment/olivesafety-api -n olivesafety
kubectl rollout status deployment/olivesafety-api -n olivesafety --timeout=300s

APP_ALB_DNS="$(kubectl get ingress olivesafety-api -n olivesafety -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

echo "Waiting for ALB DNS..."
for i in {1..30}; do
  APP_ALB_DNS="$(kubectl get ingress olivesafety-api -n olivesafety -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || true)"
  if [[ -n "${APP_ALB_DNS}" ]]; then
    break
  fi
  sleep 10
done

echo "ALB DNS: ${APP_ALB_DNS}"

if [[ -n "${APP_ALB_DNS}" ]]; then
  echo "Health check:"
  curl -s "http://${APP_ALB_DNS}/actuator/health" || true
  echo
fi

echo "==> Done"
