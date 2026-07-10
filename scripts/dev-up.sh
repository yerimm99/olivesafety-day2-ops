#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-yerim-admin}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
PROJECT_NAME="olivesafety-day2-ops"
ENV="dev"
CLUSTER_NAME="${PROJECT_NAME}-${ENV}-eks"

ALB_ROLE_NAME="${PROJECT_NAME}-${ENV}-aws-load-balancer-controller-role"
EXTERNAL_SECRETS_ROLE_NAME="${PROJECT_NAME}-${ENV}-external-secrets-role"
ECR_REPOSITORY_NAME="${PROJECT_NAME}-${ENV}/olivesafety-api"

BUILD_BOOTSTRAP_IMAGE="${BUILD_BOOTSTRAP_IMAGE:-true}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/envs/dev"
KUSTOMIZATION_PATH="${ROOT_DIR}/k8s/overlays/dev/kustomization.yaml"
ARGOCD_APP_PATH="${ROOT_DIR}/argocd/apps/olivesafety-dev.yaml"

get_kustomize_image_tag() {
  python3 - <<PY
from pathlib import Path

path = Path("${KUSTOMIZATION_PATH}")
lines = path.read_text().splitlines()

in_images = False
target = False

for line in lines:
    stripped = line.strip()

    if stripped == "images:":
        in_images = True
        continue

    if in_images and stripped.startswith("- name:"):
        target = stripped == "- name: olivesafety-api"
        continue

    if in_images and target and stripped.startswith("newTag:"):
        print(stripped.split(":", 1)[1].strip())
        break
PY
}

get_kustomize_image_name() {
  python3 - <<PY
from pathlib import Path

path = Path("${KUSTOMIZATION_PATH}")
lines = path.read_text().splitlines()

in_images = False
target = False

for line in lines:
    stripped = line.strip()

    if stripped == "images:":
        in_images = True
        continue

    if in_images and stripped.startswith("- name:"):
        target = stripped == "- name: olivesafety-api"
        continue

    if in_images and target and stripped.startswith("newName:"):
        print(stripped.split(":", 1)[1].strip())
        break
PY
}

echo "==> [1/9] Terraform apply"
cd "${TF_DIR}"
terraform init
terraform apply -auto-approve

echo "==> [2/9] Update kubeconfig"
aws eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}"

echo "==> [3/9] Get Terraform outputs"
ECR_URL="$(terraform output -raw ecr_repository_url)"
API_ROLE_ARN="$(terraform output -raw api_irsa_role_arn)"
SQS_QUEUE_URL="$(terraform output -raw sqs_queue_url)"
SNS_TOPIC_ARN="$(terraform output -raw sns_topic_arn)"

IMAGE_TAG="${IMAGE_TAG:-$(get_kustomize_image_tag)}"
MANIFEST_IMAGE_NAME="$(get_kustomize_image_name)"

echo "ECR_URL=${ECR_URL}"
echo "MANIFEST_IMAGE_NAME=${MANIFEST_IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "API_ROLE_ARN=${API_ROLE_ARN}"
echo "SQS_QUEUE_URL=${SQS_QUEUE_URL}"
echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}"

if [[ -z "${IMAGE_TAG}" ]]; then
  echo "ERROR: Failed to read image newTag from ${KUSTOMIZATION_PATH}"
  exit 1
fi

if [[ "${MANIFEST_IMAGE_NAME}" != "${ECR_URL}" ]]; then
  echo "WARNING: kustomization newName does not match Terraform ECR URL."
  echo "  manifest: ${MANIFEST_IMAGE_NAME}"
  echo "  terraform: ${ECR_URL}"
  echo "ArgoCD will deploy the image defined in Git."
fi

cd "${ROOT_DIR}"

echo "==> [4/9] Install AWS Load Balancer Controller"
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

echo "==> [5/9] Install External Secrets Operator"
EXTERNAL_SECRETS_ROLE_ARN="$(aws iam get-role \
  --role-name "${EXTERNAL_SECRETS_ROLE_NAME}" \
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
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${EXTERNAL_SECRETS_ROLE_ARN}" \
  --wait \
  --timeout 5m

kubectl rollout status deployment/external-secrets \
  -n external-secrets \
  --timeout=300s

kubectl wait --for condition=Established \
  crd/externalsecrets.external-secrets.io \
  --timeout=120s

kubectl wait --for condition=Established \
  crd/clustersecretstores.external-secrets.io \
  --timeout=120s

echo "==> [6/9] Build and push bootstrap image if missing"
if [[ "${BUILD_BOOTSTRAP_IMAGE}" == "true" ]]; then
  if aws ecr describe-images \
    --repository-name "${ECR_REPOSITORY_NAME}" \
    --image-ids imageTag="${IMAGE_TAG}" \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" >/dev/null 2>&1; then

    echo "Image already exists in ECR: ${ECR_URL}:${IMAGE_TAG}"
  else
    echo "Image does not exist in ECR. Building bootstrap image: ${ECR_URL}:${IMAGE_TAG}"

    aws ecr get-login-password \
      --region "${AWS_REGION}" \
      --profile "${AWS_PROFILE}" \
      | docker login --username AWS --password-stdin "$(echo "${ECR_URL}" | cut -d/ -f1)"

    docker buildx inspect >/dev/null 2>&1 || docker buildx create --use

    docker buildx build \
      --platform linux/amd64 \
      -t "${ECR_URL}:${IMAGE_TAG}" \
      "${ROOT_DIR}/app" \
      --push
  fi
else
  echo "Skipping bootstrap image build. BUILD_BOOTSTRAP_IMAGE=false"
fi

echo "==> [7/9] Install ArgoCD"
kubectl create namespace argocd \
  --dry-run=client \
  -o yaml | kubectl apply -f -

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for condition=Established \
  crd/applications.argoproj.io \
  --timeout=120s

kubectl rollout status deployment/argocd-repo-server \
  -n argocd \
  --timeout=300s

kubectl rollout status deployment/argocd-server \
  -n argocd \
  --timeout=300s

kubectl rollout status statefulset/argocd-application-controller \
  -n argocd \
  --timeout=300s

echo "==> [8/9] Apply ArgoCD Application"
kubectl apply -f "${ARGOCD_APP_PATH}"

kubectl annotate application olivesafety-dev \
  -n argocd \
  argocd.argoproj.io/refresh=hard \
  --overwrite

echo "Waiting for ArgoCD application to become Synced / Healthy..."
ARGOCD_READY=false

for i in {1..40}; do
  SYNC_STATUS="$(kubectl get application olivesafety-dev -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  HEALTH_STATUS="$(kubectl get application olivesafety-dev -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)"

  echo "ArgoCD status: ${SYNC_STATUS:-Unknown} / ${HEALTH_STATUS:-Unknown} (${i}/40)"

  if [[ "${SYNC_STATUS}" == "Synced" && "${HEALTH_STATUS}" == "Healthy" ]]; then
    ARGOCD_READY=true
    break
  fi

  sleep 15
done

if [[ "${ARGOCD_READY}" != "true" ]]; then
  echo "ERROR: ArgoCD application did not become Synced / Healthy."

  echo "Application conditions:"
  kubectl get application olivesafety-dev -n argocd \
    -o jsonpath='{range .status.conditions[*]}{.type}{" | "}{.message}{"\n"}{end}' || true

  echo "Application resources:"
  kubectl get application olivesafety-dev -n argocd \
    -o jsonpath='{range .status.resources[*]}{.kind}{" / "}{.name}{" / "}{.status}{" / "}{.health.status}{"\n"}{end}' || true

  echo "Pods in olivesafety namespace:"
  kubectl get pods -n olivesafety || true

  exit 1
fi

echo "==> [9/9] Verify application endpoint"
APP_ALB_DNS=""

echo "Waiting for ALB DNS..."
for i in {1..30}; do
  APP_ALB_DNS="$(kubectl get ingress olivesafety-api -n olivesafety -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

  if [[ -n "${APP_ALB_DNS}" ]]; then
    break
  fi

  echo "Waiting for ALB DNS... ${i}/30"
  sleep 10
done

echo "ALB DNS: ${APP_ALB_DNS}"

if [[ -n "${APP_ALB_DNS}" ]]; then
  echo "Health check:"
  curl -s "http://${APP_ALB_DNS}/actuator/health" || true
  echo
fi

echo "==> Done"
